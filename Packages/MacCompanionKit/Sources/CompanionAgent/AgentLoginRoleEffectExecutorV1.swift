import CompanionLifecycle
import Foundation

public enum AgentLoginRoleV1: String, CaseIterable, Sendable {
    case agent
    case menuApp
}

public enum AgentLoginRoleMutationV1: String, CaseIterable, Sendable {
    case register
    case unregister
}

public enum AgentLoginRoleFailureReasonV1: String, CaseIterable, Sendable {
    case platformFailure
    case requiresApproval
    case serviceNotFound
    case postconditionFailed
}

/// An identity-neutral seam for the containing Mac app's two login roles.
/// The permanent target supplies adapters backed by its exact `SMAppService`
/// instances only after their identifiers and designated requirements freeze.
public protocol AgentLoginRoleServiceV1: Sendable {
    func register() async throws
    func unregister() async throws
}

public struct AgentLoginRoleMutationFailureV1: Equatable, Sendable {
    public let role: AgentLoginRoleV1
    public let mutation: AgentLoginRoleMutationV1
    public let reason: AgentLoginRoleFailureReasonV1

    public init(
        role: AgentLoginRoleV1,
        mutation: AgentLoginRoleMutationV1,
        reason: AgentLoginRoleFailureReasonV1 = .platformFailure
    ) {
        self.role = role
        self.mutation = mutation
        self.reason = reason
    }
}

public enum AgentLoginRoleEffectExecutorErrorV1:
    Error, Equatable, Sendable
{
    case transitionInProgress
    case unsupportedTransition(ProductLifecycleEvent)
    case registrationFailed(
        failed: AgentLoginRoleMutationFailureV1,
        rollbackFailures: [AgentLoginRoleMutationFailureV1]
    )
    case unregistrationFailed(
        failures: [AgentLoginRoleMutationFailureV1]
    )
}

public struct AgentLoginRoleEffectReceiptV1: Equatable, Sendable {
    public let transitionID: UUID
    public let completedRegistrationEffects: [ProductLifecycleEffect]
    public let remainingProcessEffects: [ProductLifecycleEffect]

    public init(
        transitionID: UUID,
        completedRegistrationEffects: [ProductLifecycleEffect],
        remainingProcessEffects: [ProductLifecycleEffect]
    ) {
        self.transitionID = transitionID
        self.completedRegistrationEffects = completedRegistrationEffects
        self.remainingProcessEffects = remainingProcessEffects
    }
}

