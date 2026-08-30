import CompanionDomain
import CompanionIPC
import Foundation
import Testing

@Test func deviceRevocationReviewTransportRoundTripsExactBindings() throws {
    let request = try LocalDeviceRevocationReviewRequestV1(commandID: UUID(), deviceID: UUID(), requestedAtUnixMilliseconds: 1_000)
    let review = try LocalDeviceRevocationReviewV0(reviewID: UUID(), deviceID: request.deviceID,
        deviceDisplayName: .init("Disposable device"), state: .activeGranted,
        authorizationEpoch: .init(rawValue: 2), grantRevision: .init(rawValue: 3),
        createdAtUnixMilliseconds: 1_001, expiresAtUnixMilliseconds: 301_001)
    let reply = try LocalDeviceRevocationReviewReplyV1(correlationID: request.commandID, review: review)
    try reply.validate(against: request)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationReviewRequest(
        LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewRequest(request)) == request)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationReviewReply(
        LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewReply(reply)) == reply)
    let command = try LocalDeviceRevocationCommandV0(commandID: UUID(), review: review, confirmedAtUnixMilliseconds: 1_002)
    let receipt = try LocalDeviceRevokedReceiptV0(correlationID: command.commandID, reviewID: review.reviewID,
        deviceID: request.deviceID, authorizationEpoch: .init(rawValue: 3), grantRevision: .init(rawValue: 4),
        completedAtUnixMilliseconds: 1_003)
    try receipt.validate(against: command)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationCommand(
        LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationCommand(command)) == command)
    #expect(try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevokedReceipt(
        LocalMenuPairingCommandWireCodecV1.encodeDeviceRevokedReceipt(receipt)) == receipt)
    #expect(throws: DeviceAdministrationMessageErrorV0.bindingMismatch) {
        try LocalDeviceRevocationReviewReplyV1(correlationID: UUID(), review: review).validate(against: request)
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.bindingMismatch) {
        try reply.validate(against: .init(commandID: request.commandID, deviceID: UUID(), requestedAtUnixMilliseconds: 1_000))
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.bindingMismatch) {
        try reply.validate(against: .init(commandID: request.commandID, deviceID: request.deviceID, requestedAtUnixMilliseconds: 1_002))
    }
}

@Test func deviceRevocationReviewTransportRejectsMalformedAndCrossKindPayloads() throws {
    let request = try LocalDeviceRevocationReviewRequestV1(commandID: UUID(), deviceID: UUID(), requestedAtUnixMilliseconds: 1_000)
    let encoded = try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewRequest(request)
    #expect(throws: LocalMenuPairingCommandWireCodecErrorV1.invalidPayload) {
        try LocalMenuPairingCommandWireCodecV1.decodeInteractiveControlGrantReviewRequest(encoded)
    }
    for key in ["unexpected", "deviceID"] {
        var value = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        if key == "unexpected" { value[key] = true } else { value.removeValue(forKey: key) }
        let malformed = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalMenuPairingCommandWireCodecErrorV1.invalidPayload) {
            try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationReviewRequest(malformed)
        }
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidTime) {
        try LocalDeviceRevocationReviewRequestV1(commandID: UUID(), deviceID: UUID(), requestedAtUnixMilliseconds: -1)
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidIdentifier) {
        try LocalDeviceRevocationReviewRequestV1(commandID: request.deviceID, deviceID: request.deviceID, requestedAtUnixMilliseconds: 1)
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidVersion) {
        try LocalDeviceRevocationReviewRequestV1(protocolVersion: .init(major: 1, minor: 0), commandID: UUID(), deviceID: UUID(), requestedAtUnixMilliseconds: 1)
    }
}

@Test func deviceRevocationReviewTransportMatchesIndexedProfile() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        repository.appendingPathComponent("spec/fixtures/local-xpc-menu-pairing-commands-v0.1.json"))) as? [String: Any])
    let profile = try #require(fixture["reviewedDeviceRevocation"] as? [String: Any])
    #expect(profile["authorizationMethod"] as? String == "administerDevices")
    #expect(profile["reviewLifetimeMilliseconds"] as? Int == 300_000)
    #expect(profile["generationLossWithdrawsUnconfirmedReview"] as? Bool == true)
    let request = try LocalDeviceRevocationReviewRequestV1(commandID: UUID(), deviceID: UUID(), requestedAtUnixMilliseconds: 1)
    let encoded = try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewRequest(request)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(Set(object.keys) == Set(try #require(profile["reviewRequestKeys"] as? [String])))
}

@Test func localDeviceNameCommandAndReceiptAreExactlyCorrelated() throws {
    let command = try SetDeviceDisplayNameCommandV0(
        commandID: UUID(),
        deviceID: UUID(),
        displayName: DeviceDisplayName("Jenny’s iPhone"),
        occurredAtUnixMilliseconds: 1_000
    )
    let receipt = try SetDeviceDisplayNameReceiptV0(
        correlationID: command.commandID,
        deviceID: command.deviceID,
        displayName: command.displayName,
        storedAtUnixMilliseconds: 1_001
    )
    try receipt.validate(against: command)

    #expect(throws: DeviceAdministrationMessageErrorV0.bindingMismatch) {
        try SetDeviceDisplayNameReceiptV0(
            correlationID: UUID(),
            deviceID: command.deviceID,
            displayName: command.displayName,
            storedAtUnixMilliseconds: 1_001
        ).validate(against: command)
    }
}

