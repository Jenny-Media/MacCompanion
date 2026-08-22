import CompanionDiscovery
import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private struct MenuPairingCommandSamplesV1 {
    let create: LocalPairingSessionCreateCommandV0
    let created: LocalPairingSessionCreatedReceiptV0
    let dismiss: LocalPairingSessionDismissCommandV0
    let dismissed: LocalPairingSessionDismissedReceiptV0
    let decision: LocalPairingDecisionCommandV0
    let decided: LocalPairingDecisionReceiptV0

    static func make() throws -> Self {
        let createID = UUID(
            uuidString: "018f8100-0000-7000-8000-0000000000c1"
        )!
        let pairingID = UUID(
            uuidString: "018f8200-0000-7000-8000-0000000000c1"
        )!
        let dismissID = UUID(
            uuidString: "018f8300-0000-7000-8000-0000000000c1"
        )!
        let reviewID = UUID(
            uuidString: "018f8400-0000-7000-8000-0000000000c1"
        )!
        let clientID = UUID(
            uuidString: "018f8500-0000-7000-8000-0000000000c1"
        )!
        let decisionID = UUID(
            uuidString: "018f8600-0000-7000-8000-0000000000c1"
        )!
        let deviceID = UUID(
            uuidString: "018f8700-0000-7000-8000-0000000000c1"
        )!
        let createdAt: Int64 = 1_787_198_400_000
        let expiresAt = createdAt + 300_000
        let qr = try PairingQRCodePayload(
            pairingID: WireUUID(pairingID),
            oneTimeSecret: WireBytes32(Data(repeating: 0x51, count: 32)),
            expiresAtUnixMilliseconds: expiresAt,
            hostFingerprint: WireFingerprint(
                Data(repeating: 0x52, count: 32)
            ),
            endpoints: [
                try EndpointCandidate(
                    kind: .bonjour,
                    value: "mac-018f._maccompanion._tcp.local.",
                    port: 59_653
                ),
            ]
        )
        let review = try LocalPairingReviewV0(
            reviewID: reviewID,
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyFingerprint: WireFingerprint(
                Data(repeating: 0x61, count: 32)
            ),
            approvalPublicKeyFingerprint: WireFingerprint(
                Data(repeating: 0x62, count: 32)
            ),
            transcriptDigest: WireBytes32(
                Data(repeating: 0x63, count: 32)
            ),
            authenticationString: PairingAuthenticationString("23F-6F5"),
            expectedPolicyRevision: PolicyRevision(rawValue: 1),
            expiresAtUnixMilliseconds: expiresAt
        )
        let name = try DeviceDisplayName("Jenny's iPhone")

        return try Self(
            create: LocalPairingSessionCreateCommandV0(commandID: createID),
            created: LocalPairingSessionCreatedReceiptV0(
                correlationID: createID,
                pairingID: pairingID,
                encodedQRCode: PairingQRCodeCodec.encode(qr),
                createdAtUnixMilliseconds: createdAt,
                expiresAtUnixMilliseconds: expiresAt
            ),
            dismiss: LocalPairingSessionDismissCommandV0(
                commandID: dismissID,
                pairingID: pairingID
            ),
            dismissed: LocalPairingSessionDismissedReceiptV0(
                correlationID: dismissID,
                pairingID: pairingID,
                completedAtUnixMilliseconds: createdAt + 1
            ),
            decision: LocalPairingDecisionCommandV0(
                commandID: decisionID,
                review: review,
                deviceDisplayName: name,
                decision: .approve,
                decidedAtUnixMilliseconds: createdAt + 2
            ),
            decided: LocalPairingDecisionReceiptV0(
                correlationID: decisionID,
                reviewID: reviewID,
                pairingID: pairingID,
                clientID: clientID,
                decision: .approve,
                deviceID: deviceID,
                storedDisplayName: name,
                completedAtUnixMilliseconds: createdAt + 3
            )
        )
    }
}

