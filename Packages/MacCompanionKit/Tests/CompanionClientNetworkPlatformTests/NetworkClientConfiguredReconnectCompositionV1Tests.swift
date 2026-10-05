@testable import CompanionClient
@testable import CompanionClientNetworkPlatform
import CompanionDiscovery
import CompanionDomain
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Security
import Testing

private enum ReconnectCompositionTestErrorV1: Error {
    case unused
}

private actor ReconnectCompositionCustodyV1: ClientIdentityKeyCustodyV0 {
    private(set) var sessionReferences: [ClientSigningKeyReferenceV0] = []

    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        throw ReconnectCompositionTestErrorV1.unused
    }

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool {
        throw ReconnectCompositionTestErrorV1.unused
    }

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        sessionReferences.append(reference)
        return Data(repeating: 0x5A, count: 64)
    }

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        throw ReconnectCompositionTestErrorV1.unused
    }

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        throw ReconnectCompositionTestErrorV1.unused
    }
}

private actor ReconnectCompositionPersistenceV1:
    ClientPairedHostPersistenceV0
{
    func commitAtomically(
        _ record: ClientDurablePairedHostV0
    ) async throws -> ClientPairedHostCommitResultV0 {
        throw ReconnectCompositionTestErrorV1.unused
    }
}

private actor ReconnectCompositionInventoryV1:
    ClientPairedHostInventoryV1
{
    let host: ClientDurablePairedHostV0?

    init(host: ClientDurablePairedHostV0?) {
        self.host = host
    }

    func pairedHost(
        hostID: UUID
    ) async throws -> ClientDurablePairedHostV0? {
        guard host?.hostID == hostID else { return nil }
        return host
    }
}

private actor ReconnectCompositionRoutesV1:
    ClientConfiguredRoutePersistenceV1
{
    private var stored: ClientConfiguredRouteCatalogSnapshotV1?

    init(stored: ClientConfiguredRouteCatalogSnapshotV1?) {
        self.stored = stored
    }

    func snapshot(
        hostID: UUID
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1? {
        guard stored?.hostID == hostID else { return nil }
        return stored
    }

    func replaceAtomically(
        _ value: ClientConfiguredRouteCatalogSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> ClientConfiguredRouteCommitResultV1 {
        guard stored?.revision == expectedRevision else {
            throw ReconnectCompositionTestErrorV1.unused
        }
        stored = value
        return .replaced
    }
}

private func reconnectCompositionPairedHostV1(
    endpoint: EndpointCandidate
) throws -> ClientDurablePairedHostV0 {
    let pairingID = UUID()
    let clientID = UUID()
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let identity = try ClientPreparedIdentityV0(
        pairingID: pairingID,
        clientID: clientID,
        sessionKey: ClientCustodiedPublicKeyV0(
            role: .session,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: sessionKey.publicKey.x963Representation,
            protection: .afterFirstUnlockThisDeviceOnly
        ),
        approvalKey: ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: approvalKey.publicKey.x963Representation,
            protection: .whenUnlockedThisDeviceOnlyUserPresence
        )
    )
    return try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: clientID,
            hostID: UUID(),
            deviceID: UUID(),
            hostFingerprint: Data(repeating: 0x77, count: 32),
            endpoints: [endpoint],
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 2)
        ),
        identity: identity
    )
}

private func reconnectCompositionConfigurationV1(
    pairedHost: ClientDurablePairedHostV0,
    endpoint: EndpointCandidate
) throws -> ClientReconnectConfigurationV1 {
    let catalog = try ClientConfiguredRouteCatalogV1(records: [
        ClientConfiguredRouteRecordV1(
            configuredRouteID: try WireBytes16(
                Data(repeating: 0x11, count: 16)
            ),
            endpoint: endpoint,
            provenance: .directPrivateAddress
        ),
    ])
    return try ClientReconnectConfigurationV1(
        pairedHost: pairedHost,
        routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1(
            hostID: pairedHost.hostID,
            revision: 1,
            catalog: catalog
        )
    )
}

