import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let clientSessionClientID = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000001"
)!
private let clientSessionHostID = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000002"
)!
private let clientSessionDeviceID = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000003"
)!
private let clientSessionSPKI = Data((0x00...0x5a).map(UInt8.init))

private struct P256ClientSessionSigner: ClientSessionAuthenticationSigningV0 {
    let key: P256.Signing.PrivateKey

    func signAuthenticationInput(_ input: Data) async throws -> Data {
        try key.signature(for: input).rawRepresentation
    }
}

@Test func clientConfiguredRouteObservationRequiresExactAckAndSequencesHeartbeat()
    async throws
{
    let session = try await authenticatedConfiguredClientSessionV1()
    let requestID = WireUUID(UUID())
    let requestData = try #require(try await session
        .beginConfiguredRouteObservation(
            messageID: requestID,
            sentAtUnixMilliseconds: 2_004,
            monotonicNowMilliseconds: 1_005
        ))
    let request = try WireCodec.decode(
        WireEnvelope<RouteObservationBodyV1>.self,
        from: requestData
    )
    #expect(request.body.connectionID.rawValue == Data(repeating: 0x11, count: 16))
    #expect(request.body.configuredRouteID.rawValue == Data(0x50...0x5f))
    #expect(request.body.routeClass == .privateDNS)
    #expect(request.body.observationSequence == 1)

    let acknowledgement = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 2_005,
        body: try RouteObservationAcknowledgementBodyV1(
            connectionID: request.body.connectionID,
            configuredRouteID: request.body.configuredRouteID,
            routeClass: request.body.routeClass,
            observationSequence: 1
        )
    )
    try await session.receiveConfiguredRouteAcknowledgement(
        WireCodec.encode(acknowledgement),
        monotonicNowMilliseconds: 1_006
    )
    #expect(
        await session.nextRouteObservationDeadlineMonotonicMilliseconds()
            == 16_005
    )

    let heartbeat = try #require(try await session
        .beginConfiguredRouteObservation(
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 17_004,
            monotonicNowMilliseconds: 16_005
        ))
    #expect(try WireCodec.decode(
        WireEnvelope<RouteObservationBodyV1>.self,
        from: heartbeat
    ).body.observationSequence == 2)
}

@Test func clientConfiguredRouteAckMismatchClosesOnlyItsSession() async throws {
    let session = try await authenticatedConfiguredClientSessionV1()
    let requestID = WireUUID(UUID())
    let requestData = try #require(try await session
        .beginConfiguredRouteObservation(
            messageID: requestID,
            sentAtUnixMilliseconds: 2_004,
            monotonicNowMilliseconds: 1_005
        ))
    let request = try WireCodec.decode(
        WireEnvelope<RouteObservationBodyV1>.self,
        from: requestData
    )
    let mismatch = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 2_005,
        body: try RouteObservationAcknowledgementBodyV1(
            connectionID: request.body.connectionID,
            configuredRouteID: request.body.configuredRouteID,
            routeClass: request.body.routeClass,
            observationSequence: 1
        )
    )
    await #expect(throws: ClientPrimarySessionErrorV0.invalidCorrelation) {
        try await session.receiveConfiguredRouteAcknowledgement(
            WireCodec.encode(mismatch),
            monotonicNowMilliseconds: 1_006
        )
    }
    #expect(await session.phase == .closed)
}

private func clientSessionFingerprint(
    _ spki: Data = clientSessionSPKI
) throws -> Data {
    try CompanionSecurityV0.hostFingerprint(subjectPublicKeyInfoDER: spki)
}

private func clientPeerEvidence(
    spki: Data = clientSessionSPKI
) -> TLSPeerEvidence {
    TLSPeerEvidence(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: false,
        pinnedLeafPolicyAccepted: true,
        subjectPublicKeyInfoDER: spki
    )
}

