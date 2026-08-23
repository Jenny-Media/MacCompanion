#if os(macOS)
import CompanionAgentPlatform
import CompanionLifecycle
import CompanionLocalXPCPlatform

public protocol MacUpdateMenuAgentCommandingV0: Sendable {
    func closeNetworkAdmissionForUpdate() async throws
    func drainNetworkConnectionsForUpdate() async throws
}

public protocol MacUpdatePreparedInstallerStartingV0: Sendable {
    func startPreparedUpdate() async throws
}

@available(macOS 26.0, *)
extension MacLocalXPCDashboardProductV1: MacUpdateMenuAgentCommandingV0 {}

@available(macOS 26.0, *)
extension MacCompanionDashboardApplicationV1:
    MacUpdateMenuAgentCommandingV0
{}

public struct MacUpdateMenuRuntimeRecoveryV0: Sendable {
    /// Reuses a known-live authenticated dashboard generation or reconstructs
    /// one after transport ambiguity, then issues the exact idempotent reopen
    /// command. After Agent stop, the caller invokes this only after exact
    /// source-build recovery.
    public let reconcileNetworkAdmission:
        @Sendable () async throws -> Void

    public init(
        reconcileNetworkAdmission:
            @escaping @Sendable () async throws -> Void
    ) {
        self.reconcileNetworkAdmission = reconcileNetworkAdmission
    }
}

/// Menu-owned closure composition for one already validated and admitted
/// update. It deliberately accepts no feed URL, archive, Sparkle controller,
/// or generic Agent authority. Permanent app composition remains inert until
/// a separately reviewed prepared-installer adapter is supplied.
public enum MacUpdateMenuRuntimeCompositionV0 {
    public static func coordinator(
        admission: MacUpdateInstallAdmissionV0,
        agentCommands: any MacUpdateMenuAgentCommandingV0,
        agentStopOwner: MacUpdateAgentStopOwnerV0,
        observeGate: @escaping @Sendable () async
            -> MacUpdateRuntimeGateObservationV0,
        installer: any MacUpdatePreparedInstallerStartingV0,
        recovery: MacUpdateMenuRuntimeRecoveryV0
    ) -> MacUpdateRuntimeShutdownCoordinatorV0 {
        MacUpdateRuntimeShutdownCoordinatorV0(
            admission: admission,
            dependencies: MacUpdateRuntimeShutdownDependenciesV0(
                observeGate: observeGate,
                closeNetworkAdmission: {
                    try await agentCommands
                        .closeNetworkAdmissionForUpdate()
                },
                drainBoundedWork: {
                    try await agentCommands
                        .drainNetworkConnectionsForUpdate()
                },
                stopAgent: {
                    try await agentStopOwner.stopForUpdate()
                },
                startUpdater: {
                    try await installer.startPreparedUpdate()
                },
                reconcileNetworkAdmission: {
                    try await recovery.reconcileNetworkAdmission()
                },
                reconcileAgentAndNetworkAdmission: {
                    try await agentStopOwner.recoverSourceBuild()
                    try await recovery.reconcileNetworkAdmission()
                }
            )
        )
    }
}

@available(macOS 26.0, *)
@MainActor
public extension MacCompanionProductApplicationV1 {
    /// Produces only the update coordinator's network-reconciliation seam.
    /// Creating it starts no dashboard, Agent, listener, or updater.
    func makeUpdateNetworkAdmissionRecovery()
        -> MacUpdateMenuRuntimeRecoveryV0
    {
        MacUpdateMenuRuntimeRecoveryV0(
            reconcileNetworkAdmission: { [weak self] in
                guard let self else {
                    throw MacCompanionUpdateNetworkReconciliationErrorV0
                        .unavailable
                }
                try await self.reconcileNetworkAdmissionForUpdate()
            }
        )
    }
}
#endif
