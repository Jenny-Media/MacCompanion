import XCTest
import StoreKitTest
import UIKit

@MainActor final class TerminalControlsJourneyTests: XCTestCase {
    override func setUp() { super.setUp(); executionTimeAllowance = name.contains("testInteractiveReview") ? 900 : name.contains("testRuntimeKeyboard") ? 240 : 120 }
    private let itemID = "00000000-0000-0000-0000-00000000C001"
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 where !element.isHittable {
            let scroll = app.scrollViews.allElementsBoundByIndex.last { $0.isHittable && $0.frame.height > 200 } ?? app
            if up { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        if !element.isHittable {
            capture("terminal-controls-unreachable-control", app: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "terminal-controls-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func revealHorizontal(_ element: XCUIElement, scroll: XCUIElement) {
        for _ in 0..<10 {
            let frame = element.frame, viewport = scroll.frame
            if element.isHittable && frame.intersection(viewport).width >= min(44, frame.width) { return }
            // Flicks can jump over a narrow custom key in both directions.
            // Drag a bounded distance, including when AX reports an empty frame.
            let direction: CGFloat = !frame.isEmpty && frame.midX < viewport.midX ? -1 : 1
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + direction * 0.2, dy: 0.5))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - direction * 0.2, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let diagnostic = XCTAttachment(string: element.debugDescription + "\n" + scroll.debugDescription)
        diagnostic.name = "horizontal-control-unreachable"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(element.isHittable)
    }
    private func revealKey(_ element: XCUIElement, app: XCUIApplication) {
        revealHorizontal(element, scroll: app.scrollViews["terminal-modifier-keys"])
    }
    private func revealPreviewKey(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews["terminal-row-preview-scroll"]
        reveal(scroll, app: app)
        revealHorizontal(element, scroll: scroll)
    }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["controls-qa-open"].waitForExistence(timeout: 5))
        app.buttons["controls-qa-open"].tap()
        XCTAssertTrue(app.buttons["terminal-controls-cancel"].waitForExistence(timeout: 5))
        capture("terminal-controls-overview", app: app)
        app.buttons["terminal-edit-keyboard"].tap()
        let item = app.buttons["terminal-row-preview-" + itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); revealPreviewKey(item, app: app); item.tap()
    }
    private func rename(_ name: String, app: XCUIApplication, up: Bool = true) async throws {
        let field = app.textFields["terminal-control-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(field, app: app, up: up)
        field.tap()
        try await waitForSoftwareKeyboard(app)
        field.press(forDuration: 1)
        let menuItem = app.menuItems["Select All"]
        let button = app.buttons["Select All"]
        for _ in 0..<6 where !menuItem.exists && !button.exists {
            // UIKit paginates its edit menu at accessibility text sizes.
            let forward = app.buttons.allElementsBoundByIndex.first {
                $0.isHittable && ["more", "next", "forward"].contains(where: $0.label.lowercased().contains)
            }
            guard let forward else {
                capture("name-selection-menu-unavailable", app: app)
                let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; add(tree)
                throw NSError(domain: "TerminalControlsJourneyTests.EditMenu", code: 1)
            }
            forward.tap()
        }
        XCTAssertTrue(menuItem.exists || button.exists)
        if menuItem.exists { menuItem.tap() } else { button.tap() }
        field.typeText(name)
        XCTAssertEqual(field.value as? String, name)
    }
    private func cancel(_ app: XCUIApplication) async throws {
        let button = app.buttons["terminal-controls-cancel"]
        let previous = app.staticTexts["controls-qa-closes"].label
        button.tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button)], timeout: 5)
        guard !button.exists else {
            capture("editor-cancel-did-not-close", app: app)
            XCTFail("Close callback before: \(previous); after: \(app.staticTexts["controls-qa-closes"].label)")
            throw NSError(domain: "TerminalControlsJourneyTests.Dismissal", code: 1)
        }
    }
    private func launchPro() async throws -> (XCUIApplication, SKTestSession) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", (name.contains("testAccessibility") ? UIContentSizeCategory.accessibilityExtraExtraExtraLarge : .large).rawValue]
        if name.contains("testInteractiveReview"), ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] == "1" { app.launchEnvironment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] = "1" }
        if name.contains("testCommand") { app.launchEnvironment["MACCOMPANION_COMMAND_QA"] = "1" }
        app.launch()
        XCTAssertTrue(app.staticTexts["controls-qa-pro"].waitForExistence(timeout: 10))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        _ = try await store.buyProduct(identifier: "media.jenny.maccompanion.pro.lifetime")
        for _ in 0..<5 where !app.staticTexts["Pro ready"].exists {
            app.buttons["controls-qa-refresh-pro"].tap()
            if app.staticTexts["Pro ready"].waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(app.staticTexts["Pro ready"].waitForExistence(timeout: 15), "The app must verify the StoreKit test entitlement")
        return (app, store)
    }
    func testCancelAndSingleSavePreserveOneActionAcrossBothPlacements() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        open(app); try await rename("Cancelled", app: app)
        try await cancel(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
        open(app)
        XCTAssertEqual(app.textFields["terminal-control-name"].value as? String, "Project")
        try await rename("Saved Project", app: app)
        capture("terminal-controls-settings-save", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Saved Project")
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: on; Menu: on")
        open(app)
        XCTAssertEqual(app.textFields["terminal-control-name"].value as? String, "Saved Project")
        capture("terminal-controls-settings-persisted", app: app)
        try await cancel(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
    }
    func testSaveFromConnectedTerminalReturnsToResponsiveInput() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-live"].tap()
        let controls = app.buttons["terminal-controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 15))
        controls.tap(); app.buttons["session-action-customize"].tap()
        XCTAssertTrue(app.buttons["terminal-controls-save"].waitForExistence(timeout: 5))
        app.buttons["terminal-edit-keyboard"].tap()
        revealPreviewKey(app.buttons["terminal-row-preview-" + itemID], app: app); app.buttons["terminal-row-preview-" + itemID].tap()
        try await rename("Live Project", app: app)
        capture("connected-terminal-before-save", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        controls.tap()
        let shortcut = app.buttons.matching(NSPredicate(format: "label == %@", "Live Project")).firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5)); shortcut.tap()
        XCTAssertTrue(app.buttons["compose-send"].waitForExistence(timeout: 5))
        try await assertInput("", app: app)
        app.buttons["compose-send"].tap()
        let sent = NSPredicate(format: "label CONTAINS %@", "6f726967696e616c")
        let received = expectation(for: sent, evaluatedWith: app.staticTexts["controls-qa-input"])
        await fulfillment(of: [received], timeout: 5)
        revealKey(app.buttons["terminal-keyboard-toggle"], app: app); app.buttons["terminal-keyboard-toggle"].tap()
        try await waitForSoftwareKeyboard(app)
        app.typeText("q")
        try await assertInput("6f726967696e616c71", app: app)
        controls.tap()
        XCTAssertTrue(app.buttons["session-action-customize"].waitForExistence(timeout: 5))
        capture("connected-terminal-after-save", app: app)
    }

    private func live(_ app: XCUIApplication) {
        app.buttons["controls-qa-live"].tap()
        XCTAssertTrue(app.buttons["terminal-controls"].waitForExistence(timeout: 15))
    }
    private func assertInput(_ expected: String, app: XCUIApplication) async throws {
        let predicate = NSPredicate(format: "label == %@", "Input: " + expected)
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: app.staticTexts["controls-qa-input"])], timeout: 5)
        guard app.staticTexts["controls-qa-input"].label == "Input: " + expected else {
            capture("runtime-input-did-not-arrive", app: app)
            throw NSError(domain: "TerminalControlsJourneyTests.Input", code: 1)
        }
    }
    private func searchSaved(_ text: String, app: XCUIApplication) async throws {
        let field = app.textFields["terminal-saved-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text)
        try await waitForSoftwareKeyboard(app)
    }
    private func waitForSoftwareKeyboard(_ app: XCUIApplication) async throws {
        // Focus can be reported before the keyboard and automatic scrolling
        // finish. This also matters on iPhone with accessibility text sizes;
        // an early long press can otherwise hit the moving prediction row.
        // Resolve tap/press coordinates after visible keys arrive so the sheet
        // or focused field cannot move under the synthesized touch.
        let keyboard = app.keyboards.firstMatch
        // The first AX key can be a zero-size padding placeholder, and the
        // keyboard frame excludes prediction/bottom rows on iPhone.
        let space = keyboard.keys["space"]
        let visible = NSPredicate { _, _ in keyboard.exists && space.isHittable }
        await fulfillment(of: [expectation(for: visible, evaluatedWith: nil)], timeout: 5)
        guard keyboard.exists && space.isHittable else { throw NSError(domain: "TerminalControlsJourneyTests.Keyboard", code: 1) }
    }
    private func findKey(_ query: String, app: XCUIApplication) {
        let field = app.textFields["terminal-keypad-search"]
        reveal(field, app: app, up: false); field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && !["Find a key or group", "Search saved items"].contains(old) { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(query + "\n")
    }
    private func palette(_ app: XCUIApplication) {
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-moreKeys"].tap()
        XCTAssertTrue(app.navigationBars["Keypad"].waitForExistence(timeout: 5))
    }
    func testCommandModifierFromNegotiatedRemoteApplication() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        live(app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-moreKeys"].tap()
        let advanced = app.buttons["terminal-keypad-advanced"]; reveal(advanced, app: app); advanced.tap()
        let command = app.buttons["terminal-keypad-Cmd"]
        reveal(command, app: app)
        XCTAssertTrue(command.waitForExistence(timeout: 5)); XCTAssertTrue(command.isEnabled)
        command.tap(); XCTAssertTrue((command.value as? String) == "Next Key")
        findKey("Home", app: app)
        app.buttons["terminal-keypad-home"].tap()
        try await assertInput("1b5b313b39481b5b313b393a3348", app: app)
        findKey("", app: app)
        reveal(advanced, app: app)
        if advanced.value as? String != "Expanded" { advanced.tap() }
        reveal(command, app: app)
        XCTAssertTrue((command.value as? String) == "Off")
        capture("command-one-shot-negotiated-remote", app: app)
        app.buttons["Done"].tap()
    }

    func testStableBarAndDraggableCompactKeypad() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app)
        let toggle = app.buttons["terminal-keyboard-toggle"], number = app.buttons["9"]
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        let numberY = number.frame.midY - toggle.frame.midY
        XCTAssertLessThan(numberY, 0, "Numbers default above Main")
        for title in ["Esc", "Tab", "Ctrl", "Alt", "Shift"] { XCTAssertTrue(app.buttons[title].exists) }
        XCTAssertFalse(app.buttons["Cmd"].exists)
        capture("compact-numbers-top-keyboard-hidden", app: app)
        toggle.tap(); try await waitForSoftwareKeyboard(app)
        XCTAssertEqual(number.frame.midY - toggle.frame.midY, numberY, accuracy: 1)
        capture("compact-numbers-top-native-keyboard", app: app)
        revealKey(app.buttons["terminal-row-expand"], app: app); app.buttons["terminal-row-expand"].tap()
        XCTAssertTrue(app.buttons["Home"].exists)
        capture("expanded-rows-native-keyboard", app: app)
        revealKey(toggle, app: app); toggle.tap(); XCTAssertTrue(app.buttons["Home"].exists)
        capture("expanded-rows-keyboard-hidden", app: app)
        revealKey(app.buttons["terminal-row-expand"], app: app); app.buttons["terminal-row-expand"].tap()
        app.buttons["terminal-controls"].tap()
        let session = app.buttons["session-action-session"], settings = app.buttons["session-action-customize"], keypad = app.buttons["session-action-moreKeys"]
        let shortcuts = app.buttons["session-action-savedShortcuts"], text = app.buttons["session-action-savedText"]
        XCTAssertEqual(keypad.frame.midY, shortcuts.frame.midY, accuracy: 1)
        XCTAssertEqual(shortcuts.frame.midY, text.frame.midY, accuracy: 1)
        XCTAssertLessThan(keypad.frame.midX, shortcuts.frame.midX); XCTAssertLessThan(shortcuts.frame.midX, text.frame.midX)
        XCTAssertLessThan(keypad.frame.midY, settings.frame.midY)
        XCTAssertEqual(session.frame.midY, settings.frame.midY, accuracy: 1)
        XCTAssertGreaterThan(session.frame.midX, app.buttons["session-action-appearance"].frame.midX)
        capture("floating-menu-right-aligned", app: app); keypad.tap()
        let navigation = app.navigationBars["Keypad"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let halfY = navigation.frame.minY
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertGreaterThan(halfY, app.frame.height * 0.35) }
        capture("all-keys-default-half-sheet", app: app)
        let grabber = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: halfY - 10))
        let expanded = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: 130))
        grabber.press(forDuration: 0.2, thenDragTo: expanded)
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertLessThan(navigation.frame.minY, halfY - 100) }
        capture("all-keys-expanded-sheet", app: app)
        findKey("F12", app: app); app.buttons["terminal-keypad-f12"].tap()
        try await assertInput("1b5b32347e", app: app)
        XCTAssertTrue(navigation.exists, "Sending a rare key keeps the keypad open")
        findKey("Numbers", app: app)
        app.buttons["terminal-keypad-character-55-"].tap()
        app.buttons["Done"].tap(); try await assertInput("1b5b32347e37", app: app)
        revealKey(app.buttons["Shift"], app: app); app.buttons["Shift"].tap()
        app.buttons["1"].tap(); app.buttons["2"].tap()
        try await assertInput("1b5b32347e372132", app: app)
    }

    func testSeparateShortcutsAndTextAndDirectCustomization() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        live(app)
        let shortcutID = "terminal-saved-00000000-0000-0000-0000-00000000C004"
        let textID = "terminal-saved-00000000-0000-0000-0000-00000000C002"
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedShortcuts"].tap()
        XCTAssertTrue(app.navigationBars["Shortcuts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[shortcutID].exists); XCTAssertFalse(app.buttons[textID].exists)
        XCTAssertFalse(app.buttons["terminal-compose-text"].exists)
        capture("shortcuts-only-section", app: app)
        app.buttons[shortcutID].tap()
        try await assertInput("02", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        XCTAssertTrue(app.navigationBars["Text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[shortcutID].exists)
        try await searchSaved("Unicode", app: app)
        capture("text-only-section", app: app)
        app.buttons[textID].tap()
        XCTAssertTrue(app.buttons["compose-send"].waitForExistence(timeout: 5))
        try await assertInput("02", app: app)
        capture("saved-text-review-before-send", app: app)
        app.buttons["compose-send"].tap()
        try await assertInput("02e4b8ade69687f09f9880", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        app.buttons["terminal-compose-text"].tap()
        if !app.buttons["compose-back"].waitForExistence(timeout: 5) {
            capture("compose-entry-did-not-open", app: app)
            let diagnostic = XCTAttachment(string: app.debugDescription)
            diagnostic.name = "compose-entry-accessibility"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            XCTFail("Composer controls must be exposed through accessibility")
            return
        }
        app.textViews["compose-text"].tap()
        app.textViews["compose-text"].typeText("synthetic draft")
        try await assertInput("02e4b8ade69687f09f9880", app: app)
        capture("compose-from-text-section", app: app)
        app.buttons["compose-back"].tap()
        try await assertInput("02e4b8ade69687f09f9880", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-customize"].tap()
        XCTAssertTrue(app.buttons["terminal-edit-keyboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["terminal-edit-menu"].exists)
        capture("customize-controls-direct-entry", app: app)
        app.buttons["terminal-controls-cancel"].tap()
        try await assertInput("02e4b8ade69687f09f9880", app: app)
    }

    func testRuntimeKeyboardKeypadAndSearchableSavedText() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app); palette(app)
        let ctrl = app.buttons["terminal-keypad-Ctrl"]
        ctrl.tap(); XCTAssertTrue((ctrl.value as? String) == "Next Key")
        findKey("Home", app: app); app.buttons["terminal-keypad-home"].tap()
        XCTAssertTrue((ctrl.value as? String) == "Off")
        ctrl.press(forDuration: 0.7)
        findKey("End", app: app); app.buttons["terminal-keypad-end"].tap()
        XCTAssertEqual(ctrl.value as? String, "On"); capture("modifier-kept-on-without-lock-icon", app: app); ctrl.tap()
        capture("all-keys-modifier-states", app: app)
        findKey("F8", app: app)
        let f8 = app.buttons["terminal-keypad-f8"]; f8.press(forDuration: 1)
        app.buttons["Pin to Keyboard Bar"].tap()
        try await assertInput("1b5b313b35481b5b313b3546", app: app)
        XCTAssertTrue(app.staticTexts["terminal-keypad-notice"].exists)
        capture("pin-key-does-not-send", app: app)
        f8.tap(); try await assertInput("1b5b313b35481b5b313b35461b5b31397e", app: app)
        app.buttons["Done"].tap()
        let pinned = app.buttons["F8"]; revealKey(pinned, app: app); pinned.tap()
        let before = "1b5b313b35481b5b313b35461b5b31397e1b5b31397e"
        try await assertInput(before, app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        try await searchSaved("Multiline", app: app)
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C003"].tap()
        XCTAssertTrue(app.buttons["compose-send"].waitForExistence(timeout: 5))
        try await assertInput(before, app: app)
        app.buttons["compose-send"].tap()
        XCTAssertTrue(app.alerts["Send line breaks or tabs?"].waitForExistence(timeout: 5))
        capture("saved-multiline-review-confirmation", app: app)
        app.alerts.buttons["Cancel"].tap(); try await assertInput(before, app: app)
        app.buttons["compose-back"].tap()
        revealKey(app.buttons["terminal-keyboard-toggle"], app: app); app.buttons["terminal-keyboard-toggle"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["terminal-keyboard-toggle"].waitForExistence(timeout: 5))
        capture("stable-rows-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        capture("stable-rows-returned-portrait", app: app)
    }

    func testEditorsRemoveOnlyPlacementAndReuseOneSavedDefinition() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        open(app)
        let remove = app.buttons["terminal-remove-placement"]; reveal(remove, app: app); remove.tap()
        capture("keyboard-editor-remove-placement", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: off; Menu: on")
        app.buttons["controls-qa-open"].tap(); app.buttons["terminal-edit-keyboard"].tap()
        reveal(app.buttons["terminal-control-add"], app: app); app.buttons["terminal-control-add"].tap()
        app.buttons["Project"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: on; Menu: on")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 2")
        app.buttons["controls-qa-open"].tap(); app.buttons["terminal-edit-menu"].tap()
        XCTAssertFalse(app.switches["terminal-setting-numbers"].exists)
        capture("separate-floating-menu-editor", app: app)
        try await cancel(app)
    }
    func testCreateShortcutPreviewAndExplicitDelete() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-open"].tap(); app.buttons["terminal-edit-library"].tap()
        app.buttons["terminal-control-add"].tap(); app.buttons["Shortcut"].tap()
        let name = app.textFields["quick-action-name"]; reveal(name, app: app)
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Tmux Prefix")
        let key = app.textFields["quick-action-key"]; reveal(key, app: app)
        key.tap(); key.typeText(XCUIKeyboardKey.delete.rawValue + "b")
        XCTAssertTrue(app.staticTexts["terminal-shortcut-preview"].label.localizedCaseInsensitiveContains("b"))
        capture("shortcut-editor-final-chord", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 2")
        app.buttons["controls-qa-open"].tap(); app.buttons["terminal-edit-library"].tap()
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "terminal-library-", "Tmux Prefix")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5)); reveal(item, app: app); item.tap()
        let delete = app.buttons["terminal-delete-item"]; reveal(delete, app: app); delete.tap()
        app.buttons["Delete Item"].tap()
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
    }
    func testAccessibilityEditorsKeepSeparateDestinationsAndDrafts() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-open"].tap()
        app.buttons["terminal-edit-keyboard"].tap()
        XCTAssertTrue(app.buttons["terminal-row-preview-" + itemID].waitForExistence(timeout: 5))
        revealPreviewKey(app.buttons["terminal-row-preview-" + itemID], app: app); app.buttons["terminal-row-preview-" + itemID].tap()
        try await rename("Large Project", app: app)
        capture("keyboard-editor-accessibility-xxxl", app: app)
        try await cancel(app)
        app.buttons["controls-qa-open"].tap()
        let menu = app.buttons["terminal-edit-menu"]; reveal(menu, app: app); menu.tap()
        XCTAssertFalse(app.switches["terminal-setting-numbers"].exists)
        capture("floating-editor-accessibility-xxxl", app: app)
        try await cancel(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        live(app); app.buttons["terminal-controls"].tap()
        let keypad = app.buttons["session-action-moreKeys"]; reveal(keypad, app: app); keypad.tap()
        reveal(app.buttons["terminal-keypad-Ctrl"], app: app)
        XCTAssertTrue(app.buttons["terminal-keypad-Ctrl"].waitForExistence(timeout: 5))
        capture("keypad-accessibility-xxxl", app: app)
        app.buttons["terminal-keypad-Ctrl"].tap()
        XCTAssertTrue((app.buttons["terminal-keypad-Ctrl"].value as? String) == "Next Key")
        app.buttons["Done"].tap()
    }
    func testRowEditorAddsReordersAndMovesOneSharedItem() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        open(app)
        let addRow = app.buttons["terminal-add-row"]; reveal(addRow, app: app); addRow.tap()
        app.buttons["Blank"].tap()
        let name = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-name-")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("row-editor-custom-row-preview", app: app)
        let move = app.buttons["Move Numbers Down"]; reveal(move, app: app, up: false); move.tap()
        capture("row-editor-numbers-reordered", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
        open(app)
        let picker = app.buttons["terminal-item-row"]; reveal(picker, app: app)
        picker.tap(); app.buttons.matching(NSPredicate(format: "label == %@ AND NOT identifier BEGINSWITH %@", "Custom Row", "terminal-select-row-")).firstMatch.tap()
        capture("row-editor-move-shared-item", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: on; Menu: on")
    }
    func testKeypadSavedTabsPreserveAnUnsentDraft() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app); palette(app)
        app.buttons["Shortcuts"].tap()
        let shortcut = app.buttons["terminal-keypad-saved-00000000-0000-0000-0000-00000000C004"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5)); shortcut.tap()
        try await assertInput("02", app: app)
        app.buttons["Text"].tap(); findKey("Unicode", app: app)
        app.buttons["terminal-keypad-saved-00000000-0000-0000-0000-00000000C002"].tap()
        XCTAssertTrue(app.buttons["compose-back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "中文😀")
        try await assertInput("02", app: app)
        capture("keypad-text-tab-review", app: app); app.buttons["compose-back"].tap()
        palette(app); app.buttons["Text"].tap(); findKey("Multiline", app: app)
        app.buttons["terminal-keypad-saved-00000000-0000-0000-0000-00000000C003"].tap()
        XCTAssertTrue(app.alerts["Replace unsent draft?"].waitForExistence(timeout: 5))
        capture("saved-text-keeps-unsent-draft", app: app)
        app.alerts.buttons["Keep Draft"].tap(); try await assertInput("02", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap(); app.buttons["terminal-compose-text"].tap()
        XCTAssertTrue(app.buttons["compose-back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "中文😀")
        app.buttons["compose-back"].tap()
    }
    func testReadingModeHidesNumbersAndKeepsTheSameBarAcrossKeyboardChanges() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app)
        let surface = app.descendants(matching: .any).matching(identifier: "terminal-surface").firstMatch
        let before = surface.frame.height
        let numbers = app.buttons["terminal-number-toggle"]
        revealKey(numbers, app: app); numbers.tap()
        XCTAssertFalse(app.buttons["9"].exists)
        XCTAssertGreaterThan(surface.frame.height, before)
        revealKey(app.buttons["Esc"], app: app)
        try await assertInput("", app: app)
        capture("reading-mode-keyboard-hidden", app: app)
        revealKey(app.buttons["terminal-keyboard-toggle"], app: app); app.buttons["terminal-keyboard-toggle"].tap(); try await waitForSoftwareKeyboard(app)
        XCTAssertFalse(app.buttons["9"].exists)
        capture("reading-mode-native-keyboard", app: app)
        revealKey(app.buttons["terminal-keyboard-toggle"], app: app); app.buttons["terminal-keyboard-toggle"].tap()
        revealKey(numbers, app: app); numbers.tap()
        XCTAssertTrue(app.buttons["9"].waitForExistence(timeout: 5))
        try await assertInput("", app: app)
    }
    func testRealPreviewBuiltinDragPresetsRestoreAndUndoKeepSavedText() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        open(app)
        let ctrl = app.buttons["terminal-preview-item-control-ctrl"]
        revealPreviewKey(ctrl, app: app); ctrl.tap()
        let remove = app.buttons["terminal-remove-placement"]; reveal(remove, app: app); remove.tap()
        XCTAssertFalse(ctrl.exists)
        let undo = app.buttons["terminal-editor-undo"]; reveal(undo, app: app, up: false); undo.tap()
        XCTAssertTrue(ctrl.exists)
        capture("realistic-contiguous-bar-preview", app: app)
        let removeNavigation = app.buttons["Remove Navigation Row"]; reveal(removeNavigation, app: app); removeNavigation.tap()
        let addRow = app.buttons["terminal-add-row"]; reveal(addRow, app: app); addRow.tap(); app.buttons["Function Keys"].tap()
        let esc = app.buttons["terminal-preview-item-palette-key-escape"]
        revealPreviewKey(esc, app: app)
        let f1 = app.buttons["terminal-preview-item-palette-key-f1"]
        reveal(f1, app: app, up: false)
        esc.press(forDuration: 0.8, thenDragTo: f1)
        XCTAssertFalse(app.scrollViews["terminal-row-preview-scroll"].buttons["terminal-preview-item-palette-key-escape"].exists)
        capture("builtin-dragged-between-rows", app: app)
        let restore = app.buttons["terminal-restore-bar"]; reveal(restore, app: app); restore.tap()
        app.buttons["Restore Layout"].tap()
        XCTAssertTrue(ctrl.exists)
        reveal(undo, app: app, up: false); undo.tap()
        XCTAssertTrue(app.buttons["terminal-preview-item-palette-key-f12"].exists)
        reveal(restore, app: app); restore.tap(); app.buttons["Restore Layout"].tap()
        capture("restore-default-keeps-saved-items", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: off; Menu: on")
    }
    func testAllBottomControlsScrollAndFloatingButtonStaysFixed() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app)
        let floating = app.buttons["terminal-controls"], anchor = floating.frame
        let toggle = app.buttons["terminal-keyboard-toggle"], start = toggle.frame
        let last = app.buttons["terminal-row-expand"]
        let overflows = last.frame.maxX > app.scrollViews["terminal-modifier-keys"].frame.maxX
        revealKey(last, app: app)
        if overflows { XCTAssertLessThan(toggle.frame.minX, start.minX - 50) }
        else { XCTAssertTrue(toggle.isHittable, "A wide tablet can fit all controls without scrolling") }
        XCTAssertEqual(floating.frame, anchor)
        capture("whole-bottom-row-scrolls", app: app)
        floating.tap(); app.buttons["session-action-session"].tap()
        let show = app.descendants(matching: .any).matching(identifier: "session-menu-keyboard").firstMatch; XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        try await waitForSoftwareKeyboard(app)
        try await assertInput("", app: app)
        capture("keyboard-recovery-from-floating-menu", app: app)
    }
    func testInteractiveReview() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] == "1" else { throw XCTSkip("Opt-in interactive review") }
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        live(app)
        await fulfillment(of: [expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.staticTexts["controls-qa-review-finished"])], timeout: 600)
        capture("interactive-review-final-screen", app: app)
    }

}
