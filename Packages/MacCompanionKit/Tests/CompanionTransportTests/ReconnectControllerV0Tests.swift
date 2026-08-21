import CompanionDiscovery
import CompanionTransport
import Foundation
import Testing

private let controllerRouteA = try! EndpointCandidate(
    kind: .ipv4,
    value: "192.168.1.40",
    port: 47_474
)
private let controllerRouteB = try! EndpointCandidate(
    kind: .dns,
    value: "mac.tail987.ts.net",
    port: 47_474
)
private let controllerPin = Data(0x20...0x3f)

private enum ControllerAttemptPlan: Sendable {
    case authenticated
    case transientFailure
    case authenticationDenied
    case waitUntilCancelled
}

private actor ControllerAttemptRecorder: DialRouteAttemptingV0 {
    private let plans: [EndpointCandidate: ControllerAttemptPlan]
    private(set) var attemptedEndpoints: [EndpointCandidate] = []
    private(set) var selectedEndpoints: [EndpointCandidate] = []
    private(set) var closedEndpoints: [EndpointCandidate] = []

    init(plans: [EndpointCandidate: ControllerAttemptPlan]) {
        self.plans = plans
    }

    func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0 {
        attemptedEndpoints.append(attempt.endpoint)
        switch plans[attempt.endpoint] ?? .transientFailure {
        case .authenticated:
            return .authenticated(AuthenticatedDialRouteV0(
                endpoint: attempt.endpoint,
                selected: { [weak self] in
                    await self?.recordSelection(attempt.endpoint)
                },
                close: { [weak self] in
                    await self?.recordClose(attempt.endpoint)
                }
            ))
        case .transientFailure:
            return .transientFailure
        case .authenticationDenied:
            return .authenticationDenied
        case .waitUntilCancelled:
            while !Task.isCancelled { await Task.yield() }
            return .transientFailure
        }
    }

    private func recordClose(_ endpoint: EndpointCandidate) {
        closedEndpoints.append(endpoint)
    }

    private func recordSelection(_ endpoint: EndpointCandidate) {
        selectedEndpoints.append(endpoint)
    }
}

private actor ControllerEventRecorder {
    private(set) var retryDeadlines: [Int64] = []
    private(set) var failures: [ReconnectControllerFailureV0] = []

    func retry(_ deadline: Int64) {
        retryDeadlines.append(deadline)
    }

    func fail(_ failure: ReconnectControllerFailureV0) {
        failures.append(failure)
    }
}

private final class ControllerFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ReconnectControllerFailureV0] = []

    func record(_ failure: ReconnectControllerFailureV0) {
        lock.lock()
        storage.append(failure)
        lock.unlock()
    }

    func values() -> [ReconnectControllerFailureV0] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func controllerState(
    candidates: [EndpointCandidate] = [controllerRouteA]
) throws -> ReconnectStateMachine {
    try ReconnectStateMachine(
        candidates: candidates,
        requiredHostFingerprint: controllerPin,
        foreground: true,
        networkReachable: true
    )
}

private func waitForControllerPhase(
    _ expected: ReconnectPhase,
    controller: ReconnectControllerV0
) async -> Bool {
    for _ in 0..<2_000 {
        if await controller.snapshot().phase == expected { return true }
        await Task.yield()
    }
    return false
}

@Test func reconnectControllerOwnsWinnerAndClosesItOnBackground() async throws {
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .authenticated,
    ])
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    let didConnect = await waitForControllerPhase(
        .connected(controllerRouteA),
        controller: controller
    )
    #expect(didConnect)
    let connected = await controller.snapshot()
    #expect(connected.requiredHostFingerprint == controllerPin)
    #expect(await attempts.selectedEndpoints == [controllerRouteA])

    try await controller.setForeground(
        false,
        monotonicNowMilliseconds: 101
    )
    let background = await controller.snapshot()
    let closed = await attempts.closedEndpoints
    #expect(background.phase == .waitingForForeground)
    #expect(closed == [controllerRouteA])
}

@Test func controllerPublishesContentFreeWakeupsForInternalCompletion()
    async throws
{
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .authenticated,
    ])
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 }
    )
    var continuation: AsyncStream<Void>.Continuation?
    let wakeups = AsyncStream<Void>(
        bufferingPolicy: .bufferingOldest(4)
    ) { continuation = $0 }
    let callbackContinuation = try #require(continuation)
    var iterator = wakeups.makeAsyncIterator()
    await controller.setStateChanged { callbackContinuation.yield() }

    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await iterator.next() != nil)
    #expect(await waitForControllerPhase(
        .connected(controllerRouteA),
        controller: controller
    ))
    #expect(await iterator.next() != nil)

    await controller.shutdown()
    #expect(await iterator.next() != nil)
    callbackContinuation.finish()
}

