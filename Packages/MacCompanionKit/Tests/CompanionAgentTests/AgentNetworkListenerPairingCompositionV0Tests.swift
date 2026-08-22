import CompanionAgent
@testable import CompanionAgentNetworkPlatform
import CompanionDiscovery
import CompanionDomain
import CompanionHost
import CompanionHostSession
import CompanionHostWire
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionLifecycle
import CompanionNativeProviders
import CompanionPersistence
@testable import CompanionHostPlatform
import CompanionNetworkPlatform
import CompanionOperations
import CompanionPairing
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Security
import Testing

private let listenerPairingIssuanceTimeV0: Int64 = 1_724_000_000_000

private actor ListenerPairingSurfaceV0: LocalPairingReviewSurfaceV0 {
    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {}

    func withdrawLocalPairingReview(reviewID: UUID) async {}
}

private enum ListenerPairingProductProbeErrorV0: Error {
    case unused
}

private struct NetworkProductStartupMuteControllerV1:
    DefaultOutputMuteControllingV1
{
    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool { desired }
}

private struct ListenerPairingProductStatusV0:
    HostStatusSnapshotProvidingV0
{
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        throw ListenerPairingProductProbeErrorV0.unused
    }
}

private actor ListenerPairingProductInteractiveV0:
    AuthenticatedInteractiveWireDispatchingV0
{
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw ListenerPairingProductProbeErrorV0.unused
    }

    func primarySessionClosed() async {}
}

private func listenerPairingIssuedIdentityV0() throws
    -> SecurityHostIssuedIdentityV0
{
    let softwareKey = P256.Signing.PrivateKey()
    var creationError: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateWithData(
        softwareKey.x963Representation as CFData,
        [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ] as CFDictionary,
        &creationError
    ) else {
        let error = creationError?.takeRetainedValue()
        throw error ?? CocoaError(.featureUnsupported)
    }
    return try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(
        privateKey: privateKey,
        applicationTag: Data("example.listener-pairing.ephemeral".utf8),
        serialNumber: Data(repeating: 0x31, count: 16),
        issuanceTimeUnixMilliseconds: listenerPairingIssuanceTimeV0
    )
}

private struct ListenerPairingIdentityFixtureV0 {
    let issued: SecurityHostIssuedIdentityV0
    let configuration: NetworkHostTLSListenerConfigurationV0
    let stored: StoredHostIdentityRecord
}

private func listenerPairingIdentityFixtureV0() throws
    -> ListenerPairingIdentityFixtureV0
{
    let issued = try listenerPairingIssuedIdentityV0()
    let configuration = try NetworkHostTLSListenerConfigurationV0(
        issuedIdentity: issued,
        requiredHostFingerprint: issued.key.hostFingerprint,
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0
    )
    let stored = try StoredHostIdentityRecord(
        hostID: UUID(),
        keyApplicationTag: issued.key.applicationTag,
        hostFingerprint: issued.key.hostFingerprint,
        certificateDER: issued.certificateDER,
        certificateNotBeforeUnixMilliseconds:
            issued.validity.notBeforeUnixMilliseconds,
        certificateNotAfterUnixMilliseconds:
            issued.validity.notAfterUnixMilliseconds,
        establishedAtUnixMilliseconds: listenerPairingIssuanceTimeV0,
        updatedAtUnixMilliseconds: listenerPairingIssuanceTimeV0
    )
    return ListenerPairingIdentityFixtureV0(
        issued: issued,
        configuration: configuration,
        stored: stored
    )
}

private func listenerPairingConfigurationV0() throws
    -> NetworkHostTLSListenerConfigurationV0
{
    try listenerPairingIdentityFixtureV0().configuration
}

