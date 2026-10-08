import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let clientSecurityHostID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000001"
)!
private let clientSecurityClientID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000002"
)!
private let clientSecurityConnectionID = Data((0x00..<0x10).map(UInt8.init))
private let clientSecuritySPKI = Data((0x00...0x5a).map(UInt8.init))
private let clientSecurityCredential = Data((0xe0...0xff).map(UInt8.init))

private struct ClientPresenceSigner: ClientInteractiveApprovalSigningV0 {
    let key: P256.Signing.PrivateKey

    func signSessionChallenge(_ input: Data) async throws -> Data {
        try key.signature(for: input).rawRepresentation
    }
}

private func clientSecurityApprovalKey() throws -> P256.Signing.PrivateKey {
    var bytes = Data(repeating: 0, count: 32)
    bytes[31] = 2
    return try P256.Signing.PrivateKey(rawRepresentation: bytes)
}

private func clientSecurityFingerprint() throws -> Data {
    try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: clientSecuritySPKI
    )
}

private func clientSecurityPrimary(
    epoch: UInt64 = 4
) throws -> ClientInteractivePrimaryBindingV0 {
    try ClientInteractivePrimaryBindingV0(
        hostID: clientSecurityHostID,
        hostFingerprint: clientSecurityFingerprint(),
        clientID: clientSecurityClientID,
        primaryConnectionID: clientSecurityConnectionID,
        authorizationEpoch: .init(rawValue: epoch),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6)
    )
}

private struct PendingClientInteractiveSession {
    let authority: ClientInteractiveSessionAuthorityV0
    let requestID: WireUUID
    let proofID: WireUUID
    let challenge: WireEnvelope<InteractiveApprovalChallengeBody>
    let proof: WireEnvelope<InteractiveApprovalProofBody>
}

private func pendingClientInteractiveSession(
    effects: Set<InteractiveControlEffect> = [.view, .pointer, .keyboard]
) async throws -> PendingClientInteractiveSession {
    let authority = ClientInteractiveSessionAuthorityV0(
        primary: try clientSecurityPrimary(),
        signer: ClientPresenceSigner(key: try clientSecurityApprovalKey())
    )
    let requestID = WireUUID(UUID())
    let requestData = try await authority.beginRequest(
        effects: effects,
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionRequestBody>.self,
        from: requestData
    )
    let challenge = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveApprovalChallengeBody(
            hostID: WireUUID(clientSecurityHostID),
            hostFingerprint: WireFingerprint(clientSecurityFingerprint()),
            clientID: WireUUID(clientSecurityClientID),
            primaryConnectionID: WireBytes16(clientSecurityConnectionID),
            requestID: requestID,
            approvalID: WireUUID(UUID()),
            serverChallenge: WireBytes32(Data(repeating: 0x44, count: 32)),
            authorizationEpoch: .init(rawValue: 4),
            grantRevision: .init(rawValue: 5),
            policyRevision: .init(rawValue: 6),
            selectedDisplayID: WireUUID(UUID()),
            initialSurface: .desktop,
            effects: Set(request.body.effects),
            issuedAtUnixMilliseconds: 1_001,
            expiresAtUnixMilliseconds: 61_001
        )
    )
    let proofID = WireUUID(UUID())
    let proofData = try await authority.receiveApprovalChallenge(
        WireCodec.encode(challenge),
        approvalProofMessageID: proofID,
        sentAtUnixMilliseconds: 1_002,
        monotonicNowMilliseconds: 10_000
    )
    let proof = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalProofBody>.self,
        from: proofData
    )
    return PendingClientInteractiveSession(
        authority: authority,
        requestID: requestID,
        proofID: proofID,
        challenge: challenge,
        proof: proof
    )
}

private func acceptedResponse(
    proofID: WireUUID,
    epoch: UInt64 = 4,
    credential: Data = clientSecurityCredential
) throws -> WireEnvelope<InteractiveSessionAcceptedBody> {
    let input = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .input,
        credential: WireBytes32(credential),
        issuedAtUnixMilliseconds: 2_000,
        expiresAtUnixMilliseconds: 32_000
    )
    let media = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .media,
        credential: WireBytes32(Data(repeating: 0xa5, count: 32)),
        issuedAtUnixMilliseconds: 2_000,
        expiresAtUnixMilliseconds: 32_000
    )
    return try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proofID,
        sentAtUnixMilliseconds: 2_000,
        body: try InteractiveSessionAcceptedBody(
            interactiveSessionID: WireUUID(UUID()),
            authorizationEpoch: .init(rawValue: epoch),
            expiresAtUnixMilliseconds: 100_000,
            inputChannel: input,
            mediaChannel: media
        )
    )
}

