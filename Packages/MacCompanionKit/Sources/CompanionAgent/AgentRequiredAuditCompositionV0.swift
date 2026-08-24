import CompanionAuthentication
import CompanionDomain
import CompanionHostWire
import CompanionHostSession
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import CompanionOperations
import CompanionPairing
import CompanionPersistence
import CompanionTransport
import CompanionWire
import CompanionLifecycle
import Foundation

public enum AgentRequiredAuditCompositionErrorV1:
    Error, Equatable, Sendable
{
    case hostIdentityUnavailable
    case deviceRevocationRecoveryUnavailable
}

/// Projects a successful durable pairing into the local status inventory.
/// The pairing commit remains authoritative: a diagnostic refresh failure
/// must not turn an already-committed device into an ambiguous client result.
private struct AgentInventoryRefreshingPairingCommitterV1:
    PairingCommitter
{
    let durableCommitter: any PairingCommitter
    let localServices: AgentLocalServiceRootV1

    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        try await durableCommitter.commitPairing(
            pairingID: pairingID,
            record: record,
            displayName: displayName
        )
        try? await localServices.refreshInventory()
    }
}

/// Platform-only Interactive Control seams accepted by the release Agent.
/// Durable device/grant admission and required audit are deliberately absent:
/// the startup composition binds those to its own reconciled stores.
public struct AgentInteractivePlatformServicesV1: Sendable {
    package let visibleAdmission:
        any VisibleInteractiveAdmissionReadingV0
    package let materials: any InteractiveSessionMaterialGeneratingV0
    package let runtime: any InteractiveSessionRuntimeOwningV0
    package let surfaceControl:
        (any InteractiveSurfaceControlDispatchingV0)?

    public init(
        visibleAdmission: any VisibleInteractiveAdmissionReadingV0,
        materials: any InteractiveSessionMaterialGeneratingV0,
        runtime: any InteractiveSessionRuntimeOwningV0,
        surfaceControl:
            (any InteractiveSurfaceControlDispatchingV0)? = nil
    ) {
        self.visibleAdmission = visibleAdmission
        self.materials = materials
        self.runtime = runtime
        self.surfaceControl = surfaceControl
    }

    /// Explicit construction-only platform for a permanent Agent that has not
    /// yet bound authenticated visible-menu admission or a Control runtime.
    /// Every attempted Interactive operation fails closed; termination remains
    /// idempotent so product teardown can always converge.
    public static func inertUnavailable() -> Self {
        Self(
            visibleAdmission: AgentInertVisibleInteractiveAdmissionV1(),
            materials: AgentInertInteractiveMaterialsV1(),
            runtime: AgentInertInteractiveRuntimeV1()
        )
    }

    /// Release-preparation shape for an Agent that may retain a production
    /// cryptographic material source before authenticated menu admission and
    /// runtime ownership are bound. Construction invokes no material method;
    /// visibility and runtime effects remain fail-closed until the product
    /// root replaces those two authorities for an authenticated menu
    /// generation.
    public static func deferredMenuBinding(
        materials: any InteractiveSessionMaterialGeneratingV0
    ) -> Self {
        Self(
            visibleAdmission: AgentInertVisibleInteractiveAdmissionV1(),
            materials: materials,
            runtime: AgentInertInteractiveRuntimeV1()
        )
    }
}

public enum AgentInertInteractivePlatformErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
}

private struct AgentInertVisibleInteractiveAdmissionV1:
    VisibleInteractiveAdmissionReadingV0
{
    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0 {
        throw AgentInertInteractivePlatformErrorV1.unavailable
    }
}

private struct AgentInertInteractiveMaterialsV1:
    InteractiveSessionMaterialGeneratingV0
{
    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0 {
        throw AgentInertInteractivePlatformErrorV1.unavailable
    }

    func bootstrapMaterials() async throws
        -> InteractiveSessionBootstrapMaterials
    {
        throw AgentInertInteractivePlatformErrorV1.unavailable
    }
}

