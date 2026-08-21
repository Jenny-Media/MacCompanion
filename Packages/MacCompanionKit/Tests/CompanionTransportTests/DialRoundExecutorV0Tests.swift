import CompanionDiscovery
import CompanionTransport
import Foundation
import Testing

private let executorRouteA = try! EndpointCandidate(
    kind: .bonjour,
    value: "mac-018f._maccompanion._tcp.local.",
    port: 47_474
)
private let executorRouteB = try! EndpointCandidate(
    kind: .ipv4,
    value: "192.168.1.20",
    port: 47_474
)
private let executorRouteC = try! EndpointCandidate(
    kind: .dns,
    value: "mac.tail123.ts.net",
    port: 47_474
)
private let executorPin = Data(0x60...0x7f)

private enum ExecutorAttemptPlan: Sendable {
    case transientFailure
    case authenticationDenied
    case authenticated(returnedEndpoint: EndpointCandidate)
    case waitUntilCancelled
}

private struct ExecutorAttemptCall: Equatable, Sendable {
    let endpoint: EndpointCandidate
    let roundID: UUID
    let requiredHostFingerprint: Data
}

private actor ExecutorAttemptRecorder: DialRouteAttemptingV0 {
    private let plans: [EndpointCandidate: ExecutorAttemptPlan]
    private(set) var calls: [ExecutorAttemptCall] = []
    private(set) var closedEndpoints: [EndpointCandidate] = []

    init(plans: [EndpointCandidate: ExecutorAttemptPlan]) {
        self.plans = plans
    }

    func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0 {
        calls.append(ExecutorAttemptCall(
            endpoint: attempt.endpoint,
            roundID: roundID,
            requiredHostFingerprint: requiredHostFingerprint
        ))
        switch plans[attempt.endpoint] ?? .transientFailure {
        case .transientFailure:
            return .transientFailure
        case .authenticationDenied:
            return .authenticationDenied
        case let .authenticated(returnedEndpoint):
            return .authenticated(AuthenticatedDialRouteV0(
                endpoint: returnedEndpoint,
                close: { [weak self] in
                    await self?.recordClose(returnedEndpoint)
                }
            ))
        case .waitUntilCancelled:
            while !Task.isCancelled {
                await Task.yield()
            }
            return .transientFailure
        }
    }

    private func recordClose(_ endpoint: EndpointCandidate) {
        closedEndpoints.append(endpoint)
    }
}

private actor ExecutorWaitRecorder {
    private(set) var delays: [Int64] = []

    func record(_ delay: Int64) {
        delays.append(delay)
    }
}

private func executorRound() throws -> DialRound {
    var state = try ReconnectStateMachine(
        candidates: [executorRouteA, executorRouteB, executorRouteC],
        requiredHostFingerprint: executorPin,
        foreground: true,
        networkReachable: true
    )
    let roundID = UUID()
    let effects = try state.apply(.tick(
        monotonicNowMilliseconds: 100,
        roundID: roundID
    ))
    guard case let .startDialRound(round) = effects.first else {
        throw ReconnectError.invalidTransition
    }
    return round
}

@Test func dialRoundPassesOneImmutablePinAndExactStaggerPlan() async throws {
    let round = try executorRound()
    let attempts = ExecutorAttemptRecorder(plans: [:])
    let waits = ExecutorWaitRecorder()
    let executor = DialRoundExecutorV0(
        attempter: attempts,
        wait: { delay in await waits.record(delay) }
    )

    guard case .exhausted = await executor.execute(round) else {
        Issue.record("expected exhausted round")
        return
    }
    let calls = await attempts.calls
    #expect(Set(calls.map(\.endpoint)) == Set(round.attempts.map(\.endpoint)))
    #expect(calls.allSatisfy {
        $0.roundID == round.roundID
            && $0.requiredHostFingerprint == executorPin
    })
    #expect(Set(await waits.delays) == Set([0, 250, 500]))
}