private func makeClientPrimarySession(
    key: P256.Signing.PrivateKey,
    configuredRoute: ClientConfiguredRouteRecordV1? = nil
) throws -> ClientPrimarySessionV0 {
    try ClientPrimarySessionV0(
        clientID: clientSessionClientID,
        expectedHostID: clientSessionHostID,
        expectedDeviceID: clientSessionDeviceID,
        requiredHostFingerprint: clientSessionFingerprint(),
        signer: P256ClientSessionSigner(key: key),
        configuredRoute: configuredRoute
    )
}

private func authenticatedConfiguredClientSessionV1() async throws
    -> ClientPrimarySessionV0
{
    let route = try ClientConfiguredRouteRecordV1(
        configuredRouteID: WireBytes16(Data(0x50...0x5f)),
        endpoint: EndpointCandidate(
            kind: .dns,
            value: "studio.example.net",
            port: 443
        ),
        provenance: .privateDNS
    )
    let session = try makeClientPrimarySession(
        key: P256.Signing.PrivateKey(),
        configuredRoute: route
    )
    let helloID = WireUUID(UUID())
    let challengeID = WireUUID(UUID())
    let proofID = WireUUID(UUID())
    _ = try await beginClientAuthentication(
        session,
        helloMessageID: helloID,
        clientNonce: Data(repeating: 0x33, count: 32)
    )
    _ = try await session.receiveChallenge(
        WireCodec.encode(try clientChallenge(
            correlationID: helloID,
            messageID: challengeID
        )),
        proofMessageID: proofID,
        sentAtUnixMilliseconds: 2_002,
        monotonicNowMilliseconds: 1_003
    )
    _ = try await session.receiveSessionDescription(
        WireCodec.encode(try clientDescription(correlationID: proofID)),
        monotonicNowMilliseconds: 1_004
    )
    return session
}

private func beginClientAuthentication(
    _ session: ClientPrimarySessionV0,
    helloMessageID: WireUUID,
    clientNonce: Data
) async throws -> WireEnvelope<AuthHelloBody> {
    try await session.didConnectTCP(at: 1_000)
    try await session.acceptPinnedPeer(clientPeerEvidence(), at: 1_001)
    let helloData = try await session.beginAuthentication(
        clientNonce: WireBytes32(clientNonce),
        messageID: helloMessageID,
        sentAtUnixMilliseconds: 2_000,
        monotonicNowMilliseconds: 1_002
    )
    return try WireCodec.decode(
        WireEnvelope<AuthHelloBody>.self,
        from: helloData
    )
}

private func clientChallenge(
    correlationID: WireUUID,
    messageID: WireUUID,
    fingerprint: Data? = nil
) throws -> WireEnvelope<AuthChallengeBody> {
    try WireEnvelope(
        messageID: messageID,
        correlationID: correlationID,
        sentAtUnixMilliseconds: 2_001,
        body: try AuthChallengeBody(
            connectionID: WireBytes16(Data(repeating: 0x11, count: 16)),
            serverNonce: WireBytes32(Data(repeating: 0x22, count: 32)),
            hostFingerprint: WireFingerprint(
                try fingerprint ?? clientSessionFingerprint()
            )
        )
    )
}

private func clientDescription(
    correlationID: WireUUID,
    messageID: WireUUID = WireUUID(UUID()),
    hostID: UUID = clientSessionHostID,
    deviceID: UUID = clientSessionDeviceID
) throws -> WireEnvelope<SessionDescriptionBody> {
    try WireEnvelope(
        messageID: messageID,
        correlationID: correlationID,
        sentAtUnixMilliseconds: 2_003,
        body: try SessionDescriptionBody(
            hostID: WireUUID(hostID),
            deviceID: WireUUID(deviceID),
            deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 2),
            grantRevision: .init(rawValue: 3),
            policyRevision: .init(rawValue: 4),
            hostState: .userSessionActive,
            features: ["status.snapshot"],
            serverTimeUnixMilliseconds: 2_003
        )
    )
}

