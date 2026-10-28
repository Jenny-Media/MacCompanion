#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
@testable import Mac_Companion

private final class KeyboardMemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var pauseNext = false
    private var started = false
    private var reads = 0
    let resumeWrite = DispatchSemaphore(value: 0)
    func pauseNextWrite() { lock.lock(); defer { lock.unlock() }; pauseNext = true }
    var writeStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; reads += 1; return Array(values.values) }
    func write(_ data: Data, account: String) throws {
        lock.lock(); let pause = pauseNext; pauseNext = false; if pause { started = true }; lock.unlock()
        if pause, resumeWrite.wait(timeout: .now() + 5) != .success { throw DirectCloudError.storage }
        lock.lock(); defer { lock.unlock() }; values[account] = data
    }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; values.removeAll() }
}

@MainActor final class KeyboardCloudSyncTests: XCTestCase {
    @MainActor private final class MemoryProfile {
        var data: Data?
        init(_ profile: TerminalControlsProfile = .defaults) throws { data = try JSONEncoder().encode(profile) }
        var store: TerminalControlsStore {
            var store = TerminalControlsStore()
            store.read = { self.data }; store.write = { self.data = $0 }
            store.legacyIDs = { [] }; store.legacyActions = { [] }
            return store
        }
    }
    private func wait(_ sync: DirectKeyboardCloudSync) async throws {
        for _ in 0..<500 {
            if !sync.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Keyboard sync did not settle")
    }
    func testIndexedPolicyMatchesIsolatedServiceAndPrivacyBoundary() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let additions = try XCTUnwrap(root["clientAdditions"] as? [String: Any])
        let cloud = try XCTUnwrap(additions["cloudLibrary"] as? [String: Any])
        let policy = try XCTUnwrap(cloud["keyboardLayouts"] as? [String: Any])
        XCTAssertEqual(policy["service"] as? String, DirectKeyboardCloudSync.service)
        XCTAssertEqual(policy["preserveDeviceLocalSavedButtons"] as? Bool, true)
        XCTAssertEqual(policy["newDeviceReadsBeforeSeedingDefaults"] as? Bool, true)
    }
    func testSaveNotificationRecordsOfflineEditAndJournalSurvivesRestart() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud(), writer = UUID()
        var sync: DirectKeyboardCloudSync? = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"),
            writer: writer, transport: transport, stores: ["terminal": memory.store])
        var profile = try memory.store.load()
        profile.keyboardRows![0].title = "Offline edit"
        _ = try memory.store.save(profile)
        XCTAssertTrue(try transport.read().isEmpty)
        sync?.setEnabled(false); sync = nil
        let restarted = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: writer,
            transport: transport, stores: ["terminal": memory.store], observeChanges: false)
        restarted.setEnabled(true); try await wait(restarted)
        let values = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
        XCTAssertEqual(DirectCloudKeyboardVersion.winner(values, family: .terminal)?.layout.rows[0].title, "Offline edit")
        restarted.setEnabled(false)
    }
    func testProjectionExcludesDefinitionsAndPreservesLocalButtonsAcrossRowDeletion() throws {
        var profile = TerminalControlsProfile.defaults
        let text = TerminalControlAction(title: "PRIVATE-TITLE", kind: .text, text: "PRIVATE-CONTENT", inRow: true)
        profile.actions.append(text)
        profile.freezeKeyboardLayout()
        let originalRow = try XCTUnwrap(profile.addRow(title: "Local", navigation: false))
        profile.addBarPlacement(.saved(text.id), to: originalRow)
        let layout = DirectCloudKeyboardLayout(profile)
        let bytes = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        XCTAssertFalse(bytes.contains(text.id.uuidString)); XCTAssertFalse(bytes.contains(text.text))
        XCTAssertFalse(bytes.contains(text.title))
        var remote = layout
        remote.rows.removeAll { $0.id == originalRow }
        remote.rows[0].keys = [.key("key-f5"), .control(.command)]
        let applied = try remote.applying(to: profile)
        XCTAssertTrue(applied.valid); XCTAssertEqual(applied.actions, profile.actions)
        XCTAssertEqual(applied.resolvedMenuPlacements, profile.resolvedMenuPlacements)
        XCTAssertTrue(applied.resolvedRows.flatMap { applied.barItems(in: $0) }.contains(.saved(text.id)))
        XCTAssertEqual(applied.revision, profile.revision, "The persistence layer owns revision replacement")
    }
    func testBothControlsFamiliesFitTransportAndKeepTheirLocalLibrary() throws {
        for (family, source) in [(TerminalControlsFamily.terminal, TerminalControlsProfile.defaults), (.remoteMac, .remoteDefaults)] {
            let record = DirectCloudKeyboardVersion(family: family, writer: UUID(), revision: 1,
                layout: DirectCloudKeyboardLayout(source))
            try record.validate()
            let restored = try record.layout.applying(to: source)
            XCTAssertTrue(restored.valid); XCTAssertEqual(restored.family, source.family)
            XCTAssertEqual(restored.actions, source.actions)
            XCTAssertEqual(restored.remoteMenus, source.remoteMenus)
        }
    }
    func testMalformedSavedReferenceAndDuplicateRowsAreRejectedWithoutChangingSource() throws {
        let source = TerminalControlsProfile.defaults
        var layout = DirectCloudKeyboardLayout(source)
        layout.rows[0].keys.append(.saved(UUID()))
        XCTAssertThrowsError(try layout.applying(to: source))
        layout = DirectCloudKeyboardLayout(source); layout.rows.append(layout.rows[0])
        XCTAssertThrowsError(try layout.applying(to: source))
        layout = DirectCloudKeyboardLayout(source); layout.rows[0].keys = [.key("unknown")]
        XCTAssertThrowsError(try layout.applying(to: source))
        XCTAssertTrue(source.valid)
    }
    func testMergeRetainsConcurrentWritersAndRejectsConflictingSameRevision() throws {
        let layout = DirectCloudKeyboardLayout(.defaults)
        let first = DirectCloudKeyboardVersion(family: .terminal, writer: UUID(), revision: 1, layout: layout)
        var second = first; second.writer = UUID()
        let a = try DirectCloudKeyboardVersion.merge([first], [second])
        let b = try DirectCloudKeyboardVersion.merge([second], [first])
        XCTAssertEqual(a, b); XCTAssertEqual(a.count, 2)
        XCTAssertEqual(DirectCloudKeyboardVersion.winner(a, family: .terminal),
                       DirectCloudKeyboardVersion.winner(b, family: .terminal))
        var conflict = first; conflict.layout.rows[0].title = "Changed"
        XCTAssertThrowsError(try DirectCloudKeyboardVersion.merge([first], [conflict]))
        XCTAssertThrowsError(try DirectCloudKeyboardVersion.merge([], [first, first]))
    }
    func testTwoDevicesImportCloudBeforeDefaultsThenSyncEditsWhileKeepingPrivateData() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = KeyboardMemoryCloud()
        let a = try MemoryProfile(), b = try MemoryProfile()
        let first = DirectKeyboardCloudSync(url: folder.appending(path: "a.json"), writer: UUID(),
            transport: transport, stores: ["terminal": a.store], observeChanges: false)
        let second = DirectKeyboardCloudSync(url: folder.appending(path: "b.json"), writer: UUID(),
            transport: transport, stores: ["terminal": b.store], observeChanges: false)
        var edited = try a.store.load()
        edited.freezeKeyboardLayout(); edited.keyboardRows![0].title = "My Numbers"
        edited.keyboardRows![0].placements = [.init(item: .key("key-f5"))]
        _ = try a.store.save(edited)
        first.localChange(.terminal)
        XCTAssertTrue(try transport.read().isEmpty, "Off means no cloud access")
        first.setEnabled(true); try await wait(first)
        second.setEnabled(true); try await wait(second)
        XCTAssertEqual(DirectCloudKeyboardLayout(try b.store.load()), DirectCloudKeyboardLayout(try a.store.load()))
        var recipient = try b.store.load()
        let secret = TerminalControlAction(title: "Local snippet", kind: .text, text: "PRIVATE-CONTENT", inRow: true)
        recipient.actions.append(secret)
        recipient.addBarPlacement(.saved(secret.id), to: recipient.resolvedRows[0].id)
        _ = try b.store.save(recipient)
        second.localChange(.terminal); try await wait(second)
        for data in try transport.read() {
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE-CONTENT"))
        }
        first.setEnabled(false); var offline = try a.store.load()
        offline.keyboardRows![0].alignment = .right
        _ = try a.store.save(offline); first.localChange(.terminal)
        first.setEnabled(true); try await wait(first)
        second.refresh(); try await wait(second)
        let retained = try b.store.load()
        XCTAssertEqual(retained.keyboardRows![0].alignment, .right)
        XCTAssertTrue(retained.actions.contains(secret))
        XCTAssertTrue(retained.resolvedRows.flatMap { retained.barItems(in: $0) }.contains(.saved(secret.id)))
        try await first.removeCloudCopies()
        XCTAssertTrue(try transport.read().isEmpty)
        XCTAssertTrue(try a.store.load().valid)
        second.setEnabled(false)
    }
    func testCorruptAndOversizedPayloadsKeepLocalLayouts() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud()
        // Normalize the legacy fixture before isolating cloud-import effects.
        let baseline = try memory.store.load()
        let before = memory.data
        try transport.write(Data("bad".utf8), account: "bad")
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": memory.store], observeChanges: false)
        sync.setEnabled(true); try await wait(sync)
        XCTAssertEqual(memory.data, before)
        XCTAssertEqual(try memory.store.load(), baseline)
        XCTAssertTrue(sync.status.contains("couldn’t sync"))
        var huge = DirectCloudKeyboardLayout(.defaults)
        huge.rows[0].keys = Array(repeating: .key("key-f5"), count: 1000)
        let record = DirectCloudKeyboardVersion(family: .terminal, writer: UUID(), revision: 1, layout: huge)
        XCTAssertThrowsError(try record.validate())
        sync.setEnabled(false)
    }
    func testCloudRemovalDrainsInFlightWriteBeforeDeleting() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud()
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": memory.store], observeChanges: false)
        transport.pauseNextWrite(); sync.setEnabled(true)
        for _ in 0..<500 where !transport.writeStarted { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(transport.writeStarted)
        sync.setEnabled(false) // The parent settings controller disables first.
        var removed = false
        let deletion = Task { try await sync.removeCloudCopies(); removed = true }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(removed, "An admitted write must finish before cloud deletion")
        transport.resumeWrite.signal(); try await deletion.value
        XCTAssertTrue(try transport.read().isEmpty); XCTAssertTrue(try memory.store.load().valid)
    }
    func testCloudRemovalReportsLocalJournalFailureAfterDeletingLayouts() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try MemoryProfile(), transport = KeyboardMemoryCloud()
        var failJournal = false
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": profile.store], observeChanges: false,
            writeJournal: { data, url in
                if failJournal { throw DirectCloudError.storage }
                try data.write(to: url)
            })
        sync.setEnabled(true); try await wait(sync)
        XCTAssertFalse(try transport.read().isEmpty)
        failJournal = true
        do { try await sync.removeCloudCopies(); XCTFail("The local journal failure must remain visible") }
        catch { XCTAssertTrue(try transport.read().isEmpty) }
        XCTAssertTrue(try profile.store.load().valid)
    }
    func testOversizedPendingEditSurvivesRefreshRestartAndCanSyncAgain() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud(), writer = UUID()
        let url = folder.appending(path: "journal.json")
        let first = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
            stores: ["terminal": memory.store], observeChanges: false)
        first.setEnabled(true); try await wait(first)
        var large = try memory.store.load()
        large.keyboardRows![0].placements = (0..<200).map { _ in .init(item: .key("key-f5")) }
        XCTAssertTrue(large.valid)
        _ = try memory.store.save(large); first.localChange(.terminal)
        first.refresh(); try await wait(first)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].placements.count, 200)
        XCTAssertTrue(first.status.contains("couldn’t sync"))
        first.setEnabled(false)
        let restarted = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
            stores: ["terminal": memory.store], observeChanges: false)
        restarted.setEnabled(true); try await wait(restarted)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].placements.count, 200)
        var smaller = try memory.store.load()
        smaller.keyboardRows![0].placements = [.init(item: .key("key-f5"))]
        _ = try memory.store.save(smaller); restarted.localChange(.terminal); try await wait(restarted)
        let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
        XCTAssertEqual(DirectCloudKeyboardVersion.winner(records, family: .terminal)?.layout,
                       DirectCloudKeyboardLayout(try memory.store.load()))
        XCTAssertFalse(restarted.status.contains("couldn’t sync"))
        restarted.setEnabled(false)
    }
    func testFailedJournalWritePreservesEditThroughRefreshRestartAndRetry() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud(), writer = UUID()
        let url = folder.appending(path: "journal.json")
        var failWrites = false
        let write: @MainActor (Data, URL) throws -> Void = { data, destination in
            if failWrites { throw DirectCloudError.storage }
            try DirectClientPlatformV1.write(data, to: destination)
        }
        let first = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
            stores: ["terminal": memory.store], observeChanges: false, writeJournal: write)
        first.setEnabled(true); try await wait(first)
        var edited = try memory.store.load(); edited.keyboardRows![0].title = "Keep my local edit"
        failWrites = true
        _ = try memory.store.save(edited); first.localChange(.terminal)
        first.refresh(); try await wait(first)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep my local edit")
        XCTAssertTrue(first.status.contains("couldn’t be saved"))
        first.setEnabled(false)
        let restarted = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
            stores: ["terminal": memory.store], observeChanges: false, writeJournal: write)
        restarted.setEnabled(true); try await wait(restarted)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep my local edit")
        failWrites = false; restarted.retry(); try await wait(restarted)
        let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
        XCTAssertEqual(DirectCloudKeyboardVersion.winner(records, family: .terminal)?.layout.rows[0].title, "Keep my local edit")
        restarted.setEnabled(false)
    }
    func testLocalOnlySaveBeforeFirstImportDoesNotPublishDefaults() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud()
        var customized = try memory.store.load(); customized.keyboardRows![0].title = "Cloud customization"
        let remote = DirectCloudKeyboardVersion(family: .terminal,
            writer: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, revision: 1,
            layout: DirectCloudKeyboardLayout(customized))
        try transport.write(JSONEncoder().encode(remote), account: remote.account)
        let writer = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: writer,
            transport: transport, stores: ["terminal": memory.store], observeChanges: false)
        var local = try memory.store.load(); local.rowsExpanded = !(local.rowsExpanded ?? false)
        local.actions.append(.init(title: "Local snippet", kind: .text, text: "PRIVATE-CONTENT"))
        _ = try memory.store.save(local); sync.localChange(.terminal)
        sync.setEnabled(true); try await wait(sync)
        let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
        XCTAssertFalse(records.contains { $0.writer == writer }, "A local-only save cannot seed a competing default record")
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Cloud customization")
        XCTAssertTrue(try memory.store.load().actions.contains { $0.text == "PRIVATE-CONTENT" })
        sync.setEnabled(false)
    }
    func testLockedStartupThenLocalOnlySaveDoesNotPublishDefaults() async throws {
        try await checkFirstSaveAfterLockedStartup(changesLayout: false)
    }
    func testLockedStartupThenLayoutSaveStillRecordsActualEdit() async throws {
        try await checkFirstSaveAfterLockedStartup(changesLayout: true)
    }
    private func checkFirstSaveAfterLockedStartup(changesLayout: Bool) async throws {
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let memory = try MemoryProfile(family == .terminal ? .defaults : .remoteDefaults)
            var store = memory.store; store.family = family
            var remoteProfile = try store.load()
            remoteProfile.keyboardRows![0].title = "Cloud customization"
            let transport = KeyboardMemoryCloud()
            let remote = DirectCloudKeyboardVersion(family: family,
                writer: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, revision: 1,
                layout: DirectCloudKeyboardLayout(remoteProfile))
            try transport.write(JSONEncoder().encode(remote), account: remote.account)
            let writer = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
            let journalURL = folder.appending(path: "journal.json")
            var accessible = false
            let sync = DirectKeyboardCloudSync(url: journalURL, writer: writer,
                transport: transport, stores: [family.rawValue: store], canAccess: { accessible })
            XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
            accessible = true
            NotificationCenter.default.post(name: DirectAppLockV1.unlocked, object: nil)
            var local = try store.load()
            local.rowsExpanded = !(local.rowsExpanded ?? false)
            local.actions.append(.init(title: "Local snippet", kind: .text, text: "PRIVATE-LOCKED-CONTENT"))
            if changesLayout { local.keyboardRows![0].title = "Actual local edit" }
            _ = try store.save(local)
            XCTAssertEqual(transport.readCount, 0, "Unlock and local saves must not access cloud while sync is off")
            let journal = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any])
            let versions = try XCTUnwrap(journal["versions"] as? [[String: Any]])
            XCTAssertEqual(versions.count, changesLayout ? 1 : 0, "Only a projected layout edit creates a version")
            sync.setEnabled(true); try await wait(sync)
            let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
            XCTAssertEqual(records.contains { $0.writer == writer }, changesLayout)
            let expected = changesLayout ? "Actual local edit" : "Cloud customization"
            XCTAssertEqual(try store.load().keyboardRows![0].title, expected)
            XCTAssertTrue(try store.load().actions.contains { $0.text == "PRIVATE-LOCKED-CONTENT" })
            sync.setEnabled(false)
        }
    }
    func testReplacingImportedKeyAndDeletingItsRowKeepsSavedPlacementsValid() throws {
        var source = TerminalControlsProfile.defaults
        source.freezeKeyboardLayout()
        let rowID = try XCTUnwrap(source.addRow(title: "Function keys", navigation: false))
        source.addBarPlacement(.key("key-f5"), to: rowID)
        let incoming = DirectCloudKeyboardLayout(source)
        var recipient = try incoming.applying(to: source)
        let text = TerminalControlAction(title: "Local snippet", kind: .text, text: "PRIVATE-CONTENT", inRow: true)
        recipient.actions.append(text)
        XCTAssertTrue(recipient.replaceEditorItem(.key("key-f5"), in: rowID, with: .saved(text.id)))
        XCTAssertTrue(recipient.valid)
        var again = try incoming.applying(to: recipient)
        XCTAssertTrue(again.valid)
        XCTAssertTrue(again.resolvedRows.flatMap { again.barItems(in: $0) }.contains(.saved(text.id)))
        var removed = incoming; removed.rows.removeAll { $0.id == rowID }
        again = try removed.applying(to: again)
        XCTAssertTrue(again.valid)
        XCTAssertTrue(again.barItems(in: try XCTUnwrap(again.resolvedRows.first { $0.kind == .main })).contains(.saved(text.id)))
    }
    func testCloudRoundTripPreservesRestorePresetsIncludingLegacyNumbers() throws {
        let source = TerminalControlsProfile.defaults
        let numbers = try XCTUnwrap(source.resolvedRows.first { $0.preset == .numbers })
        var incoming = DirectCloudKeyboardLayout(source); incoming.rows[0].title = "Incoming change"
        var applied = try incoming.applying(to: source)
        XCTAssertEqual(applied.resolvedRows.first { $0.id == numbers.id }?.preset, .numbers)
        applied.restoreRow(numbers.id)
        XCTAssertEqual(applied.barItems(in: try XCTUnwrap(applied.resolvedRows.first { $0.id == numbers.id })), source.barItems(in: numbers))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(incoming)) as? [String: Any])
        var rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        for index in rows.indices { rows[index].removeValue(forKey: "preset") }
        object["rows"] = rows
        let legacy = try JSONDecoder().decode(DirectCloudKeyboardLayout.self, from: JSONSerialization.data(withJSONObject: object))
        let legacyApplied = try legacy.applying(to: source)
        XCTAssertEqual(legacyApplied.resolvedRows.first { $0.id == numbers.id }?.preset, .numbers)
    }

    func testPendingTerminalLayoutDoesNotBlockSharedRemoteMacFamily() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let terminal = try MemoryProfile(), remote = try MemoryProfile(.remoteDefaults)
        var remoteStore = TerminalControlsStore.remoteMac()
        remoteStore.read = { remote.data }; remoteStore.write = { remote.data = $0 }
        remoteStore.legacyIDs = { [] }; remoteStore.legacyActions = { [] }
        let transport = KeyboardMemoryCloud()
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": terminal.store, "remoteMac": remoteStore], observeChanges: false)
        sync.setEnabled(true); try await wait(sync)
        var large = try terminal.store.load()
        large.keyboardRows![0].placements = (0..<200).map { _ in .init(item: .key("key-f5")) }
        _ = try terminal.store.save(large); sync.localChange(.terminal)
        var edited = try remoteStore.load(); edited.keyboardRows![0].title = "Remote family still syncs"
        _ = try remoteStore.save(edited); sync.localChange(.remoteMac); try await wait(sync)
        XCTAssertEqual(try terminal.store.load().keyboardRows![0].placements.count, 200)
        let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
        XCTAssertEqual(DirectCloudKeyboardVersion.winner(records, family: .remoteMac)?.layout.rows[0].title, "Remote family still syncs")
        sync.setEnabled(false)
    }

    func testFailedImportJournalWriteCannotReapplyOldWinner() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(), transport = KeyboardMemoryCloud()
        var failWrites = false
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": memory.store], observeChanges: false,
            writeJournal: { data, destination in
                if failWrites, try memory.store.load().keyboardRows![0].title == "Keep imported layout" { throw DirectCloudError.storage }
                try DirectClientPlatformV1.write(data, to: destination)
            })
        sync.setEnabled(true); try await wait(sync)
        var imported = try memory.store.load(); imported.keyboardRows![0].title = "Keep imported layout"
        let remote = DirectCloudKeyboardVersion(family: .terminal, writer: UUID(), revision: 2,
            layout: DirectCloudKeyboardLayout(imported))
        try transport.write(JSONEncoder().encode(remote), account: remote.account)
        failWrites = true; sync.refresh(); try await wait(sync)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep imported layout")
        try transport.removeAll(); sync.refresh(); try await wait(sync)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep imported layout")
        failWrites = false; sync.retry(); try await wait(sync)
        XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep imported layout")
        sync.setEnabled(false)
    }

    func testStartupPreservesContextualLegacyRemoteContentBeforeSyncingRows() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try MemoryProfile(.remoteDefaults); memory.data = nil
        let macID = UUID(), transport = KeyboardMemoryCloud()
        let text = VNCQuickAction(title: "Legacy text", kind: .text, text: "PRIVATE-LEGACY-TEXT")
        let shortcut = VNCQuickAction(title: "Legacy shortcut", kind: .shortcut, key: 97, modifiers: [0xffeb])
        func store(legacyMac: UUID? = nil) -> TerminalControlsStore {
            var value = TerminalControlsStore.remoteMac(legacyMac: legacyMac)
            value.read = { memory.data }; value.write = { memory.data = $0 }
            value.legacyRemoteMenus = {
                ["desktop": DirectControlMode.desktop.defaults + (legacyMac == macID ? [text, shortcut] : []),
                 "trackpad": DirectControlMode.trackpad.defaults]
            }
            return value
        }
        var incoming = TerminalControlsProfile.remoteDefaults; incoming.freezeKeyboardLayout()
        incoming.keyboardRows![0].title = "Remote layout"
        let cloud = DirectCloudKeyboardVersion(family: .remoteMac, writer: UUID(), revision: 10,
            layout: DirectCloudKeyboardLayout(incoming))
        try transport.write(JSONEncoder().encode(cloud), account: cloud.account)
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["remoteMac": store()], observeChanges: true)
        XCTAssertNil(memory.data, "Sync-off startup cannot initialize a context-free shared profile")
        sync.setEnabled(true); try await wait(sync)
        XCTAssertNil(memory.data, "Cloud import must wait for the existing context-aware migration")
        let migrated = try store(legacyMac: macID).load()
        XCTAssertTrue(migrated.actions.contains { $0.text == text.text })
        XCTAssertTrue(migrated.actions.contains { $0.title == shortcut.title })
        XCTAssertTrue(migrated.resolvedMenuPlacements.contains { $0.actionID == text.id })
        try await wait(sync)
        let retained = try store(legacyMac: macID).load()
        XCTAssertEqual(retained.keyboardRows![0].title, "Remote layout")
        XCTAssertTrue(retained.actions.contains { $0.text == text.text })
        XCTAssertTrue(retained.resolvedMenuPlacements.contains { $0.actionID == text.id })
        XCTAssertFalse(try transport.read().contains { String(decoding: $0, as: UTF8.self).contains(text.text) })
        sync.setEnabled(false)
    }

    func testFailedImportJournalKeepsLaterEditsWithRemoteRetainedThroughRetryAndRestart() async throws {
        for (beforeImport, restart) in [(false, false), (false, true), (true, false), (true, true)] {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let memory = try MemoryProfile(), transport = KeyboardMemoryCloud(), writer = UUID()
            let url = folder.appending(path: "journal.json")
            let remoteTitle = "Imported revision ten"
            var failJournal = false
            let write: @MainActor (Data, URL) throws -> Void = { data, destination in
                if failJournal {
                    let imported = try memory.store.load().keyboardRows![0].title == remoteTitle
                    if beforeImport || imported { throw DirectCloudError.storage }
                }
                try DirectClientPlatformV1.write(data, to: destination)
            }
            let sync = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
                stores: ["terminal": memory.store], observeChanges: false, writeJournal: write)
            sync.setEnabled(true); try await wait(sync)
            let originalTitle = try memory.store.load().keyboardRows![0].title
            var imported = try memory.store.load(); imported.keyboardRows![0].title = remoteTitle
            let remote = DirectCloudKeyboardVersion(family: .terminal, writer: UUID(), revision: 10,
                layout: DirectCloudKeyboardLayout(imported))
            try transport.write(JSONEncoder().encode(remote), account: remote.account)
            failJournal = true; sync.refresh(); try await wait(sync)
            XCTAssertEqual(try memory.store.load().keyboardRows![0].title, beforeImport ? originalTitle : remoteTitle)
            var edited = try memory.store.load(); edited.keyboardRows![0].title = "Keep my later edit"
            _ = try memory.store.save(edited); sync.localChange(.terminal)
            failJournal = false
            let recovered: DirectKeyboardCloudSync
            if restart {
                sync.setEnabled(false)
                recovered = DirectKeyboardCloudSync(url: url, writer: writer, transport: transport,
                    stores: ["terminal": memory.store], observeChanges: false, writeJournal: write)
                recovered.setEnabled(true)
            } else { recovered = sync; recovered.retry() }
            try await wait(recovered)
            XCTAssertEqual(try memory.store.load().keyboardRows![0].title, "Keep my later edit", "restart=\(restart)")
            let records = try transport.read().map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
            let winner = try XCTUnwrap(DirectCloudKeyboardVersion.winner(records, family: .terminal))
            XCTAssertEqual(winner.layout.rows[0].title, "Keep my later edit")
            XCTAssertGreaterThan(winner.revision, 10)
            recovered.setEnabled(false)
        }
    }

}
#endif
