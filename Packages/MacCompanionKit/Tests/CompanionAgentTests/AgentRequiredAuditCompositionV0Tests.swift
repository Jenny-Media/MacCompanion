import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAuthentication
import CompanionDomain
import CompanionHost
import CompanionHostSession
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionLifecycle
@testable import CompanionNetworkPlatform
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Network
import Testing

private enum AgentIngressTestErrorV1: Error, Equatable {
    case unused
    case providerLoadFailed
}

private actor AgentBootstrapProviderV1: CapabilityProviderV1 {
    nonisolated let identity: CapabilityProviderIdentityV1

    init(descriptor: CapabilityDescriptorV1) {
        identity = CapabilityProviderIdentityV1(
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision
        )
    }

    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        .failed(.unavailable)
    }
}

private struct FailingAgentProviderLoaderV1:
    AgentCapabilityProviderLoadingV1
{
    func loadProviders() async throws -> [any CapabilityProviderV1] {
        throw AgentIngressTestErrorV1.providerLoadFailed
    }
}

private func agentBootstrapDescriptorV1() throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: "maccompanion.test.bootstrap",
        schemaVersion: 1,
        providerID: "maccompanion.test",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f8300-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018f8300-0000-7000-8000-000000000002"
        )!,
        englishTitle: "Bootstrap test",
        englishSummary: "Tests fail-closed Agent provider bootstrap.",
        parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []),
        effects: try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .none,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: true,
            cancellation: .notApplicable
        )
    )
}

private func readyAgentLifecycleStateV1() -> ProductLifecycleState {
    ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .active,
        agent: .ready,
        menuApp: .ready
    )
}

private func agentBootstrapHostIdentityV1(
    hostID: UUID = UUID(),
    state: StoredHostIdentityState = .ready,
    recoveryID: UUID? = nil
) throws -> StoredHostIdentityRecord {
    try StoredHostIdentityRecord(
        hostID: hostID,
        keyApplicationTag: Data("example.agent.bootstrap.identity".utf8),
        hostFingerprint: Data(repeating: 0xA5, count: 32),
        certificateDER: Data([0x30]),
        certificateNotBeforeUnixMilliseconds: 0,
        certificateNotAfterUnixMilliseconds: 10_000,
        establishedAtUnixMilliseconds: 0,
        updatedAtUnixMilliseconds: 0,
        state: state,
        recoveryID: recoveryID
    )
}

private struct AgentIngressStatusProviderV1:
    HostStatusSnapshotProvidingV0
{
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        throw AgentIngressTestErrorV1.unused
    }
}

private struct AgentProductStatusSamplerV1: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 100,
            cpuUtilizationBasisPoints: 500,
            memoryTotalBytes: 1_000,
            memoryUsedBytes: 500,
            storageTotalBytes: 2_000,
            storageAvailableBytes: 1_000,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

private struct AgentProductStatusClockV1: HostStatusClock {
    func nowUnixMilliseconds() -> Int64 { 1_787_198_400_900 }
}

private actor AgentIngressInteractiveDispatcherV1:
    AuthenticatedInteractiveWireDispatchingV0
{
    private var closeCount = 0

    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw AgentIngressTestErrorV1.unused
    }

    func primarySessionClosed() async { closeCount += 1 }

    func recordedCloseCount() -> Int { closeCount }
}

private struct AgentProductVisibleAdmissionV1:
    VisibleInteractiveAdmissionReadingV0
{
    let state: VisibleInteractiveAdmissionStateV0

    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0 {
        state
    }
}

private struct AgentProductInteractiveMaterialsV1:
    InteractiveSessionMaterialGeneratingV0
{
    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0 {
        throw AgentIngressTestErrorV1.unused
    }

    func bootstrapMaterials() async throws
        -> InteractiveSessionBootstrapMaterials {
        throw AgentIngressTestErrorV1.unused
    }
}

private actor AgentProductInteractiveRuntimeV1:
    InteractiveSessionRuntimeOwningV0
{
    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        throw AgentIngressTestErrorV1.unused
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {}
}

