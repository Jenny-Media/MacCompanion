import CompanionDiscovery
import CompanionIPC
import CompanionMacApp
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let appCreatedAt: Int64 = 1_787_198_400_000
private let appExpiresAt: Int64 = appCreatedAt + 300_000

private enum MacPairingClientProbeError: Error {
    case injected
}

private func appCreatedReceipt(
    correlationID: UUID,
    pairingID: UUID = UUID()
) throws -> LocalPairingSessionCreatedReceiptV0 {
    let payload = try PairingQRCodePayload(
        pairingID: WireUUID(pairingID),
        oneTimeSecret: WireBytes32(Data(repeating: 0x6a, count: 32)),
        expiresAtUnixMilliseconds: appExpiresAt,
        hostFingerprint: WireFingerprint(Data(repeating: 0xb4, count: 32)),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
    return try LocalPairingSessionCreatedReceiptV0(
        correlationID: correlationID,
        pairingID: pairingID,
        encodedQRCode: PairingQRCodeCodec.encode(payload),
        createdAtUnixMilliseconds: appCreatedAt,
        expiresAtUnixMilliseconds: appExpiresAt
    )
}

private actor MacPairingClientProbe: MacPairingLocalIPCClientV0 {
    private var creates: [LocalPairingSessionCreateCommandV0] = []
    private var dismisses: [LocalPairingSessionDismissCommandV0] = []
    private var createFailuresRemaining = 0
    private var dismissFailuresRemaining = 0
    private var createCorrelationOverride: UUID?
    private var dismissCorrelationOverride: UUID?
    private var suspendsCreate = false
    private var suspendedCreate:
        CheckedContinuation<LocalPairingSessionCreatedReceiptV0, any Error>?
    private var createWaiters: [CheckedContinuation<Void, Never>] = []

    func failNextCreate() { createFailuresRemaining += 1 }
    func failNextDismiss() { dismissFailuresRemaining += 1 }
    func suspendNextCreate() { suspendsCreate = true }
    func mismatchNextCreate() { createCorrelationOverride = UUID() }
    func mismatchNextDismiss() { dismissCorrelationOverride = UUID() }

    func createAttempts() -> [LocalPairingSessionCreateCommandV0] { creates }
    func dismissAttempts() -> [LocalPairingSessionDismissCommandV0] { dismisses }

    func waitForCreateAttempt() async {
        if !creates.isEmpty { return }
        await withCheckedContinuation { continuation in
            createWaiters.append(continuation)
        }
    }

    func resumeSuspendedCreate() throws {
        guard let continuation = suspendedCreate,
              let command = creates.last else {
            throw MacPairingClientProbeError.injected
        }
        suspendedCreate = nil
        continuation.resume(
            returning: try appCreatedReceipt(
                correlationID: command.commandID
            )
        )
    }

    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        creates.append(command)
        let waiters = createWaiters
        createWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if createFailuresRemaining > 0 {
            createFailuresRemaining -= 1
            throw MacPairingClientProbeError.injected
        }
        if suspendsCreate {
            suspendsCreate = false
            return try await withCheckedThrowingContinuation { continuation in
                suspendedCreate = continuation
            }
        }
        let correlationID = createCorrelationOverride ?? command.commandID
        createCorrelationOverride = nil
        return try appCreatedReceipt(correlationID: correlationID)
    }

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        dismisses.append(command)
        if dismissFailuresRemaining > 0 {
            dismissFailuresRemaining -= 1
            throw MacPairingClientProbeError.injected
        }
        let correlationID = dismissCorrelationOverride ?? command.commandID
        dismissCorrelationOverride = nil
        return try LocalPairingSessionDismissedReceiptV0(
            correlationID: correlationID,
            pairingID: command.pairingID,
            completedAtUnixMilliseconds: appCreatedAt + 1
        )
    }
}

private struct FixedMacPairingClock: MacPairingWallClockV0 {
    let now: Int64
    func nowUnixMilliseconds() -> Int64 { now }
}

