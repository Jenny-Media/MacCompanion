import AppKit
import SwiftUI
import XCTest
@testable import MacCompanion

@MainActor final class QuickActionLayoutTests: XCTestCase {
    func testShortcutRecorderOnlyCapturesWhileFocusedAndKeepsTerminalKeysCompatible() throws {
        let capture = DirectShortcutRecorder.Capture()
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = capture
        defer { capture.recorded = nil; window.contentView = nil; window.close() }
        var records: [(UInt32?, [UInt32])] = []
        capture.recorded = { records.append(($0, $1)) }
        XCTAssertTrue(window.makeFirstResponder(capture))
        func event(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        }
        XCTAssertTrue(capture.performKeyEquivalent(with: try event(8, "c", .command)))
        XCTAssertEqual(records.last?.0, 0x63); XCTAssertEqual(records.last?.1, [0xffeb])
        capture.mode = .terminal
        capture.keyDown(with: try event(8, "c", .control))
        XCTAssertEqual(records.last?.0, 0x63); XCTAssertEqual(records.last?.1, [0xffe3])
        XCTAssertTrue(VNCQuickAction(title: "Synthetic", kind: .shortcut, key: records.last!.0!, modifiers: records.last!.1).compatible(with: .terminal))
        capture.keyDown(with: try event(53, "", [])); XCTAssertNil(records.last?.0, "Escape cancels recording")
        let count = records.count
        window.makeFirstResponder(nil)
        XCTAssertFalse(capture.performKeyEquivalent(with: try event(8, "c", .command)))
        XCTAssertEqual(records.count, count, "An unfocused recorder cannot steal app shortcuts")
    }

    func testBothMacControlEditorsFitTheirWindowAndCaptureSyntheticLayouts() async throws {
        let previous = DirectAppearanceV1.shared.app
        defer { DirectAppearanceV1.shared.app = previous }
        for mode in [DirectControlMode.desktop, .terminal] {
            for appearance in [DirectAppAppearance.light, .dark] {
                DirectAppearanceV1.shared.app = appearance
                let host = NSHostingView(rootView: MacDesktopSettings(mode: mode))
                let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 820, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                defer { window.contentView = nil; window.close() }
                try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 820, accuracy: 1)
                XCTAssertEqual(host.fittingSize.height, 680, accuracy: 1)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image); attachment.name = "mac-quick-actions-" + mode.rawValue + "-" + appearance.rawValue
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
