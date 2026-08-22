import CompanionAgentPlatform
import CompanionIPC
import Foundation
import Testing

private final class BootstrapAuthorityClockV1:
    MacDashboardLifecycleWallClockV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    func nowUnixMilliseconds() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Int64) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private actor BootstrapAuthorityIntentStoreV1:
    MacRemoteAccessIntentPersistenceV1
{
    enum CommitMode: Equatable, Sendable {
        case normal
        case throwAfterWrite
        case replaceWithConflict
        case suspendReadbackAfterWrite
    }

    private var snapshot: MacRemoteAccessIntentSnapshotV1?
    private var commitMode: CommitMode = .normal
    private var suspendNextCurrentRead = false
    private var suspendedCurrentRead: CheckedContinuation<Void, Never>?
    private var currentReadObserver: CheckedContinuation<Void, Never>?
    private(set) var replacementCount = 0

    init(_ snapshot: MacRemoteAccessIntentSnapshotV1? = nil) {
        self.snapshot = snapshot
    }

    func current() async -> MacRemoteAccessIntentSnapshotV1? {
        if suspendNextCurrentRead {
            suspendNextCurrentRead = false
            await withCheckedContinuation { continuation in
                suspendedCurrentRead = continuation
                currentReadObserver?.resume()
                currentReadObserver = nil
            }
        }
        return snapshot
    }

    func replaceAtomically(
        _ replacement: MacRemoteAccessIntentSnapshotV1,
        expectedRevision: UInt64?
    ) throws -> MacRemoteAccessIntentCommitResultV1 {
        replacementCount += 1
        let before = snapshot
        guard before?.revision == expectedRevision else {
            throw MacRemoteAccessIntentStoreErrorV1.revisionConflict
        }
        switch commitMode {
        case .normal, .throwAfterWrite, .suspendReadbackAfterWrite:
            snapshot = replacement
        case .replaceWithConflict:
            snapshot = try MacRemoteAccessIntentSnapshotV1(
                revision: replacement.revision,
                desiredEnabled: false,
                commandID: UUID(
                    uuidString: "018f7400-0000-7000-8000-0000000000ff"
                )!,
                recordedAtUnixMilliseconds:
                    replacement.recordedAtUnixMilliseconds
            )
        }
        if commitMode == .suspendReadbackAfterWrite {
            suspendNextCurrentRead = true
        } else if commitMode != .normal {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        return before == nil ? .inserted : .replaced
    }

    func setCommitMode(_ mode: CommitMode) {
        commitMode = mode
    }

    func replaceExternally(
        _ replacement: MacRemoteAccessIntentSnapshotV1?
    ) {
        snapshot = replacement
    }

    func suspendNextCurrent() {
        suspendNextCurrentRead = true
    }

    func waitForSuspendedCurrent() async {
        guard suspendedCurrentRead == nil else { return }
        await withCheckedContinuation { continuation in
            currentReadObserver = continuation
        }
    }

    func resumeSuspendedCurrent() {
        let continuation = suspendedCurrentRead
        suspendedCurrentRead = nil
        continuation?.resume()
    }
}

private final class BootstrapAuthorityRestartCounterV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value = 0

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private let bootstrapAuthorityNowV1: Int64 = 1_787_198_400_000
private let bootstrapAuthorityOfferIDV1 = UUID(
    uuidString: "018f7400-0000-7000-8000-000000000001"
)!
private let bootstrapAuthorityCommandIDV1 = UUID(
    uuidString: "018f7400-0000-7000-8000-000000000002"
)!

private func bootstrapAuthorityCommandV1(
    offer: LocalRemoteAccessBootstrapOfferV0,
    id: UUID = bootstrapAuthorityCommandIDV1
) throws -> LocalRemoteAccessEnableCommandV0 {
    try LocalRemoteAccessEnableCommandV0(
        commandID: id,
        offer: offer,
        confirmedAtUnixMilliseconds: offer.createdAtUnixMilliseconds
    )
}

private func disabledBootstrapIntentV1(
    revision: UInt64 = 4
) throws -> MacRemoteAccessIntentSnapshotV1 {
    try MacRemoteAccessIntentSnapshotV1(
        revision: revision,
        desiredEnabled: false,
        commandID: UUID(
            uuidString: "018f7400-0000-7000-8000-000000000010"
        )!,
        recordedAtUnixMilliseconds: bootstrapAuthorityNowV1 - 1
    )
}

@Test
func bootstrapAuthorityIssuesOneRevisionBoundOfferPerGeneration() async throws {
    let store = BootstrapAuthorityIntentStoreV1()
    let clock = BootstrapAuthorityClockV1(bootstrapAuthorityNowV1)
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: clock,
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )

    let first = try await authority.readOffer(generation: 1)
    #expect(first.offerID == bootstrapAuthorityOfferIDV1)
    #expect(first.expectedIntentRevision == 0)
    #expect(first.createdAtUnixMilliseconds == bootstrapAuthorityNowV1)
    #expect(first.expiresAtUnixMilliseconds == bootstrapAuthorityNowV1 + 300_000)
    let repeated = try await authority.readOffer(generation: 1)
    #expect(repeated == first)

    await authority.invalidate(generation: 1)
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await authority.readOffer(generation: 1)
    }
    let replacement = try await authority.readOffer(generation: 2)
    #expect(replacement.expectedIntentRevision == 0)
}

