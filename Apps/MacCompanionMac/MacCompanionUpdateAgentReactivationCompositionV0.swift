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
    private let runningBuild: UInt64
    private let reactivator: MacUpdateAgentStartupReactivatorV0
    private let runtimeDependencies:
        MacUpdateAgentReactivationDependenciesV0

    init(
        loginRoles: MacCompanionLoginRoleComposition,
        activeAgentBuild: MacAuthenticatedAgentBuildLifetimeV0,
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
        let runtimePlatform = MacUpdateAgentReactivationPlatformV0(
            registration: loginRoles.agentRaw,
            service: loginRoles.agent,
            persistence: persistence,
            activeAgentBuild: activeAgentBuild
        )
        self.runningBuild = runningBuild
        runtimeDependencies = runtimePlatform.dependencies()
        reactivator = MacUpdateAgentStartupReactivatorV0(
            runningBuild: runningBuild,
            dependencies: platform.dependencies()
        )
    }

    func repairAtStartup() async throws {
        _ = try await reactivator.reactivateIfNeeded()
    }

    func makeStopOwner(
        candidateBuild: UInt64
    ) throws -> MacUpdateAgentStopOwnerV0 {
        try MacUpdateAgentStopOwnerV0(
            sourceBuild: runningBuild,
            candidateBuild: candidateBuild,
            dependencies: runtimeDependencies
        )
    }
}
