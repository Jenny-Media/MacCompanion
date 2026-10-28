#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
@testable import Mac_Companion

private final class SavedContentMemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var readTotal = 0, writeTotal = 0
    var failAtWrite: Int?
    var failRemoval = false
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
    func removeAll() throws {
        lock.lock(); defer { lock.unlock() }
        if failRemoval { throw DirectCloudError.storage }
        values.removeAll()
    }
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
    #if targetEnvironment(simulator)
    func testSimulatorKeychainSavedContentRoundTrip() throws {
        // Only this test's random service is touched; no real account records.
        let base = DirectCloudKeychain(service: "dev.maccompanion.qa.saved-controls." + UUID().uuidString)
        let transport = DirectSavedControlsTransport(base: base)
        defer { try? transport.removeAll() }
        XCTAssertTrue(try transport.read().isEmpty)
        let action = text(String(repeating: "synthetic ", count: 400))
        var version = DirectCloudSavedVersion(family: .terminal, id: action.id, writer: UUID(), revision: 1,
            value: DirectCloudSavedControl.project(profile(action))[action.id])
        try transport.write(version.encoded(), account: version.account)
        XCTAssertEqual(try transport.read(), [try version.encoded()])
        version.revision = 2
        version.value?.action.text = "updated synthetic text"
        try transport.write(version.encoded(), account: version.account)
        XCTAssertEqual(try transport.read(), [try version.encoded()])
        try transport.removeAll()
        XCTAssertTrue(try transport.read().isEmpty)
    }
    #endif
    func testEnablingSyncWithProductionDefaultControlFamilies() async throws {
        var terminalBytes: Data?, remoteBytes: Data?
        var terminal = TerminalControlsStore(), remote = TerminalControlsStore.remoteMac()
        terminal.read = { terminalBytes }; terminal.write = { terminalBytes = $0 }
        terminal.legacyIDs = { [] }; terminal.legacyActions = { DirectControlMode.terminal.defaults }
        remote.read = { remoteBytes }; remote.write = { remoteBytes = $0 }
        remote.legacyRemoteMenus = { ["desktop": DirectControlMode.desktop.defaults, "trackpad": DirectControlMode.trackpad.defaults] }
        let raw = SavedContentMemoryCloud(), journal = Journal()
        let sync = DirectSavedControlsCloudSync(writer: UUID(), transport: DirectSavedControlsTransport(base: raw),
            stores: ["terminal": terminal, "remoteMac": remote], observeChanges: false,
            readJournal: { try journal.read() }, writeJournal: { try journal.write($0) })
        sync.setEnabled(true); try await wait(sync)
        XCTAssertNil(sync.issue, sync.status)
        XCTAssertNotNil(try terminal.savedControlsCloudProfile())
        XCTAssertNotNil(try remote.savedControlsCloudProfile())
        sync.setEnabled(false)
    }
    func testEnablingSyncAutomaticallyPreparesFreshRecipientForSavedContent() async throws {
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            let raw = SavedContentMemoryCloud(), action = text("automatic-receiver-synthetic-text")
            let senderProfile = try Profile(profile(action, family: family))
            let sender = engine(senderProfile, Journal(), raw)
            sender.setEnabled(true); try await wait(sender); sender.setEnabled(false)
            var bytes: Data?
            var store: TerminalControlsStore = family == .remoteMac ? .remoteMac() : .init()
            store.read = { bytes }; store.write = { bytes = $0 }
            store.legacyIDs = { [] }; store.legacyActions = { [] }
            store.legacyRemoteMenus = { ["desktop": [], "trackpad": []] }
            let journal = Journal(), reads = raw.reads
            let receiver = DirectSavedControlsCloudSync(writer: UUID(), transport: DirectSavedControlsTransport(base: raw),
                stores: [family.rawValue: store], observeChanges: false,
                readJournal: { try journal.read() }, writeJournal: { try journal.write($0) })
            XCTAssertNil(bytes); XCTAssertEqual(raw.reads, reads)
            receiver.setEnabled(true); try await wait(receiver)
            let imported = try store.load()
            XCTAssertEqual(imported.actions.first { $0.id == action.id }?.text, action.text)
            XCTAssertNotNil(try store.savedControlsCloudProfile()); XCTAssertNil(receiver.issue)
            receiver.setEnabled(false)
        }
    }

    func testEnablingSyncPersistsCurrentProfileFormatBeforeSavedContentRead() async throws {
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            let action = text("synthetic existing content")
            let memory = try Profile(profile(action, family: family))
            var record = try XCTUnwrap(JSONSerialization.jsonObject(with: memory.data) as? [String: Any])
            record["version"] = TerminalControlsProfile.currentVersion - 1
            memory.data = try JSONSerialization.data(withJSONObject: record)
            let raw = SavedContentMemoryCloud(), sync = engine(memory, Journal(), raw)
            sync.setEnabled(true); try await wait(sync)
            XCTAssertNil(sync.issue, sync.status)
            let persisted = try JSONDecoder().decode(TerminalControlsProfile.self, from: memory.data)
            XCTAssertEqual(persisted.version, TerminalControlsProfile.currentVersion)
            XCTAssertNotNil(try memory.store.savedControlsCloudProfile())
            XCTAssertEqual(persisted.actions.first { $0.id == action.id }?.text, action.text)
            XCTAssertEqual(try versions(raw).first?.value?.action.text, action.text)
            sync.setEnabled(false)
        }
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
        XCTAssertEqual(policy["unmarkedDefinitionsRemainEligible"] as? Bool, true)
        XCTAssertEqual(policy["explicitPaletteChoiceIsUserDefinition"] as? Bool, true)
        XCTAssertEqual(policy["accessoryKeysUseSavedDefinitionProjection"] as? Bool, true)
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
        let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(TerminalControlsProfile.defaults))
        XCTAssertTrue(decoded.actions.contains { $0.kind == .shortcut && $0.builtIn == .interrupt })
        XCTAssertTrue(DirectCloudSavedControl.project(decoded).isEmpty, "Migration provenance survives persistence")
        var source = TerminalControlsProfile.defaults
        let index = try XCTUnwrap(source.actions.firstIndex { $0.kind == .shortcut })
        source.actions[index].title = "My renamed shortcut"
        XCTAssertEqual(DirectCloudSavedControl.project(source).count, 1)
    }
    func testPaletteReturnSyncsItsDefinitionAndKeyboardAndMenuPositions() async throws {
        let key = try XCTUnwrap(TerminalKeyCatalog.all.first { $0.character == 0xff0d && $0.modifiers.isEmpty })
        var source = TerminalControlsProfile.defaults; source.freezeKeyboardLayout()
        XCTAssertTrue(source.placeEditorItem(.key(key.id), in: .menu))
        let action = try XCTUnwrap(source.actions.first(where: key.matches))
        XCTAssertNil(action.builtIn)
        let main = try XCTUnwrap(source.resolvedRows.first { $0.kind == .main })
        source.placeBarItem(.saved(action.id), in: main.id)
        let raw = SavedContentMemoryCloud(), a = try Profile(source), b = try Profile()
        let first = engine(a, Journal(), raw), second = engine(b, Journal(), raw)
        first.setEnabled(true); try await wait(first); second.setEnabled(true); try await wait(second)
        let received = try b.store.load(), imported = try XCTUnwrap(received.actions.first { $0.id == action.id })
        XCTAssertEqual(imported.character, 0xff0d); XCTAssertEqual(imported.kind, .shortcut)
        XCTAssertTrue(received.resolvedRows.flatMap { received.barItems(in: $0) }.contains(.saved(action.id)))
        XCTAssertTrue(received.resolvedMenuPlacements.contains { $0.actionID == action.id })
        XCTAssertEqual(received.actions.filter { $0.builtIn == .interrupt }.count, 1, "Untouched local defaults are not duplicated")
        first.setEnabled(false); second.setEnabled(false)
    }
    func testUnmarkedOlderReturnAndInterruptDefinitionsRemainEligible() throws {
        for (title, character, modifiers) in [("Return", UInt32(0xff0d), [UInt32]()), ("Interrupt · Ctrl-C", UInt32(0x63), [UInt32(0xffe3)])] {
            var action = TerminalControlAction(title: title, kind: .shortcut, inRow: true)
            action.character = character; action.modifiers = modifiers
            let local = try Profile(profile(action)), loaded = try local.store.load()
            XCTAssertNil(loaded.actions.first { $0.id == action.id }?.builtIn)
            XCTAssertNotNil(DirectCloudSavedControl.project(loaded)[action.id], "Values alone cannot establish a migrated-default origin")
        }
    }
    func testExplicitPaletteSelectionActivatesMatchingMigratedReturn() throws {
        let key = try XCTUnwrap(TerminalKeyCatalog.all.first { $0.character == 0xff0d && $0.modifiers.isEmpty })
        for focusedEditor in [true, false] {
            let migrated = TerminalControlAction(VNCQuickAction(title: "Return", kind: .returnKey))
            var source = TerminalControlsProfile(actions: [migrated]); source.freezeKeyboardLayout()
            XCTAssertEqual(migrated.builtIn, .returnKey); XCTAssertTrue(DirectCloudSavedControl.project(source).isEmpty)
            if focusedEditor { XCTAssertTrue(source.placeEditorItem(.key(key.id), in: .menu)) }
            else { XCTAssertEqual(source.pin(key, in: .keyboard), migrated.id) }
            XCTAssertNil(source.actions.first { $0.id == migrated.id }?.builtIn)
            XCTAssertNotNil(DirectCloudSavedControl.project(source)[migrated.id])
        }
    }
    func testExplicitLegacyShortcutOriginSurvivesSharedMenuMigration() throws {
        let id = UUID(), migrated = VNCQuickAction(id: id, title: "Return", kind: .returnKey)
        let explicit = VNCQuickAction(id: id, title: "Return", kind: .shortcut, key: 0xff0d)
        var source = TerminalControlsProfile(family: .remoteMac)
        source.importRemoteMenus(["desktop": [migrated], "trackpad": [explicit]])
        XCTAssertEqual(source.actions.count, 1)
        XCTAssertNil(source.actions.first?.builtIn)
        XCTAssertNotNil(DirectCloudSavedControl.project(source)[id])
    }
    func testKeypadAccessoryPinsRoundTripBothDestinationsAndFamilies() async throws {
        let keys = try ["key-f1", "key-home", "key-left"].map { try XCTUnwrap(TerminalKeyCatalog.key($0)) }
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            for destination in TerminalControlsDestination.allCases {
                var source: TerminalControlsProfile = family == .terminal ? .defaults : .remoteDefaults
                var target: TerminalControlsProfile = family == .terminal ? .defaults : .remoteDefaults
                if family == .remoteMac {
                    source.remoteMenus = ["desktop": [], "trackpad": []]; source.remoteMenuMode = "desktop"
                    target.remoteMenus = ["desktop": [], "trackpad": []]; target.remoteMenuMode = "desktop"
                }
                // The real remote-Mac owner prepares and persists rows before
                // exposing its profile to cloud sync; keep both fixtures ready.
                source.freezeKeyboardLayout(); target.freezeKeyboardLayout()
                let ids = keys.map { source.pin($0, in: destination) }
                source.captureRemoteMenu()
                let a = try Profile(source), b = try Profile(target), raw = SavedContentMemoryCloud()
                let first = engine(a, Journal(), raw), second = engine(b, Journal(), raw)
                first.setEnabled(true); try await wait(first); second.setEnabled(true); try await wait(second)
                let received = try b.store.load()
                for (index, id) in ids.enumerated() {
                    let action = try XCTUnwrap(received.actions.first { $0.id == id },
                        "\(family.rawValue)/\(destination.rawValue): sender=\(first.status); receiver=\(second.status); wire=\(raw.snapshot.count); received keys=\(received.actions.filter { $0.kind == .key }.count)")
                    XCTAssertEqual(action.kind, .key); XCTAssertEqual(action.key, keys[index].accessory)
                    if destination == .keyboard { XCTAssertTrue(received.resolvedRows.flatMap { received.barItems(in: $0) }.contains(.saved(id))) }
                    else { XCTAssertTrue(received.resolvedMenuPlacements.contains { $0.actionID == id }) }
                }
                var edit = try a.store.load(); edit.delete(ids[0]); _ = try a.store.save(edit)
                first.localChange(); try await wait(first); second.refresh(); try await wait(second)
                XCTAssertFalse(try b.store.load().actions.contains { $0.id == ids[0] }, "Key definitions and placements also propagate tombstones")
                XCTAssertTrue(try b.store.load().actions.contains { $0.id == ids[1] })
                first.setEnabled(false); second.setEnabled(false)
            }
        }
    }
    func testAccessoryProjectionExcludesInactivePayloadsAndKeepsThemLocal() throws {
        var action = TerminalControlAction(title: "Synthetic F1", kind: .key, key: .f1, text: "synthetic inactive content", inRow: true)
        action.character = 0x63; action.modifiers = [0xffe3]; action.confirmBeforeRunning = true
        action.presetID = "synthetic inactive preset"; action.usage = "synthetic inactive usage"
        let source = profile(action)
        var value = try XCTUnwrap(DirectCloudSavedControl.project(source)[action.id])
        try value.validate(family: .terminal)
        let bytes = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertFalse(bytes.contains("synthetic inactive"))
        XCTAssertEqual(value.action.character, 0); XCTAssertTrue(value.action.modifiers.isEmpty); XCTAssertTrue(value.action.text.isEmpty)
        XCTAssertNil(value.action.confirmBeforeRunning); XCTAssertNil(value.action.presetID); XCTAssertNil(value.action.usage)
        var malformed = value; malformed.action.text = "synthetic foreign inactive content"
        XCTAssertThrowsError(try malformed.validate(family: .terminal))
        value.action.title = "Synced F1"
        let applied = try DirectCloudSavedControl.applying([action.id: value], to: source)
        let local = try XCTUnwrap(applied.actions.first { $0.id == action.id })
        XCTAssertEqual(local.title, "Synced F1"); XCTAssertEqual(local.key, .f1)
        XCTAssertEqual(local.text, action.text); XCTAssertEqual(local.character, action.character); XCTAssertEqual(local.modifiers, action.modifiers)
        XCTAssertEqual(local.presetID, action.presetID); XCTAssertEqual(local.usage, action.usage)
        XCTAssertEqual(DirectCloudSavedControl.project(applied)[action.id], value, "Inactive local fields cannot become an import echo")
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
    func testReplacingImportedKeyRoundTripsAfterLayoutFirstDelivery() throws {
        var template = TerminalControlsProfile.defaults; template.freezeKeyboardLayout()
        let row = try XCTUnwrap(template.addRow(title: "Synthetic Function Keys", navigation: false))
        template.addBarPlacement(.key("key-f5"), to: row)
        template.addBarPlacement(.key("key-f6"), to: row)
        var author = try DirectCloudKeyboardLayout(template).applying(to: template)
        let action = text(); author.actions.append(action)
        XCTAssertTrue(author.replaceEditorItem(.key("key-f5"), in: row, with: .saved(action.id)))
        XCTAssertTrue(author.valid)
        let value = try XCTUnwrap(DirectCloudSavedControl.project(author)[action.id])
        var receiver = try DirectCloudKeyboardLayout(author).applying(to: template)
        let incoming: [UUID: DirectCloudSavedControl?] = [action.id: value]
        receiver = try DirectCloudSavedControl.applying(incoming, to: receiver)
        XCTAssertTrue(receiver.valid)
        let importedRow = try XCTUnwrap(receiver.resolvedRows.first { $0.id == row })
        XCTAssertEqual(receiver.barItems(in: importedRow), [.saved(action.id), .key("key-f6")])
        XCTAssertEqual(receiver.actions.first { $0.id == action.id }?.text, action.text)
        let again = try DirectCloudSavedControl.applying(incoming, to: receiver)
        XCTAssertEqual(again, receiver, "Refresh must not keep reallocating placement identities")
    }
    func testIndependentlySavedButtonsWithSamePlacementIDRemainValidAndStable() throws {
        let first = text("synthetic one"), second = text("synthetic two")
        var a = try XCTUnwrap(DirectCloudSavedControl.project(profile(first))[first.id])
        var b = try XCTUnwrap(DirectCloudSavedControl.project(profile(second))[second.id])
        a.bar[0].placement = "synthetic-shared-placement"
        b.bar[0].placement = "synthetic-shared-placement"
        let values: [UUID: DirectCloudSavedControl?] = [first.id: a, second.id: b]
        let applied = try DirectCloudSavedControl.applying(values, to: .defaults)
        XCTAssertTrue(applied.valid)
        let placements = applied.resolvedRows.flatMap { applied.barPlacements(in: $0) }
        XCTAssertEqual(Set(placements.map(\.id)).count, placements.count)
        XCTAssertEqual(Set(applied.actions.filter { $0.kind == .text }.map(\.text)), [first.text, second.text])
        XCTAssertEqual(try DirectCloudSavedControl.applying(values, to: applied), applied)
    }
    func testConcurrentFavoriteReplacementKeepsBothMenuDefinitions() throws {
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            let first = text("synthetic favorite one"), second = text("synthetic favorite two")
            var original = profile(first, family: family)
            let favorite = TerminalMenuPlacement(actionID: first.id)
            original.menuPlacements = [favorite]
            if family == .remoteMac { original.remoteMenus = ["desktop": [favorite], "trackpad": [favorite]] }
            let firstValue = try XCTUnwrap(DirectCloudSavedControl.project(original)[first.id])
            var replacement = original
            XCTAssertTrue(replacement.placeEditorItem(.saved(second.id), in: .menu,
                replacing: .saved(first.id), placementID: favorite.id.uuidString, definition: second))
            if family == .remoteMac { replacement.captureRemoteMenu(); replacement.remoteMenus!["trackpad"] = [.init(id: favorite.id, actionID: second.id)] }
            let secondValue = try XCTUnwrap(DirectCloudSavedControl.project(replacement)[second.id])
            let incoming: [UUID: DirectCloudSavedControl?] = [first.id: firstValue, second.id: secondValue]
            let applied = try DirectCloudSavedControl.applying(incoming, to: original)
            XCTAssertTrue(applied.valid)
            let menus = family == .remoteMac ? try XCTUnwrap(applied.remoteMenus).values.map { $0 } : [applied.resolvedMenuPlacements]
            for menu in menus {
                XCTAssertEqual(Set(menu.map(\.actionID)), [first.id, second.id])
                XCTAssertEqual(Set(menu.map(\.id)).count, 2)
            }
            XCTAssertEqual(try DirectCloudSavedControl.applying(incoming, to: applied), applied)
        }
    }
    func testCollisionNormalizationDoesNotPublishReceiverEdits() async throws {
        var template = TerminalControlsProfile.defaults; template.freezeKeyboardLayout()
        let row = try XCTUnwrap(template.addRow(title: "Synthetic Function Keys", navigation: false))
        template.addBarPlacement(.key("key-f5"), to: row); template.addBarPlacement(.key("key-f6"), to: row)
        var author = try DirectCloudKeyboardLayout(template).applying(to: template)
        let action = text(); author.actions.append(action)
        XCTAssertTrue(author.replaceEditorItem(.key("key-f5"), in: row, with: .saved(action.id)))
        let raw = SavedContentMemoryCloud(), a = try Profile(author)
        let b = try Profile(DirectCloudKeyboardLayout(author).applying(to: template))
        let senderID = UUID(), receiverID = UUID()
        let sender = engine(a, Journal(), raw, writer: senderID)
        let receiver = engine(b, Journal(), raw, writer: receiverID, observe: true)
        sender.setEnabled(true); try await wait(sender)
        receiver.setEnabled(true); try await wait(receiver)
        receiver.refresh(); try await wait(receiver)
        XCTAssertTrue(try b.store.load().valid)
        XCTAssertEqual(try b.store.load().actions.first { $0.id == action.id }?.text, action.text)
        XCTAssertFalse(try versions(raw).contains { $0.writer == receiverID }, "Import normalization is not a new local edit")
        sender.setEnabled(false); receiver.setEnabled(false)
    }
    func testUnreadableMacJournalStillRemovesAllThreeServicesOnRepeatedRemoval() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let corrupt = Data("synthetic unreadable Mac journal".utf8); try corrupt.write(to: url)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: url) }
        let macs = SavedContentMemoryCloud(), layouts = SavedContentMemoryCloud(), content = SavedContentMemoryCloud()
        let cloud = DirectCloudSyncV1(defaults: defaults, url: url, transport: macs, writerID: UUID(),
                                     keyboardTransport: layouts, savedControlsTransport: content)
        for _ in 0..<2 {
            for service in [macs, layouts, content] { service.inject(Data("synthetic cloud data".utf8), account: "synthetic") }
            cloud.removeCloudCopies()
            for _ in 0..<500 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(cloud.busy); XCTAssertFalse(cloud.enabled)
            XCTAssertTrue(macs.snapshot.isEmpty); XCTAssertTrue(layouts.snapshot.isEmpty); XCTAssertTrue(content.snapshot.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
            XCTAssertEqual(cloud.recovery?.reason, .cloudRemoval, "Cloud deletion must not claim unreadable local history was repaired")
        }
    }
    func testUnavailableServiceDoesNotSkipOtherCloudRemovals() async throws {
        struct History: Codable { var schema = 1; var versions: [DirectCloudVersion] }
        for failedService in 0..<3 {
            let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: url) }
            let services = (0..<3).map { _ in SavedContentMemoryCloud() }
            for service in services { service.inject(Data("synthetic cloud data".utf8), account: "synthetic") }
            services[failedService].failRemoval = true
            let writer = UUID(), tombstone = DirectCloudVersion(id: UUID(), writer: writer, revision: 7, mac: nil, preferences: nil)
            let history = try JSONEncoder().encode(History(versions: [tombstone])); try history.write(to: url)
            let cloud = DirectCloudSyncV1(defaults: defaults, url: url, transport: services[0], writerID: writer,
                                         keyboardTransport: services[1], savedControlsTransport: services[2])
            cloud.removeCloudCopies()
            for _ in 0..<500 where cloud.busy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(cloud.busy); XCTAssertFalse(cloud.enabled)
            for index in services.indices { XCTAssertEqual(services[index].snapshot.isEmpty, index != failedService) }
            XCTAssertEqual(cloud.recovery?.reason, .cloudRemoval)
            if failedService == 0 {
                XCTAssertEqual(try Data(contentsOf: url), history, "A failed Mac-service removal must retain its revision and deletion history")
            } else {
                XCTAssertTrue(try JSONDecoder().decode(History.self, from: Data(contentsOf: url)).versions.isEmpty)
            }
        }
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
    func testDeletionAfterFailedImportHistorySurvivesRetryAndRestart() async throws {
        for restart in [false, true] {
            let action = text(), raw = SavedContentMemoryCloud(), a = try Profile(profile(action)), b = try Profile()
            let one = engine(a, Journal(), raw); one.setEnabled(true); try await wait(one)
            let writer = UUID(), journal = Journal()
            let two = engine(b, journal, raw, writer: writer)
            journal.failAtWrite = journal.writes + 3
            two.setEnabled(true); try await wait(two)
            XCTAssertNotNil(try b.store.load().actions.first { $0.id == action.id })
            XCTAssertTrue(two.status.contains("history"))
            var edited = try b.store.load(); edited.delete(action.id); _ = try b.store.save(edited)
            journal.failAtWrite = nil
            let recovered: DirectSavedControlsCloudSync
            if restart { two.setEnabled(false); recovered = engine(b, journal, raw, writer: writer); recovered.setEnabled(true) }
            else { recovered = two; recovered.retry() }
            try await wait(recovered)
            XCTAssertNil(try b.store.load().actions.first { $0.id == action.id }, "Deleted imported content must stay deleted")
            let records = try versions(raw)
            let key = b.family.rawValue + "." + action.id.uuidString.lowercased()
            XCTAssertNil(DirectCloudSavedVersion.winners(records)[key]?.value)
            one.setEnabled(false); recovered.setEnabled(false)
        }
    }

    func testOfflineEditsKeepLosingTextOnceAndSequentialEditsStayQuiet() async throws {
        let action = text("base"), raw = SavedContentMemoryCloud()
        let a = try Profile(profile(action)), b = try Profile(), ja = Journal(), jb = Journal()
        let writerA = UUID(), writerB = UUID()
        let one = engine(a, ja, raw, writer: writerA), two = engine(b, jb, raw, writer: writerB)
        one.setEnabled(true); try await wait(one); two.setEnabled(true); try await wait(two)
        one.setEnabled(false); two.setEnabled(false)
        var left = try a.store.load(); left.actions[left.actions.firstIndex { $0.id == action.id }!].text = "first offline edit"
        _ = try a.store.save(left); one.localChange()
        var right = try b.store.load(); right.actions[right.actions.firstIndex { $0.id == action.id }!].text = "second offline edit"
        _ = try b.store.save(right); two.localChange()
        one.setEnabled(true); try await wait(one)
        two.setEnabled(true); try await wait(two); one.refresh(); try await wait(one)
        XCTAssertEqual(try a.store.load().actions.first { $0.id == action.id }?.text, "second offline edit")
        for memory in [a, b] {
            XCTAssertEqual(try memory.store.load().syncState.recovered.compactMap { $0.control?.action.text }, ["first offline edit"])
        }
        let library = DirectControlsRecoveryLibrary(stores: [.terminal: b.store])
        XCTAssertTrue(library.discard(try XCTUnwrap(library.entries.first)))
        two.refresh(); try await wait(two); XCTAssertTrue(library.entries.isEmpty)
        two.setEnabled(false)
        let restarted = engine(b, jb, raw, writer: writerB); restarted.setEnabled(true); try await wait(restarted)
        XCTAssertTrue(library.entries.isEmpty, "Dismissed copies must not return after restart")
        var sequential = try b.store.load(); sequential.actions[sequential.actions.firstIndex { $0.id == action.id }!].text = "later ordinary edit"
        _ = try b.store.save(sequential); restarted.localChange(); try await wait(restarted)
        one.refresh(); try await wait(one)
        XCTAssertEqual(try a.store.load().actions.first { $0.id == action.id }?.text, "later ordinary edit")
        XCTAssertTrue(library.entries.isEmpty, "Successors are not conflicts")
        XCTAssertEqual(try a.store.load().syncState.recovered.count, 1, "Ordinary sync adds no recovery copy")
        one.setEnabled(false); restarted.setEnabled(false)
    }

    func testConcurrentDeletionKeepsEditRecoverableAndRestoresSeparateCopy() async throws {
        for deletionFirst in [false, true] {
            let action = text("base"), raw = SavedContentMemoryCloud(), a = try Profile(profile(action)), b = try Profile()
            let one = engine(a, Journal(), raw), two = engine(b, Journal(), raw)
            one.setEnabled(true); try await wait(one); two.setEnabled(true); try await wait(two)
            one.setEnabled(false); two.setEnabled(false)
            var deleted = try a.store.load(); deleted.delete(action.id); _ = try a.store.save(deleted); one.localChange()
            var edited = try b.store.load(); edited.actions[edited.actions.firstIndex { $0.id == action.id }!].text = "keep this conflicting edit"
            _ = try b.store.save(edited); two.localChange()
            let first = deletionFirst ? one : two, second = deletionFirst ? two : one
            first.setEnabled(true); try await wait(first); second.setEnabled(true); try await wait(second)
            first.refresh(); try await wait(first)
            XCTAssertNil(try a.store.load().actions.first { $0.id == action.id })
            XCTAssertNil(try b.store.load().actions.first { $0.id == action.id })
            let recovery = DirectControlsRecoveryLibrary(stores: [.terminal: b.store])
            let entry = try XCTUnwrap(recovery.entries.first)
            XCTAssertEqual(entry.control?.action.text, "keep this conflicting edit")
            XCTAssertTrue(recovery.restore(entry)); two.localChange(); try await wait(two)
            let restored = try b.store.load()
            XCTAssertNil(restored.actions.first { $0.id == action.id })
            let copy = try XCTUnwrap(restored.actions.first { $0.text == "keep this conflicting edit" })
            XCTAssertNotEqual(copy.id, action.id); XCTAssertTrue(copy.title.hasSuffix("(Recovered copy)"))
            XCTAssertTrue(restored.resolvedRows.flatMap(\.actionIDs).contains(copy.id))
            XCTAssertTrue(recovery.entries.isEmpty)
            one.setEnabled(false); two.setEnabled(false)
        }
    }

    func testUnappliedImportDoesNotBecomePhantomDeletion() async throws {
        let action = text(), raw = SavedContentMemoryCloud(), a = try Profile(profile(action)), b = try Profile()
        let one = engine(a, Journal(), raw); one.setEnabled(true); try await wait(one)
        var failSave = true, store = b.store
        store.write = { if failSave { throw DirectCloudError.storage }; b.data = $0 }
        let journal = Journal(), writer = UUID()
        let two = DirectSavedControlsCloudSync(writer: writer, transport: DirectSavedControlsTransport(base: raw),
            stores: ["terminal": store], observeChanges: false, readJournal: { try journal.read() }, writeJournal: { try journal.write($0) })
        two.setEnabled(true); try await wait(two); XCTAssertNotNil(two.issue)
        XCTAssertNil(try b.store.load().actions.first { $0.id == action.id })
        failSave = false; two.retry(); try await wait(two)
        XCTAssertNotNil(try b.store.load().actions.first { $0.id == action.id })
        XCTAssertFalse(try versions(raw).contains { $0.writer == writer && $0.value == nil })
        one.setEnabled(false); two.setEnabled(false)
    }

    func testDifferentConcurrentDefinitionsMergeWithoutRecoveries() async throws {
        let raw = SavedContentMemoryCloud(), first = text("one"), second = text("two")
        let a = try Profile(profile(first)), b = try Profile(profile(second))
        let one = engine(a, Journal(), raw), two = engine(b, Journal(), raw)
        one.setEnabled(true); try await wait(one); two.setEnabled(true); try await wait(two)
        one.refresh(); try await wait(one)
        for memory in [a,b] {
            let loaded = try memory.store.load()
            XCTAssertTrue(Set([first.id,second.id]).isSubset(of: Set(loaded.actions.map(\.id))))
            XCTAssertTrue(loaded.syncState.recovered.isEmpty)
        }
        one.setEnabled(false); two.setEnabled(false)
    }

    func testRecoveredShortcutsAreInspectableDataAndProjectionExcludesHistory() throws {
        var action = TerminalControlAction(title: "Synthetic shortcut", kind: .shortcut)
        action.character = 0x61; action.modifiers = [0xffe3]
        let saved = try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id])
        var local = TerminalControlsProfile.defaults, state = local.syncState
        let entry = DirectControlsRecoveredChange(id: "synthetic-shortcut-recovery", family: .terminal, control: saved)
        state.recovered = [entry]; local.syncState = state
        let memory = try Profile(local), library = DirectControlsRecoveryLibrary(stores: [.terminal: memory.store])
        XCTAssertTrue(DirectCloudSavedControl.project(local).isEmpty, "Recovery is never a cloud definition")
        XCTAssertTrue(library.restore(entry))
        let restored = try memory.store.load()
        XCTAssertEqual(restored.actions.filter { $0.title.hasSuffix("(Recovered copy)") }.count, 1)
        XCTAssertTrue(restored.syncState.recovered.isEmpty)
        // Restore writes only a definition; it has no session or input executor.
    }

    func testRecoverySaveFailureAndLockedAccessPreserveCopies() throws {
        var local = profile(text("active")), state = local.syncState
        let value = try XCTUnwrap(DirectCloudSavedControl.project(profile(text("recovered private text"))).values.first)
        let entry = DirectControlsRecoveredChange(id: "synthetic-storage-recovery", family: .terminal, control: value)
        state.recovered = [entry]; local.syncState = state
        let memory = try Profile(local), before = memory.data
        var store = memory.store; store.write = { _ in throw DirectCloudError.storage }
        let library = DirectControlsRecoveryLibrary(stores: [.terminal: store])
        XCTAssertFalse(library.restore(entry)); XCTAssertNotNil(library.error); XCTAssertEqual(memory.data,before)
        let locked = DirectControlsRecoveryLibrary(stores: [.terminal: memory.store], canAccess: { false })
        XCTAssertTrue(locked.entries.isEmpty); XCTAssertFalse(locked.discard(entry)); XCTAssertEqual(memory.data,before)
    }

    func testStartOverCanReseedCurrentContentWithoutClearingRecovery() async throws {
        let action = text("current local content"), raw = SavedContentMemoryCloud(), memory = try Profile(profile(action))
        let sync = engine(memory, Journal(), raw)
        sync.setEnabled(true); try await wait(sync)
        var local = try memory.store.load(); local.actions[local.actions.firstIndex { $0.id == action.id }!].text = "current updated content"
        _ = try memory.store.save(local); sync.localChange(); try await wait(sync)
        try await sync.removeCloudCopies(); XCTAssertTrue(raw.snapshot.isEmpty)
        XCTAssertEqual(try memory.store.load().actions.first { $0.id == action.id }?.text, "current updated content")
        sync.setEnabled(true); try await wait(sync)
        XCTAssertNil(sync.issue)
        XCTAssertEqual(try versions(raw).first { $0.id == action.id }?.value?.action.text,"current updated content")
        sync.setEnabled(false)
    }

    func testStartOverDoesNotRestoreDelayedDeletedDefinition() async throws {
        let action=text("old deleted value"), raw=SavedContentMemoryCloud(), memory=try Profile(profile(action))
        let sync=engine(memory,Journal(),raw)
        sync.setEnabled(true); try await wait(sync)
        let old=try XCTUnwrap(versions(raw).first { $0.id==action.id })
        var local=try memory.store.load(); local.delete(action.id); _=try memory.store.save(local)
        sync.localChange(); try await wait(sync); try await sync.removeCloudCopies()
        try DirectSavedControlsTransport(base:raw).write(old.encoded(),account:old.account)
        sync.setEnabled(true); try await wait(sync)
        XCTAssertNil(try memory.store.load().actions.first { $0.id==action.id })
        sync.setEnabled(false)
    }

    func testRecoveryReadWarningClearsAfterStorageRecovers() throws {
        let action=text("synthetic recoverable text"), value=try XCTUnwrap(DirectCloudSavedControl.project(profile(action))[action.id])
        var local=TerminalControlsProfile.defaults, state=local.syncState
        state.recovered=[.init(id:"read-retry",family:.terminal,control:value)]; local.syncState=state
        let memory=try Profile(local); var fail=true, store=memory.store
        store.read={ if fail { throw DirectCloudError.storage }; return memory.data }
        let library=DirectControlsRecoveryLibrary(stores:[.terminal:store])
        XCTAssertNotNil(library.error); fail=false; library.reload()
        XCTAssertNil(library.error); XCTAssertEqual(library.entries.count,1)
    }

    func testRecoveryDiscardWhileOffCannotConsumeResetReseeding() async throws {
        let action=text("deleted text"), raw=SavedContentMemoryCloud(), memory=try Profile(profile(action))
        let sync=engine(memory,Journal(),raw,observe:true)
        sync.setEnabled(true); try await wait(sync)
        let original=try XCTUnwrap(versions(raw).first { $0.id==action.id })
        var local=try memory.store.load(); local.delete(action.id)
        var state=local.syncState
        state.recovered=[.init(id:"reset-retained-recovery",family:.terminal,control:original.value)]
        local.syncState=state; _=try memory.store.save(local); try await wait(sync)
        try await sync.removeCloudCopies()
        let recovery=DirectControlsRecoveryLibrary(stores:[.terminal:memory.store])
        XCTAssertTrue(recovery.discard(try XCTUnwrap(recovery.entries.first)))
        try DirectSavedControlsTransport(base:raw).write(original.encoded(),account:original.account)
        sync.setEnabled(true); try await wait(sync)
        XCTAssertNil(try memory.store.load().actions.first { $0.id==action.id })
        sync.setEnabled(false)
    }

}
#endif