@Test(arguments: [InteractiveSessionConsentProfileV1.freshUserPresence, .trustedDevice])
func reconnectCompositionBindsExactDurableSessionKeyAndIdentity(profile: InteractiveSessionConsentProfileV1)
    async throws
{
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.40.10",
        port: 47_474
    )
    let pairedHost = try reconnectCompositionPairedHostV1(endpoint: endpoint)
    let configuration = try reconnectCompositionConfigurationV1(
        pairedHost: pairedHost,
        endpoint: endpoint
    )
    let custody = ReconnectCompositionCustodyV1()
    let runtime = NetworkClientReconnectRuntimeV1(
        custody: custody,
        sessionConsentProfile: profile,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1_724_000_000_000,
                monotonicNowMilliseconds: 1_000
            )
        },
        nonce: { try WireBytes32(Data(repeating: 0x22, count: 32)) },
        messageID: { WireUUID(UUID()) },
        pinnedLeafEvaluator: { _ in
            throw ReconnectCompositionTestErrorV1.unused
        },
        verificationQueue: DispatchQueue(
            label: "test.maccompanion.reconnect-verification"
        ),
        connectionQueue: DispatchQueue(
            label: "test.maccompanion.reconnect-connection"
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 0 }
    )

    let attempt = try NetworkClientConfiguredReconnectCompositionV1
        .makeRouteAttemptConfiguration(
            configuration: configuration,
            runtime: runtime
        )
    let signature = try await attempt.signer.signAuthenticationInput(
        Data([0x01])
    )

    #expect(signature == Data(repeating: 0x5A, count: 64))
    #expect(await custody.sessionReferences == [pairedHost.sessionKey.reference])
    #expect(await custody.sessionReferences != [pairedHost.approvalKey.reference])
    #expect(attempt.clientID == pairedHost.clientID)
    #expect(attempt.expectedHostID == pairedHost.hostID)
    #expect(attempt.expectedDeviceID == pairedHost.deviceID)
    #expect(attempt.primaryProduct != nil)
    if profile == .trustedDevice {
        let product = try #require(attempt.primaryProduct)
        _ = try await product.interactiveApprovalSigner.signSessionChallenge(Data([2]))
        #expect(await custody.sessionReferences == [pairedHost.sessionKey.reference, pairedHost.sessionKey.reference])
        #expect(runtime.replacingProductEvents(.discarding).sessionConsentProfile == .trustedDevice)
    }
    #expect(try attempt.configuredRoute(forExactEndpoint: endpoint)
        == configuration.catalog.records.first)
}

@Test func publicReconnectRuntimeConstructsFreshSystemMaterials() throws {
    let custody = ReconnectCompositionCustodyV1()
    let runtime = NetworkClientReconnectRuntimeV1(
        custody: custody,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1_724_000_000_000,
                monotonicNowMilliseconds: 1_000
            )
        },
        verificationQueue: DispatchQueue(
            label: "test.maccompanion.public-reconnect-verification"
        ),
        connectionQueue: DispatchQueue(
            label: "test.maccompanion.public-reconnect-connection"
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 0 }
    )

    let firstNonce = try runtime.nonce()
    let secondNonce = try runtime.nonce()
    let firstMessageID = runtime.messageID()
    let secondMessageID = runtime.messageID()

    #expect(firstNonce.rawValue.count == 32)
    #expect(secondNonce.rawValue.count == 32)
    #expect(firstNonce != secondNonce)
    #expect(firstMessageID != secondMessageID)
}

@Test func publicPairingCompositionConstructsScanningOwnerWithoutNetworkWork()
    async throws
{
    let owner = try NetworkClientPairingApplicationCompositionV0.makeOwner(
        clientID: UUID(),
        custody: ReconnectCompositionCustodyV1(),
        persistence: ReconnectCompositionPersistenceV1(),
        verificationQueue: DispatchQueue(
            label: "test.maccompanion.pairing-product-verification"
        ),
        connectionQueue: DispatchQueue(
            label: "test.maccompanion.pairing-product-connection"
        )
    )

    #expect(await owner.snapshot().phase == .scanning)
}

