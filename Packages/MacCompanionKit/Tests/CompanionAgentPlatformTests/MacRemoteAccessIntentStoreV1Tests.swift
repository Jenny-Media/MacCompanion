import CompanionAgentPlatform
import CompanionLifecycle
import Foundation
import Testing

private func remoteIntentSnapshotV1(
    revision: UInt64 = 1,
    enabled: Bool = true,
    commandID: UUID = UUID(
        uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    )!,
    time: Int64 = 1_787_198_400_000
) throws -> MacRemoteAccessIntentSnapshotV1 {
    try MacRemoteAccessIntentSnapshotV1(
        revision: revision,
        desiredEnabled: enabled,
        commandID: commandID,
        recordedAtUnixMilliseconds: time
    )
}

private func remoteIntentTemporaryDirectoryV1() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-remote-intent-\(UUID().uuidString.lowercased())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private actor RemoteIntentMemoryStoreV1:
    MacRemoteAccessIntentPersistenceV1
{
    private var value: MacRemoteAccessIntentSnapshotV1?

    func current() -> MacRemoteAccessIntentSnapshotV1? { value }

    func replaceAtomically(
        _ snapshot: MacRemoteAccessIntentSnapshotV1,
        expectedRevision: UInt64?
    ) throws -> MacRemoteAccessIntentCommitResultV1 {
        guard value?.revision == expectedRevision,
              snapshot.revision == (value?.revision ?? 0) + 1 else {
            throw MacRemoteAccessIntentStoreErrorV1.revisionConflict
        }
        let result: MacRemoteAccessIntentCommitResultV1 = value == nil
            ? .inserted
            : .replaced
        value = snapshot
        return result
    }
}

@Test func remoteIntentCodecIsCanonicalAndStrict() throws {
    let snapshot = try remoteIntentSnapshotV1()
    let data = try MacRemoteAccessIntentStorageCodecV1.encode(snapshot)
    #expect(String(decoding: data, as: UTF8.self) ==
        "{\"commandID\":\"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee\",\"desiredEnabled\":true,\"recordedAtUnixMilliseconds\":1787198400000,\"revision\":1,\"schemaVersion\":1}")
    #expect(try MacRemoteAccessIntentStorageCodecV1.decode(data) == snapshot)

    var unknownText = String(decoding: data, as: UTF8.self)
    unknownText.insert(contentsOf: "\"extra\":false,", at: unknownText.index(after: unknownText.startIndex))
    let unknown = Data(unknownText.utf8)
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try MacRemoteAccessIntentStorageCodecV1.decode(unknown)
    }
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try MacRemoteAccessIntentStorageCodecV1.decode(
            Data("{ \"schemaVersion\": 1 }".utf8)
        )
    }
}

@Test func remoteIntentSnapshotRejectsUnsafeNumbers() {
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try remoteIntentSnapshotV1(revision: 0)
    }
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try remoteIntentSnapshotV1(
            revision: MacRemoteAccessIntentSnapshotV1.maximumSafeInteger + 1
        )
    }
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try remoteIntentSnapshotV1(time: -1)
    }
}

@Test func remoteIntentStoreInsertsReplacesAndReopens() async throws {
    let directory = try remoteIntentTemporaryDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try remoteIntentSnapshotV1()
    let second = try remoteIntentSnapshotV1(
        revision: 2,
        enabled: false,
        commandID: UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!,
        time: 1_787_198_400_001
    )

    do {
        let store = try AtomicFileMacRemoteAccessIntentStoreV1(
            directory: directory
        )
        #expect(try await store.current() == nil)
        #expect(try await store.replaceAtomically(
            first,
            expectedRevision: nil
        ) == .inserted)
        #expect(try await store.replaceAtomically(
            first,
            expectedRevision: nil
        ) == .alreadyPresentExactSnapshot)
        #expect(try await store.replaceAtomically(
            second,
            expectedRevision: 1
        ) == .replaced)
    }

    let reopened = try AtomicFileMacRemoteAccessIntentStoreV1(
        directory: directory
    )
    #expect(try await reopened.current() == second)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: directory.appendingPathComponent(
            "remote-access-intent.json"
        ).path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func remoteIntentStoreFencesStaleRevision() async throws {
    let directory = try remoteIntentTemporaryDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileMacRemoteAccessIntentStoreV1(directory: directory)
    let first = try remoteIntentSnapshotV1()
    _ = try await store.replaceAtomically(first, expectedRevision: nil)
    let invalid = try remoteIntentSnapshotV1(revision: 3, enabled: false)
    await #expect(throws: MacRemoteAccessIntentStoreErrorV1.revisionConflict) {
        try await store.replaceAtomically(invalid, expectedRevision: 1)
    }
    #expect(try await store.current() == first)
}

