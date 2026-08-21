import CompanionAgent
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

private let hostWirePairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000e1"
)!
private let hostWireClientID = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000e1"
)!
private let hostWireHostID = UUID(
    uuidString: "018f1000-0000-7000-8000-0000000000e1"
)!
private let hostWireDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-0000000000e1"
)!
private let hostWireReviewID = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000e1"
)!
private let hostWireWall: Int64 = 1_787_198_400_000
private let hostWireCreatedMonotonic: Int64 = 900
private let hostWireAcceptedMonotonic: UInt64 = 950
private let hostWireSecret = Data(repeating: 0x71, count: 32)
private let hostWireClientNonce = Data(repeating: 0x72, count: 32)

private actor HostWirePairingCommitterV0: PairingCommitter {
    private let suspendCommit: Bool
    private var commitStarted = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var values: [(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    )] = []

    init(suspendCommit: Bool = false) {
        self.suspendCommit = suspendCommit
    }

    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        if suspendCommit {
            commitStarted = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        values.append((pairingID, record, displayName))
    }

    func waitUntilCommitStarts() async {
        while !commitStarted { await Task.yield() }
    }

    func resumeCommit() {
        continuation?.resume()
        continuation = nil
    }
}

private enum HostWirePairingPublisherErrorV0: Error {
    case injected
}

private actor HostWirePairingReviewPublisherV0:
    AgentHostPairingReviewPublishingV0
{
    private let fail: Bool
    private var values: [LocalPairingReviewV0] = []
    private var withdrawnReviewIDs: [UUID] = []

    init(fail: Bool = false) {
        self.fail = fail
    }

    func publishHostPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        if fail { throw HostWirePairingPublisherErrorV0.injected }
        values.append(review)
    }

    func reviews() -> [LocalPairingReviewV0] { values }

    func withdrawHostPairingReview(reviewID: UUID) async {
        withdrawnReviewIDs.append(reviewID)
    }

    func withdrawals() -> [UUID] { withdrawnReviewIDs }
}

private actor SuspendingHostWirePairingReviewPublisherV0:
    AgentHostPairingReviewPublishingV0
{
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func publishHostPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func withdrawHostPairingReview(reviewID: UUID) async {}

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct HostWirePairingHarnessV0 {
    let session: AgentHostPairingWireSessionV0
    let decisions: AgentLocalPairingDecisionHandlerV0
    let committer: HostWirePairingCommitterV0
    let sessionKey: P256.Signing.PrivateKey
    let approvalKey: P256.Signing.PrivateKey
    let fingerprint: Data
}

private func hostWireTLSBindingV0() throws -> HostApplicationTLSBinding {
    let hostKey = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostKey.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    return try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
}

private func hostWirePairingHarnessV0(
    publisher: any AgentHostPairingReviewPublishingV0,
    suspendCommit: Bool = false
) async throws -> HostWirePairingHarnessV0 {
    let binding = try hostWireTLSBindingV0()
    let committer = HostWirePairingCommitterV0(
        suspendCommit: suspendCommit
    )
    let authority = PairingSessionAuthority(committer: committer)
    _ = try await authority.createSession(
        pairingID: hostWirePairingID,
        hostFingerprint: binding.hostFingerprint,
        wallNowUnixMilliseconds: hostWireWall,
        monotonicNowMilliseconds: hostWireCreatedMonotonic,
        oneTimeSecret: hostWireSecret
    )
    let decisions = AgentLocalPairingDecisionHandlerV0(
        authority: authority,
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: hostWireWall + 100,
            monotonicNowMilliseconds: 1_000
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            .init(rawValue: 7)
        ),
        makeDeviceID: { hostWireDeviceID }
    )
    let session = try AgentHostPairingWireSessionV0(
        hostID: hostWireHostID,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: hostWireAcceptedMonotonic,
        authority: authority,
        decisions: decisions,
        reviewPublisher: publisher,
        makeReviewID: { hostWireReviewID }
    )
    return HostWirePairingHarnessV0(
        session: session,
        decisions: decisions,
        committer: committer,
        sessionKey: P256.Signing.PrivateKey(),
        approvalKey: P256.Signing.PrivateKey(),
        fingerprint: binding.hostFingerprint
    )
}

