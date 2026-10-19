#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class TemporaryMacCleanupTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "TemporaryMacCleanupTests." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
    func testLockedExitPersistsCleanupAndRestartRetriesStorageFailure() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID(), other = UUID()
        var unlocked = false, storageAvailable = false, attempts = [UUID](), cleared = [UUID]()
        enum Failure: Error { case unavailable }
        let first = DirectTemporaryMacCleanup(defaults: defaults, canAccess: { unlocked },
            disconnect: { attempts.append($0); return true }, erase: { _ in XCTFail("Locked cleanup must wait") },
            clearPreferences: { _ in XCTFail("Locked cleanup must wait") })
        first.updateSavedMacs([other]); first.begin(id); first.end(id)
        await Task.yield()
        XCTAssertEqual(first.pending, [id]); XCTAssertTrue(attempts.isEmpty)
        // A new owner models a process restart; only the UUID was persisted.
        let restarted = DirectTemporaryMacCleanup(defaults: defaults, canAccess: { unlocked },
            disconnect: { attempts.append($0); return true }, erase: { value in
                XCTAssertEqual(value, id)
                if !storageAvailable { throw Failure.unavailable }
            }, clearPreferences: { cleared.append($0) })
        unlocked = true; restarted.updateSavedMacs([other])
        try await wait { attempts.count == 1 }
        await Task.yield()
        XCTAssertEqual(restarted.pending, [id]); XCTAssertTrue(cleared.isEmpty)
        storageAvailable = true; restarted.retry()
        try await wait { restarted.pending.isEmpty }
        XCTAssertEqual(attempts, [id, id]); XCTAssertEqual(cleared, [id])
        let final = DirectTemporaryMacCleanup(defaults: defaults)
        XCTAssertTrue(final.pending.isEmpty)
    }
    func testActiveTemporaryAndSavedMacsAreProtectedAndLateOwnersDrain() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let active = UUID(), saved = UUID(), later = UUID()
        var erased = [UUID](), disconnected = [UUID]()
        var cleanup: DirectTemporaryMacCleanup!
        cleanup = DirectTemporaryMacCleanup(defaults: defaults, canAccess: { true }, disconnect: { id in
            disconnected.append(id)
            if id == active { cleanup.end(later); await Task.yield() }
            return true
        }, erase: { erased.append($0) }, clearPreferences: { _ in })
        cleanup.updateSavedMacs([])
        cleanup.begin(active); cleanup.begin(saved); cleanup.begin(later)
        cleanup.updateSavedMacs([saved])
        await Task.yield()
        XCTAssertTrue(disconnected.isEmpty); XCTAssertEqual(cleanup.pending, [active, later])
        cleanup.end(active)
        try await wait { cleanup.pending.isEmpty }
        XCTAssertEqual(Set(erased), [active, later]); XCTAssertEqual(Set(disconnected), [active, later])
        XCTAssertFalse(erased.contains(saved))
    }
    func testUnreadableLibraryAndUnjoinedOwnersKeepIntentAndSaveDuringJoinCancelsErase() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        var joined = false, attempts = 0, saveDuringJoin = false
        var cleanup: DirectTemporaryMacCleanup!
        cleanup = DirectTemporaryMacCleanup(defaults: defaults, canAccess: { true }, disconnect: { _ in
            attempts += 1
            if saveDuringJoin { cleanup.updateSavedMacs([id]) }
            return joined
        }, erase: { _ in XCTFail("A live or newly saved identity must not be erased") }, clearPreferences: { _ in XCTFail() })
        cleanup.begin(id); cleanup.end(id)
        await Task.yield(); XCTAssertEqual(attempts, 0)
        cleanup.updateSavedMacs([])
        try await wait { attempts == 1 }
        await Task.yield(); XCTAssertEqual(cleanup.pending, [id])
        joined = true; saveDuringJoin = true; cleanup.retry()
        try await wait { cleanup.pending.isEmpty }
        XCTAssertEqual(attempts, 2)
    }
    func testTemporaryEraseDeletesAllScopedItemsAndPreservesOtherMac() throws {
        let id = UUID(), other = UUID()
        defer {
            try? TerminalSecretStore.removeTemporaryIdentity(id)
            try? TerminalSecretStore.removeTemporaryIdentity(other)
        }
        let profile = DirectMacAccessProfile(login: .init(username: "synthetic", password: "synthetic-only"))
        let pin = "ssh-ed25519 " + Data(repeating: 7, count: 32).base64EncodedString()
        for value in [id, other] {
            try DirectMacAccessStore.write(profile, id: value)
            try TerminalSecretStore.write(Data("legacy-test-only".utf8), id: value, kind: "login")
            try TerminalSecretStore.write(Data("legacy-test-only".utf8), id: value, kind: "private-key")
            try TerminalSecretStore.approveHostKey(pin, id: value)
        }
        let owner = DirectMacConnections.shared.begin(macID: id, kind: "synthetic", disconnect: {})
        XCTAssertThrowsError(try TerminalSecretStore.removeTemporaryIdentity(id))
        XCTAssertEqual(try DirectMacAccessStore.load(id), profile)
        DirectMacConnections.shared.end(owner)
        try TerminalSecretStore.removeTemporaryIdentity(id)
        try TerminalSecretStore.removeTemporaryIdentity(id)
        for kind in [DirectMacAccessStore.kind, "login", "private-key", "host-key"] {
            XCTAssertNil(try TerminalSecretStore.read(id, kind: kind), kind)
            XCTAssertNotNil(try TerminalSecretStore.read(other, kind: kind), kind)
        }
        XCTAssertEqual(try DirectMacAccessStore.load(other), profile)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(4)
        while !condition() {
            guard Date() < end else { throw TerminalSecretStore.Failure.network }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
#endif
