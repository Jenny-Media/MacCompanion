import XCTest

@MainActor
final class ScreenTextUITests: XCTestCase {
    private func launch(largeText: Bool = false, viewportGesture: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if largeText { app.launchEnvironment["MACCOMPANION_SCREEN_TEXT_AXXXL"] = "1" }
        if viewportGesture { app.launchEnvironment["MACCOMPANION_SCREEN_TEXT_VIEWPORT_GESTURE"] = "1" }
        app.launch()
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 10))
        return app
    }
    private func area(_ app: XCUIApplication) {
        let segment = app.segmentedControls["text-copy-mode"].buttons["Area"]
        for _ in 0..<5 where !segment.isHittable { app.swipeUp() }
        segment.tap()
        let copy = app.buttons["text-copy-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.textViews["text-copy-result"].exists, "Area recognition must not open Review")
    }
    private func review(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["text-copy-edit"]
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        button.tap()
        let editor = app.textViews["text-copy-result"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Review opens without the keyboard")
        return editor
    }
    private func attach(_ app: XCUIApplication) {
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.lifetime = .keepAlways; add(capture)
    }
    func testNativeWordSelectionCanCopyAndPreserveReviewedCorrection() throws {
        let app = launch()
        guard app.segmentedControls["text-copy-mode"].buttons["Text"].isEnabled else { throw XCTSkip("System Live Text unavailable") }
        let status = app.staticTexts["text-copy-status"]
        expectation(for: NSPredicate(format: "label == %@", "Touch and hold text to select"), evaluatedWith: status)
        waitForExpectations(timeout: 20)
        let image = app.otherElements["text-copy-selection"]
        let fit = min((image.frame.width - 44) / 1000, (image.frame.height - 44) / 700)
        let word = image.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 22 + fit * 140, dy: 22 + fit * 140))
        word.press(forDuration: 1)
        let copy = app.buttons["text-copy-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy); waitForExpectations(timeout: 5)
        copy.tap(); XCTAssertEqual(status.label, "Copied")
        XCTAssertFalse(app.textViews["text-copy-result"].exists)
        let editor = review(app); editor.tap(); editor.typeText(" corrected")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.keyboards.firstMatch.frame.height, 100, "A visible software keyboard is required for this layout check")
        let corrected = editor.value as? String
        XCTAssertTrue(corrected?.contains("corrected") == true)
        app.buttons["text-copy-review-close"].tap()
        XCTAssertFalse(editor.exists)
        copy.tap(); XCTAssertEqual(status.label, "Copied")
        XCTAssertEqual(review(app).value as? String, corrected)
        attach(app)
    }
    func testAreaOutlineAdjustmentReviewDrawerRotationKeyboardAndCopy() {
        let app = launch(); area(app); attach(app)
        let corner = app.buttons["Bottom right selection corner"]
        XCTAssertTrue(corner.isHittable)
        let end = corner.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -25, dy: -20))
        corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: end)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["text-copy-copy"]); waitForExpectations(timeout: 20)
        let editor = review(app)
        XCTAssertTrue((editor.value as? String)?.contains("mini.local") == true)
        attach(app)
        // Native sheet supports expanding by dragging its header without editing.
        let title = app.staticTexts["Review Text"]
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        editor.tap(); editor.typeText(" edited")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.keyboards.firstMatch.frame.height, 100, "A visible software keyboard is required for this layout check")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let copy = app.buttons["text-copy-review-copy"]
        XCTAssertTrue(copy.isHittable); copy.tap()
        XCTAssertEqual(app.staticTexts["text-copy-review-status"].label, "Copied")
        XCTAssertTrue(app.buttons["text-copy-review-close"].isHittable); attach(app)
        app.buttons["text-copy-review-close"].tap()
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].isHittable)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
    }
    func testAreaStartsFromFrozenViewportAfterPinchAndPan() {
        let app = launch(viewportGesture: true)
        let text = app.segmentedControls["text-copy-mode"].buttons["Text"]
        XCTAssertTrue(text.isEnabled, "This Simulator must exercise the Text to Area path")
        let image = app.otherElements["text-copy-selection"]
        let bitmap = app.descendants(matching: .any)["screen-text-pinch-image"]
        XCTAssertTrue(bitmap.waitForExistence(timeout: 5))
        let probe = app.navigationBars.buttons["screen-text-viewport-probe"]
        func viewport() -> [Double] {
            probe.tap()
            let value = probe.value as? String ?? ""
            XCTContext.runActivity(named: "Frozen viewport: " + value) { _ in }
            return value.split(separator: "|").compactMap { Double($0) }
        }
        let initial = viewport()
        XCTAssertEqual(initial.count, 5)
        bitmap.pinch(withScale: 2, velocity: 1)
        var zoomed = viewport()
        if initial.count == 5 && zoomed.count == 5 && zoomed[0] <= initial[0] * 1.05 {
            // XCTest can deliver no effective scale change on the tablet.
            // Retry the real gesture, then require measured zoom and cropping.
            bitmap.pinch(withScale: 4, velocity: 1)
            zoomed = viewport()
        }
        if initial.count == 5 && zoomed.count == 5 {
            XCTAssertGreaterThan(zoomed[0], initial[0] * 1.1, "The native pinch must actually zoom the frozen image")
        }
        image.swipeLeft()
        let visible = viewport()
        XCTAssertEqual(visible.count, 5)
        app.segmentedControls["text-copy-mode"].buttons["Area"].tap()
        let corner = app.buttons["Top left selection corner"]
        XCTAssertTrue(corner.waitForExistence(timeout: 5))
        let dimensions = (corner.value as? String ?? "")
            .components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        XCTAssertEqual(dimensions.count, 2)
        if dimensions.count == 2 {
            XCTAssertGreaterThan(dimensions[0], 0)
            XCTAssertLessThan(dimensions[0] * dimensions[1], 1000 * 700, "The gesture must leave a cropped viewport")
            if visible.count == 5 {
                XCTAssertEqual(dimensions[0], Int(visible[3]), "Area must match the frozen view immediately before the mode switch")
                XCTAssertEqual(dimensions[1], Int(visible[4]))
            }
        }
        attach(app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
    }
    func testEdgeBackReturnsAndRepeatedCopyStaysAvailable() {
        let app = launch()
        for cycle in 0..<2 {
            area(app)
            app.buttons["text-copy-copy"].tap()
            XCTAssertEqual(app.staticTexts["text-copy-status"].label, "Copied")
            // An ordinary image drag must adjust/pan without navigating away.
            let image = app.otherElements["text-copy-selection"]
            image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2,
                thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
            XCTAssertTrue(app.navigationBars.buttons["BackButton"].exists)
            // Leading-edge Back remains reachable near the bottom of the phone.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.65)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)))
            XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
            if cycle == 0 { app.buttons["screen-text-open"].tap() }
        }
    }
    func testBackgroundRetiresSnapshotAndOpenReviewDrawer() {
        let app = launch(); area(app); _ = review(app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["text-copy-result"].exists)
        XCTAssertFalse(app.buttons["text-copy-review-copy"].exists)
    }
    func testLargestTextReviewCopyAndCloseRemainReachableWithKeyboard() {
        let app = launch(largeText: true); area(app)
        let editor = review(app); editor.tap(); editor.typeText(" edited")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.keyboards.firstMatch.frame.height, 100, "A visible software keyboard is required for this layout check")
        let copy = app.buttons["text-copy-review-copy"]
        XCTAssertTrue(copy.isHittable); copy.tap()
        XCTAssertEqual(app.staticTexts["text-copy-review-status"].label, "Copied")
        XCTAssertTrue(app.buttons["text-copy-review-close"].isHittable); attach(app)
        app.buttons["text-copy-review-close"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.staticTexts["screen-text-returned"].waitForExistence(timeout: 5))
    }
}
