import CompanionAgent
import CompanionLifecycle
import Foundation
import Testing

private enum RawLoginRoleTestError: Error {
    case injected
}

private enum RawLoginRoleBehavior: Sendable {
    case converge
    case throwBeforeEffect
    case throwAfterEffect
    case returnWithoutEffect
}

private actor RawLoginRoleService:
    AgentLoginRoleRawServiceV1
{
    private var currentState: AgentLoginRoleRegistrationStateV1
    private let registerBehavior: RawLoginRoleBehavior
    private let unregisterBehavior: RawLoginRoleBehavior
    private var recordedEvents: [String] = []

    init(
        state: AgentLoginRoleRegistrationStateV1,
        registerBehavior: RawLoginRoleBehavior = .converge,
        unregisterBehavior: RawLoginRoleBehavior = .converge
    ) {
        currentState = state
        self.registerBehavior = registerBehavior
        self.unregisterBehavior = unregisterBehavior
    }

    func status() -> AgentLoginRoleRegistrationStateV1 {
        recordedEvents.append("status.\(currentState.rawValue)")
        return currentState
    }

    func register() throws {
        recordedEvents.append("register")
        switch registerBehavior {
        case .converge:
            currentState = .enabled
        case .throwBeforeEffect:
            throw RawLoginRoleTestError.injected
        case .throwAfterEffect:
            currentState = .enabled
            throw RawLoginRoleTestError.injected
        case .returnWithoutEffect:
            break
        }
    }

    func unregisterAndWait() throws {
        recordedEvents.append("unregisterAndWait")
        switch unregisterBehavior {
        case .converge:
            currentState = .notRegistered
        case .throwBeforeEffect:
            throw RawLoginRoleTestError.injected
        case .throwAfterEffect:
            currentState = .notRegistered
            throw RawLoginRoleTestError.injected
        case .returnWithoutEffect:
            break
        }
    }

    func events() -> [String] {
        recordedEvents
    }
}

@Test func convergingLoginRoleRegisterIsIdempotentWhenEnabled() async throws {
    let raw = RawLoginRoleService(state: .enabled)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.register()

    #expect(await raw.events() == ["status.enabled"])
}

@Test func convergingLoginRoleRegisterChecksEnabledPostcondition() async throws {
    let raw = RawLoginRoleService(state: .notRegistered)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.register()

    #expect(await raw.events() == [
        "status.notRegistered",
        "register",
        "status.enabled",
    ])
}

@Test func bootstrapAcquisitionDistinguishesPreexistingRegistration()
    async throws
{
    let raw = RawLoginRoleService(state: .enabled)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    #expect(
        try await service.acquireForBootstrap() == .alreadyRegistered
    )
    #expect(await raw.events() == ["status.enabled"])
}

@Test func bootstrapAcquisitionOwnsEffectThenErrorRegistration()
    async throws
{
    let raw = RawLoginRoleService(
        state: .notRegistered,
        registerBehavior: .throwAfterEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    #expect(
        try await service.acquireForBootstrap() == .newlyRegistered
    )
    #expect(await raw.events() == [
        "status.notRegistered",
        "register",
        "status.enabled",
    ])
}

@Test func convergingLoginRoleRegisterPreservesApprovalRecovery() async throws {
    let raw = RawLoginRoleService(state: .requiresApproval)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.requiresApproval) {
        try await service.register()
    }
    #expect(await raw.events() == ["status.requiresApproval"])
}

@Test func convergingLoginRoleRegisterAcquiresMissingFirstRunRecord()
    async throws
{
    let raw = RawLoginRoleService(state: .notFound)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    #expect(
        try await service.acquireForBootstrap() == .newlyRegistered
    )
    #expect(await raw.events() == [
        "status.notFound",
        "register",
        "status.enabled",
    ])
}

@Test func convergingLoginRoleRegisterRejectsMissingEmbeddedService()
    async throws
{
    let raw = RawLoginRoleService(
        state: .notFound,
        registerBehavior: .throwBeforeEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.platformFailure) {
        try await service.register()
    }
    #expect(await raw.events() == [
        "status.notFound",
        "register",
        "status.notFound",
    ])
}

