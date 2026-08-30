import XCTest

/// Opt-in signed-Agent suite. The legacy full suite explicitly selects its
/// original class; this class requires the signed administration bridge.
final class SignedAgentJourneyUITests: XCTestCase {
    @MainActor
    func testSignedAgentPairObserveActControlAndClientRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--authenticated-journey", "--journey-case", UUID().uuidString]
        app.launch()
        func label(_ id: String, _ value: String, timeout: TimeInterval = 20) {
            let item = app.staticTexts[id]
            XCTAssertTrue(item.waitForExistence(timeout: 10))
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: item)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
        }
        func observe() {
            let previous = app.staticTexts["Journey verified observation"].label
            app.buttons["Journey observe"].tap()
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@", previous, "None"),
                object: app.staticTexts["Journey verified observation"])
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        }
        label("Journey phase", "Unpaired")
        app.buttons["Journey pair"].tap()
        label("Journey connection", "Connected")
        label("Journey saved", "1")
        observe()
        app.buttons["Approved Actions"].tap()
        if app.buttons["Reload"].waitForExistence(timeout: 3) { app.buttons["Reload"].tap() }
        XCTAssertTrue(app.staticTexts["No Approved Actions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Grant Act"].isHittable)
        app.buttons["Grant Act"].tap()
        label("Signed administration", "Completed")
        // Reload actual persisted client custody/routes through a new process.
        app.terminate(); app.launch()
        label("Journey connection", "Connected")
        label("Journey saved", "1")
        observe()
        app.buttons["Approved Actions"].tap()
        if app.buttons["Reload"].waitForExistence(timeout: 3) { app.buttons["Reload"].tap() }
        XCTAssertTrue(app.buttons["Set audio mute"].waitForExistence(timeout: 10))
        app.buttons["Set audio mute"].tap()
        let run = app.buttons["Run Approved Action"]
        for _ in 0..<4 where !run.isHittable { app.swipeUp() }
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        let result = app.descendants(matching: .any).matching(identifier: "Verified result $.muted").firstMatch
        for _ in 0..<5 where !result.isHittable { app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("No"))
        app.buttons["Done"].tap()
        // Running an action returns to the Approved Actions list, not the
        // primary workspace. Control is intentionally requested from that
        // workspace, so make the navigation transition explicit rather than
        // searching (and swiping) on the wrong screen.
        let approvedActions = app.navigationBars["Approved Actions"]
        XCTAssertTrue(approvedActions.waitForExistence(timeout: 5))
        let backToWorkspace = approvedActions.buttons.firstMatch
        XCTAssertTrue(backToWorkspace.exists && backToWorkspace.isHittable)
        backToWorkspace.tap()
        XCTAssertTrue(app.buttons["Approved Actions"].waitForExistence(timeout: 5))
        observe()
        let controlPrimary = app.staticTexts["Journey primary"].label
        XCTAssertTrue(app.buttons["Grant Control"].isHittable)
        app.buttons["Grant Control"].tap()
        let replacement = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@ AND label != %@", controlPrimary, "None"),
            object: app.staticTexts["Journey primary"])
        XCTAssertEqual(XCTWaiter.wait(for: [replacement], timeout: 20), .completed)
        label("Journey connection", "Connected")
        let request = app.buttons["Request Remote Control"]
        for _ in 0..<5 where !request.isHittable { app.swipeUp() }
        XCTAssertTrue(request.waitForExistence(timeout: 15))
        request.tap()
        label("Journey control", "active")
        let surface = app.otherElements["Journey live surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        assertVisibleSignedVideo(surface)
        let focusedSurfaceAcknowledged = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (Int(app.staticTexts["Journey surface acknowledgements"].label) ?? 0) >= 2
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [focusedSurfaceAcknowledged], timeout: 10),
            .completed,
            "Signed automatic focus replacement must be acknowledged before input"
        )
        let beforeInput = Int(app.staticTexts["Signed input events"].label) ?? 0
        // The acknowledged adaptive replacement rebuilds the rendered surface;
        // never retain the desktop XCUIElement across that identity change.
        let focusedSurface = app.otherElements["Journey live surface"]
        XCTAssertTrue(focusedSurface.waitForExistence(timeout: 5))
        focusedSurface.tap()
        let input = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Int(app.staticTexts["Signed input events"].label) ?? 0) > beforeInput
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [input], timeout: 10), .completed)

        // Backgrounding must retire the active Control session. Returning to
        // the foreground reconnects Observe, but never restores Control without
        // another explicit request from the user.
        let beforeBackgroundPrimary = app.staticTexts["Journey primary"].label
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
            || app.state == .runningBackgroundSuspended)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        let foregroundPrimary = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label != %@ AND label != %@",
                beforeBackgroundPrimary,
                "None"
            ),
            object: app.staticTexts["Journey primary"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [foregroundPrimary], timeout: 20), .completed)
        label("Journey connection", "Connected")
        label("Journey control", "ready")
        XCTAssertFalse(app.otherElements["Journey live surface"].exists)

        // A real production lifecycle reachability loss must retire the
        // authenticated primary without deleting pairing or restoring Control.
        // Returning online selects a fresh primary and Observe must work before
        // the user explicitly requests a replacement Control session.
        let beforeOfflinePrimary = app.staticTexts["Journey primary"].label
        app.buttons["Signed offline"].tap()
        label("Journey connection", "Disconnected")
        label("Journey saved", "1")
        label("Journey control", "ready")
        XCTAssertFalse(app.otherElements["Journey live surface"].exists)
        app.buttons["Signed online"].tap()
        label("Journey connection", "Connected")
        let onlinePrimary = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label != %@ AND label != %@",
                beforeOfflinePrimary,
                "None"
            ),
            object: app.staticTexts["Journey primary"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [onlinePrimary], timeout: 20), .completed)
        observe()
        label("Journey control", "ready")

        let acknowledgementsBeforeForegroundControl =
            Int(app.staticTexts["Journey surface acknowledgements"].label) ?? 0
        let foregroundRequest = app.buttons["Request Remote Control"]
        XCTAssertTrue(foregroundRequest.waitForExistence(timeout: 10))
        foregroundRequest.tap()
        label("Journey control", "active")
        let foregroundSurface = app.otherElements["Journey live surface"]
        XCTAssertTrue(foregroundSurface.waitForExistence(timeout: 10))
        assertVisibleSignedVideo(foregroundSurface)
        let foregroundFocusAcknowledged = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (Int(app.staticTexts["Journey surface acknowledgements"].label) ?? 0)
                    >= acknowledgementsBeforeForegroundControl + 2
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [foregroundFocusAcknowledged], timeout: 10),
            .completed,
            "Foreground Control must acknowledge desktop and automatic focus before keyboard input"
        )

        // Exercise both shipping keyboard paths across the signed Agent input
        // channel. Each must result in a newly observed host input envelope.
        app.buttons["Keyboard"].tap()
        let editor = app.textViews["Text to send to Mac"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("signed bridge")
        let beforeComposedText = Int(app.staticTexts["Signed input events"].label) ?? 0
        app.buttons["Send composed text"].tap()
        let composedText = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Int(app.staticTexts["Signed input events"].label) ?? 0) > beforeComposedText
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [composedText], timeout: 10), .completed)
        app.buttons["Keyboard"].tap()
        XCTAssertTrue(app.buttons["Use Direct Keyboard"].waitForExistence(timeout: 5))
        app.buttons["Use Direct Keyboard"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        let beforeDirectText = Int(app.staticTexts["Signed input events"].label) ?? 0
        app.typeText("abc ")
        let directText = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Int(app.staticTexts["Signed input events"].label) ?? 0) > beforeDirectText
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [directText], timeout: 10), .completed)

        let activePrimary = app.staticTexts["Journey primary"].label
        let stop = app.buttons["Stop Remote Control top"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(stop.isHittable)
        stop.tap()
        label("Journey capture", "Stopped")
        label("Journey queue", "0")
        label("Journey control", "ready")
        XCTAssertFalse(app.keyboards.element.exists)
        XCTAssertEqual(app.staticTexts["Journey primary"].label, activePrimary,
            "Signed Stop must preserve the Observe primary")
        observe()
        label("Journey failure", "None")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Signed Agent Observe Act Control verified"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertVisibleSignedVideo(_ surface: XCUIElement) {
        let image = surface.screenshot().image
        guard let cgImage = image.cgImage else { XCTFail("Signed video screenshot missing"); return }
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let luminance: Double = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 0, to: buffer.count, by: 4).reduce(0.0) {
                $0 + Double(buffer[$1])
            } / 256
        }
        XCTAssertGreaterThan(luminance, 15, "Signed encoded frames must render, not remain black")
        let attachment = XCTAttachment(screenshot: surface.screenshot())
        attachment.name = "Signed Agent live video pixel assertion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class ClientUIHarnessUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    func testAuthenticatedObserveAcrossReopens() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--authenticated-journey", "--journey-case", UUID().uuidString]
        app.launch()
        wait(for: app.staticTexts["Journey phase"], toHaveLabel: "Unpaired", timeout: 10)
        app.buttons["Reset Host"].tap()
        app.buttons["Journey pair"].tap()
        for _ in 0..<6 {
            waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
            let prior = app.staticTexts["Journey primary"].label
            app.buttons["Reopen Host"].tap()
            waitJourneyPrimaryReplacement(of: prior)
        }
        waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
    }

    @MainActor
    func testAuthenticatedPairingRestartRecoveryAndRevocation() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--authenticated-journey", "--journey-case", UUID().uuidString]
        app.launch()
        wait(for: app.staticTexts["Journey phase"], toHaveLabel: "Unpaired", timeout: 10)
        app.buttons["Reset Host"].tap()
        app.buttons["Journey wrong pin"].tap()
        wait(for: app.staticTexts["Journey phase"], toHaveLabel: "Wrong pin rejected", timeout: 20)
        XCTAssertEqual(app.staticTexts["Journey pin rejection"].label, "Verified")
        XCTAssertEqual(app.staticTexts["Journey saved"].label, "0")
        app.buttons["Journey pair"].tap()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 20)
        wait(for: app.staticTexts["Journey saved"], toHaveLabel: "1", timeout: 5)
        waitJourneyObservation(after: 0)

        // Actual Simulator process termination: no injected paired inventory.
        app.terminate(); app.launch()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 20)
        XCTAssertEqual(app.staticTexts["Journey saved"].label, "1")
        let observations = Int(app.staticTexts["Journey observations"].label) ?? 0
        let beforeReopen = app.staticTexts["Journey primary"].label
        app.buttons["Reopen Host"].tap()
        waitJourneyPrimaryReplacement(of: beforeReopen)
        waitJourneyObservation(after: observations)
        let boot = app.staticTexts["Journey host boot"].label
        XCTAssertNotEqual(boot, "Unknown")
        let beforeRestart = app.staticTexts["Journey primary"].label
        app.buttons["Restart Host"].tap()
        expectation(for: NSPredicate(format: "label != %@ AND label != %@", boot, "Unknown"),
                    evaluatedWith: app.staticTexts["Journey host boot"])
        waitForExpectations(timeout: 20)
        waitJourneyPrimaryReplacement(of: beforeRestart)
        waitJourneyObservation(after: 0)
        app.buttons["Host Off"].tap()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Disconnected", timeout: 12)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.staticTexts["Journey saved"].label, "1")
        app.buttons["Host On"].tap()
        waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
        let beforeGrant = Int(app.staticTexts["Journey authentications"].label) ?? 0
        app.buttons["Grant Control"].tap()
        expectation(for: NSPredicate { [weak self] _, _ in
            (Int(self?.app.staticTexts["Journey authentications"].label ?? "0") ?? 0) > beforeGrant
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        startJourneyControl()
        let surface = app.otherElements["Journey live surface"]
        surface.pinch(withScale: 1.5, velocity: 1)
        surface.pinch(withScale: 0.7, velocity: -1)
        let surfaceAcknowledgements = Int(app.staticTexts["Journey surface acknowledgements"].label) ?? 0
        app.buttons["Focus"].tap()
        // Focus is an asynchronous primary-channel event. Wait for the
        // client's focused-surface acknowledgement, not a guessed delay;
        // before it arrives, the direct keyboard is the correct fallback.
        expectation(for: NSPredicate { [weak self] _, _ in
            (Int(self?.app.staticTexts["Journey surface acknowledgements"].label ?? "0") ?? 0) > surfaceAcknowledgements
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.buttons["Keyboard"].tap()
        let editor = app.textViews["Text to send to Mac"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap(); editor.typeText("hello world")
        app.buttons["Send composed text"].tap()
        XCTAssertTrue(app.buttons["Keyboard"].waitForExistence(timeout: 5))
        app.buttons["Keyboard"].tap()
        XCTAssertTrue(app.buttons["Use Direct Keyboard"].waitForExistence(timeout: 5))
        app.buttons["Use Direct Keyboard"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        app.typeText("abc ")
        wait(for: app.staticTexts["Journey text"], toHaveLabel: "Matched", timeout: 8)
        let beforeStopAuth = Int(app.staticTexts["Journey authentications"].label) ?? 0
        let beforeStopPrimary = app.staticTexts["Journey primary"].label
        stopJourneyControl()
        wait(for: app.staticTexts["Journey capture"], toHaveLabel: "Stopped", timeout: 10)
        XCTAssertFalse(app.otherElements["Journey live surface"].exists)
        XCTAssertFalse(app.keyboards.element.exists)
        XCTAssertEqual(app.staticTexts["Journey connection"].label, "Connected", "Stop must retain Observe primary")
        waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
        XCTAssertEqual(Int(app.staticTexts["Journey authentications"].label), beforeStopAuth,
            "Observe must work on the same authenticated primary, not a reconnect")
        XCTAssertEqual(app.staticTexts["Journey primary"].label, beforeStopPrimary)
        for _ in 0..<3 {
            startJourneyControl()
            let previous = Int(app.staticTexts["Journey observations"].label) ?? 0
            let oldPrimary = app.staticTexts["Journey primary"].label
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended)
            app.activate()
            waitJourneyPrimaryReplacement(of: oldPrimary)
            waitJourneyObservation(after: previous)
            wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 15)
            XCTAssertFalse(app.otherElements["Journey live surface"].exists, "Reconnect must not resume Control")
        }
        startJourneyControl()
        let beforeDrop = Int(app.staticTexts["Journey authentications"].label) ?? 0
        let beforeDropPrimary = app.staticTexts["Journey primary"].label
        app.buttons["Drop"].tap()
        expectation(for: NSPredicate { [weak self] _, _ in
            (Int(self?.app.staticTexts["Journey authentications"].label ?? "0") ?? 0) > beforeDrop
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        waitJourneyPrimaryReplacement(of: beforeDropPrimary)
        waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
        XCTAssertFalse(app.otherElements["Journey live surface"].exists)
        XCTAssertFalse(app.keyboards.element.exists)
        wait(for: app.staticTexts["Journey capture"], toHaveLabel: "Stopped", timeout: 5)
        startJourneyControl()
        let activeBoot = app.staticTexts["Journey host boot"].label
        let activePrimary = app.staticTexts["Journey primary"].label
        app.buttons["Restart Host"].tap()
        expectation(for: NSPredicate(format: "label != %@ AND label != %@", activeBoot, "Unknown"),
                    evaluatedWith: app.staticTexts["Journey host boot"])
        waitForExpectations(timeout: 20)
        waitJourneyPrimaryReplacement(of: activePrimary)
        waitJourneyObservation(after: 0)
        XCTAssertFalse(app.otherElements["Journey live surface"].exists)
        XCTAssertFalse(app.keyboards.element.exists)
        app.buttons["Offline"].tap()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Disconnected", timeout: 10)
        app.buttons["Online"].tap()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 15)
        app.buttons["Revoke"].tap()
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Disconnected", timeout: 15)
        app.terminate(); app.launch()
        wait(for: app.staticTexts["Journey phase"], toHaveLabel: "Saved pairing loaded", timeout: 10)
        Thread.sleep(forTimeInterval: 5)
        XCTAssertEqual(app.staticTexts["Journey connection"].label, "Disconnected")
        XCTAssertEqual(app.staticTexts["Journey saved"].label, "1", "Revocation must not silently erase local pairing or create new keys")
        XCTAssertEqual(app.staticTexts["Journey failure"].label, "None")
    }

    @MainActor
    func testAuthenticatedAgentRenewalFailureRecovery() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--authenticated-journey", "--journey-case", UUID().uuidString]
        app.launch()
        wait(for: app.staticTexts["Journey phase"], toHaveLabel: "Unpaired", timeout: 10)
        app.buttons["Reset Host"].tap()
        app.buttons["Journey pair"].tap()
        waitJourneyObservation(after: 0)
        let prior = app.staticTexts["Journey primary"].label
        app.buttons["Grant Control"].tap()
        waitJourneyPrimaryReplacement(of: prior)
        for (button, fault) in [("Lose Renewal", "reject-renewal"), ("Expire Lease", "expire-renewal")] {
            startJourneyControl()
            let beforeFocus = Int(app.staticTexts["Journey surface acknowledgements"].label) ?? 0
            app.buttons["Focus"].tap()
            expectation(for: NSPredicate { [weak self] _, _ in
                (Int(self?.app.staticTexts["Journey surface acknowledgements"].label ?? "0") ?? 0) > beforeFocus
            }, evaluatedWith: nil)
            waitForExpectations(timeout: 10)
            // Run through two actual production-scheduler deadlines after a
            // surface change. Host counters alone are insufficient: require
            // rendered pixels and no local failure as well.
            expectation(for: NSPredicate { [weak self] _, _ in
                (Int(self?.app.staticTexts["Journey renewals"].label ?? "0") ?? 0) >= 2
            }, evaluatedWith: nil)
            waitForExpectations(timeout: 25)
            assertVisibleVideo(app.otherElements["Journey live surface"])
            XCTAssertEqual(app.staticTexts["Journey renewal failure"].label, "None")
            app.buttons["Keyboard"].tap()
            // The short-lived focused text offer has expired during the two
            // renewal deadlines. The direct keyboard is the safe fallback.
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
            app.buttons[button].tap()
            wait(for: app.staticTexts["Journey renewal failure"], toHaveLabel: fault, timeout: 20)
            wait(for: app.staticTexts["Journey capture"], toHaveLabel: "Stopped", timeout: 8)
            wait(for: app.staticTexts["Journey runtime"], toHaveLabel: "Idle", timeout: 8)
            wait(for: app.staticTexts["Journey queue"], toHaveLabel: "0", timeout: 5)
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["Journey live surface"])
            waitForExpectations(timeout: 10)
            XCTAssertFalse(app.keyboards.element.exists)
            let attempts = app.staticTexts["Journey renewal attempts"].label
            waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
            Thread.sleep(forTimeInterval: 3)
            XCTAssertEqual(app.staticTexts["Journey renewal attempts"].label, attempts, "Ambiguous renewals must not retry")
            XCTAssertFalse(app.otherElements["Journey live surface"].exists, "Recovery must not resume Control")
            revealButton("Stop Failed Session").tap()
            waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
        }
        // Only a fresh explicit request may restart capture after either fault.
        startJourneyControl()
        stopJourneyControl()
        wait(for: app.staticTexts["Journey capture"], toHaveLabel: "Stopped", timeout: 8)
        waitJourneyObservation(after: Int(app.staticTexts["Journey observations"].label) ?? 0)
        XCTAssertEqual(app.staticTexts["Journey failure"].label, "None")
    }

    @MainActor
    private func startJourneyControl() {
        revealButton("Request Remote Control").tap()
        wait(for: app.staticTexts["Journey control"], toHaveLabel: "active", timeout: 20)
        let surface = app.otherElements["Journey live surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        assertVisibleVideo(surface)
    }

    @MainActor
    private func waitJourneyPrimaryReplacement(of prior: String) {
        XCTAssertNotEqual(prior, "None")
        expectation(for: NSPredicate(format: "label != %@ AND label != %@", prior, "None"),
                    evaluatedWith: app.staticTexts["Journey primary"])
        waitForExpectations(timeout: 20)
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 5)
    }

    @MainActor
    private func waitJourneyObservation(after value: Int) {
        wait(for: app.staticTexts["Journey connection"], toHaveLabel: "Connected", timeout: 15)
        let prior = app.staticTexts["Journey verified observation"].label
        app.buttons["Journey observe"].tap()
        let predicate = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            if self.app.staticTexts["Journey failure"].label != "None" { return true }
            let verified = self.app.staticTexts["Journey verified observation"].label
            return (Int(self.app.staticTexts["Journey observations"].label) ?? 0) > value
                && verified != "None" && verified != prior
        }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 20)
        let count = app.staticTexts["Journey observations"].label
        let verified = app.staticTexts["Journey verified observation"].label
        let provider = app.staticTexts["Journey status error"].label
        let failure = app.staticTexts["Journey failure"].label
        XCTAssertEqual(result, .completed,
            "Observe: host count=\(count) expected>\(value), prior=\(prior), verified=\(verified), provider=\(provider), failure=\(failure)")
        XCTAssertEqual(app.staticTexts["Journey failure"].label, "None")
    }

    @MainActor
    private func stopJourneyControl() {
        let bottomStop = app.buttons["Stop"]
        if !app.keyboards.element.exists && bottomStop.exists && bottomStop.isHittable {
            bottomStop.tap()
            return
        }
        let topStop = app.buttons["Stop Remote Control top"]
        XCTAssertTrue(topStop.waitForExistence(timeout: 3))
        XCTAssertTrue(topStop.isHittable)
        topStop.tap()
    }

    @MainActor
    func testRetiredControlCallbacksCannotCorruptReplacement() {
        launchHarness()
        revealButton("Retired Control Callbacks").tap()
        wait(for: app.staticTexts["Retired callback regression"], toHaveLabel: "Passed", timeout: 8)
    }

    @MainActor
    func testIntegratedControlBackgroundRecovery() throws {
        launchIntegratedLab()
        for cycle in 0..<3 {
            startIntegratedControl()
            if cycle == 0 {
                // Cross the production selected-primary liveness interval.
                let media = integratedCount("media")
                Thread.sleep(forTimeInterval: 17)
                XCTAssertGreaterThan(integratedCount("media"), media)
                XCTAssertGreaterThan(integratedCount("status requests"), 0)
                assertVisibleVideo(app.otherElements["Integrated live surface"])
                focusIntegratedSurface()
                app.buttons["Keyboard"].tap()
                let editor = app.textViews["Text to send to Mac"]
                XCTAssertTrue(editor.waitForExistence(timeout: 5))
                editor.tap(); editor.typeText("hello world")
                app.buttons["Send composed text"].tap()
                wait(for: app.staticTexts["Integrated text"], toHaveLabel: "Matched", timeout: 5)
            }
            let selections = integratedCount("selections")
            let retired = integratedCount("retired sessions")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
                || app.state == .runningBackgroundSuspended)
            Thread.sleep(forTimeInterval: 2)
            app.activate()
            waitIntegratedCount("selections", greaterThan: selections)
            waitIntegratedCount("retired sessions", greaterThan: retired)
            assertIntegratedReady()
        }
        startIntegratedControl()
        app.buttons["Lab Offline"].tap()
        assertIntegratedOffline()
    }

    @MainActor
    func testIntegratedControlNetworkLossAndCancelledDial() throws {
        launchIntegratedLab()
        startIntegratedControl()
        focusIntegratedSurface()
        app.buttons["Keyboard"].tap()
        XCTAssertTrue(app.textViews["Text to send to Mac"].waitForExistence(timeout: 5))
        app.buttons["Use Direct Keyboard"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        app.buttons["Lab Offline"].tap()
        assertIntegratedOffline()
        let attempts = integratedCount("attempts")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(integratedCount("attempts"), attempts)
        app.buttons["Lab Online"].tap()
        assertIntegratedReady()
        startIntegratedControl()
        let selections = integratedCount("selections")
        app.buttons["Lab Drop"].tap()
        waitIntegratedCount("selections", greaterThan: selections)
        assertIntegratedReady()
        startIntegratedControl()

        app.buttons["Lab Offline"].tap()
        assertIntegratedOffline()
        let selectedBeforeCancellation = integratedCount("selections")
        let attemptedBeforeCancellation = integratedCount("attempts")
        app.buttons["Lab Slow Online"].tap()
        waitIntegratedCount("attempts", greaterThan: attemptedBeforeCancellation)
        app.buttons["Lab Offline"].tap()
        assertIntegratedOffline()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(integratedCount("selections"), selectedBeforeCancellation,
                       "A cancelled dial must never publish a late primary")
        app.buttons["Lab Online"].tap()
        assertIntegratedReady()
        startIntegratedControl()
        app.buttons["Lab Offline"].tap()
        assertIntegratedOffline()
    }

    @MainActor
    private func launchIntegratedLab() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--integrated-control-lab"]
        app.launch()
        assertIntegratedReady()
    }

    @MainActor
    private func integratedCount(_ name: String) -> Int {
        let label = app.staticTexts["Integrated \(name)"].label
        guard let value = Int(label) else { XCTFail("Missing numeric telemetry: \(name)"); return -1 }
        return value
    }

    @MainActor
    private func waitIntegratedCount(_ name: String, greaterThan value: Int) {
        let element = app.staticTexts["Integrated \(name)"]
        expectation(for: NSPredicate { _, _ in (Int(element.label) ?? -1) > value }, evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func focusIntegratedSurface() {
        let acknowledged = integratedCount("surface acknowledgements")
        app.buttons["Lab Focus"].tap()
        waitIntegratedCount("surface acknowledgements", greaterThan: acknowledged)
    }

    @MainActor
    private func assertIntegratedReady() {
        wait(for: app.staticTexts["Integrated connection"], toHaveLabel: "Connected", timeout: 20)
        wait(for: app.staticTexts["Integrated Control"], toHaveLabel: "ready", timeout: 10)
        wait(for: app.staticTexts["Integrated capture"], toHaveLabel: "Stopped", timeout: 5)
        XCTAssertFalse(app.otherElements["Integrated live surface"].exists,
                       "Recovery must not silently resume remote control")
        XCTAssertFalse(app.keyboards.element.exists)
        XCTAssertEqual(app.staticTexts["Integrated terminal failures"].label, "0")
        XCTAssertEqual(app.staticTexts["Integrated unclean retirements"].label, "0")
        XCTAssertEqual(app.staticTexts["Integrated failure"].label, "None")
    }

    @MainActor
    private func startIntegratedControl() {
        revealButton("Request Remote Control").tap()
        wait(for: app.staticTexts["Integrated Control"], toHaveLabel: "active", timeout: 20)
        let surface = app.otherElements["Integrated live surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        assertVisibleVideo(surface)
    }

    @MainActor
    private func assertIntegratedOffline() {
        wait(for: app.staticTexts["Integrated connection"], toHaveLabel: "Disconnected", timeout: 10)
        wait(for: app.staticTexts["Integrated lifecycle"], toHaveLabel: "Offline", timeout: 10)
        wait(for: app.staticTexts["Integrated runtime"], toHaveLabel: "Idle", timeout: 10)
        wait(for: app.staticTexts["Integrated capture"], toHaveLabel: "Stopped", timeout: 10)
        wait(for: app.staticTexts["Integrated queue"], toHaveLabel: "0", timeout: 10)
        XCTAssertFalse(app.otherElements["Integrated live surface"].exists)
        XCTAssertFalse(app.keyboards.element.exists)
        XCTAssertEqual(app.staticTexts["Integrated terminal failures"].label, "0")
        XCTAssertEqual(app.staticTexts["Integrated unclean retirements"].label, "0")
    }

    @MainActor
    func testNetworkControlLabStreamingZoomKeyboardReconnect() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--network-control-lab"]
        app.launch()
        let state = app.staticTexts["Lab state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        let streamingDeadline = Date().addingTimeInterval(20)
        while state.label != "Streaming", Date() < streamingDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            state.label,
            "Streaming",
            "Lab failed before streaming: \(app.staticTexts["Lab failure"].label)"
        )
        wait(
            for: app.staticTexts["Lab selected display"],
            toHaveLabel: "1",
            timeout: 5
        )
        XCTAssertEqual(app.staticTexts["Lab active display"].label, "1")
        let displayMenu = app.buttons["Shared Display"]
        XCTAssertTrue(displayMenu.waitForExistence(timeout: 5))
        expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: displayMenu
        )
        waitForExpectations(timeout: 5)
        expectation(
            for: NSPredicate { _, _ in
                (Int(
                    self.app.staticTexts["Lab display catalog requests"].label
                ) ?? 0) >= 1
            },
            evaluatedWith: app
        )
        waitForExpectations(timeout: 5)
        displayMenu.tap()
        let secondDisplay = app.buttons["Shared Display 2"]
        XCTAssertTrue(secondDisplay.waitForExistence(timeout: 5))
        secondDisplay.tap()
        wait(
            for: app.staticTexts["Lab active display"],
            toHaveLabel: "2",
            timeout: 10
        )
        wait(
            for: app.staticTexts["Lab selected display"],
            toHaveLabel: "2",
            timeout: 5
        )
        XCTAssertGreaterThanOrEqual(
            Int(app.staticTexts["Lab display catalog requests"].label) ?? 0,
            1
        )
        XCTAssertTrue(["generated", "real-mac-window"].contains(app.staticTexts["Lab source"].label))
        let frame = app.staticTexts["Lab rendered sequence"]
        func advances(by amount: UInt64 = 5, timeout: TimeInterval = 5) {
            let start = UInt64(frame.label) ?? 0
            expectation(for: NSPredicate { _, _ in (UInt64(frame.label) ?? 0) >= start + amount }, evaluatedWith: frame)
            waitForExpectations(timeout: timeout)
            XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
        }
        advances(by: 180, timeout: 20) // real runtime renewals; lab-owned scheduler
        let surface = app.otherElements["Lab live surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        assertVisibleVideo(surface)
        surface.tap()
        wait(for: app.staticTexts["Lab pointer"], toHaveLabel: "Delivered", timeout: 5)
        let eventsBeforeDoubleTap =
            Int(app.staticTexts["Lab input events"].label) ?? 0
        surface.doubleTap()
        wait(
            for: app.staticTexts["Lab input events"],
            toHaveLabel: String(eventsBeforeDoubleTap + 4),
            timeout: 5
        )
        surface.pinch(withScale: 1.5, velocity: 1)
        surface.pinch(withScale: 0.75, velocity: -1)
        advances()
        app.buttons["Lab Local Focus"].tap()
        wait(
            for: app.staticTexts["Lab visual zoom"],
            toHaveLabel: "Focused",
            timeout: 5
        )
        XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
        surface.pinch(withScale: 0.35, velocity: -1)
        wait(
            for: app.staticTexts["Lab visual zoom"],
            toHaveLabel: "Fit",
            timeout: 5
        )
        // The host rotates both authority tokens while publishing identical
        // focus geometry. That refresh must preserve the user's wider view.
        app.buttons["Lab Local Focus"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(
            app.staticTexts["Lab visual zoom"].label,
            "Fit",
            "Focus authority refresh must not undo an explicit pinch-out"
        )
        XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
        XCTAssertEqual(state.label, "Streaming")
        // A genuinely different focus target must also leave the user's
        // session-owned viewport untouched after any manual pinch.
        app.buttons["Lab Local Focus Churn"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.staticTexts["Lab visual zoom"].label, "Fit")
        XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
        XCTAssertEqual(state.label, "Streaming")
        // Automation resumes only through an explicit user action.
        app.buttons["Lab Resume Smart Zoom"].tap()
        wait(
            for: app.staticTexts["Lab visual zoom"],
            toHaveLabel: "Focused",
            timeout: 5
        )
        XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
        let acknowledgementsBeforeStaleFocus =
            Int(app.staticTexts["Lab acknowledgements"].label) ?? 0
        app.buttons["Lab Stale Focus"].tap()
        wait(
            for: app.staticTexts["Lab stale focus fallback recoveries"],
            toHaveLabel: "1",
            timeout: 10
        )
        XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
        XCTAssertEqual(
            Int(app.staticTexts["Lab acknowledgements"].label) ?? 0,
            acknowledgementsBeforeStaleFocus + 1
        )
        XCTAssertEqual(state.label, "Streaming")
        XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
        XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
        for raceIteration in 1...3 {
            app.buttons["Lab Delayed Focus"].tap()
            wait(for: app.staticTexts["Lab surface"], toHaveLabel: "focusedRegion", timeout: 10)
            advances()
            assertVisibleVideo(surface)
            if raceIteration == 1 {
                // Pinching outward past fit leaves Smart Zoom's narrow crop
                // for full Desktop context without ending Control.
                surface.pinch(withScale: 0.65, velocity: -1)
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "desktop",
                    timeout: 10
                )
                advances()
                XCTAssertEqual(state.label, "Streaming")
                XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
                app.buttons["Lab Focus"].tap()
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "focusedRegion",
                    timeout: 10
                )
                advances()
            }
            // A focused -> focused change first pauses the host, before the
            // client can receive the event or send its terminal input reset.
            // Inject one queued key only after the production primary channel
            // has admitted that pause and before Smart Zoom settles.
            app.buttons["Lab Focus Input Race"].tap()
            wait(
                for: app.staticTexts["Lab focus pause race injections"],
                toHaveLabel: String(raceIteration),
                timeout: 5
            )
            advances(by: 30, timeout: 8)
            XCTAssertEqual(app.staticTexts["Lab surface"].label, "focusedRegion")
            XCTAssertEqual(state.label, "Streaming")
            XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
            XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
            if raceIteration == 1 {
                let acknowledgementsBeforeRefreshRecovery =
                    Int(app.staticTexts["Lab acknowledgements"].label) ?? 0
                app.buttons["Lab Desktop Refresh Pause"].tap()
                wait(
                    for: app.staticTexts[
                        "Lab desktop refresh recoveries"
                    ],
                    toHaveLabel: "1",
                    timeout: 4
                )
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "desktop",
                    timeout: 2
                )
                XCTAssertEqual(
                    Int(app.staticTexts["Lab acknowledgements"].label) ?? 0,
                    acknowledgementsBeforeRefreshRecovery + 1
                )
                XCTAssertEqual(state.label, "Streaming")
                XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
                XCTAssertEqual(
                    app.staticTexts["Lab host failure"].label,
                    "None"
                )
                app.buttons["Lab Focus"].tap()
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "focusedRegion",
                    timeout: 10
                )
                advances()
                let acknowledgementsBeforeDisabledRecovery =
                    Int(app.staticTexts["Lab acknowledgements"].label) ?? 0
                app.buttons["Lab Disabled Zoom Pause"].tap()
                wait(
                    for: app.staticTexts["Lab disabled zoom pause recoveries"],
                    toHaveLabel: "1",
                    timeout: 10
                )
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "desktop",
                    timeout: 10
                )
                XCTAssertEqual(
                    Int(app.staticTexts["Lab acknowledgements"].label) ?? 0,
                    acknowledgementsBeforeDisabledRecovery + 1
                )
                XCTAssertEqual(state.label, "Streaming")
                XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
                XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
                app.buttons["Lab Focus"].tap()
                wait(
                    for: app.staticTexts["Lab surface"],
                    toHaveLabel: "focusedRegion",
                    timeout: 10
                )
                advances()
            }
            surface.tap()
            advances()
            app.buttons["Lab Desktop"].tap()
            wait(for: app.staticTexts["Lab surface"], toHaveLabel: "desktop", timeout: 10)
            advances()
        }
        let acknowledgementsBeforeChurn =
            Int(app.staticTexts["Lab acknowledgements"].label) ?? 0
        app.buttons["Lab Focus Churn"].tap()
        wait(
            for: app.staticTexts["Lab surface"],
            toHaveLabel: "focusedRegion",
            timeout: 10
        )
        advances(by: 30, timeout: 8)
        XCTAssertEqual(
            Int(app.staticTexts["Lab acknowledgements"].label) ?? 0,
            acknowledgementsBeforeChurn + 1,
            "Rapid focus churn must coalesce into one acknowledged surface transition"
        )
        XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
        XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
        app.buttons["Lab Desktop"].tap()
        wait(
            for: app.staticTexts["Lab surface"],
            toHaveLabel: "desktop",
            timeout: 10
        )
        advances()
        app.buttons["Lab Focus"].tap()
        wait(for: app.staticTexts["Lab surface"], toHaveLabel: "focusedRegion", timeout: 10)
        app.buttons["Keyboard"].tap()
        let editor = app.textViews["Text to send to Mac"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("hello world")
        app.buttons["Send composed text"].tap()
        wait(for: app.staticTexts["Lab input match"], toHaveLabel: "Matched", timeout: 5)
        advances()
        app.buttons["Keyboard"].tap()
        app.buttons["Use Direct Keyboard"].tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        for key in ["a", "b", "c", "space"] { app.keys[key].tap() }
        wait(for: app.staticTexts["Lab direct input match"], toHaveLabel: "Matched", timeout: 5)
        app.buttons["More"].tap()
        app.buttons["Keys & Shortcuts"].tap()
        XCTAssertFalse(app.keyboards.element.exists)
        app.buttons["return"].tap()
        app.buttons["Done"].tap()
        wait(for: app.staticTexts["Lab physical key"], toHaveLabel: "Delivered", timeout: 5)
        advances()
        app.buttons["Lab Drop"].tap()
        wait(for: state, toHaveLabel: "Disconnected", timeout: 10)
        app.buttons["Lab Reconnect"].tap()
        wait(for: state, toHaveLabel: "Streaming", timeout: 20)
        advances(by: 30)
        assertVisibleVideo(app.otherElements["Lab live surface"])
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live video after reconnect"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Stop"].tap()
        wait(for: state, toHaveLabel: "Disconnected", timeout: 10)
    }

    /// No input or surface change for 90 seconds in each mode. Frame progress,
    /// visible pixels, runtime renewals, and both client/host errors are checked.
    @MainActor
    func testNetworkControlLabIdleSoak() throws {
        launchNetworkLab()
        for kind in ["desktop", "focusedRegion"] {
            if kind == "focusedRegion" {
                app.buttons["Lab Focus"].tap()
                wait(for: app.staticTexts["Lab surface"], toHaveLabel: kind, timeout: 10)
            }
            let startRenewals = Int(app.staticTexts["Lab renewals"].label) ?? 0
            for _ in 0..<9 {
                let sequence = UInt64(app.staticTexts["Lab rendered sequence"].label) ?? 0
                Thread.sleep(forTimeInterval: 10) // app runs in a separate process
                XCTAssertGreaterThan(UInt64(app.staticTexts["Lab rendered sequence"].label) ?? 0, sequence)
                XCTAssertEqual(app.staticTexts["Lab state"].label, "Streaming")
                XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
                XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
                XCTAssertEqual(app.staticTexts["Lab capture"].label, "Running")
                assertVisibleVideo(app.otherElements["Lab live surface"])
            }
            XCTAssertGreaterThanOrEqual((Int(app.staticTexts["Lab renewals"].label) ?? 0) - startRenewals, 20)
        }
        app.buttons["Stop"].tap()
        assertLabCleanup()
    }

    @MainActor
    func testNetworkControlLabRepeatedStopDropReconnect() throws {
        launchNetworkLab()
        for cycle in 0..<5 {
            app.buttons["Lab Focus"].tap()
            wait(for: app.staticTexts["Lab surface"], toHaveLabel: "focusedRegion", timeout: 10)
            waitForLabFrames()
            app.buttons["Keyboard"].tap()
            XCTAssertTrue(app.textViews["Text to send to Mac"].waitForExistence(timeout: 5))
            app.buttons["Use Direct Keyboard"].tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
            // Exercise teardown while the iOS keyboard and a focused surface
            // are owned. Abrupt loss must also clear both before reconnecting.
            let termination = app.buttons[
                cycle.isMultiple(of: 2) ? "Stop Remote Control top" : "Lab Drop"
            ]
            XCTAssertTrue(termination.waitForExistence(timeout: 3))
            XCTAssertTrue(termination.isHittable, "Stop must stay reachable with the keyboard open")
            termination.tap()
            assertLabCleanup()
            app.buttons["Lab Reconnect"].tap()
            wait(for: app.staticTexts["Lab state"], toHaveLabel: "Streaming", timeout: 20)
            waitForLabFrames()
            XCTAssertEqual(app.staticTexts["Lab failure"].label, "None")
            XCTAssertEqual(app.staticTexts["Lab host failure"].label, "None")
            XCTAssertEqual(app.staticTexts["Lab surface"].label, "desktop")
            assertVisibleVideo(app.otherElements["Lab live surface"])
        }
        app.buttons["Stop"].tap()
        assertLabCleanup()
    }

    @MainActor
    private func launchNetworkLab() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--network-control-lab"]
        app.launch()
        wait(for: app.staticTexts["Lab state"], toHaveLabel: "Streaming", timeout: 20)
        waitForLabFrames()
    }

    @MainActor
    private func waitForLabFrames() {
        let frame = app.staticTexts["Lab rendered sequence"]
        let sequence = UInt64(frame.label) ?? 0
        expectation(for: NSPredicate { _, _ in (UInt64(frame.label) ?? 0) > sequence + 5 }, evaluatedWith: frame)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func assertLabCleanup() {
        wait(for: app.staticTexts["Lab state"], toHaveLabel: "Disconnected", timeout: 10)
        XCTAssertFalse(app.otherElements["Lab live surface"].exists)
        XCTAssertFalse(app.keyboards.element.exists)
        // Read host state independently of the retired media/client graph.
        for _ in 0..<10 {
            app.buttons["Lab Cleanup"].tap()
            if app.staticTexts["Lab host session"].label == "Closed",
               app.staticTexts["Lab capture"].label == "Stopped",
               app.staticTexts["Lab runtime"].label == "Idle",
               app.staticTexts["Lab queued media"].label == "0" { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(app.staticTexts["Lab host session"].label, "Closed")
        XCTAssertEqual(app.staticTexts["Lab capture"].label, "Stopped")
        XCTAssertEqual(app.staticTexts["Lab runtime"].label, "Idle")
        XCTAssertEqual(app.staticTexts["Lab queued media"].label, "0")
    }

    @MainActor
    private func assertVisibleVideo(_ surface: XCUIElement) {
        let snapshot = surface.screenshot()
        let attachment = XCTAttachment(screenshot: snapshot)
        attachment.name = "Live video pixel assertion"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let image = snapshot.image.cgImage,
              let center = image.cropping(to: CGRect(x: image.width / 2 - 8, y: image.height / 2 - 8, width: 16, height: 16)) else {
            XCTFail("Video surface screenshot missing"); return
        }
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let luminance: Double = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(center, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 0, to: buffer.count, by: 4).reduce(0.0) { $0 + Double(buffer[$1]) } / 256
        }
        XCTAssertGreaterThan(luminance, 15, "Decoded frames must actually appear, not a black surface")
        if app.staticTexts["Lab source"].label == "real-mac-window" {
            let blue = stride(from: 2, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) } / 256
            XCTAssertGreaterThan(luminance - blue, 12, "The actual tinted Mac test window must be visible, not a placeholder")
        }
    }

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
    private func revealButton(_ label: String) -> XCUIElement {
        let button = app.buttons[label]
        for _ in 0..<4 {
            if button.exists && button.isHittable { return button }
            app.swipeUp()
        }
        XCTFail("Expected accessible button after scrolling: \(label)")
        return button
    }

    @MainActor
    private func wait(
        for element: XCUIElement,
        toHaveLabel label: String,
        timeout: TimeInterval = 2
    ) {
        expectation(
            for: NSPredicate(format: "label == %@", label),
            evaluatedWith: element
        )
        waitForExpectations(timeout: timeout)
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
        XCTAssertTrue(revealButton("Live Control Screen").isHittable)
        XCTAssertTrue(revealButton("Choose Mac View").isHittable)
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
        XCTAssertTrue(revealButton("View Activity").isHittable)
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

        revealButton("Choose Mac View").tap()
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
    func testVerifiedNativeComposerSendsOneBoundedTextEvent() throws {
        launchHarness()
        revealButton("Live Control Screen").tap()
        XCTAssertTrue(
            app.navigationBars["Studio Mac"].waitForExistence(timeout: 2)
        )

        app.buttons["Keyboard"].tap()
        XCTAssertTrue(
            app.navigationBars["Type on Mac"].waitForExistence(timeout: 2)
        )
        let editor = app.textViews["Text to send to Mac"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.tap()
        editor.typeText("hello local")
        app.buttons["Send composed text"].tap()

        XCTAssertTrue(
            app.navigationBars["Studio Mac"].waitForExistence(timeout: 2)
        )
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic text event count"
            ],
            toHaveLabel: "Synthetic text events, 1"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["Synthetic text scalar count"]
                .label,
            "Synthetic text scalars, 11"
        )
    }

    @MainActor
    func testLiveControlKeyboardAndStopAreSemanticallyReachable() throws {
        launchHarness()
        revealButton("Live Control Screen").tap()
        XCTAssertTrue(
            app.navigationBars["Studio Mac"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Synthetic Desktop\nNo network or captured pixels"]
                .exists
        )
        XCTAssertTrue(app.buttons["Keyboard"].isHittable)
        XCTAssertTrue(app.buttons["Keyboard"].isEnabled)
        let appShortcut = app.buttons["Remote shortcut app-next"]
        XCTAssertTrue(appShortcut.isEnabled)
        XCTAssertTrue(appShortcut.isHittable)
        appShortcut.tap()
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic input payload count"
            ],
            toHaveLabel: "Synthetic input payloads, 3"
        )
        XCTAssertTrue(app.buttons["More"].isHittable)
        XCTAssertTrue(app.buttons["Stop"].isHittable)
        let pointerMode = app.buttons["Pointer mode"]
        XCTAssertTrue(pointerMode.exists)
        XCTAssertTrue(pointerMode.isEnabled)
        XCTAssertEqual(pointerMode.label, "Pointer mode, Trackpad")

        app.buttons["Keyboard"].tap()
        XCTAssertTrue(
            app.navigationBars["Type on Mac"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["Use Direct Keyboard"].isHittable)
        app.buttons["Use Direct Keyboard"].tap()
        XCTAssertTrue(
            app.navigationBars["Type on Mac"].waitForNonExistence(timeout: 2)
        )
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.descendants(matching: .any)["Synthetic text event count"]
                .label,
            "Synthetic text events, 0"
        )
        // Exercise the ordinary iOS keyboard through one XCTest text
        // transaction. Per-key XCUIElement taps can each wait a full minute
        // for the system keyboard's cursor/animation idleness on Xcode 27,
        // obscuring the semantic input assertion and exhausting the test's
        // execution allowance.
        app.typeText("hello")
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic word sequence match"
            ],
            toHaveLabel: "Synthetic word sequence, Matched"
        )
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic text event count"
            ],
            toHaveLabel: "Synthetic text events, 5"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["Synthetic text scalar count"]
                .label,
            "Synthetic text scalars, 5"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Synthetic whitespace event count"
            ].label,
            "Synthetic whitespace events, 0"
        )

        app.typeText(" ")
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic word plus space sequence match"
            ],
            toHaveLabel: "Synthetic word plus space sequence, Matched"
        )
        wait(
            for: app.descendants(matching: .any)[
                "Synthetic text event count"
            ],
            toHaveLabel: "Synthetic text events, 6"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["Synthetic text scalar count"]
                .label,
            "Synthetic text scalars, 6"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)[
                "Synthetic whitespace event count"
            ].label,
            "Synthetic whitespace events, 1"
        )

        app.buttons["More"].tap()
        XCTAssertTrue(
            app.buttons["Keys & Shortcuts"].waitForExistence(timeout: 2)
        )
        app.buttons["Keys & Shortcuts"].tap()
        XCTAssertTrue(
            app.navigationBars["Keys & Shortcuts"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.keyboards.element.exists)
        XCTAssertTrue(app.buttons["Use iOS Keyboard"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.keyboards.element.exists)
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

        for round in 2...6 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
                || app.state == .runningBackgroundSuspended)
            app.activate()
            wait(for: app.descendants(matching: .any)["Lifecycle dial rounds"],
                 toHaveLabel: "Synthetic dial rounds, \(round)", timeout: 5)
            XCTAssertEqual(app.descendants(matching: .any)["Lifecycle app state"].label, "App state, Foreground")
            XCTAssertEqual(app.descendants(matching: .any)["Lifecycle terminal failures"].label, "Terminal failures, 0")
            wait(for: app.descendants(matching: .any)["Lifecycle private access"],
                 toHaveLabel: "Private access, Connected through Local Discovery", timeout: 5)
        }
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
