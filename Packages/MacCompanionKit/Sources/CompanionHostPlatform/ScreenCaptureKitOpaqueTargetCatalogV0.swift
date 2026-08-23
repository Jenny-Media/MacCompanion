import CompanionDomain
import CompanionInteractiveShared
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureKitOpaqueTargetCatalogErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case selectedDisplayUnavailable
    case sourceUnavailable
    case descriptorMismatch
}

/// A menu-process-only capture result. ScreenCaptureKit objects and physical
/// identifiers are intentionally held behind this non-Codable boundary.
@available(macOS 13.0, *)
public final class ScreenCaptureKitResolvedSurfaceV0: @unchecked Sendable {
    public let filter: SCContentFilter
    public let descriptor: AdaptiveSurfaceDescriptor
    public let profile: ScreenCaptureKitCaptureProfileV0
    /// Global Core Graphics point-space bounds used for absolute input. This
    /// never crosses IPC and is deliberately separate from the sanitized
    /// descriptor.
    public let inputBounds: CGRect
    /// Backing scale for the display containing `inputBounds`. A selected
    /// window may live on a different physical display than the initial
    /// Desktop, so this cannot be reconstructed from the lease display ID.
    public let inputBackingScaleFactor: Double

    public init(
        filter: SCContentFilter,
        descriptor: AdaptiveSurfaceDescriptor,
        profile: ScreenCaptureKitCaptureProfileV0,
        inputBounds: CGRect,
        inputBackingScaleFactor: Double
    ) {
        self.filter = filter
        self.descriptor = descriptor
        self.profile = profile
        self.inputBounds = inputBounds
        self.inputBackingScaleFactor = inputBackingScaleFactor
    }
}

/// Owns the only mapping from session-scoped opaque target tokens to
/// ScreenCaptureKit identities. It never reads a window title and never
/// returns bundle identifiers, PIDs, window IDs, or ScreenCaptureKit objects
/// through its inventory snapshot.
@available(macOS 13.0, *)
public final class ScreenCaptureKitOpaqueTargetCatalogV0: @unchecked Sendable {
    private enum LocalSource {
        case application(processID: pid_t, bundleIdentifier: String)
        case window(
            windowID: CGWindowID,
            processID: pid_t,
            bundleIdentifier: String
        )
    }

