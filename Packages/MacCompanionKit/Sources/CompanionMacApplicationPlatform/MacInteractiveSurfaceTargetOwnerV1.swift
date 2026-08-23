#if os(macOS)
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit

public enum MacInteractiveSurfaceTargetOwnerErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case bindingMismatch
    case transitionInProgress
}

/// The menu-process-only bridge between privacy-filtered opaque picker tokens
/// and live ScreenCaptureKit objects. The Agent can receive only sanitized
/// inventory and descriptors; the selected filter and global input geometry
/// remain here until the exact replacement command claims them once.
@available(macOS 14.0, *)
public actor MacInteractiveSurfaceTargetOwnerV1 {
    private struct Active {
        var descriptor: AdaptiveSurfaceDescriptor
        var lease: InteractiveExecutionLease?
        let physicalDisplayID: CGDirectDisplayID
        let desktopRotation: SurfaceRotation
        let catalog: ScreenCaptureKitOpaqueTargetCatalogV0
    }

    private let excludedBundleIdentifiers: Set<String>
    private let excludedProcessIdentifiers: Set<pid_t>
    private let identifier: @Sendable () -> UUID
    private var active: Active?
    private var pending: ScreenCaptureKitResolvedSurfaceV0?

    public init(
        excludedBundleIdentifiers: Set<String> = [
            "media.jenny.maccompanion",
        ],
        excludedProcessIdentifiers: Set<pid_t> = [getpid()],
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.excludedProcessIdentifiers = excludedProcessIdentifiers
        self.identifier = identifier
    }

    /// Binds the initial Desktop without ScreenCaptureKit enumeration. This is
    /// called by the same menu-side preparation that created the descriptor.
    public func bindInitialDesktop(
        command: LocalInteractiveInitialDesktopPreparationCommandV1,
        descriptor: AdaptiveSurfaceDescriptor,
        physicalDisplayID: CGDirectDisplayID
    ) throws {
        guard active == nil, pending == nil,
              physicalDisplayID != 0,
              descriptor.interactiveSessionID
                == command.interactiveSessionID,
              descriptor.authorizationEpoch == command.authorizationEpoch,
              descriptor.kind == .desktop,
              Set(descriptor.interactionClasses)
                == Set(command.interactionClasses) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        let catalog = try ScreenCaptureKitOpaqueTargetCatalogV0(
            interactiveSessionID: command.interactiveSessionID,
            authorizationEpoch: command.authorizationEpoch,
            selectedDisplayID: physicalDisplayID,
            excludedBundleIdentifiers: excludedBundleIdentifiers,
            excludedProcessIdentifiers: excludedProcessIdentifiers,
            tokenGenerator: identifier
        )
        active = Active(
            descriptor: descriptor,
            lease: nil,
            physicalDisplayID: physicalDisplayID,
            desktopRotation: descriptor.rotation,
            catalog: catalog
        )
    }

    public func bindInstalledLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) throws {
        guard var active, pending == nil,
              active.lease == nil,
              active.descriptor == command.surfaceDescriptor,
              command.lease.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              command.lease.authorizationEpoch
                == active.descriptor.authorizationEpoch,
              command.lease.surfaceID == active.descriptor.surfaceID,
              command.lease.surfaceRevision.rawValue
                == active.descriptor.surfaceRevision.rawValue,
              command.lease.coordinateRevision.rawValue
                == active.descriptor.coordinateSpaceRevision.rawValue else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        active.lease = command.lease
        self.active = active
    }

    public func snapshot(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        nowMonotonicMilliseconds: Int64
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        guard let active, pending == nil,
              active.lease != nil,
              active.descriptor.interactiveSessionID
                == interactiveSessionID,
              active.descriptor.authorizationEpoch
                == authorizationEpoch,
              nowMonotonicMilliseconds >= 0 else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        let content = try await SCShareableContent.current
        return try active.catalog.refresh(
            content: content,
            nowMonotonicMilliseconds: nowMonotonicMilliseconds
        )
    }

    public func resolve(
        _ request: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicMilliseconds: Int64
    ) async throws -> AdaptiveSurfaceDescriptor {
        guard let active, pending == nil,
              active.lease != nil,
              request.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              request.authorizationEpoch
                == active.descriptor.authorizationEpoch,
              request.currentSurfaceID
                == active.descriptor.surfaceID,
              request.expectedSurfaceRevision
                == active.descriptor.surfaceRevision,
              request.expectedCoordinateSpaceRevision
                == active.descriptor.coordinateSpaceRevision,
              nowMonotonicMilliseconds >= 0 else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        let content = try await SCShareableContent.current
        let resolved: ScreenCaptureKitResolvedSurfaceV0
        if request.targetKind == .desktop {
            guard request.targetToken == nil else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
            }
            resolved = try makeDesktopReplacement(
                active: active,
                content: content,
                nowMonotonicMilliseconds: nowMonotonicMilliseconds
            )
        } else {
            guard let targetToken = request.targetToken,
                  request.targetKind == .application
                    || request.targetKind == .window else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
            }
            resolved = try active.catalog.resolve(
                targetToken: targetToken,
                expectedKind: request.targetKind,
                currentContent: content,
                replacing: active.descriptor,
                nowMonotonicMilliseconds: nowMonotonicMilliseconds
            )
        }
        pending = resolved
        return resolved.descriptor
    }

    public func takePreparedSurface(
        for transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) throws -> ScreenCaptureKitResolvedSurfaceV0 {
        guard let active, let lease = active.lease,
              let pending,
              transition.previousLeaseID == lease.leaseID,
              transition.replacement.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              transition.descriptor == pending.descriptor,
              transition.replacement.surfaceID
                == pending.descriptor.surfaceID,
              transition.replacement.surfaceRevision.rawValue
                == pending.descriptor.surfaceRevision.rawValue,
              transition.replacement.coordinateRevision.rawValue
                == pending.descriptor.coordinateSpaceRevision.rawValue else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        self.pending = nil
        return pending
    }

    public func commit(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) throws {
        guard var active, let lease = active.lease,
              pending == nil,
              transition.previousLeaseID == lease.leaseID,
              transition.descriptor.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              transition.replacement.surfaceID
                == transition.descriptor.surfaceID,
              transition.replacement.surfaceRevision.rawValue
                == transition.descriptor.surfaceRevision.rawValue,
              transition.replacement.coordinateRevision.rawValue
                == transition.descriptor.coordinateSpaceRevision.rawValue else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        active.descriptor = transition.descriptor
        active.lease = transition.replacement
        self.active = active
    }

    public func invalidate() {
        active?.catalog.invalidate()
        active = nil
        pending = nil
    }

    private func makeDesktopReplacement(
        active: Active,
        content: SCShareableContent,
        nowMonotonicMilliseconds: Int64
    ) throws -> ScreenCaptureKitResolvedSurfaceV0 {
        guard let display = content.displays.first(where: {
            $0.displayID == active.physicalDisplayID
        }) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        let bounds = CGDisplayBounds(active.physicalDisplayID)
        let pixelWidth = Int(CGDisplayPixelsWide(active.physicalDisplayID))
        let pixelHeight = Int(CGDisplayPixelsHigh(active.physicalDisplayID))
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width.rounded(.up) <= Double(UInt32.max),
              bounds.height.rounded(.up) <= Double(UInt32.max),
              nowMonotonicMilliseconds <= Int64.max - 10_000 else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        let profile = try ScreenCaptureKitOpaqueTargetCatalogV0
            .captureProfile(
                logicalWidth: pixelWidth,
                logicalHeight: pixelHeight
            )
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: active.descriptor.interactiveSessionID,
            authorizationEpoch: active.descriptor.authorizationEpoch,
            surfaceID: identifier(),
            kind: .desktop,
            surfaceRevision: active.descriptor.surfaceRevision.advanced(),
            coordinateSpaceRevision:
                active.descriptor.coordinateSpaceRevision.advanced(),
            encodedWidth: UInt16(profile.width),
            encodedHeight: UInt16(profile.height),
            logicalWidthPoints: UInt32(bounds.width.rounded(.up)),
            logicalHeightPoints: UInt32(bounds.height.rounded(.up)),
            rotation: active.desktopRotation,
            interactionClasses: Set(active.descriptor.interactionClasses),
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: nowMonotonicMilliseconds,
            expiresAtMonotonicMilliseconds:
                nowMonotonicMilliseconds + 10_000
        )
        return ScreenCaptureKitResolvedSurfaceV0(
            filter: ScreenCaptureKitCaptureConfigurationV0
                .makeDesktopFilter(display: display),
            descriptor: descriptor,
            profile: profile,
            inputBounds: bounds,
            inputBackingScaleFactor: try
                ScreenCaptureKitOpaqueTargetCatalogV0
                    .backingScaleFactor(for: active.physicalDisplayID)
        )
    }
}
#endif
