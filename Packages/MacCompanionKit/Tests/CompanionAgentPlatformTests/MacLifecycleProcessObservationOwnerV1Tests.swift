import CompanionAgent
import CompanionAgentPlatform
import CompanionLifecycle
import CompanionMacApp
import Foundation
import Testing

private actor ProcessObservationLifecycleV1:
    AgentRemoteLifecycleCommandingV1
{
    private var state: ProductLifecycleState
    private var revision: UInt64 = 0
    private var agentEpoch: UInt64 = 0
    private var menuEpoch: UInt64 = 0
    private var events: [ProductLifecycleEvent] = []

    init(state: ProductLifecycleState) { self.state = state }

    func currentState() -> ProductLifecycleState { state }

    func currentSnapshot() -> AgentRemoteLifecycleSnapshotV1 {
        AgentRemoteLifecycleSnapshotV1(
            revision: revision,
            agentObservationEpoch: agentEpoch,
            menuAppObservationEpoch: menuEpoch,
            state: state
        )
    }

    func recordedEvents() -> [ProductLifecycleEvent] { events }

    func prepare(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) throws -> AgentRemoteLifecyclePreparedTransitionV1 {
        var after = state
        let effects = try after.apply(event)
        return AgentRemoteLifecyclePreparedTransitionV1(
            baseRevision: revision,
            completed: try CompletedLifecycleTransitionV0(
                transitionID: transitionID,
                observedAtUnixMilliseconds: observedAtUnixMilliseconds,
                before: state,
                event: event,
                after: after,
                effects: effects
            )
        )
    }

    func commitPrepared(
        _ transition: AgentRemoteLifecyclePreparedTransitionV1
    ) throws -> AgentRemoteLifecycleTransitionV1 {
        guard transition.baseRevision == revision,
              transition.completed.before == state else {
            throw AgentRemoteLifecycleCoordinatorErrorV1
                .stalePreparedTransition
        }
        advance(transition.completed)
        return AgentRemoteLifecycleTransitionV1(
            completed: transition.completed
        )
    }

    func apply(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) throws -> AgentRemoteLifecycleTransitionV1 {
        let prepared = try prepare(
            event,
            transitionID: transitionID,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        )
        return try commitPrepared(prepared)
    }

    private func advance(_ transition: CompletedLifecycleTransitionV0) {
        if transition.event == .agentExited
            || (transition.event != .agentReady
                && transition.before.agent != transition.after.agent) {
            agentEpoch += 1
        }
        if transition.event == .menuAppExited
            || (transition.event != .menuAppReady
                && transition.before.menuApp != transition.after.menuApp) {
            menuEpoch += 1
        }
        revision += 1
        state = transition.after
        events.append(transition.event)
    }
}

private actor ProcessObservationStarterV1:
    MacDashboardLifecycleProcessStartingV1
{
    private var outcomes: [MacAgentDashboardEffectOutcomeV0]
    private var requests: [[ProductLifecycleEffect]] = []
    private let gate: ProcessObservationGateV1?

    init(
        outcome: MacAgentDashboardEffectOutcomeV0 = .completed,
        gate: ProcessObservationGateV1? = nil
    ) {
        outcomes = [outcome]
        self.gate = gate
    }

    init(
        outcomes: [MacAgentDashboardEffectOutcomeV0],
        gate: ProcessObservationGateV1? = nil
    ) {
        precondition(!outcomes.isEmpty)
        self.outcomes = outcomes
        self.gate = gate
    }

    func requestStarts(
        _ effects: [ProductLifecycleEffect]
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        requests.append(effects)
        if let gate { await gate.wait() }
        if outcomes.count > 1 { return outcomes.removeFirst() }
        return outcomes[0]
    }

    func recordedRequests() -> [[ProductLifecycleEffect]] { requests }
}

private actor ProcessRecoverySleepRecorderV1 {
    private var delays: [UInt64] = []

    func sleep(_ delay: UInt64) {
        delays.append(delay)
    }

    func recordedDelays() -> [UInt64] { delays }
}

