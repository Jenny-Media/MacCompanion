#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
import CoreFoundation
import Security
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
    func testCommitFailureRestoresAnInitiallyAbsentMacLibraryInMemoryAndOnDisk() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        try FileManager.default.removeItem(at: target.library.storageURL)
        target.library.reload()
        XCTAssertTrue(target.library.macs.isEmpty)
        let before = target.raw
        target.failCommit = true
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNotNil(target.service.problem)
        XCTAssertEqual(target.raw, before)
        XCTAssertTrue(target.library.readable)
        XCTAssertTrue(target.library.macs.isEmpty)
        XCTAssertTrue(try target.service.makeBackup().macs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
    }
    func testRestoreDoesNotJournalUncommittedPreferenceNotifications() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let suite = "backup-uncommitted-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloudURL = target.directory.appending(path: "cloud.json")
        let cloud = DirectCloudSyncV1(defaults: defaults, url: cloudURL, transport: BackupMemoryTransport(), writerID: UUID(),
            localBackupDirectory: target.recoveryDirectory)
        cloud.attach(target.library)
        let before = try Data(contentsOf: cloudURL)
        var notifications = 0
        let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
            pauseSync: { try await cloud.pauseForLocalRestore() }, applyPreferences: { _, id in
                notifications += 1
                NotificationCenter.default.post(name: DirectCloudSyncV1.preferenceChanged, object: id)
                XCTAssertEqual(try? Data(contentsOf: cloudURL), before)
            })
        await service.restore(try source.service.makeBackup())
        XCTAssertNil(service.problem)
        XCTAssertEqual(notifications, 1)
        XCTAssertNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
    }
    func testInterruptedRestoreReconcilesAfterStartupRollbackBeforeEnablingSync() async throws {
        try await checkInterruptedRestore(afterCommit: false)
    }
    func testCommittedRestoreReconcilesRemovedMacsAfterRestartBeforePublication() async throws {
        try await checkInterruptedRestore(afterCommit: true)
    }
    private func checkInterruptedRestore(afterCommit: Bool) async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let suite = "backup-restart-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloudURL = target.directory.appending(path: "cloud.json"), writer = UUID(), transport = BackupMemoryTransport()
        var cloud: DirectCloudSyncV1? = DirectCloudSyncV1(defaults: defaults, url: cloudURL, transport: transport, writerID: writer,
            localBackupDirectory: target.recoveryDirectory)
        cloud!.attach(target.library)
        let original = target.library.macs
        var image: BackupPersistedImage?
        let capture = { image = try BackupPersistedImage(target, cloudURL: cloudURL) }
        if afterCommit { target.afterCommit = capture } else { target.beforeCommit = capture }
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNil(target.service.problem)
        let imported = target.library.macs
        let interrupted = try XCTUnwrap(image)
        cloud = nil
        try interrupted.restore(target)
        // Reconstruct actual persisted state at the interruption, then use the
        // same recovery-before-attachment ordering as the shipping root.
        let restartedLibrary = DirectMacLibraryV1(url: target.library.storageURL, removeLogin: { _ in })
        let restartedBackup = DirectLocalBackupStore(library: restartedLibrary, stores: target.stores, directory: target.recoveryDirectory)
        try restartedBackup.recoverPending()
        let expected = afterCommit ? imported : original
        XCTAssertEqual(restartedLibrary.macs, expected)
        XCTAssertNotNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
        let restartedCloud = DirectCloudSyncV1(defaults: defaults, url: cloudURL, transport: transport, writerID: writer,
            localBackupDirectory: target.recoveryDirectory)
        restartedCloud.attach(restartedLibrary)
        XCTAssertNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
        restartedCloud.setEnabled(true)
        for _ in 0..<200 where restartedCloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(restartedCloud.busy)
        XCTAssertNil(restartedCloud.recovery)
        XCTAssertEqual(restartedLibrary.macs, expected)
        XCTAssertEqual(try DirectMacLibraryV1.readRecords(at: restartedLibrary.storageURL), expected)
    }
    func testFailedReconciliationKeepsIntentAndBlocksCloudUntilRetry() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let suite = "backup-reconcile-retry-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journalFolder = target.directory.appending(path: "cloud-folder")
        let cloudURL = journalFolder.appending(path: "cloud.json"), transport = BackupMemoryTransport()
        let cloud = DirectCloudSyncV1(defaults: defaults, url: cloudURL, transport: transport, writerID: UUID(),
            localBackupDirectory: target.recoveryDirectory)
        cloud.attach(target.library)
        let retainedFolder = target.directory.appending(path: "retained-cloud-folder")
        try FileManager.default.moveItem(at: journalFolder, to: retainedFolder)
        try Data("synthetic storage failure".utf8).write(to: journalFolder)
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNil(target.service.problem)
        let restored = target.library.macs
        XCTAssertNotNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
        cloud.setEnabled(true)
        await Task.yield()
        XCTAssertEqual(target.library.macs, restored)
        XCTAssertNotNil(cloud.recovery)
        XCTAssertEqual(transport.reads, 0)
        try FileManager.default.removeItem(at: journalFolder)
        try FileManager.default.moveItem(at: retainedFolder, to: journalFolder)
        cloud.retry()
        for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
        XCTAssertNil(cloud.recovery)
        XCTAssertGreaterThan(transport.reads, 0)
        XCTAssertEqual(target.library.macs, restored)
    }
    func testSeparateBackupLibraryReconcilesBeforeRootReload() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let suite = "backup-separate-library-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = DirectCloudSyncV1(defaults: defaults, url: target.directory.appending(path: "cloud.json"),
            transport: BackupMemoryTransport(), writerID: UUID(), localBackupDirectory: target.recoveryDirectory)
        cloud.attach(target.library)
        // Session App Settings owns another instance of the same saved file.
        // Leave the root's cache stale until after cloud handles publication.
        let backupLibrary = DirectMacLibraryV1(url: target.library.storageURL, removeLogin: { _ in })
        let service = DirectLocalBackupStore(library: backupLibrary, stores: target.stores, directory: target.recoveryDirectory,
            pauseSync: { try await cloud.pauseForLocalRestore() }, applyPreferences: { _, _ in })
        await service.restore(try source.service.makeBackup())
        XCTAssertNil(service.problem)
        let restored = backupLibrary.macs
        XCTAssertEqual(restored.map(\.name), ["Backup Mac"])
        XCTAssertEqual(target.library.macs, restored)
        XCTAssertNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
        target.library.reload() // The root observer can arrive later.
        cloud.setEnabled(true)
        for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertNil(cloud.recovery)
        XCTAssertEqual(target.library.macs, restored)
        XCTAssertEqual(try DirectMacLibraryV1.readRecords(at: target.library.storageURL), restored)
    }
    func testPreferencePersistenceFailureAtEitherBoundaryKeepsOriginalData() async throws {
        for failureAt in [1, 2] {
            let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
            defer { source.clean(); target.clean() }
            let before = target.raw
            var calls = 0, committed = false
            var files = DirectLocalBackupStore.FileStorage()
            let commit = files.commit
            files.commit = { from, to in committed = true; try commit(from, to) }
            let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
                files: files, pauseSync: {}, applyPreferences: { _, _ in }, persistPreferences: {
                    calls += 1
                    if calls == failureAt { throw BackupFixture.TestFailure.injected }
                })
            await service.restore(try source.service.makeBackup())
            XCTAssertNotNil(service.problem)
            XCTAssertEqual(calls, failureAt == 1 ? 1 : 3) // Rollback also persists its restored preferences.
            XCTAssertFalse(committed)
            XCTAssertEqual(target.raw, before)
            XCTAssertEqual(target.library.macs, [target.original])
            XCTAssertFalse(service.hasRecoveryCopy)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
        }
    }
    func testCommittedPreferencesAndSyncPauseSurviveDroppingVolatileState() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        var backup = try source.service.makeBackup()
        backup.macs[0].pointerSpeed = 2.5; backup.macs[0].display = 7
        backup.macs[0].fullscreen = true; backup.macs[0].trackpad = true
        backup.macs[0].followCursor = false; backup.macs[0].desktopSize = 3
        var volatile = [target.original.id: try target.service.makeBackup().macs[0]]
        var durable: [UUID: DirectLocalBackup.Mac] = [:]
        var enabled = true, durableEnabled = true
        var files = DirectLocalBackupStore.FileStorage()
        let commit = files.commit
        files.commit = { from, to in
            try commit(from, to)
            // Model loss of the process/system's unsaved preference cache at
            // the real commit boundary, independently of its file snapshots.
            volatile = durable; enabled = durableEnabled
        }
        let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
            files: files, pauseSync: { enabled = false }, applyPreferences: { mac, id in volatile[id] = mac },
            readPreferences: { volatile[$0.id] ?? DirectLocalBackup.Mac($0) },
            persistPreferences: { durable = volatile; durableEnabled = enabled })
        await service.restore(backup)
        XCTAssertNil(service.problem)
        XCTAssertFalse(enabled); XCTAssertFalse(durableEnabled)
        let id = try XCTUnwrap(target.library.macs.first?.id)
        let saved = try XCTUnwrap(volatile[id])
        XCTAssertEqual(saved.pointerSpeed, 2.5); XCTAssertEqual(saved.display, 7)
        XCTAssertTrue(saved.fullscreen); XCTAssertTrue(saved.trackpad)
        XCTAssertFalse(saved.followCursor); XCTAssertEqual(saved.desktopSize, 3)
        XCTAssertNotNil(durable[target.original.id]) // Previous data remains recoverable too.
    }
    func testProductionPreferenceBarrierPersistsTheOwnApplicationDomain() throws {
        let fixture = try BackupFixture(name: "Backup Mac"); defer { fixture.clean() }
        let id = UUID(), defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: DirectCloudSyncV1.enabledKey)
        defer {
            VNCSessionPreferences.clear(id)
            defaults.set(enabled, forKey: DirectCloudSyncV1.enabledKey)
            try? DirectLocalBackupStore.persistStandardPreferences()
        }
        var mac = try fixture.service.makeBackup().macs[0]
        mac.pointerSpeed = 2.25; mac.display = 9; mac.fullscreen = true
        mac.trackpad = true; mac.followCursor = false; mac.desktopSize = 1
        defaults.set(false, forKey: DirectCloudSyncV1.enabledKey)
        mac.applyPreferences(to: id)
        try DirectLocalBackupStore.persistStandardPreferences()
        XCTAssertEqual(CFPreferencesCopyAppValue(DirectCloudSyncV1.enabledKey as CFString, kCFPreferencesCurrentApplication) as? Bool, false)
        XCTAssertEqual(VNCSessionPreferences.speed(id), 2.25)
        XCTAssertEqual(VNCSessionPreferences.display(id)?.uint32Value, 9)
        XCTAssertTrue(VNCSessionPreferences.fullscreen(id)); XCTAssertTrue(VNCSessionPreferences.trackpad(id))
        XCTAssertFalse(VNCSessionPreferences.followCursor(id)); XCTAssertEqual(VNCSessionPreferences.desktopSize(id), 1)
    }
    func testPreviousDataFreezesPreferencesBeforeHigherRevisionCloudUpdate() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        var preferenceIDs = Set([target.original.id])
        defer { for id in preferenceIDs { VNCSessionPreferences.clear(id) }; try? DirectLocalBackupStore.persistStandardPreferences() }
        var original = DirectLocalBackup.Mac(target.original)
        original.pointerSpeed = 1; original.display = 3; original.fullscreen = true
        original.trackpad = true; original.followCursor = false; original.desktopSize = 1
        original.applyPreferences(to: target.original.id)
        let suite = "backup-frozen-cloud-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = BackupMemoryTransport()
        let cloud = DirectCloudSyncV1(defaults: defaults, url: target.directory.appending(path: "cloud.json"), transport: transport,
            writerID: UUID(), localBackupDirectory: target.recoveryDirectory)
        cloud.attach(target.library)
        let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
            pauseSync: { try await cloud.pauseForLocalRestore() })
        await service.restore(try source.service.makeBackup())
        XCTAssertNil(service.problem)
        let imported = try XCTUnwrap(target.library.macs.first)
        preferenceIDs.insert(imported.id)
        var newer = DirectCloudPreferences(mac: target.original.id)
        newer.speed = 2.75; newer.display = 9; newer.fullscreen = false
        newer.trackpad = false; newer.followCursor = true
        let remote = DirectCloudVersion(id: target.original.id, writer: UUID(), revision: 1_000,
            mac: target.original, preferences: newer)
        try transport.write(JSONEncoder().encode(remote), account: remote.account)
        cloud.setEnabled(true)
        for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertNil(cloud.recovery)
        XCTAssertTrue(target.library.macs.contains { $0.id == target.original.id })
        XCTAssertEqual(VNCSessionPreferences.speed(target.original.id), 2.75)
        // Desktop size is device-local; a later local edit must not mutate the copy either.
        VNCSessionPreferences.setDesktopSize(3, mac: target.original.id)
        let frozen = try XCTUnwrap(service.recoveryPreview().macs.first)
        assertPreferences(frozen, equal: original)
        await service.restorePrevious()
        XCTAssertNil(service.problem)
        XCTAssertEqual(target.library.macs, [target.original])
        assertPreferences(DirectLocalBackup.Mac(target.original), equal: original)
        // Swapping back must recover the newer state captured before the undo.
        await service.restorePrevious()
        XCTAssertNil(service.problem)
        XCTAssertEqual(Set(target.library.macs.map(\.id)), Set([target.original.id, imported.id]))
        XCTAssertEqual(VNCSessionPreferences.speed(target.original.id), 2.75)
        XCTAssertEqual(VNCSessionPreferences.display(target.original.id)?.uint32Value, 9)
        XCTAssertEqual(VNCSessionPreferences.desktopSize(target.original.id), 3)
    }
    func testPreviousDataFailureRestoresCurrentPreferencesAndRetryRecoversSnapshot() async throws {
        for failRollbackPersistence in [false, true] {
            let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
            defer { source.clean(); target.clean() }
            var preferenceIDs = Set([target.original.id])
            defer { for id in preferenceIDs { VNCSessionPreferences.clear(id) }; try? DirectLocalBackupStore.persistStandardPreferences() }
            var original = DirectLocalBackup.Mac(target.original)
            original.pointerSpeed = 1; original.display = 3; original.fullscreen = true
            original.trackpad = true; original.followCursor = false; original.desktopSize = 1
            original.applyPreferences(to: target.original.id)
            var failCommit = false, failPersistence = false
            var files = DirectLocalBackupStore.FileStorage()
            let commit = files.commit
            files.commit = { from, to in
                if failCommit { failPersistence = failRollbackPersistence; throw BackupFixture.TestFailure.injected }
                try commit(from, to)
            }
            let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
                files: files, pauseSync: {}, persistPreferences: {
                    if failPersistence { throw BackupFixture.TestFailure.injected }
                    try DirectLocalBackupStore.persistStandardPreferences()
                })
            await service.restore(try source.service.makeBackup())
            XCTAssertNil(service.problem)
            preferenceIDs.formUnion(target.library.macs.map(\.id))
            var current = target.original; current.name = "Newer Mac"
            try target.library.applyCloud([current])
            var newer = DirectLocalBackup.Mac(current)
            newer.pointerSpeed = 2.5; newer.display = 8; newer.fullscreen = false
            newer.trackpad = false; newer.followCursor = true; newer.desktopSize = 3
            newer.applyPreferences(to: current.id)
            let before = target.raw, recovery = try Data(contentsOf: target.previous)
            failCommit = true
            await service.restorePrevious()
            XCTAssertNotNil(service.problem)
            XCTAssertEqual(target.raw, before)
            XCTAssertEqual(try Data(contentsOf: target.previous), recovery)
            if failRollbackPersistence {
                XCTAssertTrue(FileManager.default.fileExists(atPath: target.pending.path))
                XCTAssertFalse(target.library.readable)
                // Startup must replay the frozen current values, not this live cache.
                original.applyPreferences(to: current.id)
                failPersistence = false
                let restartedLibrary = DirectMacLibraryV1(url: target.library.storageURL, removeLogin: { _ in })
                let restarted = DirectLocalBackupStore(library: restartedLibrary, stores: target.stores, directory: target.recoveryDirectory)
                try restarted.recoverPending()
                XCTAssertEqual(restartedLibrary.macs, [current])
            }
            assertPreferences(DirectLocalBackup.Mac(current), equal: newer)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
            failCommit = false
            await service.restorePrevious()
            XCTAssertNil(service.problem)
            XCTAssertEqual(target.library.macs, [target.original])
            assertPreferences(DirectLocalBackup.Mac(target.original), equal: original)
        }
    }
    func testRecoveryRejectsMissingOrUnboundPreferenceValuesBeforeWriting() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        await target.service.restore(try source.service.makeBackup())
        XCTAssertNil(target.service.problem)
        let snapshot = try Data(contentsOf: target.previous), before = target.raw
        for unbound in [false, true] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
            if unbound {
                let value = try DirectLocalBackup(macs: [target.original], terminal: target.stores[.terminal]!.load(), remoteMac: target.stores[.remoteMac]!.load()).macs[0]
                json["preferences"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([UUID(): value]))
            } else { json.removeValue(forKey: "preferences") }
            try JSONSerialization.data(withJSONObject: json).write(to: target.previous, options: .atomic)
            XCTAssertThrowsError(try target.service.recoveryPreview())
            await target.service.restorePrevious()
            XCTAssertNotNil(target.service.problem)
            XCTAssertEqual(target.raw, before)
        }
    }
    private func assertPreferences(_ actual: DirectLocalBackup.Mac, equal expected: DirectLocalBackup.Mac,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.pointerSpeed, expected.pointerSpeed, file: file, line: line)
        XCTAssertEqual(actual.display, expected.display, file: file, line: line)
        XCTAssertEqual(actual.fullscreen, expected.fullscreen, file: file, line: line)
        XCTAssertEqual(actual.trackpad, expected.trackpad, file: file, line: line)
        XCTAssertEqual(actual.followCursor, expected.followCursor, file: file, line: line)
        XCTAssertEqual(actual.desktopSize, expected.desktopSize, file: file, line: line)
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
    func testRestoreAndPreviousDataAreRejectedUntilCloudRemovalFinishes() async throws {
        for (stage, fails) in [(0, false), (1, false), (2, false), (0, true)] {
            let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
            defer { source.clean(); target.clean() }
            let backup = try source.service.makeBackup()
            await target.service.restore(backup)
            XCTAssertNil(target.service.problem)
            let before = target.raw, previous = try Data(contentsOf: target.previous)
            let suite = "backup-removal-" + UUID().uuidString, writer = UUID()
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer {
                defaults.removePersistentDomain(forName: suite)
                // Only this fixture's two device-local fallback journals.
                for kind in ["keyboard-cloud-journal-v1", "saved-controls-cloud-journal-v1"] {
                    SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: "media.jenny.maccompanion.ssh-\(kind).v1",
                        kSecAttrAccount as String: writer.uuidString.lowercased(), kSecAttrSynchronizable as String: false] as CFDictionary)
                }
            }
            let transports = (0..<3).map { BackupRemovalTransport(blocked: $0 == stage, fails: fails && $0 == stage) }
            defer { transports.forEach { $0.release() } }
            let cloudURL = target.directory.appending(path: "cloud.json")
            let cloud = DirectCloudSyncV1(defaults: defaults, url: cloudURL, transport: transports[0], writerID: writer,
                keyboardTransport: transports[1], savedControlsTransport: transports[2], localBackupDirectory: target.recoveryDirectory)
            cloud.attach(target.library)
            let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
                pauseSync: { try await cloud.pauseForLocalRestore() }, applyPreferences: { _, _ in })
            cloud.removeCloudCopies()
            for _ in 0..<200 where !transports[stage].started { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(transports[stage].started)
            await service.restore(backup)
            XCTAssertEqual(service.problem, "Wait for iCloud deletion to finish, then restore the backup.")
            await service.restorePrevious()
            XCTAssertEqual(service.problem, "Wait for iCloud deletion to finish, then restore the backup.")
            XCTAssertEqual(target.raw, before)
            XCTAssertEqual(try Data(contentsOf: target.previous), previous)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.pending.path))
            XCTAssertNil(try DirectLocalBackupStore.reconciliationIDs(in: target.recoveryDirectory))
            // Even a stale caller cannot release deletion's busy ownership.
            cloud.setEnabled(false); XCTAssertTrue(cloud.busy)
            cloud.setEnabled(true); XCTAssertFalse(cloud.enabled); XCTAssertTrue(cloud.busy)
            transports[stage].release()
            let finished = "Deletion requested. Sync is off; your local Macs are kept. Other devices may take a moment to update."
            for _ in 0..<200 where cloud.busy || (cloud.status != finished && cloud.recovery?.reason != .cloudRemoval) {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(cloud.busy); XCTAssertFalse(cloud.enabled)
            XCTAssertEqual(cloud.recovery?.reason, fails ? .cloudRemoval : nil)
            XCTAssertEqual(target.raw, before)
            // Admission recovers after either success or a partial failure.
            await service.restore(backup)
            XCTAssertNil(service.problem)
            let restored = target.library.macs
            cloud.setEnabled(true)
            for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(cloud.enabled); XCTAssertFalse(cloud.busy); XCTAssertNil(cloud.recovery)
            let remote = try transports[0].read().map { try JSONDecoder().decode(DirectCloudVersion.self, from: $0) }
            XCTAssertEqual(Set(DirectCloudVersion.winners(remote).values.compactMap(\.mac).map(\.id)), Set(restored.map(\.id)))
            cloud.setEnabled(false)
        }
    }
    func testRestoreDrainsAWriteCancelledByAnEarlierSyncOffToggle() async throws {
        let source = try BackupFixture(name: "Backup Mac"), target = try BackupFixture(name: "Current Mac")
        defer { source.clean(); target.clean() }
        let suite = "backup-prior-write-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = BackupBlockingWriteTransport(); defer { transport.release() }
        let cloud = DirectCloudSyncV1(defaults: defaults, url: target.directory.appending(path: "cloud.json"), transport: transport,
            writerID: UUID(), localBackupDirectory: target.recoveryDirectory)
        cloud.attach(target.library); cloud.setEnabled(true)
        for _ in 0..<200 where transport.writes == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(transport.writes, 1)
        cloud.setEnabled(false) // The admitted write is still blocked.
        let service = DirectLocalBackupStore(library: target.library, stores: target.stores, directory: target.recoveryDirectory,
            pauseSync: { try await cloud.pauseForLocalRestore() }, applyPreferences: { _, _ in })
        let backup = try source.service.makeBackup(), before = target.raw
        let restoring = Task { await service.restore(backup) }
        for _ in 0..<200 where !service.busy { try await Task.sleep(for: .milliseconds(10)) }
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(service.busy)
        XCTAssertEqual(target.raw, before)
        transport.release(); await restoring.value
        XCTAssertNil(service.problem)
        let restored = target.library.macs
        XCTAssertEqual(restored.map(\.name), ["Backup Mac"])
        cloud.setEnabled(true)
        for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertNil(cloud.recovery)
        XCTAssertEqual(target.library.macs, restored)
        let remote = try transport.snapshot.map { try JSONDecoder().decode(DirectCloudVersion.self, from: $0) }
        XCTAssertEqual(Set(DirectCloudVersion.winners(remote).values.compactMap(\.mac).map(\.id)), Set(restored.map(\.id)))
    }
    func testReenableSerializesNewPublicationAfterPreviouslyCancelledWrite() async throws {
        let fixture = try BackupFixture(name: "Current Mac"); defer { fixture.clean() }
        let suite = "backup-serial-write-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = BackupBlockingWriteTransport(); defer { transport.release() }
        let cloud = DirectCloudSyncV1(defaults: defaults, url: fixture.directory.appending(path: "cloud.json"), transport: transport,
            writerID: UUID(), localBackupDirectory: fixture.recoveryDirectory)
        cloud.attach(fixture.library); cloud.setEnabled(true)
        for _ in 0..<200 where transport.writes == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(transport.writes, 1)
        cloud.setEnabled(false)
        XCTAssertTrue(fixture.library.save(id: fixture.original.id, name: "Edited Mac", addresses: fixture.original.addresses, requiresExisting: true))
        cloud.setEnabled(true)
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(transport.reads, 1)
        XCTAssertEqual(transport.writes, 1)
        transport.release()
        for _ in 0..<200 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertNil(cloud.recovery)
        let remote = try transport.snapshot.map { try JSONDecoder().decode(DirectCloudVersion.self, from: $0) }
        XCTAssertEqual(DirectCloudVersion.winners(remote)[fixture.original.id]?.mac?.name, "Edited Mac")
        XCTAssertEqual(fixture.library.macs.first?.name, "Edited Mac")
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
    var beforeCommit: (() throws -> Void)?
    var afterCommit: (() throws -> Void)?
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
    var recoveryDirectory: URL { directory.appending(path: "recovery") }
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
        files.commit = { from, to in
            try self.beforeCommit?()
            if self.failCommit { throw TestFailure.injected }
            try commit(from, to)
            try self.afterCommit?()
        }
        return DirectLocalBackupStore(library: library, stores: stores, directory: directory.appending(path: "recovery"), files: files,
            canAccess: { self.allowed }, sessionsActive: { self.session }, pauseSync: {
                self.pauseCalls += 1; self.duringPause?()
                if let pause = self.pauseBody { await pause() } else { await Task.yield() }
            }, applyPreferences: { _, id in self.preferenceIDs.append(id) }, replaceMacs: { records in
                if self.failMacWrite { throw TestFailure.injected }
                try self.library.replaceFromBackup(records)
            })
    }
    func clean() {
        for id in Set([original.id] + library.macs.map(\.id) + preferenceIDs) { VNCSessionPreferences.clear(id) }
        try? DirectLocalBackupStore.persistStandardPreferences()
        try? FileManager.default.removeItem(at: directory)
    }
    enum TestFailure: Error { case injected }
}
/// Captures persisted files at a real transaction boundary. Reconstruction
/// models process termination without relying on caught errors and rollback.
@MainActor private struct BackupPersistedImage {
    var files: [URL: Data]
    var absent: [URL]
    var profiles: [TerminalControlsFamily: Data]
    init(_ fixture: BackupFixture, cloudURL: URL) throws {
        files = [:]; absent = []; profiles = fixture.bytes
        for url in [fixture.library.storageURL, fixture.pending, fixture.previous,
                    fixture.recoveryDirectory.appending(path: "sync-reconciliation.json"), cloudURL] {
            if FileManager.default.fileExists(atPath: url.path) { files[url] = try Data(contentsOf: url) }
            else { absent.append(url) }
        }
    }
    func restore(_ fixture: BackupFixture) throws {
        fixture.bytes = profiles
        for (url, data) in files { try data.write(to: url, options: .atomic) }
        for url in absent where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
private final class BackupMemoryTransport: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var readCount = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; readCount += 1; return Array(values.values) }
    func write(_ data: Data, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = data }
    func remove(account: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; values.removeAll() }
}
private final class BackupRemovalTransport: DirectCloudTransport, @unchecked Sendable {
    private let memory = BackupMemoryTransport()
    private let condition = NSCondition()
    private var open: Bool
    private var didStart = false
    private let fails: Bool
    init(blocked: Bool, fails: Bool) { open = !blocked; self.fails = fails }
    var started: Bool { condition.lock(); defer { condition.unlock() }; return didStart }
    func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    func read() throws -> [Data] { try memory.read() }
    func write(_ data: Data, account: String) throws { try memory.write(data, account: account) }
    func remove(account: String) throws { try memory.remove(account: account) }
    func removeAll() throws {
        condition.lock()
        defer { condition.unlock() }
        didStart = true
        let deadline = Date().addingTimeInterval(10)
        while !open { guard condition.wait(until: deadline) else { throw DirectCloudError.storage } }
        if fails { throw DirectCloudError.storage }
        try memory.removeAll()
    }
}
/// First write waits while later operations remain possible. This exposes an
/// actual transport race unless the production controller serializes its work.
private final class BackupBlockingWriteTransport: DirectCloudTransport, @unchecked Sendable {
    private let condition = NSCondition()
    private var open = false
    private var writeCount = 0
    private var readCount = 0
    private var values: [String: Data] = [:]
    var reads: Int { condition.lock(); defer { condition.unlock() }; return readCount }
    var writes: Int { condition.lock(); defer { condition.unlock() }; return writeCount }
    var snapshot: [Data] { condition.lock(); defer { condition.unlock() }; return Array(values.values) }
    func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    func read() throws -> [Data] { condition.lock(); defer { condition.unlock() }; readCount += 1; return Array(values.values) }
    func write(_ data: Data, account: String) throws {
        condition.lock(); defer { condition.unlock() }
        writeCount += 1
        if writeCount == 1 {
            while !open { if !condition.wait(until: Date().addingTimeInterval(5)) { throw DirectCloudError.storage } }
        }
        values[account] = data
    }
    func remove(account: String) throws { condition.lock(); defer { condition.unlock() }; values.removeValue(forKey: account) }
    func removeAll() throws { condition.lock(); defer { condition.unlock() }; values.removeAll() }
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
