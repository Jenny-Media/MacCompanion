import CoreVideo
import Foundation
import WebRTC

@main
enum PackageProbeMain {
    static func main() {
        do {
            try run()
        } catch {
            let message = "WebRTC package probe failed: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        guard RTCInitializeSSL() else {
            throw NSError(domain: "WebRTCProbe", code: 1)
        }
        let probe = PackageProbe()
        defer { probe.stop() }
        let inventory = PackageProbe.codecInventory()
        guard inventory["encoders"]?.contains("H264") == true,
              inventory["decoders"]?.contains("H264") == true else {
            throw NSError(domain: "WebRTCProbeMissingH264", code: 2)
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw NSError(domain: "WebRTCProbe", code: Int(status))
        }
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw NSError(domain: "WebRTCProbeBufferLock", code: Int(lockStatus))
        }
        guard let bytes = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw NSError(domain: "WebRTCProbeBufferAddress", code: 3)
        }
        memset(bytes, 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        probe.admitSyntheticFrame(buffer, timestampNs: 1_000_000_000)
        guard let receivedSize = probe.waitForLocalFrame(timeout: 5),
              receivedSize == CGSize(width: 1280, height: 720) else {
            throw NSError(domain: "WebRTCProbeLocalFrame", code: 4)
        }
        let result: [String: Any] = [
            "codecInventory": inventory,
            "factoryCreated": true,
            "syntheticPixelBufferAdmitted": true,
            "localRendererCallbackVerified": true,
            "receivedWidth": Int(receivedSize.width),
            "receivedHeight": Int(receivedSize.height),
            "encodingDecodingOrNetworkTested": false,
            "physicalCaptureOrStreamingTested": false,
            "hardwareCodecUseVerified": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        withExtendedLifetime(probe) {}
    }
}
