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
                  count == 1, display != 0 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            physicalDisplayID = display
        case let .application(processID, bundleIdentifier):
            surfaceKind = .application; windowID = 0; self.processID = processID; self.bundleIdentifier = bundleIdentifier
            guard selectedPhysicalDisplayID != 0 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            physicalDisplayID = selectedPhysicalDisplayID
        default:
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated,
              application.bundleIdentifier == bundleIdentifier, let launch = application.launchDate,
              let milliseconds = UInt64(exactly: (launch.timeIntervalSince1970 * 1000).rounded(.down)), milliseconds > 0 else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        processLaunchMilliseconds = milliseconds
        guard backingScale >= 1, backingScale <= 4, isCurrent else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    }

    /// Synchronous live check, also usable under the backend's bounded input permit.
    public var isCurrent: Bool {
        guard DispatchTime.now().uptimeNanoseconds / 1_000_000 < scope.expiresAtMonotonicMilliseconds,
              CGDisplayIsActive(physicalDisplayID) != 0, CGDisplayRotation(physicalDisplayID) == 0,
              let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated,
              application.bundleIdentifier == bundleIdentifier, let launch = application.launchDate,
              (launch.timeIntervalSince1970 * 1000).rounded(.down) == Double(processLaunchMilliseconds),
              (try? ScreenCaptureKitOpaqueTargetCatalogV0.backingScaleFactor(for: physicalDisplayID)) == backingScale else { return false }
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        if windowID != 0 {
            guard let frame = MacSelectedWindowDescriptionV1.bounds(in: windows, windowID: windowID,
                                                                    processID: processID), frame == bounds else { return false }
            var display: CGDirectDisplayID = 0, count: UInt32 = 0
            return CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &count) == .success
                && count == 1 && display == physicalDisplayID
        }
        var visibleBounds: [CGRect] = []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  let object = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: object as CFDictionary) else { continue }
            visibleBounds.append(frame)
        }
        return (try? ScreenCaptureKitApplicationCropV0(windowGlobalBounds: visibleBounds,
            sourceGlobalBounds: CGDisplayBounds(physicalDisplayID)).globalBounds) == bounds
    }

    public func contextData(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0) throws -> Data {
        guard try scope.binding() == authority.binding, try scope.surface() == authority.surface,
              try scope.sessionPublicKeyX963() == authority.sessionPublicKeyX963,
              isCurrent, scope.expiresAtMonotonicMilliseconds <= UInt64.max / 1_000_000 else {
            throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
        }
        return try Self.encodeContext(operationID: operationID, kind: surfaceKind.rawValue, physicalDisplayID: physicalDisplayID,
            windowID: windowID, processID: processID, bundleIdentifier: bundleIdentifier,
            processLaunchMilliseconds: processLaunchMilliseconds, bounds: bounds, backingScale: backingScale,
            geometry: geometry, expiryNanoseconds: scope.expiresAtMonotonicMilliseconds * 1_000_000)
    }

    package static func encodeContext(operationID: UUID, kind: String, physicalDisplayID: UInt32,
        windowID: UInt32, processID: pid_t, bundleIdentifier: String, processLaunchMilliseconds: UInt64,
        bounds: CGRect, backingScale: Double, geometry: InteractiveNativeVideoContentGeometryV0,
        expiryNanoseconds: UInt64) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: [
            "profile": "maccompanion.selected-capture-context.v0.1", "operationID": operationID.uuidString,
            "kind": kind, "displayID": physicalDisplayID, "windowID": windowID, "processID": processID,
            "bundleIdentifier": bundleIdentifier, "processLaunchMilliseconds": processLaunchMilliseconds,
            "expiresAtMonotonicNanoseconds": expiryNanoseconds, "boundsX": bounds.origin.x, "boundsY": bounds.origin.y,
            "boundsWidth": bounds.width, "boundsHeight": bounds.height, "backingScale": backingScale,
            "sourcePixelWidth": geometry.capturePixelWidth, "sourcePixelHeight": geometry.capturePixelHeight,
            "encodedWidth": geometry.encodedWidth, "encodedHeight": geometry.encodedHeight,
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 4096 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        return data
    }
}
#endif
