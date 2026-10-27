#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import XCTest
@testable import Mac_Companion

private final class KeyboardMemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var pauseNext = false
    private var started = false
    let resumeWrite = DispatchSemaphore(value: 0)
    func pauseNextWrite() { lock.lock(); defer { lock.unlock() }; pauseNext = true }
    var writeStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; return Array(values.values) }
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
        let before = memory.data
        try transport.write(Data("bad".utf8), account: "bad")
        let sync = DirectKeyboardCloudSync(url: folder.appending(path: "journal.json"), writer: UUID(),
            transport: transport, stores: ["terminal": memory.store], observeChanges: false)
        sync.setEnabled(true); try await wait(sync)
        XCTAssertEqual(memory.data, before)
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
}
#endif