private func acceptedClientInteractiveSession() async throws
    -> ClientInteractiveAcceptedSessionV0 {
    let pending = try await pendingClientInteractiveSession()
    return try await pending.authority.receiveAcceptedSession(
        WireCodec.encode(try acceptedResponse(proofID: pending.proofID)),
        monotonicNowMilliseconds: 10_001
    )
}

@Test func clientInteractiveApprovalSignsOnlyExactPrimaryAndRequestedEffects() async throws {
    let pending = try await pendingClientInteractiveSession(
        effects: [.view, .pointer, .keyboard, .text]
    )
    #expect(pending.proof.correlationID == pending.challenge.messageID)
    #expect(pending.proof.body.approvalID == pending.challenge.body.approvalID)
    let signature = try P256.Signing.ECDSASignature(
        rawRepresentation: pending.proof.body.signature.rawValue
    )
    #expect(try clientSecurityApprovalKey().publicKey.isValidSignature(
        signature,
        for: pending.challenge.body.signingInput(
            version: pending.challenge.version
        )
    ))

    let accepted = try await pending.authority.receiveAcceptedSession(
        WireCodec.encode(try acceptedResponse(proofID: pending.proofID)),
        monotonicNowMilliseconds: 10_001
    )
    #expect(accepted.primary == (try clientSecurityPrimary()))
    #expect(accepted.authorizationEpoch.rawValue == 4)
    #expect(accepted.inputChannel.role == .input)
    #expect(accepted.mediaChannel.role == .media)
    #expect(await pending.authority.phase == .accepted)
}

@Test func clientInteractiveApprovalRejectsBindingBroadeningAndAcceptedEpoch() async throws {
    let authority = ClientInteractiveSessionAuthorityV0(
        primary: try clientSecurityPrimary(),
        signer: ClientPresenceSigner(key: try clientSecurityApprovalKey())
    )
    let requestID = WireUUID(UUID())
    _ = try await authority.beginRequest(
        effects: [.view, .pointer],
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    let broadened = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveApprovalChallengeBody(
            hostID: WireUUID(clientSecurityHostID),
            hostFingerprint: WireFingerprint(clientSecurityFingerprint()),
            clientID: WireUUID(clientSecurityClientID),
            primaryConnectionID: WireBytes16(clientSecurityConnectionID),
            requestID: requestID,
            approvalID: WireUUID(UUID()),
            serverChallenge: WireBytes32(Data(repeating: 1, count: 32)),
            authorizationEpoch: .init(rawValue: 4),
            grantRevision: .init(rawValue: 5),
            policyRevision: .init(rawValue: 6),
            selectedDisplayID: WireUUID(UUID()),
            initialSurface: .desktop,
            effects: [.view, .pointer, .keyboard],
            issuedAtUnixMilliseconds: 1_001,
            expiresAtUnixMilliseconds: 61_001
        )
    )
    await #expect(
        throws: ClientInteractiveSessionErrorV0.requestBindingMismatch
    ) {
        _ = try await authority.receiveApprovalChallenge(
            WireCodec.encode(broadened),
            approvalProofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_002,
            monotonicNowMilliseconds: 10_000
        )
    }
    #expect(await authority.phase == .closed)

    let pending = try await pendingClientInteractiveSession()
    await #expect(
        throws: ClientInteractiveSessionErrorV0.acceptedSessionMismatch
    ) {
        _ = try await pending.authority.receiveAcceptedSession(
            WireCodec.encode(try acceptedResponse(
                proofID: pending.proofID,
                epoch: 5
            )),
            monotonicNowMilliseconds: 10_001
        )
    }
    #expect(await pending.authority.acceptedSession == nil)
}

