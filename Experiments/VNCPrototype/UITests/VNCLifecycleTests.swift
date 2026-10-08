import XCTest

@MainActor
final class VNCLifecycleTests: XCTestCase {
    func testViewsKeyboardAndBackgroundRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let status = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Connected · connections 1'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        for _ in 0..<10 {
            app.buttons["Desktop ▾"].tap()
            app.buttons["All Displays"].tap()
        }
        XCTAssertTrue(status.exists, "View choices must keep the original connection")
        app.buttons["⌨"].tap()
        let tutorial = app.buttons["Continue"]
        if tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.keyboards.keys["q"].tap()
        app.keyboards.keys["delete"].tap()
        app.buttons["⌨"].tap()
        XCUIDevice.shared.press(.home)
        let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 5), .completed)
        app.activate()
        let resumed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Connected · connections 2'")).firstMatch
        XCTAssertTrue(resumed.waitForExistence(timeout: 10))
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 5))
    }
}
