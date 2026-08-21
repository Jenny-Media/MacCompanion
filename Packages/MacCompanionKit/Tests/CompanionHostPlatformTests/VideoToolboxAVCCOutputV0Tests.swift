import CompanionHostPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreMedia
import Foundation
import Testing

private let videoToolboxTestSPS = Data([
    0x67, 0x42, 0xc0, 0x1f, 0xda, 0x01, 0x40, 0x16,
    0xec, 0x04, 0x40, 0x00, 0x00, 0x03, 0x00, 0x40,
    0x00, 0x00, 0x0c, 0x83, 0xc6, 0x0c, 0x65, 0x80,
])
private let videoToolboxTestPPS = Data([0x68, 0xce, 0x3c, 0x80])

private func videoToolboxTestFormatDescription(
    nalUnitHeaderLength: Int32 = 4
) throws -> CMFormatDescription {
    try videoToolboxTestSPS.withUnsafeBytes { spsBytes in
        try videoToolboxTestPPS.withUnsafeBytes { ppsBytes in
            let pointers = [
                spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
            ]
            let sizes = [videoToolboxTestSPS.count, videoToolboxTestPPS.count]
            var output: CMFormatDescription?
            let status = pointers.withUnsafeBufferPointer { pointerBuffer in
                sizes.withUnsafeBufferPointer { sizeBuffer in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: pointers.count,
                        parameterSetPointers: pointerBuffer.baseAddress!,
                        parameterSetSizes: sizeBuffer.baseAddress!,
                        nalUnitHeaderLength: nalUnitHeaderLength,
                        formatDescriptionOut: &output
                    )
                }
            }
            guard status == noErr, let output else {
                throw VideoToolboxAVCCOutputErrorV0.invalidParameterSets
            }
            return output
        }
    }
}

private func videoToolboxTestBlockBuffer(_ data: Data) throws
    -> CMBlockBuffer
{
    var output: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: data.count,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: data.count,
        flags: 0,
        blockBufferOut: &output
    ) == noErr,
          let output else {
        throw VideoToolboxAVCCOutputErrorV0.blockBufferCopyFailed
    }
    let status = data.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: output,
            offsetIntoDestination: 0,
            dataLength: data.count
        )
    }
    guard status == noErr else {
        throw VideoToolboxAVCCOutputErrorV0.blockBufferCopyFailed
    }
    return output
}

@Test func AVCCOutputBuildsExactBoundedDecoderConfiguration() throws {
    let output = try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
        sequenceParameterSets: [Data([0x67, 66, 0, 30])],
        pictureParameterSets: [Data([0x68, 0])]
    )

    #expect(output == Data([
        1, 66, 0, 30, 0xff, 0xe1,
        0, 4, 0x67, 66, 0, 30,
        1, 0, 2, 0x68, 0,
    ]))
    try AVCCPayloadValidatorV0.validateDecoderConfiguration(output)
}

@Test func AVCCOutputRejectsWrongAndInconsistentParameterSets() {
    #expect(throws: VideoToolboxAVCCOutputErrorV0.invalidParameterSets) {
        _ = try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
            sequenceParameterSets: [Data([0x68, 66, 0, 30])],
            pictureParameterSets: [Data([0x68, 0])]
        )
    }
    #expect(
        throws:
            VideoToolboxAVCCOutputErrorV0
                .inconsistentSequenceParameterSets
    ) {
        _ = try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
            sequenceParameterSets: [
                Data([0x67, 66, 0, 30]),
                Data([0x67, 66, 0, 31]),
            ],
            pictureParameterSets: [Data([0x68, 0])]
        )
    }
    #expect(
        throws:
            VideoToolboxAVCCOutputErrorV0.decoderConfigurationTooLarge
    ) {
        _ = try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
            sequenceParameterSets: [
                Data([0x67, 66, 0, 30])
                    + Data(repeating: 0, count: 4_080),
            ],
            pictureParameterSets: [Data([0x68, 0])]
        )
    }
}

@Test func AVCCOutputSupportsTheBoundedHighProfileExtensionForm()
    throws
{
    let output = try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
        sequenceParameterSets: [Data([0x67, 100, 0, 41])],
        pictureParameterSets: [Data([0x68, 0])],
        sequenceParameterSetExtensions: [Data([0x6d, 0])]
    )

    try AVCCPayloadValidatorV0.validateDecoderConfiguration(output)
    #expect(output.suffix(4) == Data([0, 2, 0x6d, 0]))
}

@Test func AVCCOutputExtractsParameterSetsFromCoreMedia() throws {
    let description = try videoToolboxTestFormatDescription()

    let output = try VideoToolboxAVCCOutputV0.decoderConfiguration(
        from: description
    )

    try AVCCPayloadValidatorV0.validateDecoderConfiguration(output)
    #expect(output.contains(videoToolboxTestSPS))
    #expect(output.contains(videoToolboxTestPPS))
}

@Test func AVCCOutputCopiesAndValidatesCoreMediaBlockBytes() throws {
    let accessUnit = Data([0, 0, 0, 2, 0x65, 0])
    let blockBuffer = try videoToolboxTestBlockBuffer(accessUnit)

    #expect(
        try VideoToolboxAVCCOutputV0.copyAccessUnit(
            from: blockBuffer,
            cleanKeyframe: true
        ) == accessUnit
    )
    #expect(throws: AVCCPayloadErrorV0.keyframeFlagMismatch) {
        _ = try VideoToolboxAVCCOutputV0.copyAccessUnit(
            from: blockBuffer,
            cleanKeyframe: false
        )
    }
}