@Test func agentAuditCompositionRequiresBothStoresAndPublishesOnlyAuditedExecution() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-required-audit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let securityStore = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path
    )
    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: []
    )

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: auditStore,
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
    let hostID = UUID()
    let interactive = AgentIngressInteractiveDispatcherV1()

    #expect(await composition.operationAuditWriter.health() == .healthy)
    #expect(await composition.lifecycleAuditWriter.health() == .healthy)
    #expect(await composition.primarySessionAuditWriter.health() == .healthy)
    #expect(await composition.pairingAuditWriter.health() == .healthy)
    #expect(await composition.interactiveAuditWriter.health() == .healthy)
    #expect(await composition.localInteractiveStopAuditWriter.health() == .healthy)
    #expect(await composition.registryPublicationAuditWriter.health() == .healthy)
    #expect(await composition.healthSnapshot()
        == AgentDetailedAuditHealthSnapshotV0(degradedProducers: []))

    let bootstrapped = try await composition.bootstrapPrimaryServices(
        hostIdentity: try agentBootstrapHostIdentityV1(hostID: hostID),
        registry: registry,
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: 0,
        lifecycleState: readyAgentLifecycleStateV1(),
        status: AgentIngressStatusProviderV1(),
        interactive: interactive
    )
    #expect(bootstrapped.hostID == hostID)
    #expect(await bootstrapped.capabilityAuthority.registrySnapshot() == registry)
    let localInventory = try await bootstrapped.localServices.statusReader.read()
    #expect(localInventory.routeKinds.isEmpty)
    #expect(localInventory.pairedDeviceCount == 0)
    #expect(localInventory.providerCount == 0)
    let hostKey = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostKey.publicKey.x963Representation
    )
    let hostFingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    #expect(bootstrapped.reconciliation.totalReconciled == 0)
    let tlsBinding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: hostFingerprint
    )
    let session = try await bootstrapped.primarySessions.open(
        tlsBinding: tlsBinding,
        acceptedAtMonotonicMilliseconds: 0
    )
    #expect(await session.phase == .awaitingHello)
    let replacement = try await bootstrapped.primarySessions.open(
        tlsBinding: tlsBinding,
        acceptedAtMonotonicMilliseconds: 1
    )
    #expect(await session.phase == .closed)
    #expect(await replacement.phase == .awaitingHello)
    #expect(await interactive.recordedCloseCount() == 1)
    await bootstrapped.primarySessions.closeIfCurrent(session)
    #expect(await replacement.phase == .awaitingHello)
    let network = try await AgentNetworkPrimaryConnectionFactoryV1(
        primarySessions: bootstrapped.primarySessions
    ).bind(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0(
            connection: NWConnection(
                host: "127.0.0.1",
                port: 9,
                using: .tcp
            ),
            tlsBinding: tlsBinding
        ),
        acceptedAtMonotonicMilliseconds: 2,
        context: {
            NetworkHostRequestContextV0(
                hostState: .userSessionActive,
                wallNowUnixMilliseconds: 3,
                monotonicNowMilliseconds: 3,
                responseMessageID: WireUUID(UUID())
            )
        }
    )
    #expect(await replacement.phase == .closed)
    #expect(await network.session.phase == .awaitingHello)
    #expect(await interactive.recordedCloseCount() == 2)
    await #expect(throws: LifecycleAuditTransitionErrorV0.mismatchedTransition) {
        _ = try await bootstrapped.lifecycle.apply(
            .menuAppExited,
            transitionID: UUID(),
            observedAtUnixMilliseconds: -1
        )
    }
    #expect(await bootstrapped.lifecycle.state == readyAgentLifecycleStateV1())
    #expect(await network.session.phase == .awaitingHello)
    #expect(await interactive.recordedCloseCount() == 2)
    let afterInvalidLifecycle = try await bootstrapped.localServices
        .statusReader.read()
    #expect(afterInvalidLifecycle.agentProcess == .ready)
    #expect(afterInvalidLifecycle.menuAppProcess == .ready)
    #expect(afterInvalidLifecycle.warningCodes.isEmpty)
    let beforeABATransitions = await bootstrapped.lifecycle.currentSnapshot()
    let staleMenuExit = try await bootstrapped.lifecycle.prepare(
        .menuAppExited,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 1
    )
    _ = try await bootstrapped.lifecycle.apply(
        .userLocked,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 2
    )
    _ = try await bootstrapped.lifecycle.apply(
        .userUnlocked,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 3
    )
    let restoredState = await bootstrapped.lifecycle.state
    let afterABATransitions = await bootstrapped.lifecycle.currentSnapshot()
    #expect(staleMenuExit.completed.before == restoredState)
    #expect(afterABATransitions.revision == beforeABATransitions.revision + 2)
    #expect(afterABATransitions.agentObservationEpoch ==
        beforeABATransitions.agentObservationEpoch)
    #expect(afterABATransitions.menuAppObservationEpoch ==
        beforeABATransitions.menuAppObservationEpoch)
    await #expect(
        throws: AgentRemoteLifecycleCoordinatorErrorV1
            .stalePreparedTransition
    ) {
        _ = try await bootstrapped.lifecycle.commitPrepared(staleMenuExit)
    }
    let preparedMenuExit = try await bootstrapped.lifecycle.prepare(
        .menuAppExited,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 4
    )
    let menuExit = try await bootstrapped.lifecycle.commitPrepared(
        preparedMenuExit
    )
    #expect(menuExit.remainingPlatformEffects == [.requestMenuRecovery])
    let menuEpochAfterExit = await bootstrapped.lifecycle
        .menuAppObservationEpoch
    #expect(menuEpochAfterExit ==
        afterABATransitions.menuAppObservationEpoch + 1)
    #expect(await network.session.phase == .awaitingHello)
    #expect(await interactive.recordedCloseCount() == 3)
    let afterMenuExit = try await bootstrapped.localServices.statusReader.read()
    #expect(afterMenuExit.agentProcess == .ready)
    #expect(afterMenuExit.menuAppProcess == .starting)
    #expect(afterMenuExit.warningCodes == [.menuAppUnavailable])
    let agentExit = try await bootstrapped.lifecycle.apply(
        .agentExited,
        transitionID: UUID(),
        observedAtUnixMilliseconds: 5
    )
    #expect(agentExit.remainingPlatformEffects == [.requestAgentRecovery])
    let agentEpochAfterExit = await bootstrapped.lifecycle
        .agentObservationEpoch
    #expect(agentEpochAfterExit ==
        afterABATransitions.agentObservationEpoch + 1)
    #expect(await network.session.phase == .closed)
    #expect(await interactive.recordedCloseCount() == 4)
    let afterAgentExit = try await bootstrapped.localServices.statusReader.read()
    #expect(afterAgentExit.agentProcess == .starting)
    #expect(afterAgentExit.menuAppProcess == .starting)
    #expect(afterAgentExit.warningCodes == [
        .agentUnavailable,
        .menuAppUnavailable,
    ])
    await #expect(
        throws: NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
    ) {
        try await network.pump.beginOnVerifiedReadyConnection()
    }
    await #expect(
        throws: AgentPrimarySessionAuthorityErrorV1.lifecycleUnavailable
    ) {
        _ = try await AgentNetworkPrimaryConnectionFactoryV1(
            primarySessions: bootstrapped.primarySessions
        ).bind(
            verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0(
                connection: NWConnection(
                    host: "127.0.0.1",
                    port: 9,
                    using: .tcp
                ),
                tlsBinding: tlsBinding
            ),
            acceptedAtMonotonicMilliseconds: 4,
            context: {
                NetworkHostRequestContextV0(
                    hostState: .userSessionActive,
                    wallNowUnixMilliseconds: 4,
                    monotonicNowMilliseconds: 4,
                    responseMessageID: WireUUID(UUID())
                )
            }
        )
    }
    let lifecycleEvents = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).events
    #expect(lifecycleEvents.map(\.draft.code) == [.hostAvailabilityChanged])
}