private func hostWireBeginRequestV0(
    _ harness: HostWirePairingHarnessV0,
    messageID: WireUUID
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: messageID,
        correlationID: nil,
        sentAtUnixMilliseconds: hostWireWall + 1,
        body: PairingBeginBody(
            pairingID: WireUUID(hostWirePairingID),
            clientID: WireUUID(hostWireClientID),
            sessionPublicKey: try WireBytes65(
                harness.sessionKey.publicKey.x963Representation
            ),
            approvalPublicKey: try WireBytes65(
                harness.approvalKey.publicKey.x963Representation
            ),
            clientNonce: WireBytes32(hostWireClientNonce)
        )
    ))
}

private func hostWireProveRequestV0(
    _ harness: HostWirePairingHarnessV0,
    challengeJSON: Data,
    messageID: WireUUID,
    tamperProof: Bool = false
) throws -> Data {
    let challenge = try WireCodec.decode(
        WireEnvelope<PairingChallengeBody>.self,
        from: challengeJSON
    )
    let transcript = try CompanionSecurityV0.pairingTranscriptInput(
        pairingID: hostWirePairingID,
        hostFingerprint: harness.fingerprint,
        clientID: hostWireClientID,
        sessionPublicKeyX963:
            harness.sessionKey.publicKey.x963Representation,
        approvalPublicKeyX963:
            harness.approvalKey.publicKey.x963Representation,
        clientNonce: hostWireClientNonce,
        hostNonce: challenge.body.hostNonce.rawValue,
        selectedMajor: challenge.body.selectedVersion.major,
        selectedMinor: challenge.body.selectedVersion.minor
    )
    let digest = CompanionSecurityV0.pairingTranscriptDigest(transcript)
    var proof = try CompanionSecurityV0.pairingSecretProof(
        oneTimeSecret: hostWireSecret,
        transcriptDigest: digest
    )
    if tamperProof { proof[0] ^= 0xff }
    let signingInput = try CompanionSecurityV0.pairingSignatureInput(
        transcriptDigest: digest
    )
    let signature = try harness.sessionKey.signature(
        for: signingInput
    ).rawRepresentation
    return try WireCodec.encode(WireEnvelope(
        messageID: messageID,
        correlationID: challenge.messageID,
        sentAtUnixMilliseconds: hostWireWall + 2,
        body: PairingProveBody(
            secretProof: WireBytes32(proof),
            signature: try WireBytes64(signature)
        )
    ))
}

@Test func hostPairingWirePublishesReviewBeforeDurableCompletion() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(
        harness,
        messageID: WireUUID(UUID())
    )
    let challengeJSON = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challengeJSON,
        messageID: proofID
    )
    let pendingJSON = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let pending = try WireCodec.decode(
        WireEnvelope<PairingPendingApprovalBody>.self,
        from: pendingJSON
    )
    let review = try #require(await publisher.reviews().first)
    #expect(pending.correlationID == proofID)
    #expect(pending.body.transcriptDigest == review.transcriptDigest)
    #expect(pending.body.authenticationString == review.authenticationString)

    let completionMessageID = WireUUID(UUID())
    #expect(try await harness.session.takeCompletionIfAvailable(
        wallNowUnixMilliseconds: hostWireWall + 3,
        monotonicNowMilliseconds: 980,
        responseMessageID: completionMessageID
    ) == nil)
    let command = try LocalPairingDecisionCommandV0(
        commandID: UUID(),
        review: review,
        deviceDisplayName: DeviceDisplayName("Jenny's iPhone"),
        decision: .approve,
        decidedAtUnixMilliseconds: hostWireWall + 99
    )
    _ = try await harness.decisions.handle(command)
    let completionJSON = try #require(
        try await harness.session.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: hostWireWall + 100,
            monotonicNowMilliseconds: 1_000,
            responseMessageID: completionMessageID
        )
    )
    let completion = try WireCodec.decode(
        WireEnvelope<PairingCompleteBody>.self,
        from: completionJSON
    )
    #expect(completion.correlationID == proofID)
    #expect(completion.body.hostID.rawValue == hostWireHostID)
    #expect(completion.body.deviceID.rawValue == hostWireDeviceID)
    #expect(completion.body.hostFingerprint.rawValue == harness.fingerprint)
    #expect(await harness.committer.values.first?.displayName == command.deviceDisplayName)
    #expect(await publisher.withdrawals() == [review.reviewID])
    #expect(await harness.session.phase == .completed)
}

