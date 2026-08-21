import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let pairingClientID = UUID(
    uuidString: "018f9200-0000-7000-8000-000000000001"
)!
private let pairingIdentifier = UUID(
    uuidString: "018f9200-0000-7000-8000-000000000002"
)!
private let pairedHostID = UUID(
    uuidString: "018f9200-0000-7000-8000-000000000003"
)!
private let pairedDeviceID = UUID(
    uuidString: "018f9200-0000-7000-8000-000000000004"
)!
private let pairingTestSPKI = Data((0x00...0x5a).map(UInt8.init))
private let pairingSecret = Data((0xc0...0xdf).map(UInt8.init))
private let pairingClientNonce = Data((0x10...0x2f).map(UInt8.init))
private let pairingHostNonce = Data((0x30...0x4f).map(UInt8.init))

private struct P256PairingSigner: ClientPairingSessionSigningV0 {
    let key: P256.Signing.PrivateKey

    func signPairingInput(_ input: Data) async throws -> Data {
        try key.signature(for: input).rawRepresentation
    }
}

private actor SuspendingPairingSigner: ClientPairingSessionSigningV0 {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var signatureContinuation:
        CheckedContinuation<Data, any Error>?

    func signPairingInput(_ input: Data) async throws -> Data {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            signatureContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        signatureContinuation?.resume(
            returning: Data(repeating: 0x5c, count: 64)
        )
        signatureContinuation = nil
    }
}

private func fixedPairingPrivateKey(_ scalar: UInt8) throws -> P256.Signing.PrivateKey {
    var bytes = Data(repeating: 0, count: 32)
    bytes[31] = scalar
    return try P256.Signing.PrivateKey(rawRepresentation: bytes)
}

private func pairingTestFingerprint() throws -> Data {
    try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: pairingTestSPKI
    )
}

private func pairingQR(
    expiresAtUnixMilliseconds: Int64 = 1_300_000
) throws -> PairingQRCodePayload {
    try PairingQRCodePayload(
        pairingID: WireUUID(pairingIdentifier),
        oneTimeSecret: WireBytes32(pairingSecret),
        expiresAtUnixMilliseconds: expiresAtUnixMilliseconds,
        hostFingerprint: WireFingerprint(pairingTestFingerprint()),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "mac-test._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
}

private func pairingPeerEvidence(
    spki: Data = pairingTestSPKI
) -> TLSPeerEvidence {
    TLSPeerEvidence(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: false,
        pinnedLeafPolicyAccepted: true,
        subjectPublicKeyInfoDER: spki
    )
}

private struct PairingClientFixture {
    let session: ClientPairingSessionV0
    let sessionKey: P256.Signing.PrivateKey
    let approvalKey: P256.Signing.PrivateKey
}

private func makePairingClient(
    qr: PairingQRCodePayload? = nil
) throws -> PairingClientFixture {
    let sessionKey = try fixedPairingPrivateKey(1)
    let approvalKey = try fixedPairingPrivateKey(2)
    return PairingClientFixture(
        session: try ClientPairingSessionV0(
            qr: try qr ?? pairingQR(),
            clientID: pairingClientID,
            sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
            approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
            signer: P256PairingSigner(key: sessionKey)
        ),
        sessionKey: sessionKey,
        approvalKey: approvalKey
    )
}

private func makeSuspendingPairingClient(
    signer: SuspendingPairingSigner
) throws -> PairingClientFixture {
    let sessionKey = try fixedPairingPrivateKey(1)
    let approvalKey = try fixedPairingPrivateKey(2)
    return PairingClientFixture(
        session: try ClientPairingSessionV0(
            qr: pairingQR(),
            clientID: pairingClientID,
            sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
            approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
            signer: signer
        ),
        sessionKey: sessionKey,
        approvalKey: approvalKey
    )
}

private func preparePairingChallenge(
    _ session: ClientPairingSessionV0
) async throws -> (Data, WireUUID) {
    try await session.didConnectTCP(
        wallNowUnixMilliseconds: 1_000_000,
        monotonicNowMilliseconds: 1_000
    )
    try await session.acceptPinnedPeer(pairingPeerEvidence(), at: 1_001)
    let beginID = WireUUID(UUID())
    _ = try await session.begin(
        clientNonce: WireBytes32(pairingClientNonce),
        messageID: beginID,
        sentAtUnixMilliseconds: 1_000_001,
        monotonicNowMilliseconds: 1_002
    )
    let challenge = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: beginID,
        sentAtUnixMilliseconds: 1_000_002,
        body: try PairingChallengeBody(
            hostNonce: WireBytes32(pairingHostNonce),
            hostFingerprint: WireFingerprint(pairingTestFingerprint())
        )
    )
    return (try WireCodec.encode(challenge), WireUUID(UUID()))
}

