import CompanionDomain
import CompanionInteractiveShared
import CoreGraphics
import Darwin
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
    case sourceDisappeared
    case descriptorMismatch
}

/// Menu-process-only identity for the app/window that must become the local
/// input destination before a selected visual surface is acknowledged. These
/// process and window identifiers are never encoded, persisted, or returned
/// through IPC.
public enum ScreenCaptureKitLocalActivationTargetV0: Equatable, Sendable {
    case application(
        processID: pid_t,
        bundleIdentifier: String
    )
    case window(
        windowID: CGWindowID,
        processID: pid_t,
        bundleIdentifier: String,
        globalBounds: CGRect
    )
}

/// A menu-process-only capture result. ScreenCaptureKit objects and physical
/// identifiers are intentionally held behind this non-Codable boundary.
@available(macOS 13.0, *)
public final class ScreenCaptureKitResolvedSurfaceV0: @unchecked Sendable {
    public let filter: SCContentFilter
    /// Display-style filter retained for a later focused-region crop. A
    /// single-window filter cannot be used because ScreenCaptureKit ignores
    /// `sourceRect` for single-window capture.
    public let focusedRegionFilter: SCContentFilter
    public let descriptor: AdaptiveSurfaceDescriptor
    public let profile: ScreenCaptureKitCaptureProfileV0
    /// Display-logical crop rectangle relative to
    /// `focusedRegionSourceGlobalBounds`, or nil for the whole filter.
    public let sourceRect: CGRect?
    public let focusedRegionSourceGlobalBounds: CGRect
    /// Global Core Graphics point-space bounds used for absolute input. This
    /// never crosses IPC and is deliberately separate from the sanitized
    /// descriptor.
    public let inputBounds: CGRect
    /// Backing scale for the display containing `inputBounds`. A selected
    /// window may live on a different physical display than the initial
    /// Desktop, so this cannot be reconstructed from the lease display ID.
    public let inputBackingScaleFactor: Double
    /// Ephemeral local activation identity. Desktop and focused crops do not
    /// create a new activation effect; app/window selections must carry one.
    public let localActivationTarget:
        ScreenCaptureKitLocalActivationTargetV0?

    public init(
        filter: SCContentFilter,
        focusedRegionFilter: SCContentFilter? = nil,
        descriptor: AdaptiveSurfaceDescriptor,
        profile: ScreenCaptureKitCaptureProfileV0,
        sourceRect: CGRect? = nil,
        focusedRegionSourceGlobalBounds: CGRect? = nil,
        inputBounds: CGRect,
        inputBackingScaleFactor: Double,
        localActivationTarget:
            ScreenCaptureKitLocalActivationTargetV0? = nil
    ) {
        self.filter = filter
        self.focusedRegionFilter = focusedRegionFilter ?? filter
        self.descriptor = descriptor
        self.profile = profile
        self.sourceRect = sourceRect
        self.focusedRegionSourceGlobalBounds =
            focusedRegionSourceGlobalBounds ?? inputBounds
        self.inputBounds = inputBounds
        self.inputBackingScaleFactor = inputBackingScaleFactor
        self.localActivationTarget = localActivationTarget
    }
}