@Test func agentReleaseBootstrapAcceptsOnlyPlatformStatusAndInteractiveSeams() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-interactive-product-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let securityStore = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let composition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
    let hostID = UUID()
    try await securityStore.establishHostIdentity(
        agentBootstrapHostIdentityV1(hostID: hostID)
    )
    let services = try await composition.bootstrapPrimaryServices(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: 0,
        lifecycleState: readyAgentLifecycleStateV1(),
        statusPlatform: AgentHostStatusPlatformServicesV1(
            sampler: AgentProductStatusSamplerV1(),
            clock: AgentProductStatusClockV1(),
            initialGeneration: UUID()
        ),
        interactivePlatform: AgentInteractivePlatformServicesV1(
            visibleAdmission: AgentProductVisibleAdmissionV1(
                state: VisibleInteractiveAdmissionStateV0(
                    generation: UUID(),
                    revision: 1,
                    visibleMenuAppAvailable: true,
                    selectedDisplayID: UUID()
                )
            ),
            materials: AgentProductInteractiveMaterialsV1(),
            runtime: AgentProductInteractiveRuntimeV1()
        )
    )

    #expect(services.hostID == hostID)
    #expect(services.reconciliation.totalReconciled == 0)
    #expect(await composition.interactiveAuditWriter.health() == .healthy)
}