private struct ProvedPairingClient {
    let fixture: PairingClientFixture
    let prove: WireEnvelope<PairingProveBody>
    let proofMessageID: WireUUID
    let transcriptDigest: Data
    let authenticationString: String
}

private func advancePairingClientThroughProof() async throws -> ProvedPairingClient {
    let fixture = try makePairingClient()
    try await fixture.session.didConnectTCP(
        wallNowUnixMilliseconds: 1_000_000,
        monotonicNowMilliseconds: 1_000
    )
    try await fixture.session.acceptPinnedPeer(
        pairingPeerEvidence(),
        at: 1_001
    )
    let beginID = WireUUID(UUID())
    let beginData = try await fixture.session.begin(
        clientNonce: WireBytes32(pairingClientNonce),
        messageID: beginID,
        sentAtUnixMilliseconds: 1_000_001,
        monotonicNowMilliseconds: 1_002
    )
    let begin = try WireCodec.decode(
        WireEnvelope<PairingBeginBody>.self,
        from: beginData
    )
    #expect(begin.body.sessionPublicKey.rawValue
        == fixture.sessionKey.publicKey.x963Representation)
    #expect(begin.body.approvalPublicKey.rawValue
        == fixture.approvalKey.publicKey.x963Representation)

    let challengeID = WireUUID(UUID())
    let challenge = try WireEnvelope(
        messageID: challengeID,
        correlationID: beginID,
        sentAtUnixMilliseconds: 1_000_002,
        body: try PairingChallengeBody(
            hostNonce: WireBytes32(pairingHostNonce),
            hostFingerprint: WireFingerprint(pairingTestFingerprint())
        )
    )
    let proofID = WireUUID(UUID())
    let proofData = try await fixture.session.receiveChallenge(
        WireCodec.encode(challenge),
        proofMessageID: proofID,
        sentAtUnixMilliseconds: 1_000_003,
        monotonicNowMilliseconds: 1_003
    )
    let prove = try WireCodec.decode(
        WireEnvelope<PairingProveBody>.self,
        from: proofData
    )
    let transcript = try CompanionSecurityV0.pairingTranscriptInput(
        pairingID: pairingIdentifier,
        hostFingerprint: pairingTestFingerprint(),
        clientID: pairingClientID,
        sessionPublicKeyX963: fixture.sessionKey.publicKey.x963Representation,
        approvalPublicKeyX963: fixture.approvalKey.publicKey.x963Representation,
        clientNonce: pairingClientNonce,
        hostNonce: pairingHostNonce,
        selectedMajor: 0,
        selectedMinor: 1
    )
    let digest = CompanionSecurityV0.pairingTranscriptDigest(transcript)
    let sas = try CompanionSecurityV0.authenticationString(
        oneTimeSecret: pairingSecret,
        transcriptDigest: digest
    )
    return ProvedPairingClient(
        fixture: fixture,
        prove: prove,
        proofMessageID: proofID,
        transcriptDigest: digest,
        authenticationString: sas
    )
}

