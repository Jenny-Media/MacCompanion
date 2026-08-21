import CompanionDomain
import CompanionInteractiveWire
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func interactiveFixture(_ path: String) throws -> Data {
    try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent(path))
}

@Test func approvalChallengeFixtureIsCanonicalAndReconstructsGoldenSigningInput() throws {
    let source = try interactiveFixture("valid/interactive-session-approval-required.json")
    let envelope = try WireCodec.decode(
        WireEnvelope<InteractiveApprovalChallengeBody>.self,
        from: source
    )
    #expect(envelope.body.requestID == envelope.correlationID)
    #expect(envelope.body.effects == [.keyboard, .pointer, .text, .view])
    let input = try envelope.body.signingInput(version: envelope.version)
    #expect(input.hexString == "4d6163436f6d70616e696f6e2f496e746572616374697665417070726f76616c2f76302e3100000010018f100000007000800000000000000100000020808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f00000010018f200000007000800000000000000100000010000102030405060708090a0b0c0d0e0f00000010018f650000007000800000000000000100000010018f660000007000800000000000000100000020303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f00000000000000040000000000000005000000000000000600000010018f670000007000800000000000000101000f0000019166685800000001916669426000000001")
    let canonicalSource = source.last == 0x0a ? Data(source.dropLast()) : source
    #expect(try WireCodec.encode(envelope) == canonicalSource)
}

@Test func channelHelloAndChallengeReconstructGoldenTranscript() throws {
    let helloData = try interactiveFixture("valid/interactive-channel-hello.json")
    let challengeData = try interactiveFixture("valid/interactive-channel-challenge.json")
    let hello = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelHelloBody>.self,
        from: helloData
    )
    let challenge = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelChallengeBody>.self,
        from: challengeData
    )
    #expect(challenge.correlationID == hello.messageID)
    let transcript = try hello.body.transcriptInput(
        challenge: challenge.body,
        version: hello.version
    )
    #expect(transcript.hexString == "4d6163436f6d70616e696f6e2f496e7465726163746976654368616e6e656c2f76302e3100000010018f68000000700080000000000000010200000010018f100000007000800000000000000100000020808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f00000010018f200000007000800000000000000100000010000102030405060708090a0b0c0d0e0f00000010018f6000000070008000000000000001000000000000000400000020101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f00000020303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f00000001")
    let canonicalHello = helloData.last == 0x0a ? Data(helloData.dropLast()) : helloData
    let canonicalChallenge = challengeData.last == 0x0a ? Data(challengeData.dropLast()) : challengeData
    #expect(try InteractiveChannelCodec.encode(hello) == canonicalHello)
    #expect(try InteractiveChannelCodec.encode(challenge) == canonicalChallenge)
}

@Test func sessionRequestMustStartDesktopAndBindNonBroadeningEffects() throws {
    #expect(throws: WireError.invalidFrame(reason: "v0.1 session must start on Desktop")) {
        try InteractiveSessionRequestBody(
            initialSurface: .window,
            effects: [.view, .pointer]
        )
    }
    #expect(throws: WireError.invalidFrame(reason: "invalid Interactive Control effects")) {
        try InteractiveSessionRequestBody(
            effects: [.view, .text]
        )
    }
}

@Test func acceptedSessionRequiresDistinctRoleSpecificCredentials() throws {
    let credential = try WireBytes32(Data(repeating: 1, count: 32))
    let input = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .input,
        credential: credential,
        issuedAtUnixMilliseconds: 1,
        expiresAtUnixMilliseconds: 30_000
    )
    let media = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .media,
        credential: credential,
        issuedAtUnixMilliseconds: 1,
        expiresAtUnixMilliseconds: 30_000
    )
    #expect(throws: WireError.invalidFrame(reason: "invalid accepted Interactive Control session")) {
        try InteractiveSessionAcceptedBody(
            interactiveSessionID: WireUUID(UUID()),
            authorizationEpoch: .init(rawValue: 1),
            expiresAtUnixMilliseconds: 100_000,
            inputChannel: input,
            mediaChannel: media
        )
    }
}

@Test func authoritativeSessionEndAndReceiptAreCanonical() throws {
    let requestData = try interactiveFixture(
        "valid/interactive-session-end.json"
    )
    let responseData = try interactiveFixture(
        "valid/interactive-session-ended.json"
    )
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndBodyV0>.self,
        from: requestData
    )
    let response = try WireCodec.decode(
        WireEnvelope<InteractiveSessionEndedBodyV0>.self,
        from: responseData
    )
    #expect(request.correlationID == nil)
    #expect(response.correlationID == request.messageID)
    #expect(response.body.interactiveSessionID
        == request.body.interactiveSessionID)
    #expect(response.body.authorizationEpoch
        == request.body.authorizationEpoch)
    let canonicalRequest = requestData.last == 0x0a
        ? Data(requestData.dropLast()) : requestData
    let canonicalResponse = responseData.last == 0x0a
        ? Data(responseData.dropLast()) : responseData
    #expect(try WireCodec.encode(request) == canonicalRequest)
    #expect(try WireCodec.encode(response) == canonicalResponse)
}

@Test func channelEnvelopeCorrelationAndBodyKindsAreClosed() throws {
    let hello = try InteractiveChannelHelloBody(
        channelID: WireUUID(UUID()),
        role: .input,
        clientID: WireUUID(UUID()),
        primaryConnectionID: WireBytes16(Data(repeating: 0, count: 16)),
        interactiveSessionID: WireUUID(UUID()),
        authorizationEpoch: .init(rawValue: 1),
        clientNonce: WireBytes32(Data(repeating: 0, count: 32))
    )
    #expect(throws: WireError.invalidFrame(reason: "channel hello must have null correlationID")) {
        try InteractiveChannelEnvelope(
            messageID: WireUUID(UUID()),
            correlationID: WireUUID(UUID()),
            body: hello
        )
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
