import XCTest

@MainActor
final class ScreenTextUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["text-copy-return"].waitForExistence(timeout: 10))
        return app
    }

    func testNativeWordSelectionCanCopyWithoutOpeningReview() throws {
        let app = launch()
        guard app.buttons["text-copy-area"].exists else {
            throw XCTSkip("System Live Text is unavailable in this Simulator; automatic area flow is tested independently")
        }
        let status = app.staticTexts["text-copy-status"]
        let ready = NSPredicate(format: "label == %@", "Select the text you want to copy")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        let image = app.otherElements["text-copy-selection"]
        XCTAssertTrue(image.exists)
        let fit = min(image.frame.width / 1000, image.frame.height / 700)
        let word = image.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: fit * 140, dy: fit * 140))
        let before = XCTAttachment(screenshot: app.screenshot()); before.lifetime = .keepAlways; add(before)
        word.press(forDuration: 1)
        let after = XCTAttachment(screenshot: app.screenshot()); after.lifetime = .keepAlways; add(after)
        let copy = app.buttons["text-copy-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 5)
        copy.tap()
        XCTAssertEqual(status.label, "Copied")
        XCTAssertFalse(app.textViews["text-copy-result"].exists)
        app.buttons["text-copy-edit"].tap()
        let editor = app.textViews["text-copy-result"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" corrected")
        let corrected = editor.value as? String
        XCTAssertTrue(corrected?.contains("corrected") == true)
        app.buttons["text-copy-edit"].tap()
        XCTAssertFalse(editor.exists)
        app.buttons["text-copy-copy"].tap()
        XCTAssertEqual(status.label, "Copied")
        app.buttons["text-copy-edit"].tap()
        XCTAssertEqual(editor.value as? String, corrected)
    }

    func testAreaRecognizesAutomaticallyAndKeepsEditingAndDoneReachable() {
        let app = launch()
        let area = app.buttons["text-copy-area"]
        if area.exists { area.tap() }
        let editor = app.textViews["text-copy-result"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        XCTAssertTrue((editor.value as? String)?.contains("mini.local") == true)
        XCTAssertTrue(app.buttons["text-copy-return"].isHittable)
        let bottomRight = app.buttons["Bottom right selection corner"]
        XCTAssertTrue(bottomRight.isHittable)
        let end = bottomRight.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -35, dy: -30))
        bottomRight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        editor.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["text-copy-return"].isHittable)
        app.buttons["text-copy-copy"].tap()
        XCTAssertEqual(app.staticTexts["text-copy-status"].label, "Copied")
        app.buttons["text-copy-return"].tap()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
    }

    func testBackgroundRetiresTheSnapshot() {
        let app = launch()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["text-copy-result"].exists)
    }

    func testLargestTextCanScrollToEditAndCopyWithKeyboardOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["MACCOMPANION_SCREEN_TEXT_AXXXL"] = "1"
        app.launch()
        let done = app.buttons["text-copy-return"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        for _ in 0..<6 where !app.buttons["text-copy-area"].isHittable { app.swipeUp() }
        let area = app.buttons["text-copy-area"]
        if area.exists { area.tap() }
        let editor = app.textViews["text-copy-result"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        for _ in 0..<6 where !editor.isHittable { app.swipeDown() }
        XCTAssertTrue(editor.isHittable)
        editor.tap()
        editor.typeText(" edited")
        let copy = app.buttons["text-copy-copy"]
        for _ in 0..<8 where !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertEqual(app.staticTexts["text-copy-status"].label, "Copied")
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
    }
}
