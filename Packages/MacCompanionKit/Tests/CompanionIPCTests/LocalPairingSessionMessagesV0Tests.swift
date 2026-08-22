import CompanionDiscovery
import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let localPairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000b1"
)!
private let localPairingCommandID = UUID(
    uuidString: "018f4200-0000-7000-8000-0000000000b1"
)!
private let localPairingCreatedAt: Int64 = 1_787_198_400_000
private let localPairingExpiresAt: Int64 = 1_787_198_700_000

private func localPairingReview() throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: UUID(
            uuidString: "018f4300-0000-7000-8000-0000000000b1"
        )!,
        pairingID: localPairingID,
        clientID: UUID(
            uuidString: "018f2000-0000-7000-8000-0000000000b1"
        )!,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x61, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x62, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x63, count: 32)),
        authenticationString: PairingAuthenticationString("23F-6F5"),
        expectedPolicyRevision: .init(rawValue: 7),
        expiresAtUnixMilliseconds: localPairingExpiresAt
    )
}

private func localPairingQRCode(
    pairingID: UUID = localPairingID,
    expiresAt: Int64 = localPairingExpiresAt
) throws -> String {
    let payload = try PairingQRCodePayload(
        pairingID: WireUUID(pairingID),
        oneTimeSecret: WireBytes32(Data(repeating: 0x41, count: 32)),
        expiresAtUnixMilliseconds: expiresAt,
        hostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 54_321
            ),
        ]
    )
    return try PairingQRCodeCodec.encode(payload)
}

@Test func localPairingCommandsAndReceiptsRoundTripExactly() throws {
    let create = try LocalPairingSessionCreateCommandV0(
        commandID: localPairingCommandID
    )
    #expect(try JSONDecoder().decode(
        LocalPairingSessionCreateCommandV0.self,
        from: JSONEncoder().encode(create)
    ) == create)

    let created = try LocalPairingSessionCreatedReceiptV0(
        correlationID: create.commandID,
        pairingID: localPairingID,
        encodedQRCode: localPairingQRCode(),
        createdAtUnixMilliseconds: localPairingCreatedAt,
        expiresAtUnixMilliseconds: localPairingExpiresAt
    )
    #expect(try JSONDecoder().decode(
        LocalPairingSessionCreatedReceiptV0.self,
        from: JSONEncoder().encode(created)
    ) == created)

    let dismiss = try LocalPairingSessionDismissCommandV0(
        commandID: UUID(),
        pairingID: localPairingID
    )
    #expect(try JSONDecoder().decode(
        LocalPairingSessionDismissCommandV0.self,
        from: JSONEncoder().encode(dismiss)
    ) == dismiss)

    let dismissed = try LocalPairingSessionDismissedReceiptV0(
        correlationID: dismiss.commandID,
        pairingID: dismiss.pairingID,
        completedAtUnixMilliseconds: localPairingCreatedAt + 1
    )
    #expect(try JSONDecoder().decode(
        LocalPairingSessionDismissedReceiptV0.self,
        from: JSONEncoder().encode(dismissed)
    ) == dismissed)
}

@Test func localPairingReceiptRejectsQRCodeBindingAndLifetimeMismatch() throws {
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingSessionCreatedReceiptV0(
            correlationID: localPairingCommandID,
            pairingID: UUID(),
            encodedQRCode: localPairingQRCode(),
            createdAtUnixMilliseconds: localPairingCreatedAt,
            expiresAtUnixMilliseconds: localPairingExpiresAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingSessionCreatedReceiptV0(
            correlationID: localPairingCommandID,
            pairingID: localPairingID,
            encodedQRCode: localPairingQRCode(
                expiresAt: localPairingExpiresAt + 1
            ),
            createdAtUnixMilliseconds: localPairingCreatedAt,
            expiresAtUnixMilliseconds: localPairingExpiresAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.invalidTime) {
        try LocalPairingSessionCreatedReceiptV0(
            correlationID: localPairingCommandID,
            pairingID: localPairingID,
            encodedQRCode: localPairingQRCode(),
            createdAtUnixMilliseconds: localPairingCreatedAt,
            expiresAtUnixMilliseconds: localPairingExpiresAt - 1
        )
    }
}

@Test func localPairingMessagesRejectUnknownMissingAndUnsupportedVersions() throws {
    let create = try LocalPairingSessionCreateCommandV0(
        commandID: localPairingCommandID
    )
    let data = try JSONEncoder().encode(create)
    let text = try #require(String(data: data, encoding: .utf8))
    let unknown = text.replacingOccurrences(
        of: "{",
        with: "{\"unknown\":true,",
        options: [],
        range: text.startIndex..<text.index(after: text.startIndex)
    )
    #expect(throws: LocalPairingSessionMessageErrorV0.unknownOrMissingField) {
        _ = try JSONDecoder().decode(
            LocalPairingSessionCreateCommandV0.self,
            from: Data(unknown.utf8)
        )
    }

    let missing = "{\"protocolVersion\":{\"major\":0,\"minor\":1}}"
    #expect(throws: LocalPairingSessionMessageErrorV0.unknownOrMissingField) {
        _ = try JSONDecoder().decode(
            LocalPairingSessionCreateCommandV0.self,
            from: Data(missing.utf8)
        )
    }

    #expect(throws: LocalPairingSessionMessageErrorV0.invalidVersion) {
        try LocalPairingSessionCreateCommandV0(
            protocolVersion: .init(major: 0, minor: 2),
            commandID: localPairingCommandID
        )
    }
}