@Test func clientInteractiveApprovalDeadlineAndRemoteDenialAreTerminal() async throws {
    let pending = try await pendingClientInteractiveSession()
    #expect(await pending.authority.nextApprovalDeadlineMonotonicMilliseconds()
        == 70_000)
    #expect(await !pending.authority.expireApprovalIfRequired(at: 69_999))
    #expect(await pending.authority.expireApprovalIfRequired(at: 70_000))
    #expect(await pending.authority.phase == .closed)

    let denied = ClientInteractiveSessionAuthorityV0(
        primary: try clientSecurityPrimary(),
        signer: ClientPresenceSigner(key: try clientSecurityApprovalKey())
    )
    let requestID = WireUUID(UUID())
    _ = try await denied.beginRequest(
        effects: [.view],
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    let error = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 1_001,
        body: try ProtocolErrorResponseBody(
            code: "policy.denied",
            retry: .afterUserAction,
            safeArguments: .object([
                .init(key: "capabilityID", value: .string(
                    "maccompanion.interactive.control"
                )),
            ])
        )
    )
    await #expect(throws: ClientInteractiveSessionErrorV0.remoteError(
        code: "policy.denied",
        retry: .afterUserAction
    )) {
        _ = try await denied.receiveApprovalChallenge(
            WireCodec.encode(error),
            approvalProofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_002,
            monotonicNowMilliseconds: 10_000
        )
    }
}

private struct PendingClientChannel {
    let authority: ClientInteractiveChannelAuthorityV0
    let session: ClientInteractiveAcceptedSessionV0
    let hello: InteractiveChannelEnvelope<InteractiveChannelHelloBody>
    let challenge: InteractiveChannelEnvelope<InteractiveChannelChallengeBody>
    let proof: InteractiveChannelEnvelope<InteractiveChannelProofBody>
}

private func pendingClientChannel(
    role: InteractiveChannelRoleName = .input
) async throws -> PendingClientChannel {
    let session = try await acceptedClientInteractiveSession()
    let authority = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: role
    )
    try await authority.didConnectTCP(at: 100)
    try await authority.acceptPinnedPeer(TLSPeerEvidence(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: false,
        pinnedLeafPolicyAccepted: true,
        subjectPublicKeyInfoDER: clientSecuritySPKI
    ), at: 101)
    let helloData = try await authority.begin(
        clientNonce: WireBytes32(Data(repeating: 0x11, count: 32)),
        messageID: WireUUID(UUID()),
        monotonicNowMilliseconds: 102
    )
    let hello = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelHelloBody>.self,
        from: helloData
    )
    let challenge = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: hello.messageID,
        body: InteractiveChannelChallengeBody(
            channelID: hello.body.channelID,
            role: role,
            hostID: WireUUID(clientSecurityHostID),
            hostFingerprint: WireFingerprint(clientSecurityFingerprint()),
            hostNonce: try WireBytes32(Data(repeating: 0x22, count: 32))
        )
    )
    let proofData = try await authority.receiveChallenge(
        InteractiveChannelCodec.encode(challenge),
        proofMessageID: WireUUID(UUID()),
        monotonicNowMilliseconds: 103
    )
    let proof = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelProofBody>.self,
        from: proofData
    )
    return PendingClientChannel(
        authority: authority,
        session: session,
        hello: hello,
        challenge: challenge,
        proof: proof
    )
}

private final class InteractiveRoleHandshakeTestIO:
    ClientInteractiveRoleHandshakeIOV0, @unchecked Sendable
{
    private let lock = NSLock()
    private var chunks: [ClientInteractiveRoleReadChunkV0]
    private var sentStorage: [Data] = []
    private var requestedLengthsStorage: [Int] = []
    private var cancelCountStorage = 0
    private let beforeReceive: @Sendable () -> Void

    init(
        chunks: [ClientInteractiveRoleReadChunkV0],
        beforeReceive: @escaping @Sendable () -> Void = {}
    ) {
        self.chunks = chunks
        self.beforeReceive = beforeReceive
    }

    func receive(
        maximumLength: Int
    ) async throws -> ClientInteractiveRoleReadChunkV0 {
        beforeReceive()
        return try take(maximumLength: maximumLength)
    }

    func send(_ data: Data) async throws {
        appendSent(data)
    }

    private func appendSent(_ data: Data) {
        lock.lock()
        sentStorage.append(data)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelCountStorage += 1
        lock.unlock()
    }

    func snapshot() -> (
        sent: [Data], requestedLengths: [Int], remaining: [Data], cancels: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            sentStorage,
            requestedLengthsStorage,
            chunks.map(\.data),
            cancelCountStorage
        )
    }

    private func take(
        maximumLength: Int
    ) throws -> ClientInteractiveRoleReadChunkV0 {
        lock.lock()
        defer { lock.unlock() }
        requestedLengthsStorage.append(maximumLength)
        guard maximumLength > 0, !chunks.isEmpty else {
            throw ClientInteractiveRoleHandshakePumpErrorV0.invalidRead
        }
        let first = chunks.removeFirst()
        guard first.data.count <= maximumLength else {
            let head = Data(first.data.prefix(maximumLength))
            let tail = Data(first.data.dropFirst(maximumLength))
            chunks.insert(
                ClientInteractiveRoleReadChunkV0(
                    data: tail,
                    isComplete: first.isComplete
                ),
                at: 0
            )
            return ClientInteractiveRoleReadChunkV0(data: head)
        }
        return first
    }
}

