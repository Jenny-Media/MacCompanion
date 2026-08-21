import Foundation
import VideoToolbox

public enum VideoToolboxH264ConfigurationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidBitrate
    case invalidKeyframeInterval
    case propertyRejected
}

public struct VideoToolboxH264EncoderProfileV0: Equatable, Sendable {
    public static let maximumTargetBitrateBitsPerSecond = 8_000_000
    public static let maximumKeyframeIntervalMilliseconds = 2_000

    public static let initial = Self(
        capture: .initial,
        targetBitrateBitsPerSecond: maximumTargetBitrateBitsPerSecond,
        keyframeIntervalMilliseconds: maximumKeyframeIntervalMilliseconds,
        validated: ()
    )

    public let capture: ScreenCaptureKitCaptureProfileV0
    public let targetBitrateBitsPerSecond: Int
    public let keyframeIntervalMilliseconds: Int

    public init(
        capture: ScreenCaptureKitCaptureProfileV0,
        targetBitrateBitsPerSecond: Int,
        keyframeIntervalMilliseconds: Int
    ) throws {
        guard (1...Self.maximumTargetBitrateBitsPerSecond).contains(
            targetBitrateBitsPerSecond
        ) else {
            throw VideoToolboxH264ConfigurationErrorV0.invalidBitrate
        }
        guard (1...Self.maximumKeyframeIntervalMilliseconds).contains(
            keyframeIntervalMilliseconds
        ) else {
            throw VideoToolboxH264ConfigurationErrorV0
                .invalidKeyframeInterval
        }
        self.capture = capture
        self.targetBitrateBitsPerSecond = targetBitrateBitsPerSecond
        self.keyframeIntervalMilliseconds = keyframeIntervalMilliseconds
    }

    private init(
        capture: ScreenCaptureKitCaptureProfileV0,
        targetBitrateBitsPerSecond: Int,
        keyframeIntervalMilliseconds: Int,
        validated _: Void
    ) {
        self.capture = capture
        self.targetBitrateBitsPerSecond = targetBitrateBitsPerSecond
        self.keyframeIntervalMilliseconds = keyframeIntervalMilliseconds
    }
}

enum VideoToolboxH264PropertyV0: Equatable, Sendable {
    case realTime(Bool)
    case highProfileLevel41
    case allowFrameReordering(Bool)
    case averageBitrate(Int)
    case expectedFrameRate(Int)
    case maximumKeyframeInterval(Int)
    case maximumKeyframeIntervalDurationMilliseconds(Int)
}

protocol VideoToolboxH264PropertyApplyingV0: Sendable {
    func apply(_ property: VideoToolboxH264PropertyV0) throws
}

private final class VideoToolboxH264SessionPropertyDriverV0:
    VideoToolboxH264PropertyApplyingV0,
    @unchecked Sendable
{
    private let session: VTCompressionSession

    init(session: VTCompressionSession) {
        self.session = session
    }

    func apply(_ property: VideoToolboxH264PropertyV0) throws {
        let key: CFString
        let value: CFTypeRef
        switch property {
        case .realTime(let enabled):
            key = kVTCompressionPropertyKey_RealTime
            value = NSNumber(value: enabled)
        case .highProfileLevel41:
            key = kVTCompressionPropertyKey_ProfileLevel
            value = kVTProfileLevel_H264_High_4_1
        case .allowFrameReordering(let enabled):
            key = kVTCompressionPropertyKey_AllowFrameReordering
            value = NSNumber(value: enabled)
        case .averageBitrate(let bitsPerSecond):
            key = kVTCompressionPropertyKey_AverageBitRate
            value = NSNumber(value: bitsPerSecond)
        case .expectedFrameRate(let framesPerSecond):
            key = kVTCompressionPropertyKey_ExpectedFrameRate
            value = NSNumber(value: framesPerSecond)
        case .maximumKeyframeInterval(let frames):
            key = kVTCompressionPropertyKey_MaxKeyFrameInterval
            value = NSNumber(value: frames)
        case .maximumKeyframeIntervalDurationMilliseconds(
            let milliseconds
        ):
            key = kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration
            value = NSNumber(value: Double(milliseconds) / 1_000)
        }
        guard VTSessionSetProperty(session, key: key, value: value)
                == noErr else {
            throw VideoToolboxH264ConfigurationErrorV0.propertyRejected
        }
    }
}

/// Applies the closed low-latency H.264 policy to an already-created session.
/// Session creation and output callbacks remain owned by the later encoder
/// adapter; this boundary neither allocates hardware nor encodes a frame.
public enum VideoToolboxH264ConfigurationV0 {
    public static func apply(
        profile: VideoToolboxH264EncoderProfileV0,
        to session: VTCompressionSession
    ) throws {
        try apply(
            profile: profile,
            using: VideoToolboxH264SessionPropertyDriverV0(
                session: session
            )
        )
    }

    static func apply(
        profile: VideoToolboxH264EncoderProfileV0,
        using driver: any VideoToolboxH264PropertyApplyingV0
    ) throws {
        let maximumKeyframeFrames = (
            profile.capture.framesPerSecond
                * profile.keyframeIntervalMilliseconds + 999
        ) / 1_000
        let properties: [VideoToolboxH264PropertyV0] = [
            .realTime(true),
            .highProfileLevel41,
            .allowFrameReordering(false),
            .averageBitrate(profile.targetBitrateBitsPerSecond),
            .expectedFrameRate(profile.capture.framesPerSecond),
            .maximumKeyframeInterval(maximumKeyframeFrames),
            .maximumKeyframeIntervalDurationMilliseconds(
                profile.keyframeIntervalMilliseconds
            ),
        ]
        for property in properties {
            try driver.apply(property)
        }
    }
}