@Test func listenerPairingFactoryBindsExactIdentityBonjourAndPort() async throws {
    let configuration = try listenerPairingConfigurationV0()
    let ipv4 = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.30.50",
        port: 47_474
    )
    let composition = try AgentNetworkListenerPairingCompositionFactoryV0.make(
        configuration: configuration,
        port: 47_474,
        additionalEndpoints: [ipv4]
    )
    try await composition.pairingContext.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    try await composition.pairingContext.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    let context = try await composition.pairingContext.currentPairingContext()

    #expect(context.hostFingerprint == configuration.hostFingerprint)
    #expect(context.endpoints.contains(ipv4))
    let bonjour = try #require(context.endpoints.first {
        $0.kind == .bonjour
    })
    #expect(bonjour.port == 47_474)
    #expect(
        bonjour.value
            == "\(configuration.bonjourFacts.instanceName)."
                + "\(configuration.bonjourFacts.serviceType)."
                + configuration.bonjourFacts.domain
    )
}

@Test func listenerPairingFactoryRejectsMismatchedRoutesBeforeConsumption() throws {
    let configuration = try listenerPairingConfigurationV0()
    #expect(
        throws: AgentNetworkListenerPairingCompositionErrorV0.invalidPort
    ) {
        _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
            configuration: configuration,
            port: 0
        )
    }
    let wrongPort = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.30.50",
        port: 47_475
    )
    #expect(
        throws: AgentNetworkListenerPairingCompositionErrorV0
            .invalidAdditionalEndpoint
    ) {
        _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
            configuration: configuration,
            port: 47_474,
            additionalEndpoints: [wrongPort]
        )
    }
    let callerAuthoredBonjour = try EndpointCandidate(
        kind: .bonjour,
        value: "other._maccompanion._tcp.local.",
        port: 47_474
    )
    #expect(
        throws: AgentNetworkListenerPairingCompositionErrorV0
            .invalidAdditionalEndpoint
    ) {
        _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
            configuration: configuration,
            port: 47_474,
            additionalEndpoints: [callerAuthoredBonjour]
        )
    }

    _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
        configuration: configuration,
        port: 47_474
    )
}

@Test func listenerPairingFactoryPreservesSingleUseListenerConfiguration() throws {
    let configuration = try listenerPairingConfigurationV0()
    _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
        configuration: configuration,
        port: 47_474
    )
    #expect(
        throws: NetworkHostTLSListenerConfigurationErrorV0
            .listenerAlreadyCreated
    ) {
        _ = try AgentNetworkListenerPairingCompositionFactoryV0.make(
            configuration: configuration,
            port: 47_474
        )
    }
}

@Test func pairingProductFactoryUsesOneListenerContextAndAuditedAuthority() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-pairing-product-\(UUID())",
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
    let denyLatch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("emergency-deny.latch")
    )
    let auditComposition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: denyLatch
    )
    let identity = try listenerPairingIdentityFixtureV0()
    let primary = try await auditComposition.bootstrapPrimaryServices(
        hostIdentity: identity.stored,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        status: ListenerPairingProductStatusV0(),
        interactive: ListenerPairingProductInteractiveV0()
    )
    let configuration = identity.configuration
    let pairingID = UUID()
    let wallNow = listenerPairingIssuanceTimeV0 + 1_000
    let product = try AgentNetworkPairingProductCompositionFactoryV0.make(
        configuration: configuration,
        port: 47_474,
        primaryServices: primary,
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: wallNow,
            monotonicNowMilliseconds: 1_000
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 1)
        ),
        alreadyAuthorizedSurface: ListenerPairingSurfaceV0(),
        pairingIDGenerator: { pairingID }
    )

    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await product.localPairingSessions.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    try await product.pairingContext.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    try await product.pairingContext.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    let created = try await product.localPairingSessions.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    let decoded = try PairingQRCodeCodec.decode(
        created.encodedQRCode,
        nowUnixMilliseconds: wallNow
    )
    #expect(decoded.pairingID.rawValue == pairingID)
    #expect(decoded.hostFingerprint.rawValue == configuration.hostFingerprint)
    #expect(decoded.endpoints.count == 1)
    #expect(decoded.endpoints.first?.kind == .bonjour)
    #expect(decoded.endpoints.first?.port == 47_474)
}

