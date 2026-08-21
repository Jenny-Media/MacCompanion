import CompanionHostPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreMedia
import Foundation
import Testing

private let encodedSampleTestSPS = Data([
    0x67, 0x42, 0xc0, 0x1f, 0xda, 0x01, 0x40, 0x16,
    0xec, 0x04, 0x40, 0x00, 0x00, 0x03, 0x00, 0x40,
    0x00, 0x00, 0x0c, 0x83, 0xc6, 0x0c, 0x65, 0x80,
])
private let encodedSampleTestPPS = Data([0x68, 0xce, 0x3c, 0x80])

private func encodedSampleTestFormatDescription() throws
    -> CMFormatDescription
{
    try encodedSampleTestSPS.withUnsafeBytes { spsBytes in
        try encodedSampleTestPPS.withUnsafeBytes { ppsBytes in
            let pointers = [
                spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
            ]
            let sizes = [encodedSampleTestSPS.count, encodedSampleTestPPS.count]
            var output: CMFormatDescription?
            let status = pointers.withUnsafeBufferPointer { pointerBuffer in
                sizes.withUnsafeBufferPointer { sizeBuffer in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: pointers.count,
                        parameterSetPointers: pointerBuffer.baseAddress!,
                        parameterSetSizes: sizeBuffer.baseAddress!,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &output
                    )
                }
            }
            guard status == noErr, let output else {
                throw VideoToolboxEncodedSampleErrorV0.invalidFormat
            }
            return output
        }
    }
}

private func encodedSampleTestBlockBuffer(_ data: Data) throws
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

private func encodedSampleTestBuffer(
    accessUnit: Data,
    presentationTime: CMTime,
    notSync: Bool
) throws -> CMSampleBuffer {
    let blockBuffer = try encodedSampleTestBlockBuffer(accessUnit)
    let description = try encodedSampleTestFormatDescription()
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    var size = accessUnit.count
    var output: CMSampleBuffer?
    guard CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: description,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &size,
        sampleBufferOut: &output
    ) == noErr,
          let output else {
        throw VideoToolboxEncodedSampleErrorV0.invalidFormat
    }
    if notSync,
       let attachments = CMSampleBufferGetSampleAttachmentsArray(
           output,
           createIfNecessary: true
       ) as? [NSMutableDictionary],
       let first = attachments.first {
        first[kCMSampleAttachmentKey_NotSync] = true
    }
    return output
}

@Test func encodedSampleNormalizesKeyframeAndNanosecondTimeline()
    throws
{
    let accessUnit = Data([0, 0, 0, 2, 0x65, 0])
    let sampleBuffer = try encodedSampleTestBuffer(
        accessUnit: accessUnit,
        presentationTime: CMTime(value: 3, timescale: 2),
        notSync: false
    )

    let output = try VideoToolboxEncodedSampleV0.extract(
        from: sampleBuffer
    )

    #expect(output.accessUnit == accessUnit)
    #expect(output.cleanKeyframe)
    #expect(output.presentationTimeNanoseconds == 1_500_000_000)
    #expect(output.width > 0)
    #expect(output.height > 0)
    try AVCCPayloadValidatorV0.validateDecoderConfiguration(
        output.decoderConfiguration
    )
}

@Test func encodedSampleUsesNotSyncAttachmentForDeltaTruth() throws {
    let accessUnit = Data([0, 0, 0, 2, 0x41, 0])
    let sampleBuffer = try encodedSampleTestBuffer(
        accessUnit: accessUnit,
        presentationTime: CMTime(value: 1, timescale: 30),
        notSync: true
    )

    let output = try VideoToolboxEncodedSampleV0.extract(
        from: sampleBuffer
    )

    #expect(!output.cleanKeyframe)
    #expect(output.accessUnit == accessUnit)
}

@Test func encodedSampleRejectsInvalidPresentationTimeBeforeOutput()
    throws
{
    let sampleBuffer = try encodedSampleTestBuffer(
        accessUnit: Data([0, 0, 0, 2, 0x65, 0]),
        presentationTime: .invalid,
        notSync: false
    )

    #expect(
        throws:
            VideoToolboxEncodedSampleErrorV0.invalidPresentationTime
    ) {
        _ = try VideoToolboxEncodedSampleV0.extract(
            from: sampleBuffer
        )
    }
}
