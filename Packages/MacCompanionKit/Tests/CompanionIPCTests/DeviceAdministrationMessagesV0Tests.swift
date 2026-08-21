import CompanionDomain
import CompanionIPC
import Foundation
import Testing

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
