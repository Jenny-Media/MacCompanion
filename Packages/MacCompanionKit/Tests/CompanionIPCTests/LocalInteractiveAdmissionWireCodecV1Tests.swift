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

@Test func interactiveAdmissionNullDisplayMatchesIndexedCodecVectors() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        repository.appendingPathComponent("spec/fixtures/local-xpc-interactive-admission-transport-v0.1.json"))) as? [String: Any])
    let vectors = try #require(object["nullDisplayCodecVectors"] as? [String: String])
    let expectedPublication = Data(try #require(vectors["publication"]).utf8)
    let expectedReceipt = Data(try #require(vectors["receipt"]).utf8)
    let publication = try LocalInteractiveAdmissionPublicationV1(commandID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration, revision: 2, selectedDisplayID: nil)
    let receipt = try LocalInteractiveAdmissionPublishedReceiptV1(correlationID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration, revision: 2, selectedDisplayID: nil)
    #expect(try LocalInteractiveAdmissionWireCodecV1.encodePublication(publication) == expectedPublication)
    #expect(try LocalInteractiveAdmissionWireCodecV1.encodeReceipt(receipt) == expectedReceipt)
    #expect(try LocalInteractiveAdmissionWireCodecV1.decodePublication(expectedPublication) == publication)
    let decodedReceipt = try LocalInteractiveAdmissionWireCodecV1.decodeReceipt(expectedReceipt)
    #expect(decodedReceipt == receipt)
    try decodedReceipt.validate(against: publication)
}

@Test func interactiveAdmissionCodecRejectsMissingDisplayKeyInPublicationAndReceipt() throws {
    let publication = try LocalInteractiveAdmissionPublicationV1(commandID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration, revision: 2, selectedDisplayID: nil)
    let receipt = try LocalInteractiveAdmissionPublishedReceiptV1(correlationID: admissionCommandID,
        menuAppGeneration: admissionMenuGeneration, revision: 2, selectedDisplayID: nil)
    func omittingDisplay(_ data: Data) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "selectedDisplayID")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    let missingPublication = try omittingDisplay(LocalInteractiveAdmissionWireCodecV1.encodePublication(publication))
    let missingReceipt = try omittingDisplay(LocalInteractiveAdmissionWireCodecV1.encodeReceipt(receipt))
    #expect(throws: LocalInteractiveAdmissionWireCodecErrorV1.invalidPayload) {
        try LocalInteractiveAdmissionWireCodecV1.decodePublication(missingPublication)
    }
    #expect(throws: LocalInteractiveAdmissionWireCodecErrorV1.invalidPayload) {
        try LocalInteractiveAdmissionWireCodecV1.decodeReceipt(missingReceipt)
    }
}

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
