#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import Crypto
import NIO
import NIOSSH
@preconcurrency import Citadel
@testable import MacCompanion

/// Synthetic loopback SSH supports an interactive PTY and SFTP on the same transport.
private final class TerminalFilesTestRouter: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    let record: SSHTestRecord
    let root: URL
    let allowSFTP: Bool
    let delay: TimeAmount
    private var selected = false
    init(record: SSHTestRecord, root: URL, allowSFTP: Bool, delay: TimeAmount) {
        self.record = record; self.root = root; self.allowSFTP = allowSFTP; self.delay = delay
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if !selected {
            do {
                if event is SSHChannelRequestEvent.SubsystemRequest {
                    try context.pipeline.syncOperations.addHandler(FilesTestSFTPProcess(root: root, allowSFTP: allowSFTP, responseDelay: delay))
                } else if event is SSHChannelRequestEvent.PseudoTerminalRequest {
                    try context.pipeline.syncOperations.addHandler(SSHTestPTY(record))
                } else { context.fireUserInboundEventTriggered(event); return }
                selected = true
            } catch { context.close(promise: nil); return }
        }
        context.fireUserInboundEventTriggered(event)
    }
}

@MainActor final class MacTerminalFilesTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < end else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func withTerminal(keyLogin: Bool = false, allowSFTP: Bool = true, delay: TimeAmount = .nanoseconds(0),
                              _ body: (DirectTerminalSession, SSHTestRecord, URL) async throws -> Void) async throws {
        let root = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = keyLogin ? TerminalSSHKey.create() : nil
        let publicKey = try key.map { NIOSSHPrivateKey(ed25519Key: try .init(rawRepresentation: $0.seed)).publicKey }
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record, publicKey: publicKey))),
                allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in
                    child.pipeline.addHandler(TerminalFilesTestRouter(record: record, root: root, allowSFTP: allowSFTP, delay: delay))
                }))
        }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Terminal Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let terminal = DirectTerminalSession(mac: mac, libraryURL: root.appending(path: "library.json"))
        defer { terminal.stop(); try? TerminalSecretStore.remove(mac.id) }
        terminal.connect(username: "synthetic", password: keyLogin ? "" : "synthetic-only", remember: false, key: key)
        try await wait { terminal.trust != nil || !terminal.connecting }
        if terminal.trust != nil { terminal.answerTrust(true) }
        try await wait { terminal.connected || !terminal.connecting }
        XCTAssertTrue(terminal.connected, terminal.status)
        guard terminal.connected else { throw DirectFilesFailure.unavailable }
        try await body(terminal, record, root)
    }
    func testPasswordAndKeyReuseOnlyOneAuthenticationAndFilesCloseKeepsShell() async throws {
        for key in [false, true] {
            try await withTerminal(keyLogin: key) { terminal, record, _ in
                let context = try XCTUnwrap(terminal.filesContext)
                XCTAssertEqual(context.account, "synthetic")
                let authentications = record.passwordRequests + record.keyRequests
                let files = DirectFilesSession(mac: terminal.mac, saveLogin: { _, _ in XCTFail("Borrowing must not retain credentials") })
                defer { files.close() }
                files.connectBorrowed(context)
                try await wait { !files.busy }
                XCTAssertEqual(files.phase, .ready, files.message ?? files.status)
                XCTAssertTrue(files.isBorrowed); XCTAssertNil(files.trust)
                XCTAssertEqual(files.account, "synthetic")
                XCTAssertEqual(record.passwordRequests + record.keyRequests, authentications)
                files.close()
                terminal.send(Array("still-usable".utf8))
                try await wait { String(decoding: record.received, as: UTF8.self).contains("still-usable") }
                XCTAssertTrue(terminal.connected)
                let reopened = DirectFilesSession(mac: terminal.mac); defer { reopened.close() }
                reopened.connectBorrowed(try XCTUnwrap(terminal.filesContext))
                try await wait { !reopened.busy }
                XCTAssertEqual(reopened.phase, .ready)
                XCTAssertEqual(record.passwordRequests + record.keyRequests, authentications)
            }
        }
    }
    func testParentDisconnectKeepsDownloadAndRejectsStaleContext() async throws {
        try await withTerminal { terminal, _, root in
            let bytes = Data([1, 2, 3, 4]); try bytes.write(to: root.appending(path: "sample.bin"))
            let context = try XCTUnwrap(terminal.filesContext)
            let files = DirectFilesSession(mac: terminal.mac); defer { files.close() }
            files.connectBorrowed(context); try await wait { !files.busy }
            XCTAssertEqual(files.phase, .ready)
            files.download(.init(name: "sample.bin", kind: .file, size: UInt64(bytes.count)))
            try await wait { !files.busy }
            let download = try XCTUnwrap(files.results.first?.localDownload)
            terminal.stop()
            try await wait { files.phase == .interrupted }
            XCTAssertNil(terminal.filesContext); XCTAssertFalse(context.isCurrent())
            XCTAssertEqual(files.resultsAccount, "synthetic")
            XCTAssertEqual(try Data(contentsOf: download), bytes)
            files.connectBorrowed(context)
            XCTAssertEqual(files.phase, .interrupted, "A disconnected context cannot reopen Files")
        }
    }
    func testFailedOrCancelledSFTPOpenDoesNotCloseTerminal() async throws {
        for allowed in [false, true] {
            try await withTerminal(allowSFTP: allowed, delay: .milliseconds(100)) { terminal, record, _ in
                let files = DirectFilesSession(mac: terminal.mac); defer { files.close() }
                files.connectBorrowed(try XCTUnwrap(terminal.filesContext))
                if allowed { files.close() } else { try await wait { !files.busy }; XCTAssertEqual(files.phase, .interrupted) }
                try await Task.sleep(for: .milliseconds(250))
                terminal.send(Array("parent-alive".utf8))
                try await wait { String(decoding: record.received, as: UTF8.self).contains("parent-alive") }
                XCTAssertTrue(terminal.connected)
                XCTAssertNotEqual(files.phase, .ready)
            }
        }
    }
    func testIndexedRoutingPinsWindowGenerationMacLibraryAndEndpoint() async throws {
        struct Row: Decodable { let id: String; let source: String; let accepted: Bool }
        struct Cases: Decodable { let routingCases: [Row] }
        struct Fixture: Decodable { let macTerminalReuse: Cases }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).macTerminalReuse.routingCases
        try await withTerminal { terminal, _, root in
            let registry = MacTerminalFilesRegistry(), id = UUID(), library = root.appending(path: "library.json")
            registry.register(terminal, windowID: id, libraryURL: library)
            let context = try XCTUnwrap(terminal.filesContext)
            for row in rows {
                var mac = terminal.mac
                if row.source == "other-mac" { mac = .init(id: UUID(), name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort) }
                if row.source == "edited-endpoint" { mac.addresses = ["127.0.0.2"] }
                let request = DirectFilesWindowRequest(macID: mac.id,
                    terminalID: ["other-window", "missing-owner"].contains(row.source) ? UUID() : id,
                    connectionGeneration: row.source == "old-generation" ? UUID() : context.generation)
                let found = registry.context(for: request, mac: mac, libraryURL: row.source == "other-library" ? root.appending(path: "other.json") : library)
                XCTAssertEqual(found != nil, row.accepted, row.id)
                if let found { XCTAssertTrue(found.client === context.client) }
            }
            let request = DirectFilesWindowRequest(macID: terminal.mac.id, terminalID: id, connectionGeneration: context.generation)
            registry.remove(terminal, windowID: id)
            XCTAssertNil(registry.context(for: request, mac: terminal.mac, libraryURL: library))
        }
    }
    func testNativeFilesWindowOpensAutomaticallyWithoutAnotherSignIn() async throws {
        try await withTerminal { terminal, record, root in
            let registry = MacTerminalFilesRegistry(), windowID = UUID(), library = root.appending(path: "library.json")
            registry.register(terminal, windowID: windowID, libraryURL: library)
            let context = try XCTUnwrap(terminal.filesContext)
            let request = DirectFilesWindowRequest(macID: terminal.mac.id, terminalID: windowID, connectionGeneration: context.generation)
            let files = DirectFilesSession(mac: terminal.mac); defer { files.close() }
            let authentications = record.passwordRequests
            let host = NSHostingView(rootView: MacFilesWindow(mac: terminal.mac,
                contextProvider: { registry.context(for: request, mac: terminal.mac, libraryURL: library) }, makeSession: { _ in files }))
            let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            try await wait { files.phase == .ready }
            XCTAssertTrue(files.isBorrowed); XCTAssertEqual(files.account, "synthetic")
            XCTAssertEqual(record.passwordRequests, authentications)
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            XCTAssertFalse(descendants(host).contains { $0 is MacCredentialFields.Fields })
            window.close()
            try await wait { files.isClosed }
            terminal.send(Array("window-closed-shell-alive".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).contains("window-closed-shell-alive") }
            XCTAssertTrue(terminal.connected)
        }
    }
    func testRestoredAndUnavailableParentShowsNoCredentialFields() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Missing Terminal", addresses: ["127.0.0.1"])
        let files = DirectFilesSession(mac: mac); defer { files.close() }
        let host = NSHostingView(rootView: DirectFilesView(mac: mac, session: files).usingConnection { nil })
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await wait { files.message != nil }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        XCTAssertFalse(descendants(host).contains { $0 is MacCredentialFields.Fields })
        XCTAssertEqual(files.phase, .signIn)
        XCTAssertTrue(files.message?.contains("Reconnect Terminal") == true)
        let legacy = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "macID": mac.id.uuidString])
        let request = try JSONDecoder().decode(DirectFilesWindowRequest.self, from: legacy)
        XCTAssertNil(request.terminalID); XCTAssertNil(request.connectionGeneration)
    }
    func testParentRetiredDuringSFTPOpenNeverBecomesReady() async throws {
        try await withTerminal(delay: .milliseconds(150)) { terminal, _, _ in
            let files = DirectFilesSession(mac: terminal.mac); defer { files.close() }
            files.connectBorrowed(try XCTUnwrap(terminal.filesContext))
            terminal.stop()
            try await wait { !files.busy }
            XCTAssertEqual(files.phase, .interrupted)
        }
    }
}
#endif
