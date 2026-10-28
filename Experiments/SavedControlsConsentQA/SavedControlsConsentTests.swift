import XCTest

@MainActor final class SavedControlsConsentTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func launch(large: Bool) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.savedcontrolsqa.ios")
        if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
        app.launch(); return app
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }
    private func tapSwitch(_ element: XCUIElement, app: XCUIApplication) {
        reveal(element, app: app)
        let thumb = element.switches.firstMatch; XCTAssertTrue(thumb.exists); thumb.tap()
    }
    func testOneSyncConfirmationIncludesSavedContentAndHasNoSeparateOption() {
        for large in [false, true] {
            let app = launch(large: large); defer { app.terminate() }
            app.buttons["fixture-sync"].tap()
            let toggle = app.switches["icloud-library-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertEqual(toggle.value as? String, "0")
            XCTAssertFalse(app.switches["icloud-saved-content-toggle"].exists)
            tapSwitch(toggle, app: app)
            XCTAssertTrue(app.staticTexts["Enable iCloud Sync?"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Saved Macs, keyboard layouts, shortcuts and saved text."].exists)
            let footer = app.staticTexts["Encrypted iCloud sync"]; reveal(footer, app: app)
            XCTAssertTrue(app.buttons["icloud-enable-confirm"].isHittable)
            XCTAssertTrue(app.buttons["icloud-enable-cancel"].isHittable)
            capture(large ? "unified-sync-large-text" : "unified-sync")
            if !large {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.buttons["icloud-enable-cancel"].isHittable); capture("unified-sync-rotated")
            }
            app.buttons["icloud-enable-cancel"].tap(); XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(toggle.value as? String, "0")
            tapSwitch(toggle, app: app)
            app.buttons["icloud-enable-confirm"].tap()
            XCTAssertEqual(toggle.value as? String, "1")
            XCTAssertFalse(app.switches["icloud-saved-content-toggle"].exists)
            tapSwitch(toggle, app: app); XCTAssertEqual(toggle.value as? String, "0")
            app.terminate()
        }
    }
    func testGuidanceRowsAndSecurityDetailsStayReachable() {
        let routes: [(String, String, String)] = [
            ("gestures", "Gesture Guide", "Customize"),
            ("setup", "Set Up Your Mac", "Your Mac account"),
            ("trust", "Verify This Mac", "2. Match the key type"),
            ("identity", "Verify Server Identity", "3. Verify again"),
            ("manual", "Manual Key Setup", "5. Test the key"),
            ("keyImport", "Import SSH Key", "Ed25519 OpenSSH keys only, up to 32 KiB. Import passphrases are used once and never saved.")
        ]
        for large in [false, true] {
            for (route,title,last) in routes {
                // Passive guidance capture does not assume where system chrome
                // puts modal/navigation buttons in the current Duo fold shape.
                let app = launch(large: large)
                let button = app.buttons["fixture-" + route]; reveal(button, app: app); button.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
                reveal(app.staticTexts[last], app: app)
                if route == "trust" {
                    XCTAssertTrue(app.staticTexts["ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"].exists)
                    XCTAssertTrue(app.buttons["server-trust-cancel"].isHittable)
                }
                capture("copy-" + route + (large ? "-large-text" : ""))
                if route == "trust" {
                    app.buttons["server-trust-cancel"].tap()
                    XCTAssertTrue(app.navigationBars["Copy QA"].waitForExistence(timeout: 5))
                }
                app.terminate()
            }
        }
    }
}
