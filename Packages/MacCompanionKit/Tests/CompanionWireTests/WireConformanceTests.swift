import CompanionTestSupport
import CompanionWire
import CompanionDiscovery
import CryptoKit
import Foundation
import Testing

private func fixture(_ relativePath: String) throws -> Data {
    try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent(relativePath))
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func decodeCanonicalFixture<Body: WireBody>(
    _ relativePath: String,
    as bodyType: Body.Type,
    expectedSHA256: String
) throws -> WireEnvelope<Body> {
    let envelope = try WireCodec.decode(
        WireEnvelope<Body>.self,
        from: fixture(relativePath)
    )
    #expect(sha256Hex(try WireCodec.encode(envelope)) == expectedSHA256)
    return envelope
}

@Test func versionIsExplicit() {
    let version = WireVersion()
    #expect(version.major == 0)
    #expect(version.minor == 1)
}

@Test func authoritativeStatusFixtureDecodesAndCanonicalizes() throws {
    let data = try fixture("valid/status-snapshot-response.json")
    let envelope = try WireCodec.decode(
        WireEnvelope<StatusSnapshotBody>.self,
        from: data
    )

    #expect(envelope.kind == .statusSnapshotResponse)
    #expect(envelope.body.resourceID == "host.status")
    #expect(envelope.body.revision == 42)
    #expect(envelope.body.system.cpuUtilizationBasisPoints == 1250)

    let canonical = try WireCodec.encode(envelope)
    #expect(sha256Hex(canonical) == "c063d3a09548104fc009bf7d2af9742a3cd6c87ba8a77663b2e23dc39ea4f077")
}

@Test func validatedConstructionPreservesAuthoritativeStatusBytes() throws {
    let decoded = try WireCodec.decode(
        WireEnvelope<StatusSnapshotBody>.self,
        from: fixture("valid/status-snapshot-response.json")
    )
    let source = decoded.body.system
    let system = try SystemOverview(
        osName: source.osName,
        osVersion: source.osVersion,
        osBuild: source.osBuild,
        uptimeSeconds: source.uptimeSeconds,
        cpuUtilizationBasisPoints: source.cpuUtilizationBasisPoints,
        memoryTotalBytes: source.memoryTotalBytes,
        memoryUsedBytes: source.memoryUsedBytes,
        storageTotalBytes: source.storageTotalBytes,
        storageAvailableBytes: source.storageAvailableBytes,
        powerSource: source.powerSource,
        batteryLevelPercent: source.batteryLevelPercent
    )
    let body = try StatusSnapshotBody(
        hostID: decoded.body.hostID,
        generation: decoded.body.generation,
        revision: decoded.body.revision,
        observedAtUnixMilliseconds: decoded.body.observedAtUnixMilliseconds,
        validForMilliseconds: decoded.body.validForMilliseconds,
        hostState: decoded.body.hostState,
        system: system
    )
    let reconstructed = try WireEnvelope(
        version: decoded.version,
        messageID: decoded.messageID,
        correlationID: decoded.correlationID,
        channel: decoded.channel,
        sentAtUnixMilliseconds: decoded.sentAtUnixMilliseconds,
        body: body
    )

    #expect(try WireCodec.encode(reconstructed) == WireCodec.encode(decoded))
}

@Test func authoritativeStatusRequestDecodesAndCanonicalizes() throws {
    let data = try fixture("valid/status-snapshot-request.json")
    let envelope = try WireCodec.decode(
        WireEnvelope<StatusSnapshotRequestBody>.self,
        from: data
    )

    #expect(envelope.kind == .statusSnapshotRequest)
    #expect(envelope.correlationID == nil)

    let canonical = try WireCodec.encode(envelope)
    #expect(sha256Hex(canonical) == "4af64d84131471b9df26e916271611a0b6cdff15099367d58600cf028d95fca8")
}

