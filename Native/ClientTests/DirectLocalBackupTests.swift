#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
@testable import Mac_Companion

@MainActor final class DirectLocalBackupTests: XCTestCase {
    func testPortableRoundTripDropsLocalIdentityAndSyncHistory() throws {
        let fixture = try BackupFixture(name: "Original Mac")
        defer { fixture.clean() }
        var terminal = try fixture.stores[.terminal]!.load()
        terminal.importedMacs = [fixture.original.id]
        var metadata = terminal.syncState
        metadata.layoutClock = [UUID().uuidString.lowercased(): 2]
        terminal.syncState = metadata
        let backup = try DirectLocalBackup(macs: [fixture.original], terminal: terminal,
            remoteMac: fixture.stores[.remoteMac]!.load(), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoded = try backup.encoded(), decoded = try DirectLocalBackup.decode(encoded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let mac = try XCTUnwrap((json["macs"] as? [[String: Any]])?.first)
        XCTAssertNil(mac["id"]); XCTAssertNil(mac["password"]); XCTAssertNil(mac["privateKey"])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(fixture.original.id.uuidString))
        XCTAssertTrue(decoded.terminal.importedMacs.isEmpty); XCTAssertNil(decoded.terminal.localCloudState)
        XCTAssertEqual(decoded.terminal.keyboardRows, backup.terminal.keyboardRows)
        XCTAssertEqual(decoded.remoteMac.remoteMenus, backup.remoteMac.remoteMenus)
        XCTAssertEqual(decoded.macs.first?.addresses, fixture.original.addresses)
        XCTAssertNotEqual(try decoded.macs[0].record().id, fixture.original.id)
        XCTAssertNotEqual(try decoded.macs[0].record().id, try decoded.macs[0].record().id)
    }
    func testInvalidOrNewerBackupsAreRejectedBeforeRestore() async throws {
        let fixture = try BackupFixture(name: "Current Mac"); defer { fixture.clean() }
        let backup = try fixture.service.makeBackup()
        let before = fixture.raw
        for edit in [0, 1, 2, 3] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup.encoded()) as? [String: Any])
            if edit == 0 { json["format"] = "some-other-app" }
            if edit == 1 { json["version"] = 2 }
            if edit == 2 { var macs = try XCTUnwrap(json["macs"] as? [[String: Any]]); macs[0]["port"] = 0; json["macs"] = macs }
            if edit == 3 { var profile = try XCTUnwrap(json["terminal"] as? [String: Any]); profile["family"] = "remoteMac"; json["terminal"] = profile }
            XCTAssertThrowsError(try DirectLocalBackup.decode(JSONSerialization.data(withJSONObject: json)))
        }
        XCTAssertEqual(fixture.raw, before); XCTAssertEqual(fixture.pauseCalls, 0)
    }
    func testRestoreAndPreviousDataPreserveLayoutsTextAndOriginalLocalIDs() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        var sourceProfile = try source.stores[.terminal]!.load()
        sourceProfile.actions.append(.init(title: "Sample Text", kind: .text, text: "Synthetic saved text.", inMenu: false))
        _ = try source.stores[.terminal]!.save(sourceProfile)
        let backup = try DirectLocalBackup.decode(source.service.makeBackup().encoded())
        let original = target.library.macs
        let previousTerminal = try target.stores[.terminal]!.load()
        await target.service.restore(backup)
        XCTAssertNil(target.service.problem); XCTAssertEqual(target.pauseCalls, 1)
        XCTAssertEqual(target.library.macs.map(\.name), ["Backup Mac"])
        XCTAssertNotEqual(target.library.macs[0].id, source.original.id)
        XCTAssertNotEqual(target.library.macs[0].id, target.original.id)
        XCTAssertEqual(target.preferenceIDs, [target.library.macs[0].id])
        XCTAssertTrue(target.service.hasRecoveryCopy)
        XCTAssertEqual(try target.stores[.terminal]!.load().actions, backup.terminal.actions)
        XCTAssertEqual(try target.service.recoveryPreview().macs.first?.name, "Current Mac")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
        await target.service.restorePrevious()
        XCTAssertNil(target.service.problem); XCTAssertEqual(target.library.macs, original)
        XCTAssertEqual(try target.stores[.terminal]!.load().actions, previousTerminal.actions)
        XCTAssertEqual(try target.stores[.terminal]!.load().keyboardRows, previousTerminal.keyboardRows)
    }
    func testStaleMacEditorCannotRecreateAnEntryRemovedByRestore() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNil(target.service.problem)
        let records = target.library.macs
        XCTAssertFalse(target.library.save(id: target.original.id, name: "Stale Draft", addresses: target.original.addresses, requiresExisting: true))
        XCTAssertEqual(target.library.macs, records)
    }
    func testSecondProfileWriteFailureRollsBackBothProfilesAndMacs() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let backup = try source.service.makeBackup(), before = target.raw
        target.failRemoteWrites = 1
        await target.service.restore(backup)
        XCTAssertNotNil(target.service.problem); XCTAssertEqual(target.raw, before)
        XCTAssertEqual(target.library.macs, [target.original]); XCTAssertFalse(target.service.hasRecoveryCopy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
    }
    func testMacWriteAndCommitFailuresKeepExistingRecoveryCopy() async throws {
        for failure in ["mac", "commit"] {
            let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
            defer { source.clean(); target.clean() }
            let backup = try source.service.makeBackup()
            await target.service.restore(backup)
            XCTAssertNil(target.service.problem)
            let before = target.raw, recovery = try Data(contentsOf: target.previous)
            if failure == "mac" { target.failMacWrite = true } else { target.failCommit = true }
            await target.service.restore(backup)
            XCTAssertNotNil(target.service.problem); XCTAssertEqual(target.raw, before)
            XCTAssertEqual(try Data(contentsOf: target.previous), recovery)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
        }
    }
    func testFailedRollbackKeepsJournalAndRestartRecoversOriginalData() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let backup = try source.service.makeBackup(), before = target.raw
        target.failRemoteWrites = 2
        await target.service.restore(backup)
        XCTAssertNotNil(target.service.problem); XCTAssertTrue(FileManager.default.fileExists(atPath: target.pending.path))
        XCTAssertFalse(target.library.readable)
        target.failRemoteWrites = 0
        let restarted = target.makeService()
        try restarted.recoverPending()
        XCTAssertEqual(target.raw, before); XCTAssertEqual(target.library.macs, [target.original])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
        XCTAssertTrue(target.library.readable)
    }
    func testLockOrNewSessionDuringSyncDrainPreventsEveryDataWrite() async throws {
        for event in ["lock", "session"] {
            let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
            defer { source.clean(); target.clean() }
            let backup = try source.service.makeBackup(), before = target.raw
            target.duringPause = { if event == "lock" { target.allowed = false } else { target.session = true } }
            await target.service.restore(backup)
            XCTAssertNotNil(target.service.problem); XCTAssertEqual(target.raw, before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
        }
    }
    func testRecoveredContentIsPortableWithoutMovingItsCloudBookkeeping() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        var profile = try source.stores[.terminal]!.load()
        let action = TerminalControlAction(title: "Recovered Text", kind: .text, text: "Synthetic recovered content.", inMenu: false)
        let control = DirectCloudSavedControl(action: action, bar: [], menus: [], libraryIndex: 0)
        var state = profile.syncState
        state.recovered = [.init(id: "source-" + source.original.id.uuidString, family: .terminal, control: control)]
        profile.syncState = state
        _ = try source.stores[.terminal]!.save(profile)
        let backup = try source.service.makeBackup(), bytes = try backup.encoded()
        XCTAssertEqual(backup.recoveredCount, 1)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(source.original.id.uuidString))
        await target.service.restore(try DirectLocalBackup.decode(bytes))
        XCTAssertNil(target.service.problem)
        let restored = try target.stores[.terminal]!.load().syncState.recovered
        XCTAssertEqual(restored.count, 1); XCTAssertEqual(restored[0].control, control)
        XCTAssertNotEqual(restored[0].id, state.recovered[0].id)
        await target.service.restorePrevious()
        XCTAssertTrue(try target.stores[.terminal]!.load().syncState.recovered.isEmpty)
    }
    func testRestoreUsesFilePositionsInsteadOfOldCloudPlacementReceipts() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let action = TerminalControlAction(title: "Sample Text", kind: .text, text: "Synthetic text.", inMenu: false)
        var profile = try source.stores[.terminal]!.load()
        profile.actions.append(action)
        _ = try source.stores[.terminal]!.save(profile)
        var current = try target.stores[.terminal]!.load()
        current.actions.append(action)
        var state = current.syncState
        state.savedPositions = [action.id.uuidString.lowercased(): .init(
            intended: [.init(row: current.resolvedRows[0].id, placement: "old-cloud-placement", index: 0)], applied: [])]
        current.syncState = state
        _ = try target.stores[.terminal]!.save(current)
        XCTAssertFalse(try XCTUnwrap(DirectCloudSavedControl.project(target.stores[.terminal]!.load())[action.id]).bar.isEmpty)
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNil(target.service.problem)
        let restored = try target.stores[.terminal]!.load()
        XCTAssertNil(restored.syncState.savedPositions)
        XCTAssertTrue(try XCTUnwrap(DirectCloudSavedControl.project(restored)[action.id]).bar.isEmpty)
    }
    func testFileSizeAndInjectedMacIdentityCannotBypassThePortableFormat() throws {
        let fixture = try BackupFixture(name: "Current Mac"); defer { fixture.clean() }
        let backup = try fixture.service.makeBackup()
        XCTAssertThrowsError(try DirectLocalBackup.decode(Data(repeating: 0x20, count: DirectLocalBackup.maximumBytes + 1)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup.encoded()) as? [String: Any])
        var macs = try XCTUnwrap(json["macs"] as? [[String: Any]])
        macs[0]["id"] = fixture.original.id.uuidString; macs[0]["password"] = "synthetic-excluded-marker"
        json["macs"] = macs
        let decoded = try DirectLocalBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNotEqual(try decoded.macs[0].record().id, fixture.original.id)
        XCTAssertFalse(String(decoding: try decoded.encoded(), as: UTF8.self).contains("synthetic-excluded-marker"))
    }
    func testConcurrentRestoreIsRejectedWithoutChangingTheAdmittedRestore() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        var resume: CheckedContinuation<Void, Never>?
        target.pauseBody = { await withCheckedContinuation { resume = $0 } }
        let backup = try source.service.makeBackup()
        let first = Task { await target.service.restore(backup) }
        for _ in 0..<200 where resume == nil { try await Task.sleep(for: .milliseconds(10)) }
        let gate = try XCTUnwrap(resume)
        await target.service.restore(backup)
        XCTAssertEqual(target.pauseCalls, 1)
        gate.resume(); await first.value
        XCTAssertNil(target.service.problem)
        XCTAssertEqual(target.library.macs.first?.name, "Backup Mac")
        XCTAssertFalse(DirectLocalBackupStore.applying)
    }
    func testPausingSyncWaitsForAdmittedCloudWorkAndKeepsCloudCopies() async throws {
        let fixture = try BackupFixture(name: "Current Mac"); defer { fixture.clean() }
        let name = "local-backup-drain-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let transport = BackupBlockingTransport(); defer { transport.release() }
        let cloud = DirectCloudSyncV1(defaults: defaults, url: fixture.directory.appending(path: "cloud.json"), transport: transport, writerID: UUID())
        cloud.attach(fixture.library); cloud.setEnabled(true)
        for _ in 0..<200 where !transport.started { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(transport.started)
        var drained = false
        let pausing = Task { try await cloud.pauseForLocalRestore(); drained = true }
        for _ in 0..<200 where cloud.enabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.enabled); XCTAssertFalse(drained)
        transport.release(); try await pausing.value
        XCTAssertTrue(drained); XCTAssertFalse(cloud.enabled)
        XCTAssertEqual(transport.removals, 0)
        XCTAssertEqual(fixture.library.macs, [fixture.original])
    }
    func testActiveSessionsAndLockedAppDoNotPauseOrWrite() async throws {
        let fixture = try BackupFixture(name: "Current Mac"); defer { fixture.clean() }
        let backup = try fixture.service.makeBackup(), before = fixture.raw
        fixture.session = true; await fixture.service.restore(backup)
        XCTAssertEqual(fixture.pauseCalls, 0); XCTAssertEqual(fixture.raw, before)
        fixture.session = false; fixture.allowed = false; await fixture.service.restore(backup)
        XCTAssertEqual(fixture.pauseCalls, 0); XCTAssertEqual(fixture.raw, before)
    }
}

