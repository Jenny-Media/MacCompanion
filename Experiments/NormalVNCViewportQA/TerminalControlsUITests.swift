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
    private func currentProfileData(_ value: TerminalControlsProfile) throws -> Data {
        var profile = value; profile.normalizeLegacyRows()
        return try JSONEncoder().encode(profile)
    }
    @Observable final class Draft { var profile = TerminalControlsProfile.defaults }
    @Observable final class MenuUpdate { var tick = 0 }
    private struct MenuHost: View {
        let state: MenuUpdate
        let action: TerminalControlAction
        var body: some View {
            VStack {
                Text("Layout update \(state.tick)")
                TerminalMenuEditingPreview(actions: [action], selected: action.id, editable: true, select: { _ in }, move: { _, _ in })
                    .environment(\.colorScheme, state.tick.isMultiple(of: 2) ? .light : .dark)
            }
        }
    }
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
    func testVisualEditorSelectsAndReordersOneDraftWithoutSendingOrSaving() async throws {
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
        XCTAssertNotNil(host.presentedViewController, "Tapping a favorite opens its focused actions")
        XCTAssertTrue(choices.allSatisfy(\.isEnabled), "The editing canvas has no disabled navigation buttons")
        host.dismiss(animated: false)
        try await settle()
        XCTAssertEqual(draft.profile.actions.last?.text, "  synthetic\n", "Selecting a placement leaves its definition unchanged; the focused editor is covered by native journeys")
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
        XCTAssertNil(largePreview.selectedPreviewID, "Actions live in a focused sheet, not a permanent selection toolbar")
        capture("terminal-controls-editor-accessibility", window: window)
    }
    func testMenuEditingMeasurementIncludesAllFixedNavigationRows() throws {
        let preview = CompanionVNCControls()
        preview.editingPreview = true
        preview.quickActions = TerminalControlsProfile.defaults.placed(.menu).map(\.native)
        preview.categoryActions = TerminalControlNavigation.items
        preview.refreshEditingPreview()
        let measured = preview.sizeThatFits(CGSize(width: 360, height: 10000))
        let panel = try XCTUnwrap(preview.value(forKey: "panel") as? UIView)
        XCTAssertNotNil((panel as? UIVisualEffectView)?.effect, "The preview needs the runtime material to separate controls from terminal content")
        XCTAssertGreaterThanOrEqual(measured.height, panel.bounds.height - 1)
        XCTAssertGreaterThan(measured.height, 200)
        let choices = try XCTUnwrap(preview.value(forKey: "choices") as? [UIButton])
        for kind in ["moreKeys", "savedShortcuts", "savedText", "customize", "appearance", "session"] {
            let key = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "session-action-" + kind })
            XCTAssertFalse(key.isEnabled)
            XCTAssertLessThanOrEqual(key.convert(key.bounds, to: panel).maxY, measured.height + 1)
        }
    }
    func testMenuPreviewKeepsPanelAcrossUnrelatedSwiftUIUpdates() async throws {
        let state = MenuUpdate()
        let action = TerminalControlAction(title: "Project", kind: .text, text: "synthetic")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: MenuHost(state: state, action: action))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let preview = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        let panel = try XCTUnwrap(preview.value(forKey: "panel") as? UIView)
        let choices = try XCTUnwrap(preview.value(forKey: "choices") as? [UIButton])
        state.tick += 1
        try await settle()
        XCTAssertTrue(preview.value(forKey: "panel") as? UIView === panel, "Layout-only updates must keep the native material and active hit targets alive")
        XCTAssertTrue((preview.value(forKey: "choices") as? [UIButton])?.first === choices.first)
    }
    func testFloatingMenuExposesKeysTextAndLibraryWithoutFnAndRetiresOldSelections() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let profile = TerminalControlsProfile.defaults
        let data = try currentProfileData(profile)
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
        controller.output = []
        controller.makeMoreKeysMenu().selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertTrue(controller.output.isEmpty, "Runtime callbacks stay paused until the editor closes")
        controller.finishCustomization()
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
        let data = try currentProfileData(profile)
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
        XCTAssertTrue(controller.output.isEmpty, "Saved text is reviewed before explicit Send Text")
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
        var item = TerminalControlAction(title: "Project", kind: .shortcut, inRow: true)
        item.character = 0x61
        var record = try JSONEncoder().encode(TerminalControlsProfile(actions: [item]))
        let store = TerminalControlsStore(read: { record }, write: { record = $0 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        let old = try XCTUnwrap(controller.controls.quickActions.first)
        let row = try XCTUnwrap(descendants(controller.keyboardBar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Project" })
        let oldMenu = controller.makeMoreKeysMenu()
        var draft = try store.load(); draft.actions[0].character = 0x62; draft.actions[0].title = "Changed"
        _ = try store.save(draft)
        session.reloadKeyboard?()
        controller.output = []
        controller.controls.actionHandler?(old)
        row.sendActions(for: .touchUpInside)
        oldMenu.selectionHandler?(["kind": "terminalKey-f1"])
        XCTAssertTrue(controller.output.isEmpty, "A stale label must not execute an edited payload or revive pending input")
        controller.controls.actionHandler?(try XCTUnwrap(controller.controls.quickActions.first))
        XCTAssertEqual(controller.output, Array("b".utf8))
    }
    func testRuntimeKeypadUsesOneShotLocksAndRejectsRetainedPresentation() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var data = try currentProfileData(.defaults)
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
        let f8 = try XCTUnwrap(TerminalKeyCatalog.all.first { $0.accessory == .f8 })
        controller.output = []
        first.pin(f8.id, .keyboard)
        XCTAssertTrue(controller.output.isEmpty, "Pinning is never terminal input")
        XCTAssertTrue(first.ready); XCTAssertTrue(controller.presentedViewController === panel)
        let pinned = try XCTUnwrap(controller.controlProfile.actions.first { f8.matches($0) })
        first.pin(f8.id, .menu)
        XCTAssertEqual(controller.controlProfile.actions.filter { f8.matches($0) }.count, 1)
        XCTAssertTrue(controller.controlProfile.actions.first { $0.id == pinned.id }!.inMenu)
        first.send("paletteKey-" + f8.id)
        XCTAssertEqual(controller.output, TerminalAccessoryKey.f8.bytes())
        controller.output = []
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
        controller.output = []; session.suspendInput?(); second.send("terminalKey-f1"); second.pin(f8.id, .keyboard)
        XCTAssertFalse(second.ready); XCTAssertTrue(controller.output.isEmpty)
        controller.ready = true; controller.epoch = UUID(); session.reloadKeyboard?()
        second.pin(f8.id, .menu); second.send("paletteKey-" + f8.id)
        XCTAssertFalse(second.ready); XCTAssertTrue(controller.output.isEmpty)
    }

    func testFreeAllKeysSendsWithoutPinningAndReconnectRetiresPanel() async throws {
        let entitlement = try await pro(); entitlement.clearTransactions()
        for _ in 0..<250 {
            await DirectProAccess.shared.refresh()
            if !DirectProAccess.shared.hasPro { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(DirectProAccess.shared.hasPro)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var data = try currentProfileData(.defaults)
        var writes = 0
        let store = TerminalControlsStore(read: { data }, write: { data = $0; writes += 1 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Free QA", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        controller.controls.actionHandler?(["kind": "moreKeys"])
        for _ in 0..<150 where controller.presentedViewController?.isBeingPresented == true { try await Task.sleep(for: .milliseconds(20)) }
        let state = try XCTUnwrap(controller.presentedViewController as? UIHostingController<TerminalKeypad>).rootView.state
        XCTAssertFalse(state.canPin)
        let insert = try XCTUnwrap(TerminalKeyCatalog.all.first { $0.accessory == .insert })
        state.pin(insert.id, .keyboard)
        XCTAssertEqual(writes, 0)
        state.send("paletteKey-" + insert.id)
        XCTAssertEqual(controller.output, [0x1b, 0x5b, 0x32, 0x7e])
        controller.output = []
        controller.epoch = UUID(); session.reloadKeyboard?()
        XCTAssertFalse(state.ready, "An unchanged settings revision cannot keep a panel from the old connection alive")
        state.send("paletteKey-" + insert.id)
        XCTAssertTrue(controller.output.isEmpty)
    }

    func testExternalProfileChangeClosesFloatingAndPresentedLegacyMenus() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var data = try currentProfileData(.defaults)
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Reload QA", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        controller.controls.button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.controls.button.accessibilityValue, "Open")
        var draft = try store.load(); draft.rowsExpanded = true; _ = try store.save(draft)
        session.reloadKeyboard?()
        XCTAssertEqual(controller.controls.button.accessibilityValue, "Closed")
        controller.controls.actionHandler?(["kind": "session"])
        for _ in 0..<150 where controller.presentedViewController?.isBeingPresented == true { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(controller.presentedViewController is UINavigationController)
        draft = try store.load(); draft.rowsExpanded = false; _ = try store.save(draft)
        session.reloadKeyboard?()
        for _ in 0..<150 where controller.presentedViewController != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(controller.output.isEmpty)
    }

    func testFloatingButtonTracksMainRowAfterRepeatedExpansionAndCollapse() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var data = try currentProfileData(.defaults)
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Geometry QA", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for _ in 0..<6 {
            controller.keyboardBar.expandButton.sendActions(for: .touchUpInside)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let button = controller.controls.button.convert(controller.controls.button.bounds, to: controller.view)
            let anchor = controller.keyboardBar.menuAnchor.convert(controller.keyboardBar.menuAnchor.bounds, to: controller.view)
            let keyboard = controller.keyboardBar.keyboardButton.convert(controller.keyboardBar.keyboardButton.bounds, to: controller.view)
            XCTAssertEqual(button.midY, anchor.midY, accuracy: 1)
            XCTAssertEqual(button.midY, keyboard.midY, accuracy: 1)
            XCTAssertTrue(controller.view.bounds.contains(button), "Menu remains reachable after either transition")
        }
    }

    func testNumbersPresetAndExplicitExpansionKeepFocusLayoutStable() throws {
        let terminal = SessionTerminalView(frame: .zero)
        let bar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        bar.translatesAutoresizingMaskIntoConstraints = true
        let holder = UIView(frame: .init(x: 0, y: 0, width: 402, height: 600)); holder.addSubview(bar)
        var profile = TerminalControlsProfile.defaults
        profile.expandedBar = false
        bar.configure(profile) { _ in XCTFail("Layout controls never send an action") }
        let height = bar.height
        XCTAssertGreaterThan(height, 90)
        var requests = [Bool](), changes = 0
        bar.openKeypad = { requests.append($0) }; bar.layoutChanged = { changes += 1 }
        for focused in [false, true, false, true] {
            bar.setKeyboardFocused(focused)
            bar.frame = CGRect(x: 0, y: 0, width: 402, height: bar.height)
            holder.layoutIfNeeded(); bar.layoutIfNeeded()
            XCTAssertEqual(bar.height, height)
            let numberScroll = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIScrollView }.first {
                $0.accessibilityIdentifier == "terminal-extra-row-" + TerminalKeyboardRow.numbersID.uuidString
            })
            let digits = descendants(numberScroll).compactMap { $0 as? UIButton }
            XCTAssertEqual(digits.count, 10)
            XCTAssertTrue(digits.allSatisfy { $0.bounds.width >= 44 })
            let right = try XCTUnwrap(digits.first { $0.accessibilityLabel == "0" })
            numberScroll.scrollRectToVisible(right.convert(right.bounds, to: numberScroll), animated: false)
            XCTAssertTrue(numberScroll.bounds.contains(right.convert(right.bounds, to: numberScroll)))
            XCTAssertGreaterThan(bar.keyScroll.contentSize.width, bar.keyScroll.bounds.width)
            bar.keyScroll.setContentOffset(.zero, animated: false)
            let original = bar.keyboardButton.convert(bar.keyboardButton.bounds, to: bar)
            let anchor = bar.menuAnchor.convert(bar.menuAnchor.bounds, to: bar)
            bar.keyScroll.setContentOffset(CGPoint(x: 120, y: 0), animated: false)
            XCTAssertLessThan(bar.keyboardButton.convert(bar.keyboardButton.bounds, to: bar).minX, original.minX - 100)
            XCTAssertEqual(bar.menuAnchor.convert(bar.menuAnchor.bounds, to: bar), anchor)
            bar.expandButton.sendActions(for: .touchUpInside)
            XCTAssertGreaterThan(bar.height, height)
            bar.setKeyboardFocused(!focused)
            XCTAssertTrue(bar.showsExtraRows)
            bar.expandButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(bar.height, height)
        }
        XCTAssertEqual(changes, 8)
        bar.keypadButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(requests, [false])
    }

    func testCommandIsOptionalAndNeverSubstitutedInLegacySessions() throws {
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let data = try currentProfileData(.defaults)
        let store = TerminalControlsStore(read: { data }, write: { _ in XCTFail("Rendering must not save") }, legacyIDs: { [] })
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        let terminal = controller.terminal, bar = controller.keyboardBar
        bar.refresh()
        let buttons = descendants(bar).compactMap { $0 as? UIButton }
        for name in ["Escape", "Tab", "Ctrl", "Alt", "Shift"] { XCTAssertTrue(buttons.contains { $0.accessibilityLabel == name }) }
        XCTAssertFalse(buttons.contains { $0.accessibilityLabel == "Cmd" })
        var profile = TerminalControlsProfile.defaults; profile.commandInBar = true
        bar.configure(profile) { _ in }
        let command = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Command" })
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
        for button in [bar.keyboardButton, bar.expandButton, bar.keypadButton] { XCTAssertTrue(button.isEnabled) }
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
            for title in ["Escape", "Tab", "Ctrl", "Alt", "Shift"] {
                let key = try XCTUnwrap(buttons.first { $0.accessibilityLabel == title })
                XCTAssertNil(key.configuration?.title); XCTAssertNotNil(key.configuration?.image)
                XCTAssertGreaterThanOrEqual(key.bounds.width, 44)
                XCTAssertEqual(key.convert(key.bounds, to: bar).midY, bar.keyboardButton.convert(bar.keyboardButton.bounds, to: bar).midY, accuracy: 1)
            }
            let project = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Project" })
            bar.keyScroll.scrollRectToVisible(project.convert(project.bounds, to: bar.keyScroll), animated: false)
            bar.layoutIfNeeded()
            XCTAssertTrue(bar.keyScroll.bounds.intersects(project.convert(project.bounds, to: bar.keyScroll)))
            XCTAssertGreaterThan(bar.height, 90)
        }
    }

    func testRealBarEditingPreviewSelectsAndMovesWithoutAnInputOwner() throws {
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
        bar.editingPreview = true
        var selected: TerminalBarItem?
        bar.previewSelect = { item, _ in selected = item }
        bar.configure(.defaults) { _ in XCTFail("Preview cannot send saved input") }
        let ctrl = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "terminal-preview-item-control-ctrl" })
        ctrl.sendActions(for: .touchUpInside)
        XCTAssertEqual(selected, .control(.ctrl)); XCTAssertNil(bar.terminal)
        let action = try XCTUnwrap(ctrl.accessibilityCustomActions?.first { $0.name == "Remove from Keyboard Bar" })
        var removed: TerminalBarItem?
        bar.previewRemove = { item, _ in removed = item }
        XCTAssertTrue(action.actionHandler?(action) == true); XCTAssertEqual(removed, .control(.ctrl))
        XCTAssertNotNil(ctrl.configuration?.image, "Preview uses production symbols and button metrics")
        XCTAssertTrue(try XCTUnwrap(ctrl.interactions.compactMap { $0 as? UIDragInteraction }.first).isEnabled,
            "Key dragging must be explicitly enabled on every device")
    }

    func testCanvasShowsAllSixRowsAndRowHandlesWithoutChangingRuntimeVisibilityOrInput() throws {
        var profile = TerminalControlsProfile.defaults
        for _ in 0..<3 { _ = profile.addPreset(.blank) }
        profile.rowsExpanded = false
        var rows = profile.resolvedRows
        rows[0].visibility = .hidden
        for index in rows.indices where rows[index].preset == .blank { rows[index].visibility = .expanded }
        profile.keyboardRows = rows
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
        bar.editingPreview = true; bar.previewShowsAllRows = true; bar.previewShowsRowHandles = true
        bar.configure(profile) { _ in XCTFail("The editor has no input owner") }
        let handles = descendants(bar).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("terminal-row-handle-") == true }
        XCTAssertEqual(handles.count, 6)
        XCTAssertTrue(handles.allSatisfy { !$0.isHidden })
        XCTAssertGreaterThan(bar.height, 320)
        let main = try XCTUnwrap(handles.first { $0.accessibilityIdentifier?.hasSuffix(TerminalKeyboardRow.mainID.uuidString) == true })
        XCTAssertEqual(main.accessibilityLabel, "Reorder Row 6")
        XCTAssertTrue(main.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } == true,
            "The row handle must support a direct drag without a long press")
        XCTAssertFalse(main.interactions.contains { $0 is UIDragInteraction }, "Row reordering is distinct from long-press key dragging")
        var selected: UUID?
        bar.previewSelectRow = { selected = $0 }; main.sendActions(for: .touchUpInside)
        XCTAssertNil(selected, "The handle only reorders; row actions use its trailing menu")
        var moved: UUID?
        bar.previewMoveRow = { moved = $0; _ = $1 }
        let up = try XCTUnwrap(main.accessibilityCustomActions?.first { $0.name == "Move Row Up" })
        XCTAssertTrue(up.actionHandler?(up) == true); XCTAssertEqual(moved, TerminalKeyboardRow.mainID)
        bar.previewShowsAllRows = false; bar.previewShowsRowHandles = false; bar.configure(profile) { _ in }
        XCTAssertEqual(bar.height, 60)
        XCTAssertFalse(profile.rowsExpanded!); XCTAssertEqual(profile.resolvedRows[0].visibility, .hidden)
    }

    func testSelectedSavedKeyIsRevealedInItsScrollablePreviewRow() throws {
        var profile = TerminalControlsProfile.defaults
        for index in 0..<12 { profile.actions.append(.init(title: "Saved Text \(index)", kind: .text, text: "synthetic", inRow: true, inMenu: false)) }
        let saved = try XCTUnwrap(profile.actions.last)
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
        bar.editingPreview = true; bar.previewShowsAllRows = true
        bar.selectedPreviewItem = .saved(saved.id); bar.selectedPreviewRow = TerminalKeyboardRow.mainID
        bar.configure(profile) { _ in XCTFail("Preview cannot send") }
        bar.frame = CGRect(x: 0, y: 0, width: 360, height: bar.height)
        bar.layoutRows()
        let button = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "terminal-row-preview-" + saved.id.uuidString })
        let visible = button.convert(button.bounds, to: bar.keyScroll).intersection(bar.keyScroll.bounds)
        XCTAssertGreaterThanOrEqual(visible.width, 44)
    }

    func testAvailableRowTemplateRendersItsKeysAtUsableWidths() throws {
        var profile = TerminalControlsProfile()
        profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .custom, title: "Function Keys", items: TerminalRowPreset.functions.items, expandedOnly: false)]
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
        bar.editingPreview = true; bar.previewShowsAllRows = true; bar.previewShowsRowHandles = true; bar.previewPreset = .functions
        bar.configure(profile) { _ in XCTFail("Templates cannot send") }
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 346, height: 60)); parent.addSubview(bar)
        NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo: parent.topAnchor), bar.bottomAnchor.constraint(equalTo: parent.bottomAnchor), bar.leadingAnchor.constraint(equalTo: parent.leadingAnchor), bar.trailingAnchor.constraint(equalTo: parent.trailingAnchor)])
        parent.layoutIfNeeded(); bar.layoutRows()
        let keys = descendants(bar).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("terminal-template-item-") == true }
        XCTAssertEqual(keys.count, 12)
        let scroll = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIScrollView }.first)
        XCTAssertGreaterThan(scroll.bounds.width, 100, String(describing: bar.perform(NSSelectorFromString("recursiveDescription"))))
        XCTAssertTrue(keys.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 })
    }

    func testKeyboardEditorSettlesAndKeepsDragSourceViewsAcrossUnchangedLayoutPasses() async throws {
        let draft = Draft()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalControlsEditor(profile: Binding(get: { draft.profile }, set: { draft.profile = $0 }), destination: .keyboard).padding(16))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let canvas = try XCTUnwrap(descendants(host.view).compactMap { $0 as? TerminalKeyboardBar }.first { $0.previewPreset == nil })
        let before = try XCTUnwrap(descendants(canvas).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "terminal-preview-item-control-ctrl" })
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await settle()
        let after = try XCTUnwrap(descendants(canvas).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == before.accessibilityIdentifier })
        XCTAssertTrue(before === after, "An unchanged SwiftUI pass must keep the active drag source alive")
        for bar in descendants(host.view).compactMap({ $0 as? TerminalKeyboardBar }) {
            XCTAssertTrue(descendants(bar).compactMap { $0 as? UIScrollView }.allSatisfy { $0.convert($0.bounds, to: bar).maxX <= bar.bounds.maxX + 1 })
        }
        XCTAssertNil(canvas.terminal)
    }

    func testReadOnlyCanvasDisablesAccessibilityEditingAndPresetCallbacks() async throws {
        let draft = Draft(), original = draft.profile
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalControlsEditor(profile: Binding(get: { draft.profile }, set: { draft.profile = $0 }), editable: false, destination: .keyboard))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let bars = descendants(host.view).compactMap { $0 as? TerminalKeyboardBar }
        XCTAssertFalse(bars.isEmpty)
        for bar in bars {
            XCTAssertFalse(bar.isUserInteractionEnabled)
            XCTAssertNil(bar.previewSelect); XCTAssertNil(bar.previewMove); XCTAssertNil(bar.previewRemove)
            XCTAssertNil(bar.previewSelectRow); XCTAssertNil(bar.previewMoveRow)
            XCTAssertNil(bar.previewAddPreset); XCTAssertNil(bar.previewAddItem)
            for button in descendants(bar).compactMap({ $0 as? UIButton }) {
                for action in button.accessibilityCustomActions ?? [] { _ = action.actionHandler?(action) }
            }
        }
        XCTAssertEqual(draft.profile, original)
    }

    func testFocusedEditorUsesFullSizeScrollableDigitsAtNormalPhoneWidth() async throws {
        let draft = Draft()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalControlsEditor(profile: Binding(get: { draft.profile }, set: { draft.profile = $0 }), destination: .keyboard))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let bar = try XCTUnwrap(descendants(host.view).compactMap { $0 as? TerminalKeyboardBar }.first)
        let scroll = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIScrollView }.first { $0.accessibilityIdentifier == "terminal-row-preview-scroll-" + TerminalKeyboardRow.numbersID.uuidString })
        let digits = descendants(scroll).compactMap { $0 as? UIButton }
        XCTAssertGreaterThan(scroll.bounds.width, 200)
        XCTAssertEqual(digits.count, 10)
        for digit in digits {
            let frame = digit.convert(digit.bounds, to: scroll)
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            scroll.scrollRectToVisible(frame, animated: false)
            XCTAssertGreaterThanOrEqual(frame.intersection(scroll.bounds).width, frame.width - 1)
        }
    }

    func testFavoriteAddTileDoesNotBecomeASavedOrDraggableAction() async throws {
        let draft = Draft(), before = draft.profile
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalControlsEditor(profile: Binding(get: { draft.profile }, set: { draft.profile = $0 })))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let preview = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        let choices = try XCTUnwrap(preview.value(forKey: "choices") as? [UIButton])
        let add = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "terminal-control-add" })
        XCTAssertFalse(add.interactions.contains { $0 is UIDragInteraction })
        XCTAssertNil(preview.actionHandler)
        add.sendActions(for: .touchUpInside); try await settle()
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertEqual(draft.profile, before)
        host.dismiss(animated: false); try await settle()
    }

    func testReconfiguringEditableBuiltinsRetiresOldKeyAndModifierCallbacks() throws {
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true; defer { session.stop() }
        let controller = ControlsInputController(session: session, customize: {})
        controller.loadViewIfNeeded()
        let bar = controller.keyboardBar
        bar.configure(.defaults) { _ in XCTFail("Only built-in input is exercised") }
        let old = descendants(bar).compactMap { $0 as? UIButton }
        let escape = try XCTUnwrap(old.first { $0.accessibilityLabel == "Escape" })
        let ctrl = try XCTUnwrap(old.first { $0.accessibilityLabel == "Ctrl" })
        var profile = TerminalControlsProfile.defaults
        profile.removeBarItem(.key("key-escape"), in: TerminalKeyboardRow.mainID)
        bar.configure(profile) { _ in XCTFail("Only built-in input is exercised") }
        escape.sendActions(for: .touchUpInside); ctrl.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.output.isEmpty); XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
        let tab = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Tab" })
        tab.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.output, [9])
    }

    func testRowAlignmentUsesSpareWidthAndOverflowKeepsFullSizeKeys() throws {
        for alignment in TerminalKeyboardRow.Alignment.allCases {
            for overflowing in [false, true] {
                var profile = TerminalControlsProfile()
                let items: [TerminalBarItem] = overflowing ? TerminalRowPreset.numbers.items : [.key("key-left"), .key("key-right")]
                profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main Row", items: items, alignment: alignment)]
                let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true
                bar.configure(profile) { _ in XCTFail("Alignment never sends input") }
                bar.frame = .init(x: 0, y: 0, width: overflowing ? 200 : 360, height: bar.height); bar.layoutRows()
                let keys = descendants(bar.keyScroll).compactMap { $0 as? UIButton }
                let first = try XCTUnwrap(keys.first), last = try XCTUnwrap(keys.last)
                XCTAssertTrue(keys.allSatisfy { $0.bounds.width >= 43.5 })
                let leading = first.convert(first.bounds, to: bar.keyScroll), trailing = last.convert(last.bounds, to: bar.keyScroll)
                if overflowing {
                    XCTAssertGreaterThan(bar.keyScroll.contentSize.width, bar.keyScroll.bounds.width)
                    bar.keyScroll.scrollRectToVisible(trailing, animated: false)
                    XCTAssertGreaterThanOrEqual(trailing.intersection(bar.keyScroll.bounds).width, trailing.width - 1)
                } else {
                    switch alignment {
                    case .left: XCTAssertEqual(leading.minX, 0, accuracy: 1)
                    case .center: XCTAssertEqual((leading.minX + trailing.maxX) / 2, bar.keyScroll.bounds.midX, accuracy: 1)
                    case .right: XCTAssertEqual(trailing.maxX, bar.keyScroll.bounds.maxX, accuracy: 1)
                    case .fill:
                        XCTAssertEqual(leading.width, trailing.width, accuracy: 1)
                        XCTAssertEqual(leading.minX, 0, accuracy: 1); XCTAssertEqual(trailing.maxX, bar.keyScroll.bounds.maxX, accuracy: 1)
                    }
                }
            }
        }
    }

    func testDockedKeyboardPreviewUsesAnIsolatedAccessoryAndLeavesDraftUnchanged() async throws {
        let profile = TerminalControlsProfile.defaults
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalDockedKeyboardPreview(profile: profile))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await settle()
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextField }.first)
        let accessory = try XCTUnwrap(field.inputAccessoryView)
        let bar = try XCTUnwrap(descendants(accessory).compactMap { $0 as? TerminalKeyboardBar }.first)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertNil(bar.terminal); XCTAssertTrue(bar.editingPreview); XCTAssertTrue(bar.presentationPreview)
        XCTAssertNil(bar.previewMove); XCTAssertNil(bar.previewRemove); XCTAssertNil(bar.previewRowAction)
        XCTAssertFalse(descendants(bar).contains { $0.accessibilityIdentifier?.hasPrefix("terminal-row-handle-") == true })
        field.insertText("preview only")
        XCTAssertTrue(field.text?.isEmpty != false)
        field.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNil(field.markedTextRange)
        field.unmarkText()
        XCTAssertTrue(field.text?.isEmpty != false)
        let height = bar.height
        let expand = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "terminal-preview-item-control-expand" || $0.accessibilityLabel == "Expand Rows" })
        expand.sendActions(for: .touchUpInside); try await settle()
        XCTAssertGreaterThan(bar.height, height)
        XCTAssertNil(profile.rowsExpanded)
    }

    func testScrollStartAndManualOffsetSurviveReconfigurationAndKeyboardChanges() throws {
        for preview in [false, true] {
            for alignment in TerminalKeyboardRow.Alignment.allCases {
                for start in TerminalKeyboardRow.ScrollStart.allCases {
                    var profile = TerminalControlsProfile()
                    let row = TerminalKeyboardRow(id: TerminalKeyboardRow.mainID, kind: .main, title: "Stale name", items: TerminalRowPreset.functions.items, alignment: alignment, scrollStart: start)
                    profile.keyboardRows = [row]
                    let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = preview; bar.translatesAutoresizingMaskIntoConstraints = true
                    bar.configure(profile) { _ in XCTFail("Scrolling never sends input") }
                    bar.frame = .init(x: 0, y: 0, width: 300, height: bar.height); bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    let maximum = bar.keyScroll.contentSize.width - bar.keyScroll.bounds.width
                    XCTAssertGreaterThan(maximum, 100)
                    XCTAssertEqual(bar.keyScroll.contentOffset.x, row.startsAtRight ? maximum : 0, accuracy: 1, "\(preview) \(alignment) \(start)")
                    bar.keyScroll.setContentOffset(.init(x: 80, y: 0), animated: false)
                    bar.configure(profile) { _ in }; bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    XCTAssertEqual(bar.keyScroll.contentOffset.x, 80, accuracy: 1)
                    bar.setKeyboardFocused(true); bar.refresh(); bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    bar.setKeyboardFocused(false); bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    XCTAssertEqual(bar.keyScroll.contentOffset.x, 80, accuracy: 1)
                    bar.frame.size.width = 340; bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    XCTAssertEqual(bar.keyScroll.contentOffset.x, 80, accuracy: 1)
                    profile.keyboardRows![0].scrollStart = row.startsAtRight ? .left : .right
                    bar.configure(profile) { _ in }; bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.layoutRows()
                    XCTAssertEqual(bar.keyScroll.contentOffset.x, row.startsAtRight ? 0 : bar.keyScroll.contentSize.width - bar.keyScroll.bounds.width, accuracy: 1)
                }
            }
        }
    }
    func testDuplicateKeysSelectAndRemoveTheirOwnOccurrenceAndKeepReadableShortcutLabels() throws {
        var profile = TerminalControlsProfile.defaults
        let main = TerminalKeyboardRow.mainID
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.herdr.shortcuts[1]))
        profile.place(id, in: main); profile.place(id, in: main)
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true
        var selected: [String] = [], removed: [String] = []
        bar.previewPlacementSelect = { selected.append($0.id); XCTAssertEqual($1, main) }
        bar.previewPlacementRemove = { removed.append($0); XCTAssertEqual($1, main) }
        bar.configure(profile) { _ in XCTFail("Preview never sends input") }
        let buttons = descendants(bar).compactMap { $0 as? UIButton }.filter { $0.accessibilityLabel == "Herdr New Workspace" }
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy { $0.configuration?.title == "N" && $0.accessibilityHint?.contains("After Herdr Navigate") == true })
        XCTAssertNotEqual(buttons[0].accessibilityIdentifier, buttons[1].accessibilityIdentifier)
        for button in buttons {
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(button.accessibilityCustomActions!.first!.actionHandler!(button.accessibilityCustomActions!.first!))
        }
        XCTAssertEqual(Set(selected).count, 2); XCTAssertEqual(removed, selected)
    }
    func testDuplicateUtilityButtonsRemainIndependentAndExpandRequiresVisibleExpandableRows() throws {
        let terminal = SessionTerminalView(frame: .zero)
        var profile = TerminalControlsProfile.defaults
        let main = TerminalKeyboardRow.mainID
        profile.placeBarItem(.control(.keyboard), in: main); profile.placeBarItem(.control(.expand), in: main)
        profile.placeBarItem(.control(.keypad), in: main); profile.placeBarItem(.control(.keypad), in: main)
        let bar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        var keyboard = 0, keypad = 0
        bar.toggleKeyboard = { keyboard += 1 }; bar.openKeypad = { _ in keypad += 1 }
        bar.configure(profile) { _ in }
        let buttons = descendants(bar).compactMap { $0 as? UIButton }
        let toggles = buttons.filter { $0.accessibilityLabel == "Show Keyboard" }
        XCTAssertEqual(toggles.count, 2)
        toggles.forEach { $0.sendActions(for: .touchUpInside) }; XCTAssertEqual(keyboard, 2)
        let pads = buttons.filter { $0.accessibilityLabel == "Keypad" }
        XCTAssertEqual(pads.count, 2); pads.forEach { XCTAssertTrue($0.isEnabled); $0.sendActions(for: .touchUpInside) }; XCTAssertEqual(keypad, 2)
        let expands = buttons.filter { $0.accessibilityLabel == "Expand Rows" }
        XCTAssertEqual(expands.count, 2); XCTAssertTrue(expands.allSatisfy { !$0.isHidden })
        expands[0].sendActions(for: .touchUpInside); XCTAssertTrue(bar.showsExtraRows)
        expands[1].sendActions(for: .touchUpInside); XCTAssertFalse(bar.showsExtraRows)
        profile.keyboardRows![profile.keyboardRows!.firstIndex { $0.id == TerminalKeyboardRow.navigationID }!].hidden = true
        bar.configure(profile) { _ in }
        XCTAssertTrue(descendants(bar).compactMap { $0 as? UIButton }.filter { $0.accessibilityLabel == "Expand Rows" }.allSatisfy(\.isHidden))
    }

    func testRepeatedMenuPlacementsUseUniquePayloadsAndExecuteSharedDefinitionOncePerTap() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        var action = TerminalControlAction(title: "Tmux Prefix", kind: .shortcut, inMenu: false)
        action.character = 0x62; action.modifiers = [0xffe3]
        var profile = TerminalControlsProfile(actions: [action])
        profile.pin(action.id, in: .menu, enabled: true); profile.pin(action.id, in: .menu, enabled: true)
        let data = try currentProfileData(profile)
        let store = TerminalControlsStore(read: { data }, write: { _ in XCTFail("Using controls cannot save") }, legacyIDs: { [] })
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"]))
        session.connected = true
        let controller = ControlsInputController(session: session, customize: {}, controlsStore: store)
        controller.loadViewIfNeeded(); defer { session.stop() }
        let payloads = controller.controls.quickActions
        XCTAssertEqual(payloads.count, 2)
        XCTAssertNotEqual(payloads[0]["id"] as? String, payloads[1]["id"] as? String)
        for payload in payloads {
            XCTAssertEqual(payload["definitionID"] as? String, action.id.uuidString)
            controller.output = []; controller.controls.actionHandler?(payload)
            XCTAssertEqual(controller.output, [2])
        }
        var forged = payloads[0]; forged["definitionID"] = UUID().uuidString
        controller.output = []; controller.controls.actionHandler?(forged); XCTAssertTrue(controller.output.isEmpty)
        controller.epoch = UUID()
        controller.controls.actionHandler?(payloads[1]); XCTAssertTrue(controller.output.isEmpty)
    }

    func testHiddenExpandDoesNotReserveSpaceInAFittingDefaultStyleRow() throws {
        func widths(includingExpand: Bool) -> [CGFloat] {
            var profile = TerminalControlsProfile()
            profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", items: includingExpand ? [.control(.keyboard), .control(.expand), .key("key-tab")] : [.control(.keyboard), .key("key-tab")], alignment: .fill)]
            let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true
            bar.configure(profile) { _ in }
            bar.frame = .init(x: 0, y: 0, width: 360, height: bar.height); bar.layoutRows()
            return descendants(bar.keyScroll).compactMap { $0 as? UIButton }.filter { !$0.isHidden }.map { $0.bounds.width }
        }
        let with = widths(includingExpand: true), without = widths(includingExpand: false)
        XCTAssertEqual(with.count, 2); XCTAssertEqual(without.count, 2)
        for (a, b) in zip(with, without) { XCTAssertEqual(a, b, accuracy: 1) }
    }

    func testOverflowingFillRowKeepsShortKeysCompactBesideLongSavedLabels() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let holder = UIViewController(); window.rootViewController = holder
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let action = TerminalControlAction(title: "Project Path", kind: .text, text: "synthetic", inRow: true)
        var profile = TerminalControlsProfile(actions: [action])
        profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", actionIDs: [action.id], items: TerminalRowPreset.numbers.items + [.saved(action.id)], alignment: .fill)]
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true
        bar.configure(profile) { _ in }
        holder.view.addSubview(bar)
        NSLayoutConstraint.activate([bar.widthAnchor.constraint(equalToConstant: 360), bar.heightAnchor.constraint(equalToConstant: bar.height),
            bar.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor), bar.topAnchor.constraint(equalTo: holder.view.safeAreaLayoutGuide.topAnchor)])
        window.makeKeyAndVisible(); holder.view.layoutIfNeeded(); bar.layoutRows()
        let buttons = descendants(bar.keyScroll).compactMap { $0 as? UIButton }
        let digit = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "1" })
        let text = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Project Path" })
        XCTAssertGreaterThan(bar.keyScroll.contentSize.width, bar.keyScroll.bounds.width)
        XCTAssertGreaterThanOrEqual(digit.bounds.width, 44)
        XCTAssertFalse(digit.constraintsAffectingLayout(for: .horizontal).isEmpty, "Measure the actual window layout engine")
        let diagnostic = "distribution=\((digit.superview as? UIStackView)?.distribution.rawValue ?? -1), digit=\(digit.configuration?.title ?? "nil"), intrinsic=\(digit.intrinsicContentSize), digitConstraints=\(digit.constraints), affecting=\(digit.constraintsAffectingLayout(for: .horizontal))"
        XCTAssertLessThan(digit.bounds.width, text.bounds.width - 20, diagnostic)
        XCTAssertEqual(digit.bounds.width, 44, accuracy: 1, diagnostic)
    }

}