@Test func clientHandshakePublishesIdentityOnlyAfterPinnedCorrelatedDescription() async throws {
    let key = P256.Signing.PrivateKey()
    let session = try makeClientPrimarySession(key: key)
    let helloID = WireUUID(UUID())
    let challengeID = WireUUID(UUID())
    let proofID = WireUUID(UUID())
    let nonce = Data(repeating: 0x33, count: 32)

    let hello = try await beginClientAuthentication(
        session,
        helloMessageID: helloID,
        clientNonce: nonce
    )
    #expect(hello.body.clientID == WireUUID(clientSessionClientID))
    #expect(await session.authenticatedSession == nil)

    let challenge = try clientChallenge(
        correlationID: helloID,
        messageID: challengeID
    )
    let proofData = try await session.receiveChallenge(
        WireCodec.encode(challenge),
        proofMessageID: proofID,
        sentAtUnixMilliseconds: 2_002,
        monotonicNowMilliseconds: 1_003
    )
    let proof = try WireCodec.decode(
        WireEnvelope<AuthProofBody>.self,
        from: proofData
    )
    #expect(proof.correlationID == challengeID)
    let signingInput = try CompanionSecurityV0.authenticationSigningInput(
        clientID: clientSessionClientID,
        connectionID: challenge.body.connectionID.rawValue,
        clientNonce: nonce,
        serverNonce: challenge.body.serverNonce.rawValue,
        hostFingerprint: clientSessionFingerprint(),
        selectedMajor: 0,
        selectedMinor: 1
    )
    let signature = try P256.Signing.ECDSASignature(
        rawRepresentation: proof.body.signature.rawValue
    )
    #expect(key.publicKey.isValidSignature(signature, for: signingInput))

    let established = try await session.receiveSessionDescription(
        WireCodec.encode(try clientDescription(correlationID: proofID)),
        monotonicNowMilliseconds: 1_004
    )
    #expect(established.hostID == clientSessionHostID)
    #expect(established.deviceID == clientSessionDeviceID)
    #expect(established.connectionID == challenge.body.connectionID.rawValue)
    #expect(established.grantRevision.rawValue == 3)
    #expect(await session.phase == .authenticated)
    #expect(await session.pinnedTLSPhase == .ready)
    try await session.admitAuthenticatedTraffic(.commandFrame)
}

@Test func clientNeverStartsAuthenticationBeforePinnedTLSAndPinFailureIsTerminal() async throws {
    let key = P256.Signing.PrivateKey()
    let premature = try makeClientPrimarySession(key: key)
    await #expect(
        throws: ClientPrimarySessionErrorV0.invalidPhase(.awaitingTCP)
    ) {
        _ = try await premature.beginAuthentication(
            clientNonce: WireBytes32(Data(repeating: 0, count: 32)),
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 0,
            monotonicNowMilliseconds: 0
        )
    }
    #expect(await premature.phase == .closed)

    let wrongPin = try makeClientPrimarySession(key: key)
    try await wrongPin.didConnectTCP(at: 0)
    await #expect(throws: PinnedTLSAuthorityError.hostFingerprintMismatch) {
        try await wrongPin.acceptPinnedPeer(
            clientPeerEvidence(spki: Data((0x01...0x5b).map(UInt8.init))),
            at: 1
        )
    }
    #expect(await wrongPin.phase == .closed)
    #expect(await wrongPin.authenticatedSession == nil)
}

