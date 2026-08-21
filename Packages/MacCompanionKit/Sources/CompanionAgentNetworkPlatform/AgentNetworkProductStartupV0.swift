import CompanionAgent
import CompanionDiscovery
import CompanionHostPlatform
import CompanionHostSession
import CompanionIPC
import CompanionLifecycle
import CompanionNetworkPlatform
import CompanionOperations
import CompanionSecurity
import CompanionWire
import Foundation

public struct AgentNetworkProductStartupInputsV0: Sendable {
    public let port: UInt16
    public let additionalEndpoints: [EndpointCandidate]
    public let registry: CapabilityRegistrySnapshotV1
    public let providerLoader: any AgentCapabilityProviderLoadingV1
    public let wallNowUnixMilliseconds: Int64
    public let lifecycleState: ProductLifecycleState
    public let statusPlatform: AgentHostStatusPlatformServicesV1
    public let interactivePlatform: AgentInteractivePlatformServicesV1
    public let pairingTimeSource: any AgentLocalPairingTimeSamplingV0
    public let pairingPolicySource: any AgentLocalPairingPolicyReadingV0
    public let alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0

    public init(
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        registry: CapabilityRegistrySnapshotV1,
        providerLoader: any AgentCapabilityProviderLoadingV1,
        wallNowUnixMilliseconds: Int64,
        lifecycleState: ProductLifecycleState,
        statusPlatform: AgentHostStatusPlatformServicesV1,
        interactivePlatform: AgentInteractivePlatformServicesV1,
        pairingTimeSource: any AgentLocalPairingTimeSamplingV0,
        pairingPolicySource: any AgentLocalPairingPolicyReadingV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0
    ) {
        self.port = port
        self.additionalEndpoints = additionalEndpoints
        self.registry = registry
        self.providerLoader = providerLoader
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.lifecycleState = lifecycleState
        self.statusPlatform = statusPlatform
        self.interactivePlatform = interactivePlatform
        self.pairingTimeSource = pairingTimeSource
        self.pairingPolicySource = pairingPolicySource
        self.alreadyAuthorizedSurface = alreadyAuthorizedSurface
    }

    /// First-party MVP construction path. The native registry and live
    /// provider references come from one reviewed composition, while all
    /// platform/session dependencies remain explicit release inputs.
    public init(
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        nativeMVPProviders: AgentNativeMVPProviderCompositionV1,
        wallNowUnixMilliseconds: Int64,
        lifecycleState: ProductLifecycleState,
        statusPlatform: AgentHostStatusPlatformServicesV1,
        interactivePlatform: AgentInteractivePlatformServicesV1,
        pairingTimeSource: any AgentLocalPairingTimeSamplingV0,
        pairingPolicySource: any AgentLocalPairingPolicyReadingV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0
    ) {
        self.init(
            port: port,
            additionalEndpoints: additionalEndpoints,
            registry: nativeMVPProviders.registry,
            providerLoader: nativeMVPProviders.providerLoader,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            lifecycleState: lifecycleState,
            statusPlatform: statusPlatform,
            interactivePlatform: interactivePlatform,
            pairingTimeSource: pairingTimeSource,
            pairingPolicySource: pairingPolicySource,
            alreadyAuthorizedSurface: alreadyAuthorizedSurface
        )
    }
}

public enum AgentNetworkProductStartupResultV0: Sendable {
    case ready(AgentNetworkPairingProductCompositionV0)
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case recoveryFenced(UUID)
}