private actor AgentInertInteractiveRuntimeV1:
    InteractiveSessionRuntimeOwningV0
{
    func install(
        _: InteractiveSessionBootstrap,
        requirement _: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        throw AgentInertInteractivePlatformErrorV1.unavailable
    }

    func terminate(
        interactiveSessionID _: UUID,
        primaryConnectionID _: Data,
        reason _: InteractiveSessionEndReason
    ) async {}
}

/// Identity-neutral construction root for Agent authorities whose audit
/// requirements must not be optional in a product composition.
///
/// Lower-level authorities retain injectable initializers for focused tests.
/// A release target constructs operation execution and lifecycle observation
/// through this root so both share the same separately bounded detailed store.
public struct AgentRequiredAuditCompositionV0: Sendable {
    package let securityStore: SQLiteSecurityStore
    private let detailedAuditStore: SQLiteBoundedAuditStoreV0
    private let denyLatch: EmergencyDenyLatch
    public let operationAuditWriter: BoundedOperationAuditWriterV0
    public let lifecycleAuditWriter: BoundedLifecycleAuditWriterV0
    public let primarySessionAuditWriter: BoundedPrimarySessionAuditWriterV0
    public let pairingAuditWriter: BoundedPairingAuditWriterV0
    public let interactiveAuditWriter: BoundedInteractiveAuditWriterV0
    public let localInteractiveStopAuditWriter:
        BoundedLocalInteractiveStopAuditWriterV0
    public let registryPublicationAuditWriter:
        BoundedCapabilityRegistryPublicationAuditWriterV1
    public init(
        securityStore: SQLiteSecurityStore,
        detailedAuditStore: SQLiteBoundedAuditStoreV0,
        denyLatch: EmergencyDenyLatch
    ) {
        self.securityStore = securityStore
        self.detailedAuditStore = detailedAuditStore
        self.denyLatch = denyLatch
        let operationAuditWriter = BoundedOperationAuditWriterV0(
            store: detailedAuditStore
        )
        self.operationAuditWriter = operationAuditWriter
        lifecycleAuditWriter = BoundedLifecycleAuditWriterV0(
            store: detailedAuditStore
        )
        primarySessionAuditWriter = BoundedPrimarySessionAuditWriterV0(
            store: detailedAuditStore
        )
        pairingAuditWriter = BoundedPairingAuditWriterV0(
            store: detailedAuditStore
        )
        interactiveAuditWriter = BoundedInteractiveAuditWriterV0(
            store: detailedAuditStore
        )
        localInteractiveStopAuditWriter =
            BoundedLocalInteractiveStopAuditWriterV0(
                store: detailedAuditStore
            )
        registryPublicationAuditWriter =
            BoundedCapabilityRegistryPublicationAuditWriterV1(
                store: detailedAuditStore
            )
    }

    public func healthSnapshot() async -> AgentDetailedAuditHealthSnapshotV0 {
        var degraded: [AgentDetailedAuditProducerV0] = []
        if await operationAuditWriter.health() == .degraded {
            degraded.append(.operation)
        }
        if await lifecycleAuditWriter.health() == .degraded {
            degraded.append(.lifecycle)
        }
        if await primarySessionAuditWriter.health() == .degraded {
            degraded.append(.primarySession)
        }
        if await pairingAuditWriter.health() == .degraded {
            degraded.append(.pairing)
        }
        if await interactiveAuditWriter.health() == .degraded {
            degraded.append(.interactiveRemote)
        }
        if await localInteractiveStopAuditWriter.health() == .degraded {
            degraded.append(.interactiveLocalStop)
        }
        if await registryPublicationAuditWriter.health() == .degraded {
            degraded.append(.registryPublication)
        }
        return AgentDetailedAuditHealthSnapshotV0(
            degradedProducers: degraded
        )
    }

    public func refreshLocalStatusAuditHealth(
        _ localServices: AgentLocalServiceRootV1
    ) async {
        await localServices.auditHealth.publish(
            degraded:
            await healthSnapshot().requiresLocalRepair
        )
    }

