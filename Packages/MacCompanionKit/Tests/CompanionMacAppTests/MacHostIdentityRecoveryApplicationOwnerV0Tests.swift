import CompanionIPC
import CompanionMacApp
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let ownerRecoveryCreatedAtV0: Int64 = 1_787_284_800_000

private enum RecoveryOwnerProbeError: Error { case injected }

private func ownerRecoveryReviewV0() throws
    -> LocalHostIdentityRecoveryReviewV0
{
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        hostFingerprint: WireFingerprint(Data(repeating: 0x21, count: 32)),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: ownerRecoveryCreatedAtV0,
        expiresAtUnixMilliseconds: ownerRecoveryCreatedAtV0 + 300_000
    )
}

private actor RecoveryOwnerClientProbe:
    MacHostIdentityRecoveryLocalIPCClientV0
{
    private var commands: [LocalHostIdentityRecoveryCommandV0] = []
    private var failuresRemaining = 0
    private var suspendNext = false
    private var suspended:
        CheckedContinuation<LocalHostIdentityRecoveredReceiptV0, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func failNext() { failuresRemaining += 1 }
    func suspendNextCall() { suspendNext = true }
    func attempts() -> [LocalHostIdentityRecoveryCommandV0] { commands }

    func waitForAttempt() async {
        if !commands.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resumeSuspended() throws {
        guard let suspended, let command = commands.last else {
            throw RecoveryOwnerProbeError.injected
        }
        self.suspended = nil
        suspended.resume(returning: try receipt(for: command))
    }

    func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        commands.append(command)
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RecoveryOwnerProbeError.injected
        }
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation {
                suspended = $0
            }
        }
        return try receipt(for: command)
    }

    private func receipt(
        for command: LocalHostIdentityRecoveryCommandV0
    ) throws -> LocalHostIdentityRecoveredReceiptV0 {
        try LocalHostIdentityRecoveredReceiptV0(
            correlationID: command.commandID,
            recoveryID: command.recoveryID,
            replacedHostID: command.review.hostID,
            newHostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            newHostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
            completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
        )
    }
}

private struct FixedRecoveryOwnerClock:
    MacHostIdentityRecoveryWallClockV0
{
    let now: Int64
    func nowUnixMilliseconds() -> Int64 { now }
}

private final class RecoveryOwnerIdentifierSource: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [UUID]

    init(_ identifiers: [UUID]) { self.identifiers = identifiers }

    func next() -> UUID {
        lock.withLock { identifiers.removeFirst() }
    }
}

@Test func macRecoveryOwnerPublishesReviewAndCompletesExactCommand()
    async throws
{
    let client = RecoveryOwnerClientProbe()
    let identifiers = RecoveryOwnerIdentifierSource([UUID(), UUID()])
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(
        client: client,
        clock: FixedRecoveryOwnerClock(now: ownerRecoveryCreatedAtV0 + 1),
        identifierSource: identifiers.next
    )
    try await owner.publishReview(ownerRecoveryReviewV0())
    try await owner.confirm()

    #expect(await client.attempts().count == 1)
    let completedPhase = await owner.snapshot().phase
    #expect({
        if case .completed = completedPhase { true }
        else { false }
    }())
}

@Test func macRecoveryOwnerRetriesTheExactCommandAfterResponseLoss()
    async throws
{
    let client = RecoveryOwnerClientProbe()
    await client.failNext()
    let identifiers = RecoveryOwnerIdentifierSource([UUID(), UUID()])
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(
        client: client,
        clock: FixedRecoveryOwnerClock(now: ownerRecoveryCreatedAtV0 + 1),
        identifierSource: identifiers.next
    )
    try await owner.publishReview(ownerRecoveryReviewV0())
    try await owner.confirm()
    try await owner.retry()

    let attempts = await client.attempts()
    #expect(attempts.count == 2)
    #expect(attempts[0] == attempts[1])
}

@Test func macRecoveryOwnerFencesDelayedSuccessAfterAgentInvalidation()
    async throws
{
    let client = RecoveryOwnerClientProbe()
    await client.suspendNextCall()
    let review = try ownerRecoveryReviewV0()
    let identifiers = RecoveryOwnerIdentifierSource([UUID(), UUID()])
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(
        client: client,
        clock: FixedRecoveryOwnerClock(now: ownerRecoveryCreatedAtV0 + 1),
        identifierSource: identifiers.next
    )
    try await owner.publishReview(review)
    let task = Task { try await owner.confirm() }
    await client.waitForAttempt()
    await owner.agentInvalidated()
    try await client.resumeSuspended()
    try await task.value

    let invalidatedPhase = await owner.snapshot().phase
    #expect({
        if case .authorizationLost = invalidatedPhase { true }
        else { false }
    }())
    try await owner.publishReview(review)
    try await owner.retry()
    #expect(await client.attempts().count == 2)
}

@Test func macRecoveryOwnerRejectsIdentifierReuseBeforeCallingClient()
    async throws
{
    let client = RecoveryOwnerClientProbe()
    let repeated = UUID()
    let identifiers = RecoveryOwnerIdentifierSource([repeated, repeated])
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(
        client: client,
        clock: FixedRecoveryOwnerClock(now: ownerRecoveryCreatedAtV0 + 1),
        identifierSource: identifiers.next
    )
    try await owner.publishReview(ownerRecoveryReviewV0())
    await #expect(throws: MacHostIdentityRecoveryApplicationOwnerErrorV0
        .identifierReuse) {
        try await owner.confirm()
    }
    #expect(await client.attempts().isEmpty)
}

@Test func macRecoveryOwnerAdoptsAgentResumeWithoutNewConfirmation()
    async throws
{
    let client = RecoveryOwnerClientProbe()
    let review = try ownerRecoveryReviewV0()
    let command = try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(),
        recoveryID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: ownerRecoveryCreatedAtV0 + 1
    )
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(
        client: client,
        identifierSource: {
            Issue.record("resume must not issue a new identifier")
            return UUID()
        }
    )

    try await owner.publishRecoveryResume(command)
    #expect(await owner.snapshot().exactRetryCommand == command)
    #expect(await client.attempts().isEmpty)
    try await owner.retry()
    #expect(await client.attempts() == [command])
}

@Test func macRecoveryOwnerSurfaceWithdrawsOnlyMatchingReview() async throws {
    let client = RecoveryOwnerClientProbe()
    let owner = MacHostIdentityRecoveryApplicationOwnerV0(client: client)
    let review = try ownerRecoveryReviewV0()
    try await owner.presentHostIdentityRecoveryReview(review)
    await owner.withdrawHostIdentityRecovery(reviewID: UUID())
    #expect(await owner.snapshot().currentReviewID == review.reviewID)
    await owner.withdrawHostIdentityRecovery(reviewID: review.reviewID)
    #expect(await owner.snapshot().phase == .idle)
}
