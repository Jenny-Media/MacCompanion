import Foundation
import XCTest

@MainActor final class SettingsFeedbackUITests: XCTestCase {
    func testFilesOpensAnIndependentWindowWithRemoteLoginGuidance() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), directory = URL.temporaryDirectory.appending(path: "files-native-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record: [String: Any] = ["id": UUID().uuidString, "name": "Synthetic Files", "addresses": ["fixture.local"], "port": 5900, "sshPort": 22, "usesAutomaticName": false, "preferredConnection": "desktop"]
        try JSONSerialization.data(withJSONObject: ["version": 5, "macs": [record]]).write(to: directory.appendingPathComponent("direct-macs-v1.json"))
        app.launchEnvironment["MACCOMPANION_DIRECT_DATA_DIRECTORY"] = directory.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]; app.launch()
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        let library = app.windows["My Macs"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.outlines.staticTexts["Synthetic Files"].firstMatch.click()
        XCTAssertTrue(library.buttons["Browse Files"].waitForExistence(timeout: 5)); library.buttons["Browse Files"].click()
        let files = app.windows.containing(.button, identifier: "files-connect").firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        XCTAssertTrue(files.textFields["files-account"].exists); XCTAssertTrue(files.secureTextFields["files-password"].exists)
        XCTAssertTrue(files.staticTexts["Requires Remote Login"].exists)
        capture("mac-files-sign-in", window: files)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(library.exists); XCTAssertFalse(files.exists)
    }
    private func capture(_ name: String, window: XCUIElement) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSyncInformationSheetReturnsToSettingsAndProIsInformational() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let directory = URL.temporaryDirectory.appending(path: "settings-feedback-ui-" + UUID().uuidString)
        app.launchEnvironment["MACCOMPANION_DIRECT_DATA_DIRECTORY"] = directory.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(app.windows["My Macs"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let category = app.descendants(matching: .any)["mac-settings-category-sync"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.click()
        let credentials = app.buttons["icloud-credentials-info"]
        XCTAssertTrue(credentials.waitForExistence(timeout: 5))
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        capture("mac-native-sync-settings", window: settings)
        credentials.click()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        capture("mac-native-credentials-info", window: app.sheets.firstMatch)
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(credentials.waitForExistence(timeout: 5), "Closing the explanation must keep Settings open")
        app.descendants(matching: .any)["mac-settings-category-general"].firstMatch.click()
        app.buttons["mac-settings-destination-pro"].click()
        XCTAssertTrue(app.buttons["pro-restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More Macs and SSH keys"].exists)
        capture("mac-native-pro", window: app.sheets.firstMatch)
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(app.buttons["mac-settings-destination-pro"].waitForExistence(timeout: 5))
    }
}
