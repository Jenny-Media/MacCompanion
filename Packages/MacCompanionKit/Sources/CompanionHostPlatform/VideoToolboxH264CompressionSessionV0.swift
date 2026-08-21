import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum VideoToolboxH264CompressionSessionErrorV0:
    Error,
    Equatable,
    Sendable
{
    case sessionCreationFailed
    case sessionInvalidated
    case encodeSubmissionFailed
}

private final class VideoToolboxH264CallbackContextV0:
    @unchecked Sendable
{
    typealias Completion = @Sendable (
        VideoToolboxH264SessionCompletionV0
    ) -> Void

    private let lock = NSLock()
    private var nextToken: UInt = 1
    private var completions: [UInt: Completion] = [:]

    func insert(_ completion: @escaping Completion) -> UInt {
        lock.withLock {
            var token = nextToken
            while completions[token] != nil {
                token = token == UInt.max ? 1 : token + 1
            }
            nextToken = token == UInt.max ? 1 : token + 1
            completions[token] = completion
            return token
        }
    }

    func take(_ token: UInt) -> Completion? {
        lock.withLock { completions.removeValue(forKey: token) }
    }

    func failAll() {
        let pending = lock.withLock {
            let result = Array(completions.values)
            completions.removeAll()
            return result
        }
        for completion in pending { completion(.failure) }
    }
}

private func videoToolboxH264CompressionOutputCallbackV0(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let outputCallbackRefCon,
          let sourceFrameRefCon else { return }
    let context = Unmanaged<VideoToolboxH264CallbackContextV0>
        .fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    let token = UInt(bitPattern: sourceFrameRefCon)
    guard let completion = context.take(token) else { return }
    guard status == noErr,
          !infoFlags.contains(.frameDropped),
          let sampleBuffer,
          let sample = try? VideoToolboxEncodedSampleV0.extract(
              from: sampleBuffer
          ) else {
        completion(.failure)
        return
    }
    completion(.success(sample))
}

/// Concrete VideoToolbox session behind the injected encoder-owner seam.
/// Construction requests, but does not require, hardware acceleration. The
/// owner still supplies all scheduling/backpressure and terminal authority.
public final class VideoToolboxH264CompressionSessionV0:
    VideoToolboxH264EncodingSessionV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let callbackContext = VideoToolboxH264CallbackContextV0()
    private var session: VTCompressionSession?

    public init(profile: VideoToolboxH264EncoderProfileV0) throws {
        let encoderSpecification = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
                as String: true,
        ] as CFDictionary
        let sourceAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: profile.capture.width,
            kCVPixelBufferHeightKey as String: profile.capture.height,
        ] as CFDictionary
        var created: VTCompressionSession?
        let callbackPointer = Unmanaged.passUnretained(
            callbackContext
        ).toOpaque()
        guard VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(profile.capture.width),
            height: Int32(profile.capture.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: sourceAttributes,
            compressedDataAllocator: nil,
            outputCallback:
                videoToolboxH264CompressionOutputCallbackV0,
            refcon: callbackPointer,
            compressionSessionOut: &created
        ) == noErr,
              let created else {
            throw VideoToolboxH264CompressionSessionErrorV0
                .sessionCreationFailed
        }
        do {
            try VideoToolboxH264ConfigurationV0.apply(
                profile: profile,
                to: created
            )
        } catch {
            VTCompressionSessionInvalidate(created)
            throw error
        }
        session = created
    }

    deinit {
        invalidate()
    }

    public func encode(
        frame: VideoToolboxH264InputFrameV0,
        forceCleanKeyframe: Bool,
        completion: @escaping @Sendable (
            VideoToolboxH264SessionCompletionV0
        ) -> Void
    ) throws {
        let active = lock.withLock { session }
        guard let active else {
            throw VideoToolboxH264CompressionSessionErrorV0
                .sessionInvalidated
        }
        let token = callbackContext.insert(completion)
        let frameProperties: CFDictionary? = forceCleanKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
                as CFDictionary
            : nil
        let status = VTCompressionSessionEncodeFrame(
            active,
            imageBuffer: frame.pixelBuffer,
            presentationTimeStamp: frame.presentationTime,
            duration: frame.duration,
            frameProperties: frameProperties,
            sourceFrameRefcon: UnsafeMutableRawPointer(bitPattern: token),
            infoFlagsOut: nil
        )
        guard status == noErr else {
            _ = callbackContext.take(token)
            throw VideoToolboxH264CompressionSessionErrorV0
                .encodeSubmissionFailed
        }
    }

    public func invalidate() {
        let active = lock.withLock {
            let result = session
            session = nil
            return result
        }
        guard let active else { return }
        _ = VTCompressionSessionCompleteFrames(
            active,
            untilPresentationTimeStamp: .invalid
        )
        VTCompressionSessionInvalidate(active)
        callbackContext.failAll()
    }
}
