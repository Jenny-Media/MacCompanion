import CompanionAgent
import CompanionDiscovery
import CompanionDomain
import CompanionIPC
import CompanionLifecycle
import CompanionPairing
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Testing

private struct PairingProductZeroProvidersV0:
    AgentActiveProviderCountReadingV1
{
    func activeProviderCount() async -> Int { 0 }
}

private actor PairingProductSurfaceV0: LocalPairingReviewSurfaceV0 {
    private(set) var presented: [LocalPairingReviewV0] = []
    private(set) var withdrawn: [UUID] = []

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        presented.append(review)
    }

    func withdrawLocalPairingReview(reviewID: UUID) async {
        withdrawn.append(reviewID)
    }
}

@Test func pairingProductCompositionSharesDurableAuthorityReviewAndAudit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-product-\(UUID())",
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
    let denyLatch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("emergency-deny.latch")
    )
    let auditComposition = AgentRequiredAuditCompositionV0(
        securityStore: securityStore,
        detailedAuditStore: auditStore,
        denyLatch: denyLatch
    )
    let localServices = try await AgentLocalServiceRootV1.bootstrap(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        pairedDevices: securityStore,
        capabilities: PairingProductZeroProvidersV0(),
        denyLatch: denyLatch,
        auditHistoryDegraded: false
    )
    let pairingID = UUID()
    let deviceID = UUID()
    let clientID = UUID()
    let reviewID = UUID()
    let wallNow: Int64 = 1_787_198_400_100
    let monotonicNow: Int64 = 1_100
    let fingerprint = Data(0x20...0x3f)
    let endpoint = try EndpointCandidate(
        kind: .bonjour,
        value: "studio._maccompanion._tcp.local.",
        port: 47_474
    )
    let surface = PairingProductSurfaceV0()
    let services = auditComposition.makePairingServices(
        localServices: localServices,
        contextSource: StaticAgentLocalPairingContextSourceV0(try .init(
            hostFingerprint: fingerprint,
            endpoints: [endpoint]
        )),
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: wallNow,
            monotonicNowMilliseconds: monotonicNow
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 7)
        ),
        alreadyAuthorizedSurface: surface,
        pairingIDGenerator: { pairingID },
        deviceIDGenerator: { deviceID }
    )

    let created = try await services.localPairingSessions.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    let qr = try PairingQRCodeCodec.decode(
        created.encodedQRCode,
        nowUnixMilliseconds: wallNow
    )
    #expect(qr.pairingID.rawValue == pairingID)
    #expect(qr.hostFingerprint.rawValue == fingerprint)
    #expect(qr.endpoints == [endpoint])

    let sessionKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    let clientNonce = Data(repeating: 0x41, count: 32)
    let hostNonce = Data(repeating: 0x52, count: 32)
    let challenge = try await services.authority.begin(
        pairingID: pairingID,
        clientID: clientID,
        sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
        approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
        clientNonce: clientNonce,
        monotonicNowMilliseconds: monotonicNow + 1,
        hostNonce: hostNonce
    )
    let transcript = try CompanionSecurityV0.pairingTranscriptInput(
        pairingID: pairingID,
        hostFingerprint: fingerprint,
        clientID: clientID,
        sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
        approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
        clientNonce: clientNonce,
        hostNonce: challenge.hostNonce,
        selectedMajor: challenge.selectedMajor,
        selectedMinor: challenge.selectedMinor
    )
    let digest = CompanionSecurityV0.pairingTranscriptDigest(transcript)
    let approval = try await services.authority.prove(
        pairingID: pairingID,
        secretProof: try CompanionSecurityV0.pairingSecretProof(
            oneTimeSecret: qr.oneTimeSecret.rawValue,
            transcriptDigest: digest
        ),
        signature: try sessionKey.signature(
            for: CompanionSecurityV0.pairingSignatureInput(
                transcriptDigest: digest
            )
        ).rawRepresentation,
        monotonicNowMilliseconds: monotonicNow + 2
    )
    let review = try await services.decisions.registerCurrentPolicyReview(
        approval,
        reviewID: reviewID
    )
    try await services.localPairingReviews.publishHostPairingReview(review)
    #expect(await surface.presented == [review])

    let displayName = try DeviceDisplayName("Jenny's iPhone")
    let receipt = try await services.localPairingReviews.resolveLocalApproval(
        LocalPairingDecisionCommandV0(
            commandID: UUID(),
            review: review,
            deviceDisplayName: displayName,
            decision: .approve,
            decidedAtUnixMilliseconds: wallNow - 1
        )
    )
    #expect(receipt.decision == .approve)
    #expect(receipt.deviceID == deviceID)
    #expect(receipt.storedDisplayName == displayName)
    #expect(await surface.withdrawn == [reviewID])
    #expect(try await securityStore.device(deviceID)?.clientID == clientID)
    #expect(
        try await localServices.statusReader.read().pairedDeviceCount == 1
    )

    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [.pairingApproved])
    #expect(page.events.first?.draft.eventID == pairingID)
    #expect(page.events.first?.draft.subjectDeviceID == deviceID)
    #expect(await auditComposition.pairingAuditWriter.health() == .healthy)
}