@Test
func bootstrapAuthorityCommitsExactSuccessorAndReplaysReceipt() async throws {
    let store = BootstrapAuthorityIntentStoreV1(
        try disabledBootstrapIntentV1()
    )
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )
    let offer = try await authority.readOffer(generation: 4)
    #expect(offer.expectedIntentRevision == 4)
    let command = try bootstrapAuthorityCommandV1(offer: offer)
    let receipt = try await authority.enable(
        generation: 4,
        command: command
    )
    try receipt.validate(against: command)
    #expect(receipt.intentRevision == 5)
    let stored = try #require(await store.current())
    #expect(stored.revision == 5)
    #expect(stored.desiredEnabled)
    #expect(stored.commandID == command.commandID)
    #expect(stored.recordedAtUnixMilliseconds == bootstrapAuthorityNowV1)
    #expect(await store.replacementCount == 1)

    let replay = try await authority.enable(
        generation: 4,
        command: command
    )
    #expect(replay == receipt)
    #expect(await store.replacementCount == 1)
}

@Test
func bootstrapAuthorityAcceptsOnlyExactPostWriteReadBack() async throws {
    let ambiguousStore = BootstrapAuthorityIntentStoreV1(
        try disabledBootstrapIntentV1()
    )
    await ambiguousStore.setCommitMode(.throwAfterWrite)
    let ambiguous = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: ambiguousStore,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )
    let offer = try await ambiguous.readOffer(generation: 5)
    let command = try bootstrapAuthorityCommandV1(offer: offer)
    let receipt = try await ambiguous.enable(
        generation: 5,
        command: command
    )
    try receipt.validate(against: command)

    let conflictingStore = BootstrapAuthorityIntentStoreV1(
        try disabledBootstrapIntentV1()
    )
    await conflictingStore.setCommitMode(.replaceWithConflict)
    let conflicting = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: conflictingStore,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )
    let conflictingOffer = try await conflicting.readOffer(generation: 6)
    let conflictingCommand = try bootstrapAuthorityCommandV1(
        offer: conflictingOffer
    )
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.storageAmbiguous
    ) {
        try await conflicting.enable(
            generation: 6,
            command: conflictingCommand
        )
    }
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await conflicting.readOffer(generation: 6)
    }
}

