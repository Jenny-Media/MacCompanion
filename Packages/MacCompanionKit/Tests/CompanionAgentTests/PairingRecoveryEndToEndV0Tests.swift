import CompanionAgent
import CompanionAuthentication
import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionIPC
import CompanionPairing
import CompanionPersistence
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private struct RecoveryE2ESignerV0: ClientPairingSessionSigningV0 {
    let key: P256.Signing.PrivateKey

    func signPairingInput(_ input: Data) async throws -> Data {
        try key.signature(for: input).rawRepresentation
    }
}

private struct RecoveryE2EUnusedPairingAuthorityV0:
    AgentHostPairingAuthorityV0
{
    func beginHostPairing(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingChallenge {
        throw PairingSessionError.notFound
    }

    func proveHostPairing(
        pairingID: UUID,
        secretProof: Data,
        signature: Data,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingApprovalContext {
        throw PairingSessionError.notFound
    }

    func cancelHostPairing(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {}
}

private struct RecoveryE2EUnusedDecisionsV0:
    AgentHostPairingDecisionHandlingV0
{
    func registerHostPairingReview(
        _ context: PairingApprovalContext,
        reviewID: UUID
    ) async throws -> LocalPairingReviewV0 {
        throw PairingSessionError.notFound
    }

    func resolveHostPairingOutcome(
        reviewID: UUID,
        expirePendingAtMonotonicMilliseconds: Int64?
    ) async -> AgentHostPairingOutcomeResolutionV0 {
        .unavailable
    }

    func cancelHostPairingReview(
        reviewID: UUID,
        monotonicNowMilliseconds: Int64
    ) async {}
}

private struct RecoveryE2EUnusedPublisherV0:
    AgentHostPairingReviewPublishingV0
{
    func publishHostPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {}

    func withdrawHostPairingReview(reviewID: UUID) async {}
}

@Test func lostPairingCompletionRecoversExactDurableDeviceEndToEnd() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-recovery-e2e-\(UUID())",
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
    let pairingID = UUID()
    let clientID = UUID()
    let hostID = UUID()
    let deviceID = UUID()
    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let sessionReference = try ClientSigningKeyReferenceV0(UUID())
    let approvalReference = try ClientSigningKeyReferenceV0(UUID())
    let identity = try ClientPreparedIdentityV0(
        pairingID: pairingID,
        clientID: clientID,
        sessionKey: try ClientCustodiedPublicKeyV0(
            role: .session,
            reference: sessionReference,
            publicKeyX963: sessionKey.publicKey.x963Representation,
            protection: .afterFirstUnlockThisDeviceOnly
        ),
        approvalKey: try ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: approvalReference,
            publicKeyX963: approvalKey.publicKey.x963Representation,
            protection: .whenUnlockedThisDeviceOnlyUserPresence
        )
    )
    let authorization = try DeviceAuthorization()
        .applying(.startPairing)
        .applying(.commitMonitorOnlyPairing)
    try await store.commitPairing(
        pairingID: pairingID,
        record: StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
            approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
            authorization: authorization,
            policyRevision: .init(rawValue: 7),
            createdAtUnixMilliseconds: 1_787_198_400_000,
            updatedAtUnixMilliseconds: 1_787_198_400_000
        )
    )

    // This committed record models the exact interruption boundary: the Mac
    // committed, but the original pairing.complete frame was dropped.
    let hostKey = P256.Signing.PrivateKey()
    let hostSPKI = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostKey.publicKey.x963Representation
    )
    let hostFingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: hostSPKI
    )
    let endpoint = try EndpointCandidate(
        kind: .bonjour,
        value: "recovery._maccompanion._tcp.local.",
        port: 47_474
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: hostSPKI
        ),
        requiredHostFingerprint: hostFingerprint
    )
    let recovery = SQLiteAgentHostPairingRecoveryAuthorityV0(
        store: store,
        makeHostNonce: { Data(repeating: 0x52, count: 32) }
    )
    await #expect(throws: AgentPairingRecoveryErrorV0.unavailable) {
        _ = try await recovery.beginPairingRecovery(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
            approvalPublicKeyX963:
                P256.Signing.PrivateKey().publicKey.x963Representation
        )
    }
    let server = try AgentHostPairingWireSessionV0(
        hostID: hostID,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 1_000,
        authority: RecoveryE2EUnusedPairingAuthorityV0(),
        recovery: recovery,
        decisions: RecoveryE2EUnusedDecisionsV0(),
        reviewPublisher: RecoveryE2EUnusedPublisherV0()
    )
    let client = try ClientPairingRecoverySessionV0(
        identity: identity,
        hostFingerprint: hostFingerprint,
        endpoints: [endpoint],
        signer: RecoveryE2ESignerV0(key: sessionKey)
    )

    try await client.didConnectTCP(monotonicNowMilliseconds: 1_001)
    try await client.acceptPinnedPeer(
        TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: hostSPKI
        ),
        at: 1_002
    )
    let resume = try await client.resume(
        clientNonce: WireBytes32(Data(repeating: 0x41, count: 32)),
        messageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_787_198_400_100,
        monotonicNowMilliseconds: 1_003
    )
    let challenge = try await server.receive(
        requestJSON: resume,
        wallNowUnixMilliseconds: 1_787_198_400_101,
        monotonicNowMilliseconds: 1_004,
        responseMessageID: WireUUID(UUID())
    )
    let proof = try await client.receiveChallenge(
        challenge,
        proofMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_787_198_400_102,
        monotonicNowMilliseconds: 1_005
    )
    let completion = try await server.receive(
        requestJSON: proof,
        wallNowUnixMilliseconds: 1_787_198_400_103,
        monotonicNowMilliseconds: 1_006,
        responseMessageID: WireUUID(UUID())
    )
    let pairedHost = try await client.receiveCompletion(
        completion,
        monotonicNowMilliseconds: 1_007
    )

    #expect(pairedHost.hostID == hostID)
    #expect(pairedHost.deviceID == deviceID)
    #expect(pairedHost.deviceState == .activeMonitorOnly)
    #expect(pairedHost.authorizationEpoch.rawValue == 1)
    #expect(pairedHost.grantRevision.rawValue == 1)
    #expect(pairedHost.policyRevision.rawValue == 7)
    #expect(try ClientDurablePairedHostV0(host: pairedHost, identity: identity).deviceID == deviceID)
    #expect(try await store.pairingConsumptionDeviceID(pairingID) == deviceID)
    #expect(try await store.device(deviceID)?.clientID == clientID)

    let authentication = ApplicationAuthenticationAuthority(
        deviceReader: store
    )
    let authenticationClientNonce = Data(repeating: 0x61, count: 32)
    let authenticationChallenge = try await authentication.challenge(
        clientID: clientID,
        clientNonce: authenticationClientNonce,
        hostFingerprint: hostFingerprint,
        monotonicNowMilliseconds: 2_000,
        connectionID: Data(repeating: 0x62, count: 16),
        serverNonce: Data(repeating: 0x63, count: 32)
    )
    let authenticationInput = try CompanionSecurityV0.authenticationSigningInput(
        clientID: clientID,
        connectionID: authenticationChallenge.connectionID,
        clientNonce: authenticationClientNonce,
        serverNonce: authenticationChallenge.serverNonce,
        hostFingerprint: hostFingerprint,
        selectedMajor: authenticationChallenge.selectedMajor,
        selectedMinor: authenticationChallenge.selectedMinor
    )
    let principal = try await authentication.prove(
        connectionID: authenticationChallenge.connectionID,
        signature: try sessionKey.signature(
            for: authenticationInput
        ).rawRepresentation,
        monotonicNowMilliseconds: 2_001
    )
    #expect(principal.deviceID == deviceID)
    #expect(principal.clientID == clientID)
    #expect(principal.deviceState == .activeMonitorOnly)
}
