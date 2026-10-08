#if os(macOS)
import AppKit
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CoreGraphics
import Foundation

/// Match an exact on-screen window identity. Callers obtain descriptions with
/// `.optionOnScreenOnly`; `.optionIncludingWindow` alone is not a valid query.
@available(macOS 14.0, *)
package enum MacSelectedWindowDescriptionV1 {
    package static func bounds(in descriptions: [[String: Any]], windowID: CGWindowID,
                               processID: pid_t) -> CGRect? {
        var matched: CGRect?
        for description in descriptions {
            guard (description[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID else { continue }
            guard matched == nil,
                  (description[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  let object = description[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: object as CFDictionary) else { return nil }
            matched = frame
        }
        return matched
    }

    package static func applicationBounds(in descriptions: [[String: Any]], processID: pid_t,
                                         displayBounds: CGRect) -> CGRect? {
        let frames = descriptions.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let object = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: object as CFDictionary) else { return nil }
            return frame
        }
        return try? ScreenCaptureKitApplicationCropV0(windowGlobalBounds: frames,
            sourceGlobalBounds: displayBounds).globalBounds
    }
}

/// Menu-local projection for the exact owned child. Deliberately not Codable:
/// physical metadata is never accepted from Agent IPC or a remote request.
@available(macOS 14.0, *)
public struct MacManagedNativeSelectedCaptureV1: Equatable, Sendable {
    public let geometry: InteractiveNativeVideoContentGeometryV0
    public let physicalDisplayID: UInt32
    public let surfaceKind: InteractiveSurfaceKind
    private let scope: LocalInteractiveNativeBackendScopeV1
    private let windowID: UInt32
    private let processID: pid_t
    private let bundleIdentifier: String
    private let processLaunchMilliseconds: UInt64
    private let bounds: CGRect
    private let backingScale: Double

    public init(surface: ScreenCaptureKitResolvedSurfaceV0,
                scope: LocalInteractiveNativeBackendScopeV1,
                selectedPhysicalDisplayID: UInt32) throws {
        geometry = try MacInteractiveNativeCaptureGeometryV1.readSelectedSurface(surface, scope: scope)
        self.scope = scope
        bounds = surface.inputBounds
        backingScale = surface.inputBackingScaleFactor
        switch surface.localActivationTarget {
        case let .window(windowID, processID, bundleIdentifier, _):
            surfaceKind = .window; self.windowID = windowID; self.processID = processID; self.bundleIdentifier = bundleIdentifier
            var display: CGDirectDisplayID = 0, count: UInt32 = 0
            guard CGGetDisplaysWithPoint(CGPoint(x: bounds.midX, y: bounds.midY), 1, &display, &count) == .success,
                  count == 1, display != 0 else { throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.captureWindowDisplay) }
            physicalDisplayID = display
        case let .application(processID, bundleIdentifier):
            surfaceKind = .application; windowID = 0; self.processID = processID; self.bundleIdentifier = bundleIdentifier
            guard selectedPhysicalDisplayID != 0 else { throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.captureApplicationDisplay) }
            physicalDisplayID = selectedPhysicalDisplayID
        default:
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.captureKind)
        }
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated,
              application.bundleIdentifier == bundleIdentifier, let launch = application.launchDate,
              let milliseconds = UInt64(exactly: (launch.timeIntervalSince1970 * 1000).rounded(.down)), milliseconds > 0 else {
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.captureApplicationIdentity)
        }
        processLaunchMilliseconds = milliseconds
        guard backingScale >= 1, backingScale <= 4 else {
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.captureScale)
        }
        if let failure = validationFailure {
            let reason: MacNativeFailureDiagnosticsV1.SelectionRejection
            switch failure {
            case .expired: reason = .liveExpired
            case .display: reason = .liveDisplay
            case .application: reason = .liveApplication
            case .scale: reason = .liveScale
            case .windowInventory: reason = .liveWindowInventory
            case .windowIdentity: reason = .liveWindowIdentity
            case .windowGeometry: reason = .liveWindowGeometry
            case .windowDisplay: reason = .liveWindowDisplay
            case .applicationGeometry: reason = .liveApplicationGeometry
            }
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(reason)
        }
    }

    /// Synchronous live check, also usable under the backend's bounded input permit.
    public var isCurrent: Bool {
        validationFailure == nil
    }

    /// Closed, content-free reasons. Never emit window/process identities,
    /// titles, bounds, application identifiers or input in diagnostics.
    package enum ValidationFailure: Int, CaseIterable, Sendable {
        case expired = 1, display = 2, application = 3, scale = 4
        case windowInventory = 5, windowIdentity = 6, windowGeometry = 7
        case windowDisplay = 8, applicationGeometry = 9
    }
    package var validationFailure: ValidationFailure? {
        guard DispatchTime.now().uptimeNanoseconds / 1_000_000 < scope.expiresAtMonotonicMilliseconds else { return .expired }
        guard CGDisplayIsActive(physicalDisplayID) != 0, CGDisplayRotation(physicalDisplayID) == 0 else { return .display }
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated,
              application.bundleIdentifier == bundleIdentifier, let launch = application.launchDate,
              (launch.timeIntervalSince1970 * 1000).rounded(.down) == Double(processLaunchMilliseconds) else { return .application }
        guard (try? ScreenCaptureKitOpaqueTargetCatalogV0.backingScaleFactor(for: physicalDisplayID)) == backingScale else { return .scale }
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return .windowInventory }
        if windowID != 0 {
            guard let frame = MacSelectedWindowDescriptionV1.bounds(in: windows, windowID: windowID,
                                                                    processID: processID) else { return .windowIdentity }
            guard frame == bounds else { return .windowGeometry }
            var display: CGDirectDisplayID = 0, count: UInt32 = 0
            guard CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &count) == .success,
                  count == 1, display == physicalDisplayID else { return .windowDisplay }
            return nil
        }
        guard MacSelectedWindowDescriptionV1.applicationBounds(in: windows, processID: processID,
            displayBounds: CGDisplayBounds(physicalDisplayID)) == bounds else { return .applicationGeometry }
        return nil
    }

    public func contextData(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
                            frameEpoch: Data? = nil) throws -> Data {
        guard try scope.binding() == authority.binding, try scope.surface() == authority.surface,
              try scope.sessionPublicKeyX963() == authority.sessionPublicKeyX963,
              isCurrent, scope.expiresAtMonotonicMilliseconds <= UInt64.max / 1_000_000 else {
            throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
        }
        return try Self.encodeContext(operationID: operationID, kind: surfaceKind.rawValue, physicalDisplayID: physicalDisplayID,
            windowID: windowID, processID: processID, bundleIdentifier: bundleIdentifier,
            processLaunchMilliseconds: processLaunchMilliseconds, bounds: bounds, backingScale: backingScale,
            geometry: geometry, expiryNanoseconds: scope.expiresAtMonotonicMilliseconds * 1_000_000, frameEpoch: frameEpoch)
    }

    package static func encodeContext(operationID: UUID, kind: String, physicalDisplayID: UInt32,
        windowID: UInt32, processID: pid_t, bundleIdentifier: String, processLaunchMilliseconds: UInt64,
        bounds: CGRect, backingScale: Double, geometry: InteractiveNativeVideoContentGeometryV0,
        expiryNanoseconds: UInt64, frameEpoch: Data? = nil) throws -> Data {
        guard frameEpoch == nil || frameEpoch?.count == 48 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        var record: [String: Any] = [
            "profile": frameEpoch == nil ? "maccompanion.selected-capture-context.v0.1" : "maccompanion.selected-capture-context.v0.2", "operationID": operationID.uuidString,
            "kind": kind, "displayID": physicalDisplayID, "windowID": windowID, "processID": processID,
            "bundleIdentifier": bundleIdentifier, "processLaunchMilliseconds": processLaunchMilliseconds,
            "expiresAtMonotonicNanoseconds": expiryNanoseconds, "boundsX": bounds.origin.x, "boundsY": bounds.origin.y,
            "boundsWidth": bounds.width, "boundsHeight": bounds.height, "backingScale": backingScale,
            "sourcePixelWidth": geometry.capturePixelWidth, "sourcePixelHeight": geometry.capturePixelHeight,
            "encodedWidth": geometry.encodedWidth, "encodedHeight": geometry.encodedHeight,
        ]
        if let frameEpoch { record["frameEpochHex"] = frameEpoch.map { String(format: "%02x", $0) }.joined() }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 4096 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        return data
    }
}
#endif