@Test
func bootstrapAuthorityExpiresOfferAndFencesOldGeneration() async throws {
    let store = BootstrapAuthorityIntentStoreV1()
    let clock = BootstrapAuthorityClockV1(bootstrapAuthorityNowV1)
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: clock,
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )
    _ = try await authority.readOffer(generation: 7)
    clock.set(bootstrapAuthorityNowV1 + 300_000)
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.offerExpired
    ) {
        try await authority.readOffer(generation: 7)
    }

    clock.set(bootstrapAuthorityNowV1)
    let replacement = try await authority.readOffer(generation: 8)
    let oldCommand = try bootstrapAuthorityCommandV1(
        offer: try LocalRemoteAccessBootstrapOfferV0(
            offerID: bootstrapAuthorityOfferIDV1,
            expectedIntentRevision: 0,
            createdAtUnixMilliseconds: bootstrapAuthorityNowV1,
            expiresAtUnixMilliseconds: bootstrapAuthorityNowV1 + 300_000
        )
    )
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await authority.enable(generation: 7, command: oldCommand)
    }
    let replacementCommand = try bootstrapAuthorityCommandV1(
        offer: replacement
    )
    let receipt = try await authority.enable(
        generation: 8,
        command: replacementCommand
    )
    try receipt.validate(against: replacementCommand)
}

@Test
func bootstrapAuthorityRejectsChangedCommandAfterDurableSuccess() async throws {
    let store = BootstrapAuthorityIntentStoreV1()
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )
    let offer = try await authority.readOffer(generation: 9)
    let command = try bootstrapAuthorityCommandV1(offer: offer)
    _ = try await authority.enable(generation: 9, command: command)
    let changed = try bootstrapAuthorityCommandV1(
        offer: offer,
        id: UUID(
            uuidString: "018f7400-0000-7000-8000-000000000003"
        )!
    )
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.commandMismatch
    ) {
        try await authority.enable(generation: 9, command: changed)
    }
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await authority.readOffer(generation: 9)
    }
}

@Test
func bootstrapAuthorityFencesSuspendedReadAcrossReplacement() async throws {
    let store = BootstrapAuthorityIntentStoreV1()
    await store.suspendNextCurrent()
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 }
    )

    let staleRead = Task {
        try await authority.readOffer(generation: 10)
    }
    await store.waitForSuspendedCurrent()
    let replacement = try await authority.readOffer(generation: 11)
    await store.resumeSuspendedCurrent()
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await staleRead.value
    }

    let command = try bootstrapAuthorityCommandV1(offer: replacement)
    let receipt = try await authority.enable(
        generation: 11,
        command: command
    )
    try receipt.validate(against: command)
}

@Test
func bootstrapAuthoritySignalsCommittedEnableWhenReplyBecomesImpossible()
    async throws
{
    let store = BootstrapAuthorityIntentStoreV1(
        try disabledBootstrapIntentV1()
    )
    let restart = BootstrapAuthorityRestartCounterV1()
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 },
        onUnacknowledgedDurableChange: { restart.record() }
    )
    let offer = try await authority.readOffer(generation: 12)
    let command = try bootstrapAuthorityCommandV1(offer: offer)
    await store.setCommitMode(.suspendReadbackAfterWrite)

    let enable = Task {
        try await authority.enable(generation: 12, command: command)
    }
    await store.waitForSuspendedCurrent()
    await authority.invalidate(generation: 12)
    await store.resumeSuspendedCurrent()
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await enable.value
    }
    #expect(restart.count == 1)
    let durable = try #require(await store.current())
    #expect(durable.desiredEnabled)
    #expect(durable.revision == 5)
    #expect(durable.commandID == command.commandID)
}

@Test
func bootstrapAuthoritySignalsDurableReceiptAcknowledgementFailureOnce()
    async throws
{
    let store = BootstrapAuthorityIntentStoreV1(
        try disabledBootstrapIntentV1()
    )
    let restart = BootstrapAuthorityRestartCounterV1()
    let authority = MacRemoteAccessBootstrapAuthorityV1(
        intentStore: store,
        wallClock: BootstrapAuthorityClockV1(bootstrapAuthorityNowV1),
        offerIDSource: { bootstrapAuthorityOfferIDV1 },
        onUnacknowledgedDurableChange: { restart.record() }
    )
    let offer = try await authority.readOffer(generation: 13)
    let command = try bootstrapAuthorityCommandV1(offer: offer)
    _ = try await authority.enable(generation: 13, command: command)

    await authority.enabledReceiptWasNotAcknowledged(generation: 13)
    await authority.enabledReceiptWasNotAcknowledged(generation: 13)

    #expect(restart.count == 1)
    await #expect(
        throws: MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
    ) {
        try await authority.enable(generation: 13, command: command)
    }
}