private actor ProcessRecoverySleepGateV1 {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_: UInt64) async throws {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor ProcessObservationGateV1 {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private struct ProcessObservationClockV1:
    MacDashboardLifecycleWallClockV1
{
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private func processObservationStateV1(
    agent: ManagedProcessState = .starting,
    menu: ManagedProcessState = .starting,
    console: ConsoleSessionState = .active,
    enabled: Bool = true
) -> ProductLifecycleState {
    ProductLifecycleState(
        desiredEnabled: enabled,
        consoleSession: console,
        agent: agent,
        menuApp: menu
    )
}

private func processObservationOwnerV1(
    state: ProductLifecycleState = processObservationStateV1(),
    outcome: MacAgentDashboardEffectOutcomeV0 = .completed,
    clock: Int64 = 1_787_198_400_000,
    gate: ProcessObservationGateV1? = nil
) -> (
    owner: MacLifecycleProcessObservationOwnerV1,
    lifecycle: ProcessObservationLifecycleV1,
    starter: ProcessObservationStarterV1
) {
    let lifecycle = ProcessObservationLifecycleV1(state: state)
    let starter = ProcessObservationStarterV1(outcome: outcome, gate: gate)
    return (
        MacLifecycleProcessObservationOwnerV1(
            lifecycle: lifecycle,
            processStarter: starter,
            wallClock: ProcessObservationClockV1(value: clock),
            transitionIDSource: {
                UUID(uuidString: "12345678-1234-4234-8234-1234567890ab")!
            }
        ),
        lifecycle,
        starter
    )
}

@Test(arguments: [AgentLoginRoleV1.agent, .menuApp])
func exactProcessGenerationAloneDoesNotClaimReady(
    role: AgentLoginRoleV1
) async throws {
    let product = processObservationOwnerV1()
    let activation = await product.owner.activateObservation(
        role: role,
        generation: UUID()
    )
    #expect(activation.disposition == .accepted)
    #expect(activation.transition == nil)
    let before = await product.lifecycle.currentState()
    #expect(role == .agent ? before.agent == .starting : before.menuApp == .starting)

    let token = try #require(activation.token)
    let ready = await product.owner.observeReady(token)
    #expect(ready.disposition == .accepted)
    #expect(ready.transition?.event == (role == .agent
        ? .agentReady
        : .menuAppReady))
    let after = await product.lifecycle.currentState()
    #expect(role == .agent ? after.agent == .ready : after.menuApp == .ready)
    #expect(await product.starter.recordedRequests().isEmpty)
    #expect(await product.owner.observeReady(token).disposition == .duplicate)
}

@Test func replacementGenerationFencesOldReadyObservation() async throws {
    let product = processObservationOwnerV1()
    let first = try #require(await product.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    ).token)
    let second = try #require(await product.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    ).token)
    #expect(await product.owner.observeReady(first).disposition == .ignoredStale)
    #expect(await product.owner.observeReady(second).disposition == .accepted)
}

@Test func replacingReadyGenerationTearsDownBeforeNewReady() async throws {
    let product = processObservationOwnerV1()
    let first = try #require(await product.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    ).token)
    #expect(await product.owner.observeReady(first).disposition == .accepted)

    let replacement = await product.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    )
    #expect(replacement.disposition == .accepted)
    #expect(replacement.transition?.event == .menuAppExited)
    #expect((await product.lifecycle.currentState()).menuApp == .starting)
    #expect(await product.starter.recordedRequests().isEmpty)
    let token = try #require(replacement.token)
    #expect(await product.owner.observeReady(token).disposition == .accepted)
}

@Test(arguments: [AgentLoginRoleV1.agent, .menuApp])
func exactTerminationRequestsOnlyMatchingRecovery(
    role: AgentLoginRoleV1
) async throws {
    let product = processObservationOwnerV1()
    let token = try #require(await product.owner.activateObservation(
        role: role,
        generation: UUID()
    ).token)
    _ = await product.owner.observeReady(token)
    let termination = await product.owner.observeTermination(token)
    #expect(termination.disposition == .accepted)
    #expect(termination.transition?.event == (role == .agent
        ? .agentExited
        : .menuAppExited))
    #expect(await product.starter.recordedRequests() == [[role == .agent
        ? .requestAgentRecovery
        : .requestMenuRecovery]])
}

