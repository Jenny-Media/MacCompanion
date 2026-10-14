import XCTest
@MainActor final class ColdStartUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.coldstartqa.ios")
        app.launchArguments = arguments; app.launch(); return app
    }
    private func connect(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Connect to " + name + " using ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
    }
    func testInactiveAuthenticationThenActivationMakesActualSettingsAndAddControlsWork() {
        let app = launch(["--inactive-auth", "--manual-auth", "--empty-library"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        let unlock = app.buttons["app-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5)); XCTAssertEqual(unlock.label, "Unlocking…")
        XCTAssertFalse(unlock.isEnabled)
        let evaluating = XCTAttachment(screenshot: app.screenshot()); evaluating.name = "synthetic-unlock-evaluating"; evaluating.lifetime = .keepAlways; add(evaluating)
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 8))
        XCTAssertEqual(unlock.label, "Opening…"); XCTAssertFalse(unlock.isEnabled)
        let pending = XCTAttachment(screenshot: app.screenshot()); pending.name = "synthetic-unlock-pending"; pending.lifetime = .keepAlways; add(pending)
        let cover = app.descendants(matching: .any)["app-privacy-cover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mac Companion"].isHittable)
        XCTAssertTrue(app.staticTexts["Unlock to access your Macs"].exists)
        XCTAssertTrue(unlock.exists)
        XCTAssertFalse(app.buttons["open-app-settings"].isHittable)
        XCTAssertFalse(app.navigationBars["My Macs"].isHittable)
        app.buttons["qa-activate"].tap()
        XCTAssertFalse(cover.isHittable)
        XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 5)); app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap(); app.buttons["Add Mac"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
    }
    func testFreeConnectionAndExistingEditingDoNotWaitForStoreKit() {
        let app = launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5)); app.buttons["Manage Free Mac"].tap()
        app.buttons["Mac Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap(); connect("Free Mac", in: app)
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
        app.buttons["mac-login-close"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
    }
    func testPaidActionTimesOutAndRetiredCompletionDoesNotPresent() {
        let app = launch(["--fast-timeout"]); defer { app.terminate() }
        connect("Second Mac", in: app)
        XCTAssertTrue(app.staticTexts["Checking purchases…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["mac-access-timeout"].waitForExistence(timeout: 5))
        app.buttons["mac-access-retry"].tap()
        app.buttons["qa-background"].tap(); app.buttons["qa-resolve-store"].tap(); app.buttons["qa-activate"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
    }
    func testVerifiedReadinessCompletesOnlyCurrentPendingAction() {
        let app = launch(); defer { app.terminate() }
        connect("Second Mac", in: app)
        XCTAssertTrue(app.staticTexts["Checking purchases…"].waitForExistence(timeout: 3))
        app.buttons["qa-resolve-store"].tap()
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
    }
}
