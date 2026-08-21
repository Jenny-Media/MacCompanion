@testable import CompanionHostPlatform
import Foundation
import Testing

private enum VideoToolboxH264TestError: Error, Equatable {
    case rejected
}

private final class VideoToolboxH264FakeDriverV0:
    VideoToolboxH264PropertyApplyingV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let rejectAtIndex: Int?
    private var storage: [VideoToolboxH264PropertyV0] = []

    init(rejectAtIndex: Int? = nil) {
        self.rejectAtIndex = rejectAtIndex
    }

    var properties: [VideoToolboxH264PropertyV0] {
        lock.withLock { storage }
    }

    func apply(_ property: VideoToolboxH264PropertyV0) throws {
        try lock.withLock {
            if storage.count == rejectAtIndex {
                throw VideoToolboxH264TestError.rejected
            }
            storage.append(property)
        }
    }
}

@Test func videoToolboxInitialProfileMatchesFrozenEncoderCeilings() {
    let profile = VideoToolboxH264EncoderProfileV0.initial

    #expect(profile.capture == .initial)
    #expect(profile.targetBitrateBitsPerSecond == 8_000_000)
    #expect(profile.keyframeIntervalMilliseconds == 2_000)
}

@Test func videoToolboxProfileRejectsUnsafeBitrateAndKeyframeInterval()
    throws
{
    let capture = try ScreenCaptureKitCaptureProfileV0(
        width: 1_280,
        height: 720,
        framesPerSecond: 24,
        queueDepth: 2
    )
    #expect(throws: VideoToolboxH264ConfigurationErrorV0.invalidBitrate) {
        _ = try VideoToolboxH264EncoderProfileV0(
            capture: capture,
            targetBitrateBitsPerSecond: 8_000_001,
            keyframeIntervalMilliseconds: 2_000
        )
    }
    #expect(
        throws:
            VideoToolboxH264ConfigurationErrorV0.invalidKeyframeInterval
    ) {
        _ = try VideoToolboxH264EncoderProfileV0(
            capture: capture,
            targetBitrateBitsPerSecond: 4_000_000,
            keyframeIntervalMilliseconds: 2_001
        )
    }
}

@Test func videoToolboxPolicyAppliesExactLowLatencyPropertiesInOrder()
    throws
{
    let capture = try ScreenCaptureKitCaptureProfileV0(
        width: 1_280,
        height: 720,
        framesPerSecond: 24,
        queueDepth: 2
    )
    let profile = try VideoToolboxH264EncoderProfileV0(
        capture: capture,
        targetBitrateBitsPerSecond: 4_000_000,
        keyframeIntervalMilliseconds: 1_500
    )
    let driver = VideoToolboxH264FakeDriverV0()

    try VideoToolboxH264ConfigurationV0.apply(
        profile: profile,
        using: driver
    )

    #expect(driver.properties == [
        .realTime(true),
        .highProfileLevel41,
        .allowFrameReordering(false),
        .averageBitrate(4_000_000),
        .expectedFrameRate(24),
        .maximumKeyframeInterval(36),
        .maximumKeyframeIntervalDurationMilliseconds(1_500),
    ])
}

@Test func videoToolboxPolicyStopsAtFirstRejectedProperty() {
    let driver = VideoToolboxH264FakeDriverV0(rejectAtIndex: 2)

    #expect(throws: VideoToolboxH264TestError.rejected) {
        try VideoToolboxH264ConfigurationV0.apply(
            profile: .initial,
            using: driver
        )
    }
    #expect(driver.properties == [
        .realTime(true),
        .highProfileLevel41,
    ])
}