@Test func staleTerminationCannotEndOrRestartCurrentGeneration()
    async throws
{
    let product = processObservationOwnerV1()
    let first = try #require(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).token)
    let second = try #require(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).token)
    #expect(await product.owner.observeTermination(first).disposition == .ignoredStale)
    #expect(await product.lifecycle.recordedEvents().isEmpty)
    #expect(await product.starter.recordedRequests().isEmpty)
    #expect(await product.owner.observeReady(second).disposition == .accepted)
}

@Test(arguments: [
    MacAgentDashboardEffectOutcomeV0.notCompleted,
    .outcomeUnknown,
])
func recoveryFailureRemainsClosedAndTruthful(
    outcome: MacAgentDashboardEffectOutcomeV0
) async throws {
    let product = processObservationOwnerV1(outcome: outcome)
    let token = try #require(await product.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    ).token)
    let result = await product.owner.observeTermination(token)
    #expect(result.disposition == (outcome == .notCompleted
        ? .recoveryNotCompleted
        : .recoveryOutcomeUnknown))
    #expect((await product.lifecycle.currentState()).menuApp == .starting)
}

@Test func disableEnableEpochRejectsPreDisableGeneration() async throws {
    let product = processObservationOwnerV1()
    let token = try #require(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).token)
    _ = try await product.lifecycle.apply(
        .disableRequested,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 1
    )
    _ = try await product.lifecycle.apply(
        .enableRequested,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 2
    )
    #expect(await product.owner.observeReady(token).disposition == .ignoredStale)
    #expect((await product.lifecycle.currentState()).agent == .starting)
}

@Test func lockUnlockDoesNotInvalidatePendingProcessGeneration()
    async throws
{
    let product = processObservationOwnerV1()
    let token = try #require(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).token)
    _ = try await product.lifecycle.apply(
        .userLocked,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 1
    )
    _ = try await product.lifecycle.apply(
        .userUnlocked,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 2
    )
    #expect(await product.owner.observeReady(token).disposition == .accepted)
}

@Test func disabledAndLoggedOutStatesRejectObservationActivation() async {
    let disabled = processObservationOwnerV1(
        state: processObservationStateV1(
            agent: .stopped,
            menu: .stopped,
            enabled: false
        )
    )
    #expect(await disabled.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).disposition == .notEligible)

    let loggedOut = processObservationOwnerV1(
        state: processObservationStateV1(
            agent: .stopped,
            menu: .stopped,
            console: .loggedOut
        )
    )
    #expect(await loggedOut.owner.activateObservation(
        role: .menuApp,
        generation: UUID()
    ).disposition == .notEligible)
}

@Test func unsafeObservationClockMutatesNothing() async {
    let product = processObservationOwnerV1(clock: -1)
    #expect(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).disposition == .notEligible)
    #expect(await product.lifecycle.recordedEvents().isEmpty)
}

@Test func processObservationSerializesAcrossSuspendedRecovery()
    async throws
{
    let gate = ProcessObservationGateV1()
    let product = processObservationOwnerV1(gate: gate)
    let token = try #require(await product.owner.activateObservation(
        role: .agent,
        generation: UUID()
    ).token)
    let termination = Task {
        await product.owner.observeTermination(token)
    }
    await gate.waitUntilEntered()
    let replacement = Task {
        await product.owner.activateObservation(
            role: .agent,
            generation: UUID()
        )
    }
    await gate.release()
    #expect(await termination.value.disposition == .accepted)
    #expect(await replacement.value.disposition == .accepted)
}