@Test func clientRejectsChallengeFingerprintCorrelationAndReplayTerminally() async throws {
    let key = P256.Signing.PrivateKey()
    let helloID = WireUUID(UUID())
    let wrongFingerprint = try makeClientPrimarySession(key: key)
    _ = try await beginClientAuthentication(
        wrongFingerprint,
        helloMessageID: helloID,
        clientNonce: Data(repeating: 1, count: 32)
    )
    let challengeID = WireUUID(UUID())
    let mismatch = try clientChallenge(
        correlationID: helloID,
        messageID: challengeID,
        fingerprint: Data(repeating: 9, count: 32)
    )
    await #expect(throws: ClientPrimarySessionErrorV0.hostFingerprintMismatch) {
        _ = try await wrongFingerprint.receiveChallenge(
            WireCodec.encode(mismatch),
            proofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 2_002,
            monotonicNowMilliseconds: 1_003
        )
    }
    #expect(await wrongFingerprint.phase == .closed)

    let replay = try makeClientPrimarySession(key: key)
    _ = try await beginClientAuthentication(
        replay,
        helloMessageID: helloID,
        clientNonce: Data(repeating: 2, count: 32)
    )
    let valid = try clientChallenge(
        correlationID: helloID,
        messageID: challengeID
    )
    await #expect(
        throws: ClientPrimarySessionErrorV0.duplicateMessage(challengeID)
    ) {
        _ = try await replay.receiveChallenge(
            WireCodec.encode(valid),
            proofMessageID: challengeID,
            sentAtUnixMilliseconds: 2_002,
            monotonicNowMilliseconds: 1_003
        )
    }
    #expect(await replay.phase == .closed)
}

@Test func clientAuthenticationDeadlineClosesSilentConnectionAtExactBoundary() async throws {
    let session = try makeClientPrimarySession(key: P256.Signing.PrivateKey())
    try await session.didConnectTCP(at: 1_000)
    #expect(await session.nextAuthenticationDeadlineMonotonicMilliseconds() == 11_000)
    #expect(await !session.expireAuthenticationIfRequired(at: 10_999))
    #expect(await session.expireAuthenticationIfRequired(at: 11_000))
    #expect(await session.phase == .closed)
    #expect(await session.pinnedTLSPhase == .closed)
}

@Test func clientRejectsRemoteDenialAndWrongPairedIdentityWithoutPublishing() async throws {
    let key = P256.Signing.PrivateKey()
    let denied = try makeClientPrimarySession(key: key)
    let helloID = WireUUID(UUID())
    _ = try await beginClientAuthentication(
        denied,
        helloMessageID: helloID,
        clientNonce: Data(repeating: 3, count: 32)
    )
    let error = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: helloID,
        sentAtUnixMilliseconds: 2_001,
        body: try ProtocolErrorResponseBody(
            code: "auth.deviceSuspended",
            retry: .afterUserAction
        )
    )
    await #expect(throws: ClientPrimarySessionErrorV0.remoteError(
        code: "auth.deviceSuspended",
        retry: .afterUserAction
    )) {
        _ = try await denied.receiveChallenge(
            WireCodec.encode(error),
            proofMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 2_002,
            monotonicNowMilliseconds: 1_003
        )
    }
    #expect(await denied.phase == .closed)

    let wrongHost = try makeClientPrimarySession(key: key)
    let secondHelloID = WireUUID(UUID())
    _ = try await beginClientAuthentication(
        wrongHost,
        helloMessageID: secondHelloID,
        clientNonce: Data(repeating: 4, count: 32)
    )
    let proofID = WireUUID(UUID())
    _ = try await wrongHost.receiveChallenge(
        WireCodec.encode(try clientChallenge(
            correlationID: secondHelloID,
            messageID: WireUUID(UUID())
        )),
        proofMessageID: proofID,
        sentAtUnixMilliseconds: 2_002,
        monotonicNowMilliseconds: 1_003
    )
    let mismatch = try clientDescription(
        correlationID: proofID,
        hostID: UUID()
    )
    await #expect(throws: ClientPrimarySessionErrorV0.hostIdentityMismatch) {
        _ = try await wrongHost.receiveSessionDescription(
            WireCodec.encode(mismatch),
            monotonicNowMilliseconds: 1_004
        )
    }
    #expect(await wrongHost.phase == .closed)
    #expect(await wrongHost.authenticatedSession == nil)
}