@Test func agentReleaseBootstrapRejectsMissingOrRecoveryFencedIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-identity-fence-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let securityStore = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let composition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )

    func bootstrap() async throws -> AgentPrimaryServicesV1 {
        try await composition.bootstrapPrimaryServices(
            registry: CapabilityRegistrySnapshotV1(
                generation: UUID(),
                capabilities: []
            ),
            providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
            wallNowUnixMilliseconds: 0,
            lifecycleState: readyAgentLifecycleStateV1(),
            statusPlatform: AgentHostStatusPlatformServicesV1(
                sampler: AgentProductStatusSamplerV1(),
                clock: AgentProductStatusClockV1(),
                initialGeneration: UUID()
            ),
            interactivePlatform: AgentInteractivePlatformServicesV1(
                visibleAdmission: AgentProductVisibleAdmissionV1(
                    state: VisibleInteractiveAdmissionStateV0(
                        generation: UUID(),
                        revision: 1,
                        visibleMenuAppAvailable: true,
                        selectedDisplayID: UUID()
                    )
                ),
                materials: AgentProductInteractiveMaterialsV1(),
                runtime: AgentProductInteractiveRuntimeV1()
            )
        )
    }

    await #expect(
        throws: AgentRequiredAuditCompositionErrorV1.hostIdentityUnavailable
    ) {
        _ = try await bootstrap()
    }
    let hostIdentity = try agentBootstrapHostIdentityV1()
    try await securityStore.establishHostIdentity(hostIdentity)
    let recoveryID = UUID()
    _ = try await securityStore.beginHostIdentityRecovery(
        intent: StoredHostIdentityRecoveryIntent(
            commandID: UUID(),
            recoveryID: recoveryID,
            reviewID: UUID(),
            expectedHostID: hostIdentity.hostID,
            expectedHostFingerprint: hostIdentity.hostFingerprint,
            cause: .keyUnavailable,
            reviewCreatedAtUnixMilliseconds: 0,
            reviewExpiresAtUnixMilliseconds: 300_000,
            confirmedAtUnixMilliseconds: 0
        ),
        occurredAtUnixMilliseconds: 1
    )
    await #expect(
        throws: AgentRequiredAuditCompositionErrorV1.hostIdentityUnavailable
    ) {
        _ = try await bootstrap()
    }
}

@Test func agentRootBoundStatusUsesExactHostAndLazyDurableSequence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-root-status-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let hostID = UUID()
    let generation = UUID()
    let provider = AgentRootBoundHostStatusProviderV1(
        hostID: hostID,
        store: store,
        platform: AgentHostStatusPlatformServicesV1(
            sampler: AgentProductStatusSamplerV1(),
            clock: AgentProductStatusClockV1(),
            initialGeneration: generation,
            validForMilliseconds: 4_000
        )
    )

    #expect(try await store.statusSequence() == nil)
    let first = try await provider.snapshot(hostState: .userSessionActive)
    let second = try await provider.snapshot(hostState: .userSessionLocked)
    #expect(first.hostID == hostID)
    #expect(first.generation == generation)
    #expect(first.revision == 0)
    #expect(first.validForMilliseconds == 4_000)
    #expect(second.hostID == hostID)
    #expect(second.generation == generation)
    #expect(second.revision == 1)
    #expect(second.hostState == .userSessionLocked)
    #expect(try await store.statusSequence()?.nextRevision == 2)
}