@Test func convergingLoginRoleRegisterRejectsFutureStatus() async throws {
    let raw = RawLoginRoleService(state: .unknown)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.platformFailure) {
        try await service.register()
    }
    #expect(await raw.events() == ["status.unknown"])
}

@Test func convergingLoginRoleRegisterAcceptsEffectThenError() async throws {
    let raw = RawLoginRoleService(
        state: .notRegistered,
        registerBehavior: .throwAfterEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.register()

    #expect(await raw.events() == [
        "status.notRegistered",
        "register",
        "status.enabled",
    ])
}

@Test func convergingLoginRoleRegisterRejectsFalseSuccess() async throws {
    let raw = RawLoginRoleService(
        state: .notRegistered,
        registerBehavior: .returnWithoutEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.postconditionFailed(
        expected: .enabled,
        actual: .notRegistered
    )) {
        try await service.register()
    }
}

@Test func convergingLoginRoleUnregisterIsIdempotentWhenAbsent() async throws {
    let raw = RawLoginRoleService(state: .notRegistered)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.unregister()

    #expect(await raw.events() == ["status.notRegistered"])
}

@Test func convergingLoginRoleUnregisterRejectsFutureStatus() async throws {
    let raw = RawLoginRoleService(state: .unknown)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.platformFailure) {
        try await service.unregister()
    }
    #expect(await raw.events() == ["status.unknown"])
}

@Test func convergingLoginRoleUnregisterRemovesApprovalBlockedRole() async throws {
    let raw = RawLoginRoleService(state: .requiresApproval)
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.unregister()

    #expect(await raw.events() == [
        "status.requiresApproval",
        "unregisterAndWait",
        "status.notRegistered",
    ])
}

@Test func convergingLoginRoleUnregisterAcceptsEffectThenError() async throws {
    let raw = RawLoginRoleService(
        state: .enabled,
        unregisterBehavior: .throwAfterEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    try await service.unregister()

    #expect(await raw.events() == [
        "status.enabled",
        "unregisterAndWait",
        "status.notRegistered",
    ])
}

@Test func convergingLoginRoleUnregisterRejectsFalseSuccess() async throws {
    let raw = RawLoginRoleService(
        state: .enabled,
        unregisterBehavior: .returnWithoutEffect
    )
    let service = AgentLoginRoleConvergingServiceV1(raw: raw)

    await #expect(throws: AgentLoginRoleConvergenceErrorV1.postconditionFailed(
        expected: .notRegistered,
        actual: .enabled
    )) {
        try await service.unregister()
    }
}

@Test func loginRoleExecutorPreservesTypedApprovalFailure() async throws {
    let agentRaw = RawLoginRoleService(state: .requiresApproval)
    let menuRaw = RawLoginRoleService(state: .notRegistered)
    let executor = AgentLoginRoleEffectExecutorV1(
        agent: AgentLoginRoleConvergingServiceV1(raw: agentRaw),
        menuApp: AgentLoginRoleConvergingServiceV1(raw: menuRaw)
    )
    let before = ProductLifecycleState(consoleSession: .active)
    var after = before
    let effects = try after.apply(.enableRequested)
    let transition = try CompletedLifecycleTransitionV0(
        transitionID: UUID(),
        observedAtUnixMilliseconds: 1,
        before: before,
        event: .enableRequested,
        after: after,
        effects: effects
    )

    await #expect(throws: AgentLoginRoleEffectExecutorErrorV1.registrationFailed(
        failed: AgentLoginRoleMutationFailureV1(
            role: .agent,
            mutation: .register,
            reason: .requiresApproval
        ),
        rollbackFailures: []
    )) {
        _ = try await executor.registerForEnablement(transition)
    }
    #expect(await agentRaw.events() == [
        "status.requiresApproval",
        "status.requiresApproval",
        "unregisterAndWait",
        "status.notRegistered",
    ])
    #expect(await menuRaw.events().isEmpty)
}
