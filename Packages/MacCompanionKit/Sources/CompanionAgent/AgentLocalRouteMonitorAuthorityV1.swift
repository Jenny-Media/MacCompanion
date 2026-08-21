import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation

public enum AgentLocalRouteMonitorStateV1:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case stopped
    case observing
    case unavailable
}

public enum AgentLocalRouteMonitorErrorV1: Error, Equatable, Sendable {
    case generationExhausted
    case invalidTime
    case timeRegressed
}

/// Content-free route-source state. It cannot represent an address, hostname,
/// interface, peer, DNS result, credential, or platform error.
public struct AgentLocalRouteMonitorSnapshotV1: Equatable, Sendable {
    public let state: AgentLocalRouteMonitorStateV1
    public let generation: UInt64
    public let routeKinds: Set<LocalRouteKind>
    public let lastObservedAtMonotonicMilliseconds: Int64?
    public let freshUntilMonotonicMilliseconds: Int64?
}

/// Bundle-independent ordering/freshness authority behind a future concrete
/// platform path monitor. Every accepted source event creates one generation;
/// the local-status sink independently rejects an older delayed publication.
public actor AgentLocalRouteMonitorAuthorityV1 {
    public static let freshnessWindowMilliseconds: Int64 = 30_000

    private let localStatus: AgentLocalStatusAuthorityV1
    private var state: AgentLocalRouteMonitorStateV1 = .stopped
    private var generation: UInt64 = 0
    private var routeKinds: Set<LocalRouteKind> = []
    /// Only these kinds are governed by `freshUntil`. Exact listener/Bonjour
    /// evidence is event-owned and must not be refreshed by an unrelated
    /// configured-route heartbeat.
    private var freshnessScopedKinds: Set<LocalRouteKind> = []
    private var lastObservedAtMonotonicMilliseconds: Int64?
    private var freshUntilMonotonicMilliseconds: Int64?
    private var lastAcceptedClockMilliseconds: Int64?

    public init(localStatus: AgentLocalStatusAuthorityV1) {
        self.localStatus = localStatus
    }

    @discardableResult
    func publishAvailable(
        routeKinds: Set<LocalRouteKind>,
        observedAtMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        try validateSourceTime(observedAtMonotonicMilliseconds)
        guard observedAtMonotonicMilliseconds
                <= WireLimits.maximumSafeInteger
                    - Self.freshnessWindowMilliseconds else {
            throw AgentLocalRouteMonitorErrorV1.invalidTime
        }
        let next = try nextGeneration()
        state = .observing
        generation = next
        self.routeKinds = routeKinds
        freshnessScopedKinds = routeKinds
        lastObservedAtMonotonicMilliseconds =
            observedAtMonotonicMilliseconds
        freshUntilMonotonicMilliseconds =
            observedAtMonotonicMilliseconds
                + Self.freshnessWindowMilliseconds
        lastAcceptedClockMilliseconds = observedAtMonotonicMilliseconds
        let result = currentSnapshot()
        await publishToLocalStatus(
            routeKinds: routeKinds,
            routeUnavailable: routeKinds.isEmpty,
            generation: next
        )
        return result
    }

    @discardableResult
    func publishUnavailable(
        observedAtMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        try validateSourceTime(observedAtMonotonicMilliseconds)
        let next = try nextGeneration()
        state = .unavailable
        generation = next
        routeKinds = []
        freshnessScopedKinds = []
        lastObservedAtMonotonicMilliseconds =
            observedAtMonotonicMilliseconds
        freshUntilMonotonicMilliseconds = nil
        lastAcceptedClockMilliseconds = observedAtMonotonicMilliseconds
        let result = currentSnapshot()
        await publishToLocalStatus(
            routeKinds: [],
            routeUnavailable: true,
            generation: next
        )
        return result
    }

    @discardableResult
    func stop(
        observedAtMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        try validateSourceTime(observedAtMonotonicMilliseconds)
        let next = try nextGeneration()
        state = .stopped
        generation = next
        routeKinds = []
        freshnessScopedKinds = []
        lastObservedAtMonotonicMilliseconds =
            observedAtMonotonicMilliseconds
        freshUntilMonotonicMilliseconds = nil
        lastAcceptedClockMilliseconds = observedAtMonotonicMilliseconds
        let result = currentSnapshot()
        await publishToLocalStatus(
            routeKinds: [],
            routeUnavailable: false,
            generation: next
        )
        return result
    }

    /// A fresh source contribution is valid through its inclusive deadline.
    /// The first later read withdraws only that contribution, preserving exact
    /// event-owned sources such as listener-plus-Bonjour LAN evidence.
    public func snapshot(
        nowMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        try validateOrderedClock(nowMonotonicMilliseconds)
        if state == .observing,
           let freshUntilMonotonicMilliseconds,
           nowMonotonicMilliseconds > freshUntilMonotonicMilliseconds {
            let next = try nextGeneration()
            routeKinds.subtract(freshnessScopedKinds)
            freshnessScopedKinds = []
            state = routeKinds.isEmpty ? .unavailable : .observing
            generation = next
            self.freshUntilMonotonicMilliseconds = nil
            lastAcceptedClockMilliseconds = nowMonotonicMilliseconds
            await publishToLocalStatus(
                routeKinds: routeKinds,
                routeUnavailable: routeKinds.isEmpty,
                generation: next
            )
        } else {
            lastAcceptedClockMilliseconds = nowMonotonicMilliseconds
        }
        return currentSnapshot()
    }

    @discardableResult
    func publishLANAvailability(
        available: Bool,
        observedAtMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        try validateSourceTime(observedAtMonotonicMilliseconds)
        var nextKinds = routeKindsAfterApplyingDueFreshness(
            at: observedAtMonotonicMilliseconds
        )
        if available {
            nextKinds.insert(.lan)
        } else {
            nextKinds.remove(.lan)
        }
        let next = try nextGeneration()
        state = .observing
        generation = next
        routeKinds = nextKinds
        lastObservedAtMonotonicMilliseconds =
            observedAtMonotonicMilliseconds
        lastAcceptedClockMilliseconds = observedAtMonotonicMilliseconds
        let result = currentSnapshot()
        await publishToLocalStatus(
            routeKinds: nextKinds,
            routeUnavailable: nextKinds.isEmpty,
            generation: next
        )
        return result
    }

    /// Replaces only the authenticated configured-route contribution. LAN is
    /// owned by the exact listener/Bonjour evidence authority and is retained.
    /// A primary connection can publish at most one configured route class.
    @discardableResult
    func publishAuthenticatedRouteAvailability(
        routeClass: ConfiguredRouteClassV1?,
        observedAtMonotonicMilliseconds: Int64
    ) async throws -> AgentLocalRouteMonitorSnapshotV1 {
        let effectiveObservedAtMonotonicMilliseconds: Int64
        if routeClass == nil {
            // Withdrawal is a narrowing transition. A valid disconnect clock
            // sampled just behind another source event clamps forward so
            // teardown cannot leave configured-route evidence stale.
            try validateClock(observedAtMonotonicMilliseconds)
            effectiveObservedAtMonotonicMilliseconds = max(
                observedAtMonotonicMilliseconds,
                lastAcceptedClockMilliseconds ?? 0
            )
            try validateSourceTime(
                effectiveObservedAtMonotonicMilliseconds
            )
        } else {
            try validateSourceTime(observedAtMonotonicMilliseconds)
            guard observedAtMonotonicMilliseconds
                    <= WireLimits.maximumSafeInteger
                        - Self.freshnessWindowMilliseconds else {
                throw AgentLocalRouteMonitorErrorV1.invalidTime
            }
            effectiveObservedAtMonotonicMilliseconds =
                observedAtMonotonicMilliseconds
        }
        var nextKinds = routeKinds
        nextKinds.remove(.privateDNS)
        nextKinds.remove(.privateNetwork)
        switch routeClass {
        case .privateDNS:
            nextKinds.insert(.privateDNS)
        case .privateNetwork:
            nextKinds.insert(.privateNetwork)
        case nil:
            break
        }
        let next = try nextGeneration()
        state = .observing
        generation = next
        routeKinds = nextKinds
        freshnessScopedKinds = switch routeClass {
        case .privateDNS: [.privateDNS]
        case .privateNetwork: [.privateNetwork]
        case nil: []
        }
        lastObservedAtMonotonicMilliseconds =
            effectiveObservedAtMonotonicMilliseconds
        freshUntilMonotonicMilliseconds = routeClass == nil
            ? nil
            : effectiveObservedAtMonotonicMilliseconds
                + Self.freshnessWindowMilliseconds
        lastAcceptedClockMilliseconds =
            effectiveObservedAtMonotonicMilliseconds
        let result = currentSnapshot()
        await publishToLocalStatus(
            routeKinds: nextKinds,
            routeUnavailable: nextKinds.isEmpty,
            generation: next
        )
        return result
    }

    private func routeKindsAfterApplyingDueFreshness(
        at observedAtMonotonicMilliseconds: Int64
    ) -> Set<LocalRouteKind> {
        guard let freshUntilMonotonicMilliseconds,
              observedAtMonotonicMilliseconds
                > freshUntilMonotonicMilliseconds else {
            return routeKinds
        }
        var current = routeKinds
        current.subtract(freshnessScopedKinds)
        freshnessScopedKinds = []
        self.freshUntilMonotonicMilliseconds = nil
        return current
    }

    private func publishToLocalStatus(
        routeKinds: Set<LocalRouteKind>,
        routeUnavailable: Bool,
        generation: UInt64
    ) async {
        do {
            try await localStatus.updateRoutes(
                routeKinds: routeKinds,
                routeUnavailable: routeUnavailable,
                generation: generation
            )
        } catch AgentLocalStatusAuthorityErrorV1.staleRouteGeneration {
            // A newer reentrant source event already published its version.
        } catch {
            assertionFailure("closed route projection unexpectedly failed")
        }
    }

    private func validateSourceTime(_ value: Int64) throws {
        try validateOrderedClock(value)
        if let previous = lastObservedAtMonotonicMilliseconds,
           value < previous {
            throw AgentLocalRouteMonitorErrorV1.timeRegressed
        }
    }

    private func validateClock(_ value: Int64) throws {
        guard value >= 0, value <= WireLimits.maximumSafeInteger else {
            throw AgentLocalRouteMonitorErrorV1.invalidTime
        }
    }

    private func validateOrderedClock(_ value: Int64) throws {
        try validateClock(value)
        if let previous = lastAcceptedClockMilliseconds,
           value < previous {
            throw AgentLocalRouteMonitorErrorV1.timeRegressed
        }
    }

    private func nextGeneration() throws -> UInt64 {
        guard generation
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalRouteMonitorErrorV1.generationExhausted
        }
        return generation + 1
    }

    private func currentSnapshot() -> AgentLocalRouteMonitorSnapshotV1 {
        AgentLocalRouteMonitorSnapshotV1(
            state: state,
            generation: generation,
            routeKinds: routeKinds,
            lastObservedAtMonotonicMilliseconds:
                lastObservedAtMonotonicMilliseconds,
            freshUntilMonotonicMilliseconds:
                freshUntilMonotonicMilliseconds
        )
    }
}
