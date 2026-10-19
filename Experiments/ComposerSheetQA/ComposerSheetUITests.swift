import XCTest
@MainActor final class ComposerSheetUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func open(narrow: Bool = false, shortcutBar: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
        app.launchArguments = (narrow ? ["--qa-narrow-composer"] : []) + (shortcutBar ? ["--qa-shortcut-bar"] : []); app.launch()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); return app
    }
    private func waitForKeyboardAndPanel(_ app: XCUIApplication) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let keyboard = app.keyboards.firstMatch, panel = app.otherElements["compose-panel"].firstMatch
        var previous: [CGRect]?
        var stableSince: ContinuousClock.Instant?
        repeat {
            let frames = [keyboard.frame, panel.frame]
            let docked = keyboard.exists && frames[0].height > 100 && frames[0].intersects(app.frame)
                && frames[0].maxY <= app.frame.maxY + 2 && frames[1].height > 35
                && frames[1].maxY <= frames[0].minY + 2
            if docked, previous == frames {
                if let stableSince, stableSince.duration(to: .now) >= .milliseconds(400) { return }
                if stableSince == nil { stableSince = .now }
            } else { stableSince = nil }
            previous = docked ? frames : nil
            try? await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        XCTFail("Composer and visible docked keyboard did not reach a stable layout")
    }
    private func grabber(_ app: XCUIApplication) -> XCUICoordinate {
        let button = app.buttons["compose-grabber"]
        return button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = name; proof.lifetime = .keepAlways; add(proof)
    }
    func testExpandAndCollapsePreserveTypingAndReturnToTheFloatingPosition() async {
        let app = open(shortcutBar: true); defer { app.terminate() }
        let editor = app.textViews["compose-text"], panel = app.otherElements["compose-panel"].firstMatch
        let expand = app.buttons["compose-expand"]
        editor.typeText("A draft to keep")
        await waitForKeyboardAndPanel(app)
        let grip = grabber(app)
        grip.press(forDuration: 0.15, thenDragTo: grip.withOffset(CGVector(dx: -25, dy: -40)))
        await waitForKeyboardAndPanel(app)
        let floating = panel.frame
        XCTAssertTrue(expand.isHittable); XCTAssertEqual(expand.value as? String, "Collapsed")
        XCTAssertFalse(editor.frame.intersects(expand.frame)); XCTAssertGreaterThanOrEqual(expand.frame.width, 44)
        capture("composer-dark-floating", app: app)
        expand.tap(); await waitForKeyboardAndPanel(app)
        XCTAssertEqual(expand.value as? String, "Expanded")
        XCTAssertGreaterThan(panel.frame.height, floating.height + 40)
        XCTAssertGreaterThanOrEqual(panel.frame.width, floating.width)
        XCTAssertFalse(panel.frame.intersects(app.otherElements["qa-shortcut-bar"].frame))
        // Use a real software key, without refocusing the editor, to verify
        // both retained focus and a usable keyboard after the resize.
        XCTAssertTrue(app.keys["space"].isHittable); app.keys["space"].tap()
        XCTAssertEqual(editor.value as? String, "A draft to keep ")
        capture("composer-dark-expanded", app: app)
        expand.tap(); await waitForKeyboardAndPanel(app)
        XCTAssertEqual(expand.value as? String, "Collapsed")
        // The unsent draft grows as it is edited, but its saved anchor stays put.
        XCTAssertEqual(panel.frame.minX, floating.minX, accuracy: 2)
        XCTAssertLessThan(panel.frame.height, 200)
        XCTAssertTrue(app.keys["delete"].isHittable); app.keys["delete"].tap()
        XCTAssertEqual(editor.value as? String, "A draft to keep")
        XCTAssertTrue(app.buttons["compose-send"].isHittable); XCTAssertTrue(app.buttons["compose-back"].isHittable)
        capture("composer-dark-collapsed", app: app)
    }
    func testTerminalPaletteAndKeyboardRemainUsableAcrossExpansion() async {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
            app.launchArguments = ["--qa-terminal", "--qa-shortcut-bar"] + (dark ? ["--qa-terminal-dark"] : ["--qa-dark"])
            app.launch()
            XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
            let editor = app.textViews["compose-text"], expand = app.buttons["compose-expand"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("terminal draft")
            await waitForKeyboardAndPanel(app)
            capture("composer-terminal-" + (dark ? "dark" : "light"), app: app)
            expand.tap(); await waitForKeyboardAndPanel(app)
            XCTAssertTrue(app.keys["x"].isHittable); app.keys["x"].tap()
            XCTAssertEqual(editor.value as? String, "terminal draftx")
            capture("composer-terminal-expanded-" + (dark ? "dark" : "light"), app: app)
            XCTAssertTrue(app.buttons["compose-back"].isHittable)
            app.terminate()
        }
    }

    func testBubbleSitsAboveShortcutBarAndStillDragsTypesAndSends() async {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
        app.launchArguments = ["--qa-shortcut-bar", "--qa-delivery-result"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
        let editor = app.textViews["compose-text"], panel = app.otherElements["compose-panel"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("retained draft")
        await waitForKeyboardAndPanel(app)
        let bar = app.otherElements["qa-shortcut-bar"]
        XCTAssertTrue(bar.exists); XCTAssertEqual(panel.frame.maxY, bar.frame.minY - 8, accuracy: 2)
        XCTAssertFalse(panel.frame.intersects(bar.frame))
        let start = grabber(app); start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: -40, dy: -90)))
        XCTAssertLessThan(panel.frame.maxY, bar.frame.minY - 30)
        editor.typeText(" typed"); XCTAssertEqual(editor.value as? String, "retained draft typed")
        app.buttons["compose-back"].tap(); app.buttons["qa-compose"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertEqual(editor.value as? String, "retained draft typed")
        app.buttons["compose-send"].tap()
        XCTAssertTrue(app.buttons["compose-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "retained draft typed")
        app.buttons["compose-error"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic delivery failure"].waitForExistence(timeout: 5))
        app.buttons["compose-error-done"].tap(); app.buttons["compose-send"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["qa-compose"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed); XCTAssertFalse(editor.exists)
    }

    func testInlineFooterGrowsMultilineWithoutTextControlOverlapAndRetainsDraft() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"], panel = app.otherElements["compose-panel"].firstMatch
        editor.typeText("one"); await waitForKeyboardAndPanel(app)
        let shortHeight = panel.frame.height
        app.typeText("\ntwo\nthree\nfour\nfive")
        await waitForKeyboardAndPanel(app)
        XCTAssertGreaterThan(panel.frame.height, shortHeight)
        let close = app.buttons["compose-back"], grip = app.buttons["compose-grabber"], send = app.buttons["compose-send"]
        XCTAssertEqual(close.frame.midY, send.frame.midY, accuracy: 2)
        XCTAssertEqual(grip.frame.midY, send.frame.midY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(editor.frame.width, panel.frame.width - 68)
        for control in [close, grip, send, app.buttons["compose-expand"]] {
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44); XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertFalse(editor.frame.intersects(control.frame))
        }
        send.tap(); XCTAssertTrue(app.alerts["Send line breaks or tabs?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(editor.value as? String, "one\ntwo\nthree\nfour\nfive")
        close.tap(); app.buttons["qa-compose"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertEqual(editor.value as? String, "one\ntwo\nthree\nfour\nfive")
    }

    func testTextBubbleDragSnapAndGrabberTapKeepKeyboardAndDraftMounted() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("alpha")
        await waitForKeyboardAndPanel(app)
        let panel = app.otherElements["compose-panel"].firstMatch, start = panel.frame
        XCTAssertLessThan(start.height, 200); XCTAssertLessThanOrEqual(start.width, 284)
        for id in ["compose-dock", "compose-more", "compose-discard", "compose-destination"] { XCTAssertFalse(app.descendants(matching: .any)[id].exists) }
        grabber(app).press(forDuration: 0.15, thenDragTo: grabber(app).withOffset(CGVector(dx: -200, dy: -140)))
        let moved = panel.frame
        XCTAssertLessThan(moved.minY, start.minY - 20); XCTAssertEqual(moved.minX, app.frame.minX + 8, accuracy: 2)
        app.buttons["compose-grabber"].tap(); XCTAssertEqual(panel.frame, moved)
        XCTAssertTrue(app.keyboards.firstMatch.exists); app.typeText(" beta")
        XCTAssertEqual(editor.value as? String, "alpha beta")
        let close = app.buttons["compose-back"], send = app.buttons["compose-send"]
        XCTAssertTrue(close.isHittable); XCTAssertTrue(send.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44); XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44); XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        XCTAssertFalse(close.frame.intersects(send.frame)); XCTAssertFalse(editor.frame.intersects(send.frame))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "synthetic-text-bubble"; capture.lifetime = .keepAlways; add(capture)
    }
    func testRegularGlassBubbleOverBusyDesktopKeepsTypingAndCloseUsable() async {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
            app.launchArguments = ["--qa-glass-background"] + (dark ? ["--qa-dark"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
            let editor = app.textViews["compose-text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            editor.typeText("glass draft"); await waitForKeyboardAndPanel(app)
            let close = app.buttons["compose-back"], send = app.buttons["compose-send"]
            XCTAssertTrue(close.isHittable); XCTAssertTrue(send.isHittable)
            XCTAssertGreaterThanOrEqual(close.frame.width, 44); XCTAssertGreaterThanOrEqual(send.frame.width, 44)
            XCTAssertFalse(editor.frame.intersects(send.frame))
            let start = grabber(app)
            start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: -100, dy: -90)))
            app.typeText(" retained"); XCTAssertEqual(editor.value as? String, "glass draft retained")
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "synthetic-glass-busy-" + (dark ? "dark" : "light")
            capture.lifetime = .keepAlways; add(capture)
            close.tap(); XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertEqual(editor.value as? String, "glass draft retained")
            app.terminate()
        }
    }
    func testSmallFloatingDragAndCloseReopenRetainedDraft() {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("retained")
        let start = grabber(app)
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 12)))
        XCTAssertTrue(editor.exists); XCTAssertEqual(editor.value as? String, "retained")
        app.buttons["compose-back"].tap()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "retained")
    }
    func testEditorScrollingDoesNotMoveAndSendingBlocksCloseAndDrag() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText(String(repeating: "row\n", count: 36))
        await waitForKeyboardAndPanel(app)
        let panel = app.otherElements["compose-panel"].firstMatch, before = panel.frame
        editor.swipeDown(); XCTAssertEqual(panel.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["compose-send"].tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Send Text"].tap()
        XCTAssertFalse(app.buttons["compose-back"].isEnabled); XCTAssertFalse(app.buttons["compose-grabber"].isEnabled)
        let sendingFrame = panel.frame
        grabber(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(editor.exists); XCTAssertEqual(panel.frame.minY, sendingFrame.minY, accuracy: 2)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "")
    }
    func testNarrowInvalidBubbleKeepsCloseErrorAndSendReachable() {
        let app = open(narrow: true); defer { app.terminate() }
        let panel = app.otherElements["compose-panel"].firstMatch, send = app.buttons["compose-send"]
        XCTAssertTrue(app.buttons["compose-back"].isHittable); XCTAssertTrue(app.buttons["compose-error"].isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.minX, panel.frame.minX); XCTAssertLessThanOrEqual(send.frame.maxX, panel.frame.maxX)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44); XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        XCTAssertFalse(send.isEnabled); XCTAssertFalse(app.buttons["compose-more"].exists)
        let draft = app.textViews["compose-text"].value as? String
        app.buttons["compose-error"].tap()
        XCTAssertTrue(app.staticTexts["Screen Sharing input can send up to 256 Unicode characters at once."].waitForExistence(timeout: 5))
        app.buttons["compose-error-done"].tap()
        XCTAssertEqual(app.textViews["compose-text"].value as? String, draft)
        app.buttons["compose-back"].tap(); XCTAssertTrue(app.buttons["qa-compose"].isHittable)
    }
    func testDeliveryErrorCanBeReviewedRetriedAndSuccessClearsDraft() {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
        app.launchArguments = ["--qa-delivery-result"]; app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
        let editor = app.textViews["compose-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("retry draft")
        app.buttons["compose-send"].tap()
        XCTAssertTrue(app.buttons["compose-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "retry draft")
        XCTAssertTrue(app.buttons["compose-send"].isEnabled); XCTAssertTrue(app.buttons["compose-back"].isEnabled)
        app.buttons["compose-error"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic delivery failure"].waitForExistence(timeout: 5))
        app.buttons["compose-error-done"].tap(); app.buttons["compose-send"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["qa-compose"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["qa-compose"].tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, ""); XCTAssertFalse(app.buttons["compose-error"].exists)
    }
    func testFloatingRotationKeepsEditorCloseAndSendAboveKeyboard() async {
        let app = open(shortcutBar: true); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("rotation draft")
        XCUIDevice.shared.orientation = .landscapeLeft
        await waitForKeyboardAndPanel(app)
        let keyboard = app.keyboards.firstMatch, panel = app.otherElements["compose-panel"].firstMatch
        XCTAssertGreaterThanOrEqual(panel.frame.minY, app.frame.minY + 8)
        XCTAssertLessThanOrEqual(panel.frame.maxY, keyboard.frame.minY + 2)
        XCTAssertFalse(panel.frame.intersects(app.otherElements["qa-shortcut-bar"].frame))
        XCTAssertGreaterThan(editor.frame.height, 35)
        XCTAssertTrue(app.buttons["compose-send"].isHittable); XCTAssertTrue(app.buttons["compose-back"].isHittable)
        XCTAssertFalse(editor.frame.intersects(app.buttons["compose-send"].frame))
        app.typeText(" retained"); XCTAssertEqual(editor.value as? String, "rotation draft retained")
        XCUIDevice.shared.orientation = .portrait
        await waitForKeyboardAndPanel(app); XCTAssertTrue(app.buttons["compose-send"].isHittable)
        XCTAssertFalse(panel.frame.intersects(app.otherElements["qa-shortcut-bar"].frame))
    }
}
