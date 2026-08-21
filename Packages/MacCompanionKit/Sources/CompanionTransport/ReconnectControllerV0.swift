import CompanionDiscovery
import Foundation

public struct ReconnectControllerSnapshotV0: Equatable, Sendable {
    public let phase: ReconnectPhase
    public let candidates: [EndpointCandidate]
    public let requiredHostFingerprint: Data
    public let failedRounds: Int
    public let isShutdown: Bool
}

public enum ReconnectControllerFailureV0: String, Equatable, Sendable {
    case invalidRuntimeInput
    case stateMachineFailure
}

/// Single owner that composes the pure reconnect policy with one dial-round
/// executor. It never creates sockets or trust evidence. The injected attempter
/// must finish the same-connection pin and application authentication before
/// returning an authenticated route.
public actor ReconnectControllerV0 {
    public typealias MonotonicNow = @Sendable () -> Int64
    public typealias JitterBasisPoints = @Sendable () -> UInt16
    public typealias RetryScheduled = @Sendable (Int64) async -> Void
    public typealias FailureObserved = @Sendable (
        ReconnectControllerFailureV0
    ) -> Void
    public typealias StateChanged = @Sendable () -> Void

    private var state: ReconnectStateMachine
    private let executor: DialRoundExecutorV0
    private let monotonicNow: MonotonicNow
    private let jitterBasisPoints: JitterBasisPoints
    private let retryScheduled: RetryScheduled
    private let failureObserved: FailureObserved
    private var stateChanged: StateChanged = {}
    private var activeRoundID: UUID?
    private var activeRoundTask: Task<Void, Never>?
    private var connectedRoute: AuthenticatedDialRouteV0?
    private var isShutdown = false

    public init(
        state: ReconnectStateMachine,
        executor: DialRoundExecutorV0,
        monotonicNow: @escaping MonotonicNow,
        jitterBasisPoints: @escaping JitterBasisPoints,
        retryScheduled: @escaping RetryScheduled = { _ in },
        failureObserved: @escaping FailureObserved = { _ in }
    ) {
        self.state = state
        self.executor = executor
        self.monotonicNow = monotonicNow
        self.jitterBasisPoints = jitterBasisPoints
        self.retryScheduled = retryScheduled
        self.failureObserved = failureObserved
    }

    public func snapshot() -> ReconnectControllerSnapshotV0 {
        ReconnectControllerSnapshotV0(
            phase: state.phase,
            candidates: state.candidates,
            requiredHostFingerprint: state.requiredHostFingerprint,
            failedRounds: state.failedRounds,
            isShutdown: isShutdown
        )
    }

    /// Installs the package-owned wakeup used by higher-level lifecycle
    /// composition. The callback carries no route or trust facts; its consumer
    /// must re-read and validate the complete owner snapshot.
    package func setStateChanged(_ stateChanged: @escaping StateChanged) {
        self.stateChanged = stateChanged
    }

    public func startRound(
        roundID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try requireActive()
        try await applyExternal(.tick(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            roundID: roundID
        ))
    }

    public func setForeground(
        _ foreground: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try requireActive()
        try await applyExternal(.setForeground(
            foreground,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        ))
    }

    public func setNetworkReachable(
        _ reachable: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try requireActive()
        try await applyExternal(.setNetworkReachable(
            reachable,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        ))
    }

    public func replaceCandidates(
        _ candidates: [EndpointCandidate],
        monotonicNowMilliseconds: Int64
    ) async throws {
        try requireActive()
        try await applyExternal(.replaceCandidates(
            candidates,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        ))
    }

    public func connectionLost(
        monotonicNowMilliseconds: Int64
    ) async throws {
        try requireActive()
        let before = snapshot()
        let route = connectedRoute
        connectedRoute = nil
        do {
            let effects = try state.apply(.connectionLost(
                monotonicNowMilliseconds: monotonicNowMilliseconds
            ))
            if let route { await route.close() }
            await handle(effects)
            publishStateChange(ifDifferentFrom: before)
        } catch {
            connectedRoute = route
            throw error
        }
    }

    public func manualDisconnect() async throws {
        try requireActive()
        try await applyExternal(.manualDisconnect)
    }

    public func resumeManualConnection() async throws {
        try requireActive()
        try await applyExternal(.resumeManualConnection)
    }

    public func resumeAfterUserAction() async throws {
        try requireActive()
        try await applyExternal(.resumeAfterUserAction)
    }

    /// Idempotently retires every task and authenticated route owned by this
    /// controller. Delayed round results remain fenced by the cleared round ID
    /// and close their own late authenticated route before returning.
    public func shutdown() async {
        guard !isShutdown else { return }
        let before = snapshot()
        isShutdown = true
        activeRoundTask?.cancel()
        activeRoundTask = nil
        activeRoundID = nil
        let route = connectedRoute
        connectedRoute = nil
        if let route { await route.close() }
        publishStateChange(ifDifferentFrom: before)
    }

    private func applyExternal(_ event: ReconnectEvent) async throws {
        let before = snapshot()
        let effects = try state.apply(event)
        await handle(effects)
        publishStateChange(ifDifferentFrom: before)
    }

    private func handle(_ effects: [ReconnectEffect]) async {
        for effect in effects {
            switch effect {
            case let .startDialRound(round):
                guard !isShutdown,
                      activeRoundTask == nil, activeRoundID == nil else {
                    failureObserved(.stateMachineFailure)
                    continue
                }
                activeRoundID = round.roundID
                activeRoundTask = Task { [executor, weak self] in
                    let result = await executor.execute(round)
                    await self?.roundFinished(
                        result,
                        roundID: round.roundID
                    )
                }
            case let .scheduleRetry(deadline):
                await retryScheduled(deadline)
            case .cancelPendingDials:
                activeRoundTask?.cancel()
                activeRoundTask = nil
                activeRoundID = nil
            case .closeConnection:
                let route = connectedRoute
                connectedRoute = nil
                if let route { await route.close() }
            }
        }
    }

    private func roundFinished(
        _ result: DialRoundRaceResultV0,
        roundID: UUID
    ) async {
        guard !isShutdown,
              activeRoundID == roundID,
              state.phase == .dialing(roundID) else {
            if case let .authenticated(route) = result {
                await route.close()
            }
            return
        }
        activeRoundTask = nil
        activeRoundID = nil
        let before = snapshot()
        defer { publishStateChange(ifDifferentFrom: before) }

        do {
            switch result {
            case let .authenticated(route):
                let effects = try state.apply(.authenticated(
                    roundID,
                    route.endpoint
                ))
                connectedRoute = route
                await route.selectedAsPrimary()
                await handle(effects)
            case .authenticationDenied, .invalidAttemptResult:
                let effects = try state.apply(.authenticationDenied(roundID))
                await handle(effects)
                if case .invalidAttemptResult = result {
                    failureObserved(.stateMachineFailure)
                }
            case .exhausted:
                let now = monotonicNow()
                let jitter = jitterBasisPoints()
                guard now >= 0, (8_000...12_000).contains(jitter) else {
                    let effects = try state.apply(.authenticationDenied(roundID))
                    await handle(effects)
                    failureObserved(.invalidRuntimeInput)
                    return
                }
                let effects = try state.apply(.roundExhausted(
                    roundID,
                    monotonicNowMilliseconds: now,
                    jitterBasisPoints: jitter
                ))
                await handle(effects)
            case .cancelled:
                failureObserved(.stateMachineFailure)
                let effects = try state.apply(.authenticationDenied(roundID))
                await handle(effects)
            }
        } catch {
            if case let .authenticated(route) = result {
                await route.close()
                connectedRoute = nil
            }
            failureObserved(.stateMachineFailure)
        }
    }

    private func publishStateChange(
        ifDifferentFrom before: ReconnectControllerSnapshotV0
    ) {
        guard snapshot() != before else { return }
        stateChanged()
    }

    private func requireActive() throws {
        guard !isShutdown else { throw ReconnectError.invalidTransition }
    }
}