@Test func pairingProductFactoryRejectsCrossWiredDurableAndTLSIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-product-identity-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let auditComposition = AgentRequiredAuditCompositionV0(
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
    let durableIdentity = try listenerPairingIdentityFixtureV0()
    let primary = try await auditComposition.bootstrapPrimaryServices(
        hostIdentity: durableIdentity.stored,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        status: ListenerPairingProductStatusV0(),
        interactive: ListenerPairingProductInteractiveV0()
    )
    let otherTLSIdentity = try listenerPairingIdentityFixtureV0()

    #expect(
        throws: AgentNetworkPairingProductCompositionErrorV0
            .hostIdentityMismatch
    ) {
        _ = try AgentNetworkPairingProductCompositionFactoryV0.make(
            configuration: otherTLSIdentity.configuration,
            port: 47_474,
            primaryServices: primary,
            timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
                wallNowUnixMilliseconds:
                    listenerPairingIssuanceTimeV0 + 1_000,
                monotonicNowMilliseconds: 1_000
            )),
            policySource: StaticAgentLocalPairingPolicySourceV0(
                .init(rawValue: 1)
            ),
            alreadyAuthorizedSurface: ListenerPairingSurfaceV0()
        )
    }
}

@Test func authorizedSurfaceLossTerminallyRetiresWholePairingProduct() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-product-loss-\(UUID())",
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
    let denyLatch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("emergency-deny.latch")
    )
    let auditComposition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: denyLatch
    )
    let identity = try listenerPairingIdentityFixtureV0()
    let primary = try await auditComposition.bootstrapPrimaryServices(
        hostIdentity: identity.stored,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: StaticAgentCapabilityProviderLoaderV1(providers: []),
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        status: ListenerPairingProductStatusV0(),
        interactive: ListenerPairingProductInteractiveV0()
    )
    let pairingID = UUID()
    let product = try AgentNetworkPairingProductCompositionFactoryV0.make(
        configuration: identity.configuration,
        port: 47_474,
        primaryServices: primary,
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0 + 1_000,
            monotonicNowMilliseconds: 1_000
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 1)
        ),
        alreadyAuthorizedSurface: ListenerPairingSurfaceV0(),
        pairingIDGenerator: { pairingID }
    )
    let listenerService = try await product.makeListenerService(
        queue: DispatchQueue(label: "maccompanion.pairing-product-loss"),
        monotonicNowMilliseconds: { 1_000 },
        primaryContext: {
            NetworkHostRequestContextV0(
                hostState: .userSessionActive,
                wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0 + 1_000,
                monotonicNowMilliseconds: 1_000,
                responseMessageID: WireUUID(UUID())
            )
        },
        pairingRequestContext: {
            NetworkHostPairingRequestContextV0(
                wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0 + 1_000,
                monotonicNowMilliseconds: 1_000,
                responseMessageID: WireUUID(UUID())
            )
        }
    )
    try await product.pairingContext.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    try await product.pairingContext.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    _ = try await product.localPairingSessions.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )

    await product.authorizedSurfaceLost()
    await product.authorizedSurfaceLost()

    #expect(await product.snapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: true,
            terminal: true
        ))
    #expect(await listenerService.snapshot().state == .terminal)
    #expect(await product.pairingContext.snapshot().terminal)
    let unavailableReview = try LocalPairingReviewV0(
        reviewID: UUID(),
        pairingID: pairingID,
        clientID: UUID(),
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x21, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x31, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x41, count: 32)),
        authenticationString: try PairingAuthenticationString("ABC-DEF"),
        expectedPolicyRevision: .init(rawValue: 1),
        expiresAtUnixMilliseconds: listenerPairingIssuanceTimeV0 + 300_000
    )
    await #expect(
        throws: AgentLocalPairingReviewServiceErrorV0.invalidated
    ) {
        try await product.localPairingReviews.publishHostPairingReview(
            unavailableReview
        )
    }
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await product.localPairingSessions.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await product.pairingServices.authority.begin(
            pairingID: pairingID,
            clientID: UUID(),
            sessionPublicKeyX963:
                P256.Signing.PrivateKey().publicKey.x963Representation,
            approvalPublicKeyX963:
                P256.Signing.PrivateKey().publicKey.x963Representation,
            clientNonce: Data(repeating: 0x11, count: 32),
            monotonicNowMilliseconds: 1_001
        )
    }
    await #expect(
        throws: AgentNetworkPairingProductCompositionErrorV0.terminal
    ) {
        _ = try await product.makeListenerService(
            queue: DispatchQueue(label: "maccompanion.pairing-product-reuse"),
            monotonicNowMilliseconds: { 1_001 },
            primaryContext: {
                NetworkHostRequestContextV0(
                    hostState: .userSessionActive,
                    wallNowUnixMilliseconds: 1,
                    monotonicNowMilliseconds: 1,
                    responseMessageID: WireUUID(UUID())
                )
            },
            pairingRequestContext: {
                NetworkHostPairingRequestContextV0(
                    wallNowUnixMilliseconds: 1,
                    monotonicNowMilliseconds: 1,
                    responseMessageID: WireUUID(UUID())
                )
            }
        )
    }
}