private func agentObservationRootV1(
    state: ProductLifecycleState = processObservationStateV1(),
    starter: ProcessObservationStarterV1? = nil,
    recoveryRetryDelaysNanoseconds: [UInt64] = [1, 2, 3],
    recoverySleep: @escaping @Sendable (UInt64) async throws -> Void = { _ in }
) async throws -> (
    root: MacAgentLifecycleObservationRootV1,
    lifecycle: ProcessObservationLifecycleV1,
    starter: ProcessObservationStarterV1
) {
    let lifecycle = ProcessObservationLifecycleV1(state: state)
    let actualStarter = starter ?? ProcessObservationStarterV1()
    let root = try await MacAgentLifecycleObservationRootV1
        .afterAgentBootstrap(
            lifecycle: lifecycle,
            processStarter: actualStarter,
            agentGeneration: UUID(
                uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            )!,
            wallClock: ProcessObservationClockV1(
                value: 1_787_198_400_000
            ),
            transitionIDSource: {
                UUID(
                    uuidString: "12345678-1234-4234-8234-1234567890ab"
                )!
            },
            recoveryRetryDelaysNanoseconds: recoveryRetryDelaysNanoseconds,
            recoverySleep: recoverySleep
        )
    return (root, lifecycle, actualStarter)
}

@Test func completeAgentBootstrapIsTheAgentReadySource() async throws {
    let product = try await agentObservationRootV1()
    let state = await product.lifecycle.currentState()
    #expect(state.agent == .ready)
    #expect(state.menuApp == .starting)
    #expect(await product.lifecycle.recordedEvents() == [.agentReady])
    #expect(await product.starter.recordedRequests().isEmpty)
}

@Test func authenticatedMenuConnectionDoesNotClaimReadyUntilPublished()
    async throws
{
    let product = try await agentObservationRootV1()
    let connection = try await product.root
        .makeAuthenticatedMenuConnection(generation: UUID())
    #expect((await product.lifecycle.currentState()).menuApp == .starting)
    #expect(await connection.publishReady().disposition == .accepted)
    #expect((await product.lifecycle.currentState()).menuApp == .ready)
}

@Test func authenticatedMenuInvalidationRequestsRecoveryAndReplaysReceipt()
    async throws
{
    let product = try await agentObservationRootV1()
    let connection = try await product.root
        .makeAuthenticatedMenuConnection(generation: UUID())
    _ = await connection.publishReady()
    let first = await connection.invalidate()
    let replay = await connection.invalidate()
    #expect(first == replay)
    #expect(first.disposition == .accepted)
    #expect(first.transition?.event == .menuAppExited)
    #expect(await product.starter.recordedRequests() == [[
        .requestMenuRecovery,
    ]])
    #expect(await connection.publishReady().disposition == .ignoredStale)
}

@Test func replacementMenuConnectionFencesOldConnectionCallbacks()
    async throws
{
    let product = try await agentObservationRootV1()
    let old = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    _ = await old.publishReady()
    let replacement = try await product.root
        .makeAuthenticatedMenuConnection(generation: UUID())
    #expect(await old.publishReady().disposition == .ignoredStale)
    #expect(await old.invalidate().disposition == .ignoredStale)
    #expect(await product.starter.recordedRequests().isEmpty)
    #expect(await replacement.publishReady().disposition == .accepted)
}

@Test func duplicateMenuGenerationCannotCreateTwoConnectionOwners()
    async throws
{
    let product = try await agentObservationRootV1()
    let generation = UUID()
    _ = try await product.root.makeAuthenticatedMenuConnection(
        generation: generation
    )
    await #expect(
        throws: MacAgentLifecycleObservationRootErrorV1
            .menuConnectionRejected(.duplicate)
    ) {
        _ = try await product.root.makeAuthenticatedMenuConnection(
            generation: generation
        )
    }
}

@Test func concurrentMenuInvalidationsSerializeAndReplayExactResult()
    async throws
{
    let gate = ProcessObservationGateV1()
    let starter = ProcessObservationStarterV1(gate: gate)
    let product = try await agentObservationRootV1(starter: starter)
    let connection = try await product.root
        .makeAuthenticatedMenuConnection(generation: UUID())
    let first = Task { await connection.invalidate() }
    await gate.waitUntilEntered()
    let second = Task { await connection.invalidate() }
    await gate.release()
    let firstResult = await first.value
    let secondResult = await second.value
    #expect(firstResult == secondResult)
    #expect(await product.starter.recordedRequests().count == 1)
}

