import XCTest

@MainActor final class VisionWindowUITests: XCTestCase {
    private func launch(sshPort: Int? = nil, compact: Bool = false, multipleMacs: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--vision-qa-empty-library"]
        if let sshPort { app.launchArguments += ["--vision-qa-ssh-port", String(sshPort)] }
        if compact { app.launchArguments += ["--vision-qa-compact-large-text"] }
        if multipleMacs { app.launchArguments += ["--vision-qa-multiple-macs"] }
        app.launch(); return app
    }
    private func addMac(_ app: XCUIApplication, sshPort: Int? = nil) {
        let add = app.buttons["vision-add-mac"]
        XCTAssertTrue(add.waitForExistence(timeout: 30)); add.tap()
        let name = app.textFields["vision-mac-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15)); name.tap(); name.typeText("Synthetic Vision Mac")
        let address = app.textFields["vision-mac-address"]; address.tap(); address.typeText("127.0.0.1")
        if let sshPort {
            let port = app.textFields["vision-ssh-port"]
            XCTAssertEqual(port.value as? String, String(sshPort), app.debugDescription)
        }
        app.buttons["vision-save-mac"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Vision Mac"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func connect(_ app: XCUIApplication, surface: XCUIElement) {
        for attempt in 0..<2 {
            let account = app.textFields["vision-login-account"]
            XCTAssertTrue(account.waitForExistence(timeout: 15))
            reveal(account, in: app.scrollViews.firstMatch, up: false); account.tap(); account.typeText("synthetic")
            let password = app.secureTextFields["vision-login-password"]
            reveal(password, in: app.scrollViews.firstMatch); password.tap(); password.typeText("synthetic-only")
            let connect = app.buttons["vision-connect"]; reveal(connect, in: app.scrollViews.firstMatch); connect.tap()
            let trust = app.buttons["Trust & Connect"]
            if trust.waitForExistence(timeout: attempt == 0 ? 20 : 5) { trust.tap() }
            // The OS password-save alert can interrupt an in-flight login.
            // The app deliberately retires it, requiring an explicit retry.
            let savePassword = app.alerts["Save Password?"]
            if savePassword.waitForExistence(timeout: 5) { savePassword.buttons["Not Now"].tap() }
            if surface.waitForExistence(timeout: 5) { break }
            XCTAssertTrue(app.buttons["vision-connect"].exists, app.debugDescription)
        }
    }
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, up: Bool = true) {
        for _ in 0..<6 {
            if element.isHittable { return }
            if up { scroll.swipeUp(velocity: .slow) } else { scroll.swipeDown(velocity: .slow) }
        }
        XCTAssertTrue(element.isHittable)
    }
    func testConnectedDesktopSelectionAndSystemKeyboard() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        addTeardownBlock { try await server.close() }
        do {
            let app = launch(sshPort: server.port); addMac(app, sshPort: server.port)
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-desktop-")).firstMatch.tap()
            let canvas = app.descendants(matching: .any).matching(identifier: "vision-desktop-canvas").firstMatch
            connect(app, surface: canvas)
            XCTAssertTrue(canvas.waitForExistence(timeout: 20), app.debugDescription)
            canvas.tap()
            for _ in 0..<100 {
                if server.record.count("pointerDown") > 0 && server.record.count("pointerUp") > 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(server.record.count("pointerDown"), 1, "A stationary selection must produce exactly one remote button press")
            XCTAssertGreaterThan(server.record.count("pointerUp"), 0, "System selection must release the remote button")
            let beforeScrollDown = server.record.count("pointerDown")
            canvas.press(forDuration: 0.05, thenDragTo: app.buttons["Keyboard"])
            for _ in 0..<100 {
                if server.record.count("pointer-mask-16") + server.record.count("pointer-mask-8") > 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertGreaterThan(server.record.count("pointer-mask-16") + server.record.count("pointer-mask-8"), 0, "Pinch movement must scroll: \(String(describing: canvas.value))")
            XCTAssertEqual(server.record.count("pointerDown"), beforeScrollDown, "Scrolling must not press a primary button or end in a click")
            canvas.press(forDuration: 0.75)
            let cancel = app.buttons["vision-target-cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(server.record.count("pointerDown"), beforeScrollDown, "Holding must not click")
            let menuCapture = XCTAttachment(screenshot: app.screenshot()); menuCapture.name = "Target actions without primary click"; menuCapture.lifetime = .keepAlways; add(menuCapture)
            cancel.tap()
            XCTAssertEqual(server.record.count("pointerDown"), beforeScrollDown, "Dismissing actions must not click")
            canvas.press(forDuration: 0.75)
            let secondary = app.buttons["vision-target-right-click"]
            XCTAssertTrue(secondary.waitForExistence(timeout: 10)); secondary.tap()
            for _ in 0..<100 {
                if server.record.count("pointer-mask-4") > 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(server.record.count("pointer-mask-4"), 1)
            XCTAssertEqual(server.record.count("pointer-mask-1"), 1, "Right Click must not first select with primary")
            canvas.press(forDuration: 0.75)
            app.buttons["vision-target-double-click"].tap()
            for _ in 0..<100 {
                if server.record.count("pointer-mask-1") == 3 && server.record.pointerEvents().suffix(4).map(\.mask) == [1, 0, 1, 0] { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(server.record.count("pointer-mask-1"), 3, "Double Click sends two complete groups")
            let double = Array(server.record.pointerEvents().suffix(4))
            XCTAssertEqual(double.map(\.mask), [1, 0, 1, 0]); XCTAssertEqual(double[0].x, double[2].x); XCTAssertEqual(double[0].y, double[2].y)
            XCTAssertLessThan(double[2].time - double[0].time, 0.35)
            canvas.press(forDuration: 0.75)
            app.buttons["vision-target-drag-item"].tap()
            XCTAssertTrue(app.staticTexts["Drag Item: pinch and move to drag the selected item"].exists)
            let beforeDrag = server.record.count("pointer-mask-1")
            let beforeDragEvents = server.record.pointerEvents().count
            canvas.press(forDuration: 0.05, thenDragTo: app.buttons["Keyboard"])
            for _ in 0..<100 {
                if server.record.count("pointer-mask-1") > beforeDrag && server.record.pointerEvents().last?.mask == 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertGreaterThan(server.record.count("pointer-mask-1"), beforeDrag)
            XCTAssertEqual(server.record.pointerEvents().last?.mask, 0, "Drag ends with release")
            let drag = Array(server.record.pointerEvents().dropFirst(beforeDragEvents))
            XCTAssertTrue(drag.dropLast().allSatisfy { $0.mask == 1 }, "The hold remains continuous until the final release")
            XCTAssertFalse(app.staticTexts["Drag Item: pinch and move to drag the selected item"].exists)
            let beforeAdjustment = server.record.pointerEvents().count
            app.buttons["vision-adjust-view"].tap()
            app.buttons["Zoom In"].tap(); app.buttons["Pan"].tap(); app.buttons["Pan Left"].tap()
            app.buttons["Fit"].tap(); app.buttons["vision-adjustment-done"].tap()
            XCTAssertEqual(server.record.pointerEvents().count, beforeAdjustment, "Local adjustment sends no remote input")
            let beforeShortcutPrimary = server.record.count("pointer-mask-1")
            app.buttons["More"].tap(); app.buttons["Right Click"].tap()
            for _ in 0..<100 {
                if server.record.count("pointer-mask-4") == 2 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(server.record.count("pointer-mask-4"), 2, "The actual More shortcut dispatches one current-target secondary click")
            XCTAssertEqual(server.record.count("pointer-mask-1"), beforeShortcutPrimary)
            app.buttons["Keyboard"].tap()
            XCTAssertTrue(app.textViews["vision-desktop-keyboard"].waitForExistence(timeout: 10))
            let systemKeyboard = XCUIApplication(bundleIdentifier: "com.apple.RealityKeyboard")
            XCTAssertTrue(systemKeyboard.keyboards.firstMatch.waitForExistence(timeout: 10), "Native input must present the visionOS system keyboard: \(systemKeyboard.debugDescription)")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Focused"), object: app.textViews["vision-desktop-keyboard"])], timeout: 5), .completed, "The first Keyboard press must focus the native responder")
            canvas.tap()
            app.buttons["Keyboard"].tap()
            XCTAssertTrue(systemKeyboard.keyboards.firstMatch.waitForExistence(timeout: 10), "One press must reopen input after canvas selection")
            let keyboardCapture = XCTAttachment(screenshot: systemKeyboard.screenshot()); keyboardCapture.name = "Reopened native virtual keyboard"; keyboardCapture.lifetime = .keepAlways; add(keyboardCapture)
            let input = app.textViews["vision-desktop-keyboard"]
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Focused"), object: input)], timeout: 5), .completed, app.debugDescription)
            XCTAssertTrue(systemKeyboard.keys["x"].exists || systemKeyboard.buttons["x"].exists, systemKeyboard.debugDescription)
            if systemKeyboard.keys["x"].exists { systemKeyboard.keys["x"].tap() }
            else { systemKeyboard.buttons["x"].tap() }
            for _ in 0..<100 {
                if server.record.count("keyDown-120") == 1 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(server.record.count("keyDown-120"), 1)
            app.buttons["vision-keyboard-done"].tap()
            XCTAssertFalse(app.textViews["vision-desktop-keyboard"].exists)
            XCTAssertGreaterThan(server.record.count("visualClick"), 0); XCTAssertGreaterThan(server.record.count("visualScroll"), 0)
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Desktop completed interaction journey"; capture.lifetime = .keepAlways; add(capture)
        } catch { throw error }
    }
    func testConnectedTerminalControlsAndIndependentNewShell() async throws {
        let server = SSHTestServer(); try await server.start()
        addTeardownBlock { try await server.close() }
        let app = launch(sshPort: server.port); addMac(app, sshPort: server.port)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-terminal-")).firstMatch.tap()
        let terminal = app.descendants(matching: .any).matching(identifier: "vision-terminal-canvas").firstMatch
        connect(app, surface: terminal)
        XCTAssertTrue(terminal.waitForExistence(timeout: 20))
        // SwiftTerm renders terminal cells itself rather than exposing each row
        // as a static-text element. Inspect this native capture for the startup
        // banner; the hosted test verifies the emulator buffer before UI input.
        let startup = XCTAttachment(screenshot: terminal.screenshot()); startup.name = "Initial Terminal banner before UI input"; startup.lifetime = .keepAlways; add(startup)
        // A steady cursor keeps XCTest's public idle wait deterministic; the
        // normal emulator handles the host's standard cursor-style sequence.
        try await server.record.emit("\u{1b}[2 q")
        app.buttons["Tab"].tap(); app.buttons["Keys"].tap(); app.buttons["Arrow Up"].tap()
        for _ in 0..<100 {
            if server.record.received == [9] + Array("\u{1b}[A".utf8) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(server.record.received, [9] + Array("\u{1b}[A".utf8))
        app.buttons["Keys"].tap(); app.buttons["Control: Off"].tap()
        app.buttons["Keys"].tap(); app.buttons["Arrow Left"].tap()
        let modified = [UInt8]([9]) + Array("\u{1b}[A\u{1b}[1;5D".utf8)
        for _ in 0..<100 {
            if server.record.received == modified { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(server.record.received, modified, "The one-shot modifier must survive opening its native Keys menu")
        try await server.record.emit("\u{1b}[?1000h\u{1b}[?1006h")
        terminal.tap(); terminal.tap()
        for _ in 0..<100 {
            if server.record.received.count > modified.count { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let reports = String(decoding: server.record.received.dropFirst(modified.count), as: UTF8.self)
        XCTAssertTrue(reports.contains("\u{1b}[<0;")); XCTAssertTrue(reports.hasSuffix("m"), "Native Terminal mouse reports must include release")
        app.buttons["Keyboard"].tap()
        let keyboard = XCUIApplication(bundleIdentifier: "com.apple.RealityKeyboard")
        XCTAssertTrue(keyboard.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.buttons["More"].tap(); app.buttons["vision-new-shell"].tap()
        let titles = app.staticTexts.matching(identifier: "Synthetic Vision Mac · Terminal")
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(app.secureTextFields["vision-login-password"].exists)
        app.windows.containing(.secureTextField, identifier: "vision-login-password").firstMatch.buttons["vision-close-session"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: titles)], timeout: 15), .completed)
        XCTAssertTrue(terminal.exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Terminal controls and preserved owner"; capture.lifetime = .keepAlways; add(capture)
    }
    func testNativeLibraryAndIndependentDesktopTerminalWindows() {
        let app = launch(); addMac(app)
        let desktop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-desktop-")).firstMatch
        desktop.tap()
        XCTAssertTrue(app.staticTexts["Synthetic Vision Mac · Desktop"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.secureTextFields["vision-login-password"].exists)
        app.buttons["Your Macs"].firstMatch.tap(); desktop.tap()
        let titles = app.staticTexts.matching(identifier: "Synthetic Vision Mac · Desktop")
        XCTAssertEqual(titles.count, 1, "The default action returns to the existing owner")
        app.buttons["Your Macs"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-another-window-")).firstMatch.tap()
        app.buttons["Another Desktop"].tap()
        let two = NSPredicate(format: "count == 2")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: two, object: titles)], timeout: 15), .completed)
        app.buttons["Your Macs"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-terminal-")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic Vision Mac · Terminal"].waitForExistence(timeout: 15))
        app.windows.containing(.staticText, identifier: "Synthetic Vision Mac · Terminal").firstMatch.buttons["vision-close-session"].tap()
        XCTAssertEqual(titles.count, 2, "Closing Terminal must retain both Desktop windows")
    }
    func testNativeSettingsAndMetadataSyncExplanation() {
        let app = launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30)); settings.tap()
        XCTAssertTrue(app.staticTexts["Privacy"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.switches["Require Unlock"].exists)
        XCTAssertTrue(app.switches["Sync Mac Metadata with iCloud"].exists)
        let privacyNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Only saved Mac metadata and supported preferences sync.")).firstMatch
        if !privacyNote.exists {
            let settingsWindow = app.windows.containing(.staticText, identifier: "Privacy").firstMatch
            XCTAssertTrue(settingsWindow.exists, app.debugDescription)
            settingsWindow.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(privacyNote.waitForExistence(timeout: 10), app.debugDescription)
        let desktopActions = app.buttons["Desktop Quick Actions"]
        let settingsWindow = app.windows.containing(.staticText, identifier: "Privacy").firstMatch
        reveal(desktopActions, in: settingsWindow); desktopActions.tap()
        let layout = app.staticTexts["Your session layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fit to Window"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Right Click"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Mouse Mode"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["Mouse Mode"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["quick-action-add"].exists, app.debugDescription)
        let settingsCapture = XCTAttachment(screenshot: app.screenshot()); settingsCapture.name = "Supported native Desktop quick actions"; settingsCapture.lifetime = .keepAlways; add(settingsCapture)

    }
    func testMetadataSyncRequiresDisclosureAndAffirmativeConsent() {
        let app = launch(); app.buttons["Settings"].tap()
        let toggle = app.switches["Sync Mac Metadata with iCloud"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15)); XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let alert = app.alerts["Enable iCloud Sync?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let disclosure = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "addresses, ports")).firstMatch
        XCTAssertTrue(disclosure.exists, app.debugDescription)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Apple Account and trusted devices")).firstMatch.exists)
        let capture = XCTAttachment(screenshot: alert.screenshot()); capture.name = "Metadata disclosure before opt-in"; capture.lifetime = .keepAlways; add(capture)
        alert.buttons["Cancel"].tap(); XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 10)); alert.buttons["Enable Sync"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["Sync completed."].exists, "Unsigned Simulator does not establish cloud delivery")
        toggle.tap(); XCTAssertEqual(toggle.value as? String, "0")
    }
    func testFreeMacCanBeChangedWithoutRemovingSavedRecords() {
        let app = launch(multipleMacs: true)
        XCTAssertTrue(app.staticTexts["Synthetic First Mac"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Synthetic Second Mac"].exists)
        app.buttons["Manage Synthetic First Mac"].tap(); app.buttons["Use as My Free Mac"].tap()
        let desktop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-desktop-")).element(boundBy: 1)
        desktop.tap()
        XCTAssertTrue(app.staticTexts["Mac Companion Pro"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Done"].tap()
        app.buttons["Manage Synthetic Second Mac"].tap(); app.buttons["Use as My Free Mac"].tap()
        desktop.tap()
        XCTAssertTrue(app.staticTexts["Synthetic Second Mac · Desktop"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Your Macs"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic First Mac"].exists); XCTAssertTrue(app.staticTexts["Synthetic Second Mac"].exists)
        let capture = XCTAttachment(screenshot: app.collectionViews.firstMatch.screenshot()); capture.name = "Both Macs retained after free choice"; capture.lifetime = .keepAlways; add(capture)
    }
    func testCompactLargerTextForms() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        addTeardownBlock { try await server.close() }
        let app = launch(sshPort: server.port, compact: true); addMac(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-another-window-")).firstMatch.isHittable)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vision-open-desktop-")).firstMatch.tap()
        XCTAssertTrue(app.textFields["vision-login-account"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["vision-close-session"].isHittable)
        XCTAssertTrue(app.buttons["Your Macs"].isHittable)
        let canvas = app.descendants(matching: .any).matching(identifier: "vision-desktop-canvas").firstMatch
        connect(app, surface: canvas); XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let owner = app.windows.containing(.staticText, identifier: "Synthetic Vision Mac · Desktop").firstMatch
        XCTAssertEqual(owner.frame.width, 600); XCTAssertEqual(owner.frame.height, 420)
        XCTAssertTrue(app.buttons["vision-keyboard-button"].isHittable); XCTAssertTrue(app.buttons["vision-adjust-view"].isHittable)
        app.buttons["More"].tap(); app.buttons["Desktop Actions"].tap()
        let cancel = app.buttons["vision-target-cancel"]
        reveal(cancel, in: app.scrollViews["vision-desktop-target-actions"]); cancel.tap()
        app.buttons["vision-adjust-view"].tap()
        let adjustments = app.scrollViews["vision-view-adjustments"]
        reveal(app.buttons["Zoom In"], in: adjustments); app.buttons["Zoom In"].tap()
        reveal(app.buttons["Fit"], in: adjustments, up: false); app.buttons["Fit"].tap()
        reveal(app.buttons["vision-adjustment-done"], in: adjustments); app.buttons["vision-adjustment-done"].tap()
        XCTAssertTrue(server.record.pointerEvents().isEmpty, "Compact native alternatives cause no remote input")
        app.buttons["Keyboard"].tap()
        XCTAssertTrue(app.textViews["vision-desktop-keyboard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["More"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Compact window with accessibility text"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["More"].tap(); app.buttons["vision-disconnect"].tap()
        XCTAssertTrue(app.buttons["vision-connect"].waitForExistence(timeout: 15))
    }
}