@Test func localMenuPairingCommandCodecRoundTripsEveryClosedPayload()
    throws
{
    let value = try MenuPairingCommandSamplesV1.make()
    let pairs: [(Data, Data)] = try [
        (
            LocalMenuPairingCommandWireCodecV1.encodeCreateCommand(
                value.create
            ),
            LocalMenuPairingCommandWireCodecV1.encodeCreatedReceipt(
                value.created
            )
        ),
        (
            LocalMenuPairingCommandWireCodecV1.encodeDismissCommand(
                value.dismiss
            ),
            LocalMenuPairingCommandWireCodecV1.encodeDismissedReceipt(
                value.dismissed
            )
        ),
        (
            LocalMenuPairingCommandWireCodecV1.encodeDecisionCommand(
                value.decision
            ),
            LocalMenuPairingCommandWireCodecV1.encodeDecisionReceipt(
                value.decided
            )
        ),
    ]
    for pair in pairs {
        #expect(!pair.0.isEmpty)
        #expect(!pair.1.isEmpty)
        #expect(pair.0.count <= 4_096)
        #expect(pair.1.count <= 4_096)
        #expect(try CanonicalJSON.canonicalize(pair.0) == pair.0)
        #expect(try CanonicalJSON.canonicalize(pair.1) == pair.1)
    }

    #expect(try LocalMenuPairingCommandWireCodecV1.decodeCreateCommand(
        pairs[0].0
    ) == value.create)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeCreatedReceipt(
        pairs[0].1
    ) == value.created)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDismissCommand(
        pairs[1].0
    ) == value.dismiss)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDismissedReceipt(
        pairs[1].1
    ) == value.dismissed)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDecisionCommand(
        pairs[2].0
    ) == value.decision)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDecisionReceipt(
        pairs[2].1
    ) == value.decided)
}

@Test func localMenuPairingCommandCodecRejectsCrossKindAndOpenPayloads()
    throws
{
    let value = try MenuPairingCommandSamplesV1.make()
    let create = try LocalMenuPairingCommandWireCodecV1.encodeCreateCommand(
        value.create
    )
    #expect(
        throws: LocalMenuPairingCommandWireCodecErrorV1.invalidPayload
    ) {
        try LocalMenuPairingCommandWireCodecV1.decodeDismissCommand(create)
    }

    guard case let .object(members) = try CanonicalJSON.parse(create) else {
        Issue.record("create command did not encode as an object")
        return
    }
    let open = CanonicalJSON.canonicalData(for: .object(
        members + [CanonicalJSONMember(key: "unexpected", value: .null)]
    ))
    #expect(
        throws: LocalMenuPairingCommandWireCodecErrorV1.invalidPayload
    ) {
        try LocalMenuPairingCommandWireCodecV1.decodeCreateCommand(open)
    }

    #expect(
        throws: LocalMenuPairingCommandWireCodecErrorV1.nonCanonicalPayload
    ) {
        try LocalMenuPairingCommandWireCodecV1.decodeCreateCommand(
            Data([0x20]) + create
        )
    }
    #expect(
        throws: LocalMenuPairingCommandWireCodecErrorV1.emptyPayload
    ) {
        try LocalMenuPairingCommandWireCodecV1.decodeCreateCommand(Data())
    }
    #expect(
        throws: LocalMenuPairingCommandWireCodecErrorV1.payloadTooLarge
    ) {
        try LocalMenuPairingCommandWireCodecV1.decodeCreateCommand(
            Data(repeating: 0x20, count: 4_097)
        )
    }
}

@Test func authoritativeMenuPairingCommandFixtureMatchesCodeContract()
    throws
{
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    let fixture = repository
        .appendingPathComponent("spec/fixtures")
        .appendingPathComponent(
            "local-xpc-menu-pairing-commands-v0.1.json"
        )
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fixture))
            as? [String: Any]
    )
    #expect(
        object["maximumPayloadBytes"] as? Int
            == LocalMenuPairingCommandWireCodecV1.maximumEncodedBytes
    )
    #expect(object["maximumInFlightCommandsPerGeneration"] as? Int == 1)
    #expect(object["serverOperationTimeoutMilliseconds"] as? Int == 4_000)
    #expect(object["clientReplyTimeoutMilliseconds"] as? Int == 5_000)
    let commands = try #require(object["commands"] as? [[String: Any]])
    #expect(commands.count == 3)
    #expect(Set(commands.compactMap {
        $0["authorizationMethod"] as? String
    }) == Set([
        LocalIPCMethod.createPairingSession.rawValue,
        LocalIPCMethod.dismissPairingSession.rawValue,
        LocalIPCMethod.resolveLocalApproval.rawValue,
    ]))
    #expect(Set(commands.compactMap { $0["kind"] as? String }) == Set([
        "command.pairing-session.create",
        "command.pairing-session.dismiss",
        "command.pairing-decision.resolve",
    ]))
}