@Test func firstAuthenticatedRouteWinsAndEveryLateWinnerCloses() async throws {
    let round = try executorRound()
    let attempts = ExecutorAttemptRecorder(plans: [
        executorRouteA: .authenticated(returnedEndpoint: executorRouteA),
        executorRouteB: .authenticated(returnedEndpoint: executorRouteB),
        executorRouteC: .authenticated(returnedEndpoint: executorRouteC),
    ])
    let executor = DialRoundExecutorV0(
        attempter: attempts,
        wait: { _ in }
    )

    guard case let .authenticated(winner) = await executor.execute(round) else {
        Issue.record("expected authenticated winner")
        return
    }
    let closedBeforeWinner = await attempts.closedEndpoints
    #expect(closedBeforeWinner.count == 2)
    #expect(!closedBeforeWinner.contains(winner.endpoint))
    await winner.close()
    #expect(await attempts.closedEndpoints.count == 3)
}

@Test func authenticationDenialCancelsUnstartedRoutesAndRequiresNoRetry() async throws {
    let round = try executorRound()
    let attempts = ExecutorAttemptRecorder(plans: [
        executorRouteA: .authenticationDenied,
        executorRouteB: .authenticated(returnedEndpoint: executorRouteB),
        executorRouteC: .authenticated(returnedEndpoint: executorRouteC),
    ])
    let executor = DialRoundExecutorV0(attempter: attempts)

    guard case .authenticationDenied = await executor.execute(round) else {
        Issue.record("expected terminal authentication denial")
        return
    }
    let calls = await attempts.calls
    #expect(calls.map(\.endpoint) == [executorRouteA])
    #expect(await attempts.closedEndpoints.isEmpty)
}

@Test func mismatchedAuthenticatedEndpointFailsClosedAndClosesRoute() async throws {
    let round = try executorRound()
    let attempts = ExecutorAttemptRecorder(plans: [
        executorRouteA: .authenticated(returnedEndpoint: executorRouteB),
    ])
    let executor = DialRoundExecutorV0(
        attempter: attempts,
        wait: { _ in }
    )

    guard case .invalidAttemptResult = await executor.execute(round) else {
        Issue.record("expected invalid adapter result")
        return
    }
    #expect(await attempts.closedEndpoints == [executorRouteB])
}

@Test func cancellingRoundCancelsAttemptsAndReturnsNoWinner() async throws {
    let round = try executorRound()
    let attempts = ExecutorAttemptRecorder(plans: [
        executorRouteA: .waitUntilCancelled,
        executorRouteB: .waitUntilCancelled,
        executorRouteC: .waitUntilCancelled,
    ])
    let executor = DialRoundExecutorV0(
        attempter: attempts,
        wait: { _ in }
    )
    let task = Task { await executor.execute(round) }
    while await attempts.calls.count < 3 {
        await Task.yield()
    }
    task.cancel()

    guard case .cancelled = await task.value else {
        Issue.record("expected cancelled round")
        return
    }
    #expect(await attempts.closedEndpoints.isEmpty)
}

@Test func authenticatedRouteOwnsCommandTransportOrFailsExplicitly() async throws {
    actor SentFrames {
        var values: [Data] = []
        func append(_ value: Data) { values.append(value) }
    }
    let sent = SentFrames()
    let frame = Data([1, 2, 3])
    let route = AuthenticatedDialRouteV0(
        endpoint: executorRouteA,
        send: { value in await sent.append(value) },
        close: {}
    )
    try await route.sendCommand(frame)
    let values = await sent.values
    #expect(values == [frame])

    let unavailable = AuthenticatedDialRouteV0(
        endpoint: executorRouteB,
        close: {}
    )
    await #expect(
        throws: AuthenticatedDialRouteErrorV0.commandTransportUnavailable
    ) {
        try await unavailable.sendCommand(frame)
    }
}
