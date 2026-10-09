import XCTest
import Foundation
import Crypto
import NIO
import NIOSSH
import Citadel

private final class UIConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [SSHTestRecord] = []
    func accepted(_ channel: Channel) -> SSHTestRecord {
        let record = SSHTestRecord(); record.openedTransport(channel)
        lock.lock(); records.append(record); lock.unlock(); return record
    }
    var connections: [SSHTestRecord] { lock.lock(); defer { lock.unlock() }; return records }
}

@MainActor final class NativeWindowUITests: XCTestCase {
    private func wait(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out: " + description); throw POSIXError(.ETIMEDOUT)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(text)
    }
    private func library(_ app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title == %@", "My Macs")).firstMatch
    }
    private func showLibrary(_ app: XCUIApplication) {
        // Each session becomes key when opened. Raise the library through the
        // native Window menu before clicking a control in that owning window.
        app.activate()
        let menu = app.menuBars.menuBarItems["Window"]
        menu.click()
        menu.menuItems["My Macs"].click()
        library(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).click()
    }
    private func open(_ mode: String, app: XCUIApplication) {
        showLibrary(app)
        let button = library(app).buttons["mac-open-" + mode]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.click()
    }
    private func windows(_ mode: String, app: XCUIApplication) -> XCUIElementQuery {
        // AppKit exposes a window's name as its title, rather than its label.
        app.windows.matching(NSPredicate(format: "title CONTAINS %@", " · " + mode))
    }
    private func connect(_ window: XCUIElement, app: XCUIApplication, acceptTrust: Bool) {
        replace(window.textFields["mac-terminal-account"], with: "synthetic")
        replace(window.secureTextFields["mac-terminal-password"], with: "synthetic-only")
        window.buttons["mac-terminal-connect"].click()
        if acceptTrust {
            let trust = window.buttons["Trust & Connect"]
            XCTAssertTrue(trust.waitForExistence(timeout: 5)); trust.click()
        }
        XCTAssertTrue(window.buttons["Disconnect"].waitForExistence(timeout: 5))
    }
    func testThreeModesAndIndependentTerminalKeyboardAndClose() async throws {
        continueAfterFailure = false
        let records = UIConnections(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            let record = records.accepted(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record))), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.macqa")
        let directory = URL.temporaryDirectory.appending(path: "maccompanion-ui-" + UUID().uuidString)
        app.launchEnvironment["MACCOMPANION_DIRECT_DATA_DIRECTORY"] = directory.path
        // The data directory is isolated, and restored scenes from a manual
        // QA run must not cover the new library or refer to another fixture.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch(); defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(library(app).waitForExistence(timeout: 10))
        showLibrary(app)
        library(app).buttons["mac-add-machine"].click()
        replace(app.textFields["mac-machine-name"], with: "Synthetic GUI")
        replace(app.textViews["mac-machine-addresses"], with: "127.0.0.1")
        replace(app.textFields["mac-machine-ssh-port"], with: String(try XCTUnwrap(server.localAddress?.port)))
        app.buttons["mac-save-machine"].click()
        let row = library(app).staticTexts["Synthetic GUI"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        open("desktop", app: app)
        XCTAssertTrue(windows("Desktop", app: app).firstMatch.waitForExistence(timeout: 5))
        open("trackpad", app: app)
        XCTAssertTrue(windows("Trackpad & Keyboard", app: app).firstMatch.waitForExistence(timeout: 5))
        open("terminal", app: app)
        let openedFirst = windows("Terminal", app: app).firstMatch
        XCTAssertTrue(openedFirst.waitForExistence(timeout: 5))
        // Freeze the owner: firstMatch changes when another window becomes key.
        let first = app.windows[openedFirst.identifier]
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).click()
        connect(first, app: app, acceptTrust: true)
        let surfaceA = first.descendants(matching: .any)["mac-terminal-surface"]
        XCTAssertTrue(surfaceA.waitForExistence(timeout: 5)); surfaceA.click(); app.typeText("A")
        try await wait("first native keyboard input") { records.connections.first?.received == [65] }
        open("terminal", app: app)
        XCTAssertEqual(windows("Terminal", app: app).count, 2)
        let second = windows("Terminal", app: app).allElementsBoundByIndex.first { $0.buttons["mac-terminal-connect"].exists }
        let ownSecond = app.windows[try XCTUnwrap(second).identifier]
        ownSecond.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).click()
        connect(ownSecond, app: app, acceptTrust: false)
        let surfaceB = ownSecond.descendants(matching: .any)["mac-terminal-surface"]
        surfaceB.click(); app.typeText("B")
        try await wait("second native keyboard input") { records.connections.count == 2 && records.connections[1].received == [66] }
        XCTAssertEqual(records.connections[0].received, [65])
        // The staggered title bar remains exposed behind the newer window.
        // Activate that owner before clicking its terminal responder.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).click()
        surfaceA.click(); app.typeText("C")
        try await wait("focus returned to first terminal") { records.connections[0].received == [65, 67] }
        XCTAssertEqual(records.connections[1].received, [66])
        app.typeKey("w", modifierFlags: .command)
        try await wait("own terminal window closes") { windows("Terminal", app: app).count == 1 }
        XCTAssertTrue(windows("Desktop", app: app).firstMatch.exists)
        XCTAssertTrue(windows("Trackpad & Keyboard", app: app).firstMatch.exists)
        surfaceB.click(); app.typeText("D")
        try await wait("surviving terminal keyboard input") { records.connections[1].received == [66, 68] }
        ownSecond.buttons["Disconnect"].click()
        try await wait("surviving terminal disconnect") { ownSecond.buttons["mac-terminal-connect"].exists }
        // Remove this synthetic record and its QA-local accepted host key.
        showLibrary(app)
        row.click(); library(app).buttons["mac-connection-settings"].click()
        app.buttons["Forget SSH Server Key"].click(); app.buttons["Forget"].click()
        app.buttons["Cancel"].click()
        try await server.close()
    }
}
