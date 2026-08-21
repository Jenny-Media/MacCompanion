import CoreMedia
import Foundation

public enum VideoToolboxEncodedSampleErrorV0:
    Error,
    Equatable,
    Sendable
{
    case sampleNotReady
    case invalidSampleCount
    case invalidFormat
    case invalidDimensions
    case missingDataBuffer
    case invalidPresentationTime
}

public struct VideoToolboxEncodedSampleV0: Equatable, Sendable {
    public let decoderConfiguration: Data
    public let accessUnit: Data
    public let cleanKeyframe: Bool
    public let width: UInt16
    public let height: UInt16
    public let presentationTimeNanoseconds: UInt64

    init(
        decoderConfiguration: Data,
        accessUnit: Data,
        cleanKeyframe: Bool,
        width: UInt16,
        height: UInt16,
        presentationTimeNanoseconds: UInt64
    ) {
        self.decoderConfiguration = decoderConfiguration
        self.accessUnit = accessUnit
        self.cleanKeyframe = cleanKeyframe
        self.width = width
        self.height = height
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
    }

    public static func extract(
        from sampleBuffer: CMSampleBuffer
    ) throws -> Self {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            throw VideoToolboxEncodedSampleErrorV0.sampleNotReady
        }
        guard CMSampleBufferGetNumSamples(sampleBuffer) == 1 else {
            throw VideoToolboxEncodedSampleErrorV0.invalidSampleCount
        }
        guard let formatDescription =
                CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaSubType(formatDescription)
                == kCMVideoCodecType_H264 else {
            throw VideoToolboxEncodedSampleErrorV0.invalidFormat
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(
            formatDescription
        )
        guard dimensions.width > 0,
              dimensions.height > 0,
              dimensions.width
                <= ScreenCaptureKitCaptureProfileV0.maximumWidth,
              dimensions.height
                <= ScreenCaptureKitCaptureProfileV0.maximumHeight,
              Int(dimensions.width)
                <= ScreenCaptureKitCaptureProfileV0.maximumPixelCount
                    / Int(dimensions.height) else {
            throw VideoToolboxEncodedSampleErrorV0.invalidDimensions
        }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else {
            throw VideoToolboxEncodedSampleErrorV0.missingDataBuffer
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(
            sampleBuffer
        )
        guard presentationTime.isNumeric,
              presentationTime.timescale > 0,
              presentationTime.value >= 0 else {
            throw VideoToolboxEncodedSampleErrorV0
                .invalidPresentationTime
        }
        let nanoseconds = CMTimeConvertScale(
            presentationTime,
            timescale: 1_000_000_000,
            method: .roundTowardZero
        )
        guard nanoseconds.isNumeric, nanoseconds.value >= 0 else {
            throw VideoToolboxEncodedSampleErrorV0
                .invalidPresentationTime
        }

        let cleanKeyframe = isCleanKeyframe(sampleBuffer)
        return Self(
            decoderConfiguration:
                try VideoToolboxAVCCOutputV0.decoderConfiguration(
                    from: formatDescription
                ),
            accessUnit: try VideoToolboxAVCCOutputV0.copyAccessUnit(
                from: blockBuffer,
                cleanKeyframe: cleanKeyframe
            ),
            cleanKeyframe: cleanKeyframe,
            width: UInt16(dimensions.width),
            height: UInt16(dimensions.height),
            presentationTimeNanoseconds: UInt64(nanoseconds.value)
        )
    }

    private static func isCleanKeyframe(
        _ sampleBuffer: CMSampleBuffer
    ) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[AnyHashable: Any]],
              let first = attachments.first else {
            return true
        }
        return (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    }
}
