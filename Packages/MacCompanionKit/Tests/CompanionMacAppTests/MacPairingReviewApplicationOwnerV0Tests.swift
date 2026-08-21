import CompanionDomain
import CompanionIPC
import CompanionMacApp
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let macReviewWall: Int64 = 1_787_198_400_100
private let macReviewID = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000f1"
)!
private let macReviewPairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000f1"
)!
private let macReviewClientID = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000f1"
)!
private let macReviewDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-0000000000f1"
)!

private enum MacReviewClientProbeErrorV0: Error {
    case injected
}

private func macReviewV0(
    reviewID: UUID = macReviewID
) throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: reviewID,
        pairingID: macReviewPairingID,
        clientID: macReviewClientID,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x61, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x62, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x63, count: 32)),
        authenticationString: PairingAuthenticationString("B14-A05"),
        expectedPolicyRevision: PolicyRevision(rawValue: 7),
        expiresAtUnixMilliseconds: macReviewWall + 1_000
    )
}

private actor MacReviewClientProbeV0: MacPairingReviewLocalIPCClientV0 {
    private var commandsStorage: [LocalPairingDecisionCommandV0] = []
    private var failNext = false
    private var suspendNext = false
    private var continuation:
        CheckedContinuation<LocalPairingDecisionReceiptV0, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func injectFailure() { failNext = true }
    func injectSuspension() { suspendNext = true }
    func commands() -> [LocalPairingDecisionCommandV0] { commandsStorage }

    func waitForCommand() async {
        if !commandsStorage.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resumeSuspended() throws {
        guard let continuation, let command = commandsStorage.last else {
            throw MacReviewClientProbeErrorV0.injected
        }
        self.continuation = nil
        continuation.resume(returning: try receipt(for: command))
    }

    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        commandsStorage.append(command)
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters { waiter.resume() }
        if failNext {
            failNext = false
            throw MacReviewClientProbeErrorV0.injected
        }
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation {
                continuation = $0
            }
        }
        return try receipt(for: command)
    }

    private func receipt(
        for command: LocalPairingDecisionCommandV0
    ) throws -> LocalPairingDecisionReceiptV0 {
        try LocalPairingDecisionReceiptV0(
            correlationID: command.commandID,
            reviewID: command.reviewID,
            pairingID: command.pairingID,
            clientID: command.clientID,
            decision: command.decision,
            deviceID: command.decision == .approve ? macReviewDeviceID : nil,
            storedDisplayName: command.deviceDisplayName,
            completedAtUnixMilliseconds: macReviewWall + 1
        )
    }
}

private struct FixedMacReviewClockV0: MacPairingWallClockV0 {
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private final class MacReviewExpiryTokenV0:
    MacPairingExpiryCancellationV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func isCancelled() -> Bool { lock.withLock { cancelled } }
}

private final class MacReviewExpirySchedulerV0:
    MacPairingExpirySchedulingV0,
    @unchecked Sendable
{
    private struct Entry: Sendable {
        let delay: Int64
        let token: MacReviewExpiryTokenV0
        let action: @Sendable () async -> Void
    }
    private let lock = NSLock()
    private var entries: [Entry] = []

    func schedule(
        afterMilliseconds: Int64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacPairingExpiryCancellationV0 {
        let token = MacReviewExpiryTokenV0()
        lock.withLock {
            entries.append(Entry(
                delay: afterMilliseconds,
                token: token,
                action: action
            ))
        }
        return token
    }

    func delays() -> [Int64] { lock.withLock { entries.map(\.delay) } }

    func fireLatestActive() async {
        let entry = lock.withLock {
            entries.last { !$0.token.isCancelled() }
        }
        await entry?.action()
    }
}

private final class MacReviewCommandIDsV0: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]
    init(_ values: [UUID]) { self.values = values }
    func next() -> UUID { lock.withLock { values.removeFirst() } }
}

@Test func macReviewPresentationStartsEmptyAndBindsLocalName() throws {
    let review = try macReviewV0()
    var presentation = MacPairingReviewPresentationV0()
    try presentation.receive(review)
    #expect(presentation.review == review)
    #expect(presentation.deviceNameDraft.isEmpty)
    #expect(presentation.deviceNameDraftIssue() == .empty)

    try presentation.updateDeviceNameDraft("Jenny's iPhone")
    let command = try presentation.approve(
        commandID: UUID(),
        decidedAtUnixMilliseconds: macReviewWall
    )
    let expectedName = try DeviceDisplayName("Jenny's iPhone")
    #expect(command.matches(review))
    #expect(command.deviceDisplayName == expectedName)
    #expect(command.decision == .approve)
}