private final class InteractiveRoleHandshakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var valueStorage: UInt64

    init(_ value: UInt64) { valueStorage = value }

    func value() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return valueStorage
    }

    func set(_ value: UInt64) {
        lock.lock()
        valueStorage = value
        lock.unlock()
    }
}

private func roleHandshakeFrame(_ body: Data) -> Data {
    let length = UInt32(body.count)
    return Data([
        UInt8(length >> 24),
        UInt8((length >> 16) & 0xff),
        UInt8((length >> 8) & 0xff),
        UInt8(length & 0xff),
    ]) + body
}

private func roleHandshakeServerFrames(
    session: ClientInteractiveAcceptedSessionV0,
    role: InteractiveChannelRoleName,
    nonce: WireBytes32,
    helloID: WireUUID,
    proofID: WireUUID
) throws -> (challenge: Data, accepted: Data) {
    let offer = role == .input ? session.inputChannel : session.mediaChannel
    let hello = try InteractiveChannelEnvelope(
        messageID: helloID,
        correlationID: nil,
        body: InteractiveChannelHelloBody(
            channelID: offer.channelID,
            role: role,
            clientID: WireUUID(session.primary.clientID),
            primaryConnectionID: try WireBytes16(
                session.primary.primaryConnectionID
            ),
            interactiveSessionID: WireUUID(session.interactiveSessionID),
            authorizationEpoch: session.authorizationEpoch,
            clientNonce: nonce
        )
    )
    let challenge = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: helloID,
        body: InteractiveChannelChallengeBody(
            channelID: offer.channelID,
            role: role,
            hostID: WireUUID(session.primary.hostID),
            hostFingerprint: WireFingerprint(
                session.primary.hostFingerprint
            ),
            hostNonce: try WireBytes32(Data(repeating: 0x72, count: 32))
        )
    )
    let transcript = try hello.body.transcriptInput(
        challenge: challenge.body,
        version: hello.version
    )
    let digest = CompanionSecurityV0.interactiveChannelTranscriptDigest(
        transcript
    )
    let accepted = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: proofID,
        body: InteractiveChannelAcceptedBody(
            channelID: offer.channelID,
            role: role,
            serverProof: try WireBytes32(
                CompanionSecurityV0.interactiveChannelServerProof(
                    credential: offer.credential.rawValue,
                    transcriptDigest: digest
                )
            )
        )
    )
    return (
        roleHandshakeFrame(try InteractiveChannelCodec.encode(challenge)),
        roleHandshakeFrame(try InteractiveChannelCodec.encode(accepted))
    )
}

@Test func interactiveRolePumpAuthenticatesBothRolesWithExactReads() async throws {
    for role in [InteractiveChannelRoleName.input, .media] {
        let session = try await acceptedClientInteractiveSession()
        let nonce = try WireBytes32(Data(repeating: 0x31, count: 32))
        let helloID = WireUUID(UUID())
        let proofID = WireUUID(UUID())
        let frames = try roleHandshakeServerFrames(
            session: session,
            role: role,
            nonce: nonce,
            helloID: helloID,
            proofID: proofID
        )
        let sentinel = Data(repeating: role == .input ? 0x49 : 0x4d, count: 96)
        let bytes = frames.challenge + frames.accepted
        let io = InteractiveRoleHandshakeTestIO(
            chunks: bytes.map {
                ClientInteractiveRoleReadChunkV0(data: Data([$0]))
            } + [ClientInteractiveRoleReadChunkV0(data: sentinel)]
        )
        let authority = try ClientInteractiveChannelAuthorityV0(
            session: session,
            role: role
        )
        let pump = ClientInteractiveRoleHandshakePumpV0(
            io: io,
            authority: authority,
            evidence: TLSPeerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: false,
                pinnedLeafPolicyAccepted: true,
                subjectPublicKeyInfoDER: clientSecuritySPKI
            ),
            monotonicNowMilliseconds: { 100 }
        )
        let ready = try await pump.beginOnVerifiedReadyConnection(
            clientNonce: nonce,
            helloMessageID: helloID,
            proofMessageID: proofID
        )
        #expect(ready.role == role)
        #expect(ready.channelID == (role == .input
            ? session.inputChannel.channelID : session.mediaChannel.channelID))
        #expect(await pump.phase == .ready)
        try await pump.admitRoleTraffic()

        let snapshot = io.snapshot()
        #expect(snapshot.sent.count == 2)
        #expect(snapshot.sent.allSatisfy { !$0.isEmpty })
        #expect(snapshot.remaining == [sentinel])
        #expect(snapshot.cancels == 0)
        #expect(snapshot.requestedLengths.allSatisfy {
            (1...ClientInteractiveRoleHandshakePumpV0
                .maximumHandshakeJSONBytes).contains($0)
        })
    }
}

