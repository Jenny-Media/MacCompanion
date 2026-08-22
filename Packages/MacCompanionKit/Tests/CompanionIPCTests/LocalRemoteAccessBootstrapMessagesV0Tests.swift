import CompanionIPC
import Foundation
import Testing

private let bootstrapOfferIDV0 = UUID(
    uuidString: "018f7100-0000-7000-8000-000000000001"
)!
private let bootstrapCommandIDV0 = UUID(
    uuidString: "018f7100-0000-7000-8000-000000000002"
)!
private let bootstrapCreatedAtV0: Int64 = 1_787_198_400_000
private let bootstrapExpiresAtV0: Int64 = bootstrapCreatedAtV0 + 300_000

private func bootstrapOfferV0(
    expectedRevision: Int64 = 0
) throws -> LocalRemoteAccessBootstrapOfferV0 {
    try LocalRemoteAccessBootstrapOfferV0(
        offerID: bootstrapOfferIDV0,
        expectedIntentRevision: expectedRevision,
        createdAtUnixMilliseconds: bootstrapCreatedAtV0,
        expiresAtUnixMilliseconds: bootstrapExpiresAtV0
    )
}

private func bootstrapCommandV0(
    offer: LocalRemoteAccessBootstrapOfferV0
) throws -> LocalRemoteAccessEnableCommandV0 {
    try LocalRemoteAccessEnableCommandV0(
        commandID: bootstrapCommandIDV0,
        offer: offer,
        confirmedAtUnixMilliseconds: bootstrapCreatedAtV0 + 1
    )
}

@Test func remoteAccessBootstrapMessagesRoundTripExactly() throws {
    let offer = try bootstrapOfferV0(expectedRevision: 7)
    let command = try bootstrapCommandV0(offer: offer)
    let receipt = try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: offer.offerID,
        intentRevision: 8,
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    try receipt.validate(against: command)

    #expect(try JSONDecoder().decode(
        LocalRemoteAccessBootstrapOfferV0.self,
        from: JSONEncoder().encode(offer)
    ) == offer)
    #expect(try JSONDecoder().decode(
        LocalRemoteAccessEnableCommandV0.self,
        from: JSONEncoder().encode(command)
    ) == command)
    #expect(try JSONDecoder().decode(
        LocalRemoteAccessEnabledReceiptV0.self,
        from: JSONEncoder().encode(receipt)
    ) == receipt)
}

@Test func remoteAccessBootstrapOfferRequiresExactSafeRevisionAndLifetime() {
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.invalidRevision) {
        try LocalRemoteAccessBootstrapOfferV0(
            offerID: bootstrapOfferIDV0,
            expectedIntentRevision: -1,
            createdAtUnixMilliseconds: bootstrapCreatedAtV0,
            expiresAtUnixMilliseconds: bootstrapExpiresAtV0
        )
    }
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.invalidTime) {
        try LocalRemoteAccessBootstrapOfferV0(
            offerID: bootstrapOfferIDV0,
            expectedIntentRevision: 0,
            createdAtUnixMilliseconds: bootstrapCreatedAtV0,
            expiresAtUnixMilliseconds: bootstrapExpiresAtV0 - 1
        )
    }
}

@Test func remoteAccessBootstrapCommandRequiresCurrentOfferWindow() throws {
    let offer = try bootstrapOfferV0()
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.invalidTime) {
        try LocalRemoteAccessEnableCommandV0(
            commandID: bootstrapCommandIDV0,
            offer: offer,
            confirmedAtUnixMilliseconds: offer.expiresAtUnixMilliseconds
        )
    }
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.invalidVersion) {
        try LocalRemoteAccessEnableCommandV0(
            protocolVersion: .init(major: 0, minor: 2),
            commandID: bootstrapCommandIDV0,
            offer: offer,
            confirmedAtUnixMilliseconds: offer.createdAtUnixMilliseconds
        )
    }
}

@Test func remoteAccessBootstrapReceiptBindsCommandOfferAndRevision() throws {
    let offer = try bootstrapOfferV0(expectedRevision: 4)
    let command = try bootstrapCommandV0(offer: offer)
    let wrongRevision = try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: offer.offerID,
        intentRevision: 7,
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.bindingMismatch) {
        try wrongRevision.validate(against: command)
    }
    let wrongOffer = try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: UUID(),
        intentRevision: 5,
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    #expect(throws: LocalRemoteAccessBootstrapMessageErrorV0.bindingMismatch) {
        try wrongOffer.validate(against: command)
    }
}

@Test func remoteAccessBootstrapMessagesRejectUnknownOrMissingFields() throws {
    let offerData = try JSONEncoder().encode(bootstrapOfferV0())
    let offerText = try #require(String(data: offerData, encoding: .utf8))
    let unknown = offerText.replacingOccurrences(
        of: "{",
        with: "{\"unknown\":true,",
        options: [],
        range: offerText.startIndex..<offerText.index(after: offerText.startIndex)
    )
    #expect(
        throws: LocalRemoteAccessBootstrapMessageErrorV0
            .unknownOrMissingField
    ) {
        _ = try JSONDecoder().decode(
            LocalRemoteAccessBootstrapOfferV0.self,
            from: Data(unknown.utf8)
        )
    }

    let missing = """
    {"protocolVersion":{"major":0,"minor":1},"offerID":"\(bootstrapOfferIDV0.uuidString.lowercased())"}
    """
    #expect(
        throws: LocalRemoteAccessBootstrapMessageErrorV0
            .unknownOrMissingField
    ) {
        _ = try JSONDecoder().decode(
            LocalRemoteAccessBootstrapOfferV0.self,
            from: Data(missing.utf8)
        )
    }

    let commandData = try JSONEncoder().encode(
        bootstrapCommandV0(offer: bootstrapOfferV0())
    )
    let commandText = try #require(
        String(data: commandData, encoding: .utf8)
    )
    let broadenedConsent = commandText.replacingOccurrences(
        of: "agentRemoteAccessV1",
        with: "unrestrictedControlV1"
    )
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            LocalRemoteAccessEnableCommandV0.self,
            from: Data(broadenedConsent.utf8)
        )
    }
}
