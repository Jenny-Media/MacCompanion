import XCTest

@MainActor
final class ReceiverUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.webrtc.receiver")

    private func waitFor(_ text: String, timeout: TimeInterval = 15) {
        let status = app.staticTexts["status"]
        let condition = NSPredicate(format: "label CONTAINS %@", text)
        expectation(for: condition, evaluatedWith: status)
        waitForExpectations(timeout: timeout)
    }

    func testRotationAndStop() {
        continueAfterFailure = false
        app.activate()
        waitFor("Receiving")
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate { [app] _, _ in app.frame.height > app.frame.width }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        let before = app.staticTexts["status"].label
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { [app] _, _ in app.frame.width > app.frame.height }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "Receiving", before),
                    evaluatedWith: app.staticTexts["status"])
        waitForExpectations(timeout: 10)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Captured test pattern in landscape"
        picture.lifetime = .keepAlways
        add(picture)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["stop-test"].tap()
        waitFor("stopped")
        let stopped = app.staticTexts["status"].label
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(app.staticTexts["status"].label, stopped)
    }

    func testBackgroundAutomaticallyReconnects() {
        continueAfterFailure = false
        app.activate()
        waitFor("Receiving")
        for cycle in 0..<8 {
            let previousSession = app.staticTexts["status"].value as? String
            XCTAssertNotEqual(previousSession, "none")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            app.activate()
            // Interrupt a resume before its replacement offer necessarily arrives.
            if cycle % 3 == 1 {
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
                app.activate()
            }
            waitFor("Receiving", timeout: 40)
            XCTAssertNotEqual(app.staticTexts["status"].value as? String, previousSession)
            let before = app.staticTexts["status"].label
            expectation(for: NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "Receiving", before),
                        evaluatedWith: app.staticTexts["status"])
            waitForExpectations(timeout: 10)
        }
        app.buttons["stop-test"].tap()
        waitFor("stopped")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        waitFor("stopped")
        let stopped = app.staticTexts["status"].label
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        XCTAssertEqual(app.staticTexts["status"].label, stopped)
        XCTAssertEqual(app.staticTexts["status"].value as? String, "none")
    }

    // Connect this method to a host session with a 30-second total lifetime.
    func testExpiredBackgroundSessionDoesNotReconnect() {
        continueAfterFailure = false
        app.activate()
        waitFor("Receiving")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(32))
        app.activate()
        waitFor("expired")
        XCTAssertEqual(app.staticTexts["status"].value as? String, "none")
    }
}