@Test func reconnectControllerSelectsOnlyTheExactParallelWinner() async throws {
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .authenticated,
        controllerRouteB: .authenticated,
    ])
    let controller = ReconnectControllerV0(
        state: try controllerState(
            candidates: [controllerRouteA, controllerRouteB]
        ),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    for _ in 0..<2_000 {
        let phase = await controller.snapshot().phase
        if case .connected = phase { break }
        await Task.yield()
    }
    for _ in 0..<2_000 where await attempts.closedEndpoints.isEmpty {
        await Task.yield()
    }

    let selected = await attempts.selectedEndpoints
    let closed = await attempts.closedEndpoints
    #expect(selected.count == 1)
    #expect(closed.count == 1)
    #expect(selected.first != closed.first)
    #expect(Set(selected + closed) == Set([
        controllerRouteA,
        controllerRouteB,
    ]))

    await controller.shutdown()
}

@Test func reconnectControllerShutdownClosesWinnerAndRejectsReuse()
    async throws
{
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .authenticated,
    ])
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForControllerPhase(
        .connected(controllerRouteA),
        controller: controller
    ))

    await controller.shutdown()
    await controller.shutdown()

    #expect(await attempts.closedEndpoints == [controllerRouteA])
    #expect(await controller.snapshot().isShutdown)
    await #expect(throws: ReconnectError.invalidTransition) {
        try await controller.startRound(
            roundID: UUID(),
            monotonicNowMilliseconds: 101
        )
    }
}

@Test func exhaustedControllerRoundSchedulesOnlyStateMachineBackoff() async throws {
    let attempts = ControllerAttemptRecorder(plans: [:])
    let events = ControllerEventRecorder()
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 },
        retryScheduled: { deadline in await events.retry(deadline) }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    let didBackOff = await waitForControllerPhase(
        .backoff(untilMonotonicMilliseconds: 1_500),
        controller: controller
    )
    let retryDeadlines = await events.retryDeadlines
    let backoffSnapshot = await controller.snapshot()
    #expect(didBackOff)
    #expect(retryDeadlines == [1_500])
    #expect(backoffSnapshot.failedRounds == 1)
}

@Test func candidateReplacementCancelsExactControllerRound() async throws {
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .waitUntilCancelled,
    ])
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    while await attempts.attemptedEndpoints.isEmpty { await Task.yield() }

    try await controller.replaceCandidates(
        [controllerRouteB],
        monotonicNowMilliseconds: 101
    )
    let snapshot = await controller.snapshot()
    #expect(snapshot.phase == .ready)
    #expect(snapshot.candidates == [controllerRouteB])
    #expect(snapshot.requiredHostFingerprint == controllerPin)
}

@Test func terminalAuthenticationDenialNeverBecomesRouteRetry() async throws {
    let attempts = ControllerAttemptRecorder(plans: [
        controllerRouteA: .authenticationDenied,
    ])
    let events = ControllerEventRecorder()
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 10_000 },
        retryScheduled: { deadline in await events.retry(deadline) }
    )
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    let requiresAction = await waitForControllerPhase(
        .requiresUserAction,
        controller: controller
    )
    let retryDeadlines = await events.retryDeadlines
    #expect(requiresAction)
    #expect(retryDeadlines.isEmpty)
    try await controller.resumeAfterUserAction()
    let resumed = await controller.snapshot()
    #expect(resumed.phase == .ready)
}

@Test func invalidRuntimeClockFailsClosedInsteadOfLeavingDialingState() async throws {
    let attempts = ControllerAttemptRecorder(plans: [:])
    let failures = ControllerFailureRecorder()
    let controller = ReconnectControllerV0(
        state: try controllerState(),
        executor: DialRoundExecutorV0(
            attempter: attempts,
            wait: { _ in }
        ),
        monotonicNow: { -1 },
        jitterBasisPoints: { 10_000 },
        failureObserved: { failure in failures.record(failure) }
    )
    var continuation: AsyncStream<Void>.Continuation?
    let wakeups = AsyncStream<Void>(
        bufferingPolicy: .bufferingOldest(3)
    ) { continuation = $0 }
    let callbackContinuation = try #require(continuation)
    var iterator = wakeups.makeAsyncIterator()
    await controller.setStateChanged { callbackContinuation.yield() }
    try await controller.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    let requiresAction = await waitForControllerPhase(
        .requiresUserAction,
        controller: controller
    )
    #expect(requiresAction)
    #expect(failures.values() == [.invalidRuntimeInput])
    #expect(await iterator.next() != nil)
    #expect(await iterator.next() != nil)
    callbackContinuation.finish()
}
