import CompanionAgentNetworkPlatform
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation
import Testing

private let deliveryRecoveryNowV0: Int64 = 1_787_284_800_000

private enum DeliveryRecoveryProbeErrorV0: Error { case injected }

private struct DeliveryRecoveryDatabaseV0 {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-recovery-delivery-\(UUID())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        database = directory.appendingPathComponent("security.sqlite3")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func deliveryRecoveryIdentityV0(
    hostID: UUID,
    byte: UInt8,
    timestamp: Int64
) throws -> StoredHostIdentityRecord {
    try StoredHostIdentityRecord(
        hostID: hostID,
        keyApplicationTag: Data(repeating: byte, count: 32),
        hostFingerprint: Data(repeating: byte &+ 1, count: 32),
        certificateDER: Data([0x30, byte]),
        certificateNotBeforeUnixMilliseconds: timestamp,
        certificateNotAfterUnixMilliseconds: timestamp + 10_000_000,
        establishedAtUnixMilliseconds: timestamp,
        updatedAtUnixMilliseconds: timestamp
    )
}

private actor DeliveryRecoveryExecutorV0:
    AgentHostIdentityRecoveryExecutingV0
{
    private let store: SQLiteSecurityStore
    private let replacement: StoredHostIdentityRecord
    private var failuresAfterFence: Int
    private var calls = 0

    init(
        store: SQLiteSecurityStore,
        replacement: StoredHostIdentityRecord,
        failuresAfterFence: Int = 0
    ) {
        self.store = store
        self.replacement = replacement
        self.failuresAfterFence = failuresAfterFence
    }

    func callCount() -> Int { calls }

    package func recover(
        intent: StoredHostIdentityRecoveryIntent
    ) async throws -> StoredHostIdentityRecord {
        calls += 1
        _ = try await store.beginHostIdentityRecovery(
            intent: intent,
            occurredAtUnixMilliseconds: deliveryRecoveryNowV0 + 2
        )
        if failuresAfterFence > 0 {
            failuresAfterFence -= 1
            throw DeliveryRecoveryProbeErrorV0.injected
        }
        try await store.completeHostIdentityRecovery(
            recoveryID: intent.recoveryID,
            replacement: replacement
        )
        return replacement
    }
}

private actor DeliveryRecoverySurfaceV0:
    LocalHostIdentityRecoverySurfaceV0
{
    private var reviews: [LocalHostIdentityRecoveryReviewV0] = []
    private var resumes: [LocalHostIdentityRecoveryCommandV0] = []
    private var withdrawals: [UUID] = []
    private var suspendNextReview = false
    private var reviewContinuation: CheckedContinuation<Void, Never>?
    private var reviewWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendReview() { suspendNextReview = true }
    func snapshot() -> (
        reviews: [LocalHostIdentityRecoveryReviewV0],
        resumes: [LocalHostIdentityRecoveryCommandV0],
        withdrawals: [UUID]
    ) { (reviews, resumes, withdrawals) }

    func waitUntilReviewArrives() async {
        if !reviews.isEmpty { return }
        await withCheckedContinuation { reviewWaiters.append($0) }
    }

    func resumeReview() { reviewContinuation?.resume(); reviewContinuation = nil }

    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        reviews.append(review)
        let waiters = reviewWaiters
        reviewWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if suspendNextReview {
            suspendNextReview = false
            await withCheckedContinuation { reviewContinuation = $0 }
        }
    }

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        resumes.append(command)
    }

    func withdrawHostIdentityRecovery(reviewID: UUID) {
        withdrawals.append(reviewID)
    }
}

private func deliveryRecoveryCommandV0(
    review: LocalHostIdentityRecoveryReviewV0
) throws -> LocalHostIdentityRecoveryCommandV0 {
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        review: review,
        confirmedAtUnixMilliseconds: deliveryRecoveryNowV0 + 1
    )
}