@Test func authoritativeSessionFixtureDecodesAndCanonicalizes() throws {
    let data = try fixture("valid/session-describe-response.json")
    let envelope = try WireCodec.decode(
        WireEnvelope<SessionDescriptionBody>.self,
        from: data
    )

    #expect(envelope.body.deviceState == .activeMonitorOnly)
    #expect(envelope.body.authorizationEpoch.rawValue == 1)

    let canonical = try WireCodec.encode(envelope)
    #expect(sha256Hex(canonical) == "3f689d31f13b11c693d0087d91f09caa2931f5a8783d08b63b439a50b4dc6aae")
}

@Test func authoritativeAuthenticationFixturesDecodeAndCanonicalize() throws {
    let hello = try decodeCanonicalFixture(
        "valid/auth-hello.json",
        as: AuthHelloBody.self,
        expectedSHA256: "dc74051c48b99fc6f57acc43ebb5945cf6d69410571faba83c9fbbdfffd2044b"
    )
    let challenge = try decodeCanonicalFixture(
        "valid/auth-challenge.json",
        as: AuthChallengeBody.self,
        expectedSHA256: "1781f1dd03eb1e90be4743ac93e5c19cba0ccde6cbafcc7fca02cc14a0517a68"
    )
    let proof = try decodeCanonicalFixture(
        "valid/auth-proof.json",
        as: AuthProofBody.self,
        expectedSHA256: "ffc28e40e76bf6f314884422264b1feddc025c8cd9d99659b06150da975563d6"
    )

    #expect(hello.body.clientNonce.rawValue == Data(0x10...0x2f))
    #expect(challenge.body.connectionID.rawValue == Data(0x00...0x0f))
    #expect(challenge.body.serverNonce.rawValue == Data(0x30...0x4f))
    #expect(proof.body.signature.rawValue.count == 64)
}

@Test func authoritativeRouteObservationDecodesAndCanonicalizes() throws {
    let envelope = try decodeCanonicalFixture(
        "valid/route-observation-private-dns.json",
        as: RouteObservationBodyV1.self,
        expectedSHA256:
            "70b3c9122fc52ac7e65836c101bc7b2305d1ebbc954ea17be851049b9572cf4e"
    )

    #expect(envelope.correlationID == nil)
    #expect(envelope.body.routeClass == .privateDNS)
    #expect(envelope.body.observationSequence == 1)
    #expect(envelope.body.connectionID.rawValue == Data(0x00...0x0f))
    #expect(envelope.body.configuredRouteID.rawValue == Data(0x50...0x5f))

    let acknowledgement = try decodeCanonicalFixture(
        "valid/route-observation-ack-private-dns.json",
        as: RouteObservationAcknowledgementBodyV1.self,
        expectedSHA256:
            "79fc1603f2e98c068081ea726d21da9161c4ea1461a3d64802b4d713e07eb01e"
    )
    #expect(acknowledgement.correlationID == envelope.messageID)
    #expect(acknowledgement.body.connectionID == envelope.body.connectionID)
    #expect(
        acknowledgement.body.configuredRouteID
            == envelope.body.configuredRouteID
    )
    #expect(acknowledgement.body.routeClass == envelope.body.routeClass)
    #expect(
        acknowledgement.body.observationSequence
            == envelope.body.observationSequence
    )
    #expect(acknowledgement.body.validForMilliseconds == 30_000)
}

@Test func invalidRouteObservationFixturesFailClosed() throws {
    for path in [
        "invalid/route-observation-unknown-class.json",
        "invalid/route-observation-zero-sequence.json",
    ] {
        #expect(throws: (any Error).self) {
            _ = try WireCodec.decode(
                WireEnvelope<RouteObservationBodyV1>.self,
                from: fixture(path)
            )
        }
    }
}