/// Owns the only mapping from session-scoped opaque target tokens to
/// ScreenCaptureKit identities. It exposes only bounded transient picker titles
/// and never returns bundle identifiers, PIDs, window IDs, or ScreenCaptureKit objects
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
            guard Self.isSelectableWindow(window),
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
            guard !(windowsByPID[application.processID] ?? []).isEmpty else { continue }
            let sourceReference = UUID()
            sourceReferences[application.processID] = sourceReference
            do {
                observations.append(try AdaptiveSurfaceTargetObservationV0(
                    sourceReference: sourceReference,
                    kind: .application,
                    applicationSourceReference: sourceReference,
                    applicationName: application.applicationName,
                    currentWindowAvailable:
                        Self.applicationViewAvailable(windows: windowsByPID[application.processID] ?? [],
                            displayID: selectedDisplayID),
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
                localSortOrder: UInt64(window.windowID),
                windowTitle: AdaptiveSurfaceTargetObservationV0.sanitizedWindowTitle(window.title)
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
        let focusedRegionFilter: SCContentFilter
        let focusedRegionSourceGlobalBounds: CGRect
        let logicalWidth: Int
        let logicalHeight: Int
        let captureWidth: Int
        let captureHeight: Int
        let sourceRect: CGRect?
        let inputBounds: CGRect
        let metadataFields: Set<SurfaceMetadataField>
        let rotation: SurfaceRotation
        let inputBackingScaleFactor: Double
        let localActivationTarget:
            ScreenCaptureKitLocalActivationTargetV0
        switch source {
        case let .application(processID, bundleIdentifier):
            guard let application = currentContent.applications.first(where: {
                $0.processID == processID
            }) else { throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceDisappeared }
            guard expectedKind == .application,
                  application.bundleIdentifier == bundleIdentifier, isAllowed(application) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            let visibleWindowBounds = currentContent.windows.compactMap {
                window -> CGRect? in
                window.isOnScreen
                    && window.windowLayer == 0
                    && window.frame.width > 0
                    && window.frame.height > 0
                    && window.owningApplication?.processID == processID
                    ? window.frame : nil
            }
            let displayBounds = CGDisplayBounds(selectedDisplayID)
            guard displayBounds.width.isFinite,
                  displayBounds.height.isFinite,
                  displayBounds.width > 0,
                  displayBounds.height > 0,
                  let crop = try? ScreenCaptureKitApplicationCropV0(
                      windowGlobalBounds: visibleWindowBounds,
                      sourceGlobalBounds: displayBounds
                  ) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceDisappeared
            }
            filter = ScreenCaptureKitCaptureConfigurationV0
                .makeApplicationFilter(
                    display: display,
                    application: application
                )
            focusedRegionFilter = filter
            sourceRect = crop.sourceRect
            inputBounds = crop.globalBounds
            focusedRegionSourceGlobalBounds = displayBounds
            logicalWidth = Int(inputBounds.width.rounded(.up))
            logicalHeight = Int(inputBounds.height.rounded(.up))
            inputBackingScaleFactor = try Self.backingScaleFactor(
                for: selectedDisplayID
            )
            captureWidth = Int(
                (inputBounds.width * inputBackingScaleFactor).rounded(.up)
            )
            captureHeight = Int(
                (inputBounds.height * inputBackingScaleFactor).rounded(.up)
            )
            metadataFields = [
                .applicationName, .windowCount, .currentWindowAvailable,
            ]
            rotation = current.kind == .window
                ? .degrees0 : current.rotation
            localActivationTarget = .application(
                processID: processID,
                bundleIdentifier: bundleIdentifier
            )
        case let .window(windowID, processID, bundleIdentifier):
            guard let window = currentContent.windows.first(where: {
                $0.windowID == windowID
            }) else { throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceDisappeared }
            guard expectedKind == .window,
                  window.owningApplication?.processID == processID,
                  let owner = window.owningApplication,
                  owner.bundleIdentifier == bundleIdentifier,
                  isAllowed(owner) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            guard Self.isSelectableWindow(window) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceDisappeared
            }
            filter = ScreenCaptureKitCaptureConfigurationV0
                .makeWindowFilter(window: window)
            sourceRect = nil
            logicalWidth = Int(window.frame.width.rounded(.up))
            logicalHeight = Int(window.frame.height.rounded(.up))
            inputBounds = window.frame
            let inputDisplayID = Self.displayContainingCenter(
                of: window.frame,
                fallback: selectedDisplayID
            )
            let displayBounds = CGDisplayBounds(inputDisplayID)
            guard let focusDisplay = currentContent.displays.first(where: {
                $0.displayID == inputDisplayID
            }) else {
                throw ScreenCaptureKitOpaqueTargetCatalogErrorV0
                    .sourceUnavailable
            }
            focusedRegionFilter = ScreenCaptureKitCaptureConfigurationV0
                .makeApplicationFilter(
                    display: focusDisplay,
                    application: owner
                )
            focusedRegionSourceGlobalBounds = displayBounds
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
            localActivationTarget = .window(
                windowID: windowID,
                processID: processID,
                bundleIdentifier: bundleIdentifier,
                globalBounds: window.frame
            )
        }
        let profile = try Self.captureProfile(
            logicalWidth: captureWidth,
            logicalHeight: captureHeight
        )
        guard profile.width >= 320, profile.height >= 240 else {
            throw ScreenCaptureKitOpaqueTargetCatalogErrorV0.sourceDisappeared
        }
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
            focusedRegionFilter: focusedRegionFilter,
            descriptor: descriptor,
            profile: profile,
            sourceRect: sourceRect,
            focusedRegionSourceGlobalBounds:
                focusedRegionSourceGlobalBounds,
            inputBounds: inputBounds,
            inputBackingScaleFactor: inputBackingScaleFactor,
            localActivationTarget: localActivationTarget
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

    /// Main windows only, with the same minimum mode as native enrollment.
    /// This pure predicate is covered by the indexed picker cases.
    public static func isSelectableWindow(onScreen: Bool, layer: Int,
        width: Double, height: Double, scale: Double) -> Bool {
        guard onScreen, layer == 0, width.isFinite, height.isFinite,
              scale.isFinite, (1...4).contains(scale), width > 0, height > 0,
              width * scale <= 32768, height * scale <= 32768,
              let profile = try? captureProfile(logicalWidth: Int(ceil(width * scale)),
                  logicalHeight: Int(ceil(height * scale))) else { return false }
        return profile.width >= 320 && profile.height >= 240
    }

    private static func isSelectableWindow(_ window: SCWindow) -> Bool {
        let frame = window.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite else { return false }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1,
                  &displayID, &count) == .success, count == 1, displayID != 0,
              CGDisplayIsActive(displayID) != 0, CGDisplayRotation(displayID) == 0,
              let scale = try? backingScaleFactor(for: displayID) else { return false }
        return isSelectableWindow(onScreen: window.isOnScreen, layer: window.windowLayer,
            width: frame.width, height: frame.height, scale: scale)
    }

    private static func applicationViewAvailable(windows: [SCWindow],
        displayID: CGDirectDisplayID) -> Bool {
        guard let crop = try? ScreenCaptureKitApplicationCropV0(
                  windowGlobalBounds: windows.map(\.frame), sourceGlobalBounds: CGDisplayBounds(displayID)),
              let scale = try? backingScaleFactor(for: displayID),
              let profile = try? captureProfile(logicalWidth: Int(ceil(crop.globalBounds.width * scale)),
                  logicalHeight: Int(ceil(crop.globalBounds.height * scale))) else { return false }
        return profile.width >= 320 && profile.height >= 240
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
        // H.264/NV12 output is chroma-aligned. VideoToolbox can silently round
        // an odd requested size down; establish the exact encoded geometry
        // here, before the descriptor, capture, and encoder bind to it.
        let width = max(2, Int((Double(logicalWidth) * scale).rounded(.down)) / 2 * 2)
        let height = max(2, Int((Double(logicalHeight) * scale).rounded(.down)) / 2 * 2)
        return try ScreenCaptureKitCaptureProfileV0(
            width: width,
            height: height,
            framesPerSecond:
                ScreenCaptureKitCaptureProfileV0.maximumFramesPerSecond,
            queueDepth: ScreenCaptureKitCaptureProfileV0.maximumQueueDepth
        )
    }
}
