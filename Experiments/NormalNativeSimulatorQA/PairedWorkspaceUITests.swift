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

    func testNormalAppRecoversDesktopWhenPickerWindowDisappears() throws {
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

    func testNormalAppReselectsWindowAfterResizeRecovery() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true, automaticWindowRecovery: true, reselectWindowAfterRecovery: true)
    }

    func testNormalAppReturnsToDesktopAfterSelectedWindowCloses() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true, automaticWindowRecovery: true)
    }

    func testNormalAppReselectsWindowAfterMoveRecovery() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true, automaticWindowRecovery: true, reselectWindowAfterRecovery: true)
    }

    func testNormalAppRestartsControlAfterSelectedWindowResizes() throws {
        try runJourney(nativeControl: true, surfaceReplacement: true,
                       selectedWindow: "Mac Companion QA Target",
                       selectedWindowInvalidation: true,
                       restartAfterWindowInvalidation: true)
    }

    func testNormalAppNativeBackgroundFencesInputAndFreshlyResumes() throws {
        try runJourney(nativeControl: true, background: true)
    }

    func testNormalAppNativeBackgroundAndConnectionRecovery() throws {
        try runJourney(nativeControl: true, background: true, connectionLoss: true)
    }

    private func runJourney(nativeControl: Bool, background: Bool = false,
                            connectionLoss: Bool = false, surfaceReplacement: Bool = false,
                            selectedTarget: String? = nil, selectedWindow: String? = nil,
                            selectedWindowInvalidation: Bool = false,
                            restartAfterWindowInvalidation: Bool = false, automaticWindowRecovery: Bool = false,
                            reselectWindowAfterRecovery: Bool = false) throws {
        continueAfterFailure = false
        XCTAssertFalse(selectedWindowInvalidation && selectedWindow == nil)
        XCTAssertFalse(restartAfterWindowInvalidation && !selectedWindowInvalidation)
        XCTAssertFalse(reselectWindowAfterRecovery && !automaticWindowRecovery)
        let windowTransitions: Int
        if let raw = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_WINDOW_SOAK_TRANSITIONS"] {
            windowTransitions = try XCTUnwrap(Int(raw))
            XCTAssertTrue(selectedWindow != nil && (2...200).contains(windowTransitions) && windowTransitions % 2 == 0)
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
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Mac Status"].exists)
        XCTAssertFalse(app.buttons["Approved Actions"].exists)
        XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Enter Pairing Code"].exists)
        app.buttons["my-macs"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Manage Mac 1"].tap()
        app.buttons["Rename"].tap()
        let name = app.textFields["mac-rename-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Studio Mac")
        app.navigationBars["Rename Mac"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["pair-another-mac"].tap()
        XCTAssertTrue(app.buttons["Enter Pairing Code"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["My Macs"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-mac-")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 30))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Studio Mac"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 30))
        if nativeControl {
            let grant = try NormalConsentBridge.command("journey-admit-paired-control")
            XCTAssertEqual(grant["pairedDevices"] as? Int, 1)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["Authenticated connection"].waitForExistence(timeout: 20))
            var expectedPresentations = 0
            for cycle in 1...sessionCount {
                app.buttons["Request Remote Control"].tap()
                let stop = app.buttons["Stop Remote Control"]
                XCTAssertTrue(stop.waitForExistence(timeout: 45), app.debugDescription)
                XCTAssertEqual(app.buttons.matching(identifier: "Stop Remote Control").count, 1,
                    "The session must expose one Close/Stop control")
                let keyboard = app.buttons["Remote Keyboard"]
                let admittedKey = app.buttons["Remote key escape"]
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
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
                    // A local view picker must not retire an admitted stream.
                    // Keep it open past the native visibility monitor's tick.
                    Thread.sleep(forTimeInterval: 1)
                    app.buttons["More"].tap()
                    app.buttons["Shared Display"].tap()
                    XCTAssertTrue(app.navigationBars["Choose Display"].waitForExistence(timeout: 10), app.debugDescription)
                    Thread.sleep(forTimeInterval: 1)
                    let layout = app.otherElements["Display Layout"]
                    XCTAssertTrue(layout.exists, app.debugDescription)
                    let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Display Map Tile "))
                    XCTAssertGreaterThan(tiles.count, 0)
                    for tile in tiles.allElementsBoundByIndex {
                        XCTAssertTrue(layout.frame.insetBy(dx: -1, dy: -1).contains(tile.frame),
                            "Every display tile must fit inside the map canvas")
                    }
                    let displayShot = XCTAttachment(screenshot: app.screenshot())
                    displayShot.name = "Contained display picker"
                    displayShot.lifetime = .keepAlways
                    add(displayShot)
                    XCTAssertTrue(app.buttons["Done"].exists,
                        "Opening the display picker must not trigger video retirement and dismiss it")
                    app.buttons["Done"].tap()
                    XCTAssertTrue(keyboard.waitForExistence(timeout: 10), app.debugDescription)
                    XCTAssertFalse(app.descendants(matching: .any)["Remote Control restart required"].firstMatch.exists,
                        "Dismissing a local picker must preserve the current native owner")
                    XCTAssertEqual(try hostControl()["nativePresentations"] as? Int, expectedPresentations,
                        "A local picker must not require another native enrollment")
                    keyboard.tap()
                    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                    XCTAssertFalse(app.alerts["Keyboard input unavailable"].exists)
                    // Switch away and back so subsequent App/Window coverage
                    // keeps using its original physical display.
                    for _ in 0..<2 {
                        app.buttons["More"].tap()
                        app.buttons["Shared Display"].tap()
                        let otherDisplay = app.buttons.matching(NSPredicate(
                            format: "identifier BEGINSWITH %@ AND value == %@",
                            "Shared Display ", "Available")).firstMatch
                        XCTAssertTrue(otherDisplay.waitForExistence(timeout: 10), app.debugDescription)
                        otherDisplay.tap()
                        expectedPresentations += 1
                        let displayDeadline = Date().addingTimeInterval(45)
                        while (try hostControl()["nativePresentations"] as? Int ?? 0) < expectedPresentations,
                              Date() < displayDeadline {
                            Thread.sleep(forTimeInterval: 0.2)
                        }
                        XCTAssertEqual(try hostControl()["nativePresentations"] as? Int, expectedPresentations,
                            "Changing Shared Display must present the replacement while the picker remains open")
                        XCTAssertTrue(app.buttons["Done"].exists,
                            "A successful display replacement must preserve the picker until dismissed")
                        app.buttons["Done"].tap()
                        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), app.debugDescription)
                        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10),
                            "Keyboard must return after a display picker switch without another keyboard tap")
                        Thread.sleep(forTimeInterval: 1)
                        XCTAssertFalse(app.descendants(matching: .any)["Remote Control restart required"].firstMatch.exists,
                            "Changing Shared Display must not retire the replacement native owner")
                    }
                    for transition in 0..<windowTransitions {
                        app.buttons["More"].tap()
                        let chooseSurface = app.buttons["Choose Surface"]
                        XCTAssertTrue(chooseSurface.waitForExistence(timeout: 5), app.debugDescription)
                        XCTAssertTrue(chooseSurface.isEnabled && chooseSurface.isHittable,
                            "The view picker action must remain reachable with the keyboard open")
                        chooseSurface.tap()
                        XCTAssertTrue(app.navigationBars["Choose Mac View"].waitForExistence(timeout: 10), app.debugDescription)
                        let chooseSelected = transition.isMultiple(of: 2)
                        if chooseSelected && (selectedTarget != nil || selectedWindow != nil) {
                            let search = app.searchFields["Find an app or window"]
                            XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
                            search.tap()
                            search.typeText(selectedWindow ?? selectedTarget ?? "")
                            let predicate = selectedWindow.map {
                                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "Surface Window ", $0)
                            } ?? NSPredicate(format: "label BEGINSWITH %@", selectedTarget ?? "")
                            let target = app.buttons.matching(predicate).firstMatch
                            XCTAssertTrue(target.waitForExistence(timeout: 5),
                                "Search must find the disposable selected target in the picker inventory")
                            if let path = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_PICKER_WINDOW_CLOSE_PATH"] {
                                XCTAssertTrue(path.hasPrefix("/private/tmp/maccompanion-"))
                                try "close\n".write(toFile: path, atomically: true, encoding: .utf8)
                                let deadline = Date().addingTimeInterval(5)
                                while !FileManager.default.fileExists(atPath: path + ".done"), Date() < deadline {
                                    Thread.sleep(forTimeInterval: 0.1)
                                }
                                XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".done"))
                            }
                            target.tap()
                        } else {
                            app.buttons["Desktop"].tap()
                        }
                        let reenrolled = XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
                        XCTAssertEqual(XCTWaiter.wait(for: [reenrolled], timeout: 45), .completed,
                            "Replacement must wait for fresh native presentation")
                        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10),
                            "Keyboard must return after a Window picker switch")
                        XCTAssertFalse(app.alerts["Keyboard input unavailable"].exists)
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
                            if reselectWindowAfterRecovery {
                                app.buttons["More"].tap()
                                app.buttons["Choose Surface"].tap()
                                XCTAssertTrue(app.navigationBars["Choose Mac View"].waitForExistence(timeout: 10),
                                    app.debugDescription)
                                let search = app.searchFields["Find an app or window"]
                                XCTAssertTrue(search.waitForExistence(timeout: 5))
                                search.tap()
                                search.typeText(try XCTUnwrap(selectedWindow))
                            }
                            let readyToChange = try NormalConsentBridge.command("journey-window-change-ready")
                            XCTAssertEqual((readyToChange["control"] as? [String: Any])?["nativePresentations"] as? Int,
                                expectedPresentations)
                            if automaticWindowRecovery {
                                if reselectWindowAfterRecovery {
                                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Surface Picker Busy").firstMatch
                                        .waitForExistence(timeout: 10),
                                        "Recovery must remain visible inside an already open picker")
                                    XCTAssertFalse(app.buttons["Desktop"].isEnabled,
                                        "A recovering picker must not advertise ignored selections as available")
                                    // Active native search replaces the sheet's
                                    // Cancel toolbar item with its local Close.
                                    let cancel = app.buttons["Cancel"].exists
                                        ? app.buttons["Cancel"] : app.buttons["Close"]
                                    XCTAssertTrue(cancel.exists && cancel.isEnabled,
                                        "Recovery must leave local picker/search cancellation available")
                                }
                                XCTAssertTrue(app.staticTexts["Showing Desktop. Choose the window again when ready."]
                                    .waitForExistence(timeout: 45), app.debugDescription)
                                if !reselectWindowAfterRecovery {
                                    let recovered = XCTNSPredicateExpectation(
                                        predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
                                    XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 45), .completed,
                                        "Selected-window loss must obtain a fresh Desktop presentation without another Control request")
                                    XCTAssertTrue(stop.exists)
                                }
                                XCTAssertFalse(app.buttons["Stop Failed Session"].exists)
                                XCTAssertFalse(app.staticTexts["Remote Control needs to restart"].exists)
                                expectedPresentations += 1
                                after = try hostControl()
                                XCTAssertEqual(after["nativePresentations"] as? Int, expectedPresentations)
                                if reselectWindowAfterRecovery {
                                    // The first ordinary selection after recovery must
                                    // reuse the fresh Desktop host, receive its own
                                    // presentation and continue delivering frames.
                                    XCTAssertTrue(app.navigationBars["Choose Mac View"].exists,
                                        "The picker must remain open through bounded recovery")
                                    let target = app.buttons.matching(NSPredicate(
                                        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                        "Surface Window ", try XCTUnwrap(selectedWindow))).firstMatch
                                    XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
                                    let selectable = XCTNSPredicateExpectation(
                                        predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: target)
                                    XCTAssertEqual(XCTWaiter.wait(for: [selectable], timeout: 5), .completed,
                                        "Recovered picker choices must become selectable again")
                                    target.tap()
                                    let reselected = XCTNSPredicateExpectation(
                                        predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
                                    XCTAssertEqual(XCTWaiter.wait(for: [reselected], timeout: 45), .completed,
                                        "Window selection immediately after Desktop recovery must present fresh video and input")
                                    expectedPresentations += 1
                                    after = try hostControl()
                                    XCTAssertEqual(after["nativePresentations"] as? Int, expectedPresentations)
                                    let previousMedia = try XCTUnwrap(after["mediaRecords"] as? Int)
                                    let mediaDeadline = Date().addingTimeInterval(5)
                                    while (after["mediaRecords"] as? Int ?? 0) <= previousMedia, Date() < mediaDeadline {
                                        Thread.sleep(forTimeInterval: 0.2)
                                        after = try hostControl()
                                    }
                                    XCTAssertGreaterThan(try XCTUnwrap(after["mediaRecords"] as? Int), previousMedia,
                                        "The reselected Window must keep producing video after recovery")
                                    XCTAssertTrue(stop.exists)
                                    XCTAssertFalse(app.buttons["Stop Failed Session"].exists)
                                    XCTAssertFalse(app.staticTexts["Remote Control needs to restart"].exists)
                                }
                            } else {
                            let failedSession = app.buttons["Stop Failed Session"]
                            XCTAssertTrue(failedSession.waitForExistence(timeout: 45),
                                "The client must show a recoverable failed session after Window geometry or visibility changes: \(app.debugDescription)")
                            XCTAssertFalse(admittedKey.exists && admittedKey.isEnabled,
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
                                    predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
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
                                app.buttons["Stop Remote Control"].tap()
                                XCTAssertTrue(request.waitForExistence(timeout: 30),
                                    "The restarted Control session must Stop cleanly: \(app.debugDescription)")
                            }
                            return
                            }
                        }
                        XCTAssertEqual(after["captureActive"] as? Bool, true)
                        if windowTransitions > 1 {
                            let mediaBefore = try XCTUnwrap(after["mediaRecords"] as? Int)
                            let mediaDeadline = Date().addingTimeInterval(5)
                            var advancing = try hostControl()
                            while (advancing["mediaRecords"] as? Int ?? 0) <= mediaBefore, Date() < mediaDeadline {
                                Thread.sleep(forTimeInterval: 0.2)
                                advancing = try hostControl()
                            }
                            XCTAssertGreaterThan(try XCTUnwrap(advancing["mediaRecords"] as? Int), mediaBefore,
                                "Every new surface must keep producing video after its fresh presentation")
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
                if app.keyboards.element.exists { app.buttons["Hide Keyboard"].tap() }
                keyboard.tap()
                XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                app.keys["a"].tap()
                XCTAssertTrue(stop.isHittable, "The single Close/Stop must remain available with the keyboard open")
                let bar = app.otherElements["Remote Session Bar"]
                XCTAssertTrue(bar.exists, app.debugDescription)
                XCTAssertLessThanOrEqual(bar.frame.maxY, app.keyboards.element.frame.minY + 2,
                    "The compact bar must remain above the system keyboard")
                let command = app.buttons["Remote modifier command"]
                command.tap()
                XCTAssertEqual(command.value as? String, "Armed for next key")
                app.keys["a"].tap()
                XCTAssertEqual(command.value as? String, "Off", "Modifier selection must clear after a software-keyboard chord")
                let keyboardShot = XCTAttachment(screenshot: app.screenshot())
                keyboardShot.name = "Native keyboard and modifiers"
                keyboardShot.lifetime = .keepAlways
                add(keyboardShot)
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
                    app.buttons["More"].tap()
                    let shortcuts = app.buttons["All remote shortcuts"]
                    XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
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
                    XCTAssertTrue(app.buttons["Stop Remote Control"].isHittable,
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
                    for entry in 0..<3 {
                        if entry == 2 {
                            _ = try NormalConsentBridge.command("journey-native-hold-next-surface")
                            app.buttons["More"].tap()
                            app.buttons["Choose Surface"].tap()
                            XCTAssertTrue(app.navigationBars["Choose Mac View"].waitForExistence(timeout: 5))
                            app.buttons["Desktop"].tap()
                            _ = try NormalConsentBridge.command("journey-native-surface-held")
                        } else {
                            keyboard.tap()
                            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
                        }
                        XCUIDevice.shared.press(.home)
                        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
                            || app.state == .runningBackgroundSuspended)
                        if entry == 2 {
                            _ = try NormalConsentBridge.command("journey-native-release-surface")
                        }
                        Thread.sleep(forTimeInterval: 1)
                        let entered = try hostControl()
                        let previousInput = try XCTUnwrap(entered["inputEvents"] as? Int)
                        Thread.sleep(forTimeInterval: 1)
                        let fenced = try hostControl()
                        XCTAssertEqual(fenced["inputEvents"] as? Int, previousInput,
                            "Background retirement must not emit or replay remote input")
                        XCTAssertEqual(fenced["nativePresentations"] as? Int, expectedPresentations,
                            "No native enrollment may present while backgrounded")
                        app.activate()
                        XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
                        XCTAssertFalse(app.keyboards.element.exists)
                        let resumed = XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "exists == 1 AND enabled == 1"), object: admittedKey)
                        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 45), .completed,
                            "Short background return must obtain fresh native presentation under the same Control approval")
                        expectedPresentations += 1
                        let after = try hostControl()
                        XCTAssertEqual(after["nativePresentations"] as? Int, expectedPresentations)
                        XCTAssertEqual(after["captureActive"] as? Bool, true)
                        XCTAssertFalse(app.descendants(matching: .any)["Remote Control restart required"].firstMatch.exists)
                        try deliversInput {
                            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        }
                    }
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
                    XCTAssertEqual(recovered["nativePresentations"] as? Int, expectedPresentations,
                        "Connection recovery must not automatically restart native Control")
                    XCTAssertEqual(recovered["captureActive"] as? Bool, false)
                    XCTAssertFalse(app.buttons["Mac Status"].exists)
                    continue
                }
                stop.tap()
                XCTAssertTrue(app.buttons["Request Remote Control"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.buttons["Stop Remote Control"].exists)
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
                XCTAssertFalse(app.buttons["Mac Status"].exists)
            }
        }
    }
}
