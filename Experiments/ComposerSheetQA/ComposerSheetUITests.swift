import XCTest
@MainActor final class ComposerSheetUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func open() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.sheetqa.ios"); app.launch()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 10)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); return app
    }
    private func grabber(_ app: XCUIApplication) -> XCUICoordinate {
        let button = app.buttons["compose-grabber"]
        return button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }
    func testNativeGrabberResizesWhileKeyboardAndDraftStayMounted() {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("alpha")
        let panel = app.otherElements["compose-panel"].firstMatch
        let compact = panel.frame
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "synthetic-compact-keyboard"; before.lifetime = .keepAlways; add(before)
        XCTAssertGreaterThan(compact.minY, app.frame.minY + 40)
        grabber(app).press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: 80)))
        let expanded = panel.frame
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "synthetic-expanded-keyboard"; after.lifetime = .keepAlways; add(after)
        XCTAssertLessThan(expanded.minY, compact.minY - 30)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" beta"); XCTAssertEqual(editor.value as? String, "alpha beta")
        grabber(app).press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: compact.minY - 22)))
        XCTAssertGreaterThan(panel.frame.minY, expanded.minY + 30)
        XCTAssertTrue(app.keyboards.firstMatch.exists); app.typeText(" gamma")
        XCTAssertEqual(editor.value as? String, "alpha beta gamma")
        XCTAssertTrue(app.buttons["compose-send"].isHittable)
    }
    func testCanceledDragRetainsDraftAndCompletedDismissalReopensDraft() {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]; editor.typeText("retained")
        let start = grabber(app)
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 12)))
        XCTAssertTrue(editor.exists); XCTAssertEqual(editor.value as? String, "retained")
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5))
        app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "retained")
    }
    func testEditorScrollingDoesNotResizeAndSendingBlocksSwipeDismissal() {
        let app = open(); defer { app.terminate() }
        let editor = app.textViews["compose-text"]
        editor.typeText(String(repeating: "row\n", count: 36))
        let panel = app.otherElements["compose-panel"].firstMatch, before = panel.frame
        editor.swipeDown()
        XCTAssertEqual(panel.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["compose-send"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Send Text"].tap()
        XCTAssertTrue(app.buttons["compose-send"].exists)
        grabber(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(editor.exists, "Delivery blocks dismissal")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["qa-compose"].waitForExistence(timeout: 5)); app.buttons["qa-compose"].tap()
        XCTAssertTrue(app.textViews["compose-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose-text"].value as? String, "", "Background retires the draft and delivery")
    }

}
