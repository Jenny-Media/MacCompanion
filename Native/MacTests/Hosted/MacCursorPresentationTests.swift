import AppKit
import SwiftUI
import XCTest
@testable import MacCompanion

private final class CursorPresentationTransport: CompanionVNCSession {
    var active = false
    private(set) var clicks = 0
    override var running: Bool { active }
    override var connected: Bool { active }
    override func connectAddresses(_ addresses: [String]!, port: Int, username: String!, password: String!) { active = true }
    override func stop() { active = false }
    override func pointerX(_ x: Int, y: Int, mask: Int) { if mask == 1 { clicks += 1 } }
    func ready() { stateHandler?("Connected", ["framebufferWidth": 100, "framebufferHeight": 100]) }
}

@MainActor final class MacCursorPresentationTests: XCTestCase {
    private func image(_ color: NSColor, width: Int = 12, height: Int = 18) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<height { for x in 0..<width { bitmap.setColor(color, atX: x, y: y) } }
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(bitmap); return image
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Native AppKit focus/presentation did not settle")
    }
    private func window(_ input: NSView) -> NSWindow {
        NSApplication.shared.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(x: 60, y: 100, width: 500, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = input
        return window
    }
    private func surface(in view: NSView) -> MacVNCInputView? {
        if let input = view as? MacVNCInputView { return input }
        return view.subviews.lazy.compactMap { self.surface(in: $0) }.first
    }
    private func update(_ input: MacVNCInputView, _ session: MacVNCSession) {
        input.update(image: session.image, crop: session.crop, zoom: session.zoom, pan: session.pan,
                     enabled: session.canInput, cursorImage: session.cursorImage,
                     cursorHotspot: session.cursorHotspot, cursorPosition: session.cursorPosition)
    }
    private func cursorEvent(_ input: MacVNCInputView, point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: .cursorUpdate, location: input.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: try XCTUnwrap(input.window).windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }
    private func hint(_ input: MacVNCInputView) throws -> NSTextField {
        try XCTUnwrap(input.subviews.first { $0.accessibilityIdentifier() == "mac-vnc-control-hint" } as? NSTextField)
    }
    private func session(_ transport: CursorPresentationTransport, allowed: @escaping () -> Bool = { true }) -> MacVNCSession {
        let session = MacVNCSession(mac: .init(id: UUID(), name: "Synthetic cursor", addresses: ["fixture.local"]),
            removeSavedLogin: { _ in }, makeTransport: { transport }, canAccess: allowed)
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        transport.ready(); transport.frameHandler?(NSImage(size: NSSize(width: 100, height: 100)))
        return session
    }
    func testArrowFallbackAndRemoteShapeApplyOnlyToFocusedCanvas() async throws {
        let transport = CursorPresentationTransport(), session = session(transport)
        let input = MacVNCInputView(session: session), window = window(input)
        defer { input.detach(); window.close(); session.close(); NSCursor.arrow.set() }
        NSApplication.shared.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        try await wait { NSApplication.shared.isActive && window.isKeyWindow }
        update(input, session)
        XCTAssertTrue(window.makeFirstResponder(input))
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow, "Missing server shapes use the normal arrow, never a crosshair")
        let shape = try image(.red), hotspot = CGPoint(x: 3, y: 5)
        transport.cursorHandler?(shape, hotspot, .zero, false); update(input, session)
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertEqual(NSCursor.current.hotSpot, hotspot)
        XCTAssertTrue(NSCursor.current.image === shape)
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 20, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow, "Letterboxing must not advertise remote control")
        XCTAssertTrue(window.makeFirstResponder(nil))
        try await wait { (try? self.hint(input).isHidden) == false }
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        XCTAssertEqual(try hint(input).stringValue, "Click to control")
        let labelPoint = CGPoint(x: try hint(input).frame.midX, y: try hint(input).frame.midY)
        XCTAssertTrue(input.hitTest(labelPoint) === input, "Readiness feedback must not intercept activation clicks")
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: input.convert(CGPoint(x: 250, y: 120), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        input.mouseDown(with: click)
        XCTAssertEqual(transport.clicks, 1); XCTAssertTrue(try hint(input).isHidden)
        input.mouseUp(with: click)
        let localField = NSTextField(frame: CGRect(x: 200, y: 40, width: 100, height: 24))
        input.addSubview(localField)
        NSCursor.iBeam.set()
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 50)))
        XCTAssertTrue(NSCursor.current === NSCursor.iBeam, "A covered desktop must not replace a local control's cursor")
        localField.removeFromSuperview()
    }
    func testStationaryPointerReceivesShapeOnlyUpdatesWithoutTakingOtherWindowsCursor() async throws {
        let transport = CursorPresentationTransport(), session = session(transport)
        let host = NSHostingView(rootView: MacVNCSurface(session: session))
        let window = window(host)
        defer { window.close(); session.close(); NSCursor.arrow.set() }
        try await wait { host.layoutSubtreeIfNeeded(); return self.surface(in: host) != nil }
        let input = try XCTUnwrap(surface(in: host))
        let originalMouse = try XCTUnwrap(CGEvent(source: nil)).location
        defer { CGWarpMouseCursorPosition(originalMouse); input.detach(); window.close(); session.close(); NSCursor.arrow.set() }
        NSApplication.shared.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        update(input, session); XCTAssertTrue(window.makeFirstResponder(input))
        try await wait { NSApplication.shared.isActive && window.isKeyWindow }
        let screenPoint = window.convertPoint(toScreen: input.convert(CGPoint(x: 250, y: 120), to: nil))
        let primary = try XCTUnwrap(NSScreen.screens.first)
        XCTAssertEqual(CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x, y: primary.frame.maxY - screenPoint.y)), .success)
        try await wait { NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber }
        let first = try image(.red), second = try image(.green, width: 8, height: 16)
        transport.cursorHandler?(first, CGPoint(x: 3, y: 5), .zero, false); update(input, session)
        try await wait { NSCursor.current.image === first }
        let frame = session.image
        transport.cursorHandler?(second, CGPoint(x: 2, y: 4), .zero, false); update(input, session)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(NSCursor.current.image === second)
        XCTAssertEqual(NSCursor.current.hotSpot, CGPoint(x: 2, y: 4)); XCTAssertTrue(session.image === frame)
        transport.cursorHandler?(nil, .zero, .zero, false); update(input, session)
        try await wait { NSCursor.current === NSCursor.arrow }
        XCTAssertNil(session.cursorImage, "An empty server cursor clears the previous shape without mouse movement")
        XCTAssertTrue(session.image === frame)
        let other = NSWindow(contentRect: CGRect(x: 620, y: 100, width: 200, height: 200),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; defer { other.close() }
        other.makeKeyAndOrderFront(nil); try await wait { other.isKeyWindow }
        NSCursor.iBeam.set()
        transport.cursorHandler?(first, .zero, .zero, false); update(input, session)
        XCTAssertTrue(NSCursor.current === NSCursor.iBeam, "Background reports must not replace another window's cursor")
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.iBeam, "A stale event cannot take another window's cursor")
    }
    func testLockDetachAndRetiredTransportCannotKeepRemoteCursorActive() async throws {
        var allowed = true
        let transport = CursorPresentationTransport(), session = session(transport, allowed: { allowed })
        let input = MacVNCInputView(session: session), window = window(input)
        defer { input.detach(); window.close(); session.close(); NSCursor.arrow.set() }
        NSApplication.shared.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        update(input, session); window.makeFirstResponder(input)
        try await wait { NSApplication.shared.isActive && window.isKeyWindow }
        let shape = try image(.blue)
        let retired = try XCTUnwrap(transport.cursorHandler)
        retired(shape, CGPoint(x: 1, y: 1), .zero, false); update(input, session)
        allowed = false; session.pauseInput(); update(input, session)
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        XCTAssertEqual(try hint(input).stringValue, "Unlock Mac Companion to control")
        allowed = true; update(input, session)
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current.image === shape)
        session.disconnect(); retired(shape, .zero, .zero, false); update(input, session)
        XCTAssertNil(session.cursorImage)
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        session.connect(username: "synthetic", password: "synthetic-only", remember: false); transport.ready()
        XCTAssertNil(session.cursorImage, "Reconnect starts with arrow until a fresh shape arrives")
        input.detach()
        input.cursorUpdate(with: try cursorEvent(input, point: CGPoint(x: 250, y: 120)))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow); XCTAssertTrue(try hint(input).isHidden)
    }
}