@Test func agentObservationRootRejectsDisabledBootstrapState() async {
    let state = processObservationStateV1(
        agent: .stopped,
        menu: .stopped,
        enabled: false
    )
    await #expect(
        throws: MacAgentLifecycleObservationRootErrorV1
            .agentBootstrapRejected(.notEligible)
    ) {
        _ = try await agentObservationRootV1(state: state)
    }
}

@Test func alreadyReadyAgentIsRetiredBeforeFreshBootstrapReady()
    async throws
{
    let product = try await agentObservationRootV1(
        state: processObservationStateV1(agent: .ready)
    )
    #expect(await product.lifecycle.recordedEvents() == [
        .agentExited,
        .agentReady,
    ])
    #expect((await product.lifecycle.currentState()).agent == .ready)
    #expect(await product.starter.recordedRequests().isEmpty)
}

@Test func menuRecoveryRetriesBoundedlyUntilStartCompletes() async throws {
    let starter = ProcessObservationStarterV1(outcomes: [
        .notCompleted,
        .outcomeUnknown,
        .completed,
    ])
    let sleeper = ProcessRecoverySleepRecorderV1()
    let product = try await agentObservationRootV1(
        starter: starter,
        recoveryRetryDelaysNanoseconds: [11, 22, 33],
        recoverySleep: { await sleeper.sleep($0) }
    )
    let connection = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    let terminal = await connection.invalidate()
    #expect(terminal.disposition == .recoveryNotCompleted)
    await connection.waitForScheduledRecovery()
    #expect(await starter.recordedRequests() == [
        [.requestMenuRecovery],
        [.requestMenuRecovery],
        [.requestMenuRecovery],
    ])
    #expect(await sleeper.recordedDelays() == [11, 22])
    #expect(await connection.invalidate() == terminal)
}

@Test func menuRecoveryStopsAfterThreeFailedRetries() async throws {
    let starter = ProcessObservationStarterV1(outcome: .outcomeUnknown)
    let sleeper = ProcessRecoverySleepRecorderV1()
    let product = try await agentObservationRootV1(
        starter: starter,
        recoveryRetryDelaysNanoseconds: [11, 22, 33],
        recoverySleep: { await sleeper.sleep($0) }
    )
    let connection = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    #expect(await connection.invalidate().disposition == .recoveryOutcomeUnknown)
    await connection.waitForScheduledRecovery()
    #expect(await starter.recordedRequests().count == 4)
    #expect(await sleeper.recordedDelays() == [11, 22, 33])
}

@Test func replacementConnectionFencesSleepingRecoveryRetry() async throws {
    let starter = ProcessObservationStarterV1(outcomes: [
        .notCompleted,
        .completed,
    ])
    let sleeper = ProcessRecoverySleepGateV1()
    let product = try await agentObservationRootV1(
        starter: starter,
        recoveryRetryDelaysNanoseconds: [1],
        recoverySleep: { try await sleeper.sleep($0) }
    )
    let old = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    #expect(await old.invalidate().disposition == .recoveryNotCompleted)
    await sleeper.waitUntilEntered()
    let replacement = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    await sleeper.release()
    await old.waitForScheduledRecovery()
    #expect(await starter.recordedRequests().count == 1)
    #expect(await replacement.publishReady().disposition == .accepted)
}

@Test func lifecycleRevisionChangeFencesSleepingRecoveryRetry() async throws {
    let starter = ProcessObservationStarterV1(outcomes: [
        .notCompleted,
        .completed,
    ])
    let sleeper = ProcessRecoverySleepGateV1()
    let product = try await agentObservationRootV1(
        starter: starter,
        recoveryRetryDelaysNanoseconds: [1],
        recoverySleep: { try await sleeper.sleep($0) }
    )
    let connection = try await product.root.makeAuthenticatedMenuConnection(
        generation: UUID()
    )
    #expect(await connection.invalidate().disposition == .recoveryNotCompleted)
    await sleeper.waitUntilEntered()
    _ = try await product.lifecycle.apply(
        .disableRequested,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 1
    )
    await sleeper.release()
    await connection.waitForScheduledRecovery()
    #expect(await starter.recordedRequests().count == 1)
    #expect((await product.lifecycle.currentState()).desiredEnabled == false)
}
