import ApplicationServices
import PlatformAuthorityProbeCore
import CoreMedia
import CoreGraphics
import CoreVideo
import Darwin
import Foundation
import ScreenCaptureKit
import ServiceManagement
import VideoToolbox

private struct PreflightReport: Codable {
    let experimentOnly: Bool
    let operatingSystemVersion: String
    let screenCaptureAccessAlreadyGranted: Bool
    let accessibilityAccessAlreadyGranted: Bool
    let containingMainAppServiceStatus: String
}

@main
private enum PlatformAuthorityProbe {
    static func main() async throws {
        let command: PlatformAuthorityProbeCommand
        do {
            command = try PlatformAuthorityProbeCommand.parse(
                Array(CommandLine.arguments.dropFirst())
            )
        } catch {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(64)
        }

        switch command {
        case .enumerateShareableContent:
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let result = [
                "experimentOnly": true,
                "displays": content.displays.count,
                "applications": content.applications.count,
                "windows": content.windows.count,
            ] as [String: Any]
            try printJSON(result)
        case .captureEncodeSmoke:
            let report = await CaptureEncodeSmokeCoordinator(
                permission: SystemCaptureEncodeSmokePermissionChecker(),
                graphs: ProductionCaptureEncodeSmokeGraphBuilder()
            ).run()
            try printEncodable(report)
            if report.result != .succeeded {
                fflush(stdout)
                exit(2)
            }
        case .preflight:
            // These APIs only inspect current state. This path never calls
            // CGRequestScreenCaptureAccess, AXIsProcessTrustedWithOptions, or
            // posts a Core Graphics event.
            let report = PreflightReport(
                experimentOnly: true,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                screenCaptureAccessAlreadyGranted: CGPreflightScreenCaptureAccess(),
                accessibilityAccessAlreadyGranted: AXIsProcessTrusted(),
                containingMainAppServiceStatus: serviceStatusName(SMAppService.mainApp.status)
            )
            try printEncodable(report)
        }
    }

    /// Compile-time proof that the input construction API is available. The
    /// probe intentionally does not expose a command that posts this event.
    static func makeUnpostedPointerEvent() -> CGEvent? {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        )
    }

    /// Compile-time construction only. No CLI argument calls these helpers,
    /// so validation cannot enumerate content, start a stream, or allocate an
    /// encoder session.
    static func makeUnstartedDisplayCaptureGraph(
        display: SCDisplay
    ) -> (SCContentFilter, SCStreamConfiguration) {
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 1_920
        configuration.height = 1_200
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat =
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = true
        return (filter, configuration)
    }

    static func makeUnstartedH264Encoder() -> VTCompressionSession? {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1_920,
            height: 1_200,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr else { return nil }
        return session
    }

    private static func serviceStatusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }

    private static func printJSON(_ value: Any) throws {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printEncodable(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
        ]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    private static let usage = """
    Usage: platform-authority-probe [--preflight | --enumerate-shareable-content | --capture-encode-smoke]

      --preflight (default)            Read current permission/service status without prompting.
      --enumerate-shareable-content    Explicitly exercise ScreenCaptureKit enumeration; may be TCC-sensitive.
      --capture-encode-smoke           Explicitly capture and validate one clean H.264 keyframe; requires pre-granted Screen Recording.

    This disposable experiment never posts input and is not a release target.
    """
}
