import XCTest
import StoreKitTest
import UIKit

@MainActor final class TerminalControlsJourneyTests: XCTestCase {
    func testTimedSequenceExecutionOverlaySingleRowAndRotation() async throws { try await dockedToolbar(rows: 1, rotate: true) }
    func testTimedSequenceExecutionOverlayFourRowsDark() async throws { try await dockedToolbar(rows: 4) }
    func testTimedSequenceExecutionOverlayAccessibilitySingleRow() async throws { try await dockedToolbar(rows: 1) }
    private func dockedToolbar(rows: Int, rotate: Bool = false) async throws {
        let (app, store) = try await launchPro(dockRows: rows); defer { app.terminate(); store.clearTransactions(); XCUIDevice.shared.orientation = .portrait }
        startSequenceProbe(app)
        let keyboard = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        if keyboard.label == "Hide Keyboard" { keyboard.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        let original = app.otherElements["terminal-keyboard-bar"].firstMatch.frame
        let surface = app.descendants(matching: .any).matching(identifier: "terminal-surface").firstMatch
        XCTAssertTrue(surface.exists)
        let originalSurface = surface.frame
        capture("dock-\(rows)-rows-before-" + (name.contains("Accessibility") ? "large-text" : "normal-text"), app: app)
        let action = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C013"]
        // At accessibility sizes the label can be wider than a scroll gesture.
        // This journey needs its reachable tap target, not full-label exposure.
        if !action.isHittable { revealHorizontal(action, scroll: app.scrollViews["terminal-modifier-keys"]) }
        action.tap()
        let cancel = app.buttons["shortcut-running-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); XCTAssertTrue(cancel.isHittable)
        let cover = app.otherElements["shortcut-execution-blocker"].firstMatch
        XCTAssertEqual(cover.frame.minX, original.minX); XCTAssertEqual(cover.frame.width, original.width)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        XCTAssertTrue(cover.frame.insetBy(dx: -1, dy: -1).contains(cancel.frame), "Cancel must fit inside the dock")
        if !name.contains("Accessibility") { XCTAssertEqual(cover.frame.height, 64) }
        XCTAssertLessThanOrEqual(surface.frame.maxY, cover.frame.minY + 1, "Terminal content must reflow above the dock")
        if rows > 1 && !name.contains("Accessibility") { XCTAssertGreaterThan(surface.frame.height, originalSurface.height) }
        XCTAssertFalse(action.exists, "Keyboard rows must be absent from accessibility while docked")
        await assertInput("740d", app: app)
        capture("dock-\(rows)-rows-running-" + (name.contains("Accessibility") ? "large-text" : "normal-text"), app: app)
        if rotate {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); XCTAssertTrue(cancel.isHittable)
            XCTAssertTrue(cover.frame.insetBy(dx: -1, dy: -1).contains(cancel.frame))
            capture("dock-single-row-landscape", app: app)
        }
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["terminal-keyboard-bar"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements["terminal-keyboard-bar"].firstMatch.frame.height, original.height, "Restore the configured rows after Cancel")
        if !rotate { XCTAssertEqual(surface.frame, originalSurface, "Restore the terminal viewport after Cancel") }
        await assertInput("740d", app: app)
        capture("dock-\(rows)-rows-restored", app: app)
    }
    func testTimedSequenceExecutionOverlayCoversExpandedRowsAndKeyboard() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app)
        let keyboard = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        if keyboard.label == "Show Keyboard" { keyboard.tap() }
        try await waitForSoftwareKeyboard(app)
        let bar = app.otherElements["terminal-keyboard-bar"].firstMatch
        let original = bar.frame
        capture("terminal-keyboard-before-shortcut", app: app)
        runSequenceProbe("C013", review: false, app: app)
        let cancel = app.buttons["shortcut-running-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        let overlay = app.otherElements["shortcut-execution-blocker"].firstMatch
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        XCTAssertFalse(bar.exists, "Covered rows must be hidden from accessibility during execution")
        XCTAssertEqual(overlay.frame.minX, original.minX)
        XCTAssertEqual(overlay.frame.width, original.width)
        XCTAssertEqual(overlay.frame.height, 64)
        XCTAssertFalse(keyboard.exists)
        await assertInput("740d", app: app)
        capture("terminal-dock-over-rows-keyboard-temporarily-hidden", app: app)
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2))
        try await waitForSoftwareKeyboard(app)
        capture("terminal-keyboard-restored-after-cancel", app: app)
        XCTAssertTrue(keyboard.isHittable); keyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        let hiddenKeyboardRows = bar.frame
        capture("terminal-rows-restored-keyboard-hidden", app: app)
        runSequenceProbe("C013", review: false, app: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertEqual(overlay.frame.maxY, hiddenKeyboardRows.maxY)
        XCTAssertEqual(overlay.frame.height, 64, "Expanded rows collapse to a compact dock")
        capture("terminal-dock-over-rows-keyboard-already-hidden", app: app)
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testTimedSequenceImmediateBlockedSSHRejectsCompetingRunAndCancels() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app)
        let second = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C011"]
        let position = second.frame
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: position.minX + position.width * 0.2, dy: position.midY))
        runSequenceProbe("C017", review: false, app: app)
        XCTAssertTrue(app.staticTexts["SSH writer stalled"].waitForExistence(timeout: 5))
        let cancel = app.buttons["shortcut-running-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); point.tap()
        await assertInput("", app: app)
        XCTAssertTrue(cancel.exists); capture("immediate-shortcut-reserves-input-while-ssh-stalled", app: app)
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2))
        runSequenceProbe("C011", review: false, app: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "A blocked no-wait shortcut must also expose progress and Cancel")
        app.buttons["controls-qa-release-write"].tap()
        await assertInput("74070f64", app: app)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
        capture("immediate-cancel-preserves-accepted-write-and-retires-suffix", app: app)
    }

    func testRemoteExecutionOverlayInScreenSharing() async throws { try await remoteExecutionOverlay(mode: "desktop") }
    func testRemoteExecutionOverlayInTrackpadAndKeyboard() async throws { try await remoteExecutionOverlay(mode: "trackpad") }
    private func remoteExecutionOverlay(mode: String) async throws {
        let (app, store) = try await launchPro(remoteMode: mode, executionOverlay: true); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-remote"].tap()
        XCTAssertTrue(app.buttons["remote-qa-edit"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["remote-qa-edit"].value as? String)?.contains("overlay=true; environment=1") == true, app.debugDescription)
        let action = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C020"]
        let quick = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C021"]
        let keyboard = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        action.tap()
        let cancel = app.buttons["shortcut-running-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        XCTAssertFalse(action.isHittable); XCTAssertFalse(quick.isHittable)
        XCTAssertEqual(app.staticTexts["remote-qa-events"].label, "Remote events: 2")
        capture(mode + "-progress-covers-rows-keyboard-hidden", app: app)
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2)); XCTAssertTrue(action.isHittable)
        keyboard.tap(); try await waitForSoftwareKeyboard(app)
        capture(mode + "-keyboard-before-shortcut", app: app)
        action.tap(); XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        capture(mode + "-dock-over-rows-keyboard-temporarily-hidden", app: app)
        cancel.tap(); XCTAssertTrue(cancel.waitForNonExistence(timeout: 2))
        try await waitForSoftwareKeyboard(app)
        capture(mode + "-keyboard-restored-after-cancel", app: app)
        quick.tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", "Remote events: 6"), evaluatedWith: app.staticTexts["remote-qa-events"])], timeout: 3)
        XCTAssertFalse(cancel.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Quick shortcuts must leave the keyboard in place")
        capture(mode + "-quick-shortcut-completes-without-progress-flash", app: app)
        action.tap(); XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        try await waitForSoftwareKeyboard(app)
        XCTAssertEqual(app.staticTexts["remote-qa-events"].label, "Remote events: 10", "Temporary keyboard dismissal must not retire the running shortcut")
        capture(mode + "-keyboard-restored-after-completion", app: app)
    }

    func testShortcutConfirmationSettingDefaultsOffAndPersists() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Confirmation Choice\n"); addSequenceReturn(app)
        let setting = app.switches["shortcut-confirm-before-running"]
        reveal(setting, app: app); XCTAssertEqual(setting.value as? String, "0")
        capture("confirmation-default-off", app: app)
        await setSwitch(setting, on: true, app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Confirmation Choice"].waitForExistence(timeout: 5)); app.staticTexts["Confirmation Choice"].tap()
        reveal(setting, app: app); XCTAssertEqual(setting.value as? String, "1")
        capture("confirmation-setting-saved", app: app)
    }
    func testTimedSequenceConfirmationSkipCancelAndReconnect() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app)
        let action = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C014"]
        let run = app.buttons["shortcut-sequence-send"]
        let skip = app.switches["shortcut-skip-connection-confirmation"]
        action.tap(); XCTAssertTrue(run.waitForExistence(timeout: 5))
        await setSwitch(skip, on: true, app: app); capture("confirm-skip-until-new-connection", app: app)
        app.buttons["Cancel"].firstMatch.tap()
        await assertInput("", app: app)
        action.tap(); XCTAssertTrue(run.waitForExistence(timeout: 5)); XCTAssertEqual(skip.value as? String, "0", "Cancel must not accept the skip choice")
        run.tap(); await assertInput("6f6b0d", app: app)
        action.tap(); XCTAssertTrue(run.waitForExistence(timeout: 5)); await setSwitch(skip, on: true, app: app); run.tap()
        await assertInput("6f6b0d6f6b0d", app: app)
        action.tap(); await assertInput("6f6b0d6f6b0d6f6b0d", app: app); XCTAssertFalse(run.exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Input ready"].waitForExistence(timeout: 10))
        action.tap(); await assertInput("6f6b0d6f6b0d6f6b0d6f6b0d", app: app); XCTAssertFalse(run.exists)
        capture("same-connection-keeps-skip-after-background", app: app)
        app.buttons["controls-qa-reconnect"].tap()
        XCTAssertTrue(app.staticTexts["Input ready"].waitForExistence(timeout: 15)); await assertInput("", app: app)
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap(); XCTAssertTrue(run.waitForExistence(timeout: 5))
        capture("new-connection-requires-confirmation-again", app: app)
    }
    func testTimedSequenceCancelBlockedSSHWriterAndRunAgain() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app); runSequenceProbe("C013", review: false, app: app)
        XCTAssertTrue(app.staticTexts["SSH writer stalled"].waitForExistence(timeout: 5))
        let cancel = app.buttons["shortcut-running-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); capture("blocked-ssh-write-before-cancel", app: app)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 2), "The banner must close while the SSH write remains blocked")
        XCTAssertTrue(app.staticTexts["SSH writer stalled"].exists)
        await assertInput("", app: app); capture("cancel-closes-banner-before-ssh-write-drains", app: app)
        runSequenceProbe("C011", review: false, app: app)
        await assertInput("", app: app)
        app.buttons["controls-qa-release-write"].tap()
        await assertInput("74070f64", app: app)
        XCTAssertFalse(cancel.exists)
        capture("accepted-prefix-then-fresh-shortcut-with-no-canceled-suffix", app: app)
        runSequenceProbe("C011", review: false, app: app); await assertInput("74070f64070f64", app: app)
        XCTAssertFalse(cancel.exists)
    }
    func testTimedSequenceProtocolRepliesAndOutputStayVisible() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app); runSequenceProbe("C016", review: false, app: app)
        let result = app.staticTexts["controls-qa-sequence-result"]
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", "Terminal replies received during wait"), evaluatedWith: result)], timeout: 5)
        XCTAssertTrue(app.buttons["shortcut-running-cancel"].exists)
        XCTAssertTrue(app.staticTexts["shortcut-running-step"].label.contains("remaining"))
        XCTAssertFalse(app.buttons["shortcut-sequence-send"].exists, "Text steps run immediately when confirmation is off")
        capture("nonmodal-progress-with-visible-output-and-terminal-replies", app: app)
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", "Session 1 selected after waiting"), evaluatedWith: result)], timeout: 8)
        XCTAssertTrue(app.staticTexts["controls-qa-input"].label.contains("1b5b306e"))
        XCTAssertFalse(app.buttons["shortcut-running-cancel"].exists)
        capture("terminal-query-flow-completed", app: app)
    }
    func testReturnQuickAddSearchEditAndPersistence() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Return Example\n")
        let addStep = app.buttons["shortcut-add-step"]
        XCTAssertTrue(addStep.isHittable)
        addStep.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        capture("add-step-menu-with-direct-return", app: app)
        for label in ["Return", "Press Key…", "Type Text…", "Paste Text…", "Wait…"] { XCTAssertTrue(sequenceMenuChoice(label, app: app).exists, app.debugDescription) }
        sequenceMenuChoice("Return", app: app).tap()
        XCTAssertFalse(app.buttons["shortcut-step-type"].exists)
        addSequenceReturn(app)
        let preview = app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch
        XCTAssertEqual(preview.label, "↵ Return → ↵ Return")
        capture("return-steps-use-readable-names", app: app)
        openSequenceStep("Press Key", app: app); app.buttons["terminal-choose-key"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find a key")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Enter")
        let key = app.buttons["terminal-choose-character-65293-"]
        XCTAssertTrue(key.waitForExistence(timeout: 5)); XCTAssertEqual(key.label, "Return")
        capture("enter-search-finds-readable-return-key", app: app)
        key.tap()
        XCTAssertTrue(app.buttons["terminal-choose-key"].label.contains("Return"))
        app.buttons["terminal-shortcut-modifier-Ctrl"].tap(); app.buttons["shortcut-step-save"].tap()
        XCTAssertEqual(preview.label, "↵ Return → ↵ Return → ⌃↵ Return")
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Return Example"].waitForExistence(timeout: 5))
        app.staticTexts["Return Example"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
        reveal(preview, app: app)
        XCTAssertEqual(preview.label, "↵ Return → ↵ Return → ⌃↵ Return")
        capture("return-steps-persist-with-modifiers", app: app)
    }
    func testReturnQuickAddCancelKeepsLibraryUnchanged() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Discard Return\n")
        addSequenceReturn(app)
        XCTAssertEqual(app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch.label, "↵ Return")
        app.buttons["terminal-item-cancel"].tap()
        XCTAssertFalse(app.staticTexts["Discard Return"].exists)
        capture("cancel-return-draft-keeps-library-unchanged", app: app)
    }
    func testTimedSequenceEditorSupportsAllFourStepTypesAndPersists() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app); app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Launch and Select\n")
        openSequenceStep("Type Text", app: app)
        let text = app.textViews["shortcut-step-text"]; XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("t")
        selectSequenceKind("Paste Text", app: app)
        XCTAssertEqual(app.textViews["shortcut-step-text"].value as? String, "t")
        selectSequenceKind("Type Text", app: app)
        XCTAssertEqual(app.textViews["shortcut-step-text"].value as? String, "t")
        app.buttons["shortcut-step-save"].tap()
        addSequenceReturn(app)
        openSequenceStep("Wait", app: app)
        XCTAssertTrue(app.steppers["shortcut-wait-duration"].exists)
        capture("wait-step-default-one-second", app: app)
        app.buttons["shortcut-step-save"].tap()
        addSequenceText("1", kind: "Type Text", app: app)
        addSequenceReturn(app)
        addSequenceText("sample", kind: "Paste Text", app: app)
        let preview = app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch
        reveal(preview, app: app)
        XCTAssertTrue(preview.label.contains("Type · t → ↵ Return → Wait 1 s → Type · 1 → ↵ Return → Paste · sample"))
        capture("four-step-types-ordered-editor", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Launch and Select"].waitForExistence(timeout: 5))
        app.staticTexts["Launch and Select"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
        reveal(preview, app: app)
        XCTAssertTrue(preview.label.contains("Wait 1 s")); XCTAssertTrue(preview.label.contains("Paste · sample"))
        capture("four-step-types-persisted", app: app)
    }

    func testTimedSequenceLaunchWaitAndNumericSelectionOverSSH() async throws {
        let (app, store) = try await launchPro(executionOverlay: true); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app)
        let keyboard = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        if keyboard.label == "Show Keyboard" { keyboard.tap() }
        try await waitForSoftwareKeyboard(app)
        runSequenceProbe("C010", review: false, app: app)
        let result = app.staticTexts["controls-qa-sequence-result"]
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", "Session 1 selected after waiting"), evaluatedWith: result)], timeout: 8)
        XCTAssertEqual(app.staticTexts["controls-qa-input"].label, "Input: 740d310d")
        XCTAssertFalse(app.buttons["shortcut-running-cancel"].exists)
        try await waitForSoftwareKeyboard(app)
        capture("t-return-wait-one-second-1-return-success", app: app)
    }

    func testTypedSequenceChordsAndSingleCharacterOverSSH() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app); runSequenceProbe("C011", review: false, app: app)
        await assertInput("070f64", app: app)
        XCTAssertEqual(app.staticTexts["controls-qa-sequence-result"].label, "Received Ctrl+G → Ctrl+O → d")
        capture("ctrl-g-ctrl-o-d-success", app: app)
    }

    func testTypedSequenceChordsAndMultipleCharactersAvoidPasteFormatting() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app); runSequenceProbe("C012", review: false, app: app)
        await assertInput("070f646f6e65", app: app)
        XCTAssertEqual(app.staticTexts["controls-qa-sequence-result"].label, "Received Ctrl+G → Ctrl+O → done")
        capture("ctrl-g-ctrl-o-multiple-typed-characters-success", app: app)
    }

    func testTimedSequenceCancelDuringWaitDoesNotSendSelection() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app); runSequenceProbe("C013", review: false, app: app)
        let cancel = app.buttons["shortcut-running-cancel"]
        capture("running-cancel-inspection", app: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        await fulfillment(of: [expectation(for: NSPredicate(format: "label CONTAINS %@", "Wait"), evaluatedWith: app.staticTexts["shortcut-running-step"])], timeout: 4)
        capture("wait-in-progress-with-cancel", app: app)
        cancel.tap()
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in !cancel.exists }, evaluatedWith: nil)], timeout: 5)
        await assertInput("740d", app: app)
        runSequenceProbe("C011", review: false, app: app)
        await assertInput("740d070f64", app: app)
        capture("wait-canceled-and-fresh-input-accepted", app: app)
    }

    func testTimedSequenceBackgroundRetiresWaitingSuffix() async throws {
        let (app, store) = try await launchPro(executionOverlay: true); defer { app.terminate(); store.clearTransactions() }
        startSequenceProbe(app)
        let keyboard = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        if keyboard.exists && keyboard.label == "Show Keyboard" { keyboard.tap(); try await waitForSoftwareKeyboard(app) }
        runSequenceProbe("C013", review: false, app: app)
        capture("running-background-inspection", app: app)
        await fulfillment(of: [expectation(for: NSPredicate(format: "label CONTAINS %@", "Wait"), evaluatedWith: app.staticTexts["shortcut-running-step"])], timeout: 4)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Input ready"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["shortcut-running-cancel"].exists)
        await assertInput("740d", app: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Background retirement must not restore execution-hidden keyboards")
        capture("background-cancels-wait-with-no-replay", app: app)
    }

    private func selectSequenceKind(_ kind: String, app: XCUIApplication) {
        app.buttons["shortcut-step-type"].tap()
        app.buttons[kind].firstMatch.tap()
    }
    private func addSequenceText(_ text: String, kind: String, app: XCUIApplication) {
        openSequenceStep(kind, app: app)
        let field = app.textViews["shortcut-step-text"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text)
        app.buttons["shortcut-step-save"].tap()
    }
    private func addSequenceReturn(_ app: XCUIApplication) {
        app.buttons["shortcut-add-step"].tap(); sequenceMenuChoice("Return", app: app).tap()
        XCTAssertFalse(app.buttons["shortcut-step-type"].exists, "Quick Return appends a key without opening another editor")
    }
    private func openSequenceStep(_ kind: String, app: XCUIApplication) {
        app.buttons["shortcut-add-step"].tap()
        sequenceMenuChoice(kind + "…", app: app).tap()
        XCTAssertTrue(app.buttons["shortcut-step-type"].waitForExistence(timeout: 5))
    }
    private func sequenceMenuChoice(_ label: String, app: XCUIApplication) -> XCUIElement {
        let choice = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3), app.debugDescription)
        return choice
    }
    private func startSequenceProbe(_ app: XCUIApplication) {
        app.buttons["controls-qa-live"].tap()
        XCTAssertTrue(app.staticTexts["controls-qa-input"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Input ready"].waitForExistence(timeout: 10))
    }
    private func runSequenceProbe(_ suffix: String, review: Bool, app: XCUIApplication) {
        let button = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000" + suffix]
        revealHorizontal(button, scroll: app.scrollViews["terminal-modifier-keys"]); button.tap()
        if review {
            XCTAssertTrue(app.buttons["shortcut-sequence-send"].waitForExistence(timeout: 5))
            if suffix == "C010" || suffix == "C013" { XCTAssertTrue(app.staticTexts["↵ Return"].firstMatch.exists) }
            capture("review-" + suffix, app: app); app.buttons["shortcut-sequence-send"].tap()
        }
    }

    func testRemoteCommandCanBeRemovedAndReaddedWithoutResettingTheLayout() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-remote"].tap()
        XCTAssertTrue(app.buttons["remote-qa-edit"].waitForExistence(timeout: 5))
        app.buttons["remote-qa-edit"].tap(); app.buttons["terminal-edit-keyboard"].tap()
        let command = app.buttons["terminal-preview-item-control-command"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        revealHorizontal(command, scroll: app.scrollViews["terminal-row-preview-scroll"]); command.tap()
        app.buttons["terminal-remove-placement"].tap()
        XCTAssertFalse(command.waitForExistence(timeout: 1))
        addToRow(mainID, app: app)
        let addCommand = app.buttons["terminal-add-control-command"]
        XCTAssertTrue(addCommand.waitForExistence(timeout: 5))
        capture("remote-command-available-in-key-picker", app: app)
        addCommand.tap()
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["remote-qa-events"].label, "Remote events: 0")
        app.buttons["remote-qa-edit"].tap(); app.buttons["terminal-edit-keyboard"].tap()
        XCTAssertTrue(command.waitForExistence(timeout: 5), "Command must survive saving and reopening the customized layout")
        revealHorizontal(command, scroll: app.scrollViews["terminal-row-preview-scroll"])
        capture("remote-command-readded-and-persisted", app: app)
        closeLayout(app, save: true); closeSettings(app)
        app.buttons["Close Remote Controls"].tap()
        openKeyboard(app); addToRow(mainID, app: app)
        XCTAssertTrue(app.buttons["terminal-add-control-ctrl"].waitForExistence(timeout: 5))
        XCTAssertFalse(addCommand.exists, "Terminal intentionally omits the remote Mac Command modifier")
        app.navigationBars["Add to Row"].buttons["Close"].tap()
        closeLayout(app, save: false); closeSettings(app)
    }

    func testRemoteFavoritesAndPointerSettingsUseTheSharedEditors() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-remote"].tap(); app.buttons["remote-qa-edit"].tap()
        XCTAssertTrue(app.buttons["terminal-edit-menu"].waitForExistence(timeout: 5))
        capture("remote-shared-customization-hub", app: app)
        app.buttons["remote-pointer-settings"].tap()
        XCTAssertTrue(app.navigationBars["Pointer & Gestures"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["trackpad-haptics-toggle"].exists)
        capture("remote-pointer-gestures-separated", app: app)
        app.navigationBars["Pointer & Gestures"].buttons.element(boundBy: 0).tap()
        app.buttons["terminal-edit-menu"].tap()
        XCTAssertTrue(app.buttons["terminal-control-add"].waitForExistence(timeout: 5))
        app.buttons["terminal-control-add"].tap()
        XCTAssertTrue(app.segmentedControls["terminal-add-page"].buttons["Actions"].exists)
        app.buttons["terminal-add-action-rightClick"].tap()
        XCTAssertTrue(app.buttons["Right Click"].firstMatch.waitForExistence(timeout: 5))
        capture("remote-favorite-added-directly", app: app)
        app.buttons["Right Click"].firstMatch.tap(); app.buttons["terminal-remove-placement"].tap()
        app.buttons["terminal-editor-undo"].tap()
        XCTAssertTrue(app.buttons["Right Click"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["terminal-full-menu-preview"].tap()
        XCTAssertTrue(app.navigationBars["Menu Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Display"].exists)
        XCTAssertFalse(app.staticTexts["Appearance"].exists)
        XCTAssertFalse(app.buttons["customize-quick-actions"].exists)
        capture("remote-full-menu-matches-live-navigation", app: app)
        app.navigationBars["Menu Preview"].buttons["Close"].tap()
        closeLayout(app, save: true); closeSettings(app)
        app.buttons["remote-qa-edit"].tap(); app.buttons["terminal-edit-menu"].tap()
        XCTAssertTrue(app.buttons["Right Click"].firstMatch.waitForExistence(timeout: 5))
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["remote-qa-events"].label, "Remote events: 0")
    }

    func testSharedRemoteControlsAndSequenceEditor() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-remote"].tap()
        XCTAssertTrue(app.buttons["remote-qa-edit"].waitForExistence(timeout: 5))
        capture("remote-shared-bar-keyboard-hidden", app: app)
        let bar = app.scrollViews["terminal-modifier-keys"]
        let ctrl = app.buttons["Ctrl"].firstMatch
        revealHorizontal(ctrl, scroll: bar); ctrl.tap(); XCTAssertEqual(ctrl.value as? String, "Next key")
        ctrl.press(forDuration: 0.7); XCTAssertEqual(ctrl.value as? String, "On")
        capture("remote-held-modifier-state", app: app)
        let keypad = app.buttons["Keypad"].firstMatch; revealHorizontal(keypad, scroll: bar); keypad.tap()
        XCTAssertTrue(app.buttons["remote-send-modifier-alone"].waitForExistence(timeout: 5))
        app.buttons["remote-send-modifier-alone"].tap(); app.buttons["Control Alone"].tap()
        capture("remote-explicit-modifier-alone", app: app)
        app.navigationBars["All Keys"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Remote events: 2"].waitForExistence(timeout: 5))
        revealHorizontal(ctrl, scroll: bar); XCTAssertEqual(ctrl.value as? String, "On"); ctrl.tap()
        app.buttons["remote-qa-edit"].tap()
        XCTAssertTrue(app.buttons["terminal-edit-keyboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["terminal-edit-menu"].exists)
        app.buttons["terminal-edit-keyboard"].tap()
        capture("remote-shared-keyboard-editor", app: app)
        addRowPreset("Numbers", app: app)
        capture("remote-numbers-row-added", app: app)
        togglePreview(app); try await waitForSoftwareKeyboard(app)
        capture("remote-native-keyboard-preview", app: app); togglePreview(app)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertTrue(app.staticTexts["Remote events: 2"].waitForExistence(timeout: 5), "Editing and preview never add input")
        capture("remote-customized-bar", app: app)
    }

    func testSequenceDraftAndPlacement() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        library(app)
        app.buttons["terminal-library-create"].tap()
        let name = app.textFields["terminal-control-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Two Steps\n")
        openSequenceStep("Press Key", app: app)
        try XCTUnwrap(app.buttons.matching(identifier: "terminal-choose-key").allElementsBoundByIndex.last).tap()
        let character = app.textFields["terminal-key-character"]; character.tap(); character.typeText("b")
        XCTAssertTrue(app.buttons["terminal-use-character"].isEnabled)
        app.buttons["terminal-use-character"].tap()
        app.buttons["terminal-shortcut-modifier-Ctrl"].tap()
        app.buttons["shortcut-step-save"].tap()
        openSequenceStep("Press Key", app: app)
        try XCTUnwrap(app.buttons.matching(identifier: "terminal-choose-key").allElementsBoundByIndex.last).tap()
        let next = app.textFields["terminal-key-character"]; next.tap(); next.typeText("c")
        app.buttons["terminal-use-character"].tap(); app.buttons["shortcut-step-save"].tap()
        capture("sequence-editor-two-steps", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch.label, "⌃b → c")
        let stepButtons = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "shortcut-step-[A-F0-9-]{36}"))
        let secondID = stepButtons.element(boundBy: 1).identifier
        stepButtons.element(boundBy: 1).tap()
        XCTAssertTrue(app.navigationBars["Edit Step"].waitForExistence(timeout: 5))
        try XCTUnwrap(app.buttons.matching(identifier: "terminal-choose-key").allElementsBoundByIndex.last).tap()
        let edited = app.textFields["terminal-key-character"]; edited.tap(); edited.typeText(XCUIKeyboardKey.delete.rawValue + "n")
        app.buttons["terminal-use-character"].tap(); app.buttons["shortcut-step-save"].tap()
        app.buttons["Options for n"].tap(); app.buttons["Duplicate"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch.label, "⌃b → n → n")
        app.buttons.matching(identifier: "Options for n").element(boundBy: 1).tap(); app.buttons["Remove"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch.label, "⌃b → n")
        let firstCell = app.cells.containing(.button, identifier: stepButtons.element(boundBy: 0).identifier).firstMatch
        let secondCell = app.cells.containing(.button, identifier: secondID).firstMatch
        secondCell.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.5)).press(forDuration: 0.7, thenDragTo: firstCell.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.1)))
        XCTAssertEqual(app.descendants(matching: .any)["shortcut-sequence-preview"].firstMatch.label, "n → ⌃b")
        capture("sequence-edit-duplicate-remove-reorder", app: app)
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Two Steps"].waitForExistence(timeout: 5))
        actions("Two Steps", app: app); app.buttons["Add to Keyboard Bar"].tap()
        app.buttons["terminal-row-menu-" + mainID].tap(); app.buttons["Add Key"].tap()
        capture("sequence-placed-on-keyboard", app: app)
        closeLayout(app, save: true)
    }

    func testSequenceReviewAndCancellation() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        app.buttons["controls-qa-live"].tap()
        let input = app.staticTexts["controls-qa-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        let action = app.buttons["terminal-row-action-00000000-0000-0000-0000-00000000C005"]
        revealHorizontal(action, scroll: app.scrollViews["terminal-modifier-keys"])
        let ctrl = app.buttons["Ctrl"].firstMatch
        revealHorizontal(ctrl, scroll: app.scrollViews["terminal-modifier-keys"]); ctrl.tap()
        revealHorizontal(action, scroll: app.scrollViews["terminal-modifier-keys"])
        action.tap(); XCTAssertTrue(app.buttons["shortcut-sequence-send"].waitForExistence(timeout: 5))
        capture("sequence-full-review-before-input", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(input.label, "Input: ")
        XCTAssertEqual(ctrl.value as? String, "Next key")
        action.tap(); XCTAssertTrue(app.buttons["shortcut-sequence-send"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["shortcut-sequence-send"].exists, "The retained review retires on background")
        XCTAssertEqual(input.label, "Input: ")
        XCTAssertTrue(app.staticTexts["Input ready"].waitForExistence(timeout: 10))
        revealHorizontal(action, scroll: app.scrollViews["terminal-modifier-keys"])
        action.tap(); XCTAssertTrue(app.buttons["shortcut-sequence-send"].waitForExistence(timeout: 5))
        app.buttons["shortcut-sequence-send"].tap()
        let sent = NSPredicate(format: "label == %@", "Input: 0273796e7468657469630d")
        await fulfillment(of: [expectation(for: sent, evaluatedWith: input)], timeout: 10)
        capture("sequence-explicit-send-completed", app: app)
    }
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
    private func setSwitch(_ control: XCUIElement, on: Bool, app: XCUIApplication) async {
        reveal(control, app: app)
        let expected = on ? "1" : "0"
        if control.value as? String != expected {
            // A SwiftUI switch's accessible frame includes its label. Hit the
            // trailing native switch instead of tapping the label's center.
            control.coordinate(withNormalizedOffset: .init(dx: 0.92, dy: 0.5)).tap()
            await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: control)], timeout: 3)
        }
        XCTAssertEqual(control.value as? String, expected)
    }
    private func revealHorizontal(_ element: XCUIElement, scroll: XCUIElement) {
        for _ in 0..<18 {
            if element.isHittable && element.frame.intersection(scroll.frame).width >= min(scroll.frame.width, element.frame.width) - 1 { return }
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
        if field.value as? String != name {
            capture("rename-awaiting-text-commit", app: app)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "rename-text-entry-state"; tree.lifetime = .keepAlways; add(tree)
            await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", name), evaluatedWith: field)], timeout: 3)
        }
        XCTAssertEqual(field.value as? String, name)
        try await waitForSoftwareKeyboard(app)
    }
    private func launchPro(failWriteOnce: Bool = false, remoteMode: String? = nil, failRead: Bool = false,
                           futureFormat: Bool = false, executionOverlay: Bool = false, dockRows: Int? = nil) async throws -> (XCUIApplication, SKTestSession) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launchEnvironment["MACCOMPANION_CONTROLS_FUNCTIONAL_TEST"] = "1"
        if let remoteMode { app.launchEnvironment["MACCOMPANION_CONTROLS_REMOTE_MODE"] = remoteMode }
        if failRead { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_READ"] = "1" }
        if futureFormat { app.launchEnvironment["MACCOMPANION_CONTROLS_FUTURE_FORMAT"] = "1" }
        if let dockRows { app.launchEnvironment["MACCOMPANION_DOCK_ROWS_QA"] = String(dockRows) }
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", (name.contains("Accessibility") ? UIContentSizeCategory.accessibilityExtraExtraExtraLarge : .large).rawValue]
        if name.contains("FourRowsDark") { app.launchEnvironment["MACCOMPANION_DOCK_DARK_QA"] = "1" }
        if name.contains("testInteractiveReview"), ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] == "1" { app.launchEnvironment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] = "1" }
        if name.contains("testCommand") { app.launchEnvironment["MACCOMPANION_COMMAND_QA"] = "1" }
        if executionOverlay || name.contains("ExecutionOverlay") { app.launchEnvironment["MACCOMPANION_EXECUTION_OVERLAY_QA"] = "1" }
        if name.contains("testTimedSequence") || name.contains("testTypedSequence") {
            app.launchEnvironment["MACCOMPANION_SEQUENCE_INPUT_QA"] = "1"
            app.launchEnvironment["MACCOMPANION_SEQUENCE_FOCUS"] = name.contains("ImmediateBlockedSSH") ? "C017" : name.contains("ExecutionOverlay") ? "C013" : name.contains("ConfirmationSkip") ? "C014" : name.contains("ProtocolReplies") ? "C016" : name.contains("CancelDuring") || name.contains("BackgroundRetires") || name.contains("BlockedSSH") ? "C013" : name.contains("MultipleCharacters") ? "C012" : name.contains("SingleCharacter") ? "C011" : "C010"
            if name.contains("ProtocolReplies") { app.launchEnvironment["MACCOMPANION_SEQUENCE_PROTOCOL_QA"] = "1" }
            if name.contains("BlockedSSH") { app.launchEnvironment["MACCOMPANION_SEQUENCE_BLOCKED_WRITE_QA"] = "1" }
        }
        if name.contains("testFailedSave") { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_WRITE"] = "1" }
        if failWriteOnce { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_WRITE_ONCE"] = "1" }
        if name.contains("testDirectLibraryRecovery") { app.launchEnvironment["MACCOMPANION_CONTROLS_FAIL_READ_ONCE"] = "1" }
        if name.contains("testOlderDevelopmentLayouts") { app.launchEnvironment["MACCOMPANION_CONTROLS_LEGACY_ROWS"] = "1" }
        if name.contains("testNewerFormat") { app.launchEnvironment["MACCOMPANION_CONTROLS_FUTURE_FORMAT"] = "1" }
        if name.contains("testRightEdgeRowRotation") { app.launchEnvironment["MACCOMPANION_CONTROLS_ROTATION"] = "1" }
        if name.contains("testRepeatedUtilityControls") { app.launchEnvironment["MACCOMPANION_CONTROLS_REPEATED_UTILITIES"] = "1" }
        app.terminate() // Interrupted runs must not reuse a process with older fixture flags.
        // Seed the entitlement before launch so the first controls adapter does
        // not render the free layout while StoreKit is replacing old receipts.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        _ = try await store.buyProduct(identifier: "media.jenny.maccompanion.pro.lifetime")
        app.terminate() // StoreKit may launch the app without the explicit fixture environment.
        app.launch()
        XCTAssertTrue(app.staticTexts["controls-qa-pro"].waitForExistence(timeout: 10))
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
        openSequenceStep("Press Key", app: app)
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
        app.buttons["shortcut-step-save"].tap()
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Couldn’t save.")).firstMatch.exists)
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
        openSequenceStep("Press Key", app: app)
        app.buttons["terminal-shortcut-modifier-Ctrl"].tap(); app.buttons["terminal-choose-key"].tap()
        let character = app.textFields["terminal-key-character"]; character.tap(); character.typeText(XCUIKeyboardKey.delete.rawValue + "b")
        app.buttons["terminal-use-character"].tap(); app.buttons["shortcut-step-save"].tap(); app.buttons["terminal-item-save"].tap()
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

    func testRepeatedUtilityControlsWorkInALiveSessionWithoutSendingInput() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        live(app)
        let row = app.scrollViews["terminal-modifier-keys"]
        let expand = row.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Expand Rows", "Collapse Rows")).firstMatch
        revealHorizontal(expand, scroll: row)
        if expand.label == "Expand Rows" { expand.tap() }
        XCTAssertEqual(expand.label, "Collapse Rows")
        let keyboards = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard"))
        XCTAssertEqual(keyboards.count, 2)
        capture("repeated-utilities-expanded-in-live-terminal", app: app)
        let keyboard = row.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show Keyboard", "Hide Keyboard")).firstMatch
        revealHorizontal(keyboard, scroll: row); keyboard.tap()
        try await waitForSoftwareKeyboard(app)
        capture("repeated-keyboard-control-opens-native-keyboard", app: app)
        keyboard.tap()
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, evaluatedWith: nil)], timeout: 5)
        revealHorizontal(expand, scroll: row); expand.tap()
        XCTAssertEqual(expand.label, "Expand Rows")
        await assertInput("", app: app)
        capture("repeated-expand-control-collapses-without-input", app: app)
    }

    func testOlderDevelopmentLayoutsResetOnceAndKeepSavedItems() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        XCTAssertFalse(app.buttons["terminal-preview-item-control-keypad"].exists)
        XCTAssertTrue(app.scrollViews["terminal-row-preview-scroll"].buttons["Left"].exists)
        XCTAssertFalse(app.buttons["terminal-row-preview-" + itemID].exists)
        capture("older-layout-reset-to-current-defaults", app: app)
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-count"].label, "Saved items: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: off; Menu: on")
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        library(app, text: true)
        XCTAssertTrue(app.staticTexts["Project"].exists)
        capture("saved-text-kept-after-layout-reset", app: app)
        closeSettings(app)
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        XCTAssertTrue(app.buttons["Project"].exists)
        capture("menu-favorite-kept-after-layout-reset", app: app)
        closeLayout(app, save: false); closeSettings(app)
        openKeyboard(app)
        let menu = app.buttons["terminal-row-menu-" + mainID]
        menu.tap(); app.buttons["Alignment"].tap(); app.collectionViews.buttons["Right"].tap()
        closeLayout(app, save: true); closeSettings(app)
        openKeyboard(app); menu.tap(); app.buttons["Alignment"].tap()
        XCTAssertTrue(app.collectionViews.buttons["Right"].isSelected)
        capture("current-layout-options-survive-reopen", app: app)
    }
    func testNewerFormatShowsUpdateMessageWithoutOverwritingSavedData() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openSettings(app)
        XCTAssertTrue(app.navigationBars["Terminal Controls"].exists)
        XCTAssertFalse(app.buttons["remote-pointer-settings"].exists)
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "newer version of Mac Companion")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        capture("newer-format-update-required-data-kept", app: app)
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        openSettings(app); XCTAssertTrue(notice.waitForExistence(timeout: 5))
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
    }

    func testRemoteControlsRecoveryKeepsPointerSettingsWithUnreadableData() async throws {
        for mode in ["desktop", "trackpad"] {
            let (app, store) = try await launchPro(remoteMode: mode, failRead: true)
            defer { app.terminate(); store.clearTransactions() }
            assertRemoteRecovery(app, mode: mode, failure: "unreadable")
        }
    }

    func testRemoteControlsRecoveryKeepsPointerSettingsWithNewerFormat() async throws {
        for mode in ["desktop", "trackpad"] {
            let (app, store) = try await launchPro(remoteMode: mode, futureFormat: true)
            defer { app.terminate(); store.clearTransactions() }
            assertRemoteRecovery(app, mode: mode, failure: "newer-format")
        }
    }

    private func assertRemoteRecovery(_ app: XCUIApplication, mode: String, failure: String) {
        openSettings(app)
        XCTAssertTrue(app.buttons["Reload Saved Controls"].waitForExistence(timeout: 5))
        capture("remote-" + mode + "-" + failure + "-recovery", app: app)
        XCTAssertTrue(app.navigationBars["Remote Mac Controls"].exists)
        XCTAssertFalse(app.navigationBars["Terminal Controls"].exists)
        let pointer = app.buttons["remote-pointer-settings"]
        XCTAssertTrue(pointer.waitForExistence(timeout: 5))
        reveal(pointer, app: app); pointer.tap()
        XCTAssertTrue(app.navigationBars["Pointer & Gestures"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Pointer Speed"].exists)
        XCTAssertTrue(app.sliders["scroll-speed-slider"].exists)
        XCTAssertTrue(app.switches["trackpad-haptics-toggle"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["remote-interaction-mode"].exists, mode == "desktop")
        capture("remote-" + mode + "-" + failure + "-pointer-settings", app: app)
        app.navigationBars["Pointer & Gestures"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Remote Mac Controls"].waitForExistence(timeout: 5))
        closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
    }

    func testRightEdgeRowRotationKeepsLastKeysAndRespectsManualScroll() async throws {
        let (app, store) = try await launchPro()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        let first = app.buttons["terminal-preview-item-palette-key-f1"]
        let last = app.buttons["terminal-preview-item-palette-key-f12"]
        let row = app.scrollViews["terminal-row-preview-scroll"]
        func visible(_ key: XCUIElement) -> Bool { key.isHittable && key.frame.intersection(row.frame).width >= min(40, key.frame.width) }
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in visible(last) && !visible(first) }, evaluatedWith: nil)], timeout: 5)
        capture("right-edge-before-rotation", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in visible(first) && visible(last) }, evaluatedWith: nil)], timeout: 5)
        capture("right-edge-row-fits-in-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in visible(last) && !visible(first) }, evaluatedWith: nil)], timeout: 5)
        capture("right-edge-retained-after-return-to-portrait", app: app)
        revealHorizontal(first, scroll: row)
        XCTAssertTrue(visible(first))
        XCUIDevice.shared.orientation = .landscapeLeft
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in visible(first) && visible(last) }, evaluatedWith: nil)], timeout: 5)
        XCUIDevice.shared.orientation = .portrait
        await fulfillment(of: [expectation(for: NSPredicate { _, _ in visible(first) && !visible(last) }, evaluatedWith: nil)], timeout: 5)
        capture("manual-left-scroll-retained-after-rotation", app: app)
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

    func testReplaceKeyboardButtonWithSavedTextPresetAndInlineShortcut() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openKeyboard(app)
        let row = app.scrollViews["terminal-row-preview-scroll"]
        let tab = app.buttons["terminal-preview-item-palette-key-tab"]
        revealHorizontal(tab, scroll: row); tab.tap(); app.buttons["terminal-replace-key"].tap()
        let pages = app.segmentedControls["terminal-add-page"]
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.buttons["Text"].tap()
        capture("replace-keyboard-button-text-catalog", app: app)
        app.buttons["terminal-reuse-" + itemID].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        let projects = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-preview-", "Project"))
        XCTAssertEqual(projects.count, 2)
        let selected = projects.element(boundBy: 0)
        revealHorizontal(selected, scroll: row); selected.tap(); app.buttons["terminal-replace-key"].tap()
        pages.buttons["Shortcuts"].tap(); app.buttons["terminal-tool-presets-tmux"].tap()
        let prefix = app.buttons["terminal-preset-tmux.prefix"], window = app.buttons["terminal-preset-tmux.window.complete"]
        XCTAssertTrue(prefix.waitForExistence(timeout: 5)); prefix.tap(); window.tap()
        XCTAssertEqual(prefix.value as? String, "Not selected")
        XCTAssertEqual(window.value as? String, "Selected")
        XCTAssertEqual(app.buttons["terminal-presets-add"].label, "Replace")
        capture("replace-one-button-single-tool-preset", app: app)
        app.buttons["terminal-presets-add"].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        XCTAssertEqual(projects.count, 1)
        let tmux = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "terminal-row-preview-", "Tmux New Window")).firstMatch
        revealHorizontal(tmux, scroll: row); tmux.tap()
        XCTAssertTrue(app.buttons["terminal-edit-selected"].exists, "Shared definition editing remains separate")
        app.buttons["terminal-replace-key"].tap(); pages.buttons["Shortcuts"].tap()
        app.buttons["terminal-create-inline"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
        app.textFields["terminal-control-name"].tap(); app.textFields["terminal-control-name"].typeText("My Prefix")
        openSequenceStep("Press Key", app: app)
        app.buttons["terminal-shortcut-modifier-Ctrl"].tap(); app.buttons["terminal-choose-key"].tap()
        let character = app.textFields["terminal-key-character"]; character.tap(); character.typeText(XCUIKeyboardKey.delete.rawValue + "b")
        app.buttons["terminal-use-character"].tap(); app.buttons["shortcut-step-save"].tap(); app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.buttons["terminal-add-row"].waitForExistence(timeout: 5))
        let replacement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "terminal-row-preview-", "My Prefix")).firstMatch
        revealHorizontal(replacement, scroll: row)
        XCTAssertFalse(tmux.exists); XCTAssertEqual(projects.count, 1)
        capture("replacement-inline-shortcut-keeps-other-placement", app: app)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        openKeyboard(app)
        XCTAssertTrue(replacement.waitForExistence(timeout: 5)); XCTAssertEqual(projects.count, 1)
        capture("keyboard-replacements-persist-after-save", app: app)
    }

    func testReplaceFavoriteAcrossActionsTextAndKeysWithoutAddingPlacements() async throws {
        let (app, store) = try await launchPro(); defer { app.terminate(); store.clearTransactions() }
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        let project = app.buttons["Project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5)); project.tap()
        app.buttons["terminal-replace-key"].tap()
        let pages = app.segmentedControls["terminal-add-page"]
        XCTAssertTrue(pages.waitForExistence(timeout: 5)); pages.buttons["Actions"].tap()
        capture("replace-favorite-app-actions", app: app)
        app.buttons["terminal-add-action-composeText"].tap()
        let compose = app.buttons["Compose Text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5)); XCTAssertFalse(project.exists)
        compose.tap(); app.buttons["terminal-replace-key"].tap(); pages.buttons["Text"].tap()
        app.buttons["terminal-create-inline"].tap()
        XCTAssertTrue(app.textFields["terminal-control-name"].waitForExistence(timeout: 5))
        app.textFields["terminal-control-name"].tap(); app.textFields["terminal-control-name"].typeText("Status")
        let text = app.textViews.firstMatch; text.tap(); text.typeText("git status --short")
        app.buttons["terminal-item-save"].tap()
        XCTAssertTrue(app.buttons["Status"].waitForExistence(timeout: 5)); XCTAssertFalse(compose.exists)
        capture("replace-favorite-inline-saved-text", app: app)
        app.buttons["Status"].tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("Home", app: app); app.buttons["terminal-add-key-home"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["Status"].exists)
        capture("replace-saved-text-with-key", app: app)
        app.buttons["terminal-editor-undo"].tap()
        XCTAssertTrue(app.buttons["Status"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["Home"].exists)
        closeLayout(app, save: true); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-menu-order"].label, "Favorites: Status")
        openSettings(app); app.buttons["terminal-edit-menu"].tap()
        XCTAssertTrue(app.buttons["Status"].waitForExistence(timeout: 5))
        app.buttons["Status"].tap(); app.buttons["terminal-replace-key"].tap()
        searchCatalog("Home", app: app); app.buttons["terminal-add-key-home"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        closeLayout(app, save: false); closeSettings(app)
        XCTAssertEqual(app.staticTexts["controls-qa-menu-order"].label, "Favorites: Status")
        library(app, text: true)
        XCTAssertTrue(app.staticTexts["Project"].exists, "Replacement keeps the original shared definition")
        XCTAssertTrue(app.staticTexts["Status"].exists)
        capture("replacement-saved-definitions-retained", app: app)
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