private final class ManualExpiryToken:
    MacPairingExpiryCancellationV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    func isCancelled() -> Bool { lock.withLock { cancelled } }
}

private final class ManualExpiryScheduler:
    MacPairingExpirySchedulingV0,
    @unchecked Sendable
{
    private struct Entry: Sendable {
        let delay: Int64
        let token: ManualExpiryToken
        let action: @Sendable () async -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func schedule(
        afterMilliseconds: Int64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacPairingExpiryCancellationV0 {
        let token = ManualExpiryToken()
        lock.withLock {
            entries.append(
                Entry(delay: afterMilliseconds, token: token, action: action)
            )
        }
        return token
    }

    func delays() -> [Int64] {
        lock.withLock { entries.map(\.delay) }
    }

    func fireLatestActive() async {
        let entry = lock.withLock {
            entries.last { !$0.token.isCancelled() }
        }
        await entry?.action()
    }
}

private final class CommandIDSourceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.withLock {
            if values.isEmpty { return UUID() }
            return values.removeFirst()
        }
    }
}

private actor PresentationProbe {
    private var values: [MacPairingSessionPresentationV0] = []
    func append(_ value: MacPairingSessionPresentationV0) { values.append(value) }
    func phases() -> [MacPairingSessionPresentationPhaseV0] {
        values.map(\.phase)
    }
}

@Test func macPairingApplicationOwnerPublishesCreateAndDismissLifecycle() async throws {
    let client = MacPairingClientProbe()
    let scheduler = ManualExpiryScheduler()
    let states = PresentationProbe()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt + 50),
        expiryScheduler: scheduler,
        stateChanged: { value in await states.append(value) }
    )

    try await owner.begin()
    #expect(await owner.snapshot().visibleReceipt != nil)
    #expect(scheduler.delays() == [299_950])
    try await owner.requestDismissal()
    #expect(await owner.snapshot().phase == .idle)

    let phases = await states.phases()
    #expect(phases.count == 4)
    #expect({ if case .creating = phases[0] { true } else { false } }())
    #expect({ if case .presenting = phases[1] { true } else { false } }())
    #expect({ if case .dismissing = phases[2] { true } else { false } }())
    #expect(phases[3] == .idle)
}

@Test func macPairingApplicationOwnerRetriesExactCreateAfterResponseLoss() async throws {
    let client = MacPairingClientProbe()
    await client.failNextCreate()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt),
        expiryScheduler: ManualExpiryScheduler()
    )

    try await owner.begin()
    let failedCreation = await owner.snapshot().phase
    #expect({
        if case .creationFailed = failedCreation { true }
        else { false }
    }())
    try await owner.retryCreation()

    let attempts = await client.createAttempts()
    #expect(attempts.count == 2)
    #expect(attempts[0] == attempts[1])
    #expect(await owner.snapshot().visibleReceipt != nil)
}

@Test func macPairingApplicationOwnerRetriesExactDismissAfterResponseLoss() async throws {
    let client = MacPairingClientProbe()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt),
        expiryScheduler: ManualExpiryScheduler()
    )
    try await owner.begin()
    await client.failNextDismiss()

    try await owner.requestDismissal()
    let failedDismissal = await owner.snapshot().phase
    #expect({
        if case .dismissalFailed = failedDismissal { true }
        else { false }
    }())
    try await owner.retryDismissal()

    let attempts = await client.dismissAttempts()
    #expect(attempts.count == 2)
    #expect(attempts[0] == attempts[1])
    #expect(await owner.snapshot().phase == .idle)
}

@Test func macPairingApplicationOwnerFencesDelayedCreateAfterAgentLoss() async throws {
    let client = MacPairingClientProbe()
    await client.suspendNextCreate()
    let owner = MacPairingApplicationOwnerV0(client: client)

    let createTask = Task { try await owner.begin() }
    await client.waitForCreateAttempt()
    await owner.agentInvalidated()
    try await client.resumeSuspendedCreate()
    try await createTask.value

    #expect(await owner.snapshot().phase == .idle)
    #expect(await owner.snapshot().visibleReceipt == nil)
}

