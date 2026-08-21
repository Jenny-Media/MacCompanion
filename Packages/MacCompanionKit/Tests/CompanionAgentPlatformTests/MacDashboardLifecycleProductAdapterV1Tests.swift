import CompanionAgent
import CompanionAgentPlatform
import CompanionDomain
import CompanionLifecycle
import CompanionMacApp
import Foundation
import Testing

private enum DashboardLifecycleProductTestErrorV1: Error {
    case injected
    case stale
}

private actor DashboardLifecycleEventRecorderV1 {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private enum DashboardLifecycleCommitBehaviorV1: Sendable {
    case succeed
    case failPreservingState
    case failAfterEnabling
}

private actor DashboardLifecycleRemoteV1:
    AgentRemoteLifecycleCommandingV1
{
    private var state: ProductLifecycleState
    private let behavior: DashboardLifecycleCommitBehaviorV1
    private let recorder: DashboardLifecycleEventRecorderV1
    private var commits = 0
    private var revision: UInt64 = 0

    init(
        state: ProductLifecycleState,
        behavior: DashboardLifecycleCommitBehaviorV1 = .succeed,
        recorder: DashboardLifecycleEventRecorderV1
    ) {
        self.state = state
        self.behavior = behavior
        self.recorder = recorder
    }

    func currentState() -> ProductLifecycleState { state }
    func currentSnapshot() -> AgentRemoteLifecycleSnapshotV1 {
        AgentRemoteLifecycleSnapshotV1(revision: revision, state: state)
    }
    func commitCount() -> Int { commits }

    func prepare(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async throws -> AgentRemoteLifecyclePreparedTransitionV1 {
        await recorder.append("remote.prepare")
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
    ) async throws -> AgentRemoteLifecycleTransitionV1 {
        commits += 1
        await recorder.append("remote.commit")
        switch behavior {
        case .succeed:
            guard transition.baseRevision == revision,
                  transition.completed.before == state else {
                throw DashboardLifecycleProductTestErrorV1.stale
            }
            revision += 1
            state = transition.completed.after
            return AgentRemoteLifecycleTransitionV1(
                completed: transition.completed
            )
        case .failPreservingState:
            throw DashboardLifecycleProductTestErrorV1.injected
        case .failAfterEnabling:
            revision += 1
            state = transition.completed.after
            throw DashboardLifecycleProductTestErrorV1.injected
        }
    }

    func apply(
        _ event: ProductLifecycleEvent,
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async throws -> AgentRemoteLifecycleTransitionV1 {
        let prepared = try await prepare(
            event,
            transitionID: transitionID,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        )
        return try await commitPrepared(prepared)
    }
}

private actor DashboardLifecycleLoginServiceV1: AgentLoginRoleServiceV1 {
    private let name: String
    private let recorder: DashboardLifecycleEventRecorderV1
    private let registerFails: Bool
    private let unregisterFails: Bool
    private let registerGate: DashboardLifecycleGateV1?

    init(
        name: String,
        recorder: DashboardLifecycleEventRecorderV1,
        registerFails: Bool = false,
        unregisterFails: Bool = false,
        registerGate: DashboardLifecycleGateV1? = nil
    ) {
        self.name = name
        self.recorder = recorder
        self.registerFails = registerFails
        self.unregisterFails = unregisterFails
        self.registerGate = registerGate
    }

    func register() async throws {
        await recorder.append("\(name).register")
        if let registerGate { await registerGate.wait() }
        if registerFails { throw DashboardLifecycleProductTestErrorV1.injected }
    }

    func unregister() async throws {
        await recorder.append("\(name).unregister")
        if unregisterFails { throw DashboardLifecycleProductTestErrorV1.injected }
    }
}

private actor DashboardLifecycleGateV1 {
    private var entered = false
    private var open = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let enteredWaiters = self.enteredWaiters
        self.enteredWaiters.removeAll()
        for waiter in enteredWaiters { waiter.resume() }
        guard !open else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        open = true
        let openWaiters = self.openWaiters
        self.openWaiters.removeAll()
        for waiter in openWaiters { waiter.resume() }
    }
}

private actor DashboardLifecycleProcessStarterV1:
    MacDashboardLifecycleProcessStartingV1
{
    private let recorder: DashboardLifecycleEventRecorderV1
    private var outcome: MacAgentDashboardEffectOutcomeV0
    private var values: [[ProductLifecycleEffect]] = []

    init(
        recorder: DashboardLifecycleEventRecorderV1,
        outcome: MacAgentDashboardEffectOutcomeV0 = .completed
    ) {
        self.recorder = recorder
        self.outcome = outcome
    }

    func requests() -> [[ProductLifecycleEffect]] { values }

    func requestStarts(
        _ effects: [ProductLifecycleEffect]
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        values.append(effects)
        await recorder.append("process.start")
        return outcome
    }
}

private actor DashboardLifecycleIntentStoreV1:
    MacRemoteAccessIntentPersistenceV1
{
    private var value: MacRemoteAccessIntentSnapshotV1?
    private let recorder: DashboardLifecycleEventRecorderV1

    init(
        value: MacRemoteAccessIntentSnapshotV1? = nil,
        recorder: DashboardLifecycleEventRecorderV1
    ) {
        self.value = value
        self.recorder = recorder
    }

    func current() -> MacRemoteAccessIntentSnapshotV1? { value }

    func replaceAtomically(
        _ snapshot: MacRemoteAccessIntentSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> MacRemoteAccessIntentCommitResultV1 {
        await recorder.append("intent.replace")
        if value == snapshot { return .alreadyPresentExactSnapshot }
        guard value?.revision == expectedRevision,
              snapshot.revision == (value?.revision ?? 0) + 1 else {
            throw MacRemoteAccessIntentStoreErrorV1.revisionConflict
        }
        let result: MacRemoteAccessIntentCommitResultV1 = value == nil
            ? .inserted
            : .replaced
        value = snapshot
        return result
    }
}

private struct DashboardLifecycleClockV1:
    MacDashboardLifecycleWallClockV1
{
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private func dashboardEnabledLifecycleStateV1() throws
    -> ProductLifecycleState
{
    var state = ProductLifecycleState(consoleSession: .active)
    _ = try state.apply(.enableRequested)
    return state
}

private func dashboardLifecycleProductV1(
    state: ProductLifecycleState = .init(consoleSession: .active),
    commitBehavior: DashboardLifecycleCommitBehaviorV1 = .succeed,
    agentRegisterFails: Bool = false,
    menuRegisterFails: Bool = false,
    agentUnregisterFails: Bool = false,
    menuUnregisterFails: Bool = false,
    processOutcome: MacAgentDashboardEffectOutcomeV0 = .completed,
    clock: Int64 = 1_787_198_400_000,
    registerGate: DashboardLifecycleGateV1? = nil,
    intentSnapshot: MacRemoteAccessIntentSnapshotV1? = nil
) -> (
    adapter: MacDashboardLifecycleProductAdapterV1,
    remote: DashboardLifecycleRemoteV1,
    process: DashboardLifecycleProcessStarterV1,
    intent: DashboardLifecycleIntentStoreV1,
    recorder: DashboardLifecycleEventRecorderV1
) {
    let recorder = DashboardLifecycleEventRecorderV1()
    let remote = DashboardLifecycleRemoteV1(
        state: state,
        behavior: commitBehavior,
        recorder: recorder
    )
    let process = DashboardLifecycleProcessStarterV1(
        recorder: recorder,
        outcome: processOutcome
    )
    let intent = DashboardLifecycleIntentStoreV1(
        value: intentSnapshot,
        recorder: recorder
    )
    let roles = AgentLoginRoleEffectExecutorV1(
        agent: DashboardLifecycleLoginServiceV1(
            name: "agent",
            recorder: recorder,
            registerFails: agentRegisterFails,
            unregisterFails: agentUnregisterFails,
            registerGate: registerGate
        ),
        menuApp: DashboardLifecycleLoginServiceV1(
            name: "menu",
            recorder: recorder,
            registerFails: menuRegisterFails,
            unregisterFails: menuUnregisterFails
        )
    )
    return (
        MacDashboardLifecycleProductAdapterV1(
            lifecycle: remote,
            loginRoles: roles,
            processStarter: process,
            intentStore: intent,
            wallClock: DashboardLifecycleClockV1(value: clock),
            transitionIDSource: { UUID(uuidString: "12345678-1234-4234-8234-1234567890ab")! }
        ),
        remote,
        process,
        intent,
        recorder
    )
}

@Test func dashboardEnableRegistersCommitsThenRequestsProcessStarts()
    async throws
{
    let product = dashboardLifecycleProductV1()
    #expect(await product.adapter.setEnabled(true) == .completed)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "agent.register",
        "menu.register",
        "remote.commit",
        "process.start",
    ])
    #expect(await product.remote.currentState().desiredEnabled)
    #expect(await product.process.requests() == [[
        .requestAgentStart,
        .requestMenuStart,
    ]])
}

