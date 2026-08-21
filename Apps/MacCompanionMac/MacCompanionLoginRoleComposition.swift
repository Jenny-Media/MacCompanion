import CompanionAgent
import CompanionAgentPlatform
import ServiceManagement

/// Permanent containing-app ownership of the two login-role identities.
///
/// Construction is intentionally side-effect free: creating `SMAppService`
/// values does not register either role. Only the package-owned lifecycle saga
/// may call the retained executor after an explicit user enable or a durable
/// restart-reconciliation decision.
@MainActor
final class MacCompanionLoginRoleComposition {
    static let agentPlistName = "media.jenny.maccompanion.agent.plist"

    let executor: AgentLoginRoleEffectExecutorV1

    init(
        agentService: SMAppService = .agent(
            plistName: MacCompanionLoginRoleComposition.agentPlistName
        ),
        menuAppService: SMAppService = .mainApp
    ) {
        let agent = AgentLoginRoleConvergingServiceV1(
            raw: SMAppServiceRawLoginRoleV1(service: agentService)
        )
        let menuApp = AgentLoginRoleConvergingServiceV1(
            raw: SMAppServiceRawLoginRoleV1(service: menuAppService)
        )
        executor = AgentLoginRoleEffectExecutorV1(
            agent: agent,
            menuApp: menuApp
        )
    }
}