    /// Constructs the complete pairing authority graph from the same durable
    /// security store and required pairing-audit writer. Production network
    /// code consumes the returned aggregate rather than independently
    /// selecting any of these owners.
    package func makePairingServices(
        localServices: AgentLocalServiceRootV1,
        contextSource: any AgentLocalPairingContextReadingV0,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) -> AgentPairingServicesV0 {
        let authority = PairingSessionAuthority(
            committer: AgentInventoryRefreshingPairingCommitterV1(
                durableCommitter: securityStore,
                localServices: localServices
            ),
            auditWriter: pairingAuditWriter
        )
        let sessions = AgentLocalPairingSessionHandlerV0(
            authority: authority,
            contextSource: contextSource,
            timeSource: timeSource,
            pairingIDGenerator: pairingIDGenerator
        )
        let decisions = AgentLocalPairingDecisionHandlerV0(
            authority: authority,
            timeSource: timeSource,
            policySource: policySource,
            makeDeviceID: deviceIDGenerator
        )
        return AgentPairingServicesV0(
            authority: authority,
            recovery: SQLiteAgentHostPairingRecoveryAuthorityV0(
                store: securityStore
            ),
            sessions: sessions,
            decisions: decisions,
            reviews: localServices.makePairingReviewService(
                decisions: decisions,
                alreadyAuthorizedSurface: alreadyAuthorizedSurface
            )
        )
    }

    /// Release construction path. Status host identity/revision storage and
    /// Interactive durable admission/required audit are issued by this exact
    /// startup root; the target supplies only platform measurement,
    /// authenticated observation, cryptographic material, and execution seams.
    public func bootstrapPrimaryServices(
        registry: CapabilityRegistrySnapshotV1,
        providerLoader: any AgentCapabilityProviderLoadingV1,
        wallNowUnixMilliseconds: Int64,
        lifecycleState: ProductLifecycleState,
        statusPlatform: AgentHostStatusPlatformServicesV1,
        interactivePlatform: AgentInteractivePlatformServicesV1,
        localStatusWallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1(),
        wallClock: any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1(),
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0()
    ) async throws -> AgentPrimaryServicesV1 {
        guard let hostIdentity = try await securityStore.hostIdentity(),
              hostIdentity.state == .ready else {
            throw AgentRequiredAuditCompositionErrorV1
                .hostIdentityUnavailable
        }
        let interactive = InteractiveSessionWireDispatcherV0(
            admission: SQLiteInteractiveSessionAdmissionReaderV0(
                store: securityStore,
                visible: interactivePlatform.visibleAdmission
            ),
            materials: interactivePlatform.materials,
            runtime: interactivePlatform.runtime,
            surfaceControl: interactivePlatform.surfaceControl,
            auditWriter: interactiveAuditWriter
        )
        return try await bootstrapPrimaryServices(
            hostIdentity: hostIdentity,
            registry: registry,
            providerLoader: providerLoader,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            lifecycleState: lifecycleState,
            status: AgentRootBoundHostStatusProviderV1(
                hostID: hostIdentity.hostID,
                store: securityStore,
                platform: statusPlatform
            ),
            interactive: interactive,
            localStatusWallClock: localStatusWallClock,
            wallClock: wallClock,
            deadlineRunner: deadlineRunner,
            detailedAuditWallClock: detailedAuditWallClock
        )
    }