@Test func dashboardEnableRegistrationFailureRollsBackWithoutCommit()
    async throws
{
    let product = dashboardLifecycleProductV1(menuRegisterFails: true)
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "agent.register",
        "menu.register",
        "menu.unregister",
        "agent.unregister",
    ])
    #expect(await product.remote.commitCount() == 0)
    #expect(!(await product.remote.currentState().desiredEnabled))
}

@Test func dashboardEnableRollbackFailureRemainsOutcomeUnknown()
    async throws
{
    let product = dashboardLifecycleProductV1(
        menuRegisterFails: true,
        menuUnregisterFails: true
    )
    #expect(await product.adapter.setEnabled(true) == .outcomeUnknown)
    #expect(await product.remote.commitCount() == 0)
    #expect(!(await product.remote.currentState().desiredEnabled))
}

@Test func staleEnableCommitCompensatesWhileStateRemainsDisabled()
    async throws
{
    let product = dashboardLifecycleProductV1(
        commitBehavior: .failPreservingState
    )
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "agent.register",
        "menu.register",
        "remote.commit",
        "agent.unregister",
        "menu.unregister",
    ])
    #expect(!(await product.remote.currentState().desiredEnabled))
    #expect(await product.process.requests().isEmpty)
}

@Test func failedCommitCannotUnregisterRolesOwnedByAnotherEnable()
    async throws
{
    let product = dashboardLifecycleProductV1(
        commitBehavior: .failAfterEnabling
    )
    #expect(await product.adapter.setEnabled(true) == .outcomeUnknown)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "agent.register",
        "menu.register",
        "remote.commit",
    ])
    #expect(await product.remote.currentState().desiredEnabled)
}