@Test func hostPairingWireDeclineReturnsClosedConsumedError() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: proofID
    )
    _ = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let review = try #require(await publisher.reviews().first)
    _ = try await harness.decisions.handle(LocalPairingDecisionCommandV0(
        commandID: UUID(),
        review: review,
        deviceDisplayName: nil,
        decision: .decline,
        decidedAtUnixMilliseconds: hostWireWall + 99
    ))
    let response = try #require(
        try await harness.session.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: hostWireWall + 100,
            monotonicNowMilliseconds: 1_000,
            responseMessageID: WireUUID(UUID())
        )
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: response
    )
    #expect(error.correlationID == proofID)
    #expect(error.body.code == "pairing.alreadyConsumed")
    #expect(error.body.retry == .never)
    #expect(await harness.committer.values.isEmpty)
    #expect(await publisher.withdrawals() == [review.reviewID])
    #expect(await harness.session.phase == .closed)
}

@Test func hostPairingWireInvalidProofCanRetryWithinExactChallenge() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let badProof = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: WireUUID(UUID()),
        tamperProof: true
    )
    let denialJSON = try await harness.session.receive(
        requestJSON: badProof,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let denial = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: denialJSON
    )
    #expect(denial.body.code == "pairing.invalidProof")
    #expect(await harness.session.phase == .awaitingProve)

    let goodProof = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: WireUUID(UUID())
    )
    let pending = try await harness.session.receive(
        requestJSON: goodProof,
        wallNowUnixMilliseconds: hostWireWall + 3,
        monotonicNowMilliseconds: 980,
        responseMessageID: WireUUID(UUID())
    )
    #expect(try WireCodec.messageKind(from: pending) == .pairingPendingApproval)
    #expect(await publisher.reviews().count == 1)
}

@Test func hostPairingWireExpiryCancelsUncommittedReview() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: proofID
    )
    _ = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let review = try #require(await publisher.reviews().first)
    let deadline = try #require(
        await harness.session.nextDeadlineMonotonicMilliseconds()
    )
    let expiredJSON = try #require(
        try await harness.session.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: hostWireWall + 300_000,
            monotonicNowMilliseconds: deadline,
            responseMessageID: WireUUID(UUID())
        )
    )
    let expired = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: expiredJSON
    )
    #expect(expired.correlationID == proofID)
    #expect(expired.body.code == "pairing.expired")
    #expect(await publisher.withdrawals() == [review.reviewID])
    #expect(await harness.session.phase == .closed)
}

@Test func hostPairingWireUnavailableReviewClosesBeforeDeadline() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: proofID
    )
    _ = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let review = try #require(await publisher.reviews().first)
    await harness.decisions.cancel(
        reviewID: review.reviewID,
        monotonicNowMilliseconds: 980
    )

    let response = try #require(
        try await harness.session.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: hostWireWall + 3,
            monotonicNowMilliseconds: 990,
            responseMessageID: WireUUID(UUID())
        )
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: response
    )
    #expect(error.correlationID == proofID)
    #expect(error.body.code == "pairing.expired")
    #expect(await publisher.withdrawals() == [review.reviewID])
    #expect(await harness.session.phase == .closed)
}

@Test func hostPairingWireCancelWinsSuspendedReviewPublication() async throws {
    let publisher = SuspendingHostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: WireUUID(UUID())
    )
    let pendingTask = Task {
        try await harness.session.receive(
            requestJSON: prove,
            wallNowUnixMilliseconds: hostWireWall + 2,
            monotonicNowMilliseconds: 970,
            responseMessageID: WireUUID(UUID())
        )
    }
    await publisher.waitUntilStarted()
    await harness.session.cancel(at: 980)
    await publisher.resume()
    await #expect(throws: (any Error).self) {
        _ = try await pendingTask.value
    }
    #expect(await harness.session.phase == .closed)
    #expect(await harness.committer.values.isEmpty)
}