@Test func agentBootstrapIssuesNothingWhenProviderLoadOrValidationFails() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-provider-bootstrap-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        ),
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
    let descriptor = try agentBootstrapDescriptorV1()
    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [descriptor]
    )

    await #expect(throws: AgentIngressTestErrorV1.providerLoadFailed) {
        _ = try await composition.bootstrapPrimaryServices(
            hostIdentity: try agentBootstrapHostIdentityV1(),
            registry: registry,
            providerLoader: FailingAgentProviderLoaderV1(),
            wallNowUnixMilliseconds: 1_000,
            lifecycleState: readyAgentLifecycleStateV1(),
            status: AgentIngressStatusProviderV1(),
            interactive: AgentIngressInteractiveDispatcherV1()
        )
    }
    await #expect(throws: CapabilityRegistryPublicationErrorV1.missingProvider(
        descriptor.providerID
    )) {
        _ = try await composition.bootstrapPrimaryServices(
            hostIdentity: try agentBootstrapHostIdentityV1(),
            registry: registry,
            providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
            wallNowUnixMilliseconds: 1_000,
            lifecycleState: readyAgentLifecycleStateV1(),
            status: AgentIngressStatusProviderV1(),
            interactive: AgentIngressInteractiveDispatcherV1()
        )
    }
}

@Test func agentBootstrapReconcilesRestartBeforeIssuingPrimaryIngress() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-restart-bootstrap-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let securityStore = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let deviceID = UUID()
    let clientID = UUID()
    try await securityStore.commitPairing(
        pairingID: UUID(),
        record: StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            approvalPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
    )
    let descriptor = try agentBootstrapDescriptorV1()
    _ = try await securityStore.replaceDeviceGrants(
        deviceID,
        grants: CapabilityGrantSet([descriptor.capabilityID]),
        occurredAtUnixMilliseconds: 1_100
    )
    let identity = try await securityStore.deviceGrantIdentitySnapshot(deviceID)
    let operationIDs = [UUID(), UUID(), UUID()]
    for (index, operationID) in operationIDs.enumerated() {
        let record = try StoredDurableOperationRecord(
            operationID: operationID,
            deviceID: deviceID,
            clientID: clientID,
            requestDigest: Data(repeating: UInt8(index + 1), count: 32),
            state: .queued,
            capabilityID: descriptor.capabilityID,
            schemaVersion: descriptor.schemaVersion,
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision,
            authorizationEpoch:
                identity.device.authorization.authorizationEpoch.rawValue,
            grantRevision: identity.device.authorization.grantRevision.rawValue,
            policyRevision: identity.device.policyRevision.rawValue,
            requiredHostState: .userSessionActive,
            expiresAtUnixMilliseconds: 10_000,
            createdAtUnixMilliseconds: 1_200,
            updatedAtUnixMilliseconds: 1_200
        )
        _ = try await securityStore.admitDurableOperation(record)
    }
    for operationID in operationIDs.dropFirst() {
        _ = try await securityStore.claimDurableOperationExecution(
            operationID,
            snapshot: DurableOperationExecutionSnapshot(
                providerGeneration: descriptor.providerGeneration,
                executionRevision: descriptor.executionRevision,
                hostState: .userSessionActive,
                nowUnixMilliseconds: 1_300
            )
        )
    }
    _ = try await securityStore.transitionDurableOperation(
        operationIDs[2],
        to: .cancelRequested,
        occurredAtUnixMilliseconds: 1_400
    )

    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [descriptor]
    )
    let loader = StaticAgentCapabilityProviderLoaderV1(
        providers: [AgentBootstrapProviderV1(descriptor: descriptor)]
    )
    let faultingComposition = AgentRequiredAuditCompositionV0(
        securityStore: try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path,
            injectedFaults: [.beforeSecurityEvent]
        ),
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("fault-audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("fault-deny.latch")
        )
    )
    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        _ = try await faultingComposition.bootstrapPrimaryServices(
            hostIdentity: try agentBootstrapHostIdentityV1(),
            registry: registry,
            providerLoader: loader,
            wallNowUnixMilliseconds: 1_900,
            lifecycleState: readyAgentLifecycleStateV1(),
            status: AgentIngressStatusProviderV1(),
            interactive: AgentIngressInteractiveDispatcherV1()
        )
    }
    #expect(try await securityStore.durableOperation(operationIDs[0])?.state
        == .queued)
    #expect(try await securityStore.durableOperation(operationIDs[1])?.state
        == .running)
    #expect(try await securityStore.durableOperation(operationIDs[2])?.state
        == .cancelRequested)

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
    let bootstrapped = try await composition.bootstrapPrimaryServices(
        hostIdentity: try agentBootstrapHostIdentityV1(),
        registry: registry,
        providerLoader: loader,
        wallNowUnixMilliseconds: 2_000,
        lifecycleState: readyAgentLifecycleStateV1(),
        status: AgentIngressStatusProviderV1(),
        interactive: AgentIngressInteractiveDispatcherV1()
    )

    #expect(bootstrapped.reconciliation
        == DurableOperationStartupReconciliation(
            queuedFailed: 1,
            inFlightOutcomeUnknown: 2
        ))
    #expect(try await securityStore.durableOperation(operationIDs[0])?.state
        == .failed)
    #expect(try await securityStore.durableOperation(operationIDs[1])?.state
        == .outcomeUnknown)
    #expect(try await securityStore.durableOperation(operationIDs[2])?.state
        == .outcomeUnknown)
}