@Test func localPairingMessagesRejectInvalidClockValuesAndQRCodeText() throws {
    #expect(throws: LocalPairingSessionMessageErrorV0.invalidQRCode) {
        try LocalPairingSessionCreatedReceiptV0(
            correlationID: localPairingCommandID,
            pairingID: localPairingID,
            encodedQRCode: "not-a-pairing-code",
            createdAtUnixMilliseconds: localPairingCreatedAt,
            expiresAtUnixMilliseconds: localPairingExpiresAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.invalidTime) {
        try LocalPairingSessionDismissedReceiptV0(
            correlationID: localPairingCommandID,
            pairingID: localPairingID,
            completedAtUnixMilliseconds: -1
        )
    }
}

@Test func localPairingReviewDecisionAndReceiptsRoundTripExactly() throws {
    let review = try localPairingReview()
    #expect(try JSONDecoder().decode(
        LocalPairingReviewV0.self,
        from: JSONEncoder().encode(review)
    ) == review)

    let command = try LocalPairingDecisionCommandV0(
        commandID: UUID(),
        review: review,
        deviceDisplayName: DeviceDisplayName("Jenny's iPhone"),
        decision: .approve,
        decidedAtUnixMilliseconds: localPairingCreatedAt
    )
    #expect(command.matches(review))
    #expect(try JSONDecoder().decode(
        LocalPairingDecisionCommandV0.self,
        from: JSONEncoder().encode(command)
    ) == command)

    let approved = try LocalPairingDecisionReceiptV0(
        correlationID: command.commandID,
        reviewID: command.reviewID,
        pairingID: command.pairingID,
        clientID: command.clientID,
        decision: .approve,
        deviceID: UUID(),
        storedDisplayName: command.deviceDisplayName,
        completedAtUnixMilliseconds: command.decidedAtUnixMilliseconds + 1
    )
    try approved.validate(against: command)
    #expect(try JSONDecoder().decode(
        LocalPairingDecisionReceiptV0.self,
        from: JSONEncoder().encode(approved)
    ) == approved)

    let declineCommand = try LocalPairingDecisionCommandV0(
        commandID: UUID(),
        review: review,
        deviceDisplayName: nil,
        decision: .decline,
        decidedAtUnixMilliseconds: localPairingCreatedAt
    )
    let declined = try LocalPairingDecisionReceiptV0(
        correlationID: declineCommand.commandID,
        reviewID: declineCommand.reviewID,
        pairingID: declineCommand.pairingID,
        clientID: declineCommand.clientID,
        decision: .decline,
        deviceID: nil,
        storedDisplayName: nil,
        completedAtUnixMilliseconds:
            declineCommand.decidedAtUnixMilliseconds + 1
    )
    try declined.validate(against: declineCommand)
    let declinedJSON = try #require(String(
        data: JSONEncoder().encode(declined),
        encoding: .utf8
    ))
    let declineCommandJSON = try #require(String(
        data: JSONEncoder().encode(declineCommand),
        encoding: .utf8
    ))
    #expect(declineCommandJSON.contains("\"deviceDisplayName\":null"))
    #expect(declinedJSON.contains("\"deviceID\":null"))
    #expect(declinedJSON.contains("\"storedDisplayName\":null"))
}

