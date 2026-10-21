import XCTest
import SwiftUI
import SwiftTerm
import StoreKitTest
import StoreKit
@testable import Mac_Companion

@MainActor private final class ControlsInputController: TerminalController {
    var output: [UInt8] = []
    var ready = true
    var epoch = UUID()
    override func viewDidLoad() {
        super.viewDidLoad()
        terminal.customInputEpoch = { [weak self] in self?.ready == true ? self?.epoch : nil }
        terminal.admitCustomInput = { [weak self] bytes in
            guard let self, ready else { return false }; output += bytes; return true
        }
        updateControls()
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { output += terminal.encodeOutput(data) }
}
@MainActor private final class ControlsFeedback: CompanionVNCInterfaceFeedback {
    var events: [String] = []
    override var foreground: Bool { true }
    override func emitFeedback(_ kind: String) { events.append(kind) }
}

@MainActor final class TerminalControlsUITests: XCTestCase {
    @Observable final class Draft { var profile = TerminalControlsProfile.defaults }
    private struct Fixtures: Decodable {
        struct Key: Decodable { let name: String; let flags: Int; let text: String?; let expectedHex: String }
        struct Paste: Decodable { let enable: String; let text: String; let expectedHex: String }
        let encodingCases: [Key]; let paste: Paste
    }
    private func fixtures() throws -> Fixtures {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "terminal-compatibility-v1", withExtension: "json"))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
    private func bytes(_ hex: String) throws -> [UInt8] {
        let characters = Array(hex)
        return try stride(from: 0, to: characters.count, by: 2).map { try XCTUnwrap(UInt8(String(characters[$0...($0 + 1)]), radix: 16)) }
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }
    private func capture(_ name: String, window: UIWindow) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func pro() async throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        DirectProAccess.shared.start(); _ = try await store.buyProduct(identifier: DirectProAccess.productID)
        for _ in 0..<250 {
            await DirectProAccess.shared.refresh()
            if DirectProAccess.shared.hasPro { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if !DirectProAccess.shared.hasPro {
            var verification = [String]()
            for await result in StoreKit.Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction): verification.append("verified \(transaction.productID), revoked=\(transaction.revocationDate != nil)")
                case .unverified(_, let error): verification.append("unverified: \(error.localizedDescription)")
                }
            }
            XCTFail("StoreKit test entitlement unavailable: " + verification.joined(separator: "; "))
            throw NSError(domain: "TerminalControlsUITests.StoreKit", code: 1)
        }
        return store
    }
    func testVisualEditorSelectsReordersAndEditsOneDraftWithoutSendingOrSaving() async throws {
        let draft = Draft()
        let saved = TerminalControlAction(title: "Project", kind: .text, text: "  synthetic\n", inRow: true)
        draft.profile.actions.append(saved)
        let originalRevision = draft.profile.revision
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack {
            ScrollView { TerminalControlsEditor(profile: Binding(get: { draft.profile }, set: { draft.profile = $0 })).padding(16) }
                .navigationTitle("Terminal Controls").navigationBarTitleDisplayMode(.inline)
        })
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let preview = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        XCTAssertTrue(preview.editingPreview); XCTAssertNil(preview.actionHandler)
        let choices = try XCTUnwrap(preview.value(forKey: "choices") as? [UIButton])
        let item = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "preview-action-" + saved.id.uuidString })
        item.sendActions(for: .touchUpInside)
        try await settle()
        XCTAssertEqual(preview.selectedPreviewID, saved.id.uuidString)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first)
        XCTAssertTrue(field.becomeFirstResponder())
        field.selectedRange = NSRange(location: 0, length: 0)
        field.insertText("中文😀\n")
        try await settle()
        XCTAssertEqual(draft.profile.actions.last?.text, "中文😀\n  synthetic\n")
        window.endEditing(true)
        preview.previewMoveHandler?(saved.id.uuidString, draft.profile.actions[0].id.uuidString)
        try await settle()
        XCTAssertEqual(draft.profile.placed(.menu).first?.id, saved.id)
        XCTAssertEqual(draft.profile.actions.filter { $0.id == saved.id }.count, 1)
        XCTAssertEqual(draft.profile.revision, originalRevision, "Draft editing never commits a storage revision")
        XCTAssertNil(preview.actionHandler, "The real menu renderer has no session input callback in editing mode")
        let normalHeight = preview.bounds.height
        capture("terminal-controls-editor", window: window)
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        try await settle()
        let largePreview = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        XCTAssertGreaterThan(largePreview.bounds.height, normalHeight * 2, "Dynamic Type remeasures the native preview instead of clipping larger actions into its old height")
        XCTAssertEqual(largePreview.selectedPreviewID, saved.id.uuidString)
        capture("terminal-controls-editor-accessibility", window: window)
    }
    func testFloatingMenuExposesKeysTextAndLibraryWithoutFnAndRetiresOldSelections() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let profile = TerminalControlsProfile.defaults
        let data = try JSONEncoder().encode(profile)
        let store = TerminalControlsStore(read: { data }, write: { _ in XCTFail("Rendering must not save controls") }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic Mac", addresses: ["127.0.0.1"]))
        session.connected = true
        var customizations = 0
        let controller = ControlsInputController(session: session, customize: { customizations += 1 }, controlsStore: store)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        controller.terminal.feed(text: "Synthetic terminal preview\r\nAll controls are in the floating menu.\r\n$ ")
        try await settle()
        XCTAssertFalse(descendants(controller.keyboardBar).compactMap { $0 as? UIButton }.contains { $0.configuration?.title == "Fn" })
        let titles = (controller.controls.categoryActions ?? []).compactMap { $0["title"] as? String }
        XCTAssertEqual(titles, ["Keypad", "Shortcuts", "Text", "Customize Controls", "Appearance", "Session"])
        XCTAssertFalse(titles.contains("All Actions"))
        controller.controls.button.sendActions(for: .touchUpInside)
        try await settle(); XCTAssertTrue(controller.controls.menuOpen)
        let choices = try XCTUnwrap(controller.controls.value(forKey: "choices") as? [UIButton])
        let more = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "session-action-moreKeys" })
        let input = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "session-action-session" })
        XCTAssertGreaterThan(input.frame.minY, more.frame.minY)
        let categoryButtons = choices.filter { ($0.accessibilityIdentifier ?? "").hasPrefix("session-action-") && $0 !== input }
        let shortcuts = try XCTUnwrap(categoryButtons.first { $0.accessibilityIdentifier == "session-action-savedShortcuts" })
        let text = try XCTUnwrap(categoryButtons.first { $0.accessibilityIdentifier == "session-action-savedText" })
        let customize = try XCTUnwrap(categoryButtons.first { $0.accessibilityIdentifier == "session-action-customize" })
        let appearance = try XCTUnwrap(categoryButtons.first { $0.accessibilityIdentifier == "session-action-appearance" })
        XCTAssertEqual(more.frame.minY, shortcuts.frame.minY, accuracy: 1)
        XCTAssertEqual(shortcuts.frame.minY, text.frame.minY, accuracy: 1)
        XCTAssertLessThan(more.frame.minX, shortcuts.frame.minX); XCTAssertLessThan(shortcuts.frame.minX, text.frame.minX)
        XCTAssertEqual(customize.frame.minY, appearance.frame.minY, accuracy: 1)
        XCTAssertEqual(appearance.frame.minY, input.frame.minY, accuracy: 1)
        XCTAssertLessThan(customize.frame.minX, appearance.frame.minX); XCTAssertLessThan(appearance.frame.minX, input.frame.minX)
        XCTAssertGreaterThanOrEqual(more.bounds.width, 90)
        XCTAssertEqual(input.frame.maxX, choices.filter { $0 !== input }.map { $0.frame.maxX }.max()!, accuracy: 1, "Session occupies the trailing slot")
        let categories = try XCTUnwrap(controller.controls.categoryActions)
        XCTAssertNotEqual(categories.first { $0["kind"] as? String == "moreKeys" }?["symbol"] as? String,
                          categories.first { $0["kind"] as? String == "customize" }?["symbol"] as? String)
        capture("terminal-controls-floating-menu", window: window)
        customize.sendActions(for: .touchUpInside)
        XCTAssertEqual(customizations, 1); XCTAssertFalse(controller.controls.menuOpen)
        XCTAssertNil(controller.presentedViewController, "Customization opens the owner editor directly, with no input submenu")
        let menu = controller.makeMoreKeysMenu()
        let kinds = menu.sections.flatMap { ($0["items"] as? [[String: Any]] ?? []).compactMap { $0["kind"] as? String } }
        for key in TerminalAccessoryKey.allCases { XCTAssertTrue(kinds.contains("terminalKey-" + key.rawValue)) }
        controller.output = []
        controller.ready = false
        menu.selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertTrue(controller.output.isEmpty)
        controller.ready = true; controller.epoch = UUID()
        menu.selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertTrue(controller.output.isEmpty, "A retained menu cannot send into a replacement input epoch")
        controller.makeMoreKeysMenu().selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertEqual(controller.output, TerminalAccessoryKey.f1.bytes())
    }
    func testUnifiedActionsKeepNegotiatedUppercaseLiteralPasteAndEpochAdmission() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        let fixture = try fixtures()
        let vector = try XCTUnwrap(fixture.encodingCases.first { $0.name == "saved-uppercase-all" })
        let expected = try bytes(vector.expectedHex)
        var uppercase = TerminalControlAction(title: "Uppercase B", kind: .shortcut)
        uppercase.character = try XCTUnwrap(vector.text?.unicodeScalars.first).value
        let saved = TerminalControlAction(title: "Saved Text", kind: .text, text: "  中文😀")
        let profile = TerminalControlsProfile(actions: [uppercase, saved])
        let data = try JSONEncoder().encode(profile)
        let store = TerminalControlsStore(read: { data }, write: { _ in XCTFail("Action use must not write settings") }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        controller.terminal.feed(text: "\u{1b}[=\(vector.flags)u" + fixture.paste.enable)
        controller.output = []
        controller.performControlAction(uppercase.id)
        XCTAssertEqual(controller.output, expected)
        controller.output = []
        controller.performControlAction(saved.id)
        XCTAssertEqual(controller.output, Array(("\u{1b}[200~  中文😀\u{1b}[201~").utf8))
        controller.updateControls()
        let old = try XCTUnwrap(controller.controls.quickActions.first)
        controller.epoch = UUID(); controller.output = []
        controller.controls.actionHandler?(old)
        XCTAssertTrue(controller.output.isEmpty)
        controller.updateControls()
        controller.controls.actionHandler?(try XCTUnwrap(controller.controls.quickActions.first))
        XCTAssertEqual(controller.output, expected)
        let feedback = ControlsFeedback()
        controller.controls.setValue(feedback, forKey: "interfaceFeedback")
        controller.keyboardBar.keyFeedback = feedback
        for ready in [true, false] {
            controller.ready = ready; controller.updateControls()
            controller.controls.button.sendActions(for: .touchUpInside)
            let choices = try XCTUnwrap(controller.controls.value(forKey: "choices") as? [UIButton])
            feedback.events = []; controller.output = []
            try XCTUnwrap(choices.first).sendActions(for: .touchUpInside)
            XCTAssertEqual(feedback.events, ready ? ["commit"] : [], "Custom floating input emits feedback only after admission")
            XCTAssertEqual(controller.output, ready ? expected : [])
        }
    }
    func testEditingSharedActionRetiresPreviouslyOpenMenuPayloadsAndRowButtons() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        let item = TerminalControlAction(title: "Project", kind: .text, text: "before", inRow: true)
        var record = try JSONEncoder().encode(TerminalControlsProfile(actions: [item]))
        let store = TerminalControlsStore(read: { record }, write: { record = $0 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        let old = try XCTUnwrap(controller.controls.quickActions.first)
        let row = try XCTUnwrap(descendants(controller.keyboardBar).compactMap { $0 as? UIButton }.first { $0.configuration?.title == "Project" })
        let oldMenu = controller.makeMoreKeysMenu()
        var draft = try store.load(); draft.actions[0].text = "after"; draft.actions[0].title = "Changed"
        _ = try store.save(draft)
        session.reloadKeyboard?()
        controller.output = []
        controller.controls.actionHandler?(old)
        row.sendActions(for: .touchUpInside)
        oldMenu.selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertTrue(controller.output.isEmpty, "A stale label must not execute an edited payload or revive pending input")
        controller.controls.actionHandler?(try XCTUnwrap(controller.controls.quickActions.first))
        XCTAssertEqual(controller.output, Array("after".utf8))
    }
    func testRuntimeKeypadUsesOneShotLocksAndRejectsRetainedPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var data = try JSONEncoder().encode(TerminalControlsProfile.defaults)
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        controller.controls.actionHandler?(["kind": "moreKeys"])
        for _ in 0..<150 where controller.presentedViewController?.isBeingPresented == true || controller.transitionCoordinator != nil { try await Task.sleep(for: .milliseconds(20)) }
        let panel = try XCTUnwrap(controller.presentedViewController as? UIHostingController<TerminalKeypad>)
        XCTAssertEqual(panel.sheetPresentationController?.detents.map(\.identifier), [.medium, .large])
        XCTAssertEqual(panel.sheetPresentationController?.selectedDetentIdentifier, .medium)
        XCTAssertEqual(panel.sheetPresentationController?.prefersGrabberVisible, true)
        let first = panel.rootView.state
        first.toggle(.ctrl, false); XCTAssertEqual(first.armed, .ctrl)
        first.send("terminalKey-home"); XCTAssertTrue(first.armed.isEmpty)
        XCTAssertEqual(controller.output, TerminalAccessoryKey.home.bytes(modifiers: .ctrl))
        first.toggle(.alt, true); first.send("terminalKey-end"); XCTAssertEqual(first.locked, .alt)
        controller.dismiss(animated: false)
        for _ in 0..<150 where controller.presentedViewController != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(controller.presentedViewController)
        controller.controls.actionHandler?(["kind": "moreKeys"])
        for _ in 0..<150 where controller.presentedViewController?.isBeingPresented == true || controller.transitionCoordinator != nil { try await Task.sleep(for: .milliseconds(20)) }
        let second = try XCTUnwrap(controller.presentedViewController as? UIHostingController<TerminalKeypad>).rootView.state
        XCTAssertFalse(first === second)
        controller.output = []; first.send("terminalKey-f1"); XCTAssertTrue(controller.output.isEmpty)
        second.toggle(.alt, false); second.send("terminalKey-f1")
        XCTAssertEqual(controller.output, TerminalAccessoryKey.f1.bytes())
        controller.output = []; session.suspendInput?(); second.send("terminalKey-f1")
        XCTAssertFalse(second.ready); XCTAssertTrue(controller.output.isEmpty)
    }

    func testSingleRowKeepsKeyboardFirstAndNumbersNeverAddHeight() {
        let terminal = SessionTerminalView(frame: .zero)
        let bar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        var profile = TerminalControlsProfile.defaults
        profile.expandedBar = false // Old collapsed choices cannot hide saved keys.
        bar.configure(profile) { _ in XCTFail("Layout controls never send an action") }
        let height = bar.height
        XCTAssertEqual(height, 60, accuracy: 1)
        var requests = [Bool](), changes = 0
        bar.openKeypad = { requests.append($0) }; bar.layoutChanged = { changes += 1 }
        for focused in [false, true, false, true] {
            bar.setKeyboardFocused(focused)
            bar.frame = CGRect(x: 0, y: 0, width: 402, height: bar.height)
            bar.layoutIfNeeded()
            let stack = bar.subviews.compactMap { $0 as? UIStackView }.first!
            XCTAssertTrue(stack.arrangedSubviews.first === bar.keyboardButton)
            XCTAssertEqual(bar.height, height)
            XCTAssertGreaterThan(bar.keyScroll.contentSize.width, bar.keyScroll.bounds.width)
            let original = bar.keyboardButton.frame
            bar.keyScroll.setContentOffset(CGPoint(x: 120, y: 0), animated: false)
            XCTAssertEqual(bar.keyboardButton.frame, original, "The keyboard toggle stays fixed while keys scroll")
            bar.numberButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(bar.height, height, "Numbers stay in the existing horizontal row")
        }
        XCTAssertEqual(changes, 4)
        bar.keypadButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(requests, [false])
    }

    func testDefaultModifiersIncludeShiftAndCommandWithoutLegacySubstitution() throws {
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let data = try JSONEncoder().encode(TerminalControlsProfile.defaults)
        let store = TerminalControlsStore(read: { data }, write: { _ in XCTFail("Rendering must not save") }, legacyIDs: { [] })
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        let terminal = controller.terminal, bar = controller.keyboardBar
        bar.refresh()
        let buttons = descendants(bar).compactMap { $0 as? UIButton }
        for name in ["Esc", "Tab", "Ctrl", "Alt", "Shift", "Cmd"] { XCTAssertTrue(buttons.contains { $0.accessibilityLabel == name }) }
        let command = buttons.first { $0.accessibilityLabel == "Cmd" }!
        XCTAssertFalse(command.isEnabled)
        bar.toggle(.command); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
        terminal.feed(text: "\u{1b}[=3u"); bar.refresh()
        XCTAssertTrue(command.isEnabled)
        bar.toggle(.command)
        XCTAssertEqual(terminal.keyboardState.armed, .command)
        terminal.performCustomInput { terminal.insertText("b") }
        XCTAssertEqual(controller.output, Array("\u{1b}[98;9u\u{1b}[98;9:3u".utf8))
        XCTAssertTrue(terminal.keyboardState.active.isEmpty)
        bar.toggle(.command, lock: true)
        terminal.feed(text: "\u{1b}[=0u"); bar.refresh()
        XCTAssertFalse(command.isEnabled); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
        controller.ready = false; bar.refresh(); controller.ready = true; bar.refresh()
        for button in [bar.keyboardButton, bar.numberButton, bar.keypadButton] { XCTAssertTrue(button.isEnabled) }
    }

    func testSymbolsAndCustomKeysShareOneScrollableRowAtPhoneWidths() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let terminal = SessionTerminalView(frame: .zero)
        let bar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        bar.configure(.init(actions: [.init(title: "Project", kind: .text, text: "synthetic", inRow: true)])) { _ in XCTFail("Layout never sends input") }
        bar.translatesAutoresizingMaskIntoConstraints = true; host.view.addSubview(bar)
        for width in [320.0, 402.0, 768.0] {
            bar.frame = CGRect(x: 0, y: 100, width: width, height: bar.height)
            bar.setNeedsLayout(); bar.layoutIfNeeded()
            let buttons = descendants(bar).compactMap { $0 as? UIButton }
            for title in ["Esc", "Tab", "Ctrl", "Alt", "Shift", "Cmd"] {
                let key = try XCTUnwrap(buttons.first { $0.accessibilityLabel == title })
                XCTAssertNil(key.configuration?.title); XCTAssertNotNil(key.configuration?.image)
                XCTAssertGreaterThanOrEqual(key.bounds.width, 44)
                XCTAssertEqual(key.convert(key.bounds, to: bar).midY, bar.keyboardButton.convert(bar.keyboardButton.bounds, to: bar).midY, accuracy: 1)
            }
            let project = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Project" })
            bar.keyScroll.scrollRectToVisible(project.convert(project.bounds, to: bar.keyScroll), animated: false)
            bar.layoutIfNeeded()
            XCTAssertTrue(bar.keyScroll.bounds.intersects(project.convert(project.bounds, to: bar.keyScroll)))
            XCTAssertEqual(bar.height, 60, accuracy: 1)
        }
    }

}