@Test func authoritativePairingFixturesDecodeAndCanonicalize() throws {
    let begin = try decodeCanonicalFixture(
        "valid/pairing-begin.json",
        as: PairingBeginBody.self,
        expectedSHA256: "b2c92bb43974c62041d47310384c5ed49119a73aaabccd0898224d23bc149746"
    )
    let challenge = try decodeCanonicalFixture(
        "valid/pairing-challenge.json",
        as: PairingChallengeBody.self,
        expectedSHA256: "b0a1b997d461bddc7bb1c83152a15778153ac23c545c05f7ba6dc3a586ae0df1"
    )
    let prove = try decodeCanonicalFixture(
        "valid/pairing-prove.json",
        as: PairingProveBody.self,
        expectedSHA256: "9c1d801fe1fce470dfb58d218fecdfcf9b31d02b7685bd89665ac2731e37bd91"
    )
    let pending = try decodeCanonicalFixture(
        "valid/pairing-pending-approval.json",
        as: PairingPendingApprovalBody.self,
        expectedSHA256: "3208043cc9164b0cc3b9fb4a372fb975ba415ce6e9b2b29a5b7f901bb00f5ddd"
    )
    let complete = try decodeCanonicalFixture(
        "valid/pairing-complete.json",
        as: PairingCompleteBody.self,
        expectedSHA256: "4e218672c33dd24064ade731f8762ab83271e8f72106d2ca2da2f7270d823cc7"
    )

    #expect(begin.body.sessionPublicKey.rawValue.first == 0x04)
    #expect(begin.body.approvalPublicKey.rawValue.first == 0x04)
    #expect(challenge.body.hostNonce.rawValue == Data(0x30...0x4f))
    #expect(
        prove.body.secretProof.rawValue.base64EncodedString()
            == "YL88vnfAL6yi/D0gtpQMG2CxUtHzd6qIsVjGvtfKZgw="
    )
    #expect(
        pending.body.transcriptDigest.rawValue.base64EncodedString()
            == "A1pTAuirGuutta0GPxRQX2XTb/mkdzptlvOP00x1ccE="
    )
    #expect(pending.body.authenticationString.rawValue == "23F-6F5")
    #expect(complete.body.deviceState == .activeMonitorOnly)
}

@Test func authenticationAndPairingEncodingRejectsInvalidCanonicalForms() throws {
    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<AuthHelloBody>.self,
            from: fixture("invalid/auth-hello-noncanonical-base64url.json")
        )
    }
    #expect(throws: WireError.self) {
        try WireCodec.decode(
            WireEnvelope<PairingBeginBody>.self,
            from: fixture("invalid/pairing-begin-nonnull-correlation.json")
        )
    }
}

@Test func envelopeConstructionEnforcesAuthenticationCorrelationDirection() throws {
    let helloFixture = try WireCodec.decode(
        WireEnvelope<AuthHelloBody>.self,
        from: fixture("valid/auth-hello.json")
    )
    let challengeFixture = try WireCodec.decode(
        WireEnvelope<AuthChallengeBody>.self,
        from: fixture("valid/auth-challenge.json")
    )

    #expect(throws: WireError.self) {
        try WireEnvelope(
            messageID: helloFixture.messageID,
            correlationID: helloFixture.messageID,
            sentAtUnixMilliseconds: helloFixture.sentAtUnixMilliseconds,
            body: helloFixture.body
        )
    }
    #expect(throws: WireError.self) {
        try WireEnvelope(
            messageID: challengeFixture.messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: challengeFixture.sentAtUnixMilliseconds,
            body: challengeFixture.body
        )
    }
}

@Test func authoritativePairingQRRoundTripsCanonicalTextAndPinsRoutesSeparately() throws {
    let data = try fixture("valid/pairing-qr-payload.json")
    let payload = try JSONDecoder().decode(PairingQRCodePayload.self, from: data)
    let text = try PairingQRCodeCodec.encode(payload)
    let decoded = try PairingQRCodeCodec.decode(
        text,
        nowUnixMilliseconds: 1_787_198_400_000
    )

    #expect(decoded == payload)
    #expect(decoded.endpoints.map(\.kind) == [.bonjour, .ipv4, .dns])
    #expect(decoded.hostFingerprint.rawValue == Data(0x80...0x9f))
    #expect(text.hasPrefix("maccompanion://pair/v0.1/"))
    #expect(text.utf8.count <= PairingQRCodeCodec.maximumTextBytes)
}

