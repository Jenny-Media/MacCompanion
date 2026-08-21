import CompanionHostPlatform
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing

@Test func screenCaptureInitialProfileMatchesFrozenMVPBounds() {
    let profile = ScreenCaptureKitCaptureProfileV0.initial

    #expect(profile.width == 1_920)
    #expect(profile.height == 1_200)
    #expect(profile.framesPerSecond == 30)
    #expect(profile.queueDepth == 3)
}

@available(macOS 13.0, *)
@Test func screenCaptureConfigurationIsVideoRangeSilentAndBounded()
    throws
{
    let profile = try ScreenCaptureKitCaptureProfileV0(
        width: 1_280,
        height: 720,
        framesPerSecond: 24,
        queueDepth: 2
    )

    let configuration =
        ScreenCaptureKitCaptureConfigurationV0.makeStreamConfiguration(
            profile: profile
        )

    #expect(configuration.width == 1_280)
    #expect(configuration.height == 720)
    #expect(
        configuration.minimumFrameInterval
            == CMTime(value: 1, timescale: 24)
    )
    #expect(configuration.queueDepth == 2)
    #expect(
        configuration.pixelFormat
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    )
    #expect(configuration.showsCursor)
    #expect(!configuration.capturesAudio)
}

@Test func screenCaptureProfileRejectsOversizedAndEmptyDimensions() {
    #expect(
        throws:
            ScreenCaptureKitCaptureConfigurationErrorV0.invalidDimensions
    ) {
        _ = try ScreenCaptureKitCaptureProfileV0(
            width: 1_921,
            height: 1_200,
            framesPerSecond: 30,
            queueDepth: 3
        )
    }
    #expect(
        throws:
            ScreenCaptureKitCaptureConfigurationErrorV0.invalidDimensions
    ) {
        _ = try ScreenCaptureKitCaptureProfileV0(
            width: 0,
            height: 720,
            framesPerSecond: 30,
            queueDepth: 3
        )
    }
}

@Test func screenCaptureProfileRejectsUnsafeRateAndQueueDepth() {
    #expect(
        throws:
            ScreenCaptureKitCaptureConfigurationErrorV0.invalidFrameRate
    ) {
        _ = try ScreenCaptureKitCaptureProfileV0(
            width: 1_280,
            height: 720,
            framesPerSecond: 31,
            queueDepth: 3
        )
    }
    #expect(
        throws:
            ScreenCaptureKitCaptureConfigurationErrorV0.invalidQueueDepth
    ) {
        _ = try ScreenCaptureKitCaptureProfileV0(
            width: 1_280,
            height: 720,
            framesPerSecond: 30,
            queueDepth: 4
        )
    }
}
