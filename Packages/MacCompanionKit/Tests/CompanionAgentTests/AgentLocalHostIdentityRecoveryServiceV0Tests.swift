import CompanionAgentNetworkPlatform
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation
import Testing

private let agentRecoveryNowV0: Int64 = 1_787_284_800_000

private struct AgentRecoveryTemporaryDatabaseV0 {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        database = directory.appendingPathComponent("security.sqlite")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func agentRecoveryIdentityV0(
    hostID: UUID,
    tagByte: UInt8,
    fingerprintByte: UInt8,
    timestamp: Int64
) throws -> StoredHostIdentityRecord {
    try StoredHostIdentityRecord(
        hostID: hostID,
        keyApplicationTag: Data(repeating: tagByte, count: 32),
        hostFingerprint: Data(repeating: fingerprintByte, count: 32),
        certificateDER: Data([0x30, tagByte]),
        certificateNotBeforeUnixMilliseconds: timestamp,
        certificateNotAfterUnixMilliseconds: timestamp + 10_000_000,
        establishedAtUnixMilliseconds: timestamp,
        updatedAtUnixMilliseconds: timestamp
    )
}

private actor AgentRecoveryExecutorProbeV0:
    AgentHostIdentityRecoveryExecutingV0
{
    private let store: SQLiteSecurityStore
    private let replacement: StoredHostIdentityRecord
    private var calls = 0

    init(
        store: SQLiteSecurityStore,
        replacement: StoredHostIdentityRecord
    ) {
        self.store = store
        self.replacement = replacement
    }

    func callCount() -> Int { calls }

    package func recover(
        intent: StoredHostIdentityRecoveryIntent
    ) async throws -> StoredHostIdentityRecord {
        calls += 1
        _ = try await store.beginHostIdentityRecovery(
            intent: intent,
            occurredAtUnixMilliseconds: replacement.updatedAtUnixMilliseconds
                - 1
        )
        try await store.completeHostIdentityRecovery(
            recoveryID: intent.recoveryID,
            replacement: replacement
        )
        return replacement
    }
}

private final class AgentRecoveryClockProbeV0: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) { self.value = value }
    func now() -> Int64 { lock.withLock { value } }
    func set(_ value: Int64) { lock.withLock { self.value = value } }
}

private func agentRecoveryCommandV0(
    review: LocalHostIdentityRecoveryReviewV0
) throws -> LocalHostIdentityRecoveryCommandV0 {
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        review: review,
        confirmedAtUnixMilliseconds: review.createdAtUnixMilliseconds + 1
    )
}

private func agentStoredRecoveryIntentV0(
    _ command: LocalHostIdentityRecoveryCommandV0
) throws -> StoredHostIdentityRecoveryIntent {
    let cause: StoredHostIdentityRecoveryCause = switch command.review.cause {
    case .keyUnavailable: .keyUnavailable
    case .suspectedCompromise: .suspectedCompromise
    case .userRequestedReset: .userRequestedReset
    }
    return try StoredHostIdentityRecoveryIntent(
        commandID: command.commandID,
        recoveryID: command.recoveryID,
        reviewID: command.review.reviewID,
        expectedHostID: command.review.hostID,
        expectedHostFingerprint: command.review.hostFingerprint.rawValue,
        cause: cause,
        reviewCreatedAtUnixMilliseconds:
            command.review.createdAtUnixMilliseconds,
        reviewExpiresAtUnixMilliseconds:
            command.review.expiresAtUnixMilliseconds,
        confirmedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
}

@Test func agentLocalRecoveryServiceBindsReviewAndDurablyReplaysReceipt()
    async throws
{
    let temporary = try AgentRecoveryTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try agentRecoveryIdentityV0(
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        tagByte: 0x21,
        fingerprintByte: 0x31,
        timestamp: agentRecoveryNowV0 - 1_000
    )
    let replacement = try agentRecoveryIdentityV0(
        hostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        tagByte: 0x52,
        fingerprintByte: 0x62,
        timestamp: agentRecoveryNowV0 + 10
    )
    try await store.establishHostIdentity(original)
    let executor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let service = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: executor,
        wallNowUnixMilliseconds: { agentRecoveryNowV0 }
    )
    let review = try await service.makeReview(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        cause: .keyUnavailable
    )
    #expect(review.hostID == original.hostID)
    #expect(review.hostFingerprint.rawValue == original.hostFingerprint)
    let command = try agentRecoveryCommandV0(review: review)
    let receipt = try await service.recoverHostIdentity(command)
    try receipt.validate(against: command)
    #expect(await executor.callCount() == 1)

    let restartedExecutor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let restarted = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: restartedExecutor,
        wallNowUnixMilliseconds: { agentRecoveryNowV0 + 301_000 }
    )
    #expect(try await restarted.recoverHostIdentity(command) == receipt)
    #expect(await restartedExecutor.callCount() == 0)
}

