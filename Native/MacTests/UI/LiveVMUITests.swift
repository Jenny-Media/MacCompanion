import Foundation
import XCTest

// Opt-in acceptance against the user-authorized disposable VM. The runner
// supplies its address, public fixture login and independently checked host key.
// No fixture credentials or screenshots are part of the application or Git.
@MainActor final class LiveVMUITests: XCTestCase {
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(text)
    }
    private func showLibrary(_ app: XCUIApplication) {
        app.activate()
        let menu = app.menuBars.menuBarItems["Window"]
        menu.click(); menu.menuItems["My Macs"].click()
        let library = app.windows.matching(NSPredicate(format: "title == %@", "My Macs")).firstMatch
        // Explicitly focus the owning title bar after menu activation. Native
        // test event synthesis must not target a covered session or another app.
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).click()
    }
    private func show(_ title: String, app: XCUIApplication) {
        app.activate()
        let menu = app.menuBars.menuBarItems["Window"]
        menu.click(); menu.menuItems[title].click()
        app.windows.matching(NSPredicate(format: "title == %@", title)).firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).click()
    }
    private func capture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLiveModesAndConnectionWindowCaptures() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let host = environment["MC_LIVE_VM_HOST"], !host.isEmpty,
              let account = environment["MC_LIVE_VM_ACCOUNT"], !account.isEmpty,
              let password = environment["MC_LIVE_VM_PASSWORD"], !password.isEmpty,
              let fingerprint = environment["MC_LIVE_VM_FINGERPRINT"], fingerprint.hasPrefix("SHA256:") else {
            throw XCTSkip("Disposable VM acceptance requires an explicitly supplied fixture and verified host fingerprint")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.macqa")
        let directory = URL.temporaryDirectory.appending(path: "maccompanion-live-ui-" + UUID().uuidString)
        app.launchEnvironment["MACCOMPANION_DIRECT_DATA_DIRECTORY"] = directory.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch(); defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        let library = app.windows.matching(NSPredicate(format: "title == %@", "My Macs")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10)); showLibrary(app)
        library.buttons["mac-add-machine"].click()
        // The real VM advertises a detected name. Keep this fixture's explicit
        // display name so discovery cannot rename it during window queries.
        let automatic = app.switches["mac-machine-automatic-name"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5)); automatic.click()
        replace(app.textFields["mac-machine-name"], with: "Sample macOS VM")
        replace(app.textViews["mac-machine-addresses"], with: host)
        app.buttons["mac-save-machine"].click()
        let row = library.staticTexts["Sample macOS VM"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        capture(library, name: "01-machine-library")

        func open(_ mode: String, title: String) -> XCUIElement {
            showLibrary(app); library.buttons["mac-open-" + mode].click()
            let window = app.windows.matching(NSPredicate(format: "title == %@", "Sample macOS VM · " + title)).firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            show("Sample macOS VM · " + title, app: app)
            return window
        }
        func connectVNC(_ window: XCUIElement) {
            replace(window.textFields["mac-vnc-account"], with: account)
            replace(window.secureTextFields["mac-vnc-password"], with: password)
            window.buttons["mac-vnc-connect"].click()
            XCTAssertTrue(window.buttons["Disconnect"].waitForExistence(timeout: 20))
            XCTAssertTrue(window.descendants(matching: .any)["mac-vnc-surface"].waitForExistence(timeout: 5))
        }
        let trackpad = open("trackpad", title: "Trackpad & Keyboard")
        connectVNC(trackpad)
        XCTAssertTrue(trackpad.staticTexts["The remote desktop is not displayed."].exists)
        capture(trackpad, name: "02-connected-trackpad")

        let terminal = open("terminal", title: "Terminal")
        replace(terminal.textFields["mac-terminal-account"], with: account)
        replace(terminal.secureTextFields["mac-terminal-password"], with: password)
        terminal.buttons["mac-terminal-connect"].click()
        let trust = terminal.buttons["Trust & Connect"]
        XCTAssertTrue(trust.waitForExistence(timeout: 10))
        XCTAssertTrue(terminal.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fingerprint, fingerprint)).firstMatch.exists)
        trust.click()
        XCTAssertTrue(terminal.buttons["Disconnect"].waitForExistence(timeout: 15))
        let shell = terminal.descendants(matching: .any)["mac-terminal-surface"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5)); shell.click()
        shell.typeText("sw_vers")
        shell.typeKey(.return, modifierFlags: [])
        shell.typeText("uname -m")
        shell.typeKey(.return, modifierFlags: [])
        capture(terminal, name: "04-connected-terminal")

        let desktop = open("desktop", title: "Desktop")
        connectVNC(desktop)
        capture(desktop, name: "03-connected-desktop")
        // These are distinct live owning windows, not successive replacements.
        XCTAssertTrue(trackpad.buttons["Disconnect"].exists)
        XCTAssertTrue(terminal.buttons["Disconnect"].exists)
        show("Sample macOS VM · Terminal", app: app)
        showLibrary(app)
        XCTAssertEqual(library.buttons.matching(NSPredicate(format: "label == %@", "Show Window")).count, 3)
        capture(library, name: "05-concurrent-connection-library")
        // Raise the registered Terminal owner through the new library control;
        // this must preserve its existing shell and all three window entries.
        library.buttons.matching(NSPredicate(format: "label == %@", "Show Window")).element(boundBy: 1).click()
        XCTAssertTrue(terminal.buttons["Disconnect"].isHittable)
        showLibrary(app)
        XCTAssertEqual(library.buttons.matching(NSPredicate(format: "label == %@", "Show Window")).count, 3)

        show("Sample macOS VM · Trackpad & Keyboard", app: app)
        app.typeKey("w", modifierFlags: .command)
        showLibrary(app)
        XCTAssertEqual(library.buttons.matching(NSPredicate(format: "label == %@", "Show Window")).count, 2)
        XCTAssertTrue(desktop.buttons["Disconnect"].exists)
        XCTAssertTrue(terminal.buttons["Disconnect"].exists)
        // Remove only this fixture's QA-local accepted server key.
        library.buttons["mac-connection-settings"].click()
        app.buttons["Forget SSH Server Key"].click(); app.buttons["Forget"].click()
        app.buttons["Cancel"].click()
    }
}