@Test func macReviewPresentationDeclineCarriesNoNameAndRetryIsExact() throws {
    let review = try macReviewV0()
    var presentation = MacPairingReviewPresentationV0()
    try presentation.receive(review)
    try presentation.updateDeviceNameDraft("Ignored local draft")
    let command = try presentation.decline(
        commandID: UUID(),
        decidedAtUnixMilliseconds: macReviewWall
    )
    #expect(command.deviceDisplayName == nil)
    #expect(command.decision == .decline)
    try presentation.decisionFailed()
    #expect(try presentation.retryDecision() == command)
    #expect(throws: MacPairingReviewPresentationErrorV0.invalidPhase) {
        try presentation.updateDeviceNameDraft("Cannot edit")
    }
}

@Test func macReviewOwnerAcknowledgesExactPresentationAndExpiry() async throws {
    let client = MacReviewClientProbeV0()
    let scheduler = MacReviewExpirySchedulerV0()
    let owner = MacPairingReviewApplicationOwnerV0(
        client: client,
        clock: FixedMacReviewClockV0(value: macReviewWall),
        expiryScheduler: scheduler
    )
    let review = try macReviewV0()
    try await owner.presentLocalPairingReview(review)
    try await owner.presentLocalPairingReview(review)
    #expect(await owner.snapshot().review == review)
    #expect(scheduler.delays() == [1_000])

    await owner.withdrawLocalPairingReview(reviewID: UUID())
    #expect(await owner.snapshot().review == review)
    await scheduler.fireLatestActive()
    #expect(await owner.snapshot().review == nil)
}

@Test func macReviewOwnerApprovalPublishesOnlyCorrelatedSuccess() async throws {
    let client = MacReviewClientProbeV0()
    let commandID = UUID()
    let IDs = MacReviewCommandIDsV0([commandID])
    let owner = MacPairingReviewApplicationOwnerV0(
        client: client,
        clock: FixedMacReviewClockV0(value: macReviewWall),
        commandIDSource: { IDs.next() }
    )
    try await owner.presentLocalPairingReview(macReviewV0())
    await #expect(throws: MacPairingReviewPresentationErrorV0.self) {
        try await owner.approve()
    }
    try await owner.updateDeviceNameDraft("Jenny's iPhone")
    try await owner.approve()

    let command = try #require(await client.commands().first)
    let expectedName = try DeviceDisplayName("Jenny's iPhone")
    #expect(command.commandID == commandID)
    #expect(command.deviceDisplayName == expectedName)
    #expect(await owner.snapshot().review == nil)
}

@Test func macReviewOwnerRetriesTheExactFailedCommand() async throws {
    let client = MacReviewClientProbeV0()
    await client.injectFailure()
    let commandID = UUID()
    let IDs = MacReviewCommandIDsV0([commandID])
    let owner = MacPairingReviewApplicationOwnerV0(
        client: client,
        clock: FixedMacReviewClockV0(value: macReviewWall),
        commandIDSource: { IDs.next() }
    )
    try await owner.presentLocalPairingReview(macReviewV0())
    try await owner.updateDeviceNameDraft("Retry Phone")
    try await owner.approve()
    guard case let .decisionFailed(failed) = await owner.snapshot().phase else {
        Issue.record("expected exact failed command")
        return
    }
    #expect(failed.commandID == commandID)

    try await owner.retryDecision()
    let attempts = await client.commands()
    #expect(attempts == [failed, failed])
    #expect(await owner.snapshot().review == nil)
}

@Test func macReviewOwnerWithdrawalFencesDelayedReceipt() async throws {
    let client = MacReviewClientProbeV0()
    await client.injectSuspension()
    let IDs = MacReviewCommandIDsV0([UUID()])
    let owner = MacPairingReviewApplicationOwnerV0(
        client: client,
        clock: FixedMacReviewClockV0(value: macReviewWall),
        commandIDSource: { IDs.next() }
    )
    let review = try macReviewV0()
    try await owner.presentLocalPairingReview(review)
    try await owner.updateDeviceNameDraft("Jenny's iPhone")
    let approval = Task { try await owner.approve() }
    await client.waitForCommand()
    await owner.withdrawLocalPairingReview(reviewID: review.reviewID)
    try await client.resumeSuspended()
    try await approval.value

    #expect(await owner.snapshot().review == nil)
    #expect(await owner.snapshot().phase == .idle)
}