private func pendingPairingResponse(
    for proved: ProvedPairingClient,
    digest: Data? = nil,
    authenticationString: String? = nil,
    expiresAtUnixMilliseconds: Int64 = 1_300_000
) throws -> WireEnvelope<PairingPendingApprovalBody> {
    try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proved.proofMessageID,
        sentAtUnixMilliseconds: 1_000_004,
        body: try PairingPendingApprovalBody(
            transcriptDigest: WireBytes32(digest ?? proved.transcriptDigest),
            authenticationString: PairingAuthenticationString(
                authenticationString ?? proved.authenticationString
            ),
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds
        )
    )
}

@Test func clientPairingBindsProofSASAndFinalMonitorOnlyIdentity() async throws {
    let proved = try await advancePairingClientThroughProof()
    #expect(proved.prove.correlationID != nil)
    #expect(try CompanionSecurityV0.verifyPairingSecretProof(
        proved.prove.body.secretProof.rawValue,
        oneTimeSecret: pairingSecret,
        transcriptDigest: proved.transcriptDigest
    ))
    let signatureInput = try CompanionSecurityV0.pairingSignatureInput(
        transcriptDigest: proved.transcriptDigest
    )
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: proved.prove.body.signature.rawValue,
        signingInput: signatureInput,
        publicKeyX963: proved.fixture.sessionKey.publicKey.x963Representation
    ))

    let pending = try pendingPairingResponse(for: proved)
    let approval = try await proved.fixture.session.receivePendingApproval(
        WireCodec.encode(pending),
        wallNowUnixMilliseconds: 1_000_005,
        monotonicNowMilliseconds: 1_004
    )
    #expect(approval.transcriptDigest == proved.transcriptDigest)
    #expect(approval.authenticationString == proved.authenticationString)

    let complete = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proved.proofMessageID,
        sentAtUnixMilliseconds: 1_000_006,
        body: try PairingCompleteBody(
            hostID: WireUUID(pairedHostID),
            deviceID: WireUUID(pairedDeviceID),
            policyRevision: .init(rawValue: 7),
            hostFingerprint: WireFingerprint(pairingTestFingerprint())
        )
    )
    let result = try await proved.fixture.session.receiveCompletion(
        WireCodec.encode(complete),
        monotonicNowMilliseconds: 1_005
    )
    #expect(result.hostID == pairedHostID)
    #expect(result.deviceID == pairedDeviceID)
    #expect(result.deviceState == .activeMonitorOnly)
    #expect(result.authorizationEpoch.rawValue == 1)
    #expect(result.grantRevision.rawValue == 1)
    #expect(result.policyRevision.rawValue == 7)
    #expect(result.endpoints == (try pairingQR()).endpoints)
    #expect(await proved.fixture.session.phase == .paired)
    #expect(await proved.fixture.session.pinnedTLSPhase == .ready)
}

@Test func clientPairingNeverSendsBeforePinAndRejectsChallengePinMismatch() async throws {
    let premature = try makePairingClient().session
    await #expect(
        throws: ClientPairingSessionErrorV0.invalidPhase(.awaitingTCP)
    ) {
        _ = try await premature.begin(
            clientNonce: WireBytes32(pairingClientNonce),
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1,
            monotonicNowMilliseconds: 1
        )
    }
    #expect(await premature.phase == .closed)

    let fixture = try makePairingClient()
    try await fixture.session.didConnectTCP(
        wallNowUnixMilliseconds: 1_000_000,
        monotonicNowMilliseconds: 100
    )
    try await fixture.session.acceptPinnedPeer(pairingPeerEvidence(), at: 101)
    let beginID = WireUUID(UUID())
    _ = try await fixture.session.begin(
        clientNonce: WireBytes32(pairingClientNonce),
        messageID: beginID,
        sentAtUnixMilliseconds: 1_000_001,
        monotonicNowMilliseconds: 102
    )
    let mismatch = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: beginID,
        sentAtUnixMilliseconds: 1_000_002,
        body: try PairingChallengeBody(
            hostNonce: WireBytes32(pairingHostNonce),
            hostFingerprint: WireFingerprint(Data(repeating: 9, count: 32))
        )
    )
    await #expect(throws: ClientPairingSessionErrorV0.hostFingerprintMismatch) {
        _ = try await fixture.session.receiveChallenge(
            WireCodec.encode(mismatch),
            proofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_000_003,
            monotonicNowMilliseconds: 103
        )
    }
    #expect(await fixture.session.phase == .closed)
}

