import CompanionHost
import CompanionHostPersistence
import CompanionPersistence
import Foundation
import Testing

private struct TemporaryStore {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccompanion-host-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        database = directory.appendingPathComponent("security.sqlite3")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FixedClock: HostStatusClock {
    func nowUnixMilliseconds() -> Int64 { 1_787_198_400_900 }
}

private struct FixedSampler: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 100,
            cpuUtilizationBasisPoints: 500,
            memoryTotalBytes: 1_000,
            memoryUsedBytes: 500,
            storageTotalBytes: 2_000,
            storageAvailableBytes: 1_000,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

@Test func durableStatusSequenceSurvivesAuthorityRecreation() async throws {
    let temporary = try TemporaryStore()
    defer { temporary.remove() }
    let generation = UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let firstBootstrap = try await SQLiteStatusSequenceCommitter.bootstrap(
        store: store,
        initialGeneration: generation
    )
    let firstAuthority = try HostStatusAuthority(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        sequence: firstBootstrap.state,
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: firstBootstrap.committer
    )
    #expect(try await firstAuthority.snapshot(hostState: .userSessionActive).revision == 0)
    #expect(try await store.statusSequence()?.nextRevision == 1)

    let secondBootstrap = try await SQLiteStatusSequenceCommitter.bootstrap(
        store: store,
        initialGeneration: UUID()
    )
    let secondAuthority = try HostStatusAuthority(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        sequence: secondBootstrap.state,
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: secondBootstrap.committer
    )
    let resumed = try await secondAuthority.snapshot(hostState: .userSessionActive)
    #expect(resumed.generation == generation)
    #expect(resumed.revision == 1)
    #expect(try await store.statusSequence()?.nextRevision == 2)
}

@Test func databaseCommitFailureReturnsNoSnapshotAndConsumesNoRevision() async throws {
    let temporary = try TemporaryStore()
    defer { temporary.remove() }
    let generation = UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!
    let setupStore = try SQLiteSecurityStore(path: temporary.database.path)
    let setup = try await SQLiteStatusSequenceCommitter.bootstrap(
        store: setupStore,
        initialGeneration: generation
    )

    let faultingStore = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeTransactionCommit]
    )
    let authority = try HostStatusAuthority(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        sequence: setup.state,
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: SQLiteStatusSequenceCommitter(store: faultingStore)
    )

    await #expect(throws: SecurityStoreError.injectedFault(.beforeTransactionCommit)) {
        _ = try await authority.snapshot(hostState: .userSessionActive)
    }
    #expect(await authority.sequenceState().nextRevision == 0)
    #expect(try await setupStore.statusSequence()?.nextRevision == 0)
}

@Test func staleAuthorityCannotReuseACommittedRevision() async throws {
    let temporary = try TemporaryStore()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let bootstrap = try await SQLiteStatusSequenceCommitter.bootstrap(
        store: store,
        initialGeneration: UUID()
    )
    let first = try HostStatusAuthority(
        hostID: UUID(),
        sequence: bootstrap.state,
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: bootstrap.committer
    )
    let stale = try HostStatusAuthority(
        hostID: UUID(),
        sequence: bootstrap.state,
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: bootstrap.committer
    )

    _ = try await first.snapshot(hostState: .userSessionActive)
    await #expect(throws: SecurityStoreError.statusSequenceConflict) {
        _ = try await stale.snapshot(hostState: .userSessionActive)
    }
    #expect(await stale.sequenceState().nextRevision == 0)
}