@Test func hostPairingWirePublisherFailureReturnsNoFalsePending() async throws {
    let publisher = HostWirePairingReviewPublisherV0(fail: true)
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: proofID
    )
    let response = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: response
    )
    #expect(error.correlationID == proofID)
    #expect(error.body.code == "pairing.alreadyConsumed")
    #expect(error.body.retry == .afterUserAction)
    #expect(await publisher.reviews().isEmpty)
    #expect(await publisher.withdrawals().count == 1)
    #expect(await harness.committer.values.isEmpty)
    #expect(await harness.session.phase == .closed)
}

@Test func hostPairingWireDeadlineDefersToInFlightDurableDecision() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(
        publisher: publisher,
        suspendCommit: true
    )
    let proofID = WireUUID(UUID())
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: proofID
    )
    _ = try await harness.session.receive(
        requestJSON: prove,
        wallNowUnixMilliseconds: hostWireWall + 2,
        monotonicNowMilliseconds: 970,
        responseMessageID: WireUUID(UUID())
    )
    let review = try #require(await publisher.reviews().first)
    let decisionTask = Task {
        try await harness.decisions.handle(LocalPairingDecisionCommandV0(
            commandID: UUID(),
            review: review,
            deviceDisplayName: DeviceDisplayName("Jenny's iPhone"),
            decision: .approve,
            decidedAtUnixMilliseconds: hostWireWall + 99
        ))
    }
    await harness.committer.waitUntilCommitStarts()
    let deadline = try #require(
        await harness.session.nextDeadlineMonotonicMilliseconds()
    )
    let completionID = WireUUID(UUID())
    #expect(try await harness.session.takeCompletionIfAvailable(
        wallNowUnixMilliseconds: hostWireWall + 300_000,
        monotonicNowMilliseconds: deadline,
        responseMessageID: completionID
    ) == nil)
    #expect(await harness.session.phase == .awaitingLocalDecision)

    await harness.committer.resumeCommit()
    _ = try await decisionTask.value
    let completion = try #require(
        try await harness.session.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: hostWireWall + 300_001,
            monotonicNowMilliseconds: deadline + 1,
            responseMessageID: completionID
        )
    )
    let body = try WireCodec.decode(
        WireEnvelope<PairingCompleteBody>.self,
        from: completion
    )
    #expect(body.correlationID == proofID)
    #expect(body.body.deviceID.rawValue == hostWireDeviceID)
}

@Test func hostPairingWireWrongProofCorrelationClosesAuthority() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: WireUUID(UUID())
    )
    let valid = try WireCodec.decode(
        WireEnvelope<PairingProveBody>.self,
        from: hostWireProveRequestV0(
            harness,
            challengeJSON: challenge,
            messageID: WireUUID(UUID())
        )
    )
    let altered = try WireCodec.encode(WireEnvelope(
        messageID: valid.messageID,
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: valid.sentAtUnixMilliseconds,
        body: valid.body
    ))
    await #expect(throws: AgentHostPairingWireErrorV0.invalidCorrelation) {
        _ = try await harness.session.receive(
            requestJSON: altered,
            wallNowUnixMilliseconds: hostWireWall + 2,
            monotonicNowMilliseconds: 970,
            responseMessageID: WireUUID(UUID())
        )
    }
    #expect(await harness.session.phase == .closed)
    #expect(await publisher.reviews().isEmpty)
}

@Test func hostPairingWireSharesReplayAcrossInboundAndOutboundIDs() async throws {
    let publisher = HostWirePairingReviewPublisherV0()
    let harness = try await hostWirePairingHarnessV0(publisher: publisher)
    let begin = try hostWireBeginRequestV0(harness, messageID: WireUUID(UUID()))
    let challengeID = WireUUID(UUID())
    let challenge = try await harness.session.receive(
        requestJSON: begin,
        wallNowUnixMilliseconds: hostWireWall + 1,
        monotonicNowMilliseconds: 960,
        responseMessageID: challengeID
    )
    let prove = try hostWireProveRequestV0(
        harness,
        challengeJSON: challenge,
        messageID: WireUUID(UUID())
    )
    await #expect(
        throws: AgentHostPairingWireErrorV0.duplicateMessage(challengeID)
    ) {
        _ = try await harness.session.receive(
            requestJSON: prove,
            wallNowUnixMilliseconds: hostWireWall + 2,
            monotonicNowMilliseconds: 970,
            responseMessageID: challengeID
        )
    }
    #expect(await harness.session.phase == .closed)
    #expect(await publisher.reviews().isEmpty)
}
