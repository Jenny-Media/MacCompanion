#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionAgentProductPlatform
import CompanionHost
import CompanionHostPlatform
import Foundation

public enum MacCompanionAgentInertPreparationDeferralV1:
    Equatable,
    Sendable
{
    case firstUnlockRequired
    case localRecoveryRequired
    case recoveryFenced
}

/// Narrow permanent-target owner. It retains the prepared product but exposes
/// no observer start, local-XPC construction, listener, pairing, process, login
/// role, provider, or runtime-activation capability.
@available(macOS 26.0, *)
public actor MacCompanionAgentInertSystemOwnerV1 {
    private let prepared: MacAgentInertApplicationLifecycleV1

    package init(prepared: MacAgentInertApplicationLifecycleV1) {
        self.prepared = prepared
    }

    public func finish() async {
        await prepared.finish()
    }
}

@available(macOS 26.0, *)
public enum MacCompanionAgentInertSystemPreparationResultV1: Sendable {
    case ready(MacCompanionAgentInertSystemOwnerV1)
    case deferred(MacCompanionAgentInertPreparationDeferralV1)
}

/// Exact permanent-process retention after preparation and authentication
/// startup policy have both converged.
@available(macOS 26.0, *)
public enum MacCompanionAgentInertStartupRetentionV1: Sendable {
    /// First unlock can converge without local administration. The process
    /// exits so its configured launchd policy may retry later.
    case retryAfterFirstUnlock
    /// Durable recovery requires future local user action. Keep only the
    /// authentication boundary alive instead of entering a launchd retry loop.
    case authenticationOnly(MacCompanionAgentInertPreparationDeferralV1)
    /// Canonical durable preparation is retained, still without activation.
    case prepared(MacCompanionAgentInertSystemOwnerV1)
}

/// Release-shaped, construction-only entry point for the permanent per-user
/// Agent. The broader product module remains hidden from the executable. This
/// seam may reconcile private release storage and host Keychain identity, but
/// it supplies explicit fail-closed Interactive and process-start platforms and
/// returns an owner with no activation method.
@available(macOS 26.0, *)
public enum MacCompanionAgentInertSystemPreparationV1 {
    public static let hostIdentityApplicationTagPrefix =
        "media.jenny.maccompanion.agent.identity.v1"

    public static func prepare() async throws
        -> MacCompanionAgentInertSystemPreparationResultV1
    {
        let clock = SystemMacDashboardLifecycleWallClockV1()
        let inputs = try makeInputs(
            registryGeneration: UUID(),
            wallNowUnixMilliseconds: clock.nowUnixMilliseconds()
        )
        return map(
            try await MacAgentApplicationPreparationFacadeV1.prepare(
                inputs: inputs
            )
        )
    }

    package static func makeInputs(
        registryGeneration: UUID,
        wallNowUnixMilliseconds: Int64
    ) throws -> MacAgentApplicationPreparationInputsV1 {
        MacAgentApplicationPreparationInputsV1(
            hostIdentityConfiguration:
                try SecurityHostIdentityKeyCustodyConfigurationV0(
                    applicationTagPrefix: hostIdentityApplicationTagPrefix
                ),
            nativeMVPProviders:
                try AgentNativeMVPProviderCompositionV1.systemDefault(
                    registryGeneration: registryGeneration
                ),
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            statusPlatform: AgentHostStatusPlatformServicesV1(
                sampler: MacSystemStatusSampler(),
                clock: SystemHostStatusClock(),
                initialGeneration: UUID()
            ),
            interactivePlatform: .inertUnavailable(),
            processStarter: InertMacDashboardLifecycleProcessStarterV1()
        )
    }

    package static func map(
        _ result: MacAgentApplicationPreparationResultV1
    ) -> MacCompanionAgentInertSystemPreparationResultV1 {
        switch result {
        case let .prepared(prepared):
            return .ready(
                MacCompanionAgentInertSystemOwnerV1(prepared: prepared)
            )
        case .waitForFirstUnlock:
            return .deferred(.firstUnlockRequired)
        case .requireLocalRecovery:
            return .deferred(.localRecoveryRequired)
        case .recoveryFenced:
            return .deferred(.recoveryFenced)
        }
    }
}

/// Orders permanent preparation before the authentication-only XPC start and
/// compensates a ready prepared owner if that local trust boundary cannot open.
/// The injectable package seam exists solely for deterministic process-policy
/// tests; the executable uses the production preparation closure.
@available(macOS 26.0, *)
public enum MacCompanionAgentInertStartupCoordinatorV1 {
    public static func prepareAndStartAuthentication(
        startAuthentication: @escaping @Sendable () throws -> Void
    ) async throws -> MacCompanionAgentInertStartupRetentionV1 {
        try await prepareAndStartAuthentication(
            prepare: {
                try await MacCompanionAgentInertSystemPreparationV1.prepare()
            },
            startAuthentication: startAuthentication
        )
    }

    package static func prepareAndStartAuthentication(
        prepare: @escaping @Sendable () async throws ->
            MacCompanionAgentInertSystemPreparationResultV1,
        startAuthentication: @escaping @Sendable () throws -> Void
    ) async throws -> MacCompanionAgentInertStartupRetentionV1 {
        let result = try await prepare()
        switch result {
        case let .ready(owner):
            do {
                try startAuthentication()
                return .prepared(owner)
            } catch {
                await owner.finish()
                throw error
            }
        case .deferred(.firstUnlockRequired):
            return .retryAfterFirstUnlock
        case let .deferred(reason):
            try startAuthentication()
            return .authenticationOnly(reason)
        }
    }
}
#endif
