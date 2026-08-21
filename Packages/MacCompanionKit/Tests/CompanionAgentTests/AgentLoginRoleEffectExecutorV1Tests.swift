import CompanionAgent
import CompanionLifecycle
import Foundation
import Testing

private enum LoginRoleTestError: Error {
    case injected
}

private actor LoginRoleEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor LoginRoleTestGate {
    private var entered = false
    private var opened = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var openContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let enteredContinuations = self.enteredContinuations
        self.enteredContinuations.removeAll()
        for continuation in enteredContinuations {
            continuation.resume()
        }
        guard !opened else { return }
        await withCheckedContinuation { continuation in
            openContinuations.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func open() {
        opened = true
        let openContinuations = self.openContinuations
        self.openContinuations.removeAll()
        for continuation in openContinuations {
            continuation.resume()
        }
    }
}

private actor RecordingLoginRoleService:
    AgentLoginRoleServiceV1
{
    let role: AgentLoginRoleV1
    let recorder: LoginRoleEventRecorder
    let failingMutations: Set<AgentLoginRoleMutationV1>
    let registerGate: LoginRoleTestGate?

    init(
        role: AgentLoginRoleV1,
        recorder: LoginRoleEventRecorder,
        failingMutations: Set<AgentLoginRoleMutationV1> = [],
        registerGate: LoginRoleTestGate? = nil
    ) {
        self.role = role
        self.recorder = recorder
        self.failingMutations = failingMutations
        self.registerGate = registerGate
    }

    func register() async throws {
        await recorder.append("\(role.rawValue).register")
        if let registerGate {
            await registerGate.wait()
        }
        guard !failingMutations.contains(.register) else {
            throw LoginRoleTestError.injected
        }
    }

    func unregister() async throws {
        await recorder.append("\(role.rawValue).unregister")
        guard !failingMutations.contains(.unregister) else {
            throw LoginRoleTestError.injected
        }
    }
}

private func loginRoleTransition(
    before: ProductLifecycleState,
    event: ProductLifecycleEvent,
    transitionID: UUID = UUID()
) throws -> CompletedLifecycleTransitionV0 {
    var after = before
    let effects = try after.apply(event)
    return try CompletedLifecycleTransitionV0(
        transitionID: transitionID,
        observedAtUnixMilliseconds: 1,
        before: before,
        event: event,
        after: after,
        effects: effects
    )
}

private func loginRoleExecutor(
    recorder: LoginRoleEventRecorder,
    agentFailures: Set<AgentLoginRoleMutationV1> = [],
    menuFailures: Set<AgentLoginRoleMutationV1> = [],
    agentRegisterGate: LoginRoleTestGate? = nil
) -> AgentLoginRoleEffectExecutorV1 {
    AgentLoginRoleEffectExecutorV1(
        agent: RecordingLoginRoleService(
            role: .agent,
            recorder: recorder,
            failingMutations: agentFailures,
            registerGate: agentRegisterGate
        ),
        menuApp: RecordingLoginRoleService(
            role: .menuApp,
            recorder: recorder,
            failingMutations: menuFailures
        )
    )
}

@Test func loginRoleEnableRegistersBothBeforeReturningStartEffects() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(recorder: recorder)
    let transitionID = UUID()
    let transition = try loginRoleTransition(
        before: ProductLifecycleState(consoleSession: .active),
        event: .enableRequested,
        transitionID: transitionID
    )

    let receipt = try await executor.registerForEnablement(transition)

    #expect(await recorder.snapshot() == [
        "agent.register",
        "menuApp.register",
    ])
    #expect(receipt == AgentLoginRoleEffectReceiptV1(
        transitionID: transitionID,
        completedRegistrationEffects: [
            .registerAgentLogin,
            .registerMenuLogin,
        ],
        remainingProcessEffects: [
            .requestAgentStart,
            .requestMenuStart,
        ]
    ))
}

@Test func loginRoleAgentRegistrationFailureAttemptsLocalRollback() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(
        recorder: recorder,
        agentFailures: [.register]
    )
    let transition = try loginRoleTransition(
        before: ProductLifecycleState(consoleSession: .active),
        event: .enableRequested
    )

    await #expect(throws: AgentLoginRoleEffectExecutorErrorV1.registrationFailed(
        failed: AgentLoginRoleMutationFailureV1(
            role: .agent,
            mutation: .register
        ),
        rollbackFailures: []
    )) {
        _ = try await executor.registerForEnablement(transition)
    }
    #expect(await recorder.snapshot() == [
        "agent.register",
        "agent.unregister",
    ])
}

