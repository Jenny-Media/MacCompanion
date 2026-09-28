import XCTest

/// A fresh real TLS pairing session from the disposable signed Agent. The
/// test host withholds approval; cancellation must leave the app unpaired.
@MainActor
final class LivePairingUITests: XCTestCase {
    func testNormalAppVerifiesLivePairingAndCancels() throws {
        continueAfterFailure = false
        let code = try XCTUnwrap(ProcessInfo.processInfo.environment["MACCOMPANION_TEST_PAIRING_CODE"])
        let app = XCUIApplication(bundleIdentifier: "media.jenny.maccompanion.ios")
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10))
        app.buttons["Enter Pairing Code"].tap()
        let input = app.textViews["Pairing Code"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(code)
        app.buttons["Use Code"].tap()
        XCTAssertTrue(app.buttons["Connect Securely"].waitForExistence(timeout: 10))
        app.buttons["Connect Securely"].tap()
        XCTAssertTrue(app.staticTexts["Compare this code on your Mac"].waitForExistence(timeout: 30),
                      "Live pairing did not reach verified comparison; inspect app and Agent diagnostics.")
        XCTAssertFalse(app.staticTexts["Mac Connected"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Mac Connected"].exists)
    }
}