@Test func pairingQRRejectsExpiryAndNoncanonicalRepresentationsBeforeRouting() throws {
    let payload = try JSONDecoder().decode(
        PairingQRCodePayload.self,
        from: fixture("valid/pairing-qr-payload.json")
    )
    let text = try PairingQRCodeCodec.encode(payload)

    #expect(throws: WireError.self) {
        _ = try PairingQRCodeCodec.decode(
            text,
            nowUnixMilliseconds: payload.expiresAtUnixMilliseconds
        )
    }
    #expect(throws: WireError.self) {
        _ = try PairingQRCodeCodec.decode(
            text + "=",
            nowUnixMilliseconds: 1_787_198_400_000
        )
    }
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(
            PairingQRCodePayload.self,
            from: fixture("invalid/pairing-qr-noncanonical-ipv4.json")
        )
    }
}

@Test func unknownEnvelopeFieldIsRejected() throws {
    let data = try fixture("invalid/status-snapshot-unknown-field.json")
    #expect(throws: (any Error).self) {
        try WireCodec.decode(WireEnvelope<StatusSnapshotBody>.self, from: data)
    }
}

@Test func isolatedStatusBoundFailureIsRejected() throws {
    let data = try fixture("invalid/status-snapshot-invalid-bounds.json")
    #expect(throws: (any Error).self) {
        try WireCodec.decode(WireEnvelope<StatusSnapshotBody>.self, from: data)
    }
}

@Test func duplicateKeysAreRejectedBeforeDecoding() throws {
    #expect(throws: WireError.self) {
        try WireCodec.decode(
            WireEnvelope<StatusSnapshotRequestBody>.self,
            from: fixture("invalid/status-snapshot-duplicate-kind.json")
        )
    }
}

@Test func unsafeIntegerFixtureIsRejectedBeforeDecoding() throws {
    #expect(throws: WireError.self) {
        try WireCodec.decode(
            WireEnvelope<StatusSnapshotRequestBody>.self,
            from: fixture("invalid/status-snapshot-unsafe-integer.json")
        )
    }
}

@Test func malformedJSONClassesAreRejectedByStrictParser() {
    let floatingPoint = Data("{\"x\":1.5}".utf8)
    let tooDeep = Data(("{\"x\":" + String(repeating: "[", count: 12)
        + "0" + String(repeating: "]", count: 12) + "}").utf8)
    let invalidUTF8 = Data([0x7b, 0x22, 0x78, 0x22, 0x3a, 0x22, 0xff, 0x22, 0x7d])

    for payload in [floatingPoint, tooDeep, invalidUTF8] {
        #expect(throws: WireError.self) {
            try WireCodec.decode(
                WireEnvelope<StatusSnapshotRequestBody>.self,
                from: payload
            )
        }
    }
}

@Test func lengthPrefixDecoderHandlesFragmentedAndAdjacentFrames() throws {
    let firstPayload = Data("{\"a\":1}".utf8)
    let secondPayload = Data("{\"b\":2}".utf8)
    let bytes = try LengthPrefixedFrameDecoder.encode(firstPayload)
        + LengthPrefixedFrameDecoder.encode(secondPayload)

    var decoder = LengthPrefixedFrameDecoder()
    #expect(try decoder.append(bytes.prefix(3)).isEmpty)
    let frames = try decoder.append(bytes.dropFirst(3))
    #expect(frames == [firstPayload, secondPayload])
}

@Test func zeroAndOversizedFramesFailBeforeAllocation() {
    var decoder = LengthPrefixedFrameDecoder()
    #expect(throws: WireError.self) {
        try decoder.append(Data([0, 0, 0, 0]))
    }

    var oversized = LengthPrefixedFrameDecoder()
    #expect(throws: WireError.self) {
        try oversized.append(Data([0, 1, 0, 1]))
    }
}

@Test func oneLargeReadCanContainMultipleMaximumFrames() throws {
    let payloads = (0..<3).map { Data(repeating: UInt8($0), count: WireLimits.maximumFrameBytes) }
    let combined = try payloads.reduce(into: Data()) { bytes, payload in
        bytes.append(try LengthPrefixedFrameDecoder.encode(payload))
    }

    var decoder = LengthPrefixedFrameDecoder()
    #expect(try decoder.append(combined) == payloads)
}
