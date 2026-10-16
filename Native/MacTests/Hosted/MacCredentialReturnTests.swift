import AppKit
import SwiftUI
import XCTest
import NIO
@testable import MacCompanion

private final class CredentialReturnVNC: CompanionVNCSession {
    var active = false
    var attempts = 0
    override var running: Bool { active }
    override var connected: Bool { active }
    override func connectAddresses(_ addresses: [String]!, port: Int, username: String!, password: String!) { active = true; attempts += 1 }
    override func stop() { active = false }
    func reportConnected() { stateHandler?("Connected", ["framebufferWidth": 100, "framebufferHeight": 100]) }
}
@MainActor final class MacCredentialReturnTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw DirectFilesFailure.timedOut
    }
    func testLegacyDesktopNativeFieldsRestoreSavedOrClearUnsavedWithoutReconnect() async throws {
        for remember in [true, false] {
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Return", addresses: ["fixture.local"])
            let transport = CredentialReturnVNC(), session = MacVNCSession(mac: mac, makeTransport: { transport })
            defer { session.close(); try? DesktopCredentialStoreV1.remove(mac.id) }
            var draft = DirectFilesLoginDraft()
            if remember { try DesktopCredentialStoreV1.save(.init(username: "synthetic", password: "synthetic-only"), hostID: mac.id) }
            else { draft.username = "synthetic"; draft.password = "synthetic-only" }
            let host = NSHostingView(rootView: MacDirectDesktopView(mac: mac, session: session, loginDraft: draft))
            let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 840, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            if !remember {
                try await wait { descendants(host).contains { $0 is MacCredentialFields.Fields } }
                session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            }
            try await wait { transport.attempts == 1 }
            transport.reportConnected(); try await Task.sleep(for: .milliseconds(100))
            session.disconnect()
            try await wait {
                let fields = descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first
                return fields?.account.stringValue == (remember ? "synthetic" : "") && fields?.secret.stringValue == (remember ? "synthetic-only" : "")
            }
            XCTAssertEqual(transport.attempts, 1); XCTAssertFalse(session.connected)
        }
    }
    func testStandaloneFilesEndClearsUnsavedFormButKeepsAuthenticatedAccount() async throws {
        let probe = FilesDirectoryTestProbe(), peer = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await peer.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files Return", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let files = DirectFilesSession(mac: mac)
        defer { files.close(); try? TerminalSecretStore.remove(mac.id) }
        files.loginDraft.username = "synthetic"; files.loginDraft.password = "synthetic-only"
        files.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { files.trust != nil }; files.answerTrust(true)
        try await wait { files.phase == .ready }
        XCTAssertEqual(files.loginDraft.password, ""); XCTAssertEqual(files.account, "synthetic")
        files.disconnect()
        XCTAssertEqual(files.loginDraft.username, ""); XCTAssertEqual(files.loginDraft.password, "")
        XCTAssertEqual(files.account, "synthetic", "Download/retry ownership must survive form cleanup")
        XCTAssertEqual(probe.authentications, 1); XCTAssertEqual(files.phase, .interrupted)
    }
}