    /// Lower construction seam retained for package tests and focused
    /// adapters. Product targets outside the package cannot supply a complete
    /// dispatcher and bypass store/audit binding.
    package func bootstrapPrimaryServices(
        hostIdentity: StoredHostIdentityRecord,
        registry: CapabilityRegistrySnapshotV1,
        providerLoader: any AgentCapabilityProviderLoadingV1,
        wallNowUnixMilliseconds: Int64,
        lifecycleState: ProductLifecycleState,
        status: any HostStatusSnapshotProvidingV0,
        interactive: any AuthenticatedInteractiveWireDispatchingV0,
        localStatusWallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1(),
        wallClock: any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1(),
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0()
    ) async throws -> AgentPrimaryServicesV1 {
        guard hostIdentity.state == .ready else {
            throw AgentRequiredAuditCompositionErrorV1
                .hostIdentityUnavailable
        }
        let hostID = hostIdentity.hostID
        let revocationCoordinator = DeviceRevocationCoordinator(
            securityStore: securityStore,
            denyLatch: denyLatch
        )
        let revocationRecovery: ReviewedDeviceRevocationRecoveryResult
        do {
            revocationRecovery = try await revocationCoordinator
                .recoverReviewedRevocation(
                    occurredAtUnixMilliseconds:
                        wallNowUnixMilliseconds
                )
        } catch {
            throw AgentRequiredAuditCompositionErrorV1
                .deviceRevocationRecoveryUnavailable
        }
        let providers = try await providerLoader.loadProviders()
        let initial = try CapabilityRegistryPublicationV1(
            registry: registry,
            providers: providers
        )
        let bound = AgentRegistryBoundOperationsV1(
            securityStore: securityStore,
            startup: OperationStartupReconcilerV0(store: securityStore),
            initial: initial,
            registryAuditWriter: registryPublicationAuditWriter,
            operationAuditWriter: operationAuditWriter,
            wallClock: wallClock,
            deadlineRunner: deadlineRunner
        )
        let ingress = try await bound.reconcileBeforeOpeningIngress(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        )
        let localServices = try await AgentLocalServiceRootV1.bootstrap(
            lifecycle: lifecycleState,
            pairedDevices: securityStore,
            capabilities: bound.capabilityAuthority,
            denyLatch: denyLatch,
            auditHistoryDegraded:
                await healthSnapshot().requiresLocalRepair,
            wallClock: localStatusWallClock
        )
        let primarySessions = AgentPrimarySessionAuthorityV1(
            hostID: hostID,
            ingress: ingress,
            ingressEnabled: lifecycleState.observeAvailable,
            authentication: ApplicationAuthenticationAuthority(
                deviceReader: securityStore
            ),
            status: status,
            audit: AuditSelfWireDispatcherV1(
                securityStore: securityStore,
                auditStore: detailedAuditStore
            ),
            interactive: interactive,
            routeObservationPublishers:
                localServices.authenticatedRouteObservationPublishers,
            detailedAudit: primarySessionAuditWriter,
            detailedAuditWallClock: detailedAuditWallClock
        )
        if case let .convergenceRequired(deviceID) = revocationRecovery {
            await primarySessions.fenceForSecurityAdministration()
            do {
                try await localServices.refreshInventory()
                try await revocationCoordinator.finishStatusConvergence(
                    deviceID: deviceID,
                    occurredAtUnixMilliseconds:
                        wallNowUnixMilliseconds
                )
                guard await localServices.refreshSecurity() == .nominal else {
                    throw AgentRequiredAuditCompositionErrorV1
                        .deviceRevocationRecoveryUnavailable
                }
            } catch {
                throw AgentRequiredAuditCompositionErrorV1
                    .deviceRevocationRecoveryUnavailable
            }
            await primarySessions.releaseSecurityAdministrationFence()
        }
        return AgentPrimaryServicesV1(
            hostIdentity: hostIdentity,
            capabilityAuthority: bound.capabilityAuthority,
            reconciliation: ingress.reconciliation,
            primarySessions: primarySessions,
            lifecycle: AgentRemoteLifecycleCoordinatorV1(
                initialState: lifecycleState,
                primarySessions: primarySessions,
                auditWriter: lifecycleAuditWriter,
                localStatus: localServices.lifecycleStatus
            ),
            localServices: localServices,
            pairingComposition: self
        )
    }

#if os(macOS)
    fileprivate func makeLocalDeviceRevocationHandler(
        primary: AgentPrimarySessionAuthorityV1,
        status: AgentLocalServiceRootV1,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64
    ) -> LocalDeviceRevocationHandlerV0 {
        LocalDeviceRevocationHandlerV0(
            store: securityStore,
            coordinator: DeviceRevocationCoordinator(
                securityStore: securityStore,
                denyLatch: denyLatch
            ),
            primary: primary,
            status: status,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        )
    }
#endif

}

