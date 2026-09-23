import CoreGraphics
import CoreVideo
import Foundation
import WebRTC

/// Disposable API/linkage probe. It owns no production credentials or capture permissions.
public final class PackageProbe: NSObject, RTCVideoRenderer {
    private let factory: RTCPeerConnectionFactory
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private let track: RTCVideoTrack
    private let frameCondition = NSCondition()
    private var receivedFrameSize: CGSize?

    public override init() {
        let factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        self.factory = factory
        source = factory.videoSource(forScreenCast: true)
        capturer = RTCVideoCapturer(delegate: source)
        track = factory.videoTrack(with: source, trackId: "disposable-package-probe")
        super.init()
        track.add(self)
    }

    public func admitSyntheticFrame(_ pixelBuffer: CVPixelBuffer, timestampNs: Int64) {
        let frame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer),
            rotation: ._0,
            timeStampNs: timestampNs
        )
        source.capturer(capturer, didCapture: frame)
    }

    public func setSize(_ size: CGSize) {}

    public func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        frameCondition.lock()
        receivedFrameSize = CGSize(width: Int(frame.width), height: Int(frame.height))
        frameCondition.signal()
        frameCondition.unlock()
    }

    public func waitForLocalFrame(timeout: TimeInterval) -> CGSize? {
        let deadline = Date().addingTimeInterval(timeout)
        frameCondition.lock()
        defer { frameCondition.unlock() }
        while receivedFrameSize == nil {
            if !frameCondition.wait(until: deadline) { break }
        }
        return receivedFrameSize
    }

    public func stop() {
        track.remove(self)
        track.isEnabled = false
    }

    public static func codecInventory() -> [String: [String]] {
        [
            "encoders": RTCDefaultVideoEncoderFactory().supportedCodecs().map(\.name),
            "decoders": RTCDefaultVideoDecoderFactory().supportedCodecs().map(\.name),
        ]
    }
}
