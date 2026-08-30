import CompanionDomain
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let displayOne = UUID(
    uuidString: "018f6900-0000-7000-8000-000000000001"
)!
private let displayTwo = UUID(
    uuidString: "018f6900-0000-7000-8000-000000000002"
)!

private func displayCandidate(
    _ id: UUID,
    ordinal: UInt8,
    isMain: Bool
) throws -> InteractiveDisplayCandidateV1 {
    try .init(
        displayID: .init(id),
        ordinal: ordinal,
        pixelWidth: ordinal == 1 ? 3_024 : 2_560,
        pixelHeight: ordinal == 1 ? 1_964 : 1_440,
        isMain: isMain
    )
}

@Test func interactiveDisplayCatalogRoundTripsTwoDisplays() throws {
    let body = try InteractiveDisplayCatalogResponseBodyV1(
        authorizationEpoch: .init(rawValue: 3),
        admissionRevision: 7,
        selectedDisplayID: .init(displayTwo),
        validForMilliseconds: 10_000,
        displays: [
            try displayCandidate(displayOne, ordinal: 1, isMain: true),
            try displayCandidate(displayTwo, ordinal: 2, isMain: false),
        ]
    )
    let envelope = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        channel: .command,
        sentAtUnixMilliseconds: 10,
        body: body
    )
    let data = try WireCodec.encode(envelope)
    let decoded = try WireCodec.decode(
        WireEnvelope<InteractiveDisplayCatalogResponseBodyV1>.self,
        from: data
    )
    #expect(decoded.body == body)
    #expect(decoded.body.selectedDisplayID.rawValue == displayTwo)
}

@Test func interactiveDisplayCatalogRejectsMissingSelectedDisplay() throws {
    #expect(throws: InteractiveDisplayMessageErrorV1.self) {
        _ = try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: .init(rawValue: 1),
            admissionRevision: 1,
            selectedDisplayID: .init(displayTwo),
            validForMilliseconds: 1_000,
            displays: [
                try displayCandidate(displayOne, ordinal: 1, isMain: true),
            ]
        )
    }
}

@Test func interactiveDisplayCatalogRejectsDuplicateOrdinals() throws {
    #expect(throws: InteractiveDisplayMessageErrorV1.self) {
        _ = try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: .init(rawValue: 1),
            admissionRevision: 1,
            selectedDisplayID: .init(displayOne),
            validForMilliseconds: 1_000,
            displays: [
                try displayCandidate(displayOne, ordinal: 1, isMain: true),
                try displayCandidate(displayTwo, ordinal: 1, isMain: false),
            ]
        )
    }
}

@Test func interactiveDisplaySelectRoundTripsExpectedRevision() throws {
    let body = try InteractiveDisplaySelectBodyV1(
        authorizationEpoch: .init(rawValue: 2),
        expectedAdmissionRevision: 8,
        displayID: .init(displayTwo)
    )
    let envelope = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        channel: .command,
        sentAtUnixMilliseconds: 20,
        body: body
    )
    let data = try WireCodec.encode(envelope)
    let decoded = try WireCodec.decode(
        WireEnvelope<InteractiveDisplaySelectBodyV1>.self,
        from: data
    )
    #expect(decoded.body == body)
}
