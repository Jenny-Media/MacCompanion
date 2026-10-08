import XCTest

@MainActor
final class PairingPasteUITests: XCTestCase {
    func testNormalAppRejectsInvalidCodeAndShowsUnverifiedPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "media.jenny.maccompanion.ios")
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Simulator testing · Device protection is unavailable"].exists)
        app.buttons["Enter Pairing Code"].tap()
        let input = app.textViews["Pairing Code"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("not-a-pairing-code")
        app.buttons["Use Code"].tap()
        XCTAssertTrue(app.buttons["Try Again"].waitForExistence(timeout: 10))
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10))
        let location = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pairing-qr-payload", withExtension: "json"))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any])
        // Runtime synthetic preview only: no listener is started, no Connect
        // action is taken, and the authoritative fixture remains unchanged.
        payload["expiresAtUnixMilliseconds"] = Int64(Date().timeIntervalSince1970 * 1000) + 300_000
        payload["endpoints"] = [["kind": "ipv4", "value": "127.0.0.1", "port": 59654]]
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let encoded = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        app.buttons["Enter Pairing Code"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("maccompanion://pair/v0.1/" + encoded)
        app.buttons["Use Code"].tap()
        XCTAssertTrue(app.buttons["Connect Securely"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ready to verify this Mac"].exists)
        XCTAssertFalse(app.staticTexts["Mac Connected"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Scan Pairing Code"].waitForExistence(timeout: 10))
    }

}