@Test func clientPairingRejectsPendingTranscriptSASAndExpiryMismatch() async throws {
    for response in [
        try pendingPairingResponse(
            for: await advancePairingClientThroughProof(),
            digest: Data(repeating: 1, count: 32)
        ),
    ] {
        let proved = try await advancePairingClientThroughProof()
        let mismatched = try WireEnvelope(
            messageID: response.messageID,
            correlationID: proved.proofMessageID,
            sentAtUnixMilliseconds: response.sentAtUnixMilliseconds,
            body: response.body
        )
        await #expect(throws: ClientPairingSessionErrorV0.transcriptMismatch) {
            _ = try await proved.fixture.session.receivePendingApproval(
                WireCodec.encode(mismatched),
                wallNowUnixMilliseconds: 1_000_005,
                monotonicNowMilliseconds: 1_004
            )
        }
    }

    let wrongSAS = try await advancePairingClientThroughProof()
    await #expect(
        throws: ClientPairingSessionErrorV0.authenticationStringMismatch
    ) {
        _ = try await wrongSAS.fixture.session.receivePendingApproval(
            WireCodec.encode(try pendingPairingResponse(
                for: wrongSAS,
                authenticationString: "000-000"
            )),
            wallNowUnixMilliseconds: 1_000_005,
            monotonicNowMilliseconds: 1_004
        )
    }

    let wrongExpiry = try await advancePairingClientThroughProof()
    await #expect(throws: ClientPairingSessionErrorV0.expiryMismatch) {
        _ = try await wrongExpiry.fixture.session.receivePendingApproval(
            WireCodec.encode(try pendingPairingResponse(
                for: wrongExpiry,
                expiresAtUnixMilliseconds: 1_299_999
            )),
            wallNowUnixMilliseconds: 1_000_005,
            monotonicNowMilliseconds: 1_004
        )
    }
}

@Test func clientPairingRejectsWrongCompletionFingerprintAndCorrelation() async throws {
    let wrongPin = try await advancePairingClientThroughProof()
    _ = try await wrongPin.fixture.session.receivePendingApproval(
        WireCodec.encode(try pendingPairingResponse(for: wrongPin)),
        wallNowUnixMilliseconds: 1_000_005,
        monotonicNowMilliseconds: 1_004
    )
    let completion = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: wrongPin.proofMessageID,
        sentAtUnixMilliseconds: 1_000_006,
        body: try PairingCompleteBody(
            hostID: WireUUID(pairedHostID),
            deviceID: WireUUID(pairedDeviceID),
            policyRevision: .init(rawValue: 1),
            hostFingerprint: WireFingerprint(Data(repeating: 8, count: 32))
        )
    )
    await #expect(throws: ClientPairingSessionErrorV0.hostFingerprintMismatch) {
        _ = try await wrongPin.fixture.session.receiveCompletion(
            WireCodec.encode(completion),
            monotonicNowMilliseconds: 1_005
        )
    }
    #expect(await wrongPin.fixture.session.pairedHost == nil)

    let wrongCorrelation = try await advancePairingClientThroughProof()
    _ = try await wrongCorrelation.fixture.session.receivePendingApproval(
        WireCodec.encode(try pendingPairingResponse(for: wrongCorrelation)),
        wallNowUnixMilliseconds: 1_000_005,
        monotonicNowMilliseconds: 1_004
    )
    let uncorrelated = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_000_006,
        body: try PairingCompleteBody(
            hostID: WireUUID(pairedHostID),
            deviceID: WireUUID(pairedDeviceID),
            policyRevision: .init(rawValue: 1),
            hostFingerprint: WireFingerprint(pairingTestFingerprint())
        )
    )
    await #expect(throws: ClientPairingSessionErrorV0.invalidCorrelation) {
        _ = try await wrongCorrelation.fixture.session.receiveCompletion(
            WireCodec.encode(uncorrelated),
            monotonicNowMilliseconds: 1_005
        )
    }
}

