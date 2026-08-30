#if os(macOS)
import AppKit
import ApplicationServices
import CompanionHostPlatform
import CoreGraphics
import Foundation

public enum MacInteractiveSelectedSurfaceActivatorErrorV1:
    Error, Equatable, Sendable
{
    case invalidTarget
    case activationFailed
    case verificationFailed
}

/// Raises and verifies the exact local app/window selected for Interactive
/// Control before its replacement surface can become active. The identity is
/// ephemeral and local to the menu process; no PID, window ID, AX element, or
/// title crosses IPC.
@available(macOS 14.0, *)
public struct MacInteractiveSelectedSurfaceActivatorV1: Sendable {
    public typealias PerformActivation = @MainActor @Sendable (
        ScreenCaptureKitLocalActivationTargetV0
    ) -> Bool
    public typealias VerifyActivation = @MainActor @Sendable (
        ScreenCaptureKitLocalActivationTargetV0
    ) -> Bool
    public typealias Wait = @MainActor @Sendable () async throws -> Void

    private let performActivation: PerformActivation
    private let verifyActivation: VerifyActivation
    private let wait: Wait
    private let maximumVerificationAttempts: Int

    public init() {
        performActivation = { Self.performSystemActivation($0) }
        verifyActivation = { Self.verifySystemActivation($0) }
        wait = { try await Task.sleep(for: .milliseconds(20)) }
        maximumVerificationAttempts = 25
    }

    package init(
        performActivation: @escaping PerformActivation,
        verifyActivation: @escaping VerifyActivation,
        maximumVerificationAttempts: Int = 25,
        wait: @escaping Wait = {
            try await Task.sleep(for: .milliseconds(20))
        }
    ) {
        self.performActivation = performActivation
        self.verifyActivation = verifyActivation
        self.maximumVerificationAttempts = maximumVerificationAttempts
        self.wait = wait
    }

    public func activate(
        _ target: ScreenCaptureKitLocalActivationTargetV0?
    ) async throws {
        guard let target else { return }
        guard Self.isValid(target), maximumVerificationAttempts > 0 else {
            throw MacInteractiveSelectedSurfaceActivatorErrorV1.invalidTarget
        }
        guard await performActivation(target) else {
            throw MacInteractiveSelectedSurfaceActivatorErrorV1
                .activationFailed
        }
        for attempt in 0..<maximumVerificationAttempts {
            if await verifyActivation(target) { return }
            if attempt + 1 < maximumVerificationAttempts {
                try await wait()
            }
        }
        throw MacInteractiveSelectedSurfaceActivatorErrorV1
            .verificationFailed
    }

    private static func isValid(
        _ target: ScreenCaptureKitLocalActivationTargetV0
    ) -> Bool {
        switch target {
        case let .application(processID, bundleIdentifier):
            return processID > 0 && !bundleIdentifier.isEmpty
        case let .window(windowID, processID, bundleIdentifier, bounds):
            return windowID > 0 && processID > 0
                && !bundleIdentifier.isEmpty && valid(bounds)
        }
    }

    @MainActor
    private static func performSystemActivation(
        _ target: ScreenCaptureKitLocalActivationTargetV0
    ) -> Bool {
        let identity = applicationIdentity(target)
        guard let application = NSRunningApplication(
            processIdentifier: identity.processID
        ), application.bundleIdentifier == identity.bundleIdentifier else {
            return false
        }
        guard application.activate(options: [.activateAllWindows]) else {
            return false
        }
        guard case let .window(
            windowID,
            processID,
            bundleIdentifier,
            globalBounds
        ) = target else { return true }
        guard revalidateWindow(
            windowID: windowID,
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            globalBounds: globalBounds
        ), AXIsProcessTrusted() else { return false }
        let applicationElement = AXUIElementCreateApplication(processID)
        guard let window = uniqueWindow(
            application: applicationElement,
            globalBounds: globalBounds
        ) else { return false }
        let raised = AXUIElementPerformAction(
            window,
            kAXRaiseAction as CFString
        ) == .success
        let focused = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window
        ) == .success
        return raised || focused
    }

    @MainActor
    private static func verifySystemActivation(
        _ target: ScreenCaptureKitLocalActivationTargetV0
    ) -> Bool {
        let identity = applicationIdentity(target)
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == identity.processID,
              frontmost.bundleIdentifier == identity.bundleIdentifier else {
            return false
        }
        guard case let .window(
            windowID,
            processID,
            bundleIdentifier,
            globalBounds
        ) = target else { return true }
        guard revalidateWindow(
            windowID: windowID,
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            globalBounds: globalBounds
        ) else { return false }
        let applicationElement = AXUIElementCreateApplication(processID)
        guard let expected = uniqueWindow(
            application: applicationElement,
            globalBounds: globalBounds
        ), let focused = copyElement(
            kAXFocusedWindowAttribute,
            from: applicationElement
        ) else { return false }
        return CFEqual(expected, focused)
    }

    private static func applicationIdentity(
        _ target: ScreenCaptureKitLocalActivationTargetV0
    ) -> (processID: pid_t, bundleIdentifier: String) {
        switch target {
        case let .application(processID, bundleIdentifier):
            (processID, bundleIdentifier)
        case let .window(_, processID, bundleIdentifier, _):
            (processID, bundleIdentifier)
        }
    }

    @MainActor
    private static func uniqueWindow(
        application: AXUIElement,
        globalBounds: CGRect
    ) -> AXUIElement? {
        guard let value = copy(kAXWindowsAttribute, from: application),
              let windows = value as? [AXUIElement] else { return nil }
        let matches = windows.filter {
            guard let bounds = windowBounds($0) else { return false }
            return approximatelyEqual(bounds, globalBounds)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    @MainActor
    private static func revalidateWindow(
        windowID: CGWindowID,
        processID: pid_t,
        bundleIdentifier: String,
        globalBounds: CGRect
    ) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: processID
        ), application.bundleIdentifier == bundleIdentifier,
              let descriptions = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                windowID
              ) as? [[String: Any]],
              descriptions.count == 1,
              let owner = descriptions[0][kCGWindowOwnerPID as String]
                as? NSNumber,
              owner.int32Value == processID,
              let bounds = descriptions[0][kCGWindowBounds as String]
                as? [String: Any] else { return false }
        var actual = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(
            bounds as CFDictionary,
            &actual
        ) else {
            return false
        }
        return approximatelyEqual(actual, globalBounds)
    }

    @MainActor
    private static func windowBounds(_ window: AXUIElement) -> CGRect? {
        guard let positionValue = copy(kAXPositionAttribute, from: window),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = copy(kAXSizeAttribute, from: window),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAX = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAX = unsafeDowncast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        let bounds = CGRect(origin: position, size: size)
        return valid(bounds) ? bounds : nil
    }

    @MainActor
    private static func copy(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value
    }

    @MainActor
    private static func copyElement(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copy(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
    }

    private static func valid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
    }
}
#endif
