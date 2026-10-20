import XCTest
import StoreKitTest
import UIKit

@MainActor final class TerminalControlsJourneyTests: XCTestCase {
    override func setUp() { super.setUp(); executionTimeAllowance = name.contains("testInteractiveReview") ? 900 : 120 }
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
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["controls-qa-open"].waitForExistence(timeout: 5))
        app.buttons["controls-qa-open"].tap()
        XCTAssertTrue(app.buttons["terminal-controls-cancel"].waitForExistence(timeout: 5))
        capture("terminal-controls-overview", app: app)
        app.buttons["terminal-edit-keyboard"].tap()
        let item = app.buttons["terminal-row-preview-" + itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    private func rename(_ name: String, app: XCUIApplication, up: Bool = true) async throws {
        let field = app.textFields["terminal-control-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(field, app: app, up: up)
        field.tap()
        try await waitForPadKeyboard(app)
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
        controls.tap(); app.buttons["customize-quick-actions"].tap()
        XCTAssertTrue(app.buttons["terminal-controls-save"].waitForExistence(timeout: 5))
        app.buttons["terminal-edit-keyboard"].tap()
        app.buttons["terminal-row-preview-" + itemID].tap()
        try await rename("Live Project", app: app)
        capture("connected-terminal-before-save", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        controls.tap()
        let shortcut = app.buttons.matching(NSPredicate(format: "label == %@", "Live Project")).firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5)); shortcut.tap()
        let sent = NSPredicate(format: "label CONTAINS %@", "6f726967696e616c")
        let received = expectation(for: sent, evaluatedWith: app.staticTexts["controls-qa-input"])
        await fulfillment(of: [received], timeout: 5)
        app.buttons["terminal-keyboard-toggle"].tap(); app.typeText("q")
        try await assertInput("6f726967696e616c71", app: app)
        controls.tap()
        XCTAssertTrue(app.buttons["customize-quick-actions"].waitForExistence(timeout: 5))
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
        try await waitForPadKeyboard(app)
    }
    private func waitForPadKeyboard(_ app: XCUIApplication) async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        // Focus/text injection can finish before iPad presents its keyboard.
        // Resolve tap/press coordinates after visible keys arrive so the sheet
        // or focused field cannot move under the synthesized touch.
        let keyboard = app.keyboards.firstMatch
        let visible = NSPredicate { _, _ in keyboard.exists && keyboard.frame.height > 250 }
        await fulfillment(of: [expectation(for: visible, evaluatedWith: nil)], timeout: 5)
        guard keyboard.exists && keyboard.frame.height > 250 else { throw NSError(domain: "TerminalControlsJourneyTests.Keyboard", code: 1) }
    }
    func testRuntimeKeyboardKeypadAndSearchableSavedText() async throws {
        let (app, store) = try await launchPro()
        defer { app.terminate(); store.clearTransactions() }
        live(app)
        app.buttons["terminal-number-toggle"].tap()
        XCTAssertTrue(app.navigationBars["Number Keypad"].waitForExistence(timeout: 5))
        capture("number-keypad-with-keyboard-hidden", app: app)
        app.buttons["Done"].tap()
        app.buttons["terminal-keyboard-toggle"].tap()
        XCTAssertTrue(app.buttons["↑"].waitForExistence(timeout: 5))
        app.buttons["↑"].tap(); app.buttons["↑"].tap(); app.buttons["←"].tap()
        try await assertInput("1b5b411b5b411b5b44", app: app)
        capture("keyboard-expanded-arrows-and-numbers", app: app)
        app.buttons["terminal-number-toggle"].tap()
        XCTAssertFalse(app.buttons["9"].exists)
        app.buttons["terminal-number-toggle"].tap(); app.buttons["9"].tap()
        try await assertInput("1b5b411b5b411b5b4439", app: app)
        app.buttons["terminal-expand-toggle"].tap()
        XCTAssertFalse(app.buttons["↑"].exists)
        capture("keyboard-collapsed", app: app)
        app.buttons["terminal-expand-toggle"].tap()
        XCTAssertTrue(app.buttons["↑"].exists)
        app.buttons["terminal-keyboard-toggle"].tap()
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-moreKeys"].tap()
        let ctrl = app.buttons["terminal-keypad-Ctrl"]
        XCTAssertTrue(ctrl.waitForExistence(timeout: 5)); ctrl.tap()
        XCTAssertTrue(ctrl.label.contains("Next Key"))
        reveal(app.buttons["terminal-keypad-home"], app: app); app.buttons["terminal-keypad-home"].tap()
        XCTAssertTrue(ctrl.label.contains("Off"))
        app.buttons["Lock Ctrl"].tap()
        XCTAssertTrue(ctrl.label.contains("Locked"))
        app.buttons["terminal-keypad-end"].tap()
        XCTAssertTrue(ctrl.label.contains("Locked"))
        app.buttons["Unlock Ctrl"].tap()
        capture("keypad-explicit-modifier-states", app: app)
        reveal(app.buttons["terminal-keypad-f1"], app: app); app.buttons["terminal-keypad-f1"].tap()
        let interrupt = app.buttons["terminal-keypad-interrupt"]; reveal(interrupt, app: app); interrupt.tap()
        app.buttons["Done"].tap()
        try await assertInput("1b5b411b5b411b5b44391b5b313b35481b5b313b35461b4f5003", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        try await searchSaved("Unicode", app: app)
        capture("saved-items-search", app: app)
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C002"].tap()
        try await assertInput("1b5b411b5b411b5b44391b5b313b35481b5b313b35461b4f5003e4b8ade69687f09f9880", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        try await searchSaved("Multiline", app: app)
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C003"].tap()
        XCTAssertTrue(app.alerts["Paste Multiline Text?"].waitForExistence(timeout: 5))
        capture("saved-multiline-confirmation", app: app)
        app.alerts.buttons["Cancel"].tap()
        try await assertInput("1b5b411b5b411b5b44391b5b313b35481b5b313b35461b4f5003e4b8ade69687f09f9880", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        try await searchSaved("Multiline", app: app)
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C003"].tap()
        XCTAssertTrue(app.alerts["Paste Multiline Text?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Paste"].tap()
        try await assertInput("1b5b411b5b411b5b44391b5b313b35481b5b313b35461b4f5003e4b8ade69687f09f98806f6e650a2020e4b8ade69687f09f9880", app: app)
        app.buttons["terminal-keyboard-toggle"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertTrue(app.buttons["Open Keypad"].waitForExistence(timeout: 5)) }
        let surface = app.descendants(matching: .any).matching(identifier: "terminal-surface").firstMatch
        XCTAssertGreaterThan(surface.frame.height, 90)
        capture("terminal-landscape-keyboard-compact", app: app)
        if UIDevice.current.userInterfaceIdiom == .phone { app.buttons["terminal-number-toggle"].tap() }
        else { app.buttons["terminal-controls"].tap(); app.buttons["session-action-moreKeys"].tap() }
        reveal(app.buttons["terminal-keypad-number-7"], app: app)
        XCTAssertTrue(app.buttons["terminal-keypad-number-7"].exists)
        app.buttons["terminal-keypad-number-7"].tap(); app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .portrait
        if app.buttons["terminal-keyboard-toggle"].label == "Show Keyboard" { app.buttons["terminal-keyboard-toggle"].tap() }
        capture("terminal-returned-to-portrait", app: app)
        XCTAssertTrue(app.buttons["↑"].waitForExistence(timeout: 5))
        capture("terminal-portrait-restores-expanded-bar", app: app)
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
        app.buttons["terminal-control-add"].tap()
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
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
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
        app.buttons["terminal-row-preview-" + itemID].tap()
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
        XCTAssertTrue(app.buttons["terminal-keypad-Ctrl"].waitForExistence(timeout: 5))
        capture("keypad-accessibility-xxxl", app: app)
        app.buttons["terminal-keypad-Ctrl"].tap()
        XCTAssertTrue(app.buttons["terminal-keypad-Ctrl"].label.contains("Next Key"))
        app.buttons["Done"].tap()
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
