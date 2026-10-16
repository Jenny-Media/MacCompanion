#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import NIO
import NIOSSH
@testable import MacCompanion

@MainActor final class MacTerminalPasswordReturnTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < end else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    func testIndexedPasswordReturnPreservesSavedAndEditedProvenance() throws {
        struct Row: Decodable {
            let id: String; let events: [String]; let account: String; let password: String; let remember: Bool; let reads: Int
        }
        struct Fixture: Decodable { let macTerminalPasswordReturnCases: [Row] }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).macTerminalPasswordReturnCases
        for row in rows {
            var draft = DirectFilesLoginDraft(), reads = 0
            let saved = TerminalSecretStore.Login(username: "synthetic", password: "synthetic-only")
            for event in row.events {
                switch event {
                case "initialize": draft.initialize(saved: saved)
                case "save-off": draft.remember = false
                case "connect-saved", "connect-unsaved", "connect-key":
                    let attempt = draft.authenticationAttempt(account: draft.username, password: draft.method == .password ? draft.password : nil, remember: draft.remember)
                    XCTAssertNotNil(attempt, row.id)
                    draft.authenticationSucceeded(attempt, retention: event == "connect-saved" ? .saved : .notRequested)
                case "end": draft.passwordSessionEnded()
                case "suspend": draft.suspend()
                case "restore", "locked-restore":
                    draft.resume()
                    draft.restorePassword(active: true, allowed: event != "locked-restore", signIn: true) { reads += 1; return saved }
                case "clear": draft.password = ""
                case "edit-account": draft.username = "synthetic-edited"
                case "key": draft.loadKeyAccount("synthetic-key", preferSelected: true)
                default: XCTFail("Unknown indexed event: " + event)
                }
            }
            XCTAssertEqual(draft.username, ["saved": "synthetic", "empty": "", "edited": "synthetic-edited", "key": "synthetic-key"][row.account], row.id)
            XCTAssertEqual(draft.password, row.password == "saved" ? "synthetic-only" : "", row.id)
            XCTAssertEqual(draft.remember, row.remember, row.id)
            XCTAssertEqual(reads, row.reads, row.id)
        }
    }
    func testReadFailureCanRetryButUserClearCannotReloadOldPassword() throws {
        enum Failure: Error { case unavailable }
        var draft = DirectFilesLoginDraft()
        let saved = TerminalSecretStore.Login(username: "synthetic", password: "synthetic-only")
        draft.initialize(saved: saved)
        let attempt = draft.authenticationAttempt(account: draft.username, password: draft.password, remember: true)
        draft.authenticationSucceeded(attempt, retention: .saved); draft.passwordSessionEnded()
        XCTAssertThrowsError(try draft.restorePassword(active: true, allowed: true, signIn: true) { throw Failure.unavailable })
        XCTAssertEqual(draft.username, "synthetic"); XCTAssertEqual(draft.password, ""); XCTAssertTrue(draft.remember)
        draft.restorePassword(active: true, allowed: true, signIn: true) { saved }
        XCTAssertEqual(draft.password, "synthetic-only")
        draft.password = ""
        draft.restorePassword(active: true, allowed: true, signIn: true) { XCTFail("Manual clear must not read an old saved password"); return saved }
        XCTAssertEqual(draft.password, "")
    }
    func testNativeRememberedDisconnectRestoresBothFieldsWithoutAnotherConnection() async throws {
        try await checkNativeReturn(remember: true)
    }
    func testNativeUnsavedDisconnectClearsBothFieldsWithoutAnotherConnection() async throws {
        try await checkNativeReturn(remember: false)
    }
    private func checkNativeReturn(remember: Bool) async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record))),
                allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Password Return", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac, libraryURL: root.appending(path: "library.json"))
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        // An unsaved login must also retire a previously saved password.
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        var draft = DirectFilesLoginDraft()
        if !remember { draft.username = "synthetic"; draft.password = "synthetic-only"; draft.remember = false }
        let host = NSHostingView(rootView: MacDirectTerminalView(mac: mac, libraryURL: root.appending(path: "library.json"), session: session, loginDraft: draft))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 840, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await wait { session.trust != nil || session.connected }
        if session.trust != nil { session.answerTrust(true) }
        try await wait { session.connected }
        // Allow SwiftUI to consume the successful-login transition before stop.
        try await Task.sleep(for: .milliseconds(100))
        let authentications = record.passwordRequests
        session.stop()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        try await wait {
            fields()?.account.stringValue == (remember ? "synthetic" : "") &&
            fields()?.secret.stringValue == (remember ? "synthetic-only" : "")
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertEqual(record.passwordRequests, authentications, "Disconnect cannot create a replacement shell")
        let retained = try TerminalSecretStore.login(mac.id)
        XCTAssertEqual(retained?.username, remember ? "synthetic" : nil)
        XCTAssertEqual(retained?.password, remember ? "synthetic-only" : nil)
    }
}
#endif
