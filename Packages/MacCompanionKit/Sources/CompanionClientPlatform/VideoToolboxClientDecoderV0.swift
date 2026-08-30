import CompanionInteractiveClient
import CompanionInteractiveShared
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum VideoToolboxClientDecoderErrorV0:
    Error,
    Equatable,
    Sendable
{
    case formatDescriptionCreationFailed
    case sessionCreationFailed
    case generationMismatch
    case sampleBufferCreationFailed
    case decodeSubmissionFailed
}

public final class VideoToolboxClientDecodedFrameV0: @unchecked Sendable {
    public let receipt: ClientDecodedFrameReceiptV0
    public let pixelBuffer: CVPixelBuffer

    init(
        receipt: ClientDecodedFrameReceiptV0,
        pixelBuffer: CVPixelBuffer
    ) {
        self.receipt = receipt
        self.pixelBuffer = pixelBuffer
    }
}

public enum VideoToolboxClientDecodeResultV0: @unchecked Sendable {
    case frame(VideoToolboxClientDecodedFrameV0)
    case failure(generation: UInt64, mediaSequence: UInt64)
}

private final class VideoToolboxClientDecodeCallbackBoxV0:
    @unchecked Sendable
{
    let command: ClientDecodeAccessUnitCommandV0
    let frameReference: UUID
    let handler: @Sendable (VideoToolboxClientDecodeResultV0) -> Void

    init(
        command: ClientDecodeAccessUnitCommandV0,
        frameReference: UUID,
        handler: @escaping @Sendable (
            VideoToolboxClientDecodeResultV0
        ) -> Void
    ) {
        self.command = command
        self.frameReference = frameReference
        self.handler = handler
    }
}