/// Sealed bundle-independent pairing graph. Package platform adapters may
/// consume its members to build the production listener, while applications
/// receive only the aggregate and cannot substitute a different authority,
/// decision owner, or review publisher.
public struct AgentPairingServicesV0: Sendable {
    package let authority: PairingSessionAuthority
    package let recovery: any AgentHostPairingRecoveryAuthorityV0
    package let sessions: AgentLocalPairingSessionHandlerV0
    package let decisions: AgentLocalPairingDecisionHandlerV0
    package let reviews: AgentLocalPairingReviewServiceV0

    package init(
        authority: PairingSessionAuthority,
        recovery: any AgentHostPairingRecoveryAuthorityV0,
        sessions: AgentLocalPairingSessionHandlerV0,
        decisions: AgentLocalPairingDecisionHandlerV0,
        reviews: AgentLocalPairingReviewServiceV0
    ) {
        self.authority = authority
        self.recovery = recovery
        self.sessions = sessions
        self.decisions = decisions
        self.reviews = reviews
    }

    /// Secret-bearing local QR API for an already authorized menu-app
    /// connection. The backing authority remains inaccessible to the app.
    public var localPairingSessions: AgentLocalPairingSessionHandlerV0 {
        sessions
    }

    /// Connection-scoped local approval delivery and resolution API.
    public var localPairingReviews: AgentLocalPairingReviewServiceV0 {
        reviews
    }
}

/// The product-owned provider-loading seam. Loading may perform local process
/// discovery or authenticated adapter construction, but no result escapes the
/// Agent bootstrap until the complete set validates against the registry and
/// durable operation startup reconciliation succeeds.
public protocol AgentCapabilityProviderLoadingV1: Sendable {
    func loadProviders() async throws -> [any CapabilityProviderV1]
}

/// Convenience loader for providers already constructed by a product target.
/// Publication validation still occurs inside the fail-closed bootstrap.
public struct StaticAgentCapabilityProviderLoaderV1:
    AgentCapabilityProviderLoadingV1, Sendable
{
    private let providers: [any CapabilityProviderV1]

    public init(providers: [any CapabilityProviderV1]) {
        self.providers = providers
    }

    public func loadProviders() async throws -> [any CapabilityProviderV1] {
        providers
    }
}

/// Complete bundle-independent service root returned to the future signed
/// Agent. No property is available when provider loading, publication
/// validation, or durable restart reconciliation fails.
public struct AgentPrimaryServicesV1: Sendable {
    public var hostID: UUID { hostIdentity.hostID }
    package let hostIdentity: StoredHostIdentityRecord
    public let capabilityAuthority: AgentCapabilityAuthorityV1
    public let reconciliation: DurableOperationStartupReconciliation
    public let primarySessions: AgentPrimarySessionAuthorityV1
    public let lifecycle: AgentRemoteLifecycleCoordinatorV1
    public let localServices: AgentLocalServiceRootV1
    private let pairingComposition: AgentRequiredAuditCompositionV0

    fileprivate init(
        hostIdentity: StoredHostIdentityRecord,
        capabilityAuthority: AgentCapabilityAuthorityV1,
        reconciliation: DurableOperationStartupReconciliation,
        primarySessions: AgentPrimarySessionAuthorityV1,
        lifecycle: AgentRemoteLifecycleCoordinatorV1,
        localServices: AgentLocalServiceRootV1,
        pairingComposition: AgentRequiredAuditCompositionV0
    ) {
        self.hostIdentity = hostIdentity
        self.capabilityAuthority = capabilityAuthority
        self.reconciliation = reconciliation
        self.primarySessions = primarySessions
        self.lifecycle = lifecycle
        self.localServices = localServices
        self.pairingComposition = pairingComposition
    }

    /// Package production adapter seam. The pairing graph can only be issued
    /// by the required-audit composition that produced this exact
    /// startup-reconciled primary/local service root.
    package func makePairingServices(
        contextSource: any AgentLocalPairingContextReadingV0,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) -> AgentPairingServicesV0 {
        pairingComposition.makePairingServices(
            localServices: localServices,
            contextSource: contextSource,
            timeSource: timeSource,
            policySource: policySource,
            alreadyAuthorizedSurface: alreadyAuthorizedSurface,
            pairingIDGenerator: pairingIDGenerator,
            deviceIDGenerator: deviceIDGenerator
        )
    }

#if os(macOS)
    /// Issued only to the final platform adapter after it authenticates the
    /// visible menu-app endpoint for `administerDevices`.
    package func makeLocalDeviceRevocationHandler(
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
    ) -> LocalDeviceRevocationHandlerV0 {
        pairingComposition.makeLocalDeviceRevocationHandler(
            primary: primarySessions,
            status: localServices,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        )
    }
#endif
}

