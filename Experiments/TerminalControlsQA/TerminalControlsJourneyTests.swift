import XCTest
import StoreKitTest
import UIKit

@MainActor final class TerminalControlsJourneyTests: XCTestCase {
    override func setUp() { super.setUp(); executionTimeAllowance = 360 }
    private let itemID = "00000000-0000-0000-0000-00000000C001"
    private let mainID = "00000000-0000-0000-0000-000000000101"
    private func capture(_ name: String, app: XCUIApplication) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<18 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func revealHorizontal(_ element: XCUIElement, scroll: XCUIElement) {
        for _ in 0..<18 {
            if element.isHittable && element.frame.intersection(scroll.frame).width >= min(40, element.frame.width) { return }
            let backward = !element.frame.isEmpty && element.frame.midX < scroll.frame.midX
            let from = scroll.coordinate(withNormalizedOffset: .init(dx: backward ? 0.25 : 0.75, dy: 0.5))
            let to = scroll.coordinate(withNormalizedOffset: .init(dx: backward ? 0.75 : 0.25, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTFail("Key unreachable: " + element.debugDescription)
    }
    private func searchCatalog(_ text: String, app: XCUIApplication) {
        let page = app.segmentedControls["terminal-add-page"]
        if page.exists { page.buttons["Keys"].tap() }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != "Find a key or saved item" { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(text + "\n")
    }
    private func togglePreview(_ app: XCUIApplication) {
        if app.navigationBars["Keyboard Preview"].exists {
            app.navigationBars["Keyboard Preview"].buttons["Close"].tap()
            XCTAssertTrue(app.buttons["terminal-layout-cancel"].waitForExistence(timeout: 5))
        } else {
            app.buttons["terminal-row-options"].tap()
            app.buttons["terminal-preview-keyboard"].tap()
            XCTAssertTrue(app.navigationBars["Keyboard Preview"].waitForExistence(timeout: 5))
            // XCTest activates the Simulator's software keyboard when typing;
            // the disposable preview deliberately discards this input.
            app.typeText(" ")
        }
    }
    private func addRowPreset(_ name: String, app: XCUIApplication) {
        app.buttons["terminal-add-row"].tap()
        let template = app.buttons["terminal-row-template-" + name]
        XCTAssertTrue(template.waitForExistence(timeout: 5)); reveal(template, app: app); template.tap()
        if app.buttons["Add Row & Move Keys"].waitForExistence(timeout: 1) { app.buttons["Add Row & Move Keys"].tap() }
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
    }
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["controls-qa-open"].waitForExistence(timeout: 5)); app.buttons["controls-qa-open"].tap()
        XCTAssertTrue(app.buttons["terminal-edit-keyboard"].waitForExistence(timeout: 5))
    }
    private func openKeyboard(_ app: XCUIApplication) {
        openSettings(app); app.buttons["terminal-edit-keyboard"].tap()
        XCTAssertTrue(app.buttons["terminal-layout-cancel"].waitForExistence(timeout: 5))
    }
    private func closeLayout(_ app: XCUIApplication, save: Bool) {
        if app.navigationBars["Keyboard Preview"].exists { togglePreview(app) }
        app.buttons[save ? "terminal-controls-save" : "terminal-layout-cancel"].tap()
        if !save, app.buttons["Discard Changes"].waitForExistence(timeout: 1) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.buttons["terminal-edit-keyboard"].waitForExistence(timeout: 5) || app.navigationBars["Shortcuts"].exists || app.navigationBars["Saved Text"].exists)
    }
    private func library(_ app: XCUIApplication, text: Bool = false) {
        openSettings(app); app.buttons[text ? "terminal-edit-text" : "terminal-edit-shortcuts"].tap()
        XCTAssertTrue(app.navigationBars[text ? "Saved Text" : "Shortcuts"].waitForExistence(timeout: 5))
    }
    private func switchToText(_ app: XCUIApplication) {
        app.navigationBars["Shortcuts"].buttons.element(boundBy: 0).tap()
        app.buttons["terminal-edit-text"].tap()
        XCTAssertTrue(app.navigationBars["Saved Text"].waitForExistence(timeout: 5))
    }
    private func addToRow(_ id: String, app: XCUIApplication) {
        app.buttons["terminal-row-menu-" + id].tap()
        app.buttons["Add Key"].tap()
    }
    private func closeSettings(_ app: XCUIApplication) {
        let done = app.buttons["terminal-controls-cancel"]
        if !done.exists {
            for title in ["Shortcuts", "Saved Text"] where app.navigationBars[title].exists {
                app.navigationBars[title].buttons.element(boundBy: 0).tap()
                break
            }
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    }
    private func selectProject(_ app: XCUIApplication) {
        let key = app.buttons["terminal-row-preview-" + itemID]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        revealHorizontal(key, scroll: app.scrollViews["terminal-row-preview-scroll"]); key.tap()
        app.buttons["terminal-edit-selected"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
    }
    private func addPrefix(_ app: XCUIApplication) {
        app.buttons["terminal-tool-presets-tmux"].tap()
        XCTAssertTrue(app.buttons["terminal-preset-tmux.prefix"].waitForExistence(timeout: 5))
        app.buttons["terminal-preset-tmux.prefix"].tap()
        capture("preset-tmux-selection", app: app)
        app.buttons["terminal-presets-add"].tap()
        XCTAssertTrue(app.staticTexts["Tmux Prefix"].waitForExistence(timeout: 5))
    }
    private func actions(_ name: String, app: XCUIApplication) {
        let button = app.buttons["Actions for " + name]
        reveal(button, app: app); button.tap()
    }
    private func live(_ app: XCUIApplication) {
        app.buttons["controls-qa-live"].tap()
        XCTAssertTrue(app.buttons["terminal-controls"].waitForExistence(timeout: 20))
    }
    private func assertInput(_ expected: String, app: XCUIApplication) async {
        let predicate = NSPredicate(format: "label == %@", "Input: " + expected)
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: app.staticTexts["controls-qa-input"])], timeout: 8)
    }
    private func palette(_ app: XCUIApplication) {
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-moreKeys"].tap()
        XCTAssertTrue(app.navigationBars["All Keys"].waitForExistence(timeout: 5))
    }
    private func findKey(_ query: String, app: XCUIApplication) {
        let field = app.textFields["terminal-keypad-search"]; field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != "Find a key or group" { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(query + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Search must dismiss its keyboard before the next key interaction")
    }
    private func rename(_ name: String, app: XCUIApplication, up: Bool = true, field target: XCUIElement? = nil) async throws {
        let field = target ?? app.textFields["terminal-control-name"]
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
        try await waitForSoftwareKeyboard(app)
    }
    private func launchPro(failWriteOnce: Bool = false) async throws -> (XCUIApplication, SKTestSession) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launchEnvironment["MACCOMPANION_CONTROLS_FUNCTIONAL_TEST"] = "1"
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", (name.contains("testAccessibility") ? UIContentSizeCategory.accessibilityExtraExtraExtraLarge : .large).rawValue]
        if name.contains("testInteractiveReview"), ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] == "1" { app.launchEnvironment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] = "1" }
        if name.contains("testCommand") { app.launchEnvironment["MACCOMPANION_COMMAND_QA"] = "1" }
        if name.contains("testFailedSave") { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_WRITE"] = "1" }
        if failWriteOnce { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_WRITE_ONCE"] = "1" }
        if name.contains("testDirectLibraryRecovery") { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_READ_ONCE"] = "1" }
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
        await fulfillment(of: [expectation(for: visible, evaluatedWith: nil)], timeout: 10)
        guard keyboard.exists && space.isHittable else {
            capture("software-keyboard-unavailable", app: app)
            let diagnostic = XCTAttachment(string: app.debugDescription); diagnostic.name = "software-keyboard-tree"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            throw NSError(domain: "TerminalControlsJourneyTests.Keyboard", code: 1)
        }
    }

    func testCompleteSharedShortcutJourney() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); capture("redesign-controls-library", app: app); addPrefix(app)
        actions("Tmux Prefix", app: app); app.buttons["Add to Keyboard Bar"].tap()
        XCTAssertTrue(app.buttons["terminal-layout-cancel"].waitForExistence(timeout: 5))
        addToRow(mainID, app: app)
        capture("redesign-shortcut-in-keyboard", app: app); closeLayout(app, save: true)
        actions("Tmux Prefix", app: app); app.buttons["Add to Floating Menu"].tap()
        XCTAssertTrue(app.buttons["terminal-layout-cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-action-moreKeys"].exists)
        XCTAssertTrue(app.buttons["terminal-full-menu-preview"].exists)
        capture("redesign-complete-menu-preview", app: app); closeLayout(app, save: true)
        app.staticTexts["Tmux Prefix"].tap()
        try await rename("Tmux", app: app)
        XCTAssertTrue(app.staticTexts["Saving updates this item everywhere it is used."].exists)
        capture("redesign-edit-shared-shortcut", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Tmux"].waitForExistence(timeout: 5))
        actions("Tmux", app: app); app.buttons["Add to Keyboard Bar"].tap()
        addToRow(mainID, app: app)
        let prefixCopies = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-preview-", "Tmux"))
        XCTAssertEqual(prefixCopies.count, 2)
        let prefixKey = prefixCopies.element(boundBy: 1)
        revealHorizontal(prefixKey, scroll: app.scrollViews["terminal-row-preview-scroll"]); prefixKey.tap()
        app.buttons["terminal-remove-placement"].tap()
        XCTAssertEqual(prefixCopies.count, 1)
        capture("redesign-removed-keyboard-placement", app: app); closeLayout(app, save: true)
        XCTAssertTrue(app.staticTexts["Tmux"].exists)
        capture("redesign-still-saved-and-in-menu", app: app)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 2")
    }

    func testNestedEditsCancelAsOneLayoutDraftAndSaveOnce() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app); XCTAssertFalse(app.keyboards.firstMatch.exists); selectProject(app)
        try await rename("Cancelled", app: app)
        app.buttons["terminal-item-save"].tap()
        capture("redesign-local-draft-applied", app: app)
        closeLayout(app, save: false); app.buttons["terminal-controls-cancel"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
        openKeyboard(app); selectProject(app)
        try await rename("Saved Project", app: app); app.buttons["terminal-item-save"].tap()
        closeLayout(app, save: true); app.buttons["terminal-controls-cancel"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Saved Project")
        openKeyboard(app); selectProject(app)
        XCTAssertEqual(app.textFields["terminal-control-name"].value as? String, "Saved Project")
        capture("redesign-saved-and-reopened", app: app)
    }

    func testCreateUppercaseShortcutAndSavedTextInFocusedEditors() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Uppercase B")
        try await waitForSoftwareKeyboard(app)
        app.buttons["terminal-choose-key"].tap()
        let character = app.textFields["terminal-key-character"]; character.tap()
        character.typeText(XCUIKeyboardKey.delete.rawValue + "B")
        try await waitForSoftwareKeyboard(app)
        XCTAssertEqual(character.value as? String, "B")
        XCTAssertTrue(app.buttons["terminal-use-character"].isEnabled)
        capture("redesign-choose-terminal-key", app: app)
        app.buttons["terminal-use-character"].tap()
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in !app.buttons["terminal-use-character"].exists }, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(app.staticTexts["terminal-shortcut-preview"].label, "Sends B.")
        capture("redesign-uppercase-shortcut", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Uppercase B"].waitForExistence(timeout: 5))
        switchToText(app); app.buttons["terminal-library-create"].tap()
        app.textFields["terminal-control-name"].tap(); app.textFields["terminal-control-name"].typeText("Project Path")
        let editor = app.textViews.firstMatch; editor.tap()
        try await waitForSoftwareKeyboard(app)
        editor.typeText("cd ~/Projects")
        try await waitForSoftwareKeyboard(app)
        capture("redesign-focused-saved-text", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Project Path"].waitForExistence(timeout: 5))
        capture("redesign-shared-text-library", app: app)
    }

    func testAllToolPresetOptionsAndIdempotentSelection() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-tool-presets-tmux"].tap()
        app.buttons["terminal-preset-tmux.prefix"].tap(); app.buttons["terminal-preset-tmux.window"].tap()
        capture("redesign-tmux-presets", app: app); app.buttons["terminal-presets-add"].tap()
        app.buttons["terminal-tool-presets-zellij"].tap()
        app.buttons["terminal-preset-zellij.pane"].tap()
        capture("redesign-zellij-default-presets", app: app)
        app.segmentedControls["terminal-preset-tool"].buttons["Unlock First"].tap()
        app.buttons["terminal-preset-zellijUnlock.unlock"].tap()
        capture("redesign-zellij-unlock-presets", app: app); app.buttons["terminal-presets-add"].tap()
        app.buttons["terminal-tool-presets-herdr"].tap(); app.buttons["terminal-preset-herdr.prefix"].tap()
        capture("redesign-herdr-presets", app: app); app.buttons["terminal-presets-add"].tap()
        app.buttons["terminal-tool-presets-tmux"].tap()
        XCTAssertFalse(app.buttons["terminal-preset-tmux.prefix"].isEnabled)
        capture("redesign-presets-already-added", app: app)
    }