@Test func dashboardDisableCommitsRemoteSafetyBeforeUnregistration()
    async throws
{
    let product = dashboardLifecycleProductV1(
        state: try dashboardEnabledLifecycleStateV1()
    )
    #expect(await product.adapter.setEnabled(false) == .completed)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "remote.commit",
        "agent.unregister",
        "menu.unregister",
    ])
    #expect(!(await product.remote.currentState().desiredEnabled))
    #expect(await product.process.requests().isEmpty)
}

@Test func dashboardDisableCleanupFailurePreservesKnownSafeOffState()
    async throws
{
    let product = dashboardLifecycleProductV1(
        state: try dashboardEnabledLifecycleStateV1(),
        agentUnregisterFails: true
    )
    #expect(await product.adapter.setEnabled(false) == .notCompleted)
    #expect(!(await product.remote.currentState().desiredEnabled))
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "remote.prepare",
        "remote.commit",
        "agent.unregister",
        "menu.unregister",
    ])
}

@Test func processStartFailureKeepsCommittedEnabledIntentTruthful()
    async throws
{
    let product = dashboardLifecycleProductV1(
        processOutcome: .notCompleted
    )
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.remote.currentState().desiredEnabled)
    #expect(await product.process.requests().count == 1)
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.process.requests().count == 2)
}

@Test func alreadyEnabledCommandConvergesRolesAndRetriesProcessStarts()
    async throws
{
    let product = dashboardLifecycleProductV1(
        state: try dashboardEnabledLifecycleStateV1()
    )
    #expect(await product.adapter.setEnabled(true) == .completed)
    #expect(await product.remote.commitCount() == 0)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "agent.register",
        "menu.register",
        "process.start",
    ])
}

