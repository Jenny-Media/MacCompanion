import XCTest
@MainActor final class ComposerSheetUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func open(narrow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios")
        app.launchArguments = narrow ? ["--qa-narrow-composer"] : []; app.launch()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); return app
    }
    private func waitForDockedKeyboardAndPanel(_ app: XCUIApplication) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let keyboard = app.keyboards.firstMatch, panel = app.otherElements["compose-panel"].firstMatch
        var previous: [CGRect]?
        repeat {
            let frames = [keyboard.frame, panel.frame]
            let docked = keyboard.exists && frames[0].height > 100 && frames[0].intersects(app.frame)
                && frames[0].maxY <= app.frame.maxY + 2 && frames[1].height > 100
                && frames[1].maxY <= frames[0].minY + 2
            if docked, previous == frames { return }
            previous = docked ? frames : nil
            try? await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        XCTFail("Composer and visible docked keyboard did not reach a stable layout")
    }
    private func grabber(_ app: XCUIApplication) -> XCUICoordinate {
        let button = app.buttons["compose-grabber"]
        return button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }
    func testFloatingDragSnapsAndDockExpandKeepKeyboardAndDraftMounted() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("alpha")
        await waitForDockedKeyboardAndPanel(app)
        let panel = app.otherElements["compose-panel"].firstMatch, start = panel.frame
        XCTAssertEqual(app.buttons["compose-dock"].label, "Dock")
        grabber(app).press(forDuration: 0.15, thenDragTo: grabber(app).withOffset(CGVector(dx: -200, dy: -140)))
        let moved = panel.frame
        XCTAssertLessThan(moved.minY, start.minY - 20); XCTAssertEqual(moved.minX, app.frame.minX + 8, accuracy: 2)
        XCTAssertTrue(app.keyboards.firstMatch.exists); app.typeText(" beta")
        XCTAssertEqual(editor.value as? String, "alpha beta")
        app.buttons["compose-dock"].tap(); XCTAssertEqual(app.buttons["compose-dock"].label, "Undock")
        await waitForDockedKeyboardAndPanel(app)
        let docked = panel.frame
        app.buttons["compose-expand"].tap(); XCTAssertLessThan(panel.frame.minY, docked.minY - 20)
        app.buttons["compose-dock"].tap(); XCTAssertEqual(app.buttons["compose-dock"].label, "Dock")
        XCTAssertEqual(panel.frame.minX, moved.minX, accuracy: 2); XCTAssertEqual(panel.frame.minY, moved.minY, accuracy: 2)
        app.typeText(" gamma"); XCTAssertEqual(editor.value as? String, "alpha beta gamma")
        XCTAssertTrue(app.buttons["compose-send"].isHittable)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "synthetic-floating-composer"; image.lifetime = .keepAlways; add(image)
    }
    func testSmallFloatingDragAndDockedDismissalReopenRetainedDraft() {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("retained")
        let start = grabber(app)
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 12)))
        XCTAssertTrue(editor.exists); XCTAssertEqual(editor.value as? String, "retained")
        app.buttons["compose-dock"].tap()
        grabber(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "retained")
    }
    func testEditorScrollingDoesNotMoveAndSendingBlocksPresentationChanges() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText(String(repeating: "row\n", count: 36))
        await waitForDockedKeyboardAndPanel(app)
        let panel = app.otherElements["compose-panel"].firstMatch, before = panel.frame
        editor.swipeDown(); XCTAssertEqual(panel.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["compose-send"].tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Send Text"].tap()
        XCTAssertFalse(app.buttons["compose-dock"].isEnabled); XCTAssertFalse(app.buttons["compose-expand"].isEnabled)
        let sendingFrame = panel.frame // Disabling the editor can dismiss the keyboard.
        grabber(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(editor.exists); XCTAssertEqual(panel.frame.minY, sendingFrame.minY, accuracy: 2)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "")
        XCTAssertEqual(app.buttons["compose-dock"].label, "Dock")
    }
    func testNarrowCompactWindowKeepsErrorSendAndMenuActionsReachable() {
        let app = open(narrow: true); defer { app.terminate() }
        let panel = app.otherElements["compose-panel"].firstMatch, send = app.buttons["compose-send"]
        XCTAssertTrue(app.buttons["compose-back"].isHittable)
        XCTAssertTrue(app.buttons["compose-error"].isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.minX, panel.frame.minX)
        XCTAssertLessThanOrEqual(send.frame.maxX, panel.frame.maxX)
        XCTAssertFalse(send.isEnabled)
        let draft = app.textViews["compose-text"].value as? String
        app.buttons["compose-more"].tap(); app.buttons["compose-expand"].tap()
        app.buttons["compose-more"].tap(); app.buttons["compose-dock"].tap()
        app.buttons["compose-more"].tap(); app.buttons["compose-dock"].tap()
        XCTAssertEqual(app.textViews["compose-text"].value as? String, draft)
        XCTAssertTrue(app.buttons["compose-more"].isHittable); XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["compose-back"].tap()
        XCTAssertTrue(app.buttons["qa-compose"].isHittable)
    }
    func testFloatingRotationKeepsSendEditorAndPresentationControlsAboveKeyboard() async {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("rotation draft")
        XCUIDevice.shared.orientation = .landscapeLeft
        await waitForDockedKeyboardAndPanel(app)
        let keyboard = app.keyboards.firstMatch, panel = app.otherElements["compose-panel"].firstMatch
        XCTAssertGreaterThanOrEqual(panel.frame.minY, app.frame.minY + 8)
        XCTAssertLessThanOrEqual(panel.frame.maxY, keyboard.frame.minY + 2)
        XCTAssertGreaterThan(editor.frame.height, 35)
        XCTAssertTrue(app.buttons["compose-send"].isHittable); XCTAssertTrue(app.buttons["compose-dock"].isHittable)
        app.buttons["compose-dock"].tap(); app.buttons["compose-dock"].tap()
        app.typeText(" retained"); XCTAssertEqual(editor.value as? String, "rotation draft retained")
        XCUIDevice.shared.orientation = .portrait
        await waitForDockedKeyboardAndPanel(app)
        XCTAssertTrue(app.buttons["compose-send"].isHittable)
    }
}
