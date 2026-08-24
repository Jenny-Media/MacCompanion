import Foundation

public enum ClientConfiguredRouteApplicationBindingPhaseV1:
    String, Equatable, Sendable
{
    case pending
    case running
    case closed
}

public enum ClientConfiguredRouteApplicationBindingErrorV1:
    Error, Equatable, Sendable
{
    case stateMismatch
    case invalidPhase
    case invalidClock
    case invalidRoundID
    case closed
}

public struct ClientConfiguredRouteApplicationBindingSnapshotV1:
    Equatable, Sendable
{
    public let phase: ClientConfiguredRouteApplicationBindingPhaseV1
    public let foreground: Bool
    public let networkReachable: Bool
    public let hasStartedEligibleRound: Bool
    public let queuedEventCount: Int
    public let isDraining: Bool
    /// The same validated route-lifecycle composition owned by this binding.
    /// Consumers must not combine these values with a separate storage read.
    public let lifecycle: ClientConfiguredRouteLifecycleSnapshotV1
}

/// Serial app-boundary owner for one configured-route lifecycle. Foreground
/// and reachability are local scheduling facts only; neither can add,
/// classify, or replace a route. Pending events synchronize the lifecycle but
/// cannot dial. Once started, each false-to-eligible transition begins exactly
/// one round through `ClientConfiguredRouteLifecycleV1.startRound`, which
/// revalidates identity and reconciles durable routes before any attempt.
public actor ClientConfiguredRouteApplicationBindingV1 {
    public typealias MonotonicNow = @Sendable () -> Int64
    public typealias RoundID = @Sendable () -> UUID
    package typealias RetryWait = @Sendable (Int64) async -> Void

    public nonisolated let reconnectStateChanges: AsyncStream<Void>

    private enum Event: Sendable {
        case start
        case setForeground(Bool)
        case setNetworkReachable(Bool)
        case primaryConnectionLost
        case close
    }

    private struct QueuedEvent {
        let event: Event
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lifecycle: ClientConfiguredRouteLifecycleV1
    private let monotonicNow: MonotonicNow
    private let roundID: RoundID
    private let retryWait: RetryWait
    private var phase = ClientConfiguredRouteApplicationBindingPhaseV1.pending
    private var foreground: Bool
    private var networkReachable: Bool
    private var hasStartedEligibleRound = false
    private var queue: [QueuedEvent] = []
    private var isDraining = false
    private var retryTask: Task<Void, Never>?
    private var scheduledRetryDeadline: Int64?

    public init(
        lifecycle: ClientConfiguredRouteLifecycleV1,
        monotonicNow: @escaping MonotonicNow,
        roundID: @escaping RoundID = { UUID() }
    ) async throws {
        try await self.init(
            lifecycle: lifecycle,
            monotonicNow: monotonicNow,
            roundID: roundID,
            retryWait: { milliseconds in
                guard milliseconds > 0 else { return }
                try? await Task.sleep(
                    nanoseconds: UInt64(milliseconds) * 1_000_000
                )
            }
        )
    }

    package init(
        lifecycle: ClientConfiguredRouteLifecycleV1,
        monotonicNow: @escaping MonotonicNow,
        roundID: @escaping RoundID,
        retryWait: @escaping RetryWait
    ) async throws {
        let snapshot = await lifecycle.snapshot()
        guard snapshot.phase != .closed,
              snapshot.phase == (snapshot.reconnect.foreground
                ? .active : .background) else {
            throw ClientConfiguredRouteApplicationBindingErrorV1
                .stateMismatch
        }
        self.lifecycle = lifecycle
        self.monotonicNow = monotonicNow
        self.roundID = roundID
        self.retryWait = retryWait
        reconnectStateChanges = lifecycle.reconnectStateChanges
        foreground = snapshot.reconnect.foreground
        networkReachable = snapshot.reconnect.networkReachable
    }

    public func snapshot() async
        -> ClientConfiguredRouteApplicationBindingSnapshotV1
    {
        ClientConfiguredRouteApplicationBindingSnapshotV1(
            phase: phase,
            foreground: foreground,
            networkReachable: networkReachable,
            hasStartedEligibleRound: hasStartedEligibleRound,
            queuedEventCount: queue.count,
            isDraining: isDraining,
            lifecycle: await lifecycle.snapshot()
        )
    }

    public func start() async throws {
        try await submit(.start)
    }

    public func setForeground(_ value: Bool) async throws {
        try await submit(.setForeground(value))
    }

    public func setNetworkReachable(_ value: Bool) async throws {
        try await submit(.setNetworkReachable(value))
    }

    /// Called only after the exact selected primary product reports that its
    /// authenticated transport terminated. The durable identity and route
    /// catalog remain authoritative; this event only rearms an eligible dial.
    package func primaryConnectionLost() async throws {
        try await submit(.primaryConnectionLost)
    }

    /// Consumes content-free reconnect state wakeups and owns the one delayed
    /// backoff task. A deadline never carries route or trust authority.
    package func reconnectStateDidChange() async {
        await synchronizeRetryTask()
    }

    public func close() async {
        try? await submit(.close)
    }

    private func submit(_ event: Event) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.append(QueuedEvent(
                event: event,
                continuation: continuation
            ))
            guard !isDraining else { return }
            isDraining = true
            Task { await self.drain() }
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let queued = queue.removeFirst()
            do {
                try await apply(queued.event)
                queued.continuation.resume()
            } catch {
                queued.continuation.resume(throwing: error)
            }
        }
        isDraining = false
    }

    private func apply(_ event: Event) async throws {
        if phase == .closed {
            if case .close = event { return }
            throw ClientConfiguredRouteApplicationBindingErrorV1.closed
        }

        switch event {
        case .start:
            guard phase == .pending else {
                throw ClientConfiguredRouteApplicationBindingErrorV1
                    .invalidPhase
            }
            phase = .running
            try await startEligibleRoundIfNeeded()

        case let .setForeground(value):
            guard value != foreground else { return }
            do {
                try await lifecycle.setForeground(
                    value,
                    monotonicNowMilliseconds: try now()
                )
                foreground = value
                if !value { hasStartedEligibleRound = false }
                try await startEligibleRoundIfNeeded()
            } catch {
                await failClosed()
                throw error
            }

        case let .setNetworkReachable(value):
            guard value != networkReachable else { return }
            do {
                try await lifecycle.setNetworkReachable(
                    value,
                    monotonicNowMilliseconds: try now()
                )
                networkReachable = value
                if !value { hasStartedEligibleRound = false }
                try await startEligibleRoundIfNeeded()
            } catch {
                await failClosed()
                throw error
            }

        case .primaryConnectionLost:
            guard phase == .running else { return }
            let reconnect = await lifecycle.snapshot().reconnect.reconnect
            guard case .connected = reconnect.phase else { return }
            do {
                try await lifecycle.primaryConnectionLost(
                    monotonicNowMilliseconds: try now()
                )
                hasStartedEligibleRound = false
                cancelRetryTask()
                try await startEligibleRoundIfNeeded()
            } catch {
                await failClosed()
                throw error
            }

        case .close:
            await failClosed()
        }
    }

    private func startEligibleRoundIfNeeded() async throws {
        guard phase == .running,
              foreground,
              networkReachable,
              !hasStartedEligibleRound else { return }
        let identifier = roundID()
        guard identifier != UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        ) else {
            await failClosed()
            throw ClientConfiguredRouteApplicationBindingErrorV1
                .invalidRoundID
        }
        do {
            try await lifecycle.startRound(
                roundID: identifier,
                monotonicNowMilliseconds: try now()
            )
            hasStartedEligibleRound = true
        } catch {
            await failClosed()
            throw error
        }
    }

    private func now() throws -> Int64 {
        let value = monotonicNow()
        guard value >= 0 else {
            throw ClientConfiguredRouteApplicationBindingErrorV1
                .invalidClock
        }
        return value
    }

    private func failClosed() async {
        guard phase != .closed else { return }
        phase = .closed
        hasStartedEligibleRound = false
        cancelRetryTask()
        await lifecycle.close()
    }

    private func synchronizeRetryTask() async {
        guard phase == .running else {
            cancelRetryTask()
            return
        }
        let reconnect = await lifecycle.snapshot().reconnect.reconnect
        guard case let .backoff(deadline) = reconnect.phase else {
            cancelRetryTask()
            return
        }
        guard scheduledRetryDeadline != deadline else { return }
        scheduleRetry(deadline: deadline)
    }

    private func scheduleRetry(deadline: Int64) {
        retryTask?.cancel()
        scheduledRetryDeadline = deadline
        let delay = max(0, deadline - monotonicNow())
        retryTask = Task { [weak self, retryWait] in
            await retryWait(delay)
            guard !Task.isCancelled else { return }
            await self?.retryDeadlineReached(deadline)
        }
    }

    private func retryDeadlineReached(_ deadline: Int64) async {
        guard phase == .running,
              scheduledRetryDeadline == deadline else { return }
        let current = await lifecycle.snapshot().reconnect.reconnect
        guard case let .backoff(currentDeadline) = current.phase,
              currentDeadline == deadline else {
            cancelRetryTask()
            return
        }
        let currentTime = monotonicNow()
        guard currentTime >= deadline else {
            scheduleRetry(deadline: deadline)
            return
        }
        retryTask = nil
        scheduledRetryDeadline = nil
        hasStartedEligibleRound = false
        do {
            try await startEligibleRoundIfNeeded()
        } catch {
            await failClosed()
        }
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
        scheduledRetryDeadline = nil
    }
}