/// The public release-shaped ordering from durable host identity through the
/// sealed shared listener product. A non-ready identity result constructs no
/// TLS configuration, primary root, pairing owner, or listener.
public enum AgentNetworkProductStartupFactoryV0 {
    public static func make(
        requiredAudit: AgentRequiredAuditCompositionV0,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        inputs: AgentNetworkProductStartupInputsV0,
        localStatusWallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1(),
        registryWallClock:
            any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1(),
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0(),
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> AgentNetworkProductStartupResultV0 {
        let coordinator = SecurityHostIdentityStartupCoordinatorV0(
            store: requiredAudit.securityStore,
            configuration: hostIdentityConfiguration,
            wallNowUnixMilliseconds: {
                inputs.wallNowUnixMilliseconds
            }
        )
        return try await make(
            hostIdentityStartup: { try await coordinator.start() },
            requiredAudit: requiredAudit,
            inputs: inputs,
            localStatusWallClock: localStatusWallClock,
            registryWallClock: registryWallClock,
            deadlineRunner: deadlineRunner,
            detailedAuditWallClock: detailedAuditWallClock,
            pairingIDGenerator: pairingIDGenerator,
            deviceIDGenerator: deviceIDGenerator
        )
    }

    package static func make(
        hostIdentityStartup: @escaping @Sendable () async throws ->
            SecurityHostIdentityStartupResultV0,
        requiredAudit: AgentRequiredAuditCompositionV0,
        inputs: AgentNetworkProductStartupInputsV0,
        localStatusWallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1(),
        registryWallClock:
            any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1(),
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0(),
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> AgentNetworkProductStartupResultV0 {
        let startup = try await hostIdentityStartup()
        switch startup {
        case .waitForFirstUnlock:
            return .waitForFirstUnlock
        case let .requireLocalRecovery(reason):
            return .requireLocalRecovery(reason)
        case let .recoveryFenced(recoveryID):
            return .recoveryFenced(recoveryID)
        case let .ready(record, issuedIdentity, _):
            let configuration = try NetworkHostTLSListenerConfigurationV0(
                issuedIdentity: issuedIdentity,
                requiredHostFingerprint: record.hostFingerprint,
                wallNowUnixMilliseconds:
                    inputs.wallNowUnixMilliseconds
            )
            let primary = try await requiredAudit.bootstrapPrimaryServices(
                registry: inputs.registry,
                providerLoader: inputs.providerLoader,
                wallNowUnixMilliseconds:
                    inputs.wallNowUnixMilliseconds,
                lifecycleState: inputs.lifecycleState,
                statusPlatform: inputs.statusPlatform,
                interactivePlatform: inputs.interactivePlatform,
                localStatusWallClock: localStatusWallClock,
                wallClock: registryWallClock,
                deadlineRunner: deadlineRunner,
                detailedAuditWallClock: detailedAuditWallClock
            )
            let product = try
                AgentNetworkPairingProductCompositionFactoryV0.make(
                    configuration: configuration,
                    port: inputs.port,
                    additionalEndpoints: inputs.additionalEndpoints,
                    primaryServices: primary,
                    timeSource: inputs.pairingTimeSource,
                    policySource: inputs.pairingPolicySource,
                    alreadyAuthorizedSurface:
                        inputs.alreadyAuthorizedSurface,
                    pairingIDGenerator: pairingIDGenerator,
                    deviceIDGenerator: deviceIDGenerator
                )
            return .ready(product)
        }
    }
}

/// Issues confirmed destructive recovery only against the same private store
/// owned by the required-audit Agent root. A future authenticated local-XPC
/// adapter may obtain only the returned connection-scoped delivery capability
/// after verifying the menu-app peer; it never receives the raw recovery
/// service, coordinator, or store.
public enum AgentHostIdentityRecoveryProductFactoryV0 {
    public static func make(
        requiredAudit: AgentRequiredAuditCompositionV0,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        alreadyAuthorizedSurface:
            any LocalHostIdentityRecoverySurfaceV0
    ) -> AgentLocalHostIdentityRecoveryDeliveryV0 {
        let coordinator = SecurityHostIdentityRecoveryCoordinatorV0(
            store: requiredAudit.securityStore,
            configuration: hostIdentityConfiguration
        )
        let recovery = AgentLocalHostIdentityRecoveryServiceV0(
            store: requiredAudit.securityStore,
            executor: SecurityAgentHostIdentityRecoveryExecutorV0(
                coordinator: coordinator
            )
        )
        return AgentLocalHostIdentityRecoveryDeliveryV0(
            recovery: recovery,
            alreadyAuthorizedSurface: alreadyAuthorizedSurface
        )
    }
}
