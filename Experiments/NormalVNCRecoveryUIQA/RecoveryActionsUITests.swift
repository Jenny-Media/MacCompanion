import XCTest

final class RecoveryActionsUITests: XCTestCase {
    @MainActor private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.recoverydiagnosis.ios")
        app.launchArguments = arguments; app.launch(); return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testTransportRecoveryShowsNewShellWithoutLoginEditing() {
        let app = launch()
        XCTAssertTrue(app.buttons["terminal-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["terminal-connect"].label.contains("Open New Shell"))
        XCTAssertFalse(app.buttons["terminal-change-login"].exists)
        XCTAssertFalse(app.textFields["Mac account username"].exists)
        XCTAssertTrue(app.buttons["terminal-login-details"].exists)
        capture(app, "synthetic-compact-terminal-recovery")
    }
    @MainActor func testIssueDetailsRefreshInlineAfterSessionChanges() async throws {
        let app = launch("replace-issue")
        XCTAssertTrue(app.buttons["terminal-login-details"].waitForExistence(timeout: 10))
        app.buttons["terminal-login-details"].tap()
        XCTAssertTrue(app.staticTexts["Stage, Original stage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stage, Replacement stage"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["Stage, Original stage"].exists)
        XCTAssertTrue(app.staticTexts["Address, synthetic.local"].exists)
        capture(app, "synthetic-inline-issue-details")
        XCTAssertTrue(app.buttons["terminal-connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Connection Issue"].exists)
    }
    @MainActor func testNoIssueDiagnosticsStillOffersConfiguredConnectionDetails() {
        let app = launch("no-details")
        XCTAssertTrue(app.buttons["terminal-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["terminal-login-details"].exists)
        app.buttons["terminal-login-details"].tap()
        XCTAssertTrue(app.staticTexts["Address, synthetic.local"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Remote Login · SSH, 2222"].exists)
        XCTAssertFalse(app.staticTexts["Issue Details"].exists)
        XCTAssertFalse(app.navigationBars["Connection Issue"].exists)
        XCTAssertFalse(app.buttons["terminal-change-login"].exists)
    }
    @MainActor func testExpandedConnectionDetailsPersistThroughRecoveryAndLoginEditing() {
        let app = launch("inline-details")
        let details = app.buttons["terminal-login-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10)); details.tap()
        XCTAssertTrue(app.staticTexts["Address, synthetic.local"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fallback 1, 100.64.0.12"].exists)
        XCTAssertTrue(app.staticTexts["Remote Login · SSH, 2222"].exists)
        app.buttons["Simulate Authentication Failure"].tap()
        XCTAssertTrue(app.staticTexts["Stage, Authentication stage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Address, synthetic.local"].exists)
        app.buttons["Simulate Transport Failure"].tap()
        XCTAssertTrue(app.staticTexts["Stage, Replacement stage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Stage, Authentication stage"].exists)
        XCTAssertTrue(app.staticTexts["Fallback 1, 100.64.0.12"].exists)
        XCTAssertTrue(app.staticTexts["Remote Login · SSH, 2222"].exists)
        let account = app.textFields["Mac account username"]
        account.tap(); account.typeText("x")
        XCTAssertFalse(app.staticTexts["Stage, Replacement stage"].exists)
        XCTAssertTrue(app.staticTexts["Address, synthetic.local"].exists)
        XCTAssertTrue(app.staticTexts["Remote Login · SSH, 2222"].exists)
        XCTAssertFalse(app.navigationBars["Connection Issue"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
    }
    @MainActor func testAuthenticationFailureKeepsWorkingPasswordAndKeyPicker() {
        let app = launch("auth-rejected")
        XCTAssertTrue(app.textFields["Mac account username"].waitForExistence(timeout: 10))
        app.buttons["terminal-login-method"].tap()
        XCTAssertTrue(app.buttons["SSH Key"].waitForExistence(timeout: 5))
        app.buttons["SSH Key"].tap()
        XCTAssertTrue(app.buttons["Choose SSH Key"].waitForExistence(timeout: 5))
        app.buttons["terminal-login-method"].tap()
        app.buttons["Password"].tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5))
        capture(app, "synthetic-editable-authentication-failure")
    }
    @MainActor func testCachedEditorOnlyScansOnExplicitRefresh() async throws {
        let app = launch("cached-editor")
        XCTAssertTrue(app.buttons["mac-refresh-details"].waitForExistence(timeout: 10))
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(app.staticTexts["Detecting Mac details…"].exists)
        capture(app, "synthetic-cached-mac-editor")
        app.buttons["mac-refresh-details"].tap()
        XCTAssertTrue(app.staticTexts["Detecting Mac details…"].waitForExistence(timeout: 5))
    }
    @MainActor func testEditingEndpointsStartsDetectionAfterDebounce() {
        let app = launch("cached-editor")
        XCTAssertTrue(app.buttons["mac-refresh-details"].waitForExistence(timeout: 10))
        let address = app.textFields["IP address or hostname"]
        app.swipeUp()
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap(); address.typeText("x")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Detecting Mac details…"].waitForExistence(timeout: 5))
    }
    @MainActor func testMacListUsesCachedDetailsAndClearOpenAction() async throws {
        let app = launch("mac-list")
        XCTAssertTrue(app.buttons["Connect to Synthetic Mac using Desktop"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Open Desktop"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Open Desktop"].waitForExistence(timeout: 10))
        capture(app, "synthetic-mac-open-desktop")
    }
    @MainActor private func checkMacListAlignment(_ size: String, captureName: String) {
        let app = launch("mac-list-alignment", size)
        let title = app.staticTexts["Laptop"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let menu = app.buttons["Manage Laptop"]
        XCTAssertTrue(menu.isHittable)
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        let action = app.staticTexts["Open Trackpad & Keyboard"]
        XCTAssertTrue(action.exists)
        let address = app.staticTexts["laptop.local · 2 addresses"]
        XCTAssertTrue(address.exists)
        XCTAssertEqual(action.frame.minX, title.frame.minX, accuracy: 1)
        XCTAssertEqual(address.frame.minX, title.frame.minX, accuracy: 1)
        let textColumn = title.frame.union(action.frame).union(address.frame)
        XCTAssertEqual(menu.frame.midY, textColumn.midY, accuracy: 4, "The menu must stay centered against the text column when it wraps")
        XCTAssertGreaterThan(action.frame.minY, title.frame.minY)
        XCTAssertLessThanOrEqual(action.frame.maxX, menu.frame.minX)
        capture(app, captureName)
        menu.tap()
        XCTAssertTrue(app.buttons["Mac Settings"].waitForExistence(timeout: 5))
    }
    @MainActor func testMacListIconAlignmentAtDefaultTextSize() {
        checkMacListAlignment("default-text", captureName: "synthetic-mac-list-default-text")
    }
    @MainActor func testMacListIconAlignmentWithWrappedLargeText() {
        checkMacListAlignment("large-text", captureName: "synthetic-mac-list-large-text")
    }
    @MainActor func testMacListIconAlignmentAtAccessibilityTextSize() {
        checkMacListAlignment("accessibility-text", captureName: "synthetic-mac-list-accessibility-text")
    }
}