private enum NetworkProductStartupProbeErrorV0: Error {
    case unused
}

private struct NetworkProductStartupSamplerV0: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 1,
            cpuUtilizationBasisPoints: 1,
            memoryTotalBytes: 1,
            memoryUsedBytes: 1,
            storageTotalBytes: 1,
            storageAvailableBytes: 1,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

private struct NetworkProductStartupClockV0: HostStatusClock {
    func nowUnixMilliseconds() -> Int64 {
        listenerPairingIssuanceTimeV0
    }
}

private struct NetworkProductStartupVisibleAdmissionV0:
    VisibleInteractiveAdmissionReadingV0
{
    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0 {
        VisibleInteractiveAdmissionStateV0(
            generation: UUID(),
            revision: 1,
            visibleMenuAppAvailable: true,
            selectedDisplayID: UUID()
        )
    }
}

private struct NetworkProductStartupMaterialsV0:
    InteractiveSessionMaterialGeneratingV0
{
    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0 {
        throw NetworkProductStartupProbeErrorV0.unused
    }

    func bootstrapMaterials() async throws
        -> InteractiveSessionBootstrapMaterials
    {
        throw NetworkProductStartupProbeErrorV0.unused
    }
}

private actor NetworkProductStartupRuntimeV0:
    InteractiveSessionRuntimeOwningV0
{
    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        throw NetworkProductStartupProbeErrorV0.unused
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {}
}

private actor NetworkProductStartupCountingLoaderV0:
    AgentCapabilityProviderLoadingV1
{
    private var count = 0

    func loadProviders() async throws -> [any CapabilityProviderV1] {
        count += 1
        return []
    }

    func loadCount() -> Int { count }
}

private func networkProductStartupInputsV0(
    providerLoader: any AgentCapabilityProviderLoadingV1
) throws -> AgentNetworkProductStartupInputsV0 {
    AgentNetworkProductStartupInputsV0(
        port: 47_474,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: providerLoader,
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        statusPlatform: AgentHostStatusPlatformServicesV1(
            sampler: NetworkProductStartupSamplerV0(),
            clock: NetworkProductStartupClockV0(),
            initialGeneration: UUID()
        ),
        interactivePlatform: AgentInteractivePlatformServicesV1(
            visibleAdmission: NetworkProductStartupVisibleAdmissionV0(),
            materials: NetworkProductStartupMaterialsV0(),
            runtime: NetworkProductStartupRuntimeV0()
        ),
        pairingTimeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds:
                listenerPairingIssuanceTimeV0 + 1_000,
            monotonicNowMilliseconds: 1_000
        )),
        pairingPolicySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 1)
        ),
        alreadyAuthorizedSurface: ListenerPairingSurfaceV0()
    )
}

private func networkPrimaryStartupInputsV1(
    providerLoader: any AgentCapabilityProviderLoadingV1
) throws -> AgentNetworkPrimaryStartupInputsV1 {
    AgentNetworkPrimaryStartupInputsV1(
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: providerLoader,
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        statusPlatform: AgentHostStatusPlatformServicesV1(
            sampler: NetworkProductStartupSamplerV0(),
            clock: NetworkProductStartupClockV0(),
            initialGeneration: UUID()
        ),
        interactivePlatform: AgentInteractivePlatformServicesV1(
            visibleAdmission: NetworkProductStartupVisibleAdmissionV0(),
            materials: NetworkProductStartupMaterialsV0(),
            runtime: NetworkProductStartupRuntimeV0()
        )
    )
}