@MainActor private final class BackupFixture {
    let directory = URL.temporaryDirectory.appending(path: "local-backup-tests-" + UUID().uuidString)
    let original: DirectMacRecordV1
    let library: DirectMacLibraryV1
    var bytes: [TerminalControlsFamily: Data]
    var allowed = true
    var session = false
    var pauseCalls = 0
    var duringPause: (() -> Void)?
    var pauseBody: (() async -> Void)?
    var preferenceIDs: [UUID] = []
    var failRemoteWrites = 0
    var failMacWrite = false
    var failCommit = false
    lazy var stores: [TerminalControlsFamily: TerminalControlsStore] = {
        Dictionary(uniqueKeysWithValues: [TerminalControlsFamily.terminal, .remoteMac].map { family in
            var store = family == .terminal ? TerminalControlsStore() : .remoteMac()
            store.read = { self.bytes[family] }
            store.write = { data in
                if family == .remoteMac && self.failRemoteWrites > 0 { self.failRemoteWrites -= 1; throw TestFailure.injected }
                self.bytes[family] = data
            }
            store.legacyIDs = { [] }; store.legacyActions = { [] }
            return (family, store)
        })
    }()
    lazy var service = makeService()
    var pending: URL { directory.appending(path: "recovery/pending.json") }
    var previous: URL { directory.appending(path: "recovery/previous.json") }
    var raw: [Data?] { [try? Data(contentsOf: library.storageURL), bytes[.terminal], bytes[.remoteMac]] }
    init(name: String) throws {
        original = try .normalized(name: name, address: "synthetic.invalid")
        library = DirectMacLibraryV1(url: directory.appending(path: "macs.json"), removeLogin: { _ in })
        bytes = [.terminal: try JSONEncoder().encode(TerminalControlsProfile.defaults),
                 .remoteMac: try JSONEncoder().encode(TerminalControlsProfile.remoteDefaults)]
        XCTAssertTrue(library.save(id: original.id, name: original.name, addresses: original.addresses))
        _ = try service.makeBackup()
    }
    func makeService() -> DirectLocalBackupStore {
        var files = DirectLocalBackupStore.FileStorage()
        let commit = files.commit
        files.commit = { from, to in if self.failCommit { throw TestFailure.injected }; try commit(from, to) }
        return DirectLocalBackupStore(library: library, stores: stores, directory: directory.appending(path: "recovery"), files: files,
            canAccess: { self.allowed }, sessionsActive: { self.session }, pauseSync: {
                self.pauseCalls += 1; self.duringPause?()
                if let pause = self.pauseBody { await pause() } else { await Task.yield() }
            }, applyPreferences: { _, id in self.preferenceIDs.append(id) }, replaceMacs: { records in
                if self.failMacWrite { throw TestFailure.injected }
                try self.library.replaceFromBackup(records)
            })
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    enum TestFailure: Error { case injected }
}
private final class BackupBlockingTransport: DirectCloudTransport, @unchecked Sendable {
    private let condition = NSCondition()
    private var open = false
    private var didStart = false
    private var removeCount = 0
    var started: Bool { condition.lock(); defer { condition.unlock() }; return didStart }
    var removals: Int { condition.lock(); defer { condition.unlock() }; return removeCount }
    func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    func read() throws -> [Data] {
        condition.lock(); defer { condition.unlock() }; didStart = true
        while !open { if !condition.wait(until: Date().addingTimeInterval(5)) { throw DirectCloudError.storage } }
        return []
    }
    func write(_ data: Data, account: String) throws {}
    func remove(account: String) throws { condition.lock(); removeCount += 1; condition.unlock() }
    func removeAll() throws { condition.lock(); removeCount += 1; condition.unlock() }
}
#endif