@Test func localPairingDecisionBindsTheCompleteAgentReview() throws {
    let review = try localPairingReview()
    let command = try LocalPairingDecisionCommandV0(
        commandID: UUID(),
        review: review,
        deviceDisplayName: DeviceDisplayName("Jenny's iPhone"),
        decision: .approve,
        decidedAtUnixMilliseconds: localPairingCreatedAt
    )
    let changed = try LocalPairingReviewV0(
        reviewID: review.reviewID,
        pairingID: review.pairingID,
        clientID: review.clientID,
        sessionPublicKeyFingerprint: review.sessionPublicKeyFingerprint,
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x7f, count: 32)
        ),
        transcriptDigest: review.transcriptDigest,
        authenticationString: review.authenticationString,
        expectedPolicyRevision: review.expectedPolicyRevision,
        expiresAtUnixMilliseconds: review.expiresAtUnixMilliseconds
    )
    #expect(!command.matches(changed))

    let receipt = try LocalPairingDecisionReceiptV0(
        correlationID: UUID(),
        reviewID: command.reviewID,
        pairingID: command.pairingID,
        clientID: command.clientID,
        decision: .approve,
        deviceID: UUID(),
        storedDisplayName: command.deviceDisplayName,
        completedAtUnixMilliseconds: command.decidedAtUnixMilliseconds + 1
    )
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try receipt.validate(against: command)
    }
}

@Test func localPairingReviewPayloadsRejectUnknownAndPartialOutcomes() throws {
    let review = try localPairingReview()
    let data = try JSONEncoder().encode(review)
    let text = try #require(String(data: data, encoding: .utf8))
    let unknown = text.replacingOccurrences(
        of: "{",
        with: "{\"unknown\":true,",
        options: [],
        range: text.startIndex..<text.index(after: text.startIndex)
    )
    #expect(throws: LocalPairingSessionMessageErrorV0.unknownOrMissingField) {
        _ = try JSONDecoder().decode(
            LocalPairingReviewV0.self,
            from: Data(unknown.utf8)
        )
    }

    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingDecisionCommandV0(
            commandID: UUID(),
            review: review,
            deviceDisplayName: nil,
            decision: .approve,
            decidedAtUnixMilliseconds: localPairingCreatedAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingDecisionCommandV0(
            commandID: UUID(),
            review: review,
            deviceDisplayName: DeviceDisplayName("Unused name"),
            decision: .decline,
            decidedAtUnixMilliseconds: localPairingCreatedAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingDecisionReceiptV0(
            correlationID: UUID(),
            reviewID: review.reviewID,
            pairingID: review.pairingID,
            clientID: review.clientID,
            decision: .approve,
            deviceID: UUID(),
            storedDisplayName: nil,
            completedAtUnixMilliseconds: localPairingCreatedAt
        )
    }
    #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
        try LocalPairingDecisionReceiptV0(
            correlationID: UUID(),
            reviewID: review.reviewID,
            pairingID: review.pairingID,
            clientID: review.clientID,
            decision: .decline,
            deviceID: UUID(),
            storedDisplayName: nil,
            completedAtUnixMilliseconds: localPairingCreatedAt
        )
    }
}

@Test func localPairingReviewRejectsUnsafeIdentifiersAndPolicyRevision() throws {
    let valid = try localPairingReview()
    let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))

    for identifiers in [
        (zero, valid.pairingID, valid.clientID),
        (valid.reviewID, zero, valid.clientID),
        (valid.reviewID, valid.pairingID, zero),
    ] {
        #expect(throws: LocalPairingSessionMessageErrorV0.invalidIdentifier) {
            try LocalPairingReviewV0(
                reviewID: identifiers.0,
                pairingID: identifiers.1,
                clientID: identifiers.2,
                sessionPublicKeyFingerprint:
                    valid.sessionPublicKeyFingerprint,
                approvalPublicKeyFingerprint:
                    valid.approvalPublicKeyFingerprint,
                transcriptDigest: valid.transcriptDigest,
                authenticationString: valid.authenticationString,
                expectedPolicyRevision: valid.expectedPolicyRevision,
                expiresAtUnixMilliseconds:
                    valid.expiresAtUnixMilliseconds
            )
        }
    }

    for revision in [UInt64(0), PolicyRevision.maximumWireValue + 1] {
        #expect(throws: LocalPairingSessionMessageErrorV0.bindingMismatch) {
            try LocalPairingReviewV0(
                reviewID: valid.reviewID,
                pairingID: valid.pairingID,
                clientID: valid.clientID,
                sessionPublicKeyFingerprint:
                    valid.sessionPublicKeyFingerprint,
                approvalPublicKeyFingerprint:
                    valid.approvalPublicKeyFingerprint,
                transcriptDigest: valid.transcriptDigest,
                authenticationString: valid.authenticationString,
                expectedPolicyRevision: .init(rawValue: revision),
                expiresAtUnixMilliseconds:
                    valid.expiresAtUnixMilliseconds
            )
        }
    }
}