private func networkProductStartupAuditRootV0(
    directory: URL,
    securityStore: SQLiteSecurityStore
) throws -> AgentRequiredAuditCompositionV0 {
    AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path
        ),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("emergency-deny.latch")
        )
    )
}

@Test func networkPrimaryPreparationIsListenerFreeAndOneUse() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-primary-preparation-\(UUID())",
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
    let identity = try listenerPairingIdentityFixtureV0()
    try await store.establishHostIdentity(identity.stored)
    let loader = NetworkProductStartupCountingLoaderV0()

    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: try networkProductStartupAuditRootV0(
                directory: directory,
                securityStore: store
            ),
            inputs: try networkPrimaryStartupInputsV1(
                providerLoader: loader
            )
        ) else {
        Issue.record("expected prepared primary Agent root")
        return
    }
    #expect(await prepared.snapshot()
        == AgentPreparedPrimaryStartupSnapshotV1(
            hostID: identity.stored.hostID,
            consumed: false
        ))
    #expect(await loader.loadCount() == 1)

    let product = try await prepared.consumeForAuthorizedSurface(
        port: 47_474,
        additionalEndpoints: [],
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds:
                listenerPairingIssuanceTimeV0 + 1_000,
            monotonicNowMilliseconds: 1_000
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 1)
        ),
        alreadyAuthorizedSurface: ListenerPairingSurfaceV0()
    )
    #expect(product.primaryServices.hostID == identity.stored.hostID)
    #expect(await prepared.snapshot().consumed)
    await #expect(
        throws: AgentNetworkPairingProductCompositionErrorV0.terminal
    ) {
        _ = try await prepared.consumeForAuthorizedSurface(
            port: 47_474,
            additionalEndpoints: [],
            timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
                wallNowUnixMilliseconds:
                    listenerPairingIssuanceTimeV0 + 1_000,
                monotonicNowMilliseconds: 1_000
            )),
            policySource: StaticAgentLocalPairingPolicySourceV0(
                .init(rawValue: 1)
            ),
            alreadyAuthorizedSurface: ListenerPairingSurfaceV0()
        )
    }
    await product.authorizedSurfaceLost()
}

@Test func allNonreadyIdentityPreparationsSkipProviders() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-primary-nonready-\(UUID())",
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
    let requiredAudit = try networkProductStartupAuditRootV0(
        directory: directory,
        securityStore: store
    )

    let waitLoader = NetworkProductStartupCountingLoaderV0()
    guard case .waitForFirstUnlock = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: { .waitForFirstUnlock },
            requiredAudit: requiredAudit,
            inputs: try networkPrimaryStartupInputsV1(
                providerLoader: waitLoader
            )
        ) else {
        Issue.record("expected first-unlock wait")
        return
    }
    #expect(await waitLoader.loadCount() == 0)

    let recoveryLoader = NetworkProductStartupCountingLoaderV0()
    guard case .requireLocalRecovery(.missingEstablishedKey) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .requireLocalRecovery(.missingEstablishedKey)
            },
            requiredAudit: requiredAudit,
            inputs: try networkPrimaryStartupInputsV1(
                providerLoader: recoveryLoader
            )
        ) else {
        Issue.record("expected local recovery requirement")
        return
    }
    #expect(await recoveryLoader.loadCount() == 0)

    let fencedLoader = NetworkProductStartupCountingLoaderV0()
    let recoveryID = UUID()
    guard case .recoveryFenced(recoveryID) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: { .recoveryFenced(recoveryID) },
            requiredAudit: requiredAudit,
            inputs: try networkPrimaryStartupInputsV1(
                providerLoader: fencedLoader
            )
        ) else {
        Issue.record("expected fenced recovery")
        return
    }
    #expect(await fencedLoader.loadCount() == 0)
}

