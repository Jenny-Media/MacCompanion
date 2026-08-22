import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let wireBootstrapCreatedAtV1: Int64 = 1_787_198_400_000

private func wireBootstrapOfferV1() throws
    -> LocalRemoteAccessBootstrapOfferV0
{
    try LocalRemoteAccessBootstrapOfferV0(
        offerID: UUID(
            uuidString: "018f7200-0000-7000-8000-000000000001"
        )!,
        expectedIntentRevision: 11,
        createdAtUnixMilliseconds: wireBootstrapCreatedAtV1,
        expiresAtUnixMilliseconds: wireBootstrapCreatedAtV1 + 300_000
    )
}

private func wireBootstrapCommandV1() throws
    -> LocalRemoteAccessEnableCommandV0
{
    try LocalRemoteAccessEnableCommandV0(
        commandID: UUID(
            uuidString: "018f7200-0000-7000-8000-000000000002"
        )!,
        offer: wireBootstrapOfferV1(),
        confirmedAtUnixMilliseconds: wireBootstrapCreatedAtV1 + 1
    )
}

@Test func bootstrapWireCodecRoundTripsEveryCanonicalPayload() throws {
    let offer = try wireBootstrapOfferV1()
    let offerData = try LocalRemoteAccessBootstrapWireCodecV1
        .encodeOffer(offer)
    #expect(try CanonicalJSON.canonicalize(offerData) == offerData)
    #expect(try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(
        offerData
    ) == offer)

    let command = try wireBootstrapCommandV1()
    let commandData = try LocalRemoteAccessBootstrapWireCodecV1
        .encodeEnableCommand(command)
    #expect(try CanonicalJSON.canonicalize(commandData) == commandData)
    #expect(try LocalRemoteAccessBootstrapWireCodecV1.decodeEnableCommand(
        commandData
    ) == command)

    let receipt = try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: command.offer.offerID,
        intentRevision: command.offer.expectedIntentRevision + 1,
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    let receiptData = try LocalRemoteAccessBootstrapWireCodecV1
        .encodeEnabledReceipt(receipt)
    #expect(try CanonicalJSON.canonicalize(receiptData) == receiptData)
    #expect(try LocalRemoteAccessBootstrapWireCodecV1.decodeEnabledReceipt(
        receiptData
    ) == receipt)
}

@Test func bootstrapWireCodecRejectsNoncanonicalAndDuplicateJSON() throws {
    let canonical = try LocalRemoteAccessBootstrapWireCodecV1.encodeOffer(
        wireBootstrapOfferV1()
    )
    #expect(
        throws: LocalRemoteAccessBootstrapWireCodecErrorV1
            .nonCanonicalPayload
    ) {
        try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(
            Data([0x20]) + canonical
        )
    }

    let text = try #require(String(data: canonical, encoding: .utf8))
    let duplicate = Data(
        text.replacingOccurrences(
            of: "{\"createdAtUnixMilliseconds\":",
            with: "{\"createdAtUnixMilliseconds\":\(wireBootstrapCreatedAtV1),\"createdAtUnixMilliseconds\":"
        ).utf8
    )
    #expect(
        throws: LocalRemoteAccessBootstrapWireCodecErrorV1.invalidPayload
    ) {
        try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(duplicate)
    }
}

@Test func bootstrapWireCodecRejectsOpenCanonicalPayload() throws {
    let canonical = try LocalRemoteAccessBootstrapWireCodecV1.encodeOffer(
        wireBootstrapOfferV1()
    )
    guard case let .object(members) = try CanonicalJSON.parse(canonical) else {
        Issue.record("bootstrap offer payload was not an object")
        return
    }
    let open = CanonicalJSON.canonicalData(
        for: .object(
            members + [
                CanonicalJSONMember(
                    key: "unexpected",
                    value: .boolean(true)
                )
            ]
        )
    )
    #expect(
        throws: LocalRemoteAccessBootstrapWireCodecErrorV1.invalidPayload
    ) {
        try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(open)
    }
}

@Test func bootstrapWireCodecRejectsEmptyAndOversizedPayloads() {
    #expect(
        throws: LocalRemoteAccessBootstrapWireCodecErrorV1.emptyPayload
    ) {
        try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(Data())
    }
    #expect(
        throws: LocalRemoteAccessBootstrapWireCodecErrorV1.payloadTooLarge
    ) {
        try LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(
            Data(
                repeating: 0x20,
                count: LocalRemoteAccessBootstrapWireCodecV1
                    .maximumEncodedBytes + 1
            )
        )
    }
}
