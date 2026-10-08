import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import IOKit

// Disposable host diagnostic. Never inspect, retain or export image pixels.
final class Output: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: Int] = [:]
    private var errors: [Int] = []

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let status = (attachments?.first?[.status] as? NSNumber)?.intValue ?? -1
        lock.lock()
        states[String(status), default: 0] += 1
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        errors.append((error as NSError).code)
        lock.unlock()
    }

    func result() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return ["frameStatuses": states, "streamErrorCodes": errors]
    }
}

@main struct Probe {
    static func main() async {
        guard CommandLine.arguments.count == 3,
              let id = UInt32(CommandLine.arguments[1]),
              ["stream", "screenshot", "watch"].contains(CommandLine.arguments[2]) else {
            print("usage: MetadataCapture DISPLAY_ID stream|screenshot|watch")
            exit(2)
        }
        var result: [String: Any] = [
            "displayID": id,
            "online": CGDisplayIsOnline(id) != 0,
            "active": CGDisplayIsActive(id) != 0,
            "asleep": CGDisplayIsAsleep(id) != 0,
            "builtin": CGDisplayIsBuiltin(id) != 0,
            "captureAccess": CGPreflightScreenCaptureAccess()
        ]
        if let mode = CGDisplayCopyDisplayMode(id) {
            result["modeWidth"] = mode.width
            result["modeHeight"] = mode.height
            result["pixelWidth"] = mode.pixelWidth
            result["pixelHeight"] = mode.pixelHeight
            result["refreshRate"] = mode.refreshRate
        }
        guard result["captureAccess"] as? Bool == true else {
            emit(result)
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            result["enumeratedDisplayIDs"] = content.displays.map(\.displayID)
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                result["stage"] = "notEnumerated"
                emit(result)
                return
            }
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            result["displayWidth"] = display.width
            result["displayHeight"] = display.height
            if CommandLine.arguments[2] == "screenshot" {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                result["screenshotWidth"] = image.width
                result["screenshotHeight"] = image.height
            } else {
                let output = Output()
                let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "metadata-only-capture"))
                try await stream.startCapture()
                if CommandLine.arguments[2] == "watch" {
                    for second in 1...60 {
                        try await Task.sleep(for: .seconds(1))
                        var interval = output.result()
                        interval["elapsedSeconds"] = second
                        interval["displayID"] = id
                        interval["active"] = CGDisplayIsActive(id) != 0
                        interval["asleep"] = CGDisplayIsAsleep(id) != 0
                        interval["mainDisplayID"] = CGMainDisplayID()
                        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
                        if root != IO_OBJECT_NULL {
                            interval["lidClosed"] = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
                            IOObjectRelease(root)
                        }
                        emit(interval)
                        fflush(stdout)
                    }
                } else {
                    try await Task.sleep(for: .seconds(5))
                }
                try await stream.stopCapture()
                result.merge(output.result()) { _, new in new }
            }
            result["stage"] = "completed"
        } catch {
            let error = error as NSError
            result["errorDomain"] = error.domain
            result["errorCode"] = error.code
        }
        emit(result)
    }

    static func emit(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}
