import CompanionAgent
import CompanionLifecycle
import CompanionMacApp
import Foundation

public struct MacLifecycleProcessObservationTokenV1:
    Equatable, Sendable
{
    public let role: AgentLoginRoleV1
    public let generation: UUID

    package init(role: AgentLoginRoleV1, generation: UUID) {
        self.role = role
        self.generation = generation
    }
}

public enum MacLifecycleProcessObservationDispositionV1:
    Equatable, Sendable
{
    case accepted
    case duplicate
    case ignoredStale
    case notEligible
    case recoveryNotCompleted
    case recoveryOutcomeUnknown
}

public struct MacLifecycleProcessObservationReceiptV1:
    Equatable, Sendable
{
    public let token: MacLifecycleProcessObservationTokenV1?
    public let disposition: MacLifecycleProcessObservationDispositionV1
    public let transition: CompletedLifecycleTransitionV0?

    public init(
        token: MacLifecycleProcessObservationTokenV1?,
        disposition: MacLifecycleProcessObservationDispositionV1,
        transition: CompletedLifecycleTransitionV0?
    ) {
        self.token = token
        self.disposition = disposition
        self.transition = transition
    }
}

/// Converts final-target-issued process generations into exact lifecycle
/// transitions. A token is only an anti-stale handle; the final target must
/// issue it from an authenticated Agent bootstrap or menu IPC/process source.
/// Login registration, a successful start request, PID presence, and a token
/// by themselves never produce `ready`.
public actor MacLifecycleProcessObservationOwnerV1 {
    private struct ActiveObservation: Sendable {
        let token: MacLifecycleProcessObservationTokenV1
        let epoch: UInt64
        var readyAccepted: Bool
    }

    private struct PendingRecovery: Equatable, Sendable {
        let revision: UInt64
        let epoch: UInt64
        let effect: ProductLifecycleEffect
    }

    public typealias TransitionIDSource = @Sendable () -> UUID

    private let lifecycle: any AgentRemoteLifecycleCommandingV1
    private let processStarter: any MacDashboardLifecycleProcessStartingV1
    private let wallClock: any MacDashboardLifecycleWallClockV1
    private let transitionIDSource: TransitionIDSource
    private var agentObservation: ActiveObservation?
    private var menuObservation: ActiveObservation?
    private var agentRecovery: PendingRecovery?
    private var menuRecovery: PendingRecovery?
    private var operationLocked = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        lifecycle: any AgentRemoteLifecycleCommandingV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        transitionIDSource: @escaping TransitionIDSource = { UUID() }
    ) {
        self.lifecycle = lifecycle
        self.processStarter = processStarter
        self.wallClock = wallClock
        self.transitionIDSource = transitionIDSource
    }

    /// Activates a generation after the final process/IPC source has
    /// authenticated it. Replacing an already-ready generation first applies
    /// the exact exit transition, but does not request a redundant recovery
    /// start because the replacement candidate already exists.
    public func activateObservation(
        role: AgentLoginRoleV1,
        generation: UUID
    ) async -> MacLifecycleProcessObservationReceiptV1 {
        await acquireOperation()
        defer { releaseOperation() }
        guard let observedAt = validatedWallTime() else {
            return receipt(.notEligible)
        }

        var snapshot = await lifecycle.currentSnapshot()
        guard processState(role, in: snapshot.state) != .stopped,
              snapshot.state.desiredEnabled,
              snapshot.state.consoleSession != .loggedOut else {
            setActive(nil, for: role)
            return receipt(.notEligible)
        }
        let token = MacLifecycleProcessObservationTokenV1(
            role: role,
            generation: generation
        )
        if let active = active(for: role),
           active.token == token,
           active.epoch == observationEpoch(role, in: snapshot) {
            return receipt(.duplicate, token: token)
        }

        var replacementTransition: CompletedLifecycleTransitionV0?
        if processState(role, in: snapshot.state) == .ready {
            do {
                let transition = try await lifecycle.apply(
                    exitEvent(role),
                    transitionID: transitionIDSource(),
                    observedAtUnixMilliseconds: observedAt
                )
                replacementTransition = transition.completed
                snapshot = await lifecycle.currentSnapshot()
            } catch {
                setActive(nil, for: role)
                return receipt(.notEligible)
            }
        }

        guard processState(role, in: snapshot.state) == .starting else {
            setActive(nil, for: role)
            return receipt(.notEligible, transition: replacementTransition)
        }
        setActive(ActiveObservation(
            token: token,
            epoch: observationEpoch(role, in: snapshot),
            readyAccepted: false
        ), for: role)
        setPendingRecovery(nil, for: role)
        return receipt(
            .accepted,
            token: token,
            transition: replacementTransition
        )
    }

    /// Accepts readiness only for the exact active generation and current
    /// role epoch. The final source must define ready as complete Agent
    /// bootstrap or authenticated visible-menu IPC/runtime readiness.
    public func observeReady(
        _ token: MacLifecycleProcessObservationTokenV1
    ) async -> MacLifecycleProcessObservationReceiptV1 {
        await acquireOperation()
        defer { releaseOperation() }
        guard let observedAt = validatedWallTime() else {
            return receipt(.notEligible, token: token)
        }
        guard var active = active(for: token.role),
              active.token == token else {
            return receipt(.ignoredStale, token: token)
        }
        let snapshot = await lifecycle.currentSnapshot()
        guard active.epoch == observationEpoch(token.role, in: snapshot) else {
            setActive(nil, for: token.role)
            return receipt(.ignoredStale, token: token)
        }
        if active.readyAccepted,
           processState(token.role, in: snapshot.state) == .ready {
            return receipt(.duplicate, token: token)
        }
        guard !active.readyAccepted,
              processState(token.role, in: snapshot.state) == .starting else {
            setActive(nil, for: token.role)
            return receipt(.notEligible, token: token)
        }

        do {
            let transition = try await lifecycle.apply(
                readyEvent(token.role),
                transitionID: transitionIDSource(),
                observedAtUnixMilliseconds: observedAt
            )
            guard transition.remainingPlatformEffects.isEmpty else {
                setActive(nil, for: token.role)
                return receipt(
                    .notEligible,
                    token: token,
                    transition: transition.completed
                )
            }
            active.readyAccepted = true
            setActive(active, for: token.role)
            return receipt(
                .accepted,
                token: token,
                transition: transition.completed
            )
        } catch {
            setActive(nil, for: token.role)
            return receipt(.notEligible, token: token)
        }
    }

    /// An exact active-generation termination advances the lifecycle before
    /// requesting the one matching recovery effect. Stale generations cannot
    /// end or restart the current process authority.
    public func observeTermination(
        _ token: MacLifecycleProcessObservationTokenV1
    ) async -> MacLifecycleProcessObservationReceiptV1 {
        await acquireOperation()
        defer { releaseOperation() }
        guard let observedAt = validatedWallTime() else {
            return receipt(.notEligible, token: token)
        }
        guard let active = active(for: token.role),
              active.token == token else {
            return receipt(.ignoredStale, token: token)
        }
        let snapshot = await lifecycle.currentSnapshot()
        guard active.epoch == observationEpoch(token.role, in: snapshot) else {
            setActive(nil, for: token.role)
            return receipt(.ignoredStale, token: token)
        }
        setActive(nil, for: token.role)
        if processState(token.role, in: snapshot.state) == .stopped {
            return receipt(.accepted, token: token)
        }

        let transition: AgentRemoteLifecycleTransitionV1
        do {
            transition = try await lifecycle.apply(
                exitEvent(token.role),
                transitionID: transitionIDSource(),
                observedAtUnixMilliseconds: observedAt
            )
        } catch {
            return receipt(.notEligible, token: token)
        }
        let expected = [recoveryEffect(token.role)]
        guard transition.remainingPlatformEffects == expected else {
            return receipt(
                .notEligible,
                token: token,
                transition: transition.completed
            )
        }
        let recoverySnapshot = await lifecycle.currentSnapshot()
        guard transition.completed.after == recoverySnapshot.state,
              processState(token.role, in: recoverySnapshot.state) == .starting,
              recoverySnapshot.state.desiredEnabled,
              recoverySnapshot.state.consoleSession != .loggedOut else {
            return receipt(
                .notEligible,
                token: token,
                transition: transition.completed
            )
        }
        let pending = PendingRecovery(
            revision: recoverySnapshot.revision,
            epoch: observationEpoch(token.role, in: recoverySnapshot),
            effect: expected[0]
        )
        setPendingRecovery(pending, for: token.role)
        let outcome = await processStarter.requestStarts(expected)
        let disposition: MacLifecycleProcessObservationDispositionV1
        switch outcome {
        case .completed:
            setPendingRecovery(nil, for: token.role)
            disposition = .accepted
        case .notCompleted:
            disposition = .recoveryNotCompleted
        case .outcomeUnknown:
            disposition = .recoveryOutcomeUnknown
        }
        return receipt(
            disposition,
            token: token,
            transition: transition.completed
        )
    }

    /// Repeats only a retained exact-role process-start request. The pending
    /// fence is removed as soon as a legitimate replacement observation is
    /// activated or any lifecycle revision/role epoch changes. This method is
    /// package-scoped so an unauthenticated caller cannot choose a role.
    package func retryPendingRecovery(
        role: AgentLoginRoleV1
    ) async -> MacLifecycleProcessObservationDispositionV1 {
        await acquireOperation()
        defer { releaseOperation() }
        guard let pending = pendingRecovery(for: role) else {
            return .ignoredStale
        }
        let before = await lifecycle.currentSnapshot()
        guard recoveryIsCurrent(pending, role: role, snapshot: before),
              active(for: role) == nil else {
            setPendingRecovery(nil, for: role)
            return .ignoredStale
        }

        let outcome = await processStarter.requestStarts([pending.effect])
        switch outcome {
        case .completed:
            setPendingRecovery(nil, for: role)
            return .accepted
        case .notCompleted, .outcomeUnknown:
            let after = await lifecycle.currentSnapshot()
            guard recoveryIsCurrent(pending, role: role, snapshot: after),
                  active(for: role) == nil else {
                setPendingRecovery(nil, for: role)
                return .ignoredStale
            }
            return outcome == .notCompleted
                ? .recoveryNotCompleted
                : .recoveryOutcomeUnknown
        }
    }

    private func validatedWallTime() -> Int64? {
        let value = wallClock.nowUnixMilliseconds()
        guard value >= 0,
              UInt64(value)
                <= MacRemoteAccessIntentSnapshotV1.maximumSafeInteger else {
            return nil
        }
        return value
    }

    private func acquireOperation() async {
        if !operationLocked {
            operationLocked = true
            return
        }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationLocked = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private func active(
        for role: AgentLoginRoleV1
    ) -> ActiveObservation? {
        switch role {
        case .agent: agentObservation
        case .menuApp: menuObservation
        }
    }

    private func setActive(
        _ value: ActiveObservation?,
        for role: AgentLoginRoleV1
    ) {
        switch role {
        case .agent: agentObservation = value
        case .menuApp: menuObservation = value
        }
    }

    private func pendingRecovery(
        for role: AgentLoginRoleV1
    ) -> PendingRecovery? {
        switch role {
        case .agent: agentRecovery
        case .menuApp: menuRecovery
        }
    }

    private func setPendingRecovery(
        _ value: PendingRecovery?,
        for role: AgentLoginRoleV1
    ) {
        switch role {
        case .agent: agentRecovery = value
        case .menuApp: menuRecovery = value
        }
    }

    private func recoveryIsCurrent(
        _ pending: PendingRecovery,
        role: AgentLoginRoleV1,
        snapshot: AgentRemoteLifecycleSnapshotV1
    ) -> Bool {
        snapshot.revision == pending.revision
            && observationEpoch(role, in: snapshot) == pending.epoch
            && processState(role, in: snapshot.state) == .starting
            && snapshot.state.desiredEnabled
            && snapshot.state.consoleSession != .loggedOut
            && pending.effect == recoveryEffect(role)
    }

    private func processState(
        _ role: AgentLoginRoleV1,
        in state: ProductLifecycleState
    ) -> ManagedProcessState {
        switch role {
        case .agent: state.agent
        case .menuApp: state.menuApp
        }
    }

    private func observationEpoch(
        _ role: AgentLoginRoleV1,
        in snapshot: AgentRemoteLifecycleSnapshotV1
    ) -> UInt64 {
        switch role {
        case .agent: snapshot.agentObservationEpoch
        case .menuApp: snapshot.menuAppObservationEpoch
        }
    }

    private func readyEvent(
        _ role: AgentLoginRoleV1
    ) -> ProductLifecycleEvent {
        switch role {
        case .agent: .agentReady
        case .menuApp: .menuAppReady
        }
    }

    private func exitEvent(
        _ role: AgentLoginRoleV1
    ) -> ProductLifecycleEvent {
        switch role {
        case .agent: .agentExited
        case .menuApp: .menuAppExited
        }
    }

    private func recoveryEffect(
        _ role: AgentLoginRoleV1
    ) -> ProductLifecycleEffect {
        switch role {
        case .agent: .requestAgentRecovery
        case .menuApp: .requestMenuRecovery
        }
    }

    private func receipt(
        _ disposition: MacLifecycleProcessObservationDispositionV1,
        token: MacLifecycleProcessObservationTokenV1? = nil,
        transition: CompletedLifecycleTransitionV0? = nil
    ) -> MacLifecycleProcessObservationReceiptV1 {
        MacLifecycleProcessObservationReceiptV1(
            token: token,
            disposition: disposition,
            transition: transition
        )
    }
}