@Test func interactiveRolePumpFailsClosedOnOversizeAndRoleSwap() async throws {
    let session = try await acceptedClientInteractiveSession()
    let oversizeIO = InteractiveRoleHandshakeTestIO(chunks: [
        ClientInteractiveRoleReadChunkV0(
            data: Data([0x00, 0x00, 0x10, 0x01])
        ),
    ])
    let oversizeAuthority = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .input
    )
    let oversize = ClientInteractiveRoleHandshakePumpV0(
        io: oversizeIO,
        authority: oversizeAuthority,
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: clientSecuritySPKI
        ),
        monotonicNowMilliseconds: { 100 }
    )
    await #expect(throws: ClientInteractiveRoleHandshakePumpErrorV0
        .invalidFrameLength(4_097)) {
        _ = try await oversize.beginOnVerifiedReadyConnection(
            clientNonce: WireBytes32(Data(repeating: 1, count: 32)),
            helloMessageID: WireUUID(UUID()),
            proofMessageID: WireUUID(UUID())
        )
    }
    #expect(await oversize.phase == .closed)
    #expect(oversizeIO.snapshot().cancels == 1)

    let nonce = try WireBytes32(Data(repeating: 2, count: 32))
    let helloID = WireUUID(UUID())
    let proofID = WireUUID(UUID())
    let mediaFrames = try roleHandshakeServerFrames(
        session: session,
        role: .media,
        nonce: nonce,
        helloID: helloID,
        proofID: proofID
    )
    let swapIO = InteractiveRoleHandshakeTestIO(chunks: [
        ClientInteractiveRoleReadChunkV0(data: mediaFrames.challenge),
    ])
    let inputAuthority = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .input
    )
    let swapped = ClientInteractiveRoleHandshakePumpV0(
        io: swapIO,
        authority: inputAuthority,
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: clientSecuritySPKI
        ),
        monotonicNowMilliseconds: { 100 }
    )
    await #expect(
        throws: ClientInteractiveChannelErrorV0.challengeBindingMismatch
    ) {
        _ = try await swapped.beginOnVerifiedReadyConnection(
            clientNonce: nonce,
            helloMessageID: helloID,
            proofMessageID: proofID
        )
    }
    #expect(await swapped.phase == .closed)
    #expect(swapIO.snapshot().cancels == 1)
}

@Test func interactiveRolePumpEnforcesFixedMonotonicDeadline() async throws {
    let session = try await acceptedClientInteractiveSession()
    let clock = InteractiveRoleHandshakeClock(1_000)
    let io = InteractiveRoleHandshakeTestIO(
        chunks: [ClientInteractiveRoleReadChunkV0(
            data: Data([0x00, 0x00, 0x00, 0x01])
        )],
        beforeReceive: { clock.set(31_000) }
    )
    let authority = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .input
    )
    let pump = ClientInteractiveRoleHandshakePumpV0(
        io: io,
        authority: authority,
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: clientSecuritySPKI
        ),
        monotonicNowMilliseconds: { clock.value() }
    )
    await #expect(
        throws: ClientInteractiveRoleHandshakePumpErrorV0.deadlineExceeded
    ) {
        _ = try await pump.beginOnVerifiedReadyConnection(
            clientNonce: WireBytes32(Data(repeating: 3, count: 32)),
            helloMessageID: WireUUID(UUID()),
            proofMessageID: WireUUID(UUID())
        )
    }
    #expect(await pump.phase == .closed)
    #expect(io.snapshot().cancels == 1)
}