    func testContinuousRowsOptionalKeyboardLibraryRestoreAndUndo() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app); capture("focused-keyboard-default", app: app)
        XCTAssertFalse(app.segmentedControls["terminal-add-page"].exists)
        XCTAssertFalse(app.buttons["terminal-editor-undo"].exists)
        for _ in 0..<2 {
            togglePreview(app); try await waitForSoftwareKeyboard(app)
            app.typeText("preview only"); capture("focused-optional-keyboard", app: app)
            togglePreview(app)
            await fulfillment(of: [expectation(for: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, evaluatedWith: nil)], timeout: 8)
        }
        addRowPreset("Function Keys", app: app); capture("focused-function-row-added", app: app)
        app.buttons["terminal-row-options"].tap(); app.buttons["Restore Keyboard Bar…"].tap(); app.buttons["Restore Layout"].tap()
        app.buttons["terminal-editor-undo"].tap()
        XCTAssertTrue(app.buttons["terminal-preview-item-palette-key-f1"].exists)
        for title in ["Symbols", "Blank"] { addRowPreset(title, app: app) }
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-handle-")).count, 6)
        app.buttons["terminal-add-row"].tap(); app.buttons["terminal-row-template-Blank"].tap()
        XCTAssertTrue(app.staticTexts["terminal-add-error"].waitForExistence(timeout: 5)); capture("focused-row-limit-explained", app: app)
        app.navigationBars["Add Row"].buttons["Close"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft; capture("focused-keyboard-landscape", app: app)
        XCTAssertTrue(app.buttons["terminal-layout-cancel"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        let portraitWorkspace = NSPredicate { _, _ in
            let options = app.buttons["terminal-row-options"]
            return app.frame.height > app.frame.width && app.staticTexts["Your keyboard"].isHittable
                && options.isHittable && options.frame.maxY < app.frame.midY
        }
        await fulfillment(of: [expectation(for: portraitWorkspace, evaluatedWith: nil)], timeout: 8)
        togglePreview(app); try await waitForSoftwareKeyboard(app)
        closeLayout(app, save: false)
        app.buttons["terminal-edit-keyboard"].tap(); togglePreview(app); try await waitForSoftwareKeyboard(app)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
    }

    func testLiveCustomizationPausesInputAndReturnsToResponsiveKeyboard() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app)
        let keyboard = app.buttons["terminal-keyboard-toggle"]
        revealHorizontal(keyboard, scroll: app.scrollViews["terminal-modifier-keys"]); keyboard.tap()
        try await waitForSoftwareKeyboard(app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-customize"].tap()
        app.buttons["terminal-edit-keyboard"].tap()
        XCTAssertFalse(app.otherElements["terminal-session-context-preview"].exists)
        capture("workspace-live-session-background-hidden", app: app)
        togglePreview(app); try await waitForSoftwareKeyboard(app)
        app.typeText("never sent"); await assertInput("", app: app)
        capture("redesign-live-input-paused", app: app)
        togglePreview(app)
        closeLayout(app, save: true); app.buttons["terminal-controls-cancel"].tap()
        try await waitForSoftwareKeyboard(app)
        app.typeText("q"); await assertInput("71", app: app)
        capture("redesign-live-responsive-after-save", app: app)
    }

    func testRuntimeShortcutsTextReviewAndDirectSharedManagement() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app); app.buttons["terminal-controls"].tap()
        app.buttons["session-action-savedShortcuts"].tap()
        capture("redesign-runtime-shortcuts-send", app: app)
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C004"].tap()
        await assertInput("02", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedText"].tap()
        let search = app.textFields["terminal-saved-search"]; search.tap(); search.typeText("Multiline\n")
        app.buttons["terminal-saved-00000000-0000-0000-0000-00000000C003"].tap()
        XCTAssertTrue(app.buttons["compose-send"].waitForExistence(timeout: 5))
        await assertInput("02", app: app); capture("redesign-runtime-saved-text-review", app: app)
        app.buttons["compose-send"].tap()
        XCTAssertTrue(app.alerts["Send line breaks or tabs?"].waitForExistence(timeout: 5))
        capture("redesign-runtime-multiline-confirmation", app: app)
        app.alerts.buttons["Cancel"].tap(); app.buttons["compose-back"].tap()
        await assertInput("02", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedShortcuts"].tap()
        app.buttons["terminal-saved-manage"].tap()
        XCTAssertTrue(app.navigationBars["Shortcuts"].waitForExistence(timeout: 5))
        capture("redesign-direct-manage-shared-library", app: app)
    }

    func testAddedToolPresetsSendOnlyTheirOwnChord() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app); app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedShortcuts"].tap()
        app.buttons["terminal-saved-manage"].tap()
        app.buttons["terminal-tool-presets-tmux"].tap()
        app.buttons["terminal-preset-tmux.prefix"].tap(); app.buttons["terminal-preset-tmux.window"].tap()
        app.buttons["terminal-presets-add"].tap(); closeSettings(app)
        await assertInput("", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedShortcuts"].tap()
        app.staticTexts["Tmux Prefix"].tap(); await assertInput("02", app: app)
        app.buttons["terminal-controls"].tap(); app.buttons["session-action-savedShortcuts"].tap()
        capture("redesign-added-presets-runtime", app: app)
        app.staticTexts["Tmux New Window"].tap(); await assertInput("0263", app: app)
        capture("redesign-prefix-then-command-two-explicit-taps", app: app)
    }

    func testRuntimeAllKeysOneShotHeldModifiersAndPlacementNeverSends() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app); palette(app); capture("redesign-all-keys-medium-sheet", app: app)
        XCTAssertFalse(app.segmentedControls["terminal-keypad-page"].exists)
        let ctrl = app.buttons["terminal-keypad-Ctrl"]
        ctrl.tap(); findKey("Home", app: app); app.buttons["terminal-keypad-home"].tap()
        XCTAssertEqual(ctrl.value as? String, "Off")
        ctrl.press(forDuration: 0.7); findKey("End", app: app); app.buttons["terminal-keypad-end"].tap()
        XCTAssertEqual(ctrl.value as? String, "On"); capture("redesign-modifier-held-on", app: app); ctrl.tap()
        findKey("F8", app: app)
        for _ in 0..<2 { app.buttons["terminal-keypad-f8"].press(forDuration: 1); app.buttons["Pin to Keyboard Bar"].tap() }
        await assertInput("1b5b313b35481b5b313b3546", app: app)
        capture("redesign-all-keys-pin-without-send", app: app)
        app.buttons["terminal-keypad-f8"].tap()
        await assertInput("1b5b313b35481b5b313b35461b5b31397e", app: app)
        app.navigationBars["All Keys"].buttons["Done"].tap()
        let copies = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-action-", "F8"))
        XCTAssertEqual(copies.count, 2)
        revealHorizontal(copies.element(boundBy: 1), scroll: app.scrollViews["terminal-modifier-keys"])
        capture("keypad-repeated-pins-create-independent-copies", app: app)
    }

    func testRowTemplateAdditionAndRemovalAreUndoable() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app); addRowPreset("Function Keys", app: app)
        let menu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "terminal-row-menu-", "Row 1")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
        app.buttons["Remove Row"].tap()
        // iOS may expose both the SwiftUI action and its UIKit button.
        app.buttons["terminal-remove-row"].firstMatch.tap()
        XCTAssertFalse(app.buttons["terminal-preview-item-palette-key-f1"].exists)
        app.buttons["terminal-editor-undo"].tap(); XCTAssertTrue(app.buttons["terminal-preview-item-palette-key-f1"].exists)
        capture("focused-row-remove-undone", app: app); closeLayout(app, save: true)
    }

    func testDeleteSavedItemConfirmsAndRemovesEveryPlacement() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app, text: true)
        let item = app.buttons["terminal-library-" + itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        actions("Project", app: app); app.buttons["Delete…"].tap()
        capture("redesign-delete-shared-item-confirmation", app: app)
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.navigationBars["Saved Text"].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(item.exists)
        actions("Project", app: app); app.buttons["Delete…"].tap()
        app.buttons["Delete Saved Item"].tap()
        XCTAssertTrue(app.staticTexts["No Saved Text"].waitForExistence(timeout: 5))
        capture("redesign-shared-text-empty-after-delete", app: app)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 0")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        openKeyboard(app)
        XCTAssertFalse(app.buttons["terminal-row-preview-" + itemID].exists)
        closeLayout(app, save: false)
        app.buttons["terminal-edit-menu"].tap()
        XCTAssertFalse(app.buttons["preview-action-" + itemID].exists)
        capture("redesign-no-remaining-placement-after-delete", app: app)
    }

    func testFailedSaveKeepsLayoutDraftOpenAndCancelable() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app); selectProject(app)
        try await rename("Unsaved", app: app); app.buttons["terminal-item-save"].tap()
        app.buttons["terminal-controls-save"].tap()
        XCTAssertTrue(app.buttons["terminal-layout-cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Couldn’t save.")).firstMatch.exists)
        capture("redesign-failed-save-draft-remains-open", app: app)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
    }

    func testNativeDragMovesAKeyAndReordersRows() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        let tab = app.buttons["terminal-preview-item-palette-key-tab"]
        let home = app.buttons["terminal-preview-item-palette-key-home"]
        tab.press(forDuration: 0.8, thenDragTo: home, withVelocity: .slow, thenHoldForDuration: 0.3)
        let navigation = app.scrollViews["terminal-row-preview-scroll-00000000-0000-0000-0000-000000000103"]
        XCTAssertTrue(navigation.buttons["terminal-preview-item-palette-key-tab"].exists)
        capture("redesign-native-key-drag", app: app)
        let numbers = app.descendants(matching: .any)["terminal-row-handle-00000000-0000-0000-0000-000000000102"]
        let main = app.descendants(matching: .any)["terminal-row-handle-" + mainID]
        numbers.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: main.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.85)), withVelocity: .slow, thenHoldForDuration: 0.1)
        capture("redesign-native-row-drag", app: app)
        closeLayout(app, save: true); app.buttons["terminal-controls-cancel"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-row-order"].label, "Rows: Navigation | Main Row | Numbers")
        openKeyboard(app)
        let reopenedNumbers = app.descendants(matching: .any)["terminal-row-handle-00000000-0000-0000-0000-000000000102"]
        let navigationHandle = app.descendants(matching: .any)["terminal-row-handle-00000000-0000-0000-0000-000000000103"]
        XCTAssertGreaterThan(reopenedNumbers.frame.midY, app.descendants(matching: .any)["terminal-row-handle-" + mainID].frame.midY)
        capture("workspace-row-order-persists-after-reopen", app: app)
        reopenedNumbers.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: navigationHandle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 0.1)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-row-order"].label, "Rows: Numbers | Navigation | Main Row")
    }

    func testFocusedWorkspaceShowsOnlyLayoutAndCancelsChanges() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        XCTAssertFalse(app.segmentedControls["terminal-add-page"].exists)
        XCTAssertFalse(app.scrollViews["terminal-workspace-catalog"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("focused-layout-without-standing-catalog", app: app)
        addRowPreset("Blank", app: app)
        let custom = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "terminal-row-menu-", "Row 1")).firstMatch
        XCTAssertTrue(custom.exists)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-row-order"].label, "Rows: Numbers | Navigation | Main Row")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
    }

    func testWorkspaceKeysAndSavedItemsUseSelectedRowAndUndo() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        let navID = "00000000-0000-0000-0000-000000000103"
        addToRow(navID, app: app)
        searchCatalog("F8", app: app); capture("focused-add-key-picker", app: app)
        app.buttons["terminal-add-key-f8"].tap()
        let navigation = app.scrollViews["terminal-row-preview-scroll-" + navID]
        let f8 = navigation.buttons["terminal-preview-item-palette-key-f8"]
        XCTAssertTrue(f8.waitForExistence(timeout: 5)); capture("focused-key-added", app: app)
        addToRow(navID, app: app); searchCatalog("F8", app: app)
        app.buttons["terminal-add-key-f8"].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        let copies = navigation.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-preview-item-palette-key-f8"))
        XCTAssertEqual(copies.count, 2)
        let second = copies.element(boundBy: 1)
        revealHorizontal(second, scroll: navigation); second.tap(); app.buttons["terminal-remove-placement"].tap()
        XCTAssertEqual(copies.count, 1)
        revealHorizontal(f8, scroll: navigation); f8.tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("F9", app: app); app.buttons["terminal-add-key-f9"].tap()
        let f9 = navigation.buttons["terminal-preview-item-palette-key-f9"]
        XCTAssertTrue(f9.waitForExistence(timeout: 5)); XCTAssertFalse(f8.exists)
        revealHorizontal(f9, scroll: navigation); f9.tap(); app.buttons["terminal-remove-placement"].tap()
        XCTAssertFalse(f9.exists); app.buttons["terminal-editor-undo"].tap(); XCTAssertTrue(f9.exists)
        addToRow(navID, app: app)
        app.segmentedControls["terminal-add-page"].buttons["Text"].tap()
        app.buttons["terminal-reuse-" + itemID].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["terminal-row-preview-scroll"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-preview-" + itemID)).firstMatch.exists)
        XCTAssertTrue(navigation.buttons["terminal-row-preview-" + itemID].waitForExistence(timeout: 5))
        capture("focused-saved-item-reused", app: app)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        openKeyboard(app)
        XCTAssertTrue(app.scrollViews["terminal-row-preview-scroll-" + navID].buttons["terminal-row-preview-" + itemID].exists)
    }

    func testSixRowDragScrollsAtEdgeAndSavesExactOrderInLandscape() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        for _ in 0..<3 { addRowPreset("Blank", app: app) }
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-handle-")).count, 6)
        XCUIDevice.shared.orientation = .landscapeLeft
        let numberID = "terminal-row-handle-00000000-0000-0000-0000-000000000102"
        let number = app.descendants(matching: .any)[numberID]
        let bars = app.scrollViews.containing(.any, identifier: numberID).firstMatch
        for _ in 0..<8 {
            if number.isHittable && bars.frame.contains(number.frame) { break }
            let below = number.frame.midY > bars.frame.midY
            bars.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: below ? 0.7 : 0.3)).press(forDuration: 0.05,
                thenDragTo: bars.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: below ? 0.3 : 0.7)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(number.isHittable && bars.frame.contains(number.frame), app.debugDescription)
        capture("focused-six-rows-landscape", app: app)
        number.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: bars.coordinate(withNormalizedOffset: .init(dx: 0.08, dy: 0.98)), withVelocity: .slow, thenHoldForDuration: 2)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertTrue(app.staticTexts["controls-qa-row-order"].label.hasSuffix("Main Row | Numbers"))
        XCUIDevice.shared.orientation = .portrait
    }

    func testAccessibilityEditorsAndKeypadRemainReachable() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        let mainRow = app.descendants(matching: .any)["terminal-row-handle-" + mainID]
        XCTAssertTrue(mainRow.isHittable)
        XCTAssertTrue(app.buttons["terminal-add-row"].isHittable)
        capture("focused-keyboard-accessibility", app: app)
        app.buttons["terminal-add-row"].tap()
        XCTAssertTrue(app.buttons["terminal-row-template-Numbers"].waitForExistence(timeout: 5))
        capture("focused-row-picker-accessibility", app: app)
        app.navigationBars["Add Row"].buttons["Close"].tap()
        closeLayout(app, save: false); app.buttons["terminal-edit-menu"].tap()
        let favorite = app.buttons["preview-action-" + itemID]
        reveal(favorite, app: app, up: false); favorite.tap()
        XCTAssertTrue(app.buttons["terminal-edit-selected"].waitForExistence(timeout: 5)); capture("focused-menu-item-accessibility", app: app)
        app.navigationBars["Project"].buttons["Close"].tap()
        capture("focused-menu-accessibility", app: app)
        closeLayout(app, save: false); app.buttons["terminal-controls-cancel"].tap()
        live(app); palette(app); capture("focused-keypad-accessibility", app: app)
        let ctrl = app.buttons["terminal-keypad-Ctrl"]; reveal(ctrl, app: app); ctrl.tap()
        XCTAssertEqual(ctrl.value as? String, "Next Key")
    }

    func testMenuFavoritesAddEditReorderRemoveAndPreview() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        XCTAssertFalse(app.buttons["session-action-moreKeys"].exists)
        capture("focused-menu-default", app: app)
        app.buttons["terminal-control-add"].tap(); searchCatalog("Home", app: app)
        app.buttons["terminal-add-key-home"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        app.buttons["Home"].tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("F8", app: app); app.buttons["terminal-add-key-f8"].tap()
        XCTAssertTrue(app.buttons["F8"].waitForExistence(timeout: 5))
        capture("focused-menu-key-replaced", app: app)
        app.buttons["F8"].tap(); app.buttons["terminal-remove-placement"].tap()
        XCTAssertFalse(app.buttons["F8"].exists); app.buttons["terminal-editor-undo"].tap()
        XCTAssertTrue(app.buttons["F8"].waitForExistence(timeout: 5))
        let project = app.buttons["preview-action-" + itemID]
        project.press(forDuration: 0.8, thenDragTo: app.buttons["F8"], withVelocity: .slow, thenHoldForDuration: 0.2)
        capture("focused-menu-favorite-reordered", app: app)
        app.buttons["terminal-full-menu-preview"].tap()
        XCTAssertTrue(app.navigationBars["Menu Preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-action-session"].exists)
        capture("focused-full-menu-passive-preview", app: app)
        app.navigationBars["Menu Preview"].buttons["Close"].tap()
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-menu-order"].label, "Favorites: F8 | Project")
    }

    func testInlineCreationFromBothLayoutsAndSharedEditing() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app); addToRow(mainID, app: app)
        app.segmentedControls["terminal-add-page"].buttons["Shortcuts"].tap()
        app.buttons["terminal-create-inline"].tap()
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["terminal-item-validation"].exists)
        app.textFields["terminal-control-name"].tap(); app.textFields["terminal-control-name"].typeText("My Prefix")
        app.buttons["terminal-shortcut-modifier-Ctrl"].tap(); app.buttons["terminal-choose-key"].tap()
        let character = app.textFields["terminal-key-character"]; character.tap(); character.typeText(XCUIKeyboardKey.delete.rawValue + "b")
        app.buttons["terminal-use-character"].tap(); app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5)); capture("focused-inline-shortcut-added", app: app)
        closeLayout(app, save: true); app.buttons["terminal-edit-menu"].tap()
        app.buttons["terminal-control-add"].tap(); app.segmentedControls["terminal-add-page"].buttons["Shortcuts"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "terminal-reuse-", "My Prefix")).firstMatch.tap()
        XCTAssertTrue(app.buttons["My Prefix"].waitForExistence(timeout: 5))
        app.buttons["My Prefix"].tap(); app.buttons["terminal-edit-selected"].tap()
        try await rename("Shared Prefix", app: app); app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.buttons["Shared Prefix"].waitForExistence(timeout: 5))
        app.buttons["terminal-control-add"].tap(); app.segmentedControls["terminal-add-page"].buttons["Text"].tap()
        app.buttons["terminal-create-inline"].tap()
        app.textFields["terminal-control-name"].tap(); app.textFields["terminal-control-name"].typeText("Status")
        let text = app.textViews.firstMatch; text.tap(); text.typeText("git status --short")
        capture("focused-inline-text-editor", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.buttons["Status"].waitForExistence(timeout: 5))
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 2")
        openKeyboard(app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-preview-", "Shared Prefix")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        revealHorizontal(saved, scroll: app.scrollViews["terminal-row-preview-scroll"])
        capture("focused-shared-edit-in-keyboard", app: app)
    }

    func testMenuFavoritesCancelAndRestoreRemainOneDraft() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        app.buttons["terminal-control-add"].tap(); searchCatalog("Home", app: app); app.buttons["terminal-add-key-home"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        app.buttons["terminal-menu-options"].tap(); app.buttons["Restore Menu Favorites…"].tap(); app.buttons["Restore Favorites"].tap()
        XCTAssertFalse(app.buttons["preview-action-" + itemID].exists)
        capture("focused-menu-restored-defaults", app: app)
        app.buttons["terminal-editor-undo"].tap()
        XCTAssertTrue(app.buttons["preview-action-" + itemID].exists); XCTAssertTrue(app.buttons["Home"].exists)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
    }

    func testUnavailableCustomizationExplainsAccessAndCanClose() async throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launchEnvironment["MACCOMPANION_CONTROLS_FUNCTIONAL_TEST"] = "1"; app.launch()
        defer { app.terminate(); store.clearTransactions() }
        XCTAssertTrue(app.staticTexts["controls-qa-pro"].waitForExistence(timeout: 10))
        for _ in 0..<5 where app.staticTexts["Pro ready"].exists { app.buttons["controls-qa-refresh-pro"].tap() }
        openSettings(app); app.buttons["terminal-edit-keyboard"].tap()
        XCTAssertTrue(app.staticTexts["Customization Unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["terminal-add-row"].exists)
        XCTAssertTrue(app.buttons["terminal-controls-save"].isEnabled)
        capture("focused-unavailable-editor-explained", app: app)
        closeLayout(app, save: true)
    }

    func testDirectLibraryRecoveryOffersReloadWithoutLosingSavedText() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-text"].tap()
        XCTAssertTrue(app.navigationBars["Saved Text"].waitForExistence(timeout: 5))
        let reload = app.buttons["Reload Saved Controls"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5)); XCTAssertTrue(reload.isEnabled)
        XCTAssertFalse(app.buttons["terminal-library-create"].exists)
        capture("direct-library-read-failure-recovery", app: app)
        reload.tap()
        XCTAssertTrue(app.buttons["terminal-library-" + itemID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["terminal-library-create"].isEnabled)
        capture("direct-library-reloaded-saved-text", app: app)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
    }

    func testLibrarySaveRecoveryClearsErrorAndAllowsRetry() async throws {
        let (app, store) = try await launchPro(failWriteOnce: true)
        defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-text"].tap()
        let item = app.buttons["terminal-library-" + itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        actions("Project", app: app); app.buttons["Delete…"].tap()
        app.buttons["Delete Saved Item"].tap()
        let reload = app.buttons["Reload Saved Controls"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        XCTAssertTrue(item.exists, "A failed delete must preserve the saved item")
        capture("library-transient-save-failure", app: app)

        reload.tap()
        XCTAssertTrue(reload.waitForNonExistence(timeout: 5))
        XCTAssertTrue(item.exists)
        XCTAssertFalse(app.staticTexts["Couldn’t save. Close and reload controls before trying again."].exists,
                       "A successful reload must clear every stale save-error message")
        capture("library-successful-reload-clears-save-error", app: app)

        actions("Project", app: app); app.buttons["Delete…"].tap()
        app.buttons["Delete Saved Item"].tap()
        XCTAssertTrue(app.staticTexts["No Saved Text"].waitForExistence(timeout: 5))
        XCTAssertFalse(reload.exists)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 0")
    }

    func testDirectLibraryExplainsProAccessAndOffersUpgrade() async throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launchEnvironment["MACCOMPANION_CONTROLS_FUNCTIONAL_TEST"] = "1"; app.launch()
        defer { app.terminate(); store.clearTransactions() }
        XCTAssertTrue(app.buttons["controls-qa-shortcuts"].waitForExistence(timeout: 10))
        app.buttons["controls-qa-refresh-pro"].tap()
        app.buttons["controls-qa-shortcuts"].tap()
        XCTAssertTrue(app.navigationBars["Shortcuts"].waitForExistence(timeout: 5))
        let upgrade = app.buttons["terminal-library-pro"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 8)); XCTAssertTrue(upgrade.isEnabled)
        XCTAssertFalse(app.buttons["terminal-library-create"].exists)
        capture("direct-library-pro-access-explained", app: app)
        upgrade.tap()
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 5))
        capture("direct-library-pro-options", app: app)
    }

    func testAlignmentMenuAndDockedPreviewLeaveTheDraftUnchanged() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        // A single key makes alignment observable; an overflowing row would
        // have identical geometry even if the menu action were a no-op.
        addRowPreset("Blank", app: app)
        let menu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "terminal-row-menu-", "Row 1")).firstMatch
        let rowID = String(menu.identifier.dropFirst("terminal-row-menu-".count))
        addToRow(rowID, app: app); searchCatalog("F8", app: app); app.buttons["terminal-add-key-f8"].tap()
        let row = app.scrollViews["terminal-row-preview-scroll-" + rowID]
        let key = row.buttons["terminal-preview-item-palette-key-f8"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        menu.tap(); app.buttons["Alignment"].tap(); app.collectionViews.buttons["Right"].tap()
        XCTAssertEqual(key.frame.maxX, row.frame.maxX, accuracy: 1)
        capture("keyboard-row-aligned-right", app: app)
        let before = key.frame
        togglePreview(app); try await waitForSoftwareKeyboard(app)
        capture("docked-keyboard-preview-without-editor-chrome", app: app)
        // Covered SwiftUI screens can remain in the accessibility tree.
        XCTAssertFalse(app.buttons["terminal-add-row"].isHittable)
        XCTAssertFalse(app.buttons["terminal-editor-undo"].isHittable)
        XCTAssertFalse(menu.isHittable)
        app.typeText("preview only")
        togglePreview(app)
        XCTAssertEqual(key.frame, before)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        openKeyboard(app)
        XCTAssertEqual(key.frame.maxX, row.frame.maxX, accuracy: 1)
        capture("keyboard-row-alignment-persists", app: app)
        menu.tap(); app.buttons["Alignment"].tap(); app.collectionViews.buttons["Left"].tap()
        XCTAssertEqual(key.frame.minX, row.frame.minX, accuracy: 1)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        openKeyboard(app)
        XCTAssertEqual(key.frame.maxX, row.frame.maxX, accuracy: 1)
        capture("keyboard-row-cancel-preserves-right-alignment", app: app)
    }

    func testRestoredRowsKeepTheirKeysAfterOptionsSaveAndSavedItemDeletion() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        app.buttons["terminal-row-options"].tap(); app.buttons["Restore Keyboard Bar…"].tap(); app.buttons["Restore Layout"].tap()
        let rowMenu = app.buttons["terminal-row-menu-00000000-0000-0000-0000-000000000102"]
        rowMenu.tap(); app.buttons["Alignment"].tap(); app.collectionViews.buttons["Right"].tap()
        rowMenu.tap(); app.buttons["Scroll Start"].tap(); app.collectionViews.buttons["Right"].tap()
        capture("restored-keyboard-options-before-deletion", app: app)
        closeLayout(app, save: true); closeSettings(app)
        library(app, text: true)
        actions("Project", app: app); app.buttons["Delete…"].tap(); app.buttons["Delete Saved Item"].tap()
        XCTAssertTrue(app.staticTexts["No Saved Text"].waitForExistence(timeout: 5))
        capture("unused-saved-text-deleted", app: app)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 0")
        openKeyboard(app)
        XCTAssertTrue(app.buttons["terminal-preview-item-palette-key-escape"].exists)
        XCTAssertTrue(app.buttons["terminal-preview-item-palette-key-home"].exists)
        XCTAssertTrue(app.buttons["terminal-preview-item-palette-character-49-"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-handle-")).count, 3)
        capture("preset-rows-preserved-after-library-deletion", app: app)
        rowMenu.tap(); app.buttons["Scroll Start"].tap()
        XCTAssertTrue(app.collectionViews.buttons["Right"].isSelected)
        capture("row-scroll-preference-preserved-after-deletion", app: app)
    }

    func testReplaceOneRepeatedFavoritePreservesOtherCopyUndoCancelAndSave() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        for _ in 0..<2 {
            app.buttons["terminal-control-add"].tap(); searchCatalog("Home", app: app)
            app.buttons["terminal-add-key-home"].tap()
            XCTAssertTrue(app.buttons["terminal-control-add"].waitForExistence(timeout: 5))
        }
        let home = app.buttons.matching(NSPredicate(format: "label == %@", "Home"))
        let f8 = app.buttons.matching(NSPredicate(format: "label == %@", "F8"))
        XCTAssertEqual(home.count, 2)
        capture("duplicate-home-favorites-before-replacement", app: app)
        home.element(boundBy: 1).tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("F8", app: app); app.buttons["terminal-add-key-f8"].tap()
        XCTAssertTrue(f8.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(home.count, 1); XCTAssertEqual(f8.count, 1)
        capture("only-selected-home-favorite-replaced", app: app)
        app.buttons["terminal-editor-undo"].tap()
        XCTAssertEqual(home.count, 2); XCTAssertEqual(f8.count, 0)
        capture("favorite-replacement-undone", app: app)
        home.element(boundBy: 1).tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("F8", app: app); app.buttons["terminal-add-key-f8"].tap()
        XCTAssertTrue(f8.firstMatch.waitForExistence(timeout: 5))
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-menu-order"].label, "Favorites: Project | Home | F8")
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        XCTAssertEqual(home.count, 1); XCTAssertEqual(f8.count, 1)
        f8.firstMatch.tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("Home", app: app); app.buttons["terminal-add-key-home"].tap()
        XCTAssertTrue(app.buttons["terminal-control-add"].waitForExistence(timeout: 5)); XCTAssertEqual(home.count, 2)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-menu-order"].label, "Favorites: Project | Home | F8")
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        XCTAssertEqual(home.count, 1); XCTAssertEqual(f8.count, 1)
        capture("favorite-save-persists-and-cancel-keeps-other-copy", app: app)
    }

    func testIndependentCopiesAndOrdinalRowsWithScrollStartSaveAndCancel() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        capture("focused-keyboard-default", app: app)
        for _ in 0..<2 {
            addToRow(mainID, app: app); searchCatalog("F8", app: app); app.buttons["terminal-add-key-f8"].tap()
            XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        }
        let row = app.scrollViews["terminal-row-preview-scroll"]
        let copies = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-preview-item-palette-key-f8"))
        XCTAssertEqual(copies.count, 2)
        revealHorizontal(copies.element(boundBy: 1), scroll: row)
        capture("independent-key-copies-before-removal", app: app)
        copies.element(boundBy: 1).tap(); app.buttons["terminal-remove-placement"].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5)); XCTAssertEqual(copies.count, 1)
        app.buttons["terminal-editor-undo"].tap(); XCTAssertEqual(copies.count, 2)
        let menu = app.buttons["terminal-row-menu-" + mainID]
        XCTAssertTrue(menu.label.contains("Row 3"))
        menu.tap(); app.buttons["Scroll Start"].tap()
        capture("row-scroll-start-options", app: app)
        app.collectionViews.buttons["Right"].tap()
        capture("row-options-scroll-start-right", app: app)
        closeLayout(app, save: true); closeSettings(app)
        openKeyboard(app)
        XCTAssertTrue(copies.element(boundBy: 1).isHittable)
        capture("rightmost-scroll-start-persists-after-save", app: app)
        menu.tap(); app.buttons["Scroll Start"].tap(); app.collectionViews.buttons["Left"].tap()
        closeLayout(app, save: false); closeSettings(app)
        openKeyboard(app); XCTAssertTrue(copies.element(boundBy: 1).isHittable)
        // Full preset additions keep all prior placements.
        addRowPreset("Navigation", app: app)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-row-handle-")).count, 4)
        capture("complete-navigation-preset-with-existing-rows", app: app)
        closeLayout(app, save: true); closeSettings(app)
        openKeyboard(app); addToRow(mainID, app: app)
        app.segmentedControls["terminal-add-page"].buttons["Shortcuts"].tap()
        app.buttons["terminal-tool-presets-tmux"].tap()
        app.buttons["terminal-preset-tmux.prefix"].tap(); app.buttons["terminal-preset-tmux.window"].tap()
        capture("direct-tool-shortcuts-with-after-prefix-group", app: app)
        app.buttons["terminal-presets-add"].tap()
        let command = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-preview-", "Tmux New Window")).firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        revealHorizontal(command, scroll: row)
        capture("compact-prefix-and-command-keycaps", app: app)
        closeLayout(app, save: true); closeSettings(app)
        // Favorites also allow duplicate placements and remove only one copy.
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        for _ in 0..<2 {
            app.buttons["terminal-control-add"].tap()
            app.buttons["terminal-add-action-composeText"].tap()
            XCTAssertTrue(app.buttons["terminal-control-add"].waitForExistence(timeout: 5))
        }
        capture("independent-favorite-copies", app: app)
        // Select through the renderer's descriptive accessibility label.
        let compose = app.buttons.matching(NSPredicate(format: "label == %@", "Compose Text")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(compose.count, 2)
        compose.last!.tap(); app.buttons["terminal-remove-placement"].tap()
        XCTAssertTrue(app.buttons["terminal-control-add"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Compose Text")).allElementsBoundByIndex.filter(\.isHittable).count, compose.count - 1)
        capture("favorite-copy-removed-and-undo-available", app: app)
        closeLayout(app, save: true)
    }

}