@Test func macPairingApplicationOwnerRejectsMismatchedCreateReceipt() async throws {
    let client = MacPairingClientProbe()
    await client.mismatchNextCreate()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt),
        expiryScheduler: ManualExpiryScheduler()
    )

    try await owner.begin()

    let phase = await owner.snapshot().phase
    #expect({ if case .creationFailed = phase { true } else { false } }())
    #expect(await owner.snapshot().visibleReceipt == nil)
}

@Test func macPairingApplicationOwnerKeepsCodeVisibleOnMismatchedDismissReceipt() async throws {
    let client = MacPairingClientProbe()
    let scheduler = ManualExpiryScheduler()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt),
        expiryScheduler: scheduler
    )
    try await owner.begin()
    let pairingID = try #require(await owner.snapshot().visibleReceipt?.pairingID)
    await client.mismatchNextDismiss()

    try await owner.requestDismissal()

    let phase = await owner.snapshot().phase
    #expect({ if case .dismissalFailed = phase { true } else { false } }())
    #expect(await owner.snapshot().visibleReceipt?.pairingID == pairingID)
    #expect(scheduler.delays() == [300_000, 300_000])
}

@Test func macPairingApplicationOwnerExpiryErasesSecretAndRequestsCleanup() async throws {
    let client = MacPairingClientProbe()
    let scheduler = ManualExpiryScheduler()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt + 10),
        expiryScheduler: scheduler
    )
    try await owner.begin()
    let pairingID = try #require(await owner.snapshot().visibleReceipt?.pairingID)

    await scheduler.fireLatestActive()

    #expect(await owner.snapshot().phase == .idle)
    #expect(await owner.snapshot().visibleReceipt == nil)
    let cleanup = await client.dismissAttempts()
    #expect(cleanup.count == 1)
    #expect(cleanup[0].pairingID == pairingID)
}

@Test func macPairingApplicationOwnerRearmsExpiryAfterDismissFailure() async throws {
    let client = MacPairingClientProbe()
    let scheduler = ManualExpiryScheduler()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt + 100),
        expiryScheduler: scheduler
    )
    try await owner.begin()
    await client.failNextDismiss()
    try await owner.requestDismissal()

    #expect(scheduler.delays() == [299_900, 299_900])
    #expect(await owner.snapshot().visibleReceipt != nil)
    await scheduler.fireLatestActive()
    #expect(await owner.snapshot().phase == .idle)
}

@Test func macPairingApplicationOwnerRejectsCommandIDReuseAcrossOperations() async throws {
    let repeated = UUID()
    let source = CommandIDSourceProbe([repeated, repeated])
    let client = MacPairingClientProbe()
    let owner = MacPairingApplicationOwnerV0(
        client: client,
        clock: FixedMacPairingClock(now: appCreatedAt),
        expiryScheduler: ManualExpiryScheduler(),
        commandIDSource: { source.next() }
    )
    try await owner.begin()

    await #expect(throws: MacPairingApplicationOwnerErrorV0.commandIDReuse) {
        try await owner.requestDismissal()
    }
    #expect(await client.dismissAttempts().isEmpty)
    #expect(await owner.snapshot().visibleReceipt != nil)
}

@Test func macPairingApplicationOwnerUsesNoMoreThanReceiptLifetimeWhenClockRegresses() async throws {
    let scheduler = ManualExpiryScheduler()
    let owner = MacPairingApplicationOwnerV0(
        client: MacPairingClientProbe(),
        clock: FixedMacPairingClock(now: appCreatedAt - 99_000),
        expiryScheduler: scheduler
    )
    try await owner.begin()
    #expect(scheduler.delays() == [300_000])
}
