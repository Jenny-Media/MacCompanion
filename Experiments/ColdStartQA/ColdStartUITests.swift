import UIKit
import XCTest
@MainActor final class ColdStartUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.coldstartqa.ios")
        app.launchArguments = arguments; app.launch(); return app
    }
    private func connect(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Connect to " + name + " using ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
    }
    private func tapVisibleControl(_ element: XCUIElement, x: CGFloat = 0.5) {
        var previous = CGRect.null, stable = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists && element.isHittable else { stable = 0; return false }
            let frame = element.frame
            stable = frame == previous ? stable + 1 : 0; previous = frame
            return stable >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        print("Visible control target:", element.frame)
        // Touch the visible control, rather than a Form row's activation point.
        element.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    func testMacRowsKeepTheSavedDisplayModeAndOtherConnectionNamesDistinct() {
        let app = launch(["--connect-flow", "--row-modes-review"]); defer { app.terminate() }
        let virtual = app.buttons["Connect to Free Mac using Screen Sharing"]
        let mirror = app.buttons["Connect to Second Mac using Screen Sharing"]
        XCTAssertTrue(virtual.waitForExistence(timeout: 8))
        XCTAssertEqual(virtual.value as? String, "Virtual Display")
        XCTAssertEqual(mirror.value as? String, "Mirror Mac Screen")
        XCTAssertEqual(app.buttons["Connect to Terminal Mac using Terminal"].value as? String ?? "", "")
        XCTAssertEqual(app.buttons["Connect to Trackpad Mac using Trackpad & Keyboard"].value as? String ?? "", "")
        capture("mac-row-saved-modes", app)
        app.buttons["Manage Free Mac"].tap(); app.buttons["Mac Settings"].tap()
        let form = app.descendants(matching: .any)["mac-editor-form"].firstMatch
        let mirrorChoice = app.buttons["mac-display-mirror"]
        for _ in 0..<6 where !mirrorChoice.isHittable { form.swipeUp() }
        XCTAssertTrue(mirrorChoice.isHittable); mirrorChoice.tap()
        app.navigationBars["Edit Mac"].buttons["Save"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            virtual.exists && virtual.value as? String == "Mirror Mac Screen"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        app.buttons["Manage Free Mac"].tap(); app.buttons["Mac Settings"].tap()
        let virtualChoice = app.buttons["mac-display-virtual"]
        for _ in 0..<6 where !virtualChoice.isHittable { form.swipeUp() }
        XCTAssertTrue(virtualChoice.isHittable); virtualChoice.tap()
        app.navigationBars["Edit Mac"].buttons["Cancel"].tap()
        XCTAssertTrue(virtual.waitForExistence(timeout: 5))
        XCTAssertEqual(virtual.value as? String, "Mirror Mac Screen", "Cancelling a draft must leave the saved row mode unchanged")
        XCTAssertEqual(mirror.value as? String, "Mirror Mac Screen")
        capture("mac-row-saved-mode-after-cancel", app)
    }

    func testConnectedSessionHidesLibraryAccessibilityAndRestoresItAfterDisconnect() {
        for locked in [false, true] {
        let app = launch(["--connect-flow", "--connected-session-review"] + (locked ? ["--inactive-auth"] : [])); defer { app.terminate() }
        let row = app.buttons["Connect to Free Mac using Terminal"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let controls = app.buttons["terminal-controls"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controls.exists && controls.isHittable && !app.descendants(matching: .any)["connection-sheet"].firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 10), .completed)
        for id in ["macs-add", "macs-search", "macs-edit-order", "open-app-settings"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, id)
        }
        XCTAssertFalse(row.exists)
        XCTAssertFalse(app.buttons["Manage Second Mac"].exists)
        capture("connected-terminal-hides-library-" + (locked ? "locked-start" : "unlocked-start"), app)
        controls.tap(); app.buttons["Session"].tap(); app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-app-settings"].exists)
        XCTAssertTrue(row.exists)
        capture("disconnected-restores-library-" + (locked ? "locked-start" : "unlocked-start"), app)
        }
    }

    func testSearchCanDismissKeyboardWithoutClearingTheFilter() {
        let app = launch(["--connect-flow"]); defer { app.terminate() }
        let search = app.textFields["macs-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap(); search.typeText("Free")
        let done = app.buttons["macs-search-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["macs-add"].exists)
        XCTAssertFalse(search.frame.intersects(done.frame))
        XCTAssertEqual(search.frame.midY, done.frame.midY, accuracy: 3)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        capture("search-keyboard-inline-done", app)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Free")
        XCTAssertTrue(app.buttons["macs-add"].isHittable)
        capture("search-dismissed-keeps-filter", app)
        search.tap(); search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Free")
    }

    func testSearchControlsStaySeparateAtLargeTextAndInLandscape() {
        for (theme, category, orientation) in [("dark", "UICTContentSizeCategoryL", UIDeviceOrientation.landscapeLeft),
                                                ("light", "UICTContentSizeCategoryAccessibilityXXXL", .portrait)] {
            let app = launch(["--connect-flow", "-direct-client-appearance-v1", theme, "-UIPreferredContentSizeCategoryName", category])
            XCUIDevice.shared.orientation = orientation
            let search = app.textFields["macs-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap()
            let done = app.buttons["macs-search-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                done.isHittable && !search.frame.intersects(done.frame) && abs(search.frame.midY - done.frame.midY) < 3
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            XCTAssertFalse(app.buttons["macs-add"].exists)
            XCTAssertLessThanOrEqual(done.frame.maxX, app.frame.maxX)
            capture("search-inline-done-" + theme + "-" + category, app)
            done.tap(); XCTAssertTrue(app.buttons["macs-add"].isHittable)
            app.terminate(); XCUIDevice.shared.orientation = .portrait
        }
    }

    func testTerminalMethodMenuDoesNotClaimASavedLoginAndPreservesAccountDraft() {
        let app = launch(["--connect-flow"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 8))
        app.buttons["Manage Free Mac"].tap(); app.buttons["Terminal"].tap()
        let username = app.textFields["terminal-login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        let method = app.buttons["terminal-login-access"]
        XCTAssertEqual(method.value as? String, "Password")
        XCTAssertFalse(method.label.contains("Saved Login"))
        username.tap(); username.typeText("synthetic-account")
        method.tap(); capture("terminal-signin-method-menu", app)
        app.buttons["SSH Key"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Choose SSH Key"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["terminal-login-password"].exists)
        XCTAssertEqual(method.value as? String, "SSH Key")
        capture("terminal-key-method", app)
        method.tap(); app.buttons["Password"].firstMatch.tap()
        XCTAssertTrue(app.secureTextFields["terminal-login-password"].waitForExistence(timeout: 5))
        XCTAssertEqual(username.value as? String, "synthetic-account")
        XCTAssertEqual(method.value as? String, "Password")
        capture("terminal-password-method-restored", app)
        app.buttons["terminal-login-cancel"].tap()
    }

    func testLoginFooterStaysAboveKeyboardForBothConnectionModes() {
        for terminal in [false, true] {
            // Isolate keyboard/rotation state between native and hosted forms.
            let app = launch(["--connect-flow"]); defer { app.terminate() }
            if terminal { app.buttons["Manage Free Mac"].tap(); app.buttons["Terminal"].tap() }
            else { connect("Free Mac", in: app) }
            let username = app.textFields[terminal ? "terminal-login-username" : "mac-login-username"]
            let password = app.secureTextFields[terminal ? "terminal-login-password" : "mac-login-password"]
            let cancel = app.buttons[terminal ? "terminal-login-cancel" : "mac-login-cancel"]
            let connect = app.buttons[terminal ? "terminal-connect" : "mac-login-connect"]
            XCTAssertTrue(username.waitForExistence(timeout: 5))
            assertEmptyInput(username, placeholder: "Username")
            assertEmptyInput(password, placeholder: "Password")
            XCTAssertEqual(username.label, "Username")
            XCTAssertEqual(password.label, "Password")
            // Placeholders share the same leading edge; captions reserve their height.
            XCTAssertEqual(username.frame.minX, password.frame.minX, accuracy: 2)
            XCTAssertGreaterThan(password.frame.midY - username.frame.midY, 40)
            XCTAssertLessThan(password.frame.midY - username.frame.midY, 80)
            XCTAssertGreaterThan(password.frame.width, 60)
            XCTAssertTrue(cancel.isHittable)
            let panel = app.otherElements["connection-sheet"].firstMatch
            XCTAssertLessThan(panel.frame.maxY - cancel.frame.maxY, 60)
            capture(terminal ? "terminal-login-footer-empty" : "screen-login-footer-empty", app)
            username.tap()
            XCTAssertTrue(username.placeholderValue == nil || username.placeholderValue == "", "The focused caption replaces its placeholder")
            capture(terminal ? "terminal-login-caption-focused" : "screen-login-caption-focused", app)
            let focusedHeight = username.frame.height
            username.typeText("synthetic-account")
            XCTAssertEqual(username.frame.height, focusedHeight, accuracy: 1)
            password.tap(); password.typeText("synthetic-password")
            XCTAssertTrue(username.placeholderValue == nil || username.placeholderValue == "", "Filled rows retain their caption after leaving focus")
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                connect.isEnabled && cancel.isHittable && app.keyboards.firstMatch.exists && cancel.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            capture(terminal ? "terminal-login-footer-filled-keyboard" : "screen-login-footer-filled-keyboard", app)
            tapVisibleControl(app.buttons["Show Password"].firstMatch)
            let visiblePassword = app.textFields[terminal ? "terminal-login-password" : "mac-login-password"]
            XCTAssertTrue(visiblePassword.waitForExistence(timeout: 5))
            for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
                XCUIDevice.shared.orientation = orientation
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in cancel.isHittable }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
                // Short native layouts can scroll their fields while keeping
                // actions fixed. Verify that real path instead of requiring
                // every input to fit above a landscape software keyboard.
                let scroll = terminal ? panel.scrollViews.firstMatch : app.scrollViews["mac-login-scroll"]
                for _ in 0..<4 where !visiblePassword.isHittable { scroll.swipeUp() }
                XCTAssertTrue(visiblePassword.isHittable)
                visiblePassword.tap()
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                XCTAssertTrue(cancel.isHittable)
                XCTAssertLessThanOrEqual(visiblePassword.frame.maxY, cancel.frame.minY + 2)
                XCTAssertLessThanOrEqual(cancel.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
                XCTAssertEqual(username.value as? String, "synthetic-account")
                XCTAssertEqual(visiblePassword.value as? String, "synthetic-password")
                capture((terminal ? "terminal-grouped-" : "screen-grouped-") + (orientation == .portrait ? "portrait-request-" : "landscape-request-") + (app.frame.width > app.frame.height ? "wide" : "tall"), app)
            }
            cancel.tap()
            XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 5))
        }
    }

    func testUnlockPageKeepsItsBrandAndBottomActionAcrossRotationAndLargeText() {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(["--inactive-auth", "--unlock-layout", "-UIPreferredContentSizeCategoryName", category])
            let button = app.buttons["app-unlock"].firstMatch, brand = app.staticTexts["app-unlock-brand"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8)); XCTAssertTrue(brand.exists)
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                let portrait = orientation == .portrait
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
                for _ in 0..<3 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
                XCTAssertTrue(button.isHittable); XCTAssertTrue(button.isEnabled)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
                XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
                XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                image.name = "unlock-page-" + (portrait ? "portrait-" : "landscape-") + category
                image.lifetime = .keepAlways; add(image)
            }
            XCUIDevice.shared.orientation = .portrait
            let portraitReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [portraitReady], timeout: 5), .completed)
            button.tap(); XCTAssertEqual(button.label, "Unlocking…"); XCTAssertFalse(button.isEnabled)
            capture("unlock-authenticating-" + category, app)
            app.terminate(); XCUIDevice.shared.orientation = .portrait
        }
    }
    private func openSavedLogin(in app: XCUIApplication) {
        app.buttons["Manage Free Mac"].tap(); app.buttons["Mac Settings"].tap()
        let saved = app.buttons["Saved Login"]
        let form = app.descendants(matching: .any)["mac-editor-form"].firstMatch
        for _ in 0..<6 where !saved.isHittable { form.swipeUp() }
        XCTAssertTrue(saved.isHittable); saved.tap()
        XCTAssertTrue(app.navigationBars["Saved Login"].waitForExistence(timeout: 5))
    }
    func testSavedLoginKeepsDraftThroughTerminalSettingsAndCancelDiscardsIt() {
        let app = launch(["--saved-login-tests"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5)); openSavedLogin(in: app)
        let username = app.textFields["access-account"]
        XCTAssertEqual(username.value as? String, "synthetic-account")
        XCTAssertTrue(app.secureTextFields["access-password"].exists)
        // Form exposes the complete SwiftUI username row as its accessibility
        // frame. The UIKit password reports only its editor. Their text-column
        // geometry is checked in the hosted row test and screenshot review.
        XCTAssertTrue(username.isHittable)
        XCTAssertTrue(app.secureTextFields["access-password"].isHittable)
        XCTAssertLessThan(app.secureTextFields["access-password"].frame.midY - username.frame.midY, 72)
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.textFields["access-password"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["access-password"].value as? String, "synthetic-password")
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.secureTextFields["access-password"].waitForExistence(timeout: 5))
        username.tap(); username.typeText("-draft")
        let draft = username.value as? String
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.textFields["access-password"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["access-password"].value as? String, "synthetic-password")
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.secureTextFields["access-password"].waitForExistence(timeout: 5))
        let savedImage = XCTAttachment(screenshot: app.screenshot()); savedImage.name = "saved-login-editor"; savedImage.lifetime = .keepAlways; add(savedImage)
        app.buttons["access-terminal-settings"].tap()
        XCTAssertTrue(app.navigationBars["Terminal Sign-In"].waitForExistence(timeout: 5))
        app.buttons["access-ssh-method"].tap(); app.buttons["Different Account"].firstMatch.tap()
        XCTAssertTrue(app.textFields["access-terminal-account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["access-terminal-password"].isHittable)
        capture("saved-terminal-grouped-rows", app)
        app.textFields["access-terminal-account"].tap(); app.textFields["access-terminal-account"].typeText("terminal-draft")
        app.navigationBars["Terminal Sign-In"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Saved Login"].waitForExistence(timeout: 5))
        XCTAssertEqual(username.value as? String, draft)
        XCTAssertTrue(app.buttons["access-terminal-settings"].label.contains("Different Account"))
        app.buttons["access-terminal-settings"].tap()
        XCTAssertEqual(app.textFields["access-terminal-account"].value as? String, "terminal-draft")
        app.navigationBars["Terminal Sign-In"].buttons.firstMatch.tap()
        app.navigationBars["Saved Login"].buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
        app.buttons["Saved Login"].tap()
        XCTAssertEqual(app.textFields["access-account"].value as? String, "synthetic-account")
        XCTAssertTrue(app.buttons["access-terminal-settings"].label.contains("Mac Account"))
    }

    func testSavedLoginGroupedFieldsSupportMacAndSeparateTerminalAccounts() {
        let app = launch(["--saved-login-tests", "--connect-flow"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5)); openSavedLogin(in: app)
        let username = app.textFields["access-account"]
        XCTAssertEqual(username.value as? String, "synthetic-account")
        XCTAssertTrue(app.secureTextFields["access-password"].isHittable)
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.textFields["access-password"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["access-password"].value as? String, "synthetic-password")
        capture("saved-mac-grouped-rows", app)
        app.buttons["access-terminal-settings"].tap()
        app.buttons["access-ssh-method"].tap(); app.buttons["Different Account"].firstMatch.tap()
        let account = app.textFields["access-terminal-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5)); account.tap(); account.typeText("terminal-draft")
        XCTAssertEqual(account.value as? String, "terminal-draft")
        tapVisibleControl(app.buttons["access-terminal-password-visibility"])
        let password = app.textFields["access-terminal-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap(); password.typeText("synthetic-terminal")
        XCTAssertEqual(password.value as? String, "synthetic-terminal")
        capture("saved-terminal-grouped-filled", app)
    }

    func testForgetSavedLoginNeedsOnlyOneConfirmationWithUnsavedEdits() {
        let app = launch(["--saved-login-tests", "--connect-flow"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5)); openSavedLogin(in: app)
        let username = app.textFields["access-account"]
        XCTAssertEqual(username.value as? String, "synthetic-account")
        username.tap(); username.typeText("-unsaved")
        let forget = app.buttons["access-forget-login"]
        let form = app.descendants(matching: .any)["access-login-form"].firstMatch
        // Form's accessibility frame extends under the system keyboard. Start
        // drags in the visible content instead of sending them to keyboard keys.
        for _ in 0..<6 {
            if forget.isHittable { break }
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : form.frame.maxY
            let startY = min(form.frame.maxY, keyboardTop) - form.frame.minY - 24
            let origin = form.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: form.frame.width / 2, dy: startY)).press(forDuration: 0.1,
                thenDragTo: origin.withOffset(CGVector(dx: form.frame.width / 2, dy: max(24, startY - 240))))
        }
        XCTAssertTrue(forget.isHittable); forget.tap()
        let confirm = app.buttons["access-confirm-forget-login"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture("forget-login-confirmation", app)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Saved Login"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].exists)
        app.buttons["Saved Login"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        assertEmptyInput(username, placeholder: "Username")
        tapVisibleControl(app.buttons["access-password-visibility"])
        XCTAssertTrue(app.textFields["access-password"].waitForExistence(timeout: 5))
        assertEmptyInput(app.textFields["access-password"], placeholder: "Password")
        capture("forgotten-login-stays-empty", app)
        app.navigationBars["Saved Login"].buttons["Cancel"].tap()
        app.navigationBars["Edit Mac"].buttons["Cancel"].tap()
        connect("Free Mac", in: app)
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
        assertEmptyInput(app.textFields["mac-login-username"], placeholder: "Username")
        XCTAssertFalse(app.buttons["mac-login-connect"].isEnabled)
    }

    func testUnlockTimingSnapshotWaitsForAdmissionAndEligibleNativeDisplayTick() {
        let app = launch(["--held-library", "--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa-timing-status"].label, "Timing pending")
        XCTAssertTrue(app.buttons["open-app-settings"].isHittable)
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["qa-activate"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Timing ready"), object: app.staticTexts["qa-timing-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let phases = app.staticTexts["qa-timing-phases"].label
        for phase in ["authenticationCallback", "authenticationHandled", "localAdmission", "activationNotification", "activeAdmission", "coverRemoved", "unlockObserversReturned", "libraryDisplayTick"] {
            XCTAssertTrue(phases.contains(phase), phase)
        }
        XCTAssertTrue(app.staticTexts["Loading saved Macs…"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap(); app.buttons["qa-load-macs"].tap()
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5))
    }

    func testSuccessfulAuthenticationMakesActualLocalControlsWorkBeforeActivation() {
        let app = launch(["--inactive-auth", "--manual-auth", "--empty-library"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        let unlock = app.buttons["app-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5)); XCTAssertEqual(unlock.label, "Unlocking…")
        XCTAssertFalse(unlock.isEnabled)
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["app-privacy-cover"].isHittable)
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap(); app.buttons["Add your first Mac"].tap()
        XCTAssertTrue(app.textFields["quick-connect-host"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap(); app.buttons["qa-activate"].tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote ready")
    }
    func testRemoteOpeningWaitsForActivationWhileLocalSettingsWork() {
        let app = launch(["--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        connect("Free Mac", in: app)
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        app.buttons["qa-activate"].tap()
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
        app.buttons["mac-login-cancel"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
    }
    func testBackgroundRetiresRemoteOpeningRequestedDuringSuccessfulHandoff() {
        let app = launch(["--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.staticTexts["Authenticated; awaiting activation"].waitForExistence(timeout: 5))
        connect("Free Mac", in: app); app.buttons["qa-background"].tap()
        app.buttons["qa-activate"].tap(); app.buttons["qa-finish-auth"].tap()
        XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 5))
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
    }
    func testLoadingSavedMacsOverlapsAuthenticationAndKeepsSettingsUsable() {
        let app = launch(["--held-library", "--inactive-auth", "--manual-auth"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Authenticating; inactive"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["app-unlock"].label, "Unlocking…")
        app.buttons["qa-finish-auth"].tap()
        XCTAssertEqual(app.staticTexts["qa-remote-ready"].label, "Remote paused")
        XCTAssertTrue(app.staticTexts["Loading saved Macs…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["macs-add"].isEnabled)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["qa-load-macs"].tap()
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Loading saved Macs…"].exists)
        app.buttons["Manage Free Mac"].tap(); app.buttons["Mac Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
    }
    func testFreeConnectionAndExistingEditingDoNotWaitForStoreKit() {
        let app = launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5)); app.buttons["Manage Free Mac"].tap()
        app.buttons["Mac Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-editor-form"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap(); connect("Free Mac", in: app)
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
        let signInImage = XCTAttachment(screenshot: app.screenshot()); signInImage.name = "bottom-connection-sign-in"; signInImage.lifetime = .keepAlways; add(signInImage)
        app.buttons["mac-login-cancel"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
    }
    func testPaidActionTimesOutAndRetiredCompletionDoesNotPresent() {
        let app = launch(["--fast-timeout"]); defer { app.terminate() }
        connect("Second Mac", in: app)
        XCTAssertTrue(app.staticTexts["Checking purchases…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["mac-access-timeout"].waitForExistence(timeout: 5))
        app.buttons["mac-access-retry"].tap()
        app.buttons["qa-background"].tap(); app.buttons["qa-resolve-store"].tap(); app.buttons["qa-activate"].tap()
        XCTAssertTrue(app.navigationBars["My Macs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
        app.buttons["open-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
    }
    func testVerifiedReadinessCompletesOnlyCurrentPendingAction() {
        let app = launch(); defer { app.terminate() }
        connect("Second Mac", in: app)
        XCTAssertTrue(app.staticTexts["Checking purchases…"].waitForExistence(timeout: 3))
        app.buttons["qa-resolve-store"].tap()
        XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
    }
    func testQuickConnectionSheetExpandsOptionsAndCancelDoesNotSaveMac() {
        let app = launch(["--empty-library", "--connect-flow"]); defer { app.terminate() }
        let add = app.buttons["macs-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 8)); XCTAssertTrue(add.isHittable)
        XCTAssertFalse(app.buttons["macs-edit-order"].exists)
        let search = app.textFields["macs-search"]
        XCTAssertLessThan(abs(search.frame.midY - add.frame.midY), 20)
        add.tap()
        let host = app.textFields["quick-connect-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quick-connect-options"].exists)
        XCTAssertFalse(app.buttons["quick-connect-submit"].isEnabled)
        let panel = app.otherElements["connection-sheet"].firstMatch
        let first = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); first.name = "quick-connect-partial-sheet"; first.lifetime = .keepAlways; self.add(first)
        host.tap(); host.typeText("synthetic.invalid")
        XCTAssertTrue(app.buttons["quick-connect-submit"].isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(host.isHittable)
        XCTAssertLessThanOrEqual(host.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertEqual(app.navigationBars.matching(identifier: "Connect to Mac").count, 1,
            "The native form keeps one presentation while the keyboard opens")
        capture("quick-connect-keyboard", app)
        app.buttons["quick-connect-options"].tap()
        XCTAssertTrue(app.navigationBars["Connection Options"].waitForExistence(timeout: 5))
        let ssh = app.textFields["quick-connect-ssh-port"]
        for _ in 0..<5 where !ssh.isHittable { app.swipeUp() }
        XCTAssertTrue(ssh.isHittable)
        let options = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); options.name = "quick-connect-options"; options.lifetime = .keepAlways; self.add(options)
        app.navigationBars["Connection Options"].buttons.firstMatch.tap()
        XCTAssertEqual(host.value as? String, "synthetic.invalid")
        app.buttons["quick-connect-cancel"].tap()
        XCTAssertTrue(app.buttons["Add your first Mac"].waitForExistence(timeout: 5))
        add.tap(); XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertEqual(host.value as? String, "Hostname or IP address")
    }
    func testConnectionPresentationKeepsRealBackgroundAndStableIdentityWhileEditing() {
        let app = launch(["--connect-flow"]); defer { app.terminate() }
        connect("Free Mac", in: app)
        let username = app.textFields["mac-login-username"], cancel = app.buttons["mac-login-cancel"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        let panel = app.otherElements["connection-sheet"].firstMatch
        XCTAssertTrue(panel.exists)
        let initialInset = username.frame.minX - panel.frame.minX
        let initialTrailing = panel.frame.maxX - username.frame.maxX
        capture("screen-sharing-login", app)
        username.tap(); username.typeText("synthetic-account")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(username.frame.minX - panel.frame.minX, initialInset, accuracy: 2)
        XCTAssertEqual(panel.frame.maxX - username.frame.maxX, initialTrailing, accuracy: 2)
        capture("screen-sharing-login-keyboard", app)
        app.scrollViews.firstMatch.swipeDown()
        capture("screen-sharing-after-keyboard", app)
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        XCTAssertTrue(app.buttons["Manage Free Mac"].waitForExistence(timeout: 5))
        app.buttons["Manage Free Mac"].tap(); app.buttons["Terminal"].tap()
        XCTAssertTrue(app.textFields["terminal-login-username"].waitForExistence(timeout: 5))
        capture("terminal-login-real-background", app)
        XCTAssertTrue(app.buttons["terminal-login-cancel"].isHittable)
        app.buttons["terminal-login-cancel"].tap()
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 5))
    }
    private func dragSheetDown(_ panel: XCUIElement) {
        // Start on the native sheet's top edge. A swipe in its middle can scroll
        // the login content instead of exercising interactive sheet dismissal.
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.05, thenDragTo: panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
    }
    private func assertEmptyInput(_ field: XCUIElement, placeholder: String) {
        XCTAssertEqual(field.placeholderValue, placeholder)
        XCTAssertTrue(["", placeholder].contains(field.value as? String ?? ""), "An empty field may expose its placeholder as its accessibility value")
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let panel = app.otherElements["connection-sheet"].firstMatch
        if panel.exists {
            var previous = CGRect.null, stable = 0
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = panel.frame
                stable = frame == previous ? stable + 1 : 0; previous = frame
                return stable >= 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func assertSheetUsesAvailableSpace(_ panel: XCUIElement, app: XCUIApplication) {
        // The active UIWindow follows the Duo display; XCUIApplication's frame
        // can retain the requested orientation during an RC posture transition.
        let window = app.windows.firstMatch
        let available = window.exists ? window.frame : app.frame
        print("Adaptive sheet bounds:", panel.frame, "window:", available, "application:", app.frame)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, available.minX)
        XCTAssertLessThanOrEqual(panel.frame.maxX, available.maxX)
        if available.width >= 700 && available.height >= 600 {
            XCTAssertLessThanOrEqual(panel.frame.width, 600)
            XCTAssertEqual(panel.frame.midX, available.midX, accuracy: 12)
            if !app.keyboards.firstMatch.exists { XCTAssertEqual(panel.frame.midY, available.midY, accuracy: 40) }
        }
    }
    func testTrustActionsStayAtTheBottomAndCancelRemainsExplicit() {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(["--connect-flow", "--progress-review", "--trust-review", "-UIPreferredContentSizeCategoryName", category])
            let approve = app.buttons["server-trust-approve"], cancel = app.buttons["server-trust-cancel"]
            XCTAssertTrue(approve.waitForExistence(timeout: 8)); XCTAssertTrue(cancel.isHittable)
            let panel = app.otherElements["connection-sheet"].firstMatch
            assertSheetUsesAvailableSpace(panel, app: app)
            XCTAssertLessThan(panel.frame.maxY - cancel.frame.maxY, 70)
            XCTAssertLessThanOrEqual(approve.frame.maxY, cancel.frame.minY)
            capture("adaptive-trust-" + category, app)
            cancel.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }
    func testQuickConnectOptionsKeepsActionsAboveThePortKeyboard() {
        let app = launch(["--empty-library", "--connect-flow"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 8)); app.buttons["macs-add"].tap()
        let host = app.textFields["quick-connect-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5)); host.tap(); host.typeText("synthetic.invalid")
        let options = app.buttons["quick-connect-options"]
        tapVisibleControl(options) // Use the settled visible row's center.
        XCTAssertTrue(app.navigationBars["Connection Options"].waitForExistence(timeout: 5))
        let port = app.textFields["quick-connect-ssh-port"]
        let form = app.descendants(matching: .any)["quick-connect-options-form"].firstMatch
        let connect = app.buttons["quick-connect-options-submit"], cancel = app.buttons["quick-connect-options-cancel"]
        // Form can report a row hittable even while it lies behind the footer.
        // Scroll the actual value above the action area before touching it.
        for _ in 0..<6 where !port.isHittable || port.frame.maxY > connect.frame.minY - 8 { form.swipeUp() }
        XCTAssertTrue(port.isHittable)
        XCTAssertLessThan(port.frame.maxY, connect.frame.minY)
        tapVisibleControl(port, x: 0.9); port.typeText("2")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            port.isHittable && port.frame.maxY < connect.frame.minY - 4 && cancel.isHittable && connect.isHittable && app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        capture("adaptive-quick-options-keyboard", app)
        cancel.tap()
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 5))
    }
    func testBothConnectionProgressSheetsFitTheirContentAndUseTheSameCancelAction() {
        for (terminal, mirror) in [(false, false), (false, true), (true, false)] {
            let app = launch(["--connect-flow", "--progress-review"] + (terminal ? ["--terminal-review"] : mirror ? ["--mirror-review"] : []))
            let cancel = app.buttons[terminal ? "terminal-login-cancel" : "mac-login-cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 8)); XCTAssertTrue(cancel.isHittable)
            let status = app.staticTexts["Connecting…"]
            let visibleStatus = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                status.isHittable && status.frame.maxY <= cancel.frame.minY - 4
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visibleStatus], timeout: 5), .completed)
            let subtitle = app.staticTexts[terminal ? "Terminal" : mirror ? "Mirror Mac Screen" : "Virtual Display"].firstMatch
            XCTAssertTrue(subtitle.exists)
            if cancel.frame.minY - subtitle.frame.maxY > 350 {
                XCTAssertEqual(status.frame.midY, (subtitle.frame.maxY + cancel.frame.minY) / 2, accuracy: 64,
                    "Progress should balance the space between the Mac header and fixed actions")
            }
            let panel = app.otherElements["connection-sheet"].firstMatch
            assertSheetUsesAvailableSpace(panel, app: app)
            XCTAssertLessThan(panel.frame.maxY - cancel.frame.maxY, 70)
            capture(terminal ? "terminal-progress" : mirror ? "mirror-progress" : "virtual-progress", app)
            cancel.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }
    func testConnectingSheetsRejectSwipeDismissalButExplicitCancelWorks() {
        for terminal in [false, true] {
            let app = launch(["--connect-flow", "--progress-review"] + (terminal ? ["--terminal-review"] : []))
            let cancel = app.buttons[terminal ? "terminal-login-cancel" : "mac-login-cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 8))
            let panel = app.otherElements["connection-sheet"].firstMatch
            dragSheetDown(panel)
            XCTAssertTrue(panel.exists); XCTAssertTrue(cancel.isHittable)
            capture(terminal ? "terminal-progress-rejects-dismiss" : "desktop-progress-rejects-dismiss", app)
            cancel.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["macs-add"].isHittable)
            app.terminate()
        }
        let app = launch(["--connect-flow"]); defer { app.terminate() }
        for terminal in [false, true] {
            for _ in 0..<2 {
                if terminal { app.buttons["Manage Free Mac"].tap(); app.buttons["Terminal"].tap() }
                else { connect("Free Mac", in: app) }
                XCTAssertTrue(app.textFields[terminal ? "terminal-login-username" : "mac-login-username"].waitForExistence(timeout: 5))
                let panel = app.otherElements["connection-sheet"].firstMatch
                dragSheetDown(panel)
                XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "Idle credentials remain dismissible")
                XCTAssertTrue(app.buttons["macs-add"].isHittable)
            }
        }
    }
    func testProgressFitsAccessibilityTextWithoutHidingCancel() {
        let app = launch(["--connect-flow", "--progress-review", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        let cancel = app.buttons["mac-login-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        for _ in 0..<4 where !cancel.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(cancel.isHittable)
        capture("screen-progress-largest-text", app)
    }
    func testConnectionSheetsRemainUsableInDarkAppearanceAndAtAccessibilityTextSize() {
        for (theme, category) in [("dark", "UICTContentSizeCategoryL"), ("light", "UICTContentSizeCategoryAccessibilityXXXL")] {
            let app = launch(["--connect-flow", "-direct-client-appearance-v1", theme, "-UIPreferredContentSizeCategoryName", category])
            connect("Free Mac", in: app)
            XCTAssertTrue(app.textFields["mac-login-username"].waitForExistence(timeout: 5))
            let cancel = app.buttons["mac-login-cancel"]
            for _ in 0..<4 where !cancel.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(cancel.isHittable)
            capture("screen-sharing-login-" + theme + "-" + category, app)
            cancel.tap()
            app.buttons["Manage Free Mac"].tap(); app.buttons["Terminal"].tap()
            XCTAssertTrue(app.textFields["terminal-login-username"].waitForExistence(timeout: 5))
            let terminalCancel = app.buttons["terminal-login-cancel"]
            for _ in 0..<5 where !terminalCancel.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(terminalCancel.isHittable)
            capture("terminal-login-" + theme + "-" + category, app)
            terminalCancel.tap(); app.terminate()
        }
    }

    func testQuickConnectionSheetCanBeDismissedByDraggingWithoutSaving() {
        let app = launch(["--empty-library", "--connect-flow"]); defer { app.terminate() }
        let add = app.buttons["macs-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        XCTAssertTrue(app.textFields["quick-connect-host"].waitForExistence(timeout: 5))
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        XCTAssertTrue(app.buttons["Add your first Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable); XCTAssertFalse(app.textFields["quick-connect-host"].exists)
        add.tap(); XCTAssertTrue(app.textFields["quick-connect-host"].waitForExistence(timeout: 5))
        app.buttons["quick-connect-cancel"].tap()
    }
    func testQuickConnectionSheetKeepsControlsReachableWithLargeTextAndRotation() {
        let app = launch(["--empty-library", "--connect-flow", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 8)); app.buttons["macs-add"].tap()
        let host = app.textFields["quick-connect-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5)); host.tap(); host.typeText("synthetic.invalid")
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["quick-connect-cancel"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["quick-connect-cancel"].isHittable)
            XCTAssertTrue(app.buttons["quick-connect-submit"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["quick-connect-submit"].frame.height, 44)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = "quick-connect-accessibility-" + (orientation == .portrait ? "portrait" : "landscape"); image.lifetime = .keepAlways; self.add(image)
        }
        app.buttons["quick-connect-cancel"].tap()
        XCTAssertTrue(app.buttons["Add your first Mac"].waitForExistence(timeout: 5))
    }

    func testQuickConnectionPurchaseWaitLocksTheChosenHostAndCanBeCancelled() {
        let app = launch(["--connect-flow", "--fast-timeout"]); defer { app.terminate() }
        XCTAssertTrue(app.buttons["macs-add"].waitForExistence(timeout: 8)); app.buttons["macs-add"].tap()
        let host = app.textFields["quick-connect-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5)); host.tap(); host.typeText("synthetic-new.invalid")
        let entryReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.navigationBars["Connect to Mac"].frame.minY < app.frame.height * 0.2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entryReady], timeout: 5), .completed)
        XCTAssertGreaterThanOrEqual(app.buttons["quick-connect-submit"].frame.height, 44)
        app.buttons["quick-connect-submit"].tap()
        capture("quick-connect-purchase-wait", app)
        XCTAssertTrue(app.buttons["mac-access-cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(host.isEnabled); XCTAssertFalse(app.buttons["quick-connect-submit"].isEnabled)
        app.buttons["mac-access-cancel"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["macs-add"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertFalse(app.textFields["mac-login-username"].exists)
    }

}