@Test func agentAuditHealthSnapshotNamesOnlyTheDegradedProducer() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-audit-health-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        ),
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path,
            injectedFaults: [.beforeInsert]
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )

    let bootstrapped = try await composition.bootstrapPrimaryServices(
        hostIdentity: try agentBootstrapHostIdentityV1(),
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: 0,
        lifecycleState: readyAgentLifecycleStateV1(),
        status: AgentIngressStatusProviderV1(),
        interactive: AgentIngressInteractiveDispatcherV1()
    )
    #expect(bootstrapped.localServices.bootstrapReport.degradedSources.isEmpty)

    await composition.primarySessionAuditWriter.recordRejectedProof(
        proofMessageID: UUID(),
        observedAtUnixMilliseconds: 1
    )

    let snapshot = await composition.healthSnapshot()
    #expect(snapshot.requiresLocalRepair)
    #expect(snapshot.degradedProducers == [.primarySession])

    await composition.refreshLocalStatusAuditHealth(
        bootstrapped.localServices
    )
    let coherent = try await bootstrapped.localServices.statusReader.read()
    #expect(coherent.securityPosture == .nominal)
    #expect(coherent.warningCodes == [.auditHistoryDegraded])
}

@Test func securityAdministrationFenceClosesAndLifecycleCannotReopenIngress()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-security-fence-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        ),
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
    let services = try await composition.bootstrapPrimaryServices(
        hostIdentity: try agentBootstrapHostIdentityV1(),
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: 0,
        lifecycleState: readyAgentLifecycleStateV1(),
        status: AgentIngressStatusProviderV1(),
        interactive: AgentIngressInteractiveDispatcherV1()
    )
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: try CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: spki
        )
    )
    let current = try await services.primarySessions.open(
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 0
    )

    await services.primarySessions.fenceForSecurityAdministration()
    #expect(await current.phase == .closed)
    #expect(await services.primarySessions
        .isSecurityAdministrationIngressDenied())
    await services.primarySessions.setLifecycleIngressEnabled(true)
    await #expect(
        throws: AgentPrimarySessionAuthorityErrorV1
            .securityAdministrationUnavailable
    ) {
        _ = try await services.primarySessions.open(
            tlsBinding: binding,
            acceptedAtMonotonicMilliseconds: 1
        )
    }

    await services.primarySessions.releaseSecurityAdministrationFence()
    let reopened = try await services.primarySessions.open(
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 2
    )
    #expect(await reopened.phase == .awaitingHello)
}

