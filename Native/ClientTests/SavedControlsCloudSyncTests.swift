#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
@testable import Mac_Companion

private final class SavedContentMemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var readTotal = 0, writeTotal = 0
    var failAtWrite: Int?
    private var pause = false, started = false
    let resume = DispatchSemaphore(value: 0)
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readTotal }
    var writes: Int { lock.lock(); defer { lock.unlock() }; return writeTotal }
    var writeStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    var snapshot: [String: Data] { lock.lock(); defer { lock.unlock() }; return values }
    func pauseNextWrite() { lock.lock(); defer { lock.unlock() }; pause = true }
    func inject(_ data: Data, account: String) { lock.lock(); defer { lock.unlock() }; values[account] = data }
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; readTotal += 1; return Array(values.values) }
    func write(_ data: Data, account: String) throws {
        lock.lock(); writeTotal += 1; let fails = writeTotal == failAtWrite, waits = pause; pause = false
        if waits { started = true }; lock.unlock()
        if fails { throw DirectCloudError.storage }
        if waits, resume.wait(timeout: .now() + 5) != .success { throw DirectCloudError.storage }
        inject(data, account: account)
    }
    func remove(account: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; values.removeAll() }
}

@MainActor final class SavedControlsCloudSyncTests: XCTestCase {
    @MainActor private final class Journal {
        var data: Data?
        var failWrite = false
        var writes = 0
        var failAtWrite: Int?
        var reads = 0
        func read() throws -> Data? { reads += 1; return data }
        func write(_ next: Data) throws { writes += 1; if failWrite || writes == failAtWrite { throw DirectCloudError.storage }; data = next }
    }
    @MainActor private final class Profile {
        var data: Data
        let family: TerminalControlsFamily
        init(_ profile: TerminalControlsProfile = .defaults) throws {
            family = profile.family ?? .terminal; data = try JSONEncoder().encode(profile)
        }
        var store: TerminalControlsStore {
            var value: TerminalControlsStore = family == .remoteMac ? .remoteMac() : .init()
            value.read = { self.data }; value.write = { self.data = $0 }
            value.legacyIDs = { [] }; value.legacyActions = { [] }
            value.legacyRemoteMenus = { ["desktop": [], "trackpad": []] }
            return value
        }
    }
    private func text(_ content: String = "synthetic saved content") -> TerminalControlAction {
        .init(title: "Synthetic Text", kind: .text, text: content, inRow: true, inMenu: true)
    }
    private func profile(_ action: TerminalControlAction, family: TerminalControlsFamily = .terminal) -> TerminalControlsProfile {
        var value: TerminalControlsProfile = family == .terminal ? .defaults : .remoteDefaults
        if family == .remoteMac { value.remoteMenus = ["desktop": [], "trackpad": []]; value.remoteMenuMode = "desktop" }
        value.freezeKeyboardLayout(); value.actions.append(action)
        let main = value.keyboardRows!.firstIndex { $0.kind == .main }!
        var row = value.keyboardRows![main]
        var entries = row.placements; entries.insert(.init(id: "synthetic-placement-" + action.id.uuidString, item: .saved(action.id)), at: 1)
        row.placements = entries; value.keyboardRows![main] = row
        return value
    }
    private func engine(_ memory: Profile, _ journal: Journal, _ raw: SavedContentMemoryCloud, writer: UUID = UUID(), observe: Bool = false,
                        canAccess: @escaping @MainActor () -> Bool = { true }) -> DirectSavedControlsCloudSync {
        .init(writer: writer, transport: DirectSavedControlsTransport(base: raw), stores: [memory.family.rawValue: memory.store],
            observeChanges: observe, canAccess: canAccess, readJournal: { try journal.read() }, writeJournal: { try journal.write($0) })
    }
    private func wait(_ sync: DirectSavedControlsCloudSync) async throws {
        for _ in 0..<600 {
            if !sync.busy { return }; try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Saved-content sync did not settle")
    }
    private func versions(_ raw: SavedContentMemoryCloud) throws -> [DirectCloudSavedVersion] {
        try DirectSavedControlsTransport(base: raw).read().map { try JSONDecoder().decode(DirectCloudSavedVersion.self, from: $0) }
    }
    func testIndexedPolicyUsesMainSyncAndCompleteVersions() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let additions = try XCTUnwrap(data["clientAdditions"] as? [String: Any])
        let cloud = try XCTUnwrap(additions["cloudLibrary"] as? [String: Any])
        let policy = try XCTUnwrap(cloud["savedControls"] as? [String: Any])
        XCTAssertEqual(policy["service"] as? String, DirectSavedControlsTransport.service)
        XCTAssertEqual(policy["defaultEnabled"] as? Bool, false)
        XCTAssertEqual(policy["requiresSeparateConsent"] as? Bool, false)
        XCTAssertEqual(policy["followsMainSync"] as? Bool, true)
        XCTAssertEqual(policy["enabledMainSettingIncludesExistingContent"] as? Bool, true)
        XCTAssertEqual(policy["importExecutesActions"] as? Bool, false)
        XCTAssertEqual(policy["maximumLogicalBytes"] as? Int, DirectCloudSavedVersion.maximumBytes)
        XCTAssertEqual(policy["pieceBytes"] as? Int, DirectSavedControlsTransport.pieceBytes)
    }
    func testProjectionKeepsTextAndPositionsWithoutUnrelatedPreferences() throws {
        let action = text(), local = profile(action)
        let value = try XCTUnwrap(DirectCloudSavedControl.project(local)[action.id])
        let applied = try DirectCloudSavedControl.applying([action.id: value], to: .defaults)
        XCTAssertEqual(DirectCloudSavedControl.project(applied)[action.id], value)
        XCTAssertEqual(value.bar.first?.index, 1)
        XCTAssertTrue(applied.valid); XCTAssertEqual(applied.actions.first { $0.id == action.id }?.text, action.text)
        XCTAssertEqual(applied.importedMacs, [])
    }
    func testUntouchedMigratedBuiltinsAreNotDuplicatedAsUserDefinitions() throws {
        XCTAssertTrue(DirectCloudSavedControl.project(.defaults).isEmpty)
        var source = TerminalControlsProfile.defaults
        let index = try XCTUnwrap(source.actions.firstIndex { $0.kind == .shortcut })
        source.actions[index].title = "My renamed shortcut"
        XCTAssertEqual(DirectCloudSavedControl.project(source).count, 1)
    }
    func testReturningToUntouchedBuiltinKeepsItsLocalDefinition() throws {
        let source = TerminalControlsProfile.defaults
        let action = try XCTUnwrap(source.actions.first { $0.kind == .shortcut })
        let applied = try DirectCloudSavedControl.applying([action.id: nil], to: source)
        XCTAssertTrue(applied.actions.contains { $0.id == action.id })
    }
    func testOversizedLocalPlacementEditIsRetainedWithoutTruncation() async throws {
        let action = text(), memory = try Profile(profile(action)), raw = SavedContentMemoryCloud()
        let sync = engine(memory, Journal(), raw)
        var edit = try memory.store.load()
        let main = edit.keyboardRows!.firstIndex { $0.kind == .main }!
        edit.keyboardRows![main].placements = (0..<1000).map { .init(id: "synthetic-oversized-placement-\($0)", item: .saved(action.id)) }
        XCTAssertTrue(edit.valid); _ = try memory.store.save(edit); sync.localChange()
        sync.setEnabled(true); try await wait(sync)
        XCTAssertEqual(try memory.store.load().keyboardRows![main].placements.count, 1000)
        XCTAssertTrue(sync.status.contains("exceed")); XCTAssertTrue(raw.snapshot.isEmpty)
        sync.setEnabled(false)
    }
    func testRemoteMacRetainsBothMenuFavoritesAndLocalMode() throws {
        let action = text(); var local = profile(action, family: .remoteMac)
        let placement = TerminalMenuPlacement(actionID: action.id)
        local.remoteMenus = ["desktop": [placement], "trackpad": [placement]]
        local.menuPlacements = [placement]
        let value = try XCTUnwrap(DirectCloudSavedControl.project(local)[action.id]); try value.validate(family: .remoteMac)
        var receiver = TerminalControlsProfile.remoteDefaults
        receiver.remoteMenus = ["desktop": [], "trackpad": []]; receiver.remoteMenuMode = "trackpad"; receiver.rowsExpanded = true
        let applied = try DirectCloudSavedControl.applying([action.id: value], to: receiver)
        XCTAssertEqual(applied.remoteMenus?["desktop"]?.map(\.actionID), [action.id])
        XCTAssertEqual(applied.remoteMenus?["trackpad"]?.map(\.actionID), [action.id])
        XCTAssertEqual(applied.remoteMenuMode, "trackpad"); XCTAssertEqual(applied.rowsExpanded, true)
    }
    func testFull4096ByteTextRoundTripsAndOldPiecesAreCollected() throws {
        let action = text(String(repeating: "x", count: 4096)), raw = SavedContentMemoryCloud()
        let transport = DirectSavedControlsTransport(base: raw)
        var version = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id]))
        try transport.write(version.encoded(), account: version.account)
        let originalCount = raw.snapshot.count
        XCTAssertTrue(raw.snapshot.values.allSatisfy { $0.count <= 4096 })
        XCTAssertEqual(try versions(raw).first?.value?.action.text, action.text)
        version.revision = 2; version.value!.action.text = "short synthetic text"
        try transport.write(version.encoded(), account: version.account)
        XCTAssertLessThan(raw.snapshot.count, originalCount)
        XCTAssertEqual(try versions(raw), [version])
    }
    func testIncompleteInitialWriteDoesNotBecomeAnEmptyLibraryAndCanResume() throws {
        let action = text(String(repeating: "y", count: 4096)), raw = SavedContentMemoryCloud(), transport = DirectSavedControlsTransport(base: raw)
        let version = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id]))
        raw.failAtWrite = 2
        XCTAssertThrowsError(try transport.write(version.encoded(), account: version.account))
        XCTAssertThrowsError(try transport.read())
        raw.failAtWrite = nil; try transport.write(version.encoded(), account: version.account)
        XCTAssertEqual(try versions(raw), [version])
    }
    func testPartialUpdateRetainsPriorCompleteGeneration() throws {
        let action = text(), raw = SavedContentMemoryCloud(), transport = DirectSavedControlsTransport(base: raw)
        var version = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id]))
        try transport.write(version.encoded(), account: version.account)
        let old = version
        version.revision = 2; version.value!.action.text = String(repeating: "z", count: 4096)
        raw.failAtWrite = raw.writes + 2
        XCTAssertThrowsError(try transport.write(version.encoded(), account: version.account))
        XCTAssertEqual(try versions(raw), [old])
        raw.failAtWrite = nil; try transport.write(version.encoded(), account: version.account)
        XCTAssertEqual(try versions(raw), [version])
    }
    func testCorruptPieceDigestIsRejected() throws {
        let action = text(), raw = SavedContentMemoryCloud(), transport = DirectSavedControlsTransport(base: raw)
        let version = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id]))
        try transport.write(version.encoded(), account: version.account)
        let part = try XCTUnwrap(raw.snapshot.first { $0.key.contains(".part.") })
        var wire = try JSONDecoder().decode(DirectSavedControlsTransport.Wire.self, from: part.value)
        wire.data![0] ^= 1
        raw.inject(try JSONEncoder().encode(wire), account: part.key)
        XCTAssertThrowsError(try transport.read())
    }
    func testCapacityIsCheckedBeforeAnyNewWireWrite() throws {
        let raw = SavedContentMemoryCloud()
        for _ in 0..<512 {
            let wire = DirectSavedControlsTransport.Wire(account: "terminal." + UUID().uuidString.lowercased() + "." + UUID().uuidString.lowercased(),
                generation: UUID(), index: 0, data: Data([1]))
            raw.inject(try JSONEncoder().encode(wire), account: wire.slot)
        }
        let action = text(), before = raw.snapshot
        let value = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id]))
        XCTAssertThrowsError(try DirectSavedControlsTransport(base: raw).write(value.encoded(), account: value.account))
        XCTAssertEqual(raw.writes, 0); XCTAssertEqual(raw.snapshot, before)
    }
    func testPerDefinitionMergeAndDeterministicTombstoneConflict() throws {
        let action = text(), payload = try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id])
        let a = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, revision: 5, value: payload)
        var b = a; b.writer = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!; b.value = nil
        XCTAssertNil(DirectCloudSavedVersion.winners(try DirectCloudSavedVersion.merge([a], [b]))[a.key]?.value)
        var conflict = a; conflict.value!.action.text = "different synthetic content"
        XCTAssertThrowsError(try DirectCloudSavedVersion.merge([a], [conflict]))
    }
    func testDisabledEngineMakesNoCloudReadsOrWrites() async throws {
        let memory = try Profile(profile(text())), journal = Journal(), raw = SavedContentMemoryCloud()
        let sync = engine(memory, journal, raw)
        var edit = try memory.store.load(); edit.actions[edit.actions.count - 1].text = "offline synthetic edit"
        _ = try memory.store.save(edit); sync.localChange(); sync.refresh()
        XCTAssertEqual(raw.reads, 0); XCTAssertEqual(raw.writes, 0)
    }
    func testLockedStartupDefersPrivateJournalAndProfileAccess() async throws {
        let memory = try Profile(profile(text())), journal = Journal(), raw = SavedContentMemoryCloud()
        var allowed = false
        let sync = engine(memory, journal, raw, canAccess: { allowed })
        sync.setEnabled(true); XCTAssertEqual(journal.reads, 0); XCTAssertEqual(raw.reads, 0)
        allowed = true; sync.refresh(); try await wait(sync)
        XCTAssertGreaterThan(journal.reads, 0); XCTAssertFalse(try versions(raw).isEmpty)
        sync.setEnabled(false)
    }
    func testTwoDevicesKeepIndependentAdditionsAndPropagateDeletion() async throws {
        let first = text("first synthetic content"), second = text("second synthetic content")
        let a = try Profile(profile(first)), b = try Profile(profile(second)), raw = SavedContentMemoryCloud()
        let one = engine(a, Journal(), raw), two = engine(b, Journal(), raw)
        one.setEnabled(true); try await wait(one); two.setEnabled(true); try await wait(two)
        one.refresh(); try await wait(one)
        for memory in [a, b] { XCTAssertTrue(Set(try memory.store.load().actions.map(\.id)).isSuperset(of: [first.id, second.id])) }
        var edited = try a.store.load(); edited.delete(first.id); _ = try a.store.save(edited); one.localChange(); try await wait(one)
        two.refresh(); try await wait(two)
        XCTAssertFalse(try b.store.load().actions.contains { $0.id == first.id })
        XCTAssertTrue(try b.store.load().actions.contains { $0.id == second.id })
        one.setEnabled(false); two.setEnabled(false)
    }
    func testOfflineEditSurvivesRestartAndRebasesAgainstFetchedClock() async throws {
        let action = text(), a = try Profile(profile(action)), b = try Profile(), raw = SavedContentMemoryCloud(), journal = Journal(), writer = UUID()
        let first = engine(a, journal, raw, writer: writer)
        first.setEnabled(true); try await wait(first); first.setEnabled(false)
        var edit = try a.store.load(); edit.actions[edit.actions.count - 1].text = "offline synthetic revision"
        _ = try a.store.save(edit); first.localChange()
        let restarted = engine(a, journal, raw, writer: writer), second = engine(b, Journal(), raw)
        restarted.setEnabled(true); try await wait(restarted); second.setEnabled(true); try await wait(second)
        XCTAssertEqual(try b.store.load().actions.first { $0.id == action.id }?.text, "offline synthetic revision")
        restarted.setEnabled(false); second.setEnabled(false)
    }
    func testFailedFetchedJournalWritePreservesContentUntilRetry() async throws {
        let action = text(), a = try Profile(profile(action)), b = try Profile(), raw = SavedContentMemoryCloud()
        let one = engine(a, Journal(), raw); one.setEnabled(true); try await wait(one)
        let journal = Journal(), two = engine(b, journal, raw)
        _ = try b.store.load()
        let before = b.data; journal.failWrite = true
        two.setEnabled(true); try await wait(two)
        XCTAssertEqual(b.data, before); XCTAssertTrue(two.status.contains("history"))
        journal.failWrite = false; two.retry(); try await wait(two)
        XCTAssertEqual(try b.store.load().actions.first { $0.id == action.id }?.text, action.text)
        one.setEnabled(false); two.setEnabled(false)
    }
    func testAdmittedPartialWriteRepairsAfterRestartBeforeImport() async throws {
        let action = text(String(repeating: "w", count: 4096)), memory = try Profile(profile(action)), raw = SavedContentMemoryCloud(), journal = Journal(), writer = UUID()
        let first = engine(memory, journal, raw, writer: writer)
        raw.failAtWrite = 2; first.setEnabled(true); try await wait(first); first.setEnabled(false)
        XCTAssertThrowsError(try versions(raw)); XCTAssertTrue(try memory.store.load().actions.contains { $0.id == action.id })
        raw.failAtWrite = nil
        let restarted = engine(memory, journal, raw, writer: writer); restarted.setEnabled(true); try await wait(restarted)
        XCTAssertEqual(try versions(raw).first?.value?.action.text, action.text); restarted.setEnabled(false)
    }
    func testCloudRemovalDrainsAdmittedWriteAndKeepsLocalContent() async throws {
        let action = text(), memory = try Profile(profile(action)), raw = SavedContentMemoryCloud(), sync = engine(memory, Journal(), raw)
        raw.pauseNextWrite(); sync.setEnabled(true)
        for _ in 0..<500 where !raw.writeStarted { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(raw.writeStarted)
        var removed = false
        let deletion = Task { try await sync.removeCloudCopies(); removed = true }
        try await Task.sleep(for: .milliseconds(20)); XCTAssertFalse(removed)
        raw.resume.signal(); try await deletion.value
        XCTAssertTrue(raw.snapshot.isEmpty); XCTAssertTrue(try memory.store.load().actions.contains { $0.id == action.id })
    }
    func testLayoutImportReappliesSavedPositionsWithoutEchoingContentAsLocalEdits() async throws {
        let action = text(), raw = SavedContentMemoryCloud(), a = try Profile(profile(action)), b = try Profile()
        var local = try a.store.load(); let row = try XCTUnwrap(local.addRow(title: "Synthetic Row", navigation: false))
        local.removeBarItem(.saved(action.id)); local.addBarPlacement(.saved(action.id), to: row)
        _ = try a.store.save(local)
        let writerA = UUID(), writerB = UUID(), one = engine(a, Journal(), raw, writer: writerA), two = engine(b, Journal(), raw, writer: writerB, observe: true)
        one.setEnabled(true); try await wait(one); two.setEnabled(true); try await wait(two)
        XCTAssertTrue(try b.store.load().resolvedRows.first { $0.kind == .main }!.actionIDs.contains(action.id))
        let layout = DirectCloudKeyboardLayout(try a.store.load())
        let imported = try layout.applying(to: b.store.load()); _ = try b.store.save(imported, cloudImport: true)
        try await wait(two)
        XCTAssertTrue(try b.store.load().resolvedRows.first { $0.id == row }!.actionIDs.contains(action.id))
        XCTAssertFalse(try versions(raw).contains { $0.writer == writerB })
        one.setEnabled(false); two.setEnabled(false)
    }
    func testMainSyncDefaultsOffAndRemovalDisablesTheSingleSetting() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let content = SavedContentMemoryCloud(); content.inject(Data("synthetic".utf8), account: "synthetic")
        let cloud = DirectCloudSyncV1(defaults: defaults, url: url, transport: SavedContentMemoryCloud(), writerID: UUID(), savedControlsTransport: content)
        XCTAssertFalse(cloud.enabled)
        cloud.setEnabled(true); XCTAssertTrue(defaults.bool(forKey: DirectCloudSyncV1.enabledKey))
        cloud.removeCloudCopies()
        for _ in 0..<500 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertFalse(cloud.enabled); XCTAssertTrue(content.snapshot.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: DirectCloudSyncV1.enabledKey))
    }
    func testExistingEnabledMainSyncIgnoresObsoleteSavedContentFlags() throws {
        for oldChoice in [false, true] {
            let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(true, forKey: DirectCloudSyncV1.enabledKey)
            defaults.set(oldChoice, forKey: "direct-cloud-saved-controls-enabled-v1")
            defaults.set(UUID().uuidString, forKey: "direct-cloud-saved-controls-consent-writer-v1")
            let cloud = DirectCloudSyncV1(defaults: defaults, url: URL.temporaryDirectory.appending(path: UUID().uuidString), transport: SavedContentMemoryCloud(), writerID: UUID())
            XCTAssertTrue(cloud.enabled, "Only the main choice governs sync")
        }
    }
    func testObsoleteContentConsentCannotTurnMainSyncOn() throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "direct-cloud-saved-controls-enabled-v1")
        let cloud = DirectCloudSyncV1(defaults: defaults, url: URL.temporaryDirectory.appending(path: UUID().uuidString), transport: SavedContentMemoryCloud(), writerID: UUID())
        XCTAssertFalse(cloud.enabled)
    }
    func testUnreadableMacJournalDoesNotSkipSavedContentDeletion() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let corrupt = Data("synthetic unreadable journal".utf8)
        try corrupt.write(to: url)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: url) }
        let macs = SavedContentMemoryCloud(), content = SavedContentMemoryCloud()
        content.inject(Data("synthetic cloud content".utf8), account: "synthetic-account")
        let cloud = DirectCloudSyncV1(defaults: defaults, url: url, transport: macs, writerID: UUID(), savedControlsTransport: content)
        XCTAssertNotNil(cloud.recovery)
        cloud.removeCloudCopies()
        for _ in 0..<600 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(cloud.busy); XCTAssertTrue(content.snapshot.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), corrupt, "Unreadable local history must be preserved")
        XCTAssertNotNil(cloud.recovery, "Deleting cloud copies does not repair unreadable local history")
    }
    func testLibraryRankAboveUnmanagedInterruptSurvivesRoundTrip() throws {
        var custom = TerminalControlAction(title: "Synthetic Shortcut", kind: .shortcut)
        custom.character = 0x61; custom.modifiers = [0xffe3]
        var source = profile(custom)
        let builtin = try XCTUnwrap(source.actions.first { $0.title == "Interrupt · Ctrl-C" })
        source.shortcutOrder = [custom.id, builtin.id]
        let value = try XCTUnwrap(DirectCloudSavedControl.project(source)[custom.id])
        XCTAssertEqual(value.libraryIndex, 0)
        let applied = try DirectCloudSavedControl.applying([custom.id: value], to: source)
        XCTAssertEqual(applied.savedItems(.shortcuts).map(\.id), [custom.id, builtin.id])
    }
    func testLegacyCollisionMigrationDoesNotPublishProvisionalIdentities() async throws {
        let macs = [UUID(), UUID()], shared = UUID(), raw = SavedContentMemoryCloud(), journal = Journal()
        var bytes: Data?
        var store = TerminalControlsStore()
        store.read = { bytes }; store.write = { bytes = $0 }; store.legacyActions = { [] }
        store.legacyIDs = { macs }
        store.legacyKeyboard = { mac in .init(snippets: [.init(id: shared, name: "Synthetic legacy text", text: mac == macs[0] ? "first synthetic value" : "second synthetic value")]) }
        let sync = DirectSavedControlsCloudSync(writer: UUID(), transport: DirectSavedControlsTransport(base: raw),
            stores: ["terminal": store], observeChanges: false, readJournal: { try journal.read() }, writeJournal: { try journal.write($0) })
        XCTAssertNil(bytes, "An off-state baseline must not commit private-profile migration")
        let migrated = try store.load(); XCTAssertEqual(migrated.actions.filter { $0.kind == .text }.count, 2)
        sync.localChange(); sync.setEnabled(true); try await wait(sync)
        let records = try versions(raw)
        XCTAssertEqual(records.count, 2, "Only durable definition IDs should be published")
        XCTAssertFalse(records.contains { $0.value == nil }, "Migration must not create phantom tombstones")
        sync.setEnabled(false)
    }
    func testFailedPostImportJournalDoesNotRepublishFallbackPlacement() async throws {
        let action = text(), raw = SavedContentMemoryCloud(), a = try Profile(profile(action)), b = try Profile()
        var local = try a.store.load(); let row = try XCTUnwrap(local.addRow(title: "Synthetic remote row", navigation: false))
        local.removeBarItem(.saved(action.id)); local.addBarPlacement(.saved(action.id), to: row); _ = try a.store.save(local)
        let one = engine(a, Journal(), raw); one.setEnabled(true); try await wait(one)
        let writerB = UUID(), journal = Journal(), two = engine(b, journal, raw, writer: writerB)
        journal.failAtWrite = journal.writes + 3
        two.setEnabled(true); try await wait(two)
        XCTAssertTrue(try b.store.load().resolvedRows.first { $0.kind == .main }!.actionIDs.contains(action.id))
        XCTAssertTrue(two.status.contains("history"))
        journal.failAtWrite = nil; two.retry(); try await wait(two)
        XCTAssertFalse(try versions(raw).contains { $0.writer == writerB }, "An imported fallback is not a local layout edit")
        one.setEnabled(false); two.setEnabled(false)
    }
}
#endif
