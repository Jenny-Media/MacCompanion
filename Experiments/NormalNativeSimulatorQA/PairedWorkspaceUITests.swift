import XCTest

@MainActor
final class PairedWorkspaceUITests: XCTestCase {
    func testNormalAppPairsAndRestartsIntoWorkspace() throws {
        try runJourney(nativeControl: false)
    }

    func testNormalAppPairsAndRunsNativeControl() throws {
        try runJourney(nativeControl: true)
    }

    func testNormalAppReenrollsNativeVideoAfterDesktopSelection() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true)
    }

    func testNormalAppReenrollsNativeVideoAfterAppSelection() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedTarget: "Mac Companion QA Target")
    }

    func testNormalAppReenrollsNativeVideoAfterWindowSelection() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target")
    }

    func testNormalAppRetiresNativeVideoWhenSelectedWindowCloses() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true)
    }

    func testNormalAppRetiresNativeVideoWhenSelectedWindowMoves() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true)
    }

    func testNormalAppRetiresNativeVideoWhenSelectedWindowResizes() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true)
    }

    func testNormalAppRestartsControlAfterSelectedWindowResizes() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true,
                       restartAfterWindowInvalidation: true)
    }

    func testNormalAppNativeBackgroundFencesInputAndRequiresRestart() throws {
        try runJourney(nativeControl: true, background: true)
    }

    func testNormalAppNativeBackgroundAndConnectionRecovery() throws {
        try runJourney(nativeControl: true, background: true, connectionLoss: true)
    }

    private func runJourney(nativeControl: Bool, background: Bool = false,
                            connectionLoss: Bool = false, surfaceReplacement: Bool = false,
                            selectedTarget: String? = nil, selectedWindow: String? = nil,
                            selectedWindowInvalidation: Bool = false,
                            restartAfterWindowInvalidation: Bool = false) throws {
        continueAfterFailure = false
        XCTAssertFalse(selectedWindowInvalidation && selectedWindow == nil)
        XCTAssertFalse(restartAfterWindowInvalidation && !selectedWindowInvalidation)
        let windowTransitions: Int
        if let raw = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_WINDOW_SOAK_TRANSITIONS"] {
            windowTransitions = try XCTUnwrap(Int(raw))
            XCTAssertTrue(selectedWindow != nil && windowTransitions == 20)
        } else {
            windowTransitions = 1
        }
        let holdSeconds: Int
        if let raw = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_NATIVE_HOLD_SECONDS"] {
            holdSeconds = try XCTUnwrap(Int(raw))
            XCTAssertTrue(nativeControl && !background && !connectionLoss
                && !surfaceReplacement && selectedTarget == nil && selectedWindow == nil
                && (holdSeconds == 60 || holdSeconds == 1_800))
        } else {
            holdSeconds = 0
        }
        let sessionCount: Int
        if let raw = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_NATIVE_SESSION_SOAK_COUNT"] {
            sessionCount = try XCTUnwrap(Int(raw))
            XCTAssertTrue(nativeControl && !background && !connectionLoss
                && !surfaceReplacement && sessionCount == 10)
        } else {
            sessionCount = holdSeconds > 0 ? 1 : connectionLoss ? 3 : 2
        }
        let code = try XCTUnwrap(ProcessInfo.processInfo.environment["MACCOMPANION_TEST_PAIRING_CODE"])
        let app = XCUIApplication(bundleIdentifier: "media.jenny.maccompanion.ios")
        defer {
            if app.staticTexts["Compare this code on your Mac"].exists {
                app.buttons["Cancel"].tap()
                _ = app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10)
            }
            app.terminate()
        }
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
        XCTAssertTrue(app.staticTexts["Mac Connected"].waitForExistence(timeout: 30))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Choose Private Routes"].waitForExistence(timeout: 10))
        let picker = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Route Type")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let choice = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Private Network")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Mac Status"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["This iPhone is paired for Observe only. Remote Control must first be allowed on the Mac."].exists)
        app.buttons["Mac Status"].tap()
        XCTAssertTrue(app.buttons["Refresh Status"].waitForExistence(timeout: 10))
        app.buttons["Refresh Status"].tap()
        XCTAssertTrue(app.staticTexts["Live status"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Mac Connected"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Mac Status"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["This iPhone is paired for Observe only. Remote Control must first be allowed on the Mac."].exists)
        app.buttons["Mac Status"].tap()
        XCTAssertTrue(app.buttons["Refresh Status"].waitForExistence(timeout: 10))
        app.buttons["Refresh Status"].tap()
        XCTAssertTrue(app.staticTexts["Live status"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Enter Pairing Code"].exists)
        if nativeControl {
            app.navigationBars["Mac Status"].buttons["Mac"].tap()
            let grant = try NormalConsentBridge.command("journey-grant-control-observe")
            XCTAssertEqual(grant["pairedDevices"] as? Int, 1)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 20))
            var expectedPresentations = 0
            for cycle in 1...sessionCount {
                app.buttons["Request Remote Control"].tap()
                let stop = app.buttons["Stop Remote Control top"]
                XCTAssertTrue(stop.waitForExistence(timeout: 45), app.debugDescription)
                let keyboard = app.buttons["Keyboard"]
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: keyboard)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, app.debugDescription)
                func hostControl() throws -> [String: Any] {
                    try XCTUnwrap(NormalConsentBridge.command("journey-status")["control"] as? [String: Any])
                }
                var control = try hostControl()
                let deadline = Date().addingTimeInterval(45)
                expectedPresentations += 1
                while (control["nativePresentations"] as? Int ?? 0) < expectedPresentations, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.2)
                    control = try hostControl()
                }
                XCTAssertEqual(control["nativePresentations"] as? Int, expectedPresentations,
                    "Each session must present native video and receive host input admission")
                XCTAssertEqual(control["captureActive"] as? Bool, true)
                if surfaceReplacement && cycle == 1 {
                    for transition in 0..<windowTransitions {
                        app.buttons["More"].tap()
                        app.buttons["Choose Surface"].tap()
                        XCTAssertTrue(app.navigationBars["Choose Mac View"].waitForExistence(timeout: 10), app.debugDescription)
                        let chooseSelected = transition.isMultiple(of: 2)
                        if chooseSelected && (selectedTarget != nil || selectedWindow != nil) {
                            let search = app.searchFields["Find an app or window"]
                            XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
                            search.tap()
                            search.typeText(selectedWindow ?? selectedTarget ?? "")
                            let predicate = selectedWindow.map {
                                NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Window ", $0)
                            } ?? NSPredicate(format: "label BEGINSWITH %@", selectedTarget ?? "")
                            let target = app.buttons.matching(predicate).firstMatch
                            XCTAssertTrue(target.waitForExistence(timeout: 5),
                                "Search must find the disposable selected target in the picker inventory")
                            target.tap()
                        } else {
                            app.buttons["Desktop"].tap()
                        }
                        let reenrolled = XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: keyboard)
                        XCTAssertEqual(XCTWaiter.wait(for: [reenrolled], timeout: 45), .completed,
                            "Replacement must wait for fresh native presentation")
                        XCTAssertFalse(app.staticTexts["Remote Control needs to restart"].exists,
                            "A successful surface replacement must not retain restart guidance")
                        expectedPresentations += 1
                        var after = try hostControl()
                        let deadline = Date().addingTimeInterval(45)
                        while (after["nativePresentations"] as? Int ?? 0) < expectedPresentations, Date() < deadline {
                            Thread.sleep(forTimeInterval: 0.2)
                            after = try hostControl()
                        }
                        XCTAssertEqual(after["nativePresentations"] as? Int, expectedPresentations)
                        if selectedWindowInvalidation {
                            let readyToChange = try NormalConsentBridge.command("journey-window-change-ready")
                            XCTAssertEqual((readyToChange["control"] as? [String: Any])?["nativePresentations"] as? Int,
                                expectedPresentations)
                            let failedSession = app.buttons["Stop Failed Session"]
                            XCTAssertTrue(failedSession.waitForExistence(timeout: 45),
                                "The client must show a recoverable failed session after Window geometry or visibility changes: \(app.debugDescription)")
                            XCTAssertFalse(keyboard.exists && keyboard.isEnabled,
                                "A changed Window must not retain Keyboard authority")
                            failedSession.tap()
                            let request = app.buttons["Request Remote Control"]
                            XCTAssertTrue(request.waitForExistence(timeout: 30),
                                "Stopping the failed session must allow a new Control request: \(app.debugDescription)")
                            if restartAfterWindowInvalidation {
                                // The disposable Mac test menu is replaced after its
                                // local XPC generation is invalidated. The normal app
                                // has its own recovery owner; this delay is test-only.
                                Thread.sleep(forTimeInterval: 5)
                                request.tap()
                                XCTAssertTrue(stop.waitForExistence(timeout: 45),
                                    "Control must restart after the changed Window session is stopped: \(app.debugDescription)")
                                let restarted = XCTNSPredicateExpectation(
                                    predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: keyboard)
                                XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 45), .completed,
                                    "A fresh native frame must enable input after restart: \(app.debugDescription)")
                                // The replacement Mac test menu has a new loopback
                                // port. The host runner checks its frame count;
                                // this process checks that Control stays usable.
                                if ProcessInfo.processInfo.environment["MACCOMPANION_TEST_RAPID_STOP_AFTER_RESTART"] != "1" {
                                    Thread.sleep(forTimeInterval: 5)
                                    XCTAssertTrue(keyboard.exists && keyboard.isEnabled,
                                        "The restarted Control screen must remain usable before Stop")
                                }
                                app.buttons["Stop Remote Control bottom"].tap()
                                XCTAssertTrue(request.waitForExistence(timeout: 30),
                                    "The restarted Control session must Stop cleanly: \(app.debugDescription)")
                            }
                            return
                        }
                        XCTAssertEqual(after["captureActive"] as? Bool, true)
                        if windowTransitions > 1 {
                            let previous = try XCTUnwrap(after["inputEvents"] as? Int)
                            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                            var delivered = try hostControl()
                            let inputDeadline = Date().addingTimeInterval(10)
                            while (delivered["inputEvents"] as? Int ?? 0) <= previous, Date() < inputDeadline {
                                Thread.sleep(forTimeInterval: 0.2)
                                delivered = try hostControl()
                            }
                            XCTAssertGreaterThan(try XCTUnwrap(delivered["inputEvents"] as? Int), previous,
                                "Every new surface must deliver input only after fresh presentation")
                        }
                    }
                }
                let beforeInput = try XCTUnwrap(control["inputEvents"] as? Int)
                keyboard.tap()
                XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                app.keys["a"].tap()
                app.buttons["Hide Keyboard"].tap()
                var delivered = try hostControl()
                let inputDeadline = Date().addingTimeInterval(10)
                while (delivered["inputEvents"] as? Int ?? 0) <= beforeInput, Date() < inputDeadline {
                    Thread.sleep(forTimeInterval: 0.2)
                    delivered = try hostControl()
                }
                XCTAssertGreaterThan(try XCTUnwrap(delivered["inputEvents"] as? Int), beforeInput)
                func deliversInput(_ action: () -> Void) throws {
                    let previous = try XCTUnwrap(hostControl()["inputEvents"] as? Int)
                    action()
                    var current = try hostControl()
                    let deadline = Date().addingTimeInterval(10)
                    while (current["inputEvents"] as? Int ?? 0) <= previous, Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.2)
                        current = try hostControl()
                    }
                    XCTAssertGreaterThan(try XCTUnwrap(current["inputEvents"] as? Int), previous)
                }
                try deliversInput {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                if cycle == 1 {
                    let shortcuts = app.buttons["All remote shortcuts"]
                    XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
                    for _ in 0..<3 where !shortcuts.isHittable {
                        app.scrollViews.containing(.button, identifier: "All remote shortcuts").firstMatch.swipeLeft()
                    }
                    shortcuts.tap()
                    app.buttons["shift"].tap()
                    try deliversInput {
                        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                            "Copy", "Remote shortcut copy")).element.tap()
                    }
                    try deliversInput { app.buttons["tab"].tap() }
                    app.buttons["Done"].tap()
                    XCTAssertTrue(app.buttons["Remote Keyboard"].isHittable,
                        "The Control toolbar must keep its keyboard button touchable")
                    XCTAssertTrue(app.buttons["Stop Remote Control bottom"].isHittable,
                        "The Control toolbar must keep its Stop button touchable")
                }
                if holdSeconds > 0 {
                    let started = Date()
                    var previousRecords = try XCTUnwrap(hostControl()["mediaRecords"] as? Int)
                    let checkpointSeconds = holdSeconds == 60 ? 10 : 60
                    for _ in 0..<(holdSeconds / checkpointSeconds) {
                        Thread.sleep(forTimeInterval: TimeInterval(checkpointSeconds))
                        let current = try hostControl()
                        XCTAssertEqual(current["captureActive"] as? Bool, true)
                        XCTAssertEqual(current["nativePresentations"] as? Int, 1)
                        XCTAssertTrue(keyboard.exists && keyboard.isEnabled,
                            "The normal app must keep current input available throughout Control")
                        let records = try XCTUnwrap(current["mediaRecords"] as? Int)
                        XCTAssertGreaterThan(records, previousRecords,
                            "The managed host must keep producing video during the session")
                        previousRecords = records
                        try deliversInput {
                            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        }
                    }
                    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), Double(holdSeconds))
                }
                if background && cycle == 1 {
                    keyboard.tap()
                    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                    XCUIDevice.shared.press(.home)
                    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
                        || app.state == .runningBackgroundSuspended)
                    Thread.sleep(forTimeInterval: 2)
                    app.activate()
                    XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
                    XCTAssertFalse(app.keyboards.element.exists)
                    XCTAssertTrue(app.descendants(matching: .any)["Remote Control restart required"].firstMatch
                        .waitForExistence(timeout: 10), app.debugDescription)
                    XCTAssertFalse(keyboard.exists && keyboard.isEnabled,
                        "Retired video must not offer keyboard input on foreground return")
                    let fenced = try hostControl()
                    let previous = try XCTUnwrap(fenced["inputEvents"] as? Int)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    Thread.sleep(forTimeInterval: 1)
                    let denied = try hostControl()
                    XCTAssertEqual(denied["inputEvents"] as? Int, previous,
                        "Foreground return must not restore input from the retired native generation")
                    XCTAssertEqual(denied["nativePresentations"] as? Int, cycle,
                        "Foreground return must not automatically enroll another native session")
                }
                if connectionLoss && cycle == 2 {
                    keyboard.tap()
                    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                    _ = try NormalConsentBridge.command("journey-network-cut")
                    XCTAssertTrue(app.buttons["Reconnect"].waitForExistence(timeout: 30), app.debugDescription)
                    XCTAssertFalse(app.keyboards.element.exists)
                    XCTAssertFalse(stop.exists)
                    XCTAssertFalse(app.buttons["Enter Pairing Code"].exists)
                    var closed = try hostControl()
                    let deadline = Date().addingTimeInterval(10)
                    while closed["runtimeIdle"] as? Bool != true, Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.2)
                        closed = try hostControl()
                    }
                    XCTAssertEqual(closed["captureActive"] as? Bool, false)
                    XCTAssertEqual(closed["runtimeIdle"] as? Bool, true)
                    XCTAssertEqual(closed["queuedMediaRecords"] as? Int, 0)
                    let previous = try XCTUnwrap(closed["inputEvents"] as? Int)
                    Thread.sleep(forTimeInterval: 1)
                    XCTAssertEqual(try hostControl()["inputEvents"] as? Int, previous)
                    _ = try NormalConsentBridge.command("journey-network-restore")
                    app.buttons["Reconnect"].tap()
                    XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 30), app.debugDescription)
                    XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 10))
                    XCTAssertFalse(stop.exists)
                    XCTAssertFalse(app.buttons["Enter Pairing Code"].exists)
                    let recovered = try hostControl()
                    XCTAssertEqual(recovered["nativePresentations"] as? Int, cycle,
                        "Connection recovery must not automatically restart native Control")
                    XCTAssertEqual(recovered["captureActive"] as? Bool, false)
                    app.buttons["Mac Status"].tap()
                    app.buttons["Refresh Status"].tap()
                    XCTAssertTrue(app.staticTexts["Live status"].waitForExistence(timeout: 20))
                    app.navigationBars["Mac Status"].buttons["Mac"].tap()
                    continue
                }
                stop.tap()
                XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.buttons["Stop Remote Control top"].exists)
                let ended = try NormalConsentBridge.command("journey-status")
                let clean = try XCTUnwrap(ended["control"] as? [String: Any])
                XCTAssertEqual(clean["captureActive"] as? Bool, false)
                XCTAssertEqual(clean["runtimeIdle"] as? Bool, true)
                XCTAssertEqual(clean["queuedMediaRecords"] as? Int, 0)
                if sessionCount == 10 {
                    // Back-to-back status reads after Stop must see the same
                    // drained generation while the previous socket closes.
                    for _ in 0..<12 {
                        let status = try NormalConsentBridge.command("journey-status")
                        let current = try XCTUnwrap(status["control"] as? [String: Any])
                        XCTAssertEqual(current["captureActive"] as? Bool, false)
                        XCTAssertEqual(current["runtimeIdle"] as? Bool, true)
                        XCTAssertEqual(current["queuedMediaRecords"] as? Int, 0)
                    }
                }
                XCTAssertTrue(app.staticTexts["Authenticated connection"].exists)
                app.buttons["Mac Status"].tap()
                app.buttons["Refresh Status"].tap()
                XCTAssertTrue(app.staticTexts["Live status"].waitForExistence(timeout: 20))
                app.navigationBars["Mac Status"].buttons["Mac"].tap()
            }
        }
    }
}
