#if !DEBUG
#error("Real Mac lab is test-only")
#endif
import AppKit
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum RealMacLabError: Error { case permissionsRequired, targetUnavailable, inputOutsideTestContract }

enum RealMacInputContract {
    static func validate(_ payload: InteractiveInputPayload) throws {
        switch payload {
        case .pointerMove, .reset: break
        case .button(let button, _) where button == .primary: break
        case .physicalKey(let usage, _, let modifiers) where usage == 0x28 && modifiers.isEmpty: break
        case .text(let text) where !text.isEmpty && text.utf8.count <= 64 && text.allSatisfy({ "hello worldabc ".contains($0) }): break
        default: throw RealMacLabError.inputOutsideTestContract
        }
    }
}

/// Results come from AppKit receiving events, never from the sending socket.
final class RealMacFeedback: @unchecked Sendable {
    private let lock = NSLock()
    private var events = 0
    private var text = ""
    private var buttons = 0
    private var returns = 0
    func received(button: Bool, returnKey: Bool) {
        lock.withLock { events += 1; buttons += button ? 1 : 0; returns += returnKey ? 1 : 0 }
    }
    func changed(_ value: String) {
        lock.withLock { text = value }
        FileHandle.standardError.write(Data("REAL_MAC_TEXT_RECEIVED count=\(value.count) composedMatch=\(value.hasPrefix("hello world"))\n".utf8))
    }
    func reset() { lock.withLock { events = 0; text = ""; buttons = 0; returns = 0 } }
    func snapshot() -> (Int, Bool, Bool, Bool, Bool) {
        lock.withLock { (events, text.hasPrefix("hello world"), text == "hello worldabc ", buttons >= 2, returns >= 2 && text.hasSuffix("\n")) }
    }
}

private let labEventMarker: Int64 = 0x4D434C4142

@MainActor private final class LabApplication: NSApplication {
    var targetWindow: NSWindow?
    var targetEditor: NSTextView?
    var feedback: RealMacFeedback?
    override func sendEvent(_ event: NSEvent) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) == labEventMarker else {
            super.sendEvent(event); return
        }
        guard let window = targetWindow, let editor = targetEditor, window.isVisible else { return }
        feedback?.received(button: event.type == .leftMouseDown || event.type == .leftMouseUp,
                           returnKey: (event.type == .keyDown || event.type == .keyUp) && event.keyCode == 36)
        // The OS delivers to this process. Dispatch only into our test editor,
        // never menu commands, other windows, or the globally focused app.
        switch event.type {
        case .keyDown:
            FileHandle.standardError.write(Data("REAL_MAC_KEY_RECEIVED characters=\(event.characters?.count ?? 0) keyWindow=\(window.isKeyWindow) firstResponder=\(window.firstResponder === editor)\n".utf8))
            // XCTest keeps the Simulator foreground, so AppKit's default key
            // interpretation ignores this inactive window. This controlled
            // target consumes OS-delivered characters through NSTextInputClient;
            // no socket payload is ever inserted into the editor directly.
            if event.keyCode == 36 { editor.insertNewline(nil) }
            else if let text = event.characters, !text.isEmpty {
                editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            feedback?.changed(editor.string)
        case .keyUp: editor.keyUp(with: event)
        case .leftMouseDown: window.makeFirstResponder(editor)
        default: break
        }
    }
}

@MainActor private final class LabWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class LabTextView: NSTextView {
    let feedback: RealMacFeedback
    init(feedback: RealMacFeedback) {
        self.feedback = feedback
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 641, height: 361))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: 641, height: 361), textContainer: container)
        isEditable = true; isSelectable = true
        isRichText = false; isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = .monospacedSystemFont(ofSize: 24, weight: .regular)
        textColor = .black; backgroundColor = .white
        textContainerInset = NSSize(width: 24, height: 140)
    }
    required init?(coder: NSCoder) { fatalError("No archive loading") }
    override func didChangeText() { super.didChangeText(); feedback.changed(string) }
}

/// Owns one fixed disposable window. Its identity is never supplied by a peer.
@MainActor final class RealMacTarget {
    nonisolated let feedback = RealMacFeedback()
    nonisolated let input: RealMacInputPoster
    let window: NSWindow
    private let editor: LabTextView
    private var pulse: Timer?
    private var tick = 0

    static func preflight() -> Bool {
        // Fault injection can only deny; it never supplies permission.
        if ProcessInfo.processInfo.environment["MACCOMPANION_LAB_DENY_PERMISSIONS"] == "1" {
            print("REAL_MAC_PREFLIGHT injected-denial")
            return false
        }
        let capture = CGPreflightScreenCaptureAccess()
        let input = CGPreflightPostEventAccess()
        print("REAL_MAC_PREFLIGHT capture=\(capture) input=\(input)")
        return capture && input
    }

