import XCTest

@MainActor final class SavedControlsConsentTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func capture(_ title: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = title; image.lifetime = .keepAlways; add(image)
    }
    private func tapSwitch(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        let thumb = element.switches.firstMatch
        XCTAssertTrue(thumb.exists); thumb.tap()
    }
    func testContentOptInCanBeCancelledEnabledAndDisabledWithoutCloudEffects() {
        for large in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.savedcontrolsqa.ios")
            if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
            app.launch(); defer { app.terminate() }
            let toggle = app.switches["icloud-saved-content-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertEqual(toggle.value as? String, "0")
            tapSwitch(toggle, app: app)
            XCTAssertTrue(app.staticTexts["Sync shortcuts & saved text?"].waitForExistence(timeout: 5))
            let footer = app.staticTexts["Encrypted iCloud sync"]
            for _ in 0..<5 where !footer.isHittable { app.swipeUp() }
            XCTAssertTrue(footer.isHittable)
            XCTAssertTrue(app.buttons["icloud-saved-content-confirm"].isHittable)
            XCTAssertTrue(app.buttons["icloud-saved-content-cancel"].isHittable)
            capture(large ? "saved-content-consent-large-text" : "saved-content-consent")
            if !large {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.buttons["icloud-saved-content-cancel"].isHittable)
                capture("saved-content-consent-rotated")
            }
            app.buttons["icloud-saved-content-cancel"].tap()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(toggle.value as? String, "0", "Cancel must not opt in")
            tapSwitch(toggle, app: app)
            XCTAssertTrue(app.buttons["icloud-saved-content-confirm"].waitForExistence(timeout: 5))
            app.buttons["icloud-saved-content-confirm"].tap()
            XCTAssertEqual(toggle.value as? String, "1", "Only explicit confirmation opts in")
            let main = app.switches["icloud-library-toggle"]
            for _ in 0..<5 where !main.isHittable { app.swipeDown() }
            tapSwitch(main, app: app)
            XCTAssertTrue(toggle.isEnabled, "A remembered opt-in can be disabled while main sync is off")
            tapSwitch(toggle, app: app)
            XCTAssertEqual(toggle.value as? String, "0")
            XCTAssertFalse(toggle.isEnabled, "New content opt-in requires the main sync setting")
            app.terminate()
        }
    }
}