    private let lock = NSLock()
    private let selectedDisplayID: CGDirectDisplayID
    private let excludedBundleIdentifiers: Set<String>
    private let excludedProcessIdentifiers: Set<pid_t>
    private var inventory: AdaptiveSurfaceTargetInventoryV0
    private var localSources: [UUID: LocalSource] = [:]

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: CGDirectDisplayID,
        excludedBundleIdentifiers: Set<String>,
        excludedProcessIdentifiers: Set<pid_t>,
        tokenGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        guard selectedDisplayID != 0,
              !excludedBundleIdentifiers.isEmpty
                || !excludedProcessIdentifiers.isEmpty else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                .invalidConfiguration
        }
        self.selectedDisplayID = selectedDisplayID
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.excludedProcessIdentifiers = excludedProcessIdentifiers
        inventory = try AdaptiveSurfaceTargetInventoryV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            tokenGenerator: tokenGenerator
        )
    }

    public func refresh(
        content: SCShareableContent,
        nowMonotonicMilliseconds: Int64,
        lifetimeMilliseconds: Int64 =
            AdaptiveSurfaceTargetInventoryV0.maximumLifetimeMilliseconds
    ) throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        lock.lock()
        defer { lock.unlock() }
        guard content.displays.contains(where: {
            $0.displayID == selectedDisplayID
        }) else {
            invalidateLocked()
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                .selectedDisplayUnavailable
        }

        let applications = content.applications.filter(isAllowed)
        let allowedPIDs = Set(applications.map(\.processID))
        let windows = content.windows.filter { window in
            guard window.isOnScreen,
                  window.frame.width > 0,
                  window.frame.height > 0,
                  let owner = window.owningApplication else { return false }
            return allowedPIDs.contains(owner.processID)
                && isAllowed(owner)
        }
        let windowsByPID = Dictionary(grouping: windows) {
            $0.owningApplication!.processID
        }
        var sourceReferences: [pid_t: UUID] = [:]
        var observations: [AdaptiveSurfaceTargetObservationV0] = []
        var nextSources: [UUID: LocalSource] = [:]

        for application in applications {
            let sourceReference = UUID()
            sourceReferences[application.processID] = sourceReference
            do {
                observations.append(try AdaptiveSurfaceTargetObservationV0(
                    sourceReference: sourceReference,
                    kind: .application,
                    applicationSourceReference: sourceReference,
                    applicationName: application.applicationName,
                    currentWindowAvailable:
                        !(windowsByPID[application.processID] ?? []).isEmpty,
                    localSortOrder: UInt64(
                        UInt32(bitPattern: application.processID)
                    )
                ))
                nextSources[sourceReference] = .application(
                    processID: application.processID,
                    bundleIdentifier: application.bundleIdentifier
                )
            } catch AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation {
                sourceReferences.removeValue(forKey: application.processID)
            }
        }
        for window in windows {
            guard let owner = window.owningApplication,
                  let applicationReference =
                    sourceReferences[owner.processID] else { continue }
            let sourceReference = UUID()
            observations.append(try AdaptiveSurfaceTargetObservationV0(
                sourceReference: sourceReference,
                kind: .window,
                applicationSourceReference: applicationReference,
                applicationName: owner.applicationName,
                currentWindowAvailable: true,
                localSortOrder: UInt64(window.windowID)
            ))
            nextSources[sourceReference] = .window(
                windowID: window.windowID,
                processID: owner.processID,
                bundleIdentifier: owner.bundleIdentifier
            )
        }

        var nextInventory = inventory
        let snapshot = try nextInventory.replace(
            observations: observations,
            nowMonotonicMilliseconds: nowMonotonicMilliseconds,
            lifetimeMilliseconds: lifetimeMilliseconds
        )
        inventory = nextInventory
        localSources = nextSources
        return snapshot
    }

    public func resolve(
        targetToken: UUID,
        expectedKind: InteractiveSurfaceKind,
        currentContent: SCShareableContent,
        replacing current: AdaptiveSurfaceDescriptor,
        nowMonotonicMilliseconds: Int64
    ) throws -> ScreenCaptureKitResolvedSurfaceV0 {
        lock.lock()
        defer { lock.unlock() }
        guard current.interactiveSessionID == inventory.interactiveSessionID,
              current.authorizationEpoch == inventory.authorizationEpoch else {
            invalidateLocked()
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.descriptorMismatch
        }
        let resolution = try inventory.consume(
            targetToken: targetToken,
            expectedKind: expectedKind,
            nowMonotonicMilliseconds: nowMonotonicMilliseconds
        )
        defer { localSources.removeAll(keepingCapacity: false) }
        guard let source = localSources[resolution.sourceReference],
              let display = currentContent.displays.first(where: {
                  $0.displayID == selectedDisplayID
              }) else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceUnavailable
        }

        let filter: SCContentFilter
        let logicalWidth: Int
        let logicalHeight: Int
        let captureWidth: Int
        let captureHeight: Int
        let inputBounds: CGRect
        let metadataFields: Set<SurfaceMetadataField>
        let rotation: SurfaceRotation
        let inputBackingScaleFactor: Double
        switch source {
        case let .application(processID, bundleIdentifier):
            guard expectedKind == .application,
                  let application = currentContent.applications.first(where: {
                      $0.processID == processID
                        && $0.bundleIdentifier == bundleIdentifier
                  }), isAllowed(application) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            let hasWindow = currentContent.windows.contains { window in
                window.isOnScreen
                    && window.frame.width > 0
                    && window.frame.height > 0
                    && window.owningApplication?.processID == processID
            }
            guard hasWindow else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            filter = ScreenCaptureKitCaptureConfigurationV0
                .makeApplicationFilter(
                    display: display,
                    application: application
                )
            inputBounds = CGDisplayBounds(selectedDisplayID)
            logicalWidth = Int(inputBounds.width.rounded(.up))
            logicalHeight = Int(inputBounds.height.rounded(.up))
            captureWidth = Int(CGDisplayPixelsWide(selectedDisplayID))
            captureHeight = Int(CGDisplayPixelsHigh(selectedDisplayID))
            metadataFields = [
                .applicationName, .windowCount, .currentWindowAvailable,
            ]
            rotation = current.kind == .window
                ? .degrees0 : current.rotation
            inputBackingScaleFactor = try Self.backingScaleFactor(
                for: selectedDisplayID
            )
        case let .window(windowID, processID, bundleIdentifier):
            guard expectedKind == .window,
                  let window = currentContent.windows.first(where: {
                      $0.windowID == windowID
                  }), window.isOnScreen,
                  window.frame.width > 0,
                  window.frame.height > 0,
                  window.owningApplication?.processID == processID,
                  let owner = window.owningApplication,
                  owner.bundleIdentifier == bundleIdentifier,
                  isAllowed(owner) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            filter = ScreenCaptureKitCaptureConfigurationV0
                .makeWindowFilter(window: window)
            logicalWidth = Int(window.frame.width.rounded(.up))
            logicalHeight = Int(window.frame.height.rounded(.up))
            inputBounds = window.frame
            let inputDisplayID = Self.displayContainingCenter(
                of: window.frame,
                fallback: selectedDisplayID
            )
            let displayBounds = CGDisplayBounds(inputDisplayID)
            guard displayBounds.width.isFinite,
                  displayBounds.height.isFinite,
                  displayBounds.width > 0,
                  displayBounds.height > 0 else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            let pointScale = max(
                Double(CGDisplayPixelsWide(inputDisplayID))
                    / displayBounds.width,
                Double(CGDisplayPixelsHigh(inputDisplayID))
                    / displayBounds.height
            )
            inputBackingScaleFactor = pointScale
            captureWidth = Int(
                (window.frame.width * pointScale).rounded(.up)
            )
            captureHeight = Int(
                (window.frame.height * pointScale).rounded(.up)
            )
            metadataFields = [.applicationName, .genericWindowOrdinal]
            rotation = .degrees0
        }
        let profile = try Self.captureProfile(
            logicalWidth: captureWidth,
            logicalHeight: captureHeight
        )
        guard logicalWidth > 0, logicalHeight > 0,
              captureWidth > 0, captureHeight > 0,
              inputBounds.origin.x.isFinite,
              inputBounds.origin.y.isFinite,
              inputBounds.width.isFinite,
              inputBounds.height.isFinite,
              inputBackingScaleFactor.isFinite,
              inputBackingScaleFactor > 0,
              logicalWidth <= Int(UInt32.max),
              logicalHeight <= Int(UInt32.max),
              nowMonotonicMilliseconds
                <= Int64.max - 10_000 else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                .sourceUnavailable
        }
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: current.interactiveSessionID,
            authorizationEpoch: current.authorizationEpoch,
            surfaceID: UUID(),
            kind: expectedKind,
            surfaceRevision: current.surfaceRevision.advanced(),
            coordinateSpaceRevision:
                current.coordinateSpaceRevision.advanced(),
            applicationToken: resolution.candidate.applicationToken,
            windowToken: expectedKind == .window
                ? resolution.candidate.targetToken : nil,
            parentSurfaceID: current.surfaceID,
            fallbackSurfaceID: current.kind == .desktop
                ? current.surfaceID : current.fallbackSurfaceID,
            encodedWidth: UInt16(profile.width),
            encodedHeight: UInt16(profile.height),
            logicalWidthPoints: UInt32(logicalWidth),
            logicalHeightPoints: UInt32(logicalHeight),
            rotation: rotation,
            interactionClasses: Set(current.interactionClasses),
            privacyProfile: .visualOnly,
            metadataFields: metadataFields,
            createdAtMonotonicMilliseconds: nowMonotonicMilliseconds,
            expiresAtMonotonicMilliseconds:
                nowMonotonicMilliseconds + 10_000
        )
        return ScreenCaptureKitResolvedSurfaceV0(
            filter: filter,
            descriptor: descriptor,
            profile: profile,
            inputBounds: inputBounds,
            inputBackingScaleFactor: inputBackingScaleFactor
        )
    }

    public static func backingScaleFactor(
        for displayID: CGDirectDisplayID
    ) throws -> Double {
        let bounds = CGDisplayBounds(displayID)
        guard displayID != 0,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                .sourceUnavailable
        }
        let scale = max(
            Double(CGDisplayPixelsWide(displayID)) / bounds.width,
            Double(CGDisplayPixelsHigh(displayID)) / bounds.height
        )
        guard scale.isFinite, scale > 0 else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                .sourceUnavailable
        }
        return scale
    }

    private static func displayContainingCenter(
        of frame: CGRect,
        fallback: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard center.x.isFinite, center.y.isFinite,
              CGGetDisplaysWithPoint(center, 1, &displayID, &count)
                == .success,
              count == 1, displayID != 0 else { return fallback }
        return displayID
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidateLocked()
    }

    private func isAllowed(_ application: SCRunningApplication) -> Bool {
        guard !excludedProcessIdentifiers.contains(application.processID)
        else { return false }
        if excludedBundleIdentifiers.contains(application.bundleIdentifier) {
            return false
        }
        return true
    }

    private func invalidateLocked() {
        inventory.invalidate()
        localSources.removeAll(keepingCapacity: false)
    }

    public static func captureProfile(
        logicalWidth: Int,
        logicalHeight: Int
    ) throws -> ScreenCaptureKitCaptureProfileV0 {
        guard logicalWidth > 0, logicalHeight > 0 else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceUnavailable
        }
        let scale = min(
            Double(ScreenCaptureKitCaptureProfileV0.maximumWidth)
                / Double(logicalWidth),
            Double(ScreenCaptureKitCaptureProfileV0.maximumHeight)
                / Double(logicalHeight),
            1
        )
        let width = max(1, Int((Double(logicalWidth) * scale).rounded(.down)))
        let height = max(1, Int((Double(logicalHeight) * scale).rounded(.down)))
        return try ScreenCaptureKitCaptureProfileV0(
            width: width,
            height: height,
            framesPerSecond:
                ScreenCaptureKitCaptureProfileV0.maximumFramesPerSecond,
            queueDepth: ScreenCaptureKitCaptureProfileV0.maximumQueueDepth
        )
    }
}