@Test func localDeviceNameMessagesRoundTripThroughValidatedDomainName() throws {
    let command = try SetDeviceDisplayNameCommandV0(
        commandID: UUID(),
        deviceID: UUID(),
        displayName: DeviceDisplayName("Local iPhone"),
        occurredAtUnixMilliseconds: 2_000
    )
    let encoded = try JSONEncoder().encode(command)
    #expect(try JSONDecoder().decode(
        SetDeviceDisplayNameCommandV0.self,
        from: encoded
    ) == command)
}

@Test func localDeviceNameMessagesRejectUnsafeTimesAndVersions() throws {
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidTime) {
        try SetDeviceDisplayNameCommandV0(
            commandID: UUID(),
            deviceID: UUID(),
            displayName: DeviceDisplayName("iPhone"),
            occurredAtUnixMilliseconds: -1
        )
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidVersion) {
        try SetDeviceDisplayNameCommandV0(
            protocolVersion: .init(major: 0, minor: 2),
            commandID: UUID(),
            deviceID: UUID(),
            displayName: DeviceDisplayName("iPhone"),
            occurredAtUnixMilliseconds: 1
        )
    }
}

@Test func decodingCannotBypassLocalDeviceNameMessageValidation() throws {
    let command = try SetDeviceDisplayNameCommandV0(
        commandID: UUID(),
        deviceID: UUID(),
        displayName: DeviceDisplayName("iPhone"),
        occurredAtUnixMilliseconds: 1
    )
    var object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(command)
        ) as? [String: Any]
    )
    object["occurredAtUnixMilliseconds"] = -1
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidTime) {
        try JSONDecoder().decode(
            SetDeviceDisplayNameCommandV0.self,
            from: invalid
        )
    }
}

private func localDeviceRevocationReviewV0(
    state: DeviceAuthorizationState = .activeGranted
) throws -> LocalDeviceRevocationReviewV0 {
    try LocalDeviceRevocationReviewV0(
        reviewID: UUID(),
        deviceID: UUID(),
        deviceDisplayName: DeviceDisplayName("Local iPhone"),
        state: state,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 7),
        createdAtUnixMilliseconds: 10_000,
        expiresAtUnixMilliseconds: 310_000
    )
}

@Test func localDeviceRevocationRoundTripsAndBindsExactAdvance() throws {
    let review = try localDeviceRevocationReviewV0()
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 10_001
    )
    let receipt = try LocalDeviceRevokedReceiptV0(
        correlationID: command.commandID,
        reviewID: review.reviewID,
        deviceID: review.deviceID,
        authorizationEpoch: .init(rawValue: 5),
        grantRevision: .init(rawValue: 8),
        completedAtUnixMilliseconds: 10_002
    )
    try receipt.validate(against: command)

    let encoded = try JSONEncoder().encode(command)
    #expect(try JSONDecoder().decode(
        LocalDeviceRevocationCommandV0.self,
        from: encoded
    ) == command)
    #expect(try JSONDecoder().decode(
        LocalDeviceRevokedReceiptV0.self,
        from: JSONEncoder().encode(receipt)
    ) == receipt)
}

@Test func localDeviceRevocationRejectsStaleAndNonTerminalShapes() throws {
    let review = try localDeviceRevocationReviewV0()
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidTime) {
        try LocalDeviceRevocationCommandV0(
            commandID: UUID(),
            review: review,
            confirmedAtUnixMilliseconds: review.expiresAtUnixMilliseconds
        )
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidState) {
        try localDeviceRevocationReviewV0(state: .revoked)
    }
    #expect(throws: DeviceAdministrationMessageErrorV0.invalidState) {
        try LocalDeviceRevokedReceiptV0(
            correlationID: UUID(),
            reviewID: review.reviewID,
            deviceID: review.deviceID,
            state: .suspended,
            authorizationEpoch: .init(rawValue: 5),
            grantRevision: .init(rawValue: 8),
            completedAtUnixMilliseconds: 10_002
        )
    }
}

@Test func localDeviceRevocationDecodingIsClosed() throws {
    let review = try localDeviceRevocationReviewV0()
    var object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(review)
        ) as? [String: Any]
    )
    object["remoteName"] = "untrusted"
    #expect(throws: DeviceAdministrationMessageErrorV0.unknownOrMissingField) {
        try JSONDecoder().decode(
            LocalDeviceRevocationReviewV0.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