@Test func agentBootstrapCompletesPendingReviewedRevocationBeforeIngress()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-agent-revoke-bootstrap-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let securityStore = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let deviceID = UUID()
    let clientID = UUID()
    let displayName = try DeviceDisplayName("Bootstrap iPhone")
    try await securityStore.commitPairing(
        pairingID: UUID(),
        record: StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            approvalPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        ),
        displayName: displayName
    )
    let intent = try StoredDeviceRevocationIntent(
        commandID: UUID(),
        reviewID: UUID(),
        deviceID: deviceID,
        deviceDisplayName: displayName,
        reviewedState: .activeMonitorOnly,
        authorizationEpoch: .init(rawValue: 1),
        grantRevision: .init(rawValue: 1),
        reviewCreatedAtUnixMilliseconds: 1_100,
        reviewExpiresAtUnixMilliseconds: 301_100,
        confirmedAtUnixMilliseconds: 1_200
    )
    #expect(try await securityStore.beginDeviceRevocation(intent) == .prepared)
    let latch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("emergency-deny.latch")
    )
    #expect(try await latch.snapshot().health == .clear)

    let composition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: latch
    )
    let services = try await composition.bootstrapPrimaryServices(
        hostIdentity: try agentBootstrapHostIdentityV1(),
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: 2_000,
        lifecycleState: readyAgentLifecycleStateV1(),
        status: AgentIngressStatusProviderV1(),
        interactive: AgentIngressInteractiveDispatcherV1()
    )

    #expect(try await securityStore.device(deviceID)?.authorization.state
        == .revoked)
    #expect(try await securityStore.deviceRevocationRecord(
        commandID: intent.commandID
    )?.receipt?.completedAtUnixMilliseconds == 2_000)
    #expect(try await securityStore.securityEventCount() == 2)
    #expect(try await latch.snapshot().health == .clear)
    #expect(await services.primarySessions
        .isSecurityAdministrationIngressDenied() == false)
    let status = try await services.localServices.statusReader.read()
    #expect(status.pairedDeviceCount == 0)
    #expect(status.securityPosture == .nominal)
}

@Test func agentBootstrapConvergesCompletedAndLegacyRevocationLatches()
    async throws
{
    for durableReceiptExists in [false, true] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "maccompanion-agent-revoke-latch-\(UUID())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        )
        let deviceID = UUID()
        let displayName = try DeviceDisplayName("Recovery iPhone")
        try await store.commitPairing(
            pairingID: UUID(),
            record: StoredDeviceRecord(
                deviceID: deviceID,
                clientID: UUID(),
                sessionPublicKeyX963: P256.Signing.PrivateKey()
                    .publicKey.x963Representation,
                approvalPublicKeyX963: P256.Signing.PrivateKey()
                    .publicKey.x963Representation,
                authorization: DeviceAuthorization(
                    state: .activeMonitorOnly,
                    authorizationEpoch: .init(rawValue: 1),
                    grantRevision: .init(rawValue: 1)
                ),
                policyRevision: .init(rawValue: 1),
                createdAtUnixMilliseconds: 1_000,
                updatedAtUnixMilliseconds: 1_000
            ),
            displayName: displayName
        )
        if durableReceiptExists {
            let intent = try StoredDeviceRevocationIntent(
                commandID: UUID(),
                reviewID: UUID(),
                deviceID: deviceID,
                deviceDisplayName: displayName,
                reviewedState: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1),
                reviewCreatedAtUnixMilliseconds: 1_100,
                reviewExpiresAtUnixMilliseconds: 301_100,
                confirmedAtUnixMilliseconds: 1_200
            )
            _ = try await store.beginDeviceRevocation(intent)
            _ = try await store.completeDeviceRevocation(
                intent,
                occurredAtUnixMilliseconds: 1_500
            )
        }
        let latch = try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
        _ = try await latch.activate(
            pendingDeviceID: deviceID,
            reason: .revocationInProgress,
            recordedAtUnixMilliseconds: 1_500
        )
        let composition = AgentRequiredAuditCompositionV0(
            securityStore: store,
            detailedAuditStore: try SQLiteBoundedAuditStoreV0(
                path: directory.appendingPathComponent("audit.sqlite3").path
            ),
            denyLatch: latch
        )

        let services = try await composition.bootstrapPrimaryServices(
            hostIdentity: try agentBootstrapHostIdentityV1(),
            registry: CapabilityRegistrySnapshotV1(
                generation: UUID(),
                capabilities: []
            ),
            providerLoader: StaticAgentCapabilityProviderLoaderV1(
                providers: []
            ),
            wallNowUnixMilliseconds: 2_000,
            lifecycleState: readyAgentLifecycleStateV1(),
            status: AgentIngressStatusProviderV1(),
            interactive: AgentIngressInteractiveDispatcherV1()
        )
        #expect(try await store.device(deviceID)?.authorization.state
            == .revoked)
        #expect(try await store.securityEventCount() == 2)
        #expect(try await latch.snapshot().health == .clear)
        #expect(await services.primarySessions
            .isSecurityAdministrationIngressDenied() == false)
    }
}
