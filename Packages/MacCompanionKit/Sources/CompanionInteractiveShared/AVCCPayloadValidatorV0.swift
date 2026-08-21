import Foundation

public enum AVCCPayloadErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case unsupportedNALLengthSize
    case invalidParameterSet
    case truncatedNALUnit
    case invalidNALUnit
    case missingVideoSlice
    case keyframeFlagMismatch
}

public enum AVCCPayloadValidatorV0 {
    private static let profilesWithExtensions: Set<UInt8> = [
        44, 83, 86, 100, 110, 118, 122, 128, 134, 135, 138, 139, 144, 244,
    ]

    public static func validateDecoderConfiguration(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard (7...4_096).contains(bytes.count),
              bytes[0] == 1,
              bytes[4] & 0xfc == 0xfc,
              bytes[5] & 0xe0 == 0xe0 else {
            throw AVCCPayloadErrorV0.invalidConfiguration
        }
        guard bytes[4] & 0x03 == 3 else {
            throw AVCCPayloadErrorV0.unsupportedNALLengthSize
        }

        var cursor = 6
        let sequenceParameterSetCount = Int(bytes[5] & 0x1f)
        guard (1...8).contains(sequenceParameterSetCount) else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        for _ in 0..<sequenceParameterSetCount {
            try consumeParameterSet(type: 7, bytes: bytes, cursor: &cursor)
        }
        guard cursor < bytes.count else {
            throw AVCCPayloadErrorV0.invalidConfiguration
        }
        let pictureParameterSetCount = Int(bytes[cursor])
        cursor += 1
        guard (1...8).contains(pictureParameterSetCount) else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        for _ in 0..<pictureParameterSetCount {
            try consumeParameterSet(type: 8, bytes: bytes, cursor: &cursor)
        }

        if cursor < bytes.count {
            guard profilesWithExtensions.contains(bytes[1]),
                  bytes.count - cursor >= 4,
                  bytes[cursor] & 0xfc == 0xfc,
                  bytes[cursor + 1] & 0xf8 == 0xf8,
                  bytes[cursor + 2] & 0xf8 == 0xf8 else {
                throw AVCCPayloadErrorV0.invalidConfiguration
            }
            cursor += 3
            let extensionCount = Int(bytes[cursor])
            cursor += 1
            guard extensionCount <= 8 else {
                throw AVCCPayloadErrorV0.invalidParameterSet
            }
            for _ in 0..<extensionCount {
                try consumeParameterSet(type: 13, bytes: bytes, cursor: &cursor)
            }
        }
        guard cursor == bytes.count else {
            throw AVCCPayloadErrorV0.invalidConfiguration
        }
    }

    public static func decoderParameterSets(
        _ data: Data
    ) throws -> AVCCDecoderParameterSetsV0 {
        try validateDecoderConfiguration(data)
        let bytes = [UInt8](data)
        var cursor = 6
        var sequence: [Data] = []
        for _ in 0..<Int(bytes[5] & 0x1f) {
            sequence.append(try readParameterSet(bytes, cursor: &cursor))
        }
        let pictureCount = Int(bytes[cursor])
        cursor += 1
        var picture: [Data] = []
        for _ in 0..<pictureCount {
            picture.append(try readParameterSet(bytes, cursor: &cursor))
        }
        return AVCCDecoderParameterSetsV0(
            sequence: sequence,
            picture: picture
        )
    }

    public static func validateAccessUnit(
        _ data: Data,
        cleanKeyframe: Bool
    ) throws {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw AVCCPayloadErrorV0.truncatedNALUnit }
        var cursor = 0
        var hasVideoSlice = false
        var hasIDR = false
        while cursor < bytes.count {
            guard bytes.count - cursor >= 4 else {
                throw AVCCPayloadErrorV0.truncatedNALUnit
            }
            let length = Int(readUInt32(bytes, cursor))
            cursor += 4
            guard length > 0, length <= bytes.count - cursor else {
                throw AVCCPayloadErrorV0.truncatedNALUnit
            }
            let header = bytes[cursor]
            let type = header & 0x1f
            guard header & 0x80 == 0, (1...23).contains(type) else {
                throw AVCCPayloadErrorV0.invalidNALUnit
            }
            if (1...5).contains(type) {
                hasVideoSlice = true
                hasIDR = hasIDR || type == 5
            }
            cursor += length
        }
        guard hasVideoSlice else { throw AVCCPayloadErrorV0.missingVideoSlice }
        guard hasIDR == cleanKeyframe else {
            throw AVCCPayloadErrorV0.keyframeFlagMismatch
        }
    }

    private static func consumeParameterSet(
        type expectedType: UInt8,
        bytes: [UInt8],
        cursor: inout Int
    ) throws {
        guard bytes.count - cursor >= 2 else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
        cursor += 2
        guard length > 0, length <= bytes.count - cursor,
              bytes[cursor] & 0x80 == 0,
              bytes[cursor] & 0x1f == expectedType else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        cursor += length
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { ($0 << 8) | UInt32(bytes[offset + $1]) }
    }

    private static func readParameterSet(
        _ bytes: [UInt8],
        cursor: inout Int
    ) throws -> Data {
        guard bytes.count - cursor >= 2 else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
        cursor += 2
        guard length > 0, length <= bytes.count - cursor else {
            throw AVCCPayloadErrorV0.invalidParameterSet
        }
        let result = Data(bytes[cursor..<(cursor + length)])
        cursor += length
        return result
    }
}

public struct AVCCDecoderParameterSetsV0: Equatable, Sendable {
    public let sequence: [Data]
    public let picture: [Data]

    public init(sequence: [Data], picture: [Data]) {
        self.sequence = sequence
        self.picture = picture
    }
}