/// Product construction for the currently migrated registry consumers. The
/// same audited publication authority backs discovery, operation admission,
/// provider resolution, execution, and cancellation.
private struct AgentRegistryBoundOperationsV1: Sendable {
    let capabilityAuthority: AgentCapabilityAuthorityV1
    private let commands: OperationCommandCoordinatorV0
    private let operationWire: OperationWireCommandDispatcherV0
    private let capabilityWire: CapabilityRegistryWireDispatcherV1

    fileprivate init(
        securityStore: SQLiteSecurityStore,
        startup: OperationStartupReconcilerV0,
        initial: CapabilityRegistryPublicationV1,
        registryAuditWriter:
            BoundedCapabilityRegistryPublicationAuditWriterV1,
        operationAuditWriter: BoundedOperationAuditWriterV0,
        wallClock: any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1(),
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1()
    ) {
        let capabilityAuthority = AgentCapabilityAuthorityV1(
            initial: initial,
            grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(
                store: securityStore
            ),
            registryAuditWriter: registryAuditWriter,
            wallClock: wallClock
        )
        self.capabilityAuthority = capabilityAuthority
        let discovery = CapabilityDiscoveryAuthorityV1(
            store: securityStore,
            registryReader: capabilityAuthority
        )
        let commands = OperationCommandCoordinatorV0(
            store: securityStore,
            startup: startup,
            publicationReader: capabilityAuthority,
            deadlineRunner: deadlineRunner,
            auditWriter: operationAuditWriter
        )
        self.commands = commands
        operationWire = OperationWireCommandDispatcherV0(coordinator: commands)
        capabilityWire = CapabilityRegistryWireDispatcherV1(
            authority: discovery
        )
    }

    /// No authenticated session factory is available until durable operation
    /// startup reconciliation has succeeded.
    func reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: Int64
    ) async throws -> ReconciledAgentPrimaryIngressV1 {
        let report = try await commands.reconcileBeforeOpeningIngress(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        )
        return ReconciledAgentPrimaryIngressV1(
            operationWire: operationWire,
            capabilityWire: capabilityWire,
            reconciliation: report
        )
    }
}

/// Capability to construct authenticated primary sessions, issued only after
/// the durable startup fence has completed.
private struct ReconciledAgentPrimaryIngressV1: Sendable {
    let reconciliation: DurableOperationStartupReconciliation
    private let operationWire: OperationWireCommandDispatcherV0
    private let capabilityWire: CapabilityRegistryWireDispatcherV1

    fileprivate init(
        operationWire: OperationWireCommandDispatcherV0,
        capabilityWire: CapabilityRegistryWireDispatcherV1,
        reconciliation: DurableOperationStartupReconciliation
    ) {
        self.operationWire = operationWire
        self.capabilityWire = capabilityWire
        self.reconciliation = reconciliation
    }

    func makeAuthenticatedPrimarySession(
        hostID: UUID,
        tlsBinding: HostApplicationTLSBinding,
        acceptedAtMonotonicMilliseconds: UInt64,
        authentication: ApplicationAuthenticationAuthority,
        status: any HostStatusSnapshotProvidingV0,
        audit: (any AuthenticatedAuditWireDispatchingV1)? = nil,
        interactive: any AuthenticatedInteractiveWireDispatchingV0,
        routeObservationPublisher:
            any AuthenticatedRouteObservationPublishingV1,
        detailedAudit: any PrimarySessionAuditWritingV0,
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0()
    ) throws -> AuthenticatedPrimarySessionV0 {
        try AuthenticatedPrimarySessionV0(
            hostID: hostID,
            tlsBinding: tlsBinding,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds,
            authentication: authentication,
            status: status,
            operations: operationWire,
            capabilities: capabilityWire,
            audit: audit,
            interactive: interactive,
            routeObservationPublisher: routeObservationPublisher,
            detailedAudit: detailedAudit,
            detailedAuditWallClock: detailedAuditWallClock
        )
    }
}

