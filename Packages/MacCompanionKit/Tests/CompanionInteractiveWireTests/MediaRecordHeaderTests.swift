import CompanionInteractiveWire
import CompanionTestSupport
import Foundation
import Testing

private struct MediaHeaderVector: Decodable {
    let headerHex: String
}

private func mediaVector(_ path: String) throws -> Data {
    let url = FixturePaths.authoritativeFixtures().appendingPathComponent(path)
    let vector = try JSONDecoder().decode(MediaHeaderVector.self, from: Data(contentsOf: url))
    guard vector.headerHex.count == MediaRecordHeader.byteCount * 2 else {
        throw MediaRecordError.truncated
    }
    var result = Data()
    var index = vector.headerHex.startIndex
    while index < vector.headerHex.endIndex {
        let next = vector.headerHex.index(index, offsetBy: 2)
        guard let byte = UInt8(vector.headerHex[index..<next], radix: 16) else {
            throw MediaRecordError.invalidMagic
        }
        result.append(byte)
        index = next
    }
    return result
}

@Test func authoritativeMediaHeaderHasExactOffsetsAndRoundTrips() throws {
    let bytes = try mediaVector("valid/interactive-media-header.json")
    let header = try MediaRecordHeader.decode(bytes)
    #expect(header.type == .videoAccessUnit)
    #expect(header.flags == [.cleanKeyframe])
    #expect(header.payloadLength == 4_096)
    #expect(header.interactiveSessionID.uuidString.lowercased() ==
        "018f6000-0000-7000-8000-000000000001")
    #expect(header.authorizationEpoch.rawValue == 4)
    #expect(header.surfaceID.uuidString.lowercased() ==
        "018f6100-0000-7000-8000-000000000001")
    #expect(header.surfaceRevision.rawValue == 2)
    #expect(header.coordinateSpaceRevision.rawValue == 3)
    #expect(header.mediaSequence == 7)
    #expect(header.presentationTimeNanoseconds == 123_456_789)
    #expect(header.encodedWidth == 1_920)
    #expect(header.encodedHeight == 1_080)
    #expect(header.encode() == bytes)
}

@Test func reservedMediaHeaderBitsFailClosed() throws {
    #expect(throws: MediaRecordError.reservedBitsSet) {
        try MediaRecordHeader.decode(
            mediaVector("invalid/interactive-media-header-reserved.json")
        )
    }
}

@Test func recordSpecificPayloadAndDimensionBoundsAreClosed() throws {
    let sessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
    let surfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!
    #expect(throws: MediaRecordError.invalidPayloadLength) {
        try MediaRecordHeader(
            type: .end,
            payloadLength: 1,
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            surfaceID: surfaceID,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            mediaSequence: 1,
            presentationTimeNanoseconds: 0,
            encodedWidth: 0,
            encodedHeight: 0
        )
    }
    #expect(throws: MediaRecordError.invalidDimensions) {
        try MediaRecordHeader(
            type: .videoAccessUnit,
            payloadLength: 1,
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            surfaceID: surfaceID,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            mediaSequence: 1,
            presentationTimeNanoseconds: 0,
            encodedWidth: 1_921,
            encodedHeight: 1_080
        )
    }
}
