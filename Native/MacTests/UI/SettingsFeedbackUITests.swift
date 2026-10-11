import Foundation
import XCTest
import Crypto
import NIO
@preconcurrency import NIOSSH
import Citadel

@MainActor final class SettingsFeedbackUITests: XCTestCase {
    func testConfirmedFilesCloseKeepsOtherWindowAndCancellingPreservesDownload() async throws {
        continueAfterFailure = false
        let directory = URL.temporaryDirectory.appending(path: "files-close-ui-" + UUID().uuidString)
        let remote = directory.appending(path: "remote", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Data("synthetic-download-only".utf8).write(to: remote.appendingPathComponent("download.txt"))
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record))),
                allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in
                    record.opened(child)
                    return child.pipeline.addHandler(FilesTestSFTPProcess(root: remote, allowSFTP: true, responseDelay: .nanoseconds(0)))
                }))
        }.bind(host: "127.0.0.1", port: 0).get()
        let port = try XCTUnwrap(server.localAddress?.port)
        let macs = ["Synthetic Pending Files", "Synthetic Other Files"].map { name in
            ["id": UUID().uuidString, "name": name, "addresses": ["127.0.0.1"], "port": 5900, "sshPort": port,
             "usesAutomaticName": false, "preferredConnection": "desktop"] as [String: Any]
        }
        try JSONSerialization.data(withJSONObject: ["version": 5, "macs": macs]).write(to: directory.appendingPathComponent("direct-macs-v1.json"))
        let app = XCUIApplication()
        app.launchEnvironment["MACCOMPANION_DIRECT_DATA_DIRECTORY"] = directory.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]; app.launch()
        defer {
            app.terminate()
            Task { try? await record.finish(status: nil, transportFailed: true); try? await server.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        let library = app.windows["My Macs"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        func showLibrary() {
            app.activate()
            let menu = app.menuBars.menuBarItems["Window"]; menu.click(); menu.menuItems["My Macs"].click()
        }
        func open(_ name: String) {
            showLibrary(); library.outlines.staticTexts[name].firstMatch.click(); library.buttons["Browse Files"].click()
        }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(5)
            while !condition() {
                guard Date() < deadline else { XCTFail("Files window transition timed out"); throw POSIXError(.ETIMEDOUT) }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func fill(_ field: XCUIElement, _ value: String) {
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.click()
            field.typeKey("a", modifierFlags: .command); field.typeText(value)
        }
        open("Synthetic Pending Files")
        let signInWindow = app.windows.containing(.button, identifier: "files-connect").firstMatch
        XCTAssertTrue(signInWindow.waitForExistence(timeout: 5))
        let files = app.windows[signInWindow.identifier]
        fill(files.textFields["files-account"], "synthetic"); fill(files.secureTextFields["files-password"], "synthetic-only")
        files.buttons["files-connect"].click()
        let trust = files.buttons["Trust & Connect"]
        XCTAssertTrue(trust.waitForExistence(timeout: 5)); trust.click()
        XCTAssertTrue(files.buttons["files-upload"].waitForExistence(timeout: 10))
        files.buttons["Download"].firstMatch.click()
        XCTAssertTrue(files.staticTexts["Ready to save"].waitForExistence(timeout: 10))
        // Check native close while this sign-in/download window still has focus.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(files.exists, "Native close must remain blocked before confirmation")
        XCTAssertTrue(library.exists)
        files.toolbars.buttons["files-done"].click()
        let close = app.windows.buttons["Close Files"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5)); app.windows.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(files.staticTexts["Ready to save"].exists, "Cancel keeps the private download available")
        // Open another Files owner, then use the native Window menu to return
        // to the pending download before confirming its closure.
        open("Synthetic Other Files")
        XCTAssertTrue(signInWindow.waitForExistence(timeout: 5))
        let other = app.windows[signInWindow.identifier]
        XCTAssertNotEqual(files.identifier, other.identifier)
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click(); windowMenu.menuItems.matching(identifier: "Files").element(boundBy: 0).click()
        files.toolbars.buttons["files-done"].click()
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.click()
        try await wait { !files.exists }
        XCTAssertTrue(other.exists); XCTAssertTrue(other.buttons["files-connect"].exists); XCTAssertTrue(library.exists)
        // Remove the synthetic record and its QA-local host trust through the client.
        showLibrary(); library.outlines.staticTexts["Synthetic Pending Files"].firstMatch.rightClick()
        app.menuItems["Remove Mac"].click()
        let remove = app.windows.buttons["Remove Mac"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.click()
    }
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