@Test func recoveryDeliveryConvergesFromFreshReviewToRestartedResume()
    async throws
{
    let temporary = try DeliveryRecoveryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try deliveryRecoveryIdentityV0(
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        byte: 0x21,
        timestamp: deliveryRecoveryNowV0 - 1_000
    )
    let replacement = try deliveryRecoveryIdentityV0(
        hostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        byte: 0x52,
        timestamp: deliveryRecoveryNowV0 + 3
    )
    try await store.establishHostIdentity(original)

    let firstExecutor = DeliveryRecoveryExecutorV0(
        store: store,
        replacement: replacement,
        failuresAfterFence: 1
    )
    let firstRecovery = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: firstExecutor,
        wallNowUnixMilliseconds: { deliveryRecoveryNowV0 }
    )
    let firstSurface = DeliveryRecoverySurfaceV0()
    let firstDelivery = AgentLocalHostIdentityRecoveryDeliveryV0(
        recovery: firstRecovery,
        alreadyAuthorizedSurface: firstSurface
    )
    let review = try await firstDelivery.publishReview(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        cause: .suspectedCompromise
    )
    let command = try deliveryRecoveryCommandV0(review: review)
    await #expect(throws: DeliveryRecoveryProbeErrorV0.injected) {
        try await firstDelivery.recoverHostIdentity(command)
    }
    #expect(try await store.hostIdentityRecoveryIntent()?.commandID
        == command.commandID)
    await firstDelivery.invalidate()

    let resumedExecutor = DeliveryRecoveryExecutorV0(
        store: store,
        replacement: replacement
    )
    let resumedRecovery = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: resumedExecutor,
        wallNowUnixMilliseconds: { deliveryRecoveryNowV0 + 600_000 }
    )
    let resumedSurface = DeliveryRecoverySurfaceV0()
    let resumedDelivery = AgentLocalHostIdentityRecoveryDeliveryV0(
        recovery: resumedRecovery,
        alreadyAuthorizedSurface: resumedSurface
    )
    #expect(try await resumedDelivery.publishResumable() == command)
    #expect(await resumedSurface.snapshot().resumes == [command])

    let changed = try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(),
        recoveryID: command.recoveryID,
        review: command.review,
        confirmedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    await #expect(
        throws: AgentLocalHostIdentityRecoveryDeliveryErrorV0.unavailable
    ) {
        try await resumedDelivery.recoverHostIdentity(changed)
    }
    let receipt = try await resumedDelivery.recoverHostIdentity(command)
    try receipt.validate(against: command)
    #expect(await resumedExecutor.callCount() == 1)
}

@Test func recoveryDeliveryInvalidationFencesSuspendedPublication()
    async throws
{
    let temporary = try DeliveryRecoveryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try deliveryRecoveryIdentityV0(
        hostID: UUID(),
        byte: 0x21,
        timestamp: deliveryRecoveryNowV0 - 1_000
    )
    let replacement = try deliveryRecoveryIdentityV0(
        hostID: UUID(),
        byte: 0x52,
        timestamp: deliveryRecoveryNowV0 + 3
    )
    try await store.establishHostIdentity(original)
    let recovery = AgentLocalHostIdentityRecoveryServiceV0(
        store: store,
        executor: DeliveryRecoveryExecutorV0(
            store: store,
            replacement: replacement
        ),
        wallNowUnixMilliseconds: { deliveryRecoveryNowV0 }
    )
    let surface = DeliveryRecoverySurfaceV0()
    await surface.suspendReview()
    let delivery = AgentLocalHostIdentityRecoveryDeliveryV0(
        recovery: recovery,
        alreadyAuthorizedSurface: surface
    )
    let publish = Task {
        try await delivery.publishReview(
            reviewID: UUID(),
            cause: .keyUnavailable
        )
    }
    await surface.waitUntilReviewArrives()
    await delivery.invalidate()
    await surface.resumeReview()
    await #expect(
        throws: AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
    ) {
        try await publish.value
    }
    #expect(!(await surface.snapshot().withdrawals.isEmpty))
    await #expect(
        throws: AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
    ) {
        try await delivery.publishResumable()
    }
}
