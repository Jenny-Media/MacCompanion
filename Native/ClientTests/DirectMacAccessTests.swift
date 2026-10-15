#if os(iOS)
import XCTest
import Security
import NIO
@preconcurrency @testable import Citadel
@testable import Mac_Companion

@MainActor final class DirectMacAccessTests: XCTestCase {
    func testIndexedMigrationPreservesSharedAndDifferentCredentials() throws {
        struct Row: Decodable { let id: String; let desktop: [String]?; let ssh: [String]?; let key: Bool; let `default`: [String]?; let override: String }
        struct Cases: Decodable { let migrationCases: [Row] }
        struct Fixture: Decodable { let iosSharedAccess: Cases }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).iosSharedAccess.migrationCases
        for row in rows {
            func login(_ fields: [String]?) -> DirectMacAccessProfile.Password? { fields.map { .init(username: $0[0], password: $0[1]) } }
            let key = row.key ? TerminalNamedKey(id: UUID(), name: "Synthetic Key", key: .init(seed: Data(repeating: 7, count: 32), username: "synthetic-key-account")) : nil
            let value = DirectMacAccessProfile.migrated(desktop: login(row.desktop), ssh: login(row.ssh), key: key)
            XCTAssertEqual(value.login, login(row.default), row.id)
            XCTAssertEqual(value.sshMethod.rawValue, row.override, row.id)
            if row.ssh != row.default { XCTAssertEqual(value.sshPassword, login(row.ssh), "A selected key must not discard a different saved password") }
            if let key { XCTAssertEqual(value.keyID, key.id); XCTAssertEqual(value.keyUsername, key.key.username) }
            XCTAssertEqual(try JSONDecoder().decode(DirectMacAccessProfile.self, from: JSONEncoder().encode(value)), value)
        }
    }
    func testMigrationFailureNeverCleansLegacyAndCanonicalEmptyNeverFallsBack() throws {
        enum Failure: Error { case test }
        let original = DirectMacAccessProfile(login: .init(username: "synthetic", password: "synthetic-only"))
        var bytes: Data?, clean = 0, legacyReads = 0
        var repository = DirectMacAccessStore.Repository(read: { bytes }, write: { bytes = $0 }, legacy: { legacyReads += 1; return original }, clean: { clean += 1 })
        repository.write = { _ in throw Failure.test }
        XCTAssertThrowsError(try repository.load()); XCTAssertEqual(clean, 0); XCTAssertNil(bytes)
        repository.write = { _ in }
        XCTAssertThrowsError(try repository.load()); XCTAssertEqual(clean, 0)
        repository.write = { bytes = $0 }
        XCTAssertEqual(try repository.load(), original); XCTAssertEqual(clean, 1)
        bytes = try JSONEncoder().encode(DirectMacAccessProfile())
        let before = legacyReads
        XCTAssertNil(try repository.load().login); XCTAssertEqual(legacyReads, before)
        bytes = Data([0xff])
        XCTAssertThrowsError(try repository.load()); XCTAssertEqual(legacyReads, before); XCTAssertEqual(clean, 1)
    }
    func testReadFailureAndCleanupFailurePreserveAuthority() throws {
        enum Failure: Error { case test }
        var reads = 0, clean = 0, bytes: Data?
        let value = DirectMacAccessProfile(login: .init(username: "synthetic", password: "synthetic-only"))
        let failed = DirectMacAccessStore.Repository(read: { throw Failure.test }, write: { _ in XCTFail("Must not write after failed read") }, legacy: { reads += 1; return value }, clean: { clean += 1 })
        XCTAssertThrowsError(try failed.load()); XCTAssertEqual(reads, 0); XCTAssertEqual(clean, 0)
        let repository = DirectMacAccessStore.Repository(read: { bytes }, write: { bytes = $0 }, legacy: { reads += 1; return value }, clean: { clean += 1; throw Failure.test })
        XCTAssertEqual(try repository.load(), value); XCTAssertEqual(try repository.load(), value)
        XCTAssertEqual(reads, 1); XCTAssertEqual(clean, 1)
    }
    func testIndexedActivityAndDisconnectAreScopedToTheMacAndWaitForTeardown() async throws {
        let registry = DirectMacConnections(), mac = UUID(), other = UUID(), key = UUID()
        var first: UUID?, second: UUID?, disconnected = 0
        first = registry.begin(macID: mac, kind: "desktop", keyID: key) {
            disconnected += 1
            Task { try? await Task.sleep(for: .milliseconds(100)); registry.end(first) }
        }
        second = registry.begin(macID: other, kind: "terminal") { XCTFail("Unrelated Mac must remain connected") }
        XCTAssertTrue(registry.isActive(mac)); XCTAssertTrue(registry.keyInUse(key))
        let finished = await registry.disconnect(mac)
        XCTAssertTrue(finished); XCTAssertEqual(disconnected, 1); XCTAssertFalse(registry.isActive(mac))
        XCTAssertTrue(registry.isActive(other)); XCTAssertFalse(registry.keyInUse(key)); registry.end(second)
        struct Row: Decodable { let owners: [String]; let editable: Bool }
        struct Cases: Decodable { let activityCases: [Row] }
        struct Fixture: Decodable { let iosSharedAccess: Cases }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        for row in try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).iosSharedAccess.activityCases {
            let tokens = row.owners.map { registry.begin(macID: mac, kind: $0, disconnect: {}) }
            XCTAssertEqual(!registry.isActive(mac), row.editable)
            tokens.forEach { registry.end($0) }
        }
    }
    func testManagementCommitRejectsActiveConnectionsAndStaleDrafts() throws {
        let mac = UUID(); defer { removeFixtureProfile(mac) }
        let original = try DirectMacAccessStore.load(mac)
        var changed = original; changed.login = .init(username: "synthetic", password: "synthetic-only")
        let owner = DirectMacConnections.shared.begin(macID: mac, kind: "connecting", disconnect: {})
        XCTAssertThrowsError(try DirectMacAccessStore.save(changed, id: mac, replacing: original))
        XCTAssertEqual(try DirectMacAccessStore.load(mac), original)
        DirectMacConnections.shared.end(owner)
        try DirectMacAccessStore.save(changed, id: mac, replacing: original)
        XCTAssertThrowsError(try DirectMacAccessStore.save(original, id: mac, replacing: original))
        XCTAssertEqual(try DirectMacAccessStore.load(mac), changed)
    }
    func testBorrowedFilesUsesOneAuthenticationAndClosingItKeepsParentUsable() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Shared Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        defer { Task { try? await client.close() } }
        let files = DirectFilesSession(mac: mac), generation = UUID()
        defer { files.close() }
        let context = DirectFilesConnectionContext(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: generation)
        XCTAssertEqual(probe.authentications, 1)
        files.connectBorrowed(context)
        try await wait { !files.busy }
        XCTAssertEqual(files.phase, .ready, files.message ?? files.status)
        XCTAssertEqual(files.account, context.account); XCTAssertEqual(probe.authentications, 1)
        XCTAssertTrue(DirectMacConnections.shared.isActive(mac.id))
        files.connectBorrowed(context)
        XCTAssertEqual(files.phase, .ready); XCTAssertEqual(probe.authentications, 1)
        files.disconnect()
        try await wait { !DirectMacConnections.shared.isActive(mac.id) }
        // A fresh SFTP channel on the same connection proves Files did not close its parent.
        let next = try await client.openSFTP()
        _ = try await next.getRealPath(atPath: ".")
        try await next.close()
        XCTAssertEqual(probe.authentications, 1)
        files.connectBorrowed(context)
        try await wait { !files.busy }
        XCTAssertEqual(files.phase, .ready)
        files.disconnectBorrowed(UUID()); XCTAssertEqual(files.phase, .ready, "Another parent's closure must not retire this Files channel")
        files.disconnectBorrowed(generation); XCTAssertEqual(files.phase, .interrupted)
    }
    func testBorrowedFilesRejectsDifferentMacBeforeOpeningChannel() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port),
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        defer { Task { try? await client.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Context Boundary", addresses: ["127.0.0.1"])
        let files = DirectFilesSession(mac: mac); defer { files.close() }
        files.connectBorrowed(.init(client: client, macID: UUID(), account: "synthetic", keyID: nil, generation: UUID()))
        XCTAssertEqual(files.phase, .signIn); XCTAssertFalse(files.busy); XCTAssertFalse(DirectMacConnections.shared.isActive(mac.id))
    }
    func testEditingRequiresDisconnectEvenForSameOwnerAndOtherMacStaysEditable() throws {
        let mac = UUID(), other = UUID(), ownerID = UUID()
        defer { removeFixtureProfile(mac); removeFixtureProfile(other) }
        let login = DirectMacAccessProfile.Password(username: "synthetic", password: "synthetic-only")
        try DirectMacAccessStore.setMacLogin(login, id: mac)
        let draft = DirectMacAccessDraft(macID: mac); draft.load()
        let lease = DirectMacConnections.shared.begin(macID: mac, kind: "desktop", ownerID: ownerID, disconnect: {})
        defer { DirectMacConnections.shared.end(lease) }
        XCTAssertFalse(draft.editable)
        XCTAssertNoThrow(try DirectMacAccessStore.checkConnection(macID: mac, username: login.username, password: login.password, key: nil, ssh: false))
        XCTAssertThrowsError(try DirectMacAccessStore.checkConnection(macID: mac, username: login.username, password: "different", key: nil, ssh: false))
        draft.value.login?.username = "changed"
        XCTAssertFalse(draft.save())
        XCTAssertThrowsError(try DirectMacAccessStore.setMacLogin(nil, id: mac))
        XCTAssertNoThrow(try DirectMacAccessStore.setMacLogin(login, id: other))
        XCTAssertEqual(try DirectMacAccessStore.load(mac).login, login)
    }
    func testUnsavedOwnerCanReconnectWhileOtherOwnersCannotChangeItsIdentity() throws {
        let mac = UUID(), owner = UUID(); defer { removeFixtureProfile(mac) }
        _ = try DirectMacAccessStore.load(mac)
        let lease = DirectMacConnections.shared.begin(macID: mac, kind: "closing", ownerID: owner, disconnect: {})
        defer { DirectMacConnections.shared.end(lease) }
        XCTAssertNoThrow(try DirectMacAccessStore.checkConnection(macID: mac, username: "synthetic", password: "unsaved", key: nil, ssh: false, ownerID: owner))
        XCTAssertThrowsError(try DirectMacAccessStore.checkConnection(macID: mac, username: "synthetic", password: "another", key: nil, ssh: false))
        XCTAssertNoThrow(try DirectMacAccessStore.setMacLogin(nil, id: mac))
        XCTAssertTrue(DirectMacConnections.shared.isActive(mac), "The management editor still waits for teardown")
    }
    func testStandaloneMacLoginKeepsTheSeparateSSHOverrideUnchanged() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Default Files Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        defer { removeFixtureProfile(mac.id) }
        let initial = try DirectMacAccessStore.load(mac.id)
        var profile = initial
        profile.login = .init(username: "synthetic", password: "synthetic-only")
        profile.sshMethod = .password; profile.sshPassword = .init(username: "different-ssh-account", password: "synthetic-override")
        try DirectMacAccessStore.save(profile, id: mac.id, replacing: initial)
        let parent = DirectMacConnections.shared.begin(macID: mac.id, kind: "desktop", disconnect: {})
        defer { DirectMacConnections.shared.end(parent) }
        let files = DirectFilesSession(mac: mac); defer { files.close() }
        files.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true, useMacLogin: true)
        try await wait { files.trust != nil || !files.busy }
        XCTAssertNotNil(files.trust); files.answerTrust(true)
        try await wait { !files.busy }
        XCTAssertEqual(files.phase, .ready, files.message ?? files.status)
        XCTAssertEqual(try DirectMacAccessStore.load(mac.id), profile, "Successful Files access must not overwrite the different SSH account")
        XCTAssertEqual(files.account, "synthetic")
    }
    func testPendingLoginRetentionBlocksAuthenticationUsingTheOldSavedProfile() throws {
        let mac = UUID(); defer { removeFixtureProfile(mac) }
        try DirectMacAccessStore.setMacLogin(.init(username: "synthetic", password: "synthetic-old"), id: mac)
        let owner = DirectMacConnections.shared.begin(macID: mac, kind: "connecting", pendingAccessChange: true, disconnect: {})
        defer { DirectMacConnections.shared.end(owner) }
        XCTAssertThrowsError(try DirectMacAccessStore.checkConnection(macID: mac, username: "synthetic", password: "synthetic-old", key: nil, ssh: false))
        try DirectMacAccessStore.retain(.init(username: "synthetic", password: "synthetic-new"), macID: mac, ssh: false, owner: owner)
        XCTAssertNoThrow(try DirectMacAccessStore.checkConnection(macID: mac, username: "synthetic", password: "synthetic-new", key: nil, ssh: false))
        XCTAssertThrowsError(try DirectMacAccessStore.checkConnection(macID: mac, username: "synthetic", password: "synthetic-old", key: nil, ssh: false))
        XCTAssertTrue(DirectMacConnections.shared.isActive(mac), "Successful retention does not unlock management during the session")
    }
    func testCancelledBorrowedOpenKeepsTheEditGuardUntilItsChannelCloses() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe, responseDelay: .milliseconds(250))
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Pending SFTP", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        defer { Task { try? await client.close() } }
        let files = DirectFilesSession(mac: mac); defer { files.close() }
        files.connectBorrowed(.init(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: UUID()))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(files.busy)
        files.disconnect()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(DirectMacConnections.shared.isActive(mac.id), "A cancelled open is still a closing owner")
        try await wait { !DirectMacConnections.shared.isActive(mac.id) }
        let next = try await client.openSFTP(); try await next.close()
        XCTAssertEqual(probe.authentications, 1)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            guard Date() < deadline else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func removeFixtureProfile(_ id: UUID) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "media.jenny.maccompanion.ssh-" + DirectMacAccessStore.kind + ".v1",
            kSecAttrAccount as String: id.uuidString.lowercased()]
        SecItemDelete(query as CFDictionary)
    }
}
#endif
