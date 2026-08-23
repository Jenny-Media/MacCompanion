import CompanionIPC
import Foundation
import Testing

private let admissionCommandID = UUID(
    uuidString: "018f6800-0000-7000-8000-000000000001"
)!
private let admissionMenuGeneration = UUID(
    uuidString: "018f6800-0000-7000-8000-000000000002"
)!
private let admissionDisplayID = UUID(
    uuidString: "018f6800-0000-7000-8000-000000000003"
)!

@Test func interactiveAdmissionCodecRoundTripsExactPublicationAndReceipt()
    throws
{
    let publication = try LocalInteractiveAdmissionPublicationV1(
        commandID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration,
        revision: 1,
        selectedDisplayID: admissionDisplayID
    )
    let encoded = try LocalInteractiveAdmissionWireCodecV1
        .encodePublication(publication)
    #expect(
        try LocalInteractiveAdmissionWireCodecV1
            .decodePublication(encoded) == publication
    )

    let receipt = try LocalInteractiveAdmissionPublishedReceiptV1(
        correlationID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration,
        revision: 1,
        selectedDisplayID: admissionDisplayID
    )
    let encodedReceipt = try LocalInteractiveAdmissionWireCodecV1
        .encodeReceipt(receipt)
    let decodedReceipt = try LocalInteractiveAdmissionWireCodecV1
        .decodeReceipt(encodedReceipt)
    #expect(decodedReceipt == receipt)
    try decodedReceipt.validate(against: publication)
}

@Test func interactiveAdmissionCodecRejectsUnknownNoncanonicalAndOversized()
    throws
{
    let publication = try LocalInteractiveAdmissionPublicationV1(
        commandID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration,
        revision: 1,
        selectedDisplayID: nil
    )
    let canonical = try LocalInteractiveAdmissionWireCodecV1
        .encodePublication(publication)
    #expect(
        throws: LocalInteractiveAdmissionWireCodecErrorV1
            .nonCanonicalPayload
    ) {
        try LocalInteractiveAdmissionWireCodecV1
            .decodePublication(Data(" \n".utf8) + canonical)
    }

    var object = try #require(
        JSONSerialization.jsonObject(with: canonical)
            as? [String: Any]
    )
    object["unexpected"] = true
    let unknown = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    #expect(
        throws: LocalInteractiveAdmissionWireCodecErrorV1
            .invalidPayload
    ) {
        try LocalInteractiveAdmissionWireCodecV1
            .decodePublication(unknown)
    }

    #expect(
        throws: LocalInteractiveAdmissionWireCodecErrorV1.payloadTooLarge
    ) {
        try LocalInteractiveAdmissionWireCodecV1.decodePublication(
            Data(
                repeating: 0x20,
                count: LocalInteractiveAdmissionWireCodecV1
                    .maximumEncodedBytes + 1
            )
        )
    }
}
