import XCTest

final class ClientUIHarnessUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    private func launchHarness(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(
            app.navigationBars["Mac Companion"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testClosedSurfacesAreSemanticallyReachable() throws {
        launchHarness()
        XCTAssertTrue(app.staticTexts["No networking or credentials"].exists)
        XCTAssertTrue(app.buttons["Host Summary"].isHittable)
        XCTAssertTrue(app.buttons["Mac Status"].isHittable)
        XCTAssertTrue(app.buttons["Approved Actions"].isHittable)
        XCTAssertTrue(app.buttons["Pairing Entry"].isHittable)
        XCTAssertTrue(app.buttons["Private Access Guidance"].isHittable)
        XCTAssertTrue(app.buttons["First-Pairing Route Choices"].isHittable)
        XCTAssertTrue(app.buttons["Edit Saved Routes"].isHittable)
        XCTAssertTrue(app.buttons["Application Lifecycle"].isHittable)
        XCTAssertTrue(app.buttons["Live Control Screen"].isHittable)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Choose Mac View"].isHittable)
        app.swipeDown()

        app.buttons["Host Summary"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready"].exists)
        XCTAssertTrue(app.buttons["Open Remote Control"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Mac Status"].tap()
        XCTAssertTrue(app.navigationBars["Mac Status"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Live status"].exists)
        XCTAssertTrue(app.staticTexts["Mac Health"].exists)
        XCTAssertTrue(app.staticTexts["History is incomplete"].exists)
        XCTAssertTrue(app.buttons["Refresh Status"].isHittable)
        XCTAssertTrue(app.buttons["View Activity"].isHittable)
        XCTAssertFalse(app.buttons["Open Remote Control"].exists)
        app.buttons["View Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["History is incomplete"].exists)
        XCTAssertTrue(app.staticTexts["Action completed"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Approved Actions"].tap()
        XCTAssertTrue(
            app.navigationBars["Approved Actions"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["Typed synthetic Act flow; no socket, credential, or signer. Reloads: 0"].exists)
        XCTAssertTrue(app.buttons["Set audio mute"].isHittable)
        XCTAssertFalse(app.buttons["Open Remote Control"].exists)
        app.buttons["Set audio mute"].tap()
        XCTAssertTrue(app.navigationBars["Set audio mute"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Muted"].isHittable)
        XCTAssertTrue(app.switches["Muted"].isEnabled)
        XCTAssertEqual(app.switches["Muted"].value as? String, "0")
        XCTAssertTrue(app.buttons["Run Approved Action"].isHittable)
        app.switches["Muted"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .tap()
        let mutedOn = NSPredicate(format: "value == %@", "1")
        expectation(for: mutedOn, evaluatedWith: app.switches["Muted"])
        waitForExpectations(timeout: 2)
        app.buttons["Run Approved Action"].tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.descendants(matching: .any)["Verified result $.muted"].label,
            "Muted, Yes"
        )
        XCTAssertFalse(app.buttons["Open Remote Control"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Pairing Entry"].tap()
        XCTAssertTrue(app.navigationBars["Connect to Mac"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Scan Pairing Code"].isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["First-Pairing Route Choices"].tap()
        XCTAssertTrue(app.navigationBars["Choose Private Routes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["studio.example.test:47474"].exists)
        XCTAssertTrue(app.staticTexts["203.0.113.10:47474"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Edit Saved Routes"].tap()
        XCTAssertTrue(app.navigationBars["Private Routes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["studio.example.test:47474"].exists)
        XCTAssertTrue(app.buttons["Add Route"].isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        if !app.buttons["Choose Mac View"].isHittable { app.swipeUp() }
        app.buttons["Choose Mac View"].tap()
        XCTAssertTrue(app.navigationBars["Choose Mac View"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Desktop"].isHittable)
        XCTAssertTrue(app.buttons["Notes, Application Focus"].isHittable)
        XCTAssertTrue(app.staticTexts["Window 2"].exists)
        XCTAssertTrue(app.staticTexts["Unavailable"].exists)
    }

    @MainActor
    func testPrivateAccessGuidanceIsNoRelayAndNonAuthorizing() throws {
        launchHarness()
        app.buttons["Private Access Guidance"].tap()
        XCTAssertTrue(
            app.navigationBars["Private Access"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["No usable network path"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Same Local Network"].exists)
        XCTAssertTrue(app.staticTexts["User-Managed Private Network"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Tailscale")
            ).firstMatch.exists
        )
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "operates no relay")
            ).firstMatch.exists
        )
        XCTAssertFalse(app.buttons["Open Remote Control"].exists)
        XCTAssertFalse(app.buttons["Connect"].exists)
    }

    @MainActor
    func testLiveControlKeyboardAndStopAreSemanticallyReachable() throws {
        launchHarness()
        app.buttons["Live Control Screen"].tap()
        XCTAssertTrue(
            app.navigationBars["Studio Mac"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Synthetic Desktop\nNo network or captured pixels"]
                .exists
        )
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Keyboard"].isHittable)
        let pointerMode = app.buttons["Pointer mode"]
        XCTAssertTrue(pointerMode.exists)
        XCTAssertTrue(pointerMode.isEnabled)
        XCTAssertEqual(pointerMode.label, "Pointer mode, Touch")

        app.buttons["Keyboard"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        for key in ["h", "e", "l", "l", "o"] {
            app.keys[key].tap()
        }
        let receivedInput = NSPredicate(
            format: "label BEGINSWITH %@ AND label != %@",
            "Synthetic input payloads:",
            "Synthetic input payloads: 0"
        )
        expectation(
            for: receivedInput,
            evaluatedWith: app.descendants(matching: .any)[
                "Synthetic input payload count"
            ]
        )
        waitForExpectations(timeout: 2)

        app.buttons["Stop"].tap()
        XCTAssertTrue(
            app.navigationBars["Mac Companion"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.keyboards.element.exists)
    }

    @MainActor
    func testLifecycleUsesInjectedReachabilityAndRearmsAfterBackground()
        throws
    {
        launchHarness()
        app.buttons["Application Lifecycle"].tap()
        XCTAssertTrue(
            app.navigationBars["Application Lifecycle"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle network"].label,
            "Injected network, Not reachable"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle dial rounds"].label,
            "Synthetic dial rounds, 0"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Lifecycle terminal failures"
            ].label,
            "Terminal failures, 0"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Lifecycle private access"
            ].label,
            "Private access, No usable network path"
        )

        app.buttons["Set Reachable"].tap()
        let firstRound = NSPredicate(
            format: "label == %@",
            "Synthetic dial rounds, 1"
        )
        expectation(
            for: firstRound,
            evaluatedWith: app.descendants(matching: .any)[
                "Lifecycle dial rounds"
            ]
        )
        waitForExpectations(timeout: 2)
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle network"].label,
            "Injected network, Reachable"
        )
        let authenticated = NSPredicate(
            format: "label == %@",
            "Private access, Connected through Local Discovery"
        )
        expectation(
            for: authenticated,
            evaluatedWith: app.descendants(matching: .any)[
                "Lifecycle private access"
            ]
        )
        waitForExpectations(timeout: 2)

        XCUIDevice.shared.press(.home)
        app.activate()
        let secondRound = NSPredicate(
            format: "label == %@",
            "Synthetic dial rounds, 2"
        )
        expectation(
            for: secondRound,
            evaluatedWith: app.descendants(matching: .any)[
                "Lifecycle dial rounds"
            ]
        )
        waitForExpectations(timeout: 3)
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle app state"].label,
            "App state, Foreground"
        )
    }

    @MainActor
    func testLifecycleTerminalFailureStopsFurtherReachability() throws {
        launchHarness(arguments: ["--invalid-round-id"])
        app.buttons["Application Lifecycle"].tap()
        XCTAssertTrue(
            app.navigationBars["Application Lifecycle"]
                .waitForExistence(timeout: 2)
        )

        app.buttons["Set Reachable"].tap()
        let closed = NSPredicate(
            format: "label BEGINSWITH %@",
            "Binding, Closed:"
        )
        expectation(
            for: closed,
            evaluatedWith: app.descendants(matching: .any)[
                "Lifecycle binding"
            ]
        )
        waitForExpectations(timeout: 2)
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle dial rounds"].label,
            "Synthetic dial rounds, 0"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Lifecycle terminal failures"
            ].label,
            "Terminal failures, 1"
        )

        app.buttons["Set Reachable"].tap()
        XCTAssertEqual(
            app.descendants(matching: .any)["Lifecycle dial rounds"].label,
            "Synthetic dial rounds, 0"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Lifecycle terminal failures"
            ].label,
            "Terminal failures, 1"
        )
        XCTAssertTrue(
            closed.evaluate(
                with: app.descendants(matching: .any)["Lifecycle binding"]
            )
        )
    }

    @MainActor
    func testHostStateMenuChangesClosedProjection() throws {
        launchHarness()
        app.buttons["Host Summary"].tap()
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 2))

        app.buttons["Host state, Ready"].tap()
        app.buttons["No Network"].tap()

        XCTAssertTrue(app.staticTexts["No Private Network"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Reconnect"].isHittable)
        XCTAssertFalse(app.staticTexts["Controlling Mac"].exists)
    }
}
