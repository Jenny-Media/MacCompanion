import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureKitCaptureConfigurationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidDimensions
    case invalidFrameRate
    case invalidQueueDepth
}

/// The bounded capture-side facts frozen by the Interactive Control MVP.
/// Construction is permission-free and does not enumerate or start capture.
public struct ScreenCaptureKitCaptureProfileV0: Equatable, Sendable {
    public static let maximumWidth = 1_920
    public static let maximumHeight = 1_200
    public static let maximumPixelCount = 2_304_000
    public static let maximumFramesPerSecond = 30
    public static let maximumQueueDepth = 3

    public static let initial = Self(
        width: maximumWidth,
        height: maximumHeight,
        framesPerSecond: maximumFramesPerSecond,
        queueDepth: maximumQueueDepth,
        validated: ()
    )

    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let queueDepth: Int

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        queueDepth: Int
    ) throws {
        guard (1...Self.maximumWidth).contains(width),
              (1...Self.maximumHeight).contains(height),
              width <= Self.maximumPixelCount / height else {
            throw ScreenCaptureKitCaptureConfigurationErrorV0
                .invalidDimensions
        }
        guard (1...Self.maximumFramesPerSecond).contains(
            framesPerSecond
        ) else {
            throw ScreenCaptureKitCaptureConfigurationErrorV0
                .invalidFrameRate
        }
        guard (1...Self.maximumQueueDepth).contains(queueDepth) else {
            throw ScreenCaptureKitCaptureConfigurationErrorV0
                .invalidQueueDepth
        }
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.queueDepth = queueDepth
    }

    private init(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        queueDepth: Int,
        validated _: Void
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.queueDepth = queueDepth
    }
}

/// Narrow ScreenCaptureKit construction boundary. These helpers allocate
/// configuration/filter values only: they never enumerate content, request
/// TCC access, construct `SCStream`, or start capture.
@available(macOS 13.0, *)
public enum ScreenCaptureKitCaptureConfigurationV0 {
    public static func makeStreamConfiguration(
        profile: ScreenCaptureKitCaptureProfileV0
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = profile.width
        configuration.height = profile.height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(profile.framesPerSecond)
        )
        configuration.queueDepth = profile.queueDepth
        configuration.pixelFormat =
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = true
        configuration.capturesAudio = false
        return configuration
    }

    public static func makeDesktopFilter(
        display: SCDisplay
    ) -> SCContentFilter {
        SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
    }

    public static func makeApplicationFilter(
        display: SCDisplay,
        application: SCRunningApplication
    ) -> SCContentFilter {
        SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
    }

    public static func makeWindowFilter(
        window: SCWindow
    ) -> SCContentFilter {
        SCContentFilter(desktopIndependentWindow: window)
    }
}