/// Executes only the containing app's two login-registration roles.
/// Registration occurs before an enable transition may be committed and is an
/// all-or-rollback transaction in Agent-then-menu order. Unregistration accepts
/// only a transition returned after the Agent coordinator has completed remote
/// teardown, and always attempts both roles so one failure cannot suppress the
/// other safe cleanup. Process start remains explicit output because
/// registration does not itself prove process readiness.
public actor AgentLoginRoleEffectExecutorV1 {
    private let agent: any AgentLoginRoleServiceV1
    private let menuApp: any AgentLoginRoleServiceV1
    private var transitionInProgress = false

    public init(
        agent: any AgentLoginRoleServiceV1,
        menuApp: any AgentLoginRoleServiceV1
    ) {
        self.agent = agent
        self.menuApp = menuApp
    }

    public func registerForEnablement(
        _ transition: CompletedLifecycleTransitionV0
    ) async throws -> AgentLoginRoleEffectReceiptV1 {
        guard transition.event == .enableRequested,
              transition.effects == [
                  .registerAgentLogin,
                  .registerMenuLogin,
                  .requestAgentStart,
                  .requestMenuStart,
              ] else {
            throw AgentLoginRoleEffectExecutorErrorV1
                .unsupportedTransition(transition.event)
        }
        try beginTransition()
        defer { transitionInProgress = false }
        try await registerBoth()

        return AgentLoginRoleEffectReceiptV1(
            transitionID: transition.transitionID,
            completedRegistrationEffects: [
                .registerAgentLogin,
                .registerMenuLogin,
            ],
            remainingProcessEffects: [
                .requestAgentStart,
                .requestMenuStart,
            ]
        )
    }

    /// Idempotent repair path used only after the product owner has verified
    /// that authoritative desired state is already enabled.
    package func registerForCurrentEnabledState(
        transitionID: UUID
    ) async throws -> AgentLoginRoleEffectReceiptV1 {
        try beginTransition()
        defer { transitionInProgress = false }
        try await registerBoth()
        return AgentLoginRoleEffectReceiptV1(
            transitionID: transitionID,
            completedRegistrationEffects: [
                .registerAgentLogin,
                .registerMenuLogin,
            ],
            remainingProcessEffects: [
                .requestAgentStart,
                .requestMenuStart,
            ]
        )
    }

    public func unregisterAfterRemoteSafety(
        _ transition: AgentRemoteLifecycleTransitionV1
    ) async throws -> AgentLoginRoleEffectReceiptV1 {
        guard transition.completed.event == .disableRequested,
              transition.remainingPlatformEffects == [
                  .unregisterAgentLogin,
                  .unregisterMenuLogin,
              ] else {
            throw AgentLoginRoleEffectExecutorErrorV1
                .unsupportedTransition(transition.completed.event)
        }
        try beginTransition()
        defer { transitionInProgress = false }
        try await unregisterBoth()

        return AgentLoginRoleEffectReceiptV1(
            transitionID: transition.completed.transitionID,
            completedRegistrationEffects: [
                .unregisterAgentLogin,
                .unregisterMenuLogin,
            ],
            remainingProcessEffects: []
        )
    }

    /// Idempotent cleanup path used only after the product owner has verified
    /// that authoritative desired state is already disabled.
    package func unregisterForCurrentDisabledState(
        transitionID: UUID
    ) async throws -> AgentLoginRoleEffectReceiptV1 {
        try beginTransition()
        defer { transitionInProgress = false }
        try await unregisterBoth()
        return AgentLoginRoleEffectReceiptV1(
            transitionID: transitionID,
            completedRegistrationEffects: [
                .unregisterAgentLogin,
                .unregisterMenuLogin,
            ],
            remainingProcessEffects: []
        )
    }

    /// Compensates a fully registered enable preparation that could not be
    /// committed because the lifecycle state changed. This accepts only the
    /// exact prepared enable transition and always attempts both roles.
    package func unregisterAfterFailedEnablement(
        _ transition: CompletedLifecycleTransitionV0
    ) async throws -> AgentLoginRoleEffectReceiptV1 {
        guard transition.event == .enableRequested,
              transition.effects == [
                  .registerAgentLogin,
                  .registerMenuLogin,
                  .requestAgentStart,
                  .requestMenuStart,
              ] else {
            throw AgentLoginRoleEffectExecutorErrorV1
                .unsupportedTransition(transition.event)
        }
        try beginTransition()
        defer { transitionInProgress = false }
        try await unregisterBoth()
        return AgentLoginRoleEffectReceiptV1(
            transitionID: transition.transitionID,
            completedRegistrationEffects: [
                .unregisterAgentLogin,
                .unregisterMenuLogin,
            ],
            remainingProcessEffects: []
        )
    }

    private func beginTransition() throws {
        guard !transitionInProgress else {
            throw AgentLoginRoleEffectExecutorErrorV1.transitionInProgress
        }
        transitionInProgress = true
    }

    private func registerBoth() async throws {
        do {
            try await agent.register()
        } catch {
            let rollbackFailures = await rollback([
                (.agent, agent),
            ])
            throw AgentLoginRoleEffectExecutorErrorV1.registrationFailed(
                failed: AgentLoginRoleMutationFailureV1(
                    role: .agent,
                    mutation: .register,
                    reason: failureReason(error)
                ),
                rollbackFailures: rollbackFailures
            )
        }

        do {
            try await menuApp.register()
        } catch {
            let rollbackFailures = await rollback([
                (.menuApp, menuApp),
                (.agent, agent),
            ])
            throw AgentLoginRoleEffectExecutorErrorV1.registrationFailed(
                failed: AgentLoginRoleMutationFailureV1(
                    role: .menuApp,
                    mutation: .register,
                    reason: failureReason(error)
                ),
                rollbackFailures: rollbackFailures
            )
        }
    }

    private func unregisterBoth() async throws {
        var failures: [AgentLoginRoleMutationFailureV1] = []
        do {
            try await agent.unregister()
        } catch {
            failures.append(AgentLoginRoleMutationFailureV1(
                role: .agent,
                mutation: .unregister,
                reason: failureReason(error)
            ))
        }
        do {
            try await menuApp.unregister()
        } catch {
            failures.append(AgentLoginRoleMutationFailureV1(
                role: .menuApp,
                mutation: .unregister,
                reason: failureReason(error)
            ))
        }
        guard failures.isEmpty else {
            throw AgentLoginRoleEffectExecutorErrorV1.unregistrationFailed(
                failures: failures
            )
        }
    }

    private func rollback(
        _ roles: [(AgentLoginRoleV1, any AgentLoginRoleServiceV1)]
    ) async -> [AgentLoginRoleMutationFailureV1] {
        var failures: [AgentLoginRoleMutationFailureV1] = []
        for (role, service) in roles {
            do {
                try await service.unregister()
            } catch {
                failures.append(AgentLoginRoleMutationFailureV1(
                    role: role,
                    mutation: .unregister,
                    reason: failureReason(error)
                ))
            }
        }
        return failures
    }

    private func failureReason(
        _ error: any Error
    ) -> AgentLoginRoleFailureReasonV1 {
        guard let convergenceError = error as? AgentLoginRoleConvergenceErrorV1
        else {
            return .platformFailure
        }
        switch convergenceError {
        case .requiresApproval:
            return .requiresApproval
        case .serviceNotFound:
            return .serviceNotFound
        case .platformFailure:
            return .platformFailure
        case .postconditionFailed:
            return .postconditionFailed
        }
    }
}
