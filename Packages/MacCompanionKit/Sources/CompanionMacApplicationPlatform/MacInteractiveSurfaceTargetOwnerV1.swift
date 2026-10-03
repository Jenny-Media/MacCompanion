#if os(macOS)
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveHost
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

public struct MacInteractiveFocusCandidateProjectionV1: Sendable {
    public let candidate: InteractiveFocusEventCandidateV0
    public let requiresInputPause: Bool

    public init(
        candidate: InteractiveFocusEventCandidateV0,
        requiresInputPause: Bool
    ) {
        self.candidate = candidate
        self.requiresInputPause = requiresInputPause
    }
}

enum MacInteractiveFocusReuseGuardV1 {
    static func shouldReuseActiveFocus(
        activeKind: InteractiveSurfaceKind,
        activeFocus: SurfaceFocus?,
        lastFocus: SurfaceFocus?,
        fingerprintMatches: Bool
    ) -> Bool {
        activeKind == .focusedRegion
            && fingerprintMatches
            && activeFocus != nil
            && lastFocus == activeFocus
    }
}

/// A selected app/window can be covered by another app's modal at the same
/// coordinates. Geometry alone cannot bind an AX focus to the capture owner.
enum MacInteractiveFocusOwnershipV1 {
    static func accepts(
        currentKind: InteractiveSurfaceKind,
        selectedProcessID: pid_t?,
        observedProcessID: pid_t?
    ) -> Bool {
        guard let observedProcessID, observedProcessID > 0 else {
            return false
        }
        switch currentKind {
        case .desktop:
            return true
        case .application, .window:
            return selectedProcessID == observedProcessID
                && selectedProcessID != nil
        case .focusedRegion:
            return selectedProcessID.map { $0 == observedProcessID }
                ?? true
        }
    }
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
        var physicalDisplayID: CGDirectDisplayID
        var desktopRotation: SurfaceRotation
        let catalog: ScreenCaptureKitOpaqueTargetCatalogV0
        var inputBounds: CGRect
        var focusedRegionFilter: SCContentFilter?
        var focusedRegionSourceGlobalBounds: CGRect?
        var focusedRegionPointPixelScale: Double?
        var localActivationTarget:
            ScreenCaptureKitLocalActivationTargetV0?
        var nativeCaptureSurface: ScreenCaptureKitResolvedSurfaceV0? = nil
    }

    private struct FocusFingerprint: Equatable {
        let category: FocusElementCategory
        let globalBounds: CGRect
        let editable: Bool
        let secure: Bool
        let processID: pid_t?
    }

    private let excludedBundleIdentifiers: Set<String>
    private let excludedProcessIdentifiers: Set<pid_t>
    private let identifier: @Sendable () -> UUID
    private let focusReader: any MacAccessibilityFocusReadingV0
    private let focusProjector = MacAccessibilityFocusProjectorV0()
    private var active: Active?
    private var pending: ScreenCaptureKitResolvedSurfaceV0?
    private var taken: ScreenCaptureKitResolvedSurfaceV0?
    private var lastFocusFingerprint: FocusFingerprint?
    private var focusToken: UUID?
    private var focusRevision: UInt64 = 0
    private var lastFocus: SurfaceFocus?
    private var lastFocusGlobalBounds: CGRect?
    private var issuedFocusTokens: Set<UUID> = []

    public init(
        excludedBundleIdentifiers: Set<String> = [
            "media.jenny.maccompanion",
        ],
        excludedProcessIdentifiers: Set<pid_t> = [getpid()],
        identifier: @escaping @Sendable () -> UUID = { UUID() },
        focusReader: any MacAccessibilityFocusReadingV0 =
            SystemMacAccessibilityFocusReaderV0()
    ) {
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.excludedProcessIdentifiers = excludedProcessIdentifiers
        self.identifier = identifier
        self.focusReader = focusReader
    }

    /// Binds the initial Desktop without ScreenCaptureKit enumeration. This is
    /// called by the same menu-side preparation that created the descriptor.
    public func bindInitialDesktop(
        command: LocalInteractiveInitialDesktopPreparationCommandV1,
        descriptor: AdaptiveSurfaceDescriptor,
        physicalDisplayID: CGDirectDisplayID
    ) throws {
        let inputBounds = CGDisplayBounds(physicalDisplayID)
        guard active?.lease == nil, pending == nil, taken == nil,
              physicalDisplayID != 0,
              Self.valid(inputBounds),
              descriptor.interactiveSessionID
                == command.interactiveSessionID,
              descriptor.authorizationEpoch == command.authorizationEpoch,
              descriptor.kind == .desktop,
              Set(descriptor.interactionClasses)
                == Set(command.interactionClasses) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        // Preparing a descriptor starts no capture and grants no execution
        // authority. If the Agent fails before installing the first lease, a
        // later fresh session must be able to replace that unleased residue.
        // An installed lease remains non-replaceable until explicit teardown.
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
            catalog: catalog,
            inputBounds: inputBounds,
            focusedRegionFilter: nil,
            focusedRegionSourceGlobalBounds: nil,
            focusedRegionPointPixelScale: nil,
            localActivationTarget: nil
        )
    }

    public func bindInstalledLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) throws {
        guard var active, pending == nil, taken == nil,
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

    package func retargetDesktop(
        physicalDisplayID: CGDirectDisplayID
    ) throws {
        guard var active, active.lease != nil,
              pending == nil, taken == nil,
              physicalDisplayID != 0,
              let rotation = Self.rotation(
                CGDisplayRotation(physicalDisplayID)
              ),
              Self.valid(CGDisplayBounds(physicalDisplayID)) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        active.physicalDisplayID = physicalDisplayID
        active.desktopRotation = rotation
        self.active = active
        lastFocusFingerprint = nil
        focusToken = nil
        lastFocus = nil
        lastFocusGlobalBounds = nil
    }

    /// Mirrors a validated same-surface renewal so later target resolution is
    /// correlated to the lease currently owned by the menu runtime.
    public func adoptRenewedLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) throws {
        guard var active, pending == nil, taken == nil,
              let current = active.lease else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        do {
            try renewal.validate(current: current)
        } catch {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        active.lease = renewal.replacement
        self.active = active
    }

    public func snapshot(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        nowMonotonicMilliseconds: Int64
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        guard let active, pending == nil, taken == nil,
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
        guard let active, pending == nil, taken == nil,
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
        } else if request.targetKind == .focusedRegion {
            guard let targetToken = request.targetToken else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
            }
            resolved = try makeFocusedRegionReplacement(
                active: active,
                content: content,
                targetToken: targetToken,
                nowMonotonicMilliseconds: nowMonotonicMilliseconds
            )
        } else {
            guard let targetToken = request.targetToken,
                  request.targetKind == .application
                    || request.targetKind == .window else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
            }
            do {
                resolved = try active.catalog.resolve(
                    targetToken: targetToken,
                    expectedKind: request.targetKind,
                    currentContent: content,
                    replacing: active.descriptor,
                    nowMonotonicMilliseconds: nowMonotonicMilliseconds
                )
            } catch ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceDisappeared {
                // The exact token was consumed, but its live source vanished.
                // Publish a fresh acknowledged Desktop transition, preserving
                // the current lease and selected display. Invalid tokens and
                // authority errors never reach this recovery path.
                resolved = try makeDesktopReplacement(active: active, content: content,
                    nowMonotonicMilliseconds: nowMonotonicMilliseconds)
            }
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
        taken = pending
        return pending
    }

    public func commit(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) throws {
        guard var active, let lease = active.lease,
              pending == nil, let taken,
              transition.previousLeaseID == lease.leaseID,
              transition.descriptor.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              transition.replacement.surfaceID
                == transition.descriptor.surfaceID,
              transition.replacement.surfaceRevision.rawValue
                == transition.descriptor.surfaceRevision.rawValue,
              transition.replacement.coordinateRevision.rawValue
                == transition.descriptor.coordinateSpaceRevision.rawValue,
              taken.descriptor == transition.descriptor,
              Self.valid(taken.inputBounds) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        active.descriptor = transition.descriptor
        active.lease = transition.replacement
        active.inputBounds = taken.inputBounds
        active.focusedRegionFilter = taken.focusedRegionFilter
        active.focusedRegionSourceGlobalBounds =
            taken.focusedRegionSourceGlobalBounds
        active.focusedRegionPointPixelScale =
            taken.inputBackingScaleFactor
        active.localActivationTarget = taken.localActivationTarget
        active.nativeCaptureSurface = taken
        self.active = active
        self.taken = nil
        if let focus = transition.descriptor.focus,
           transition.descriptor.kind == .focusedRegion {
            focusToken = focus.token
            focusRevision = focus.revision.rawValue
            lastFocus = focus
        } else {
            lastFocusFingerprint = nil
            focusToken = nil
            lastFocus = nil
            lastFocusGlobalBounds = nil
        }
    }

    /// An absent selected object is valid only for the exact active Desktop.
    /// Pending, replaced and unsupported targets cannot be treated as Desktop.
    public func nativeCaptureTarget(
        scope: LocalInteractiveNativeBackendScopeV1,
        nowMonotonicNanoseconds: UInt64
    ) throws -> ScreenCaptureKitResolvedSurfaceV0? {
        try scope.validate()
        guard pending == nil, taken == nil,
              let active, let lease = active.lease,
              lease.hostID == scope.hostID,
              lease.interactiveSessionID == scope.interactiveSessionID,
              lease.authorizationEpoch.rawValue == UInt64(scope.authorizationEpoch),
              lease.selectedDisplayID == scope.selectedDisplayID,
              lease.surfaceID == scope.surfaceID,
              lease.surfaceRevision.rawValue == UInt64(scope.surfaceRevision),
              lease.coordinateRevision.rawValue == UInt64(scope.coordinateSpaceRevision),
              Int(active.descriptor.encodedWidth) == scope.encodedWidth,
              Int(active.descriptor.encodedHeight) == scope.encodedHeight,
              active.descriptor.logicalWidthPoints == scope.logicalWidthPoints,
              active.descriptor.logicalHeightPoints == scope.logicalHeightPoints,
              active.descriptor.rotation == scope.rotation,
              nowMonotonicNanoseconds < lease.expiresAtMonotonicNanoseconds,
              nowMonotonicNanoseconds / 1_000_000 < scope.expiresAtMonotonicMilliseconds else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        if active.descriptor.kind == .desktop {
            guard active.nativeCaptureSurface == nil || (active.nativeCaptureSurface?.descriptor == active.descriptor
                && active.nativeCaptureSurface?.localActivationTarget == nil) else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            return nil
        }
        guard active.descriptor.kind == .application || active.descriptor.kind == .window,
              let surface = active.nativeCaptureSurface,
              surface.descriptor == active.descriptor else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        _ = try MacInteractiveNativeCaptureGeometryV1.readSelectedSurface(surface, scope: scope)
        return surface
    }

    /// Retained ScreenCaptureKit objects remain entirely in the menu. The
    /// caller still needs a current native runtime snapshot, actual sample
    /// evidence and presentation admission before it can stream or post input.
    public func nativeCaptureSurface(
        scope: LocalInteractiveNativeBackendScopeV1,
        nowMonotonicNanoseconds: UInt64
    ) throws -> ScreenCaptureKitResolvedSurfaceV0 {
        guard let surface = try nativeCaptureTarget(scope: scope, nowMonotonicNanoseconds: nowMonotonicNanoseconds) else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return surface
    }

    public func focusCandidate(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        inputPaused: Bool
    ) throws -> MacInteractiveFocusCandidateProjectionV1 {
        guard let active, pending == nil, taken == nil,
              active.lease != nil,
              command.interactiveSessionID
                == active.descriptor.interactiveSessionID,
              command.authorizationEpoch
                == active.descriptor.authorizationEpoch,
              command.currentSurfaceID == active.descriptor.surfaceID,
              command.expectedSurfaceRevision
                == active.descriptor.surfaceRevision,
              command.expectedCoordinateSpaceRevision
                == active.descriptor.coordinateSpaceRevision,
              Self.valid(active.inputBounds) else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        let rawReadResult = focusReader.readCurrentFocus()
        let readResult: MacAccessibilityFocusReadResultV0
        if case let .verified(observation) = rawReadResult,
           !MacInteractiveFocusOwnershipV1.accepts(
               currentKind: active.descriptor.kind,
               selectedProcessID: Self.processID(
                   for: active.localActivationTarget
               ),
               observedProcessID: observation.processID
           ) {
            readResult = .unavailable(.noVerifiedFocus)
        } else {
            readResult = rawReadResult
        }
        let observationFingerprint: FocusFingerprint?
        if case let .verified(observation) = readResult {
            observationFingerprint = FocusFingerprint(
                category: observation.category,
                globalBounds: observation.globalBounds,
                editable: observation.editable,
                secure: observation.secure,
                processID: observation.processID
            )
        } else {
            observationFingerprint = nil
        }
        let projected = try focusProjector.project(
            readResult,
            currentSurfaceGlobalBounds: active.inputBounds,
            focusToken: command.commandID,
            focusRevision: FocusRevision(rawValue: 1),
            inputPaused: inputPaused
        )
        guard let projectedFocus = projected.focus else {
            lastFocusFingerprint = nil
            focusToken = nil
            lastFocus = nil
            lastFocusGlobalBounds = nil
            return MacInteractiveFocusCandidateProjectionV1(
                candidate: projected,
                requiresInputPause:
                    active.descriptor.kind == .focusedRegion
                        && active.descriptor.focus != nil
            )
        }
        guard let fingerprint = observationFingerprint else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        if MacInteractiveFocusReuseGuardV1.shouldReuseActiveFocus(
            activeKind: active.descriptor.kind,
            activeFocus: active.descriptor.focus,
            lastFocus: lastFocus,
            fingerprintMatches: fingerprint == lastFocusFingerprint
        ), let activeFocus = active.descriptor.focus {
            let candidate = try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: .focusedRegion,
                focus: activeFocus,
                inputPaused: inputPaused,
                reason: .verifiedFocus,
                validForMilliseconds: projected.validForMilliseconds
            )
            lastFocus = activeFocus
            lastFocusGlobalBounds = fingerprint.globalBounds
            return MacInteractiveFocusCandidateProjectionV1(
                candidate: candidate,
                requiresInputPause: false
            )
        }
        if fingerprint != lastFocusFingerprint {
            guard focusRevision < FocusRevision.maximumWireValue,
                  issuedFocusTokens.count < 100_000 else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
            }
            let nextToken = identifier()
            guard nextToken != active.descriptor.surfaceID,
                  !issuedFocusTokens.contains(nextToken) else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
            }
            focusRevision += 1
            focusToken = nextToken
            issuedFocusTokens.insert(nextToken)
            lastFocusFingerprint = fingerprint
        }
        guard let focusToken, focusRevision >= 1 else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
        }
        let focus = try SurfaceFocus(
            token: focusToken,
            revision: FocusRevision(rawValue: focusRevision),
            category: projectedFocus.category,
            bounds: projectedFocus.bounds,
            editable: projectedFocus.editable,
            secure: projectedFocus.secure
        )
        let candidate = try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: projected.recommendedTargetKind,
            focus: focus,
            inputPaused: projected.inputPaused,
            reason: projected.reason,
            validForMilliseconds: projected.validForMilliseconds
        )
        lastFocus = focus
        if case let .verified(observation) = readResult {
            lastFocusGlobalBounds = observation.globalBounds
        } else {
            lastFocusGlobalBounds = nil
        }
        return MacInteractiveFocusCandidateProjectionV1(
            candidate: candidate,
            requiresInputPause:
                active.descriptor.kind == .focusedRegion
                    && candidate.focus != active.descriptor.focus
        )
    }

    public func invalidate() {
        active?.catalog.invalidate()
        active = nil
        pending = nil
        taken = nil
        lastFocusFingerprint = nil
        focusToken = nil
        focusRevision = 0
        lastFocus = nil
        lastFocusGlobalBounds = nil
        issuedFocusTokens.removeAll(keepingCapacity: false)
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
            focusedRegionSourceGlobalBounds: bounds,
            inputBounds: bounds,
            inputBackingScaleFactor: try
                ScreenCaptureKitOpaqueTargetCatalogV0
                    .backingScaleFactor(for: active.physicalDisplayID)
        )
    }

    private static func rotation(_ value: Double) -> SurfaceRotation? {
        guard value.isFinite else { return nil }
        return switch Int(value.rounded()) {
        case 0, 360, -360: .degrees0
        case 90, -270: .degrees90
        case 180, -180: .degrees180
        case 270, -90: .degrees270
        default: nil
        }
    }

    private static func processID(
        for target: ScreenCaptureKitLocalActivationTargetV0?
    ) -> pid_t? {
        switch target {
        case let .application(processID, _),
             let .window(_, processID, _, _):
            processID
        case nil:
            nil
        }
    }

    private func makeFocusedRegionReplacement(
        active: Active,
        content: SCShareableContent,
        targetToken _: UUID,
        nowMonotonicMilliseconds: Int64
    ) throws -> ScreenCaptureKitResolvedSurfaceV0 {
        guard let expectedFocus = lastFocus,
              let expectedGlobalBounds = lastFocusGlobalBounds,
              case let .verified(observation) = focusReader.readCurrentFocus(),
              MacInteractiveFocusOwnershipV1.accepts(
                  currentKind: active.descriptor.kind,
                  selectedProcessID: Self.processID(
                      for: active.localActivationTarget
                  ),
                  observedProcessID: observation.processID
              ),
              observation.globalBounds == expectedGlobalBounds,
              nowMonotonicMilliseconds <= Int64.max - 10_000 else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }
        let fingerprint = FocusFingerprint(
            category: observation.category,
            globalBounds: observation.globalBounds,
            editable: observation.editable,
            secure: observation.secure,
            processID: observation.processID
        )
        guard fingerprint == lastFocusFingerprint else {
            throw MacInteractiveSurfaceTargetOwnerErrorV1.bindingMismatch
        }

        let filter: SCContentFilter
        let sourceBounds: CGRect
        let pointPixelScale: Double
        if let retainedFilter = active.focusedRegionFilter,
           let retainedBounds = active.focusedRegionSourceGlobalBounds,
           let retainedScale = active.focusedRegionPointPixelScale {
            filter = retainedFilter
            sourceBounds = retainedBounds
            pointPixelScale = retainedScale
        } else {
            guard active.descriptor.kind == .desktop,
                  let display = content.displays.first(where: {
                    $0.displayID == active.physicalDisplayID
                  }) else {
                throw MacInteractiveSurfaceTargetOwnerErrorV1.unavailable
            }
            filter = ScreenCaptureKitCaptureConfigurationV0
                .makeDesktopFilter(display: display)
            sourceBounds = CGDisplayBounds(active.physicalDisplayID)
            pointPixelScale = try ScreenCaptureKitOpaqueTargetCatalogV0
                .backingScaleFactor(for: active.physicalDisplayID)
        }
        let crop = try ScreenCaptureKitFocusedRegionCropV0(
            focusGlobalBounds: observation.globalBounds,
            sourceGlobalBounds: sourceBounds,
            pointPixelScale: pointPixelScale
        )
        let applicationToken = active.descriptor.applicationToken
            ?? identifier()
        let fallbackSurfaceID = active.descriptor.kind == .desktop
            ? active.descriptor.surfaceID
            : active.descriptor.fallbackSurfaceID
                ?? active.descriptor.surfaceID
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: active.descriptor.interactiveSessionID,
            authorizationEpoch: active.descriptor.authorizationEpoch,
            surfaceID: identifier(),
            kind: .focusedRegion,
            surfaceRevision: active.descriptor.surfaceRevision.advanced(),
            coordinateSpaceRevision:
                active.descriptor.coordinateSpaceRevision.advanced(),
            applicationToken: applicationToken,
            parentSurfaceID: active.descriptor.surfaceID,
            fallbackSurfaceID: fallbackSurfaceID,
            encodedWidth: UInt16(crop.profile.width),
            encodedHeight: UInt16(crop.profile.height),
            logicalWidthPoints: UInt32(
                crop.globalBounds.width.rounded(.up)
            ),
            logicalHeightPoints: UInt32(
                crop.globalBounds.height.rounded(.up)
            ),
            interactionClasses: Set(active.descriptor.interactionClasses),
            privacyProfile: .assistedVisual,
            metadataFields: [
                .focusCategory, .focusBounds, .editable, .secure,
            ],
            focus: expectedFocus,
            createdAtMonotonicMilliseconds: nowMonotonicMilliseconds,
            expiresAtMonotonicMilliseconds:
                nowMonotonicMilliseconds + 10_000
        )
        return ScreenCaptureKitResolvedSurfaceV0(
            filter: filter,
            focusedRegionFilter: filter,
            descriptor: descriptor,
            profile: crop.profile,
            sourceRect: crop.sourceRect,
            focusedRegionSourceGlobalBounds: sourceBounds,
            inputBounds: crop.globalBounds,
            inputBackingScaleFactor: pointPixelScale,
            localActivationTarget: active.localActivationTarget
        )
    }

    private static func valid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
    }
}
#endif
