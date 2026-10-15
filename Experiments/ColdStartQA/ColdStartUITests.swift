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

    func testUnlockTimingSnapshotWaitsForAdmissionAndEligibleNativeDisplayTick() {
        let app = launch(["--held-library", "--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-timing-status"].label, "Timing pending")
        XCTAssertTrue(app.buttons["open-app-settings"].isHittable)
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["qa-activate"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Timing ready"), object: app.staticTexts["qa-timing-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let phases = app.staticTexts["qa-timing-phases"].label
        for phase in ["authenticationCallback", "authenticationHandled", "localAdmission", "activationNotification", "activeAdmission", "coverRemoved", "unlockObserversReturned", "libraryDisplayTick"] {
            XCTAssertTrue(phases.contains(phase), phase)
        }
        XCTAssertTrue(app.staticTexts["Loading saved Macs…"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap(); app.buttons["qa-load-macs"].tap()
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5))
    }

    func testSuccessfulAuthenticationMakesActualLocalControlsWorkBeforeActivation() {
        let app = launch(["--inactive-auth", "--manual-auth", "--empty-library"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        let unlock = app.buttons["app-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5)); XCTAssertEqual(unlock.label, "Unlocking…")
        XCTAssertFalse(unlock.isEnabled)
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["app-privacy-cover"].isHittable)
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap(); app.buttons["Add Mac"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap(); app.buttons["qa-activate"].tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote ready")
    }
    func testRemoteOpeningWaitsForActivationWhileLocalSettingsWork() {
        let app = launch(["--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        connect("Free Mac", in: app)
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["qa-activate"].tap()
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
        app.buttons["mac-login-close"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
    }
    func testBackgroundRetiresRemoteOpeningRequestedDuringSuccessfulHandoff() {
        let app = launch(["--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        connect("Free Mac", in: app); app.buttons["qa-background"].tap()
        app.buttons["qa-activate"].tap(); app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 5))
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
    }
    func testLoadingSavedMacsOverlapsAuthenticationAndKeepsSettingsUsable() {
        let app = launch(["--held-library", "--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["app-unlock"].label, "Unlocking…")
        app.buttons["qa-finish-auth"].tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        XCTAssertTrue(app.staticTexts["Loading saved Macs…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Mac"].isEnabled)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["qa-load-macs"].tap()
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Loading saved Macs…"].exists)
        app.buttons["Manage Free Mac"].tap(); app.buttons["Mac Settings"].tap()
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