@Test func configuredRouteApplicationProductStartsPessimisticAndStoreBound()
    async throws
{
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.40.20",
        port: 47_474
    )
    let pairedHost = try reconnectCompositionPairedHostV1(endpoint: endpoint)
    let configuration = try reconnectCompositionConfigurationV1(
        pairedHost: pairedHost,
        endpoint: endpoint
    )
    let custody = ReconnectCompositionCustodyV1()
    let runtime = NetworkClientReconnectRuntimeV1(
        custody: custody,
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1_724_000_000_000,
                monotonicNowMilliseconds: 1_000
            )
        },
        nonce: { try WireBytes32(Data(repeating: 0x22, count: 32)) },
        messageID: { WireUUID(UUID()) },
        pinnedLeafEvaluator: { _ in
            throw ReconnectCompositionTestErrorV1.unused
        },
        verificationQueue: DispatchQueue(
            label: "test.maccompanion.application-verification"
        ),
        connectionQueue: DispatchQueue(
            label: "test.maccompanion.application-connection"
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 0 }
    )

    let product = try await
        NetworkClientConfiguredRouteApplicationProductFactoryV1.make(
            hostID: pairedHost.hostID,
            pairedHosts: ReconnectCompositionInventoryV1(host: pairedHost),
            routes: ReconnectCompositionRoutesV1(
                stored: configuration.routeSnapshot
            ),
            runtime: runtime,
            newRouteID: {
                try WireBytes16(Data(repeating: 0x44, count: 16))
            },
            roundID: { UUID() }
        )
    let lifecycle = await product.lifecycle.snapshot()
    let binding = await product.binding.snapshot()
    let primary = product.primaryState.snapshot()

    #expect(lifecycle.pairedHost == pairedHost)
    #expect(lifecycle.routeSnapshot == configuration.routeSnapshot)
    #expect(lifecycle.phase == .background)
    #expect(!lifecycle.reconnect.foreground)
    #expect(!lifecycle.reconnect.networkReachable)
    #expect(lifecycle.reconnect.reconnect.candidates == [endpoint])
    #expect(binding.phase == .pending)
    #expect(!binding.foreground)
    #expect(!binding.networkReachable)
    #expect(primary.hostID == pairedHost.hostID)
    #expect(primary.availability == .disconnected)
    #expect(primary.revision == 0)
    #expect(await custody.sessionReferences.isEmpty)

    try await product.binding.start()
    let running = await product.binding.snapshot()
    #expect(running.phase == .running)
    #expect(!running.hasStartedEligibleRound)
    await product.binding.close()
    #expect(await product.lifecycle.snapshot().phase == .closed)
}

@Test func configuredRouteApplicationProductFailsBeforeBindingWithoutState()
    async throws
{
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.40.21",
        port: 47_474
    )
    let pairedHost = try reconnectCompositionPairedHostV1(endpoint: endpoint)
    let runtime = NetworkClientReconnectRuntimeV1(
        custody: ReconnectCompositionCustodyV1(),
        clock: {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: 1_724_000_000_000,
                monotonicNowMilliseconds: 1_000
            )
        },
        nonce: { try WireBytes32(Data(repeating: 0x22, count: 32)) },
        messageID: { WireUUID(UUID()) },
        pinnedLeafEvaluator: { _ in
            throw ReconnectCompositionTestErrorV1.unused
        },
        verificationQueue: DispatchQueue(
            label: "test.maccompanion.missing-verification"
        ),
        connectionQueue: DispatchQueue(
            label: "test.maccompanion.missing-connection"
        ),
        monotonicNow: { 1_000 },
        jitterBasisPoints: { 0 }
    )

    await #expect(
        throws: ClientConfiguredRouteLifecycleErrorV1.missingCatalog
    ) {
        _ = try await
            NetworkClientConfiguredRouteApplicationProductFactoryV1.make(
                hostID: pairedHost.hostID,
                pairedHosts: ReconnectCompositionInventoryV1(
                    host: pairedHost
                ),
                routes: ReconnectCompositionRoutesV1(stored: nil),
                runtime: runtime
            )
    }
    await #expect(
        throws: ClientConfiguredRouteLifecycleErrorV1.missingPairedHost
    ) {
        _ = try await
            NetworkClientConfiguredRouteApplicationProductFactoryV1.make(
                hostID: pairedHost.hostID,
                pairedHosts: ReconnectCompositionInventoryV1(host: nil),
                routes: ReconnectCompositionRoutesV1(stored: nil),
                runtime: runtime
            )
    }
}