@Test func clientInteractiveChannelVerifiesMutualProofBeforeRoleTraffic() async throws {
    let pending = try await pendingClientChannel()
    let transcript = try pending.hello.body.transcriptInput(
        challenge: pending.challenge.body,
        version: pending.hello.version
    )
    let digest = CompanionSecurityV0.interactiveChannelTranscriptDigest(
        transcript
    )
    #expect(try CompanionSecurityV0.verifyInteractiveChannelClientProof(
        pending.proof.body.clientProof.rawValue,
        credential: pending.session.inputChannel.credential.rawValue,
        transcriptDigest: digest
    ))
    let accepted = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: pending.proof.messageID,
        body: InteractiveChannelAcceptedBody(
            channelID: pending.session.inputChannel.channelID,
            role: .input,
            serverProof: try WireBytes32(
                CompanionSecurityV0.interactiveChannelServerProof(
                    credential: pending.session.inputChannel.credential.rawValue,
                    transcriptDigest: digest
                )
            )
        )
    )
    try await pending.authority.receiveAcceptance(
        InteractiveChannelCodec.encode(accepted),
        monotonicNowMilliseconds: 104
    )
    #expect(await pending.authority.phase == .ready)
    #expect(await pending.authority.pinnedTLSPhase == .ready)
    try await pending.authority.admitRoleTraffic()
}

@Test func clientInteractiveChannelRejectsRoleSwapAndWrongServerProof() async throws {
    let session = try await acceptedClientInteractiveSession()
    let roleSwap = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .media
    )
    try await roleSwap.didConnectTCP(at: 100)
    try await roleSwap.acceptPinnedPeer(TLSPeerEvidence(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: false,
        pinnedLeafPolicyAccepted: true,
        subjectPublicKeyInfoDER: clientSecuritySPKI
    ), at: 101)
    let helloData = try await roleSwap.begin(
        clientNonce: WireBytes32(Data(repeating: 1, count: 32)),
        messageID: WireUUID(UUID()),
        monotonicNowMilliseconds: 102
    )
    let hello = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelHelloBody>.self,
        from: helloData
    )
    let swapped = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: hello.messageID,
        body: InteractiveChannelChallengeBody(
            channelID: session.mediaChannel.channelID,
            role: .input,
            hostID: WireUUID(clientSecurityHostID),
            hostFingerprint: WireFingerprint(clientSecurityFingerprint()),
            hostNonce: try WireBytes32(Data(repeating: 2, count: 32))
        )
    )
    await #expect(
        throws: ClientInteractiveChannelErrorV0.challengeBindingMismatch
    ) {
        _ = try await roleSwap.receiveChallenge(
            InteractiveChannelCodec.encode(swapped),
            proofMessageID: WireUUID(UUID()),
            monotonicNowMilliseconds: 103
        )
    }

    let wrongProof = try await pendingClientChannel()
    let accepted = try InteractiveChannelEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: wrongProof.proof.messageID,
        body: InteractiveChannelAcceptedBody(
            channelID: wrongProof.session.inputChannel.channelID,
            role: .input,
            serverProof: try WireBytes32(Data(repeating: 0, count: 32))
        )
    )
    await #expect(
        throws: ClientInteractiveChannelErrorV0.serverProofMismatch
    ) {
        try await wrongProof.authority.receiveAcceptance(
            InteractiveChannelCodec.encode(accepted),
            monotonicNowMilliseconds: 104
        )
    }
    #expect(await wrongProof.authority.phase == .closed)
}

@Test func clientInteractiveChannelPinGateAndDeadlineAreExact() async throws {
    let session = try await acceptedClientInteractiveSession()
    let channel = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .input
    )
    await #expect(
        throws: ClientInteractiveChannelErrorV0.invalidPhase(.awaitingTCP)
    ) {
        _ = try await channel.begin(
            clientNonce: WireBytes32(Data(repeating: 0, count: 32)),
            messageID: WireUUID(UUID()),
            monotonicNowMilliseconds: 0
        )
    }
    #expect(await channel.phase == .closed)

    let expiring = try ClientInteractiveChannelAuthorityV0(
        session: session,
        role: .input
    )
    try await expiring.didConnectTCP(at: 1_000)
    #expect(await expiring.nextDeadlineMonotonicMilliseconds() == 31_000)
    #expect(await !expiring.expireIfRequired(at: 30_999))
    #expect(await expiring.expireIfRequired(at: 31_000))
    #expect(await expiring.pinnedTLSPhase == .closed)
}
