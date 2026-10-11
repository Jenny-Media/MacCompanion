import AppKit
import SwiftUI
import Observation
import XCTest
@testable import MacCompanion

@MainActor @Observable private final class ShortcutFieldDraft {
    var action = VNCQuickAction(title: "Synthetic", kind: .shortcut, key: 0x63, modifiers: [0xffeb])
}

@MainActor final class QuickActionLayoutTests: XCTestCase {
    func testShortcutCharacterCanBeClearedAndReplacedInTheNativeField() async throws {
        let draft = ShortcutFieldDraft()
        let host = NSHostingView(rootView: DirectQuickActionInspector(
            action: Binding(get: { draft.action }, set: { draft.action = $0 }), mode: .desktop).frame(width: 600, height: 400))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func update() async throws { try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        try await update()
        let field = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Letter or symbol" })
        XCTAssertTrue(window.makeFirstResponder(field))
        try await update()
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count)); editor.deleteBackward(nil)
        try await update()
        XCTAssertEqual(draft.action.key, 0)
        XCTAssertEqual(editor.string, "", "An invalid key must not put an invisible NUL into the native field")
        XCTAssertFalse(draft.action.shortcutTitle.unicodeScalars.contains { $0.value == 0 })
        editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await update()
        XCTAssertEqual(draft.action.key, 0x78)
        XCTAssertEqual(editor.string, "x"); XCTAssertTrue(draft.action.valid)
        draft.action.key = 0xff09
        try await update()
        draft.action.key = 0 // Selecting Character after a special key starts empty.
        try await update()
        XCTAssertEqual(editor.string, "")
        editor.insertText("k", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await update()
        XCTAssertEqual(draft.action.key, 0x6b); XCTAssertTrue(draft.action.valid)
    }

    func testNativeQuickActionsMenusRetainShortcutChordsWithoutRegisteringHostShortcuts() async throws {
        let actions = [VNCQuickAction(title: "Synthetic Copy", kind: .shortcut, key: 0x63, modifiers: [0xffeb]),
            VNCQuickAction(title: "⌘K", kind: .shortcut, key: 0x6b, modifiers: [0xffeb]),
            VNCQuickAction(title: "Right Click", kind: .rightClick)]
        var performed = 0
        let live = Menu("Quick Actions", systemImage: "keyboard") {
            MacQuickActionsMenu(actions: actions, perform: { _ in performed += 1 }, customize: {})
        }
        func check<V: View>(_ root: V) async throws {
            let menu = NSHostingMenu(rootView: root)
            menu.update(); try await Task.sleep(for: .milliseconds(100))
            let submenu = try XCTUnwrap(menu.items.first?.submenu)
            submenu.update(); try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(submenu.items.prefix(3).map(\.title), ["Synthetic Copy · ⌘C", "⌘K", "Right Click"])
            XCTAssertTrue(submenu.items.allSatisfy { $0.keyEquivalent.isEmpty }, "Remote shortcuts must not become host key equivalents")
        }
        try await check(live)
        try await check(live.labelStyle(.iconOnly))
        XCTAssertEqual(performed, 0, "Rendering the menu must not execute remote input")
    }

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