@Test func loginRoleMenuRegistrationFailureRollsBackInReverseOrder() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(
        recorder: recorder,
        menuFailures: [.register, .unregister]
    )
    let transition = try loginRoleTransition(
        before: ProductLifecycleState(consoleSession: .active),
        event: .enableRequested
    )

    await #expect(throws: AgentLoginRoleEffectExecutorErrorV1.registrationFailed(
        failed: AgentLoginRoleMutationFailureV1(
            role: .menuApp,
            mutation: .register
        ),
        rollbackFailures: [AgentLoginRoleMutationFailureV1(
            role: .menuApp,
            mutation: .unregister
        )]
    )) {
        _ = try await executor.registerForEnablement(transition)
    }
    #expect(await recorder.snapshot() == [
        "agent.register",
        "menuApp.register",
        "menuApp.unregister",
        "agent.unregister",
    ])
}

@Test func loginRoleDisableAttemptsBothUnregistrationsAfterFailure() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(
        recorder: recorder,
        agentFailures: [.unregister]
    )
    var enabled = ProductLifecycleState(consoleSession: .active)
    _ = try enabled.apply(.enableRequested)
    let transition = AgentRemoteLifecycleTransitionV1(
        completed: try loginRoleTransition(
            before: enabled,
            event: .disableRequested
        )
    )

    await #expect(throws: AgentLoginRoleEffectExecutorErrorV1.unregistrationFailed(
        failures: [AgentLoginRoleMutationFailureV1(
            role: .agent,
            mutation: .unregister
        )]
    )) {
        _ = try await executor.unregisterAfterRemoteSafety(transition)
    }
    #expect(await recorder.snapshot() == [
        "agent.unregister",
        "menuApp.unregister",
    ])
}

@Test func loginRoleDisableReturnsOnlyAfterBothUnregister() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(recorder: recorder)
    var enabled = ProductLifecycleState(consoleSession: .active)
    _ = try enabled.apply(.enableRequested)
    let transition = AgentRemoteLifecycleTransitionV1(
        completed: try loginRoleTransition(
            before: enabled,
            event: .disableRequested
        )
    )

    let receipt = try await executor.unregisterAfterRemoteSafety(transition)

    #expect(await recorder.snapshot() == [
        "agent.unregister",
        "menuApp.unregister",
    ])
    #expect(receipt.completedRegistrationEffects == [
        .unregisterAgentLogin,
        .unregisterMenuLogin,
    ])
    #expect(receipt.remainingProcessEffects.isEmpty)
}

@Test func loginRoleEnableRejectsANonEnableTransition() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(recorder: recorder)
    let transition = try loginRoleTransition(
        before: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .loggedOut
        ),
        event: .userLoggedIn
    )

    await #expect(
        throws: AgentLoginRoleEffectExecutorErrorV1
            .unsupportedTransition(.userLoggedIn)
    ) {
        _ = try await executor.registerForEnablement(transition)
    }
    #expect(await recorder.snapshot().isEmpty)
}

@Test func loginRoleDisableRejectsTransitionWithoutRemoteSafetyEffects() async throws {
    let recorder = LoginRoleEventRecorder()
    let executor = loginRoleExecutor(recorder: recorder)
    var ready = ProductLifecycleState(consoleSession: .active)
    _ = try ready.apply(.enableRequested)
    _ = try ready.apply(.menuAppReady)
    let transition = AgentRemoteLifecycleTransitionV1(
        completed: try loginRoleTransition(
            before: ready,
            event: .menuAppExited
        )
    )

    await #expect(
        throws: AgentLoginRoleEffectExecutorErrorV1
            .unsupportedTransition(.menuAppExited)
    ) {
        _ = try await executor.unregisterAfterRemoteSafety(transition)
    }
    #expect(await recorder.snapshot().isEmpty)
}

@Test func loginRoleExecutorRejectsReentrantTransition() async throws {
    let recorder = LoginRoleEventRecorder()
    let gate = LoginRoleTestGate()
    let executor = loginRoleExecutor(
        recorder: recorder,
        agentRegisterGate: gate
    )
    let first = try loginRoleTransition(
        before: ProductLifecycleState(consoleSession: .active),
        event: .enableRequested
    )
    let second = try loginRoleTransition(
        before: ProductLifecycleState(consoleSession: .active),
        event: .enableRequested
    )
    let task = Task {
        try await executor.registerForEnablement(first)
    }
    await gate.waitUntilEntered()

    await #expect(
        throws: AgentLoginRoleEffectExecutorErrorV1.transitionInProgress
    ) {
        _ = try await executor.registerForEnablement(second)
    }
    await gate.open()
    _ = try await task.value
}
