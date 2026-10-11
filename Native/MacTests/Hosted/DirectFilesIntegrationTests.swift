import XCTest
import Foundation
import Crypto
import NIO
import NIOSSH
import Citadel
import SwiftUI
import AppKit
import Observation
@testable import MacCompanion

@MainActor @Observable private final class FilesTestAccess { var allowed = true }

private struct FilesTestWindowRoot: View {
    let library: DirectMacLibraryV1
    let owner: DirectFilesSession
    var body: some View {
        MacFilesWindow(mac: library.macs.first { $0.id == owner.mac.id }, makeSession: { _ in owner })
    }
}

@MainActor final class DirectFilesIntegrationTests: XCTestCase {
    private func wait(_ predicate: () -> Bool, seconds: Double = 10) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() {
            guard Date() < deadline else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func open(_ session: DirectFilesSession) async throws {
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.trust != nil || session.phase != .connecting }
        if session.trust != nil { session.answerTrust(true) }
        try await wait { session.phase != .connecting }
        XCTAssertEqual(session.phase, .ready, session.message ?? session.status)
        guard session.phase == .ready else { throw DirectFilesFailure.unavailable }
    }
    private func server(root: URL, record: SSHTestRecord, allowSFTP: Bool = true, responseDelay: TimeAmount = .nanoseconds(0), publicKey: NIOSSHPublicKey? = nil) async throws -> Channel {
        let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        return try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record, publicKey: publicKey, usernames: ["synthetic", "synthetic-second"]))), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in
                    record.opened(child)
                    return child.pipeline.addHandler(FilesTestSFTPProcess(root: root, allowSFTP: allowSFTP, responseDelay: responseDelay))
                }))
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func testNamedKeyFilesLoginRetainsAccountForFreshFilesAndTerminal() async throws {
        let storageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let library = try TerminalKeyLibraryStore.load()
        defer { try? TerminalSecretStore.write(JSONEncoder().encode(library), id: storageID, kind: "key-library-v2") }
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let key = TerminalSSHKey.create(), record = SSHTestRecord()
        let publicKey = NIOSSHPrivateKey(ed25519Key: try .init(rawRepresentation: key.seed)).publicKey
        let server = try await self.server(root: root, record: record, publicKey: publicKey)
        defer { Task { try? await server.close() } }
        let id = try TerminalKeyLibraryStore.add(key, name: "Synthetic Files Key")
        for priorAccount in ["", "old-account"] {
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Named Key", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            try TerminalKeyLibraryStore.associate(id, macID: mac.id, username: priorAccount)
            let selected = try XCTUnwrap(TerminalKeyLibraryStore.selected(mac.id))
            let session = DirectFilesSession(mac: mac)
            defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
            session.connect(username: "synthetic", password: "", key: selected.key, remember: false)
            try await wait { session.trust != nil }; session.answerTrust(true)
            try await wait { session.phase != .connecting }
            XCTAssertEqual(session.phase, .ready, session.message ?? session.status)
            let saved = try XCTUnwrap(TerminalKeyLibraryStore.selected(mac.id))
            XCTAssertEqual(saved.id, id); XCTAssertEqual(saved.key.username, "synthetic")
            XCTAssertEqual(saved.name, "Synthetic Files Key"); XCTAssertEqual(saved.key.seed, key.seed)
            var terminalLogin = TerminalLoginSelection()
            terminalLogin.loadKeyAccount(saved.key.username, preferSelected: true)
            XCTAssertEqual(terminalLogin.method, .sshKey); XCTAssertEqual(terminalLogin.username, "synthetic")
            var expectedAccount = "synthetic"
            if priorAccount.isEmpty {
                // A continuously mounted view may still hold its original key
                // value, whose account predates the first successful login.
                session.disconnect()
                session.connect(username: "synthetic-second", password: "", key: selected.key, remember: false)
                try await wait { session.phase != .connecting }
                XCTAssertEqual(session.phase, .ready, session.message ?? session.status)
                expectedAccount = "synthetic-second"
                XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.key.username, expectedAccount)
            }
            session.close()
            let reopened = DirectFilesSession(mac: mac); defer { reopened.close() }
            let host = NSHostingView(rootView: DirectFilesView(mac: mac, session: reopened))
            let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
            try await wait { fields()?.account.stringValue == expectedAccount }
            XCTAssertTrue(fields()?.secret.isHiddenOrHasHiddenAncestor == true, "Key login must not become password login")
        }
        XCTAssertGreaterThanOrEqual(record.keyRequests, 2)
    }
    func testNamedKeyFilesLoginPreservesRejectionAndConcurrentSelectionChanges() async throws {
        let storageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let library = try TerminalKeyLibraryStore.load()
        defer { try? TerminalSecretStore.write(JSONEncoder().encode(library), id: storageID, kind: "key-library-v2") }
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let key = TerminalSSHKey.create()
        let publicKey = NIOSSHPrivateKey(ed25519Key: try .init(rawRepresentation: key.seed)).publicKey
        let server = try await self.server(root: root, record: SSHTestRecord(), publicKey: publicKey)
        defer { Task { try? await server.close() } }
        for change in ["rejected", "key", "account", "deleted"] {
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Pending Key", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let id = try TerminalKeyLibraryStore.add(key, name: "Synthetic Pending Key")
            try TerminalKeyLibraryStore.associate(id, macID: mac.id, username: "")
            let selected = try XCTUnwrap(TerminalKeyLibraryStore.selected(mac.id))
            let session = DirectFilesSession(mac: mac)
            defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
            session.connect(username: change == "rejected" ? "rejected-synthetic" : "synthetic", password: "", key: selected.key, remember: false)
            try await wait { session.trust != nil }
            if change == "key" {
                let newer = try TerminalKeyLibraryStore.add(.create(), name: "Synthetic Newer Key")
                try TerminalKeyLibraryStore.associate(newer, macID: mac.id, username: "newer-account")
            } else if change == "account" {
                try TerminalKeyLibraryStore.associate(id, macID: mac.id, username: "newer-account")
            } else if change == "deleted" { try TerminalKeyLibraryStore.delete(id) }
            let before = try TerminalKeyLibraryStore.load()
            session.answerTrust(true); try await wait { session.phase != .connecting }
            if change == "rejected" { XCTAssertNotEqual(session.phase, .ready) }
            else { XCTAssertEqual(session.phase, .ready, session.message ?? session.status) }
            let current = try TerminalKeyLibraryStore.selected(mac.id)
            XCTAssertEqual(current?.key.username, change == "deleted" ? nil : change == "rejected" ? "" : "newer-account")
            XCTAssertEqual(try TerminalKeyLibraryStore.load().keys, before.keys)
        }
    }
    func testIndexedDiskKeyFilesLoginPreservesConcurrentAccountAndSelectionEdits() async throws {
        try await checkDiskKeyAccountRetention(terminal: false)
    }
    func testIndexedDiskKeyTerminalLoginPreservesConcurrentAccountAndSelectionEdits() async throws {
        try await checkDiskKeyAccountRetention(terminal: true)
    }
    private func checkDiskKeyAccountRetention(terminal useTerminal: Bool) async throws {
        struct Fixture: Decodable {
            struct Case: Decodable {
                let id: String
                let priorAccount: String
                let change: String
                let login: String
                let expectedAccount: String?
            }
            let diskKeyAccountCases: [Case]
        }
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let cases = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL)).diskKeyAccountCases
        let namedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let named = try TerminalKeyLibraryStore.load(), original = try MacSSHKeyFileStore.load()
        defer {
            try? TerminalSecretStore.write(JSONEncoder().encode(named), id: namedID, kind: "key-library-v2")
            try? TerminalSecretStore.write(JSONEncoder().encode(original), id: MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind)
        }
        try TerminalSecretStore.write(JSONEncoder().encode(TerminalKeyLibraryStore.Library()), id: namedID, kind: "key-library-v2")
        func save(_ library: MacSSHKeyFileStore.Library) throws {
            try TerminalSecretStore.write(JSONEncoder().encode(library), id: MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind)
        }
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        for item in cases {
            let key = TerminalSSHKey.create(), record = SSHTestRecord()
            let publicKey = NIOSSHPrivateKey(ed25519Key: try .init(rawRepresentation: key.seed)).publicKey
            let server: Channel
            if useTerminal {
                let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
                server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
                    record.openedTransport(channel)
                    return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record, publicKey: publicKey, usernames: ["synthetic", "synthetic-second"]))), allocator: channel.allocator,
                        inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
                }.bind(host: "127.0.0.1", port: 0).get()
            } else { server = try await self.server(root: root, record: record, publicKey: publicKey) }
            defer { Task { try? await server.close() } }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Disk Key", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            // No private-key bytes or actual security-scoped bookmarks are stored.
            // Existing disk-reader tests cover resolving and parsing real key files.
            let file = MacSSHKeyFileReference(id: UUID(), name: "Synthetic Reference", bookmark: Data([1]), fingerprint: key.fingerprint)
            let newer = MacSSHKeyFileReference(id: UUID(), name: "Synthetic Newer Reference", bookmark: Data([2]), fingerprint: TerminalSSHKey.create().fingerprint)
            var library = MacSSHKeyFileStore.Library(files: [file, newer], associations: [.init(macID: mac.id, keyID: file.id, username: item.priorAccount)])
            try save(library)
            let files = useTerminal ? nil : DirectFilesSession(mac: mac)
            let terminal = useTerminal ? DirectTerminalSession(mac: mac) : nil
            func start(_ username: String) {
                files?.connect(username: username, password: "", key: key, remember: false, keyFileID: file.id)
                terminal?.connect(username: username, password: "", remember: false, key: key, keyFileID: file.id)
            }
            func stop() { files?.disconnect(); terminal?.stop() }
            func connecting() -> Bool { files.map { $0.phase == .connecting } ?? terminal!.connecting }
            func ready() -> Bool { files.map { $0.phase == .ready } ?? terminal!.connected }
            defer { files?.close(); terminal?.stop(); try? TerminalSecretStore.remove(mac.id) }
            start(item.login == "rejected" ? "rejected-synthetic" : "synthetic")
            try await wait { files?.trust != nil || terminal?.trust != nil || !connecting() }
            XCTAssertTrue(files?.trust != nil || terminal?.trust != nil, item.id)
            XCTAssertEqual(record.keyRequests, 0, "Changes occur before authentication: \(item.id)")
            switch item.change {
            case "account": library.associations[0].username = "newer-account"
            case "key": library.associations[0] = .init(macID: mac.id, keyID: newer.id, username: "newer-account")
            case "reference": library.files[0].bookmark = Data([3])
            case "association": library.associations = []
            case "delete": library.files.removeAll { $0.id == file.id }; library.associations = []
            default: break
            }
            try save(library)
            if item.login == "cancelled" { files?.disconnect(); terminal?.cancelConnection() }
            else { files?.answerTrust(true); terminal?.answerTrust(true) }
            try await wait { !connecting() }
            XCTAssertEqual(ready(), item.login != "rejected" && item.login != "cancelled", item.id)
            if item.login == "repeated" {
                XCTAssertEqual(try MacSSHKeyFileStore.selected(mac.id)?.username, "synthetic", item.id)
                stop(); start("synthetic-second"); try await wait { !connecting() }
                XCTAssertTrue(ready(), item.id)
            }
            let saved = try MacSSHKeyFileStore.load()
            XCTAssertEqual(try MacSSHKeyFileStore.selected(mac.id)?.username, item.expectedAccount, item.id)
            XCTAssertEqual(saved.files, library.files, "Retention never rewrites or recreates references: \(item.id)")
            XCTAssertEqual(saved.associations.map(\.keyID), library.associations.map(\.keyID), item.id)
            XCTAssertTrue(try TerminalKeyLibraryStore.load().keys.isEmpty, "Disk login must not import private key material: \(item.id)")
            XCTAssertNil(try TerminalSecretStore.sshKey(mac.id), item.id)
        }
    }
    func testMacOSSFTPBrowseFolderUploadKeepBothReplaceDownloadAndIsolation() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let first = DirectFilesSession(mac: mac), second = DirectFilesSession(mac: mac)
        defer { first.close(); second.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(first); try await open(second)
        let home = try XCTUnwrap(first.directory?.path)
        XCTAssertEqual(URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
        first.createFolder("Uploads"); try await wait { !first.busy }
        XCTAssertTrue(first.directory?.entries.contains { $0.name == "Uploads" && $0.kind == .folder } == true)
        let folder = try DirectFilesPolicy.child("Uploads", of: home)
        first.browse(folder); try await wait { !first.busy }; XCTAssertEqual(first.directory?.path, folder)
        try await captureBrowser(first, name: "mac-files-empty-folder")
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "report.txt")
        let original = Data((0..<100_000).map { UInt8($0 % 251) }); try original.write(to: source)
        first.upload([source], to: folder); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed, first.results.first?.message ?? "")
        let remote = URL(fileURLWithPath: folder).appendingPathComponent("report.txt")
        XCTAssertEqual(try Data(contentsOf: remote), original)
        try await captureBrowser(first, name: "mac-files-upload-completed")
        let changed = Data(repeating: 7, count: 70_000); try changed.write(to: source)
        first.upload([source], to: folder); try await wait { first.conflict != nil }; first.answerConflict(.keepBoth); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed)
        XCTAssertEqual(first.results.first?.destinationName, "report (2).txt")
        XCTAssertEqual(try Data(contentsOf: remote), original)
        XCTAssertEqual(try Data(contentsOf: remote.deletingLastPathComponent().appendingPathComponent("report (2).txt")), changed)
        first.upload([source], to: folder); try await wait { first.conflict != nil }; first.answerConflict(.replace); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed, first.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: remote), changed)
        let entry = try XCTUnwrap(first.directory?.entries.first { $0.name == "report.txt" })
        first.download(entry); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed)
        let downloaded = try XCTUnwrap(first.results.first?.localDownload)
        XCTAssertEqual(try Data(contentsOf: downloaded), changed)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder).contains { $0.hasPrefix(".maccompanion-upload-") })
        first.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
        second.browse(home); try await wait { !second.busy }; XCTAssertEqual(second.phase, .ready)
    }
    private func captureBrowser(_ session: DirectFilesSession, name: String) async throws {
        let host = NSHostingView(rootView: DirectFilesView(mac: session.mac, session: session, retainWhenDismissed: true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPreparedUploadOwnershipRollsBackCancelsSupersedesAndPreservesAdoptedResults() async throws {
        let remote = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: remote); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: remote, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Preparation", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "prepared.txt")
        let bytes = Data(repeating: 29, count: 100_000); try bytes.write(to: source)
        let first = try await session.prepare([source])
        let ownerRoot = try XCTUnwrap(first.first).deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(session.preparedUploads, first)
        session.discardPreparedUploads() // The upload-review Cancel action.
        XCTAssertFalse(FileManager.default.fileExists(atPath: first[0].path))
        do { _ = try await session.prepare([source, source.deletingLastPathComponent()]); XCTFail("A rejected second item must roll back the first") } catch {}
        XCTAssertTrue(session.preparedUploads.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: ownerRoot.path).isEmpty)
        let replaced = try await session.prepare([source]), current = try await session.prepare([source])
        XCTAssertFalse(FileManager.default.fileExists(atPath: replaced[0].path))
        session.discardPreparedUploads(replaced) // A stale UI completion cannot discard the newer batch.
        XCTAssertEqual(session.preparedUploads, current)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current[0].path))
        session.disconnect()
        XCTAssertTrue(session.preparedUploads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current[0].path))
        try await open(session)
        let pending = Task { try await session.prepare([source]) }
        await Task.yield(); session.disconnect()
        _ = await pending.result
        XCTAssertTrue(session.preparedUploads.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: ownerRoot.path).isEmpty, "Retired preparations cannot leave copies after completion")
        try await open(session)
        let adopted = try await session.prepare([source])
        session.upload(adopted, to: session.home); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed)
        XCTAssertTrue(session.preparedUploads.isEmpty)
        session.discardPreparedUploads(); session.disconnect()
        XCTAssertTrue(FileManager.default.fileExists(atPath: adopted[0].path), "Transfer results retain adopted sources")
        XCTAssertEqual(try Data(contentsOf: source), bytes, "Picker originals are never removed")
        session.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: adopted[0].path))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testKeepBothWithFullLengthFilenamePreservesOriginalAndPublishesDuplicate() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let name = String(repeating: "a", count: 251) + ".txt", original = Data([9]), changed = Data([1, 2, 3])
        try original.write(to: root.appendingPathComponent(name))
        let source = local.appendingPathComponent(name); try changed.write(to: source)
        let server = try await self.server(root: root, record: SSHTestRecord()); defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Long Name", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        session.upload([source], to: session.home)
        try await wait { session.conflict != nil }; session.answerConflict(.keepBoth); try await wait { !session.busy }
        let duplicate = String(repeating: "a", count: 247) + " (2).txt"
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(session.results.first?.destinationName, duplicate)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(duplicate)), changed)
    }
    func testEmptyReplacementUploadAtEncoderCapacityBoundary() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: root, record: SSHTestRecord()); defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Boundary", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.forgetHostKey(mac.id) }
        try await open(session)
        let temporaryName = ".maccompanion-upload-" + UUID().uuidString + ".part"
        let oldPathBytes = 256 - (4 + 1 + 4 + 4 + "posix-rename@openssh.com".utf8.count + 4)
        let folderBytes = oldPathBytes - 1 - temporaryName.utf8.count
        let padding = folderBytes - session.home.utf8.count - 1
        XCTAssertGreaterThan(padding, 0)
        guard padding > 0 else { throw DirectFilesFailure.invalidPath }
        session.createFolder(String(repeating: "a", count: padding)); try await wait { !session.busy }
        let folder = try DirectFilesPolicy.child(String(repeating: "a", count: padding), of: session.home)
        XCTAssertEqual(folder.utf8.count, folderBytes)
        let destination = URL(fileURLWithPath: folder).appendingPathComponent("empty.txt")
        try Data([9]).write(to: destination)
        session.browse(folder); try await wait { !session.busy }
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "empty.txt")
        session.upload([source], to: folder); try await wait { session.conflict != nil }
        session.answerConflict(.replace); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: destination), Data())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder).contains { $0.hasPrefix(".maccompanion-upload-") })
    }
    func testMountedFilesOwnerRetainsDownloadAfterLocalAndSyncedRecordRemoval() async throws {
        for synced in [false, true] {
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let bytes = Data([1, 2, 3]); try bytes.write(to: root.appendingPathComponent("pending.txt"))
            let server = try await self.server(root: root, record: SSHTestRecord()); defer { Task { try? await server.close() } }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Removed Mac", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let library = DirectMacLibraryV1(url: root.appendingPathComponent("library.json"), removeLogin: { _ in })
            XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort))
            let owner = DirectFilesSession(mac: mac); defer { owner.close(); try? TerminalSecretStore.remove(mac.id) }
            try await open(owner)
            owner.download(try XCTUnwrap(owner.directory?.entries.first { $0.name == "pending.txt" })); try await wait { !owner.busy }
            let download = try XCTUnwrap(owner.results.first?.localDownload)
            let host = NSHostingView(rootView: FilesTestWindowRoot(library: library, owner: owner))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
            if synced { try library.applyCloud([]) } else { library.remove(mac) }
            XCTAssertTrue(library.macs.isEmpty)
            try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
            XCTAssertEqual(owner.phase, .ready)
            XCTAssertTrue(owner.hasPendingResults)
            XCTAssertEqual(owner.mac.name, mac.name)
            XCTAssertEqual(try Data(contentsOf: download), bytes)
            // Only an explicit confirmed close releases this owner's result.
            XCTAssertTrue(owner.confirmExit(.close, retainWhenDismissed: false))
            XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
        }
        var admissions = 0
        _ = MacFilesWindow(mac: nil, makeSession: { record in admissions += 1; return DirectFilesSession(mac: record) })
        XCTAssertEqual(admissions, 0, "A missing-at-open record must not create an owner")
    }
    func testSFTPSubsystemClosureRequiresReconnectAndPreservesPendingDownload() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([3, 2, 1]); try bytes.write(to: root.appendingPathComponent("pending.txt"))
        let record = SSHTestRecord(), server = try await self.server(root: root, record: record)
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic SFTP Closure", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        session.download(try XCTUnwrap(session.directory?.entries.first { $0.name == "pending.txt" })); try await wait { !session.busy }
        let download = try XCTUnwrap(session.results.first?.localDownload)
        XCTAssertTrue(record.transportIsActive)
        // Closes only the SSH child subsystem, never its parent transport.
        try await record.finish(status: nil)
        try await wait { session.phase == .interrupted }
        XCTAssertFalse(session.busy); XCTAssertTrue(session.hasPendingResults)
        XCTAssertEqual(try Data(contentsOf: download), bytes)
        XCTAssertTrue(session.message?.contains("Reconnect") == true)
        XCTAssertEqual(record.passwordRequests, 1, "No automatic reconnect")
        try await open(session)
        XCTAssertEqual(record.passwordRequests, 2)
        XCTAssertTrue(session.hasPendingResults)
        XCTAssertEqual(try Data(contentsOf: download), bytes)
    }
    func testInterruptionRequiresExplicitReconnectAndRetryWithNoAutomaticReplay() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "interrupted.txt")
        let bytes = Data(repeating: 8, count: 300_000); try bytes.write(to: source)
        let folder = session.home
        let staged = try await session.prepare([source])
        var stopped = false, dismissRequested = true
        session.activityChanged = { [weak session] _ in
            if !stopped, (session?.results.first?.bytes ?? 0) > 0 {
                stopped = true; dismissRequested = session?.confirmExit(.disconnect, retainWhenDismissed: false) ?? true
            }
        }
        session.upload(staged, to: folder); try await wait { stopped && !session.busy }
        XCTAssertFalse(dismissRequested); XCTAssertTrue(FileManager.default.fileExists(atPath: staged[0].path))
        XCTAssertEqual(session.results.first?.outcome, .interrupted)
        let destination = URL(fileURLWithPath: folder).appendingPathComponent("interrupted.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        session.activityChanged = nil
        session.connect(username: "synthetic-second", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.phase != .connecting }
        XCTAssertEqual(session.phase, .ready)
        let resultID = try XCTUnwrap(session.results.first?.id)
        session.upload([source], to: folder)
        session.download(.init(name: "another.txt", kind: .file, size: 1))
        XCTAssertEqual(session.results.first?.id, resultID); XCTAssertFalse(session.busy)
        session.retry(try XCTUnwrap(session.results.first?.id))
        XCTAssertFalse(session.busy); XCTAssertEqual(session.results.first?.outcome, .interrupted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "A retry cannot change accounts")
        session.disconnect()
        try await open(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.results.first?.outcome, .interrupted)
        session.retry(try XCTUnwrap(session.results.first?.id)); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        session.discardResults()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testPendingDownloadsRequireSaveOrDiscardBeforeNewTransfers() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let remoteA = root.appendingPathComponent("a.txt"), remoteB = root.appendingPathComponent("b.txt")
        try Data([1]).write(to: remoteA); try Data([2]).write(to: remoteB)
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let a = try XCTUnwrap(session.directory?.entries.first { $0.name == "a.txt" })
        let b = try XCTUnwrap(session.directory?.entries.first { $0.name == "b.txt" })
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "upload.txt"); try Data([3]).write(to: source)
        session.download(a); try await wait { !session.busy }
        let id = try XCTUnwrap(session.results.first?.id), download = try XCTUnwrap(session.results.first?.localDownload)
        XCTAssertTrue(session.hasPendingResults); XCTAssertTrue(session.hasUnsavedDownloads)
        session.download(b); session.upload([source], to: session.home)
        XCTAssertEqual(session.results.first?.id, id); XCTAssertEqual(try Data(contentsOf: download), Data([1]))
        XCTAssertFalse(session.busy)
        do { _ = try await session.prepare([source]); XCTFail("Pending downloads must survive upload preparation") } catch {}
        XCTAssertEqual(session.results.first?.id, id)
        session.discardResults()
        XCTAssertTrue(session.results.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
        XCTAssertEqual(try Data(contentsOf: remoteA), Data([1]))
        session.download(b); try await wait { !session.busy }
        let secondID = try XCTUnwrap(session.results.first?.id), secondDownload = try XCTUnwrap(session.results.first?.localDownload)
        let exported = local.appendingPathComponent("exported.txt"); try FileManager.default.copyItem(at: secondDownload, to: exported)
        session.markSaved(secondID); XCTAssertFalse(session.hasPendingResults)
        let staged = try await session.prepare([source])
        session.upload(staged, to: session.home); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("upload.txt")), Data([3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDownload.path))
        XCTAssertEqual(try Data(contentsOf: exported), Data([2])); XCTAssertEqual(try Data(contentsOf: source), Data([3]))
        XCTAssertFalse(session.confirmExit(.close, retainWhenDismissed: true))
        XCTAssertTrue(session.confirmExit(.close, retainWhenDismissed: false))
    }
    func testFilesUnsavedPasswordRemovesPreviousLoginButPreservesHostTrust() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try TerminalSecretStore.save(.init(username: "old-synthetic", password: "old-synthetic"), id: mac.id)
        try await open(session); XCTAssertNil(try TerminalSecretStore.login(mac.id))
        let pin = try XCTUnwrap(TerminalSecretStore.hostKey(mac.id)); session.disconnect()
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        try await wait { session.phase != .connecting }; XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "synthetic-only")
        session.disconnect(); try await open(session)
        XCTAssertNil(try TerminalSecretStore.login(mac.id)); XCTAssertEqual(try TerminalSecretStore.hostKey(mac.id), pin)
    }
    func testConfirmedCloseReleasesPendingDownloadAndNativeDismissalProtection() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("pending.txt"))
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Pending Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        session.download(try XCTUnwrap(session.directory?.entries.first { $0.name == "pending.txt" }))
        try await wait { !session.busy }
        let download = try XCTUnwrap(session.results.first?.localDownload)
        XCTAssertTrue(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults))
        XCTAssertFalse(session.confirmExit(.close, retainWhenDismissed: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: download.path)); XCTAssertTrue(session.hasPendingResults)
        XCTAssertTrue(session.confirmExit(.close, retainWhenDismissed: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.path)); XCTAssertFalse(session.hasPendingResults)
        XCTAssertFalse(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("pending.txt").path))
    }
    func testProgressingSFTPListingOutlastsIdleDeadlineAndStalledResponseTimesOut() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<512 { try Data().write(to: root.appendingPathComponent("file-\(index).txt")) }
        let server = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .milliseconds(200))
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac, idleTimeout: .milliseconds(900))
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let began = ContinuousClock.now
        session.browse(session.home); try await wait { !session.busy }
        XCTAssertGreaterThan(began.duration(to: .now), .milliseconds(900))
        XCTAssertEqual(session.phase, .ready, session.message ?? ""); XCTAssertEqual(session.directory?.entries.count, 512)
        session.disconnect()
        let stalledServer = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .seconds(2))
        defer { Task { try? await stalledServer.close() } }
        let stalledMac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(stalledServer.localAddress?.port))
        let stalled = DirectFilesSession(mac: stalledMac, idleTimeout: .milliseconds(900))
        defer { stalled.close(); try? TerminalSecretStore.remove(stalledMac.id) }
        stalled.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { stalled.trust != nil || stalled.phase != .connecting }; stalled.answerTrust(true)
        try await wait { stalled.phase != .connecting }
        XCTAssertEqual(stalled.phase, .interrupted); XCTAssertTrue(stalled.message?.contains("stopped responding") == true)
    }
    func testSFTPAdmissionAndMissingUploadDestinationEachResetIdleDeadline() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        // Every response is within the idle budget; VERSION + REALPATH, and
        // missing-destination LSTAT + OPEN, each exceed it if activity is lost.
        let server = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .milliseconds(600))
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Slow Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac, idleTimeout: .milliseconds(1000))
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "new.txt"), bytes = Data([1, 2, 3])
        try bytes.write(to: source)
        session.upload([source], to: session.home); try await wait({ !session.busy }, seconds: 20)
        XCTAssertEqual(session.phase, .ready, session.message ?? "")
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("new.txt")), bytes)
    }
    func testCachedRegularFileChangedToSymlinkIsRejectedBeforeDownloadingTarget() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected.txt"), target = root.appendingPathComponent("target.txt")
        try Data([1]).write(to: selected); try Data([2]).write(to: target)
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let stale = try XCTUnwrap(session.directory?.entries.first { $0.name == "selected.txt" })
        XCTAssertEqual(stale.kind, .file)
        try FileManager.default.removeItem(at: selected); try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: target)
        session.download(stale); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .interrupted); XCTAssertNil(session.results.first?.localDownload)
        XCTAssertEqual(session.results.first?.message, DirectFilesFailure.notRegular.localizedDescription)
        XCTAssertEqual(try Data(contentsOf: target), Data([2]))
    }
    func testLifecycleStopsHiddenOwnerAndChangedHostPinRejectsBeforeAuthentication() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SSHTestRecord(), server = try await self.server(root: root, record: record)
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let access = FilesTestAccess()
        let session = DirectFilesSession(mac: mac, canAccess: { access.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        access.allowed = false; try await wait { session.phase == .interrupted }
        access.allowed = true
        XCTAssertEqual(session.phase, .interrupted, "Unlock must not reconnect automatically")
        try await open(session)
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        XCTAssertEqual(session.phase, .interrupted)
        try await open(session)
        session.disconnect()
        let replacementRecord = SSHTestRecord(), replacement = try await self.server(root: root, record: replacementRecord)
        defer { Task { try? await replacement.close() } }
        let changedMac = DirectMacRecordV1(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: try XCTUnwrap(replacement.localAddress?.port))
        let changed = DirectFilesSession(mac: changedMac); defer { changed.close() }
        changed.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { changed.phase != .connecting }
        XCTAssertEqual(changed.phase, .interrupted)
        XCTAssertTrue(changed.message?.contains("identity changed") == true, changed.message ?? "")
        XCTAssertNil(changed.trust); XCTAssertEqual(replacementRecord.passwordRequests, 0)
    }
    func testConcurrentFirstUseApprovalsPreserveWinningPinBeforeAuthentication() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let firstRecord = SSHTestRecord(), secondRecord = SSHTestRecord()
        let firstServer = try await server(root: root, record: firstRecord)
        let secondServer = try await server(root: root, record: secondRecord)
        defer { Task { try? await firstServer.close(); try? await secondServer.close() } }
        let firstMac = DirectMacRecordV1(id: UUID(), name: "Synthetic Competing Trust", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(firstServer.localAddress?.port))
        var secondMac = firstMac; secondMac.sshPort = try XCTUnwrap(secondServer.localAddress?.port)
        let first = DirectFilesSession(mac: firstMac), second = DirectFilesSession(mac: secondMac)
        defer { first.close(); second.close(); try? TerminalSecretStore.remove(firstMac.id) }
        first.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        second.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { first.trust != nil && second.trust != nil }
        XCTAssertNotEqual(first.trust?.fingerprint, second.trust?.fingerprint)
        second.answerTrust(true); try await wait { second.phase != .connecting }
        XCTAssertEqual(second.phase, .ready, second.message ?? "")
        let pin = try XCTUnwrap(TerminalSecretStore.hostKey(firstMac.id))
        first.answerTrust(true); try await wait { first.phase != .connecting }
        XCTAssertEqual(first.phase, .interrupted)
        XCTAssertTrue(first.message?.contains("identity changed") == true, first.message ?? "")
        XCTAssertEqual(firstRecord.passwordRequests, 0, "A superseded approval must fail before sending credentials")
        XCTAssertEqual(try TerminalSecretStore.hostKey(firstMac.id), pin)
        XCTAssertEqual(second.phase, .ready, "A rejected competing approval must not disconnect the trusted owner")
    }
    func testSFTPOpenAfterAuthenticatedSSHClosureFailsWithoutLeakingPromises() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port),
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        try await client.close()
        let began = ContinuousClock.now
        do { _ = try await client.openSFTP(); XCTFail("A closed SSH transport must not open SFTP") }
        catch { XCTAssertLessThan(began.duration(to: .now), .seconds(5), "Channel creation failure must finish without awaiting the admission timeout") }
        // A second attempt also releases the creation state on the event loop.
        do { _ = try await client.openSFTP(); XCTFail("A closed SSH transport must stay closed") } catch {}
    }
    func testReopenedConnectedFilesInitializesSavedLoginOnceAfterDisconnect() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Retained Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        try await wait { session.trust != nil }; session.answerTrust(true)
        try await wait { session.phase != .connecting }; XCTAssertEqual(session.phase, .ready)
        // Reopening UIKit's retained sheet creates an entirely new view. Mount
        // that shared SwiftUI view while its existing owner is still Ready.
        let host = NSHostingView(rootView: DirectFilesView(mac: mac, session: session, retainWhenDismissed: true))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        XCTAssertNil(fields(), "Reopening connected Files must preserve the browser")
        session.disconnect()
        try await wait { fields()?.account.stringValue == "synthetic" }
        let pair = try XCTUnwrap(fields()); XCTAssertEqual(pair.secret.stringValue, "synthetic-only")
        pair.account.stringValue = "synthetic-edited-account"; pair.secret.stringValue = "synthetic-edited-password"
        // Subsequent sign-in transitions preserve an already initialized draft.
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true); session.disconnect()
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        XCTAssertEqual(fields()?.account.stringValue, "synthetic-edited-account")
        XCTAssertEqual(fields()?.secret.stringValue, "synthetic-edited-password")
    }
    func testRejectedLoginAndUnavailableSFTPHaveSeparateGuidance() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord(), allowSFTP: false)
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "incorrect-synthetic", key: nil, remember: false)
        try await wait { session.trust != nil || session.phase != .connecting }
        session.answerTrust(true); try await wait { session.phase != .connecting }
        XCTAssertTrue(session.message?.contains("did not accept") == true, session.message ?? "")
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.phase != .connecting }
        XCTAssertTrue(session.message?.contains("SSH connected, but Files") == true, session.message ?? "")
        XCTAssertFalse(session.message?.contains("did not accept") == true)
    }
}