    init() throws {
        guard Self.preflight() else { throw RealMacLabError.permissionsRequired }
        let app = LabApplication.shared as! LabApplication
        app.setActivationPolicy(.accessory)
        window = LabWindow(contentRect: NSRect(x: 80, y: 80, width: 641, height: 361),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Mac Companion — disposable capture and input test"
        window.isReleasedWhenClosed = false
        editor = LabTextView(feedback: feedback)
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        app.targetWindow = window; app.targetEditor = editor; app.feedback = feedback
        guard let screen = NSScreen.screens.first else { throw RealMacLabError.targetUnavailable }
        let rect = CGRect(x: window.frame.minX, y: screen.frame.maxY - window.frame.maxY, width: 641, height: 361)
        input = RealMacInputPoster(windowID: CGWindowID(window.windowNumber), bounds: rect)
        // Change only synthetic content so the compositor emits real frames.
        pulse = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                self.editor.backgroundColor = NSColor(calibratedRed: 1, green: 0.82 + Double(self.tick % 15) / 100, blue: 0.82, alpha: 1)
                self.editor.needsDisplay = true
            }
        }
    }

    func reset() { editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0)); feedback.reset() }

    func captureSession(profile: ScreenCaptureKitCaptureProfileV0, focused: Bool) async throws -> ScreenCaptureKitStreamingSessionAdapterV0 {
        guard CGPreflightScreenCaptureAccess(), window.isVisible else { throw RealMacLabError.targetUnavailable }
        let id = CGWindowID(window.windowNumber)
        return try await Self.makeCaptureSession(id: id, profile: profile, focused: focused)
    }
    private nonisolated static func makeCaptureSession(id: CGWindowID, profile: ScreenCaptureKitCaptureProfileV0, focused: Bool) async throws -> ScreenCaptureKitStreamingSessionAdapterV0 {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let owned = content.windows.first(where: {
            $0.windowID == id && $0.owningApplication?.processID == getpid()
        }) else { throw RealMacLabError.targetUnavailable }
        return ScreenCaptureKitStreamingSessionAdapterV0(
            filter: SCContentFilter(desktopIndependentWindow: owned), profile: profile,
            sourceRect: focused ? CGRect(x: 160, y: 60, width: 321, height: 241) : nil)
    }
}

private final class EventBatch: CoreGraphicsConstructedEventSinkV0 {
    var events: [CGEvent] = []
    func receiveConstructedEvent(_ event: CGEvent) { events.append(event) }
}

/// Production planning/construction, but posting only to this disposable PID.
/// No global HID posting path and no peer-selected process/window identifiers.
final class RealMacInputPoster: @unchecked Sendable {
    private let lock = NSLock()
    private let windowID: CGWindowID
    private let bounds: CGRect
    private var configuration: (InteractiveCommandFence, MacDisplayGeometrySnapshotV0)?
    private var planner = MacInteractiveInputPlannerV0()
    private var cursor: CGPoint
    init(windowID: CGWindowID, bounds: CGRect) {
        self.windowID = windowID; self.bounds = bounds
        cursor = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    func configure(lease: InteractiveExecutionLease, descriptor: AdaptiveSurfaceDescriptor) throws {
        try lock.withLock {
            let rect = descriptor.kind == .focusedRegion
                ? CGRect(x: bounds.minX + 160, y: bounds.minY + 60, width: 321, height: 241) : bounds
            let fence = InteractiveCommandFence(leaseID: lease.leaseID, hostID: lease.hostID, deviceID: lease.deviceID,
                interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
                selectedDisplayID: lease.selectedDisplayID, surfaceID: lease.surfaceID,
                surfaceRevision: lease.surfaceRevision, coordinateRevision: lease.coordinateRevision)
            configuration = (fence, try .init(selectedDisplayID: lease.selectedDisplayID, coordinateRevision: lease.coordinateRevision,
                logicalBounds: rect, backingScaleFactor: 1, rotation: .degrees0))
            cursor = CGPoint(x: rect.midX, y: rect.midY)
        }
    }
    func post(_ envelope: InteractiveInputEnvelope) throws {
        try lock.withLock {
            guard let (fence, geometry) = configuration,
                  envelope.interactiveSessionID.rawValue == fence.interactiveSessionID,
                  envelope.surfaceID.rawValue == fence.surfaceID,
                  envelope.surfaceRevision.rawValue == fence.surfaceRevision.rawValue,
                  envelope.coordinateSpaceRevision.rawValue == fence.coordinateRevision.rawValue,
                  envelope.authorizationEpoch == fence.authorizationEpoch else { throw RealMacLabError.targetUnavailable }
            try RealMacInputContract.validate(envelope.input)
            var next = planner
            try deliver(next.plan(envelope.input), fence: fence, geometry: geometry)
            planner = next
        }
    }
    func release() throws {
        try lock.withLock {
            guard let (fence, geometry) = configuration else { return }
            var next = planner
            try deliver(next.releaseAll(), fence: fence, geometry: geometry)
            planner = next
        }
    }
    private func deliver(_ descriptions: [MacInteractiveInputEventV0], fence: InteractiveCommandFence, geometry: MacDisplayGeometrySnapshotV0) throws {
        guard CGPreflightPostEventAccess() else { throw RealMacLabError.permissionsRequired }
        let batch = EventBatch()
        try CoreGraphicsNoPostInputConstructorV0().construct(descriptions, fence: fence, geometry: geometry, currentCursorPosition: cursor, sink: batch)
        for event in batch.events {
            event.setIntegerValueField(.eventSourceUserData, value: labEventMarker)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.postToPid(getpid())
            if event.type == .mouseMoved { cursor = event.location }
        }
    }
}