@Test func alreadyDisabledCommandConvergesBothRolesAbsent() async throws {
    let product = dashboardLifecycleProductV1()
    #expect(await product.adapter.setEnabled(false) == .completed)
    #expect(await product.remote.commitCount() == 0)
    #expect(await product.recorder.snapshot() == [
        "intent.replace",
        "agent.unregister",
        "menu.unregister",
    ])
}

@Test func lifecycleProductRejectsUnsafeClockBeforeRegistration()
    async throws
{
    let unsafe = Int64(
        MonotonicRevision<AuthorizationEpochTag>.maximumWireValue + 1
    )
    let product = dashboardLifecycleProductV1(clock: unsafe)
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.remote.commitCount() == 0)
    #expect(await product.recorder.snapshot().isEmpty)
}

@Test func lifecycleProductSerializesReentrantCommands() async throws {
    let gate = DashboardLifecycleGateV1()
    let product = dashboardLifecycleProductV1(registerGate: gate)
    let first = Task { await product.adapter.setEnabled(true) }
    await gate.waitUntilEntered()
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    await gate.release()
    #expect(await first.value == .completed)
    #expect(await product.remote.commitCount() == 1)
}

@Test func restartReconciliationConvergesPersistedEnablement() async throws {
    let product = dashboardLifecycleProductV1(
        intentSnapshot: try remoteIntentSnapshotForDashboardV1(enabled: true)
    )
    #expect(await product.adapter.reconcileAfterRestart() == .completed)
    #expect(await product.remote.currentState().desiredEnabled)
    #expect(await product.recorder.snapshot() == [
        "remote.prepare",
        "agent.register",
        "menu.register",
        "remote.commit",
        "process.start",
    ])
}

@Test func restartReconciliationConvergesPersistedDisablement() async throws {
    let product = dashboardLifecycleProductV1(
        state: try dashboardEnabledLifecycleStateV1(),
        intentSnapshot: try remoteIntentSnapshotForDashboardV1(enabled: false)
    )
    #expect(await product.adapter.reconcileAfterRestart() == .completed)
    #expect(!(await product.remote.currentState().desiredEnabled))
    #expect(await product.recorder.snapshot() == [
        "remote.prepare",
        "remote.commit",
        "agent.unregister",
        "menu.unregister",
    ])
}

@Test func restartReconciliationDefaultsMissingIntentToDisabled()
    async throws
{
    let product = dashboardLifecycleProductV1(
        state: try dashboardEnabledLifecycleStateV1()
    )
    #expect(await product.adapter.reconcileAfterRestart() == .completed)
    #expect(!(await product.remote.currentState().desiredEnabled))
    #expect(await product.recorder.snapshot().first == "remote.prepare")
}

@Test func restartOfEnabledLoggedOutStateRegistersWithoutStarting()
    async throws
{
    let state = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .loggedOut
    )
    let product = dashboardLifecycleProductV1(
        state: state,
        intentSnapshot: try remoteIntentSnapshotForDashboardV1(enabled: true)
    )
    #expect(await product.adapter.reconcileAfterRestart() == .completed)
    #expect(await product.recorder.snapshot() == [
        "agent.register",
        "menu.register",
    ])
    #expect(await product.process.requests().isEmpty)
}

@Test func registrationFailureKeepsDurableEnableIntentForRestart()
    async throws
{
    let product = dashboardLifecycleProductV1(menuRegisterFails: true)
    #expect(await product.adapter.setEnabled(true) == .notCompleted)
    #expect(await product.intent.current()?.desiredEnabled == true)
    #expect(!(await product.remote.currentState().desiredEnabled))
}

private func remoteIntentSnapshotForDashboardV1(
    enabled: Bool
) throws -> MacRemoteAccessIntentSnapshotV1 {
    try MacRemoteAccessIntentSnapshotV1(
        revision: 1,
        desiredEnabled: enabled,
        commandID: UUID(
            uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        )!,
        recordedAtUnixMilliseconds: 1_787_198_400_000
    )
}