/// Sole primary-session owner for the one-Mac/one-phone MVP. Reconnect closes
/// the previous owner before opening the replacement, which also makes the
/// shared Interactive authority's close notification unambiguous.
public enum AgentPrimarySessionAuthorityErrorV1:
    Error, Equatable, Sendable
{
    case transitionInProgress
    case closedDuringReplacement
    case sessionNotCurrent
    case lifecycleUnavailable
    case securityAdministrationUnavailable
}

public protocol AgentPrimaryTransportClosingV1: Sendable {
    func closeTransport() async
}

public actor AgentPrimarySessionAuthorityV1 {
    private let hostID: UUID
    private let ingress: ReconciledAgentPrimaryIngressV1
    private let authentication: ApplicationAuthenticationAuthority
    private let status: any HostStatusSnapshotProvidingV0
    private let audit: any AuthenticatedAuditWireDispatchingV1
    private let interactive: any AuthenticatedInteractiveWireDispatchingV0
    private let routeObservationPublishers:
        AgentAuthenticatedRouteObservationPublisherFactoryV1
    private let detailedAudit: any PrimarySessionAuditWritingV0
    private let detailedAuditWallClock: any PrimarySessionAuditWallClockV0
    private var ingressEnabled: Bool
    private var securityAdministrationIngressDenied = false
    private var current: AuthenticatedPrimarySessionV0?
    private var currentTransport: (any AgentPrimaryTransportClosingV1)?
    private var transitionInProgress = false
    private var closeRequestedDuringTransition = false
    private var transitionWaiters: [CheckedContinuation<Void, Never>] = []

    fileprivate init(
        hostID: UUID,
        ingress: ReconciledAgentPrimaryIngressV1,
        ingressEnabled: Bool,
        authentication: ApplicationAuthenticationAuthority,
        status: any HostStatusSnapshotProvidingV0,
        audit: any AuthenticatedAuditWireDispatchingV1,
        interactive: any AuthenticatedInteractiveWireDispatchingV0,
        routeObservationPublishers:
            AgentAuthenticatedRouteObservationPublisherFactoryV1,
        detailedAudit: any PrimarySessionAuditWritingV0,
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0
    ) {
        self.hostID = hostID
        self.ingress = ingress
        self.ingressEnabled = ingressEnabled
        self.authentication = authentication
        self.status = status
        self.audit = audit
        self.interactive = interactive
        self.routeObservationPublishers = routeObservationPublishers
        self.detailedAudit = detailedAudit
        self.detailedAuditWallClock = detailedAuditWallClock
    }

    /// Opens the only current application-primary session. Connection-specific
    /// TLS evidence and acceptance time remain caller supplied; every semantic
    /// authority was fixed at successful Agent bootstrap.
    public func open(
        tlsBinding: HostApplicationTLSBinding,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async throws -> AuthenticatedPrimarySessionV0 {
        guard ingressEnabled else {
            throw AgentPrimarySessionAuthorityErrorV1.lifecycleUnavailable
        }
        guard !securityAdministrationIngressDenied else {
            throw AgentPrimarySessionAuthorityErrorV1
                .securityAdministrationUnavailable
        }
        guard !transitionInProgress else {
            throw AgentPrimarySessionAuthorityErrorV1.transitionInProgress
        }
        transitionInProgress = true
        let previous = current
        let previousTransport = currentTransport
        current = nil
        currentTransport = nil
        if let previousTransport {
            await previousTransport.closeTransport()
        }
        if let previous { await previous.close() }
        let session: AuthenticatedPrimarySessionV0
        do {
            let routeObservationPublisher = try await
                routeObservationPublishers.makePublisher()
            session = try ingress.makeAuthenticatedPrimarySession(
                hostID: hostID,
                tlsBinding: tlsBinding,
                acceptedAtMonotonicMilliseconds:
                    acceptedAtMonotonicMilliseconds,
                authentication: authentication,
                status: status,
                audit: audit,
                interactive: interactive,
                routeObservationPublisher: routeObservationPublisher,
                detailedAudit: detailedAudit,
                detailedAuditWallClock: detailedAuditWallClock
            )
        } catch {
            closeRequestedDuringTransition = false
            finishTransition()
            throw error
        }
        if closeRequestedDuringTransition {
            closeRequestedDuringTransition = false
            await session.close()
            finishTransition()
            throw AgentPrimarySessionAuthorityErrorV1.closedDuringReplacement
        }
        current = session
        finishTransition()
        return session
    }

    public func setLifecycleIngressEnabled(_ enabled: Bool) {
        ingressEnabled = enabled
    }

    /// Installs an independent global security fence before awaiting any live
    /// transport/session teardown. Lifecycle callbacks cannot reopen this
    /// fence; only the security owner may release it after durable convergence.
    package func fenceForSecurityAdministration() async {
        securityAdministrationIngressDenied = true
        await closeCurrent()
    }

    package func releaseSecurityAdministrationFence() {
        securityAdministrationIngressDenied = false
    }

    package func isSecurityAdministrationIngressDenied() -> Bool {
        securityAdministrationIngressDenied
    }

    /// Attaches the exact transport constructed for the current session. A
    /// lifecycle close or reconnect then owns socket teardown as well as
    /// semantic-session teardown.
    public func attachTransport(
        _ transport: any AgentPrimaryTransportClosingV1,
        to session: AuthenticatedPrimarySessionV0
    ) throws {
        guard !transitionInProgress, current === session,
              currentTransport == nil else {
            throw AgentPrimarySessionAuthorityErrorV1.sessionNotCurrent
        }
        currentTransport = transport
    }

    public func closeCurrent() async {
        while transitionInProgress {
            closeRequestedDuringTransition = true
            await waitForTransition()
        }
        closeRequestedDuringTransition = false
        guard let current else { return }
        transitionInProgress = true
        let transport = currentTransport
        self.current = nil
        currentTransport = nil
        if let transport { await transport.closeTransport() }
        await current.close()
        closeRequestedDuringTransition = false
        finishTransition()
    }

    /// Failure cleanup for a connection being composed outside this actor.
    /// A stale factory may close its own session but can never close a newer
    /// current session installed by a racing verified connection.
    public func closeIfCurrent(
        _ session: AuthenticatedPrimarySessionV0
    ) async {
        while transitionInProgress { await waitForTransition() }
        guard current === session else {
            await session.close()
            return
        }
        transitionInProgress = true
        let transport = currentTransport
        current = nil
        currentTransport = nil
        if let transport { await transport.closeTransport() }
        await session.close()
        finishTransition()
    }

    /// Ends only Interactive authority while leaving an eligible Observe/Act
    /// primary connection open, as required when the visible menu app exits.
    public func endInteractiveControl() async {
        while transitionInProgress { await waitForTransition() }
        transitionInProgress = true
        await interactive.primarySessionClosed()
        finishTransition()
    }

    private func waitForTransition() async {
        await withCheckedContinuation { continuation in
            transitionWaiters.append(continuation)
        }
    }

    private func finishTransition() {
        transitionInProgress = false
        let waiters = transitionWaiters
        transitionWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

public enum AgentDetailedAuditProducerV0:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case operation
    case lifecycle
    case primarySession
    case pairing
    case interactiveRemote
    case interactiveLocalStop
    case registryPublication
}

public struct AgentDetailedAuditHealthSnapshotV0: Equatable, Sendable {
    public let degradedProducers: [AgentDetailedAuditProducerV0]

    public var requiresLocalRepair: Bool { !degradedProducers.isEmpty }

    public init(degradedProducers: [AgentDetailedAuditProducerV0]) {
        let unique = Set(degradedProducers)
        self.degradedProducers = AgentDetailedAuditProducerV0.allCases.filter {
            unique.contains($0)
        }
    }
}