@Test func clientPairingDeadlineAndRemoteDenialAreTerminal() async throws {
    let expiringQR = try pairingQR(expiresAtUnixMilliseconds: 1_001_000)
    let expiring = try makePairingClient(qr: expiringQR).session
    try await expiring.didConnectTCP(
        wallNowUnixMilliseconds: 1_000_000,
        monotonicNowMilliseconds: 5_000
    )
    #expect(await expiring.nextDeadlineMonotonicMilliseconds() == 6_000)
    #expect(await !expiring.expireIfRequired(at: 5_999))
    #expect(await expiring.expireIfRequired(at: 6_000))
    #expect(await expiring.phase == .closed)

    let denied = try makePairingClient().session
    try await denied.didConnectTCP(
        wallNowUnixMilliseconds: 1_000_000,
        monotonicNowMilliseconds: 100
    )
    try await denied.acceptPinnedPeer(pairingPeerEvidence(), at: 101)
    let beginID = WireUUID(UUID())
    _ = try await denied.begin(
        clientNonce: WireBytes32(pairingClientNonce),
        messageID: beginID,
        sentAtUnixMilliseconds: 1_000_001,
        monotonicNowMilliseconds: 102
    )
    let error = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: beginID,
        sentAtUnixMilliseconds: 1_000_002,
        body: try ProtocolErrorResponseBody(
            code: "pairing.expired",
            retry: .afterUserAction
        )
    )
    await #expect(throws: ClientPairingSessionErrorV0.remoteError(
        code: "pairing.expired",
        retry: .afterUserAction
    )) {
        _ = try await denied.receiveChallenge(
            WireCodec.encode(error),
            proofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_000_003,
            monotonicNowMilliseconds: 103
        )
    }
    #expect(await denied.phase == .closed)
}

@Test func clientPairingCloseDuringSuspendedSigningCannotResurrectProof() async throws {
    let signer = SuspendingPairingSigner()
    let fixture = try makeSuspendingPairingClient(signer: signer)
    let (challenge, proofID) = try await preparePairingChallenge(
        fixture.session
    )

    let proofTask = Task {
        try await fixture.session.receiveChallenge(
            challenge,
            proofMessageID: proofID,
            sentAtUnixMilliseconds: 1_000_003,
            monotonicNowMilliseconds: 1_003
        )
    }
    await signer.waitUntilStarted()
    await fixture.session.close()
    await signer.resume()

    await #expect(
        throws: ClientPairingSessionErrorV0.invalidPhase(.closed)
    ) {
        _ = try await proofTask.value
    }
    #expect(await fixture.session.phase == .closed)
    #expect(await fixture.session.approval == nil)
    #expect(await fixture.session.nextDeadlineMonotonicMilliseconds() == nil)
}

@Test func clientPairingConcurrentProofCallTerminatesSuspendedSigning() async throws {
    let signer = SuspendingPairingSigner()
    let fixture = try makeSuspendingPairingClient(signer: signer)
    let (challenge, proofID) = try await preparePairingChallenge(
        fixture.session
    )

    let first = Task {
        try await fixture.session.receiveChallenge(
            challenge,
            proofMessageID: proofID,
            sentAtUnixMilliseconds: 1_000_003,
            monotonicNowMilliseconds: 1_003
        )
    }
    await signer.waitUntilStarted()
    await #expect(
        throws: ClientPairingSessionErrorV0.invalidPhase(.awaitingChallenge)
    ) {
        _ = try await fixture.session.receiveChallenge(
            challenge,
            proofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_000_004,
            monotonicNowMilliseconds: 1_004
        )
    }
    await signer.resume()
    await #expect(
        throws: ClientPairingSessionErrorV0.invalidPhase(.closed)
    ) {
        _ = try await first.value
    }

    #expect(await fixture.session.phase == .closed)
    #expect(await fixture.session.pairedHost == nil)
}