@Test func remoteIntentStorePreRenameFaultDoesNotPublish() async throws {
    let directory = try remoteIntentTemporaryDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileMacRemoteAccessIntentStoreV1(
        directory: directory,
        injectedFaults: [.beforeRename]
    )
    let snapshot = try remoteIntentSnapshotV1()
    await #expect(throws: MacRemoteAccessIntentStoreErrorV1.injectedFault(
        .beforeRename
    )) {
        try await store.replaceAtomically(snapshot, expectedRevision: nil)
    }
    #expect(try await store.current() == nil)
}

@Test func remoteIntentStorePostRenameFaultConvergesOnReadback() async throws {
    let directory = try remoteIntentTemporaryDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileMacRemoteAccessIntentStoreV1(
        directory: directory,
        injectedFaults: [.afterRenameBeforeDirectorySync]
    )
    let snapshot = try remoteIntentSnapshotV1()
    await #expect(throws: MacRemoteAccessIntentStoreErrorV1.injectedFault(
        .afterRenameBeforeDirectorySync
    )) {
        try await store.replaceAtomically(snapshot, expectedRevision: nil)
    }
    #expect(try await store.current() == snapshot)
}

@Test func remoteIntentStoreRejectsUnknownVisibleState() throws {
    let directory = try remoteIntentTemporaryDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("unexpected".utf8).write(
        to: directory.appendingPathComponent("unexpected.txt")
    )
    #expect(throws: MacRemoteAccessIntentStoreErrorV1.unsafeStorage) {
        try AtomicFileMacRemoteAccessIntentStoreV1(directory: directory)
    }
}

@Test func remoteIntentStartupLoaderDefaultsDisabledAndNeverRestoresReady()
    async throws
{
    let store = RemoteIntentMemoryStoreV1()
    let loader = MacDashboardLifecycleStartupStateLoaderV1(
        intentStore: store
    )
    let absent = try await loader.loadInitialState(consoleSession: .active)
    #expect(!absent.desiredEnabled)
    #expect(absent.agent == .stopped)
    #expect(absent.menuApp == .stopped)

    _ = try await store.replaceAtomically(
        remoteIntentSnapshotV1(),
        expectedRevision: nil
    )
    let enabled = try await loader.loadInitialState(consoleSession: .locked)
    #expect(enabled.desiredEnabled)
    #expect(enabled.consoleSession == .locked)
    #expect(enabled.agent == .starting)
    #expect(enabled.menuApp == .starting)

    let ambiguous = try await loader.loadInitialState(
        consoleSession: .otherConsoleUserActive
    )
    #expect(ambiguous.desiredEnabled)
    #expect(ambiguous.consoleSession == .otherConsoleUserActive)
    #expect(ambiguous.agent == .starting)
    #expect(ambiguous.menuApp == .starting)
    #expect(!ambiguous.observeAvailable)
    #expect(!ambiguous.newInteractiveControlAvailable)

    let loggedOut = try await loader.loadInitialState(
        consoleSession: .loggedOut
    )
    #expect(loggedOut.desiredEnabled)
    #expect(loggedOut.agent == .stopped)
    #expect(loggedOut.menuApp == .stopped)
}