@Test func networkProductStartupBindsIdentityPrimaryAndListenerAsOneGraph()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-product-startup-\(UUID())",
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
    let identity = try listenerPairingIdentityFixtureV0()
    try await store.establishHostIdentity(identity.stored)
    let loader = NetworkProductStartupCountingLoaderV0()

    guard case let .ready(product) = try await
        AgentNetworkProductStartupFactoryV0.make(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: try networkProductStartupAuditRootV0(
                directory: directory,
                securityStore: store
            ),
            inputs: try networkProductStartupInputsV0(
                providerLoader: loader
            )
        ) else {
        Issue.record("expected ready Agent network product")
        return
    }
    #expect(product.primaryServices.hostID == identity.stored.hostID)
    #expect(await product.snapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: false,
            terminal: false
        ))
    #expect(await loader.loadCount() == 1)
}

@Test func networkProductStartupPublishesTheBoundNativeMVPProvider()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-native-mvp-startup-\(UUID())",
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
    let identity = try listenerPairingIdentityFixtureV0()
    try await store.establishHostIdentity(identity.stored)
    let generation = UUID()
    let native = try AgentNativeMVPProviderCompositionV1(
        registryGeneration: generation,
        audioMuteController: NetworkProductStartupMuteControllerV1()
    )
    let inputs = AgentNetworkProductStartupInputsV0(
        port: 47_474,
        nativeMVPProviders: native,
        wallNowUnixMilliseconds: listenerPairingIssuanceTimeV0,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        statusPlatform: AgentHostStatusPlatformServicesV1(
            sampler: NetworkProductStartupSamplerV0(),
            clock: NetworkProductStartupClockV0(),
            initialGeneration: UUID()
        ),
        interactivePlatform: AgentInteractivePlatformServicesV1(
            visibleAdmission: NetworkProductStartupVisibleAdmissionV0(),
            materials: NetworkProductStartupMaterialsV0(),
            runtime: NetworkProductStartupRuntimeV0()
        ),
        pairingTimeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds:
                listenerPairingIssuanceTimeV0 + 1_000,
            monotonicNowMilliseconds: 1_000
        )),
        pairingPolicySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 1)
        ),
        alreadyAuthorizedSurface: ListenerPairingSurfaceV0()
    )

    guard case let .ready(product) = try await
        AgentNetworkProductStartupFactoryV0.make(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: try networkProductStartupAuditRootV0(
                directory: directory,
                securityStore: store
            ),
            inputs: inputs
        ) else {
        Issue.record("expected ready native-MVP Agent network product")
        return
    }
    let registry = await product.primaryServices.capabilityAuthority
        .registrySnapshot()
    #expect(registry.generation == generation)
    #expect(registry.capabilities.map(\.capabilityID) == [
        NativeAudioMuteCapabilityV1.capabilityID,
    ])
    #expect(await product.primaryServices.capabilityAuthority
        .activeProviderCount() == 1)
}

@Test func nonreadyHostIdentityConstructsNoProviderOrNetworkProduct()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-product-wait-\(UUID())",
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
    let loader = NetworkProductStartupCountingLoaderV0()

    guard case .waitForFirstUnlock = try await
        AgentNetworkProductStartupFactoryV0.make(
            hostIdentityStartup: { .waitForFirstUnlock },
            requiredAudit: try networkProductStartupAuditRootV0(
                directory: directory,
                securityStore: store
            ),
            inputs: try networkProductStartupInputsV0(
                providerLoader: loader
            )
        ) else {
        Issue.record("expected closed first-unlock wait")
        return
    }
    #expect(await loader.loadCount() == 0)
    #expect(try await store.hostIdentity() == nil)
}

@Test func networkProductStartupRejectsIdentityChangedBeforeFinalConsumption()
    async throws
{
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-network-product-stale-\(UUID())",
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
    let durable = try listenerPairingIdentityFixtureV0()
    let stale = try listenerPairingIdentityFixtureV0()
    try await store.establishHostIdentity(durable.stored)

    await #expect(
        throws: AgentNetworkPairingProductCompositionErrorV0
            .hostIdentityMismatch
    ) {
        _ = try await AgentNetworkProductStartupFactoryV0.make(
            hostIdentityStartup: {
                .ready(
                    record: stale.stored,
                    issuedIdentity: stale.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: try networkProductStartupAuditRootV0(
                directory: directory,
                securityStore: store
            ),
            inputs: try networkProductStartupInputsV0(
                providerLoader: StaticAgentCapabilityProviderLoaderV1(
                    providers: []
                )
            )
        )
    }
}