@Test func agentLocalRecoveryServiceRejectsForgedReviewBeforeFencing()
    async throws
{
    let temporary = try AgentRecoveryTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try agentRecoveryIdentityV0(
        hostID: UUID(),
        tagByte: 0x11,
        fingerprintByte: 0x22,
        timestamp: agentRecoveryNowV0 - 1_000
    )
    let replacement = try agentRecoveryIdentityV0(
        hostID: UUID(),
        tagByte: 0x33,
        fingerprintByte: 0x44,
        timestamp: agentRecoveryNowV0 + 10
    )
    try await store.establishHostIdentity(original)
    let executor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let service = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: executor,
        wallNowUnixMilliseconds: { agentRecoveryNowV0 }
    )
    _ = try await service.makeReview(reviewID: UUID(), cause: .keyUnavailable)
    let forged = try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(),
        hostID: original.hostID,
        hostFingerprint: WireFingerprint(original.hostFingerprint),
        cause: .suspectedCompromise,
        createdAtUnixMilliseconds: agentRecoveryNowV0,
        expiresAtUnixMilliseconds: agentRecoveryNowV0 + 300_000
    )

    await #expect(
        throws: AgentLocalHostIdentityRecoveryServiceErrorV0.reviewNotCurrent
    ) {
        try await service.recoverHostIdentity(
            agentRecoveryCommandV0(review: forged)
        )
    }
    #expect(await executor.callCount() == 0)
    #expect(try await store.hostIdentity() == original)
}

@Test func agentLocalRecoveryServiceResumesExactFencedReviewAfterRestart()
    async throws
{
    let temporary = try AgentRecoveryTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try agentRecoveryIdentityV0(
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        tagByte: 0x11,
        fingerprintByte: 0x22,
        timestamp: agentRecoveryNowV0 - 1_000
    )
    let replacement = try agentRecoveryIdentityV0(
        hostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        tagByte: 0x33,
        fingerprintByte: 0x44,
        timestamp: agentRecoveryNowV0 + 10
    )
    try await store.establishHostIdentity(original)
    let setupExecutor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let setupService = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: setupExecutor,
        wallNowUnixMilliseconds: { agentRecoveryNowV0 }
    )
    let review = try await setupService.makeReview(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        cause: .suspectedCompromise
    )
    let command = try agentRecoveryCommandV0(review: review)
    let intent = try agentStoredRecoveryIntentV0(command)
    _ = try await store.beginHostIdentityRecovery(
        intent: intent,
        occurredAtUnixMilliseconds: agentRecoveryNowV0 + 1
    )

    let restartedExecutor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let restarted = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: restartedExecutor,
        wallNowUnixMilliseconds: { agentRecoveryNowV0 + 600_000 }
    )
    #expect(try await restarted.resumableReview() == review)
    #expect(try await restarted.resumableCommand() == command)

    let differentCommand = try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(),
        recoveryID: command.recoveryID,
        review: review,
        confirmedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    await #expect(
        throws: AgentLocalHostIdentityRecoveryServiceErrorV0.reviewNotCurrent
    ) {
        try await restarted.recoverHostIdentity(differentCommand)
    }
    #expect(await restartedExecutor.callCount() == 0)

    let receipt = try await restarted.recoverHostIdentity(command)
    try receipt.validate(against: command)
    #expect(await restartedExecutor.callCount() == 1)
    #expect(try await restarted.resumableReview() == review)

    await #expect(
        throws: AgentLocalHostIdentityRecoveryServiceErrorV0.reviewNotCurrent
    ) {
        try await restarted.recoverHostIdentity(differentCommand)
    }
    #expect(await restartedExecutor.callCount() == 1)
}

@Test func agentLocalRecoveryServiceRejectsExpiredOrInvalidatedReview()
    async throws
{
    let temporary = try AgentRecoveryTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try agentRecoveryIdentityV0(
        hostID: UUID(),
        tagByte: 0x11,
        fingerprintByte: 0x22,
        timestamp: agentRecoveryNowV0 - 1_000
    )
    let replacement = try agentRecoveryIdentityV0(
        hostID: UUID(),
        tagByte: 0x33,
        fingerprintByte: 0x44,
        timestamp: agentRecoveryNowV0 + 10
    )
    try await store.establishHostIdentity(original)
    let clock = AgentRecoveryClockProbeV0(agentRecoveryNowV0)
    let executor = AgentRecoveryExecutorProbeV0(
        store: store,
        replacement: replacement
    )
    let service = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: executor,
        wallNowUnixMilliseconds: clock.now
    )
    let review = try await service.makeReview(
        reviewID: UUID(),
        cause: .userRequestedReset
    )
    let command = try agentRecoveryCommandV0(review: review)
    clock.set(review.expiresAtUnixMilliseconds)
    await #expect(
        throws: AgentLocalHostIdentityRecoveryServiceErrorV0.reviewNotCurrent
    ) {
        try await service.recoverHostIdentity(command)
    }
    clock.set(agentRecoveryNowV0 + 1)
    await service.invalidateReview()
    await #expect(
        throws: AgentLocalHostIdentityRecoveryServiceErrorV0.reviewNotCurrent
    ) {
        try await service.recoverHostIdentity(command)
    }
    #expect(await executor.callCount() == 0)
}
