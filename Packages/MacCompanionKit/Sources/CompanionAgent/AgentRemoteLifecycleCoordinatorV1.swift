import CompanionLifecycle
import Foundation

public enum AgentRemoteLifecycleCoordinatorErrorV1:
    Error, Equatable, Sendable
{
    case transitionInProgress
    case stalePreparedTransition
    case revisionExhausted
}

public struct AgentRemoteLifecycleSnapshotV1: Equatable, Sendable {
    public let revision: UInt64
    public let agentObservationEpoch: UInt64
    public let menuAppObservationEpoch: UInt64
    public let state: ProductLifecycleState

    public init(
        revision: UInt64,
        agentObservationEpoch: UInt64 = 0,
        menuAppObservationEpoch: UInt64 = 0,
        state: ProductLifecycleState
    ) {
        self.revision = revision
        self.agentObservationEpoch = agentObservationEpoch
        self.menuAppObservationEpoch = menuAppObservationEpoch
        self.state = state
    }
}

public struct AgentRemoteLifecyclePreparedTransitionV1:
    Equatable, Sendable
{
    public let baseRevision: UInt64
    public let completed: CompletedLifecycleTransitionV0

    public init(
        baseRevision: UInt64,
        completed: CompletedLifecycleTransitionV0
    ) {
        self.baseRevision = baseRevision
        self.completed = completed
    }
}

public protocol AgentRemoteLifecycleCommandingV1: Sendable {
    func currentState() async -> ProductLifecycleState
    func currentSnapshot() async -> AgentRemoteLifecycleSnapshotV1

    func prepare(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async throws -> AgentRemoteLifecyclePreparedTransitionV1

    func commitPrepared(
        _ transition: AgentRemoteLifecyclePreparedTransitionV1
    ) async throws -> AgentRemoteLifecycleTransitionV1

    func apply(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async throws -> AgentRemoteLifecycleTransitionV1
}

public struct AgentRemoteLifecycleTransitionV1: Equatable, Sendable {
    public let completed: CompletedLifecycleTransitionV0
    public let remainingPlatformEffects: [ProductLifecycleEffect]

    public init(completed: CompletedLifecycleTransitionV0) {
        self.completed = completed
        remainingPlatformEffects = completed.effects.filter {
            $0 != .endInteractiveControl && $0 != .closeAllRemoteSessions
        }
    }
}

/// Applies the pure lifecycle reducer, completes its remote-authority teardown
/// effects, then records best-effort lifecycle detail. Login registration and
/// process recovery effects remain explicit output for the signed platform
/// owner; this bundle-independent coordinator does not impersonate SMAppService.
public actor AgentRemoteLifecycleCoordinatorV1:
    AgentRemoteLifecycleCommandingV1
{
    public private(set) var state: ProductLifecycleState
    public private(set) var revision: UInt64 = 0
    public private(set) var agentObservationEpoch: UInt64 = 0
    public private(set) var menuAppObservationEpoch: UInt64 = 0

    private let primarySessions: AgentPrimarySessionAuthorityV1
    private let auditWriter: any LifecycleAuditWritingV0
    private let localStatus: AgentLocalLifecycleStatusPublisherV1
    private var transitionInProgress = false

    package init(
        initialState: ProductLifecycleState,
        primarySessions: AgentPrimarySessionAuthorityV1,
        auditWriter: any LifecycleAuditWritingV0,
        localStatus: AgentLocalLifecycleStatusPublisherV1
    ) {
        state = initialState
        self.primarySessions = primarySessions
        self.auditWriter = auditWriter
        self.localStatus = localStatus
    }

    public func currentState() -> ProductLifecycleState { state }

    public func currentSnapshot() -> AgentRemoteLifecycleSnapshotV1 {
        AgentRemoteLifecycleSnapshotV1(
            revision: revision,
            agentObservationEpoch: agentObservationEpoch,
            menuAppObservationEpoch: menuAppObservationEpoch,
            state: state
        )
    }

    /// Builds an exact transition from the current state without reserving or
    /// mutating it. Login-role registration may occur against this value; the
    /// later commit is compare-and-set and fails if a lock/logout/crash or
    /// another lifecycle event changed the state in the meantime.
    public func prepare(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) throws -> AgentRemoteLifecyclePreparedTransitionV1 {
        guard !transitionInProgress else {
            throw AgentRemoteLifecycleCoordinatorErrorV1.transitionInProgress
        }
        return AgentRemoteLifecyclePreparedTransitionV1(
            baseRevision: revision,
            completed: try makeTransition(
                from: state,
                event: event,
                transitionID: transitionID,
                observedAtUnixMilliseconds: observedAtUnixMilliseconds
            )
        )
    }

    public func commitPrepared(
        _ transition: AgentRemoteLifecyclePreparedTransitionV1
    ) async throws -> AgentRemoteLifecycleTransitionV1 {
        guard !transitionInProgress else {
            throw AgentRemoteLifecycleCoordinatorErrorV1.transitionInProgress
        }
        guard transition.baseRevision == revision,
              transition.completed.before == state else {
            throw AgentRemoteLifecycleCoordinatorErrorV1
                .stalePreparedTransition
        }
        transitionInProgress = true
        defer { transitionInProgress = false }
        return try await commit(transition.completed)
    }

    public func apply(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async throws -> AgentRemoteLifecycleTransitionV1 {
        guard !transitionInProgress else {
            throw AgentRemoteLifecycleCoordinatorErrorV1.transitionInProgress
        }
        transitionInProgress = true
        defer { transitionInProgress = false }

        let completed = try makeTransition(
            from: state,
            event: event,
            transitionID: transitionID,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        )
        return try await commit(completed)
    }

    private func makeTransition(
        from before: ProductLifecycleState,
        event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) throws -> CompletedLifecycleTransitionV0 {
        var after = before
        let effects = try after.apply(event)
        return try CompletedLifecycleTransitionV0(
            transitionID: transitionID,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds,
            before: before,
            event: event,
            after: after,
            effects: effects
        )
    }

    private func commit(
        _ completed: CompletedLifecycleTransitionV0
    ) async throws -> AgentRemoteLifecycleTransitionV1 {
        let advanceAgentEpoch = completed.event == .agentExited
            || (completed.event != .agentReady
                && completed.before.agent != completed.after.agent)
        let advanceMenuEpoch = completed.event == .menuAppExited
            || (completed.event != .menuAppReady
                && completed.before.menuApp != completed.after.menuApp)
        guard revision < UInt64.max,
              !advanceAgentEpoch || agentObservationEpoch < UInt64.max,
              !advanceMenuEpoch || menuAppObservationEpoch < UInt64.max else {
            throw AgentRemoteLifecycleCoordinatorErrorV1.revisionExhausted
        }
        revision += 1
        if advanceAgentEpoch { agentObservationEpoch += 1 }
        if advanceMenuEpoch { menuAppObservationEpoch += 1 }
        state = completed.after
        await primarySessions.setLifecycleIngressEnabled(
            completed.after.observeAvailable
        )

        if completed.effects.contains(.closeAllRemoteSessions) {
            // Closing the primary owner also tears down its Interactive state;
            // do not issue a second, separately ordered notification.
            await primarySessions.closeCurrent()
        } else if completed.effects.contains(.endInteractiveControl) {
            await primarySessions.endInteractiveControl()
        }

        await localStatus.publish(completed.after)
        await auditWriter.recordCompletedTransition(completed)
        return AgentRemoteLifecycleTransitionV1(completed: completed)
    }
}
