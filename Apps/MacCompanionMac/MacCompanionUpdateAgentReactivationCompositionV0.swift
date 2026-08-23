import CompanionAgentPlatform
import CompanionLifecycle
import CompanionLocalXPCPlatform
import Foundation

enum MacCompanionUpdateAgentReactivationCompositionErrorV0: Error {
    case unavailable
}

/// Containing-app ownership of durable update-time Agent recovery. Merely
/// constructing this value opens no XPC session and mutates no login role.
/// Startup repair runs before ordinary product routing and before the dashboard
/// owns the single authenticated menu lifetime.
@MainActor
final class MacCompanionUpdateAgentReactivationCompositionV0 {
    private let reactivator: MacUpdateAgentStartupReactivatorV0

    init(
        loginRoles: MacCompanionLoginRoleComposition,
        bundle: Bundle = .main
    ) throws {
        guard let runningBuild = MacLocalXPCProcessBuildV1.current(
            bundle: bundle
        ) else {
            throw MacCompanionUpdateAgentReactivationCompositionErrorV0
                .unavailable
        }
        let persistence = try
            AtomicFileMacUpdateAgentReactivationStoreV0.systemDefault()
        let readiness = try MacUpdateAgentBuildReadinessV0()
        let platform = MacUpdateAgentReactivationPlatformV0(
            registration: loginRoles.agentRaw,
            service: loginRoles.agent,
            persistence: persistence,
            readiness: readiness
        )
        reactivator = MacUpdateAgentStartupReactivatorV0(
            runningBuild: runningBuild,
            dependencies: platform.dependencies()
        )
    }

    func repairAtStartup() async throws {
        _ = try await reactivator.reactivateIfNeeded()
    }
}