private func videoToolboxClientDecodeCallbackV0(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard let sourceFrameRefCon else { return }
    let box = Unmanaged<VideoToolboxClientDecodeCallbackBoxV0>
        .fromOpaque(sourceFrameRefCon).takeRetainedValue()
    guard status == noErr,
          !infoFlags.contains(.frameDropped),
          let pixelBuffer = imageBuffer,
          CVPixelBufferGetWidth(pixelBuffer)
            == Int(box.command.fence.encodedWidth),
          CVPixelBufferGetHeight(pixelBuffer)
            == Int(box.command.fence.encodedHeight),
          CVPixelBufferGetPixelFormatType(pixelBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
          CMTimeCompare(
              presentationTimeStamp,
              CMTime(
                  value: Int64(
                      box.command.presentationTimeNanoseconds
                  ),
                  timescale: 1_000_000_000
              )
          ) == 0 else {
        box.handler(.failure(
            generation: box.command.generation,
            mediaSequence: box.command.mediaSequence
        ))
        return
    }
    let receipt = ClientDecodedFrameReceiptV0(
        generation: box.command.generation,
        fence: box.command.fence,
        mediaSequence: box.command.mediaSequence,
        presentationTimeNanoseconds:
            box.command.presentationTimeNanoseconds,
        frameReference: box.frameReference
    )
    box.handler(.frame(VideoToolboxClientDecodedFrameV0(
        receipt: receipt,
        pixelBuffer: pixelBuffer
    )))
}

/// Concrete decoder behind the pure generation/render authority. It does not
/// render, retain more than VideoToolbox owns, or decide callback freshness.
public final class VideoToolboxClientDecoderV0: @unchecked Sendable {
    private let lock = NSLock()
    private let handler:
        @Sendable (VideoToolboxClientDecodeResultV0) -> Void
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var generation: UInt64?

    public init(
        handler: @escaping @Sendable (
            VideoToolboxClientDecodeResultV0
        ) -> Void
    ) {
        self.handler = handler
    }

    deinit { invalidate() }

    public func configure(
        _ command: ClientDecoderConfigurationCommandV0
    ) throws {
        let parameterSets = try AVCCPayloadValidatorV0.decoderParameterSets(
            command.configuration
        )
        let values = parameterSets.sequence + parameterSets.picture
        let stable = values.map { $0 as NSData }
        let pointers = stable.map {
            $0.bytes.assumingMemoryBound(to: UInt8.self)
        }
        let sizes = stable.map(\.length)
        var createdFormat: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: pointers.count,
            parameterSetPointers: pointers,
            parameterSetSizes: sizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &createdFormat
        ) == noErr,
              let createdFormat else {
            throw VideoToolboxClientDecoderErrorV0
                .formatDescriptionCreationFailed
        }
        let destinationAttributes = [
            // Display layers require IOSurface-backed buffers. Software
            // decoding in Simulator must request these explicitly, too.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String:
                Int(command.fence.encodedWidth),
            kCVPixelBufferHeightKey as String:
                Int(command.fence.encodedHeight),
        ] as CFDictionary
        let decoderSpecification = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder
                as String: true,
        ] as CFDictionary
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback:
                videoToolboxClientDecodeCallbackV0,
            decompressionOutputRefCon: nil
        )
        var createdSession: VTDecompressionSession?
        guard VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: createdFormat,
            decoderSpecification: decoderSpecification,
            imageBufferAttributes: destinationAttributes,
            outputCallback: &callback,
            decompressionSessionOut: &createdSession
        ) == noErr,
              let createdSession else {
            throw VideoToolboxClientDecoderErrorV0.sessionCreationFailed
        }
        let old = lock.withLock { () -> VTDecompressionSession? in
            let old = session
            session = createdSession
            formatDescription = createdFormat
            generation = command.generation
            return old
        }
        if let old {
            _ = VTDecompressionSessionWaitForAsynchronousFrames(old)
            VTDecompressionSessionInvalidate(old)
        }
    }

    public func decode(
        _ command: ClientDecodeAccessUnitCommandV0
    ) throws {
        let active = try lock.withLock {
            guard generation == command.generation,
                  let session,
                  let formatDescription else {
                throw VideoToolboxClientDecoderErrorV0.generationMismatch
            }
            return (session, formatDescription)
        }
        let sample = try Self.makeSampleBuffer(
            command: command,
            formatDescription: active.1
        )
        let box = VideoToolboxClientDecodeCallbackBoxV0(
            command: command,
            frameReference: UUID(),
            handler: handler
        )
        let retained = Unmanaged.passRetained(box)
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            active.0,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: retained.toOpaque(),
            infoFlagsOut: &infoFlags
        )
        guard status == noErr else {
            retained.release()
            throw VideoToolboxClientDecoderErrorV0.decodeSubmissionFailed
        }
    }

    public func invalidate() {
        let old = lock.withLock { () -> VTDecompressionSession? in
            let old = session
            session = nil
            formatDescription = nil
            generation = nil
            return old
        }
        guard let old else { return }
        _ = VTDecompressionSessionWaitForAsynchronousFrames(old)
        VTDecompressionSessionInvalidate(old)
    }

    private static func makeSampleBuffer(
        command: ClientDecodeAccessUnitCommandV0,
        formatDescription: CMVideoFormatDescription
    ) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: command.accessUnit.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: command.accessUnit.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr,
              let blockBuffer else {
            throw VideoToolboxClientDecoderErrorV0
                .sampleBufferCreationFailed
        }
        let copied = command.accessUnit.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: bytes.count
            )
        }
        guard copied == noErr else {
            throw VideoToolboxClientDecoderErrorV0
                .sampleBufferCreationFailed
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: Int64(command.presentationTimeNanoseconds),
                timescale: 1_000_000_000
            ),
            decodeTimeStamp: .invalid
        )
        var size = command.accessUnit.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        ) == noErr,
              let sample else {
            throw VideoToolboxClientDecoderErrorV0
                .sampleBufferCreationFailed
        }
        return sample
    }
}
