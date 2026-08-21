import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreMedia
import Foundation

public enum VideoToolboxAVCCOutputErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidParameterSets
    case inconsistentSequenceParameterSets
    case unsupportedParameterSet
    case unsupportedNALUnitHeaderLength
    case decoderConfigurationTooLarge
    case invalidAccessUnitLength
    case blockBufferCopyFailed
}

/// Builds the exact AVCDecoderConfigurationRecord accepted by the v0 media
/// profile. Parameter-set inputs are raw NAL units without Annex-B start codes.
public enum VideoToolboxAVCCOutputV0 {
    public static func makeDecoderConfiguration(
        sequenceParameterSets: [Data],
        pictureParameterSets: [Data],
        sequenceParameterSetExtensions: [Data] = []
    ) throws -> Data {
        guard (1...8).contains(sequenceParameterSets.count),
              (1...8).contains(pictureParameterSets.count),
              sequenceParameterSets.allSatisfy({
                  validParameterSet($0, type: 7, minimumLength: 4)
              }),
              pictureParameterSets.allSatisfy({
                  validParameterSet($0, type: 8, minimumLength: 1)
              }),
              sequenceParameterSetExtensions.count <= 8,
              sequenceParameterSetExtensions.allSatisfy({
                  validParameterSet($0, type: 13, minimumLength: 1)
              }) else {
            throw VideoToolboxAVCCOutputErrorV0.invalidParameterSets
        }
        let profileTriplet = sequenceParameterSets[0][1...3]
        guard sequenceParameterSets.dropFirst().allSatisfy({
            $0[1...3].elementsEqual(profileTriplet)
        }) else {
            throw VideoToolboxAVCCOutputErrorV0
                .inconsistentSequenceParameterSets
        }
        let encodedLength = 7
            + sequenceParameterSets.reduce(0) { $0 + 2 + $1.count }
            + pictureParameterSets.reduce(0) { $0 + 2 + $1.count }
            + (sequenceParameterSetExtensions.isEmpty ? 0 : 4)
            + sequenceParameterSetExtensions.reduce(0) {
                $0 + 2 + $1.count
            }
        guard encodedLength <= 4_096 else {
            throw VideoToolboxAVCCOutputErrorV0
                .decoderConfigurationTooLarge
        }

        var output = Data([
            1,
            sequenceParameterSets[0][1],
            sequenceParameterSets[0][2],
            sequenceParameterSets[0][3],
            0xff,
            0xe0 | UInt8(sequenceParameterSets.count),
        ])
        for parameterSet in sequenceParameterSets {
            appendLengthAndBytes(parameterSet, to: &output)
        }
        output.append(UInt8(pictureParameterSets.count))
        for parameterSet in pictureParameterSets {
            appendLengthAndBytes(parameterSet, to: &output)
        }
        if !sequenceParameterSetExtensions.isEmpty {
            // The v0 source and encoder profile is exactly 4:2:0, 8-bit.
            output.append(0xfd)
            output.append(0xf8)
            output.append(0xf8)
            output.append(UInt8(sequenceParameterSetExtensions.count))
            for parameterSet in sequenceParameterSetExtensions {
                appendLengthAndBytes(parameterSet, to: &output)
            }
        }
        assert(output.count == encodedLength)
        try AVCCPayloadValidatorV0.validateDecoderConfiguration(output)
        return output
    }

    public static func decoderConfiguration(
        from formatDescription: CMFormatDescription
    ) throws -> Data {
        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        ) == noErr else {
            throw VideoToolboxAVCCOutputErrorV0.invalidParameterSets
        }
        guard nalUnitHeaderLength == 4 else {
            throw VideoToolboxAVCCOutputErrorV0
                .unsupportedNALUnitHeaderLength
        }
        guard (2...24).contains(parameterSetCount) else {
            throw VideoToolboxAVCCOutputErrorV0.invalidParameterSets
        }

        var sequenceParameterSets: [Data] = []
        var pictureParameterSets: [Data] = []
        var sequenceParameterSetExtensions: [Data] = []
        for index in 0..<parameterSetCount {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            ) == noErr,
                  let pointer,
                  size > 0,
                  size <= Int(UInt16.max) else {
                throw VideoToolboxAVCCOutputErrorV0.invalidParameterSets
            }
            let parameterSet = Data(bytes: pointer, count: size)
            switch parameterSet[0] & 0x1f {
            case 7:
                sequenceParameterSets.append(parameterSet)
            case 8:
                pictureParameterSets.append(parameterSet)
            case 13:
                sequenceParameterSetExtensions.append(parameterSet)
            default:
                throw VideoToolboxAVCCOutputErrorV0
                    .unsupportedParameterSet
            }
        }
        return try makeDecoderConfiguration(
            sequenceParameterSets: sequenceParameterSets,
            pictureParameterSets: pictureParameterSets,
            sequenceParameterSetExtensions:
                sequenceParameterSetExtensions
        )
    }

    public static func copyAccessUnit(
        from blockBuffer: CMBlockBuffer,
        cleanKeyframe: Bool
    ) throws -> Data {
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard (1...8_388_608).contains(length) else {
            throw VideoToolboxAVCCOutputErrorV0.invalidAccessUnitLength
        }
        var output = Data(count: length)
        let status = output.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: bytes.baseAddress!
            )
        }
        guard status == noErr else {
            throw VideoToolboxAVCCOutputErrorV0.blockBufferCopyFailed
        }
        try AVCCPayloadValidatorV0.validateAccessUnit(
            output,
            cleanKeyframe: cleanKeyframe
        )
        return output
    }

    private static func validParameterSet(
        _ data: Data,
        type: UInt8,
        minimumLength: Int
    ) -> Bool {
        data.count >= minimumLength
            && data.count <= Int(UInt16.max)
            && data[0] & 0x80 == 0
            && data[0] & 0x1f == type
    }

    private static func appendLengthAndBytes(
        _ data: Data,
        to output: inout Data
    ) {
        let length = UInt16(data.count)
        output.append(UInt8(length >> 8))
        output.append(UInt8(length & 0xff))
        output.append(data)
    }
}
