import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let localRecoveryCreatedAtV0: Int64 = 1_787_284_800_000
private let localRecoveryExpiresAtV0 = localRecoveryCreatedAtV0 + 300_000

private func localRecoveryReviewV0(
    fingerprintByte: UInt8 = 0x31
) throws -> LocalHostIdentityRecoveryReviewV0 {
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        hostFingerprint: WireFingerprint(
            Data(repeating: fingerprintByte, count: 32)
        ),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: localRecoveryCreatedAtV0,
        expiresAtUnixMilliseconds: localRecoveryExpiresAtV0
    )
}

private func localRecoveryCommandV0()
    throws -> LocalHostIdentityRecoveryCommandV0
{
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        review: localRecoveryReviewV0(),
        confirmedAtUnixMilliseconds: localRecoveryCreatedAtV0 + 1
    )
}

@Test func localHostIdentityRecoveryMessagesRoundTripAndCorrelateExactly()
    throws
{
    let command = try localRecoveryCommandV0()
    let receipt = try LocalHostIdentityRecoveredReceiptV0(
        correlationID: command.commandID,
        recoveryID: command.recoveryID,
        replacedHostID: command.review.hostID,
        newHostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        newHostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    try receipt.validate(against: command)

    for value in [
        try JSONEncoder().encode(command.review),
        try JSONEncoder().encode(command),
        try JSONEncoder().encode(receipt),
    ] {
        #expect(!value.isEmpty)
    }
    #expect(try JSONDecoder().decode(
        LocalHostIdentityRecoveryReviewV0.self,
        from: JSONEncoder().encode(command.review)
    ) == command.review)
    #expect(try JSONDecoder().decode(
        LocalHostIdentityRecoveryCommandV0.self,
        from: JSONEncoder().encode(command)
    ) == command)
    #expect(try JSONDecoder().decode(
        LocalHostIdentityRecoveredReceiptV0.self,
        from: JSONEncoder().encode(receipt)
    ) == receipt)
}

@Test func localHostIdentityRecoveryReviewAndCommandEnforceClosedWindow()
    throws
{
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0.invalidTime) {
        try LocalHostIdentityRecoveryReviewV0(
            reviewID: UUID(),
            hostID: UUID(),
            hostFingerprint: WireFingerprint(Data(repeating: 1, count: 32)),
            cause: .suspectedCompromise,
            createdAtUnixMilliseconds: localRecoveryCreatedAtV0,
            expiresAtUnixMilliseconds: localRecoveryExpiresAtV0 + 1
        )
    }
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0.invalidTime) {
        try LocalHostIdentityRecoveryCommandV0(
            commandID: UUID(),
            recoveryID: UUID(),
            review: localRecoveryReviewV0(),
            confirmedAtUnixMilliseconds: localRecoveryExpiresAtV0
        )
    }
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0.invalidVersion) {
        try LocalHostIdentityRecoveryReviewV0(
            protocolVersion: .init(major: 0, minor: 2),
            reviewID: UUID(),
            hostID: UUID(),
            hostFingerprint: WireFingerprint(Data(repeating: 1, count: 32)),
            cause: .userRequestedReset,
            createdAtUnixMilliseconds: localRecoveryCreatedAtV0,
            expiresAtUnixMilliseconds: localRecoveryExpiresAtV0
        )
    }
}

@Test func localHostIdentityRecoveryDecodingRejectsUnknownAndBroadenedFields()
    throws
{
    let command = try localRecoveryCommandV0()
    var commandObject = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(command)
        ) as? [String: Any]
    )
    commandObject["replacementKeyTag"] = "caller-choice"
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0
        .unknownOrMissingField) {
        try JSONDecoder().decode(
            LocalHostIdentityRecoveryCommandV0.self,
            from: JSONSerialization.data(withJSONObject: commandObject)
        )
    }

    var reviewObject = try #require(commandObject["review"] as? [String: Any])
    reviewObject["scope"] = "invalidateOnePhone"
    commandObject.removeValue(forKey: "replacementKeyTag")
    commandObject["review"] = reviewObject
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            LocalHostIdentityRecoveryCommandV0.self,
            from: JSONSerialization.data(withJSONObject: commandObject)
        )
    }
}

@Test func localHostIdentityRecoveryReceiptRejectsStaleOrUnrotatedIdentity()
    throws
{
    let command = try localRecoveryCommandV0()
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0
        .invalidReplacement) {
        try LocalHostIdentityRecoveredReceiptV0(
            correlationID: command.commandID,
            recoveryID: command.recoveryID,
            replacedHostID: command.review.hostID,
            newHostID: command.review.hostID,
            newHostFingerprint: command.review.hostFingerprint,
            completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
        )
    }

    let stale = try LocalHostIdentityRecoveredReceiptV0(
        correlationID: command.commandID,
        recoveryID: command.recoveryID,
        replacedHostID: UUID(),
        newHostID: UUID(),
        newHostFingerprint: WireFingerprint(Data(repeating: 0x73, count: 32)),
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    #expect(throws: LocalHostIdentityRecoveryMessageErrorV0.bindingMismatch) {
        try stale.validate(against: command)
    }
}

@Test func localHostIdentityRecoveryWireCodecIsCanonicalBoundedAndTyped()
    throws
{
    let command = try localRecoveryCommandV0()
    let receipt = try LocalHostIdentityRecoveredReceiptV0(
        correlationID: command.commandID,
        recoveryID: command.recoveryID,
        replacedHostID: command.review.hostID,
        newHostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        newHostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    let commandBytes = try LocalHostIdentityRecoveryWireCodecV1
        .encodeCommand(command)
    let receiptBytes = try LocalHostIdentityRecoveryWireCodecV1
        .encodeReceipt(receipt)

    #expect(try LocalHostIdentityRecoveryWireCodecV1
        .decodeCommand(commandBytes) == command)
    #expect(try LocalHostIdentityRecoveryWireCodecV1
        .decodeReceipt(receiptBytes) == receipt)
    #expect(commandBytes.count
        <= LocalHostIdentityRecoveryWireCodecV1.maximumEncodedBytes)
    #expect(receiptBytes.count
        <= LocalHostIdentityRecoveryWireCodecV1.maximumEncodedBytes)
    #expect(throws: LocalHostIdentityRecoveryWireCodecErrorV1.self) {
        try LocalHostIdentityRecoveryWireCodecV1.decodeCommand(receiptBytes)
    }

    var noncanonical = Data([0x7b, 0x20])
    noncanonical.append(commandBytes.dropFirst())
    #expect(throws: LocalHostIdentityRecoveryWireCodecErrorV1
        .nonCanonicalPayload) {
        try LocalHostIdentityRecoveryWireCodecV1.decodeCommand(noncanonical)
    }
    #expect(throws: LocalHostIdentityRecoveryWireCodecErrorV1
        .payloadTooLarge) {
        try LocalHostIdentityRecoveryWireCodecV1.decodeCommand(
            Data(
                repeating: 0x20,
                count: LocalHostIdentityRecoveryWireCodecV1
                    .maximumEncodedBytes + 1
            )
        )
    }
}
