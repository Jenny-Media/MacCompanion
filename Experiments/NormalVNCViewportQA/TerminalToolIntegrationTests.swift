import XCTest
import UIKit
import SwiftTerm
@testable import Mac_Companion

/// Actual host binaries through the app's SSH PTY and renderer. The opt-in host
/// owns isolated sessions, credentials and cleanup; no user SSH account is used.
@MainActor final class TerminalToolIntegrationTests: XCTestCase {
    private struct Host: Decodable {
        let port: Int; let password: String; let hostKey: String; let tools: [String: String]
    }
    func testTmuxRoundTripAndReattachPreservesRemoteShell() async throws { try await exercise("tmux") }
    func testZellijRoundTripAndReattachPreservesRemoteShell() async throws { try await exercise("zellij") }
    func testHerdrRoundTripAndReattachPreservesRemoteShell() async throws { try await exercise("herdr") }

    private func exercise(_ tool: String) async throws {
        guard let encoded = ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_TOOL_HOST"] else {
            throw XCTSkip("Real-tool tests require the opt-in loopback host runner")
        }
        let config = try JSONDecoder().decode(Host.self, from: Data(encoded.utf8))
        guard let version = config.tools[tool] else { throw XCTSkip(tool + " executable was not supplied; no compatibility claim") }
        XCTAssertTrue((1...65535).contains(config.port)); XCTAssertFalse(version.isEmpty)
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic " + tool, addresses: ["127.0.0.1"], sshPort: config.port)
        try TerminalSecretStore.write(Data(config.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        var lastOutputAt = Date()
        let receive = session.received
        session.received = { bytes in receive?(bytes); lastOutputAt = Date() }
        defer {
            session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            try? TerminalSecretStore.remove(mac.id)
        }
        func text() -> String { terminalCompatibilityText(controller.terminal.getTerminal()) }
        func connect() { session.connect(username: tool, password: config.password, remember: false) }
        func focusReadyPane() async throws {
            try await wait("ready pane shell", diagnostics: text) { text().contains("MCQA>") }
            // Match tapping the terminal to open the software keyboard. This
            // also delivers the focus report requested by the multiplexer.
            lastOutputAt = Date()
            XCTAssertTrue(controller.terminal.becomeFirstResponder())
            try await wait("focus, keyboard layout and capability negotiation settle", diagnostics: text) {
                Date().timeIntervalSince(lastOutputAt) >= 0.25
            }
        }
        func command(_ value: String) async throws {
            let paste = controller.terminal.getTerminal().bracketedPasteMode ? "\u{1b}[200~" + value + "\u{1b}[201~" : value
            session.send(Array(paste.utf8))
            // Model pasting and then pressing Return as separate user actions.
            // Zellij 0.44.3 can drop legacy Enter when its stdin parser receives
            // Paste and Enter in one read. Echo proves the paste was handled;
            // normalize whitespace because phone-sized panes wrap commands.
            let expected = value.filter { !$0.isWhitespace }
            try await wait("pasted command echo before native Return", diagnostics: text) {
                text().filter { !$0.isWhitespace }.contains(expected)
            }
            controller.terminal.insertText("\n")
        }
        connect()
        try await wait("authenticated " + tool) { session.connected || session.recovery != nil }
        XCTAssertTrue(session.connected, session.status)
        try await focusReadyPane()
        // Adjacent printf arguments keep the complete expected marker out of
        // the echoed command, so matching it proves shell execution and rendering.
        try await command("MCQA_STATE=kept; printf '%s%s\\n' 'MCQA_' 'ROUNDTRIP_中文😀'")
        try await wait("Unicode command output from " + tool, diagnostics: text) { text().contains("MCQA_ROUNDTRIP_中文😀") }
        XCTAssertTrue(session.connected)
        session.resize(columns: 100, rows: 30)
        try await command("printf '%s%s\\n' 'MCQA_' 'RESIZED'")
        try await wait("output after PTY resize", diagnostics: text) { text().contains("MCQA_RESIZED") }
        _ = controller.terminal.resignFirstResponder()
        session.stop()
        try await Task.sleep(for: .milliseconds(350))
        connect()
        try await wait("reattached SSH " + tool) { session.connected || session.recovery != nil }
        XCTAssertTrue(session.connected, session.status)
        try await focusReadyPane()
        try await command("printf '%s%s\\n' 'MCQA_PERSIST_' \"$MCQA_STATE\"")
        try await wait("original pane shell survives client disconnect", diagnostics: text) { text().contains("MCQA_PERSIST_kept") }
        XCTAssertTrue(session.connected)
        try await captureForReview(tool + "-reattached")
    }

    /// Opt-in pause for an external simctl screenshot, including the system
    /// keyboard. Only synthetic test sessions are visible; no pixels enter Git.
    private func captureForReview(_ name: String) async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { return }
        let folder = URL.documentsDirectory.appending(path: "TerminalCompatibilityScreenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ready = folder.appending(path: "ready")
        defer { try? FileManager.default.removeItem(at: ready) }
        try Data(name.utf8).write(to: ready, options: .atomic)
        try await Task.sleep(for: .seconds(3))
    }

    private func wait(_ message: String, diagnostics: (() -> String)? = nil, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if let diagnostics {
            let attachment = XCTAttachment(string: diagnostics())
            attachment.name = "Synthetic tool screen at timeout"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("Synthetic tool screen at timeout: " + diagnostics().debugDescription)
        }
        XCTFail("Timed out waiting for " + message)
        throw POSIXError(.ETIMEDOUT)
    }
}
