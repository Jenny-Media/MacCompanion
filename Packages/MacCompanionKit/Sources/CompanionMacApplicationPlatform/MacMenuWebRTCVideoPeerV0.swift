#if os(macOS) && MACCOMPANION_WEBRTC_DEVELOPMENT && canImport(WebRTC)
import CompanionHostPlatform
import CoreMedia
import Foundation
import ScreenCaptureKit
@preconcurrency import WebRTC

public enum MacMenuWebRTCVideoPeerErrorV0: Error, Sendable {
    case unavailable
    case missingH264
    case missingDescription
    case incompleteICE
    case closed
}

/// Feeds the menu-owned ScreenCaptureKit pixel buffers directly to WebRTC.
/// The stream owner still supplies its bounded newest-frame callback policy.
private actor MacMenuWebRTCFrameEncoderV0:
    ScreenCaptureKitVideoEncodingV0
{
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private var closed = false

    init(source: RTCVideoSource) {
        self.source = source
        capturer = RTCVideoCapturer(delegate: source)
    }

    func submit(
        _ frame: VideoToolboxH264InputFrameV0,
        forceCleanKeyframe _: Bool
    ) async throws -> VideoToolboxH264FrameSubmissionV0 {
        guard !closed, frame.presentationTime.isNumeric,
              frame.presentationTime.value >= 0 else {
            throw MacMenuWebRTCVideoPeerErrorV0.closed
        }
        let timestamp = CMTimeConvertScale(
            frame.presentationTime,
            timescale: 1_000_000_000,
            method: .roundHalfAwayFromZero
        )
        guard timestamp.isNumeric, timestamp.value >= 0 else {
            throw MacMenuWebRTCVideoPeerErrorV0.unavailable
        }
        source.capturer(capturer, didCapture: RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: frame.pixelBuffer),
            rotation: ._0,
            timeStampNs: timestamp.value
        ))
        return .started
    }

    func stop() async { closed = true }
}

/// Created only after the menu runtime validates a current Control lease and
/// selected surface. The caller must revalidate that lease after every await.
/// No SDP or ICE value is an authorization source.
public final class MacMenuWebRTCVideoPeerV0:
    NSObject, RTCPeerConnectionDelegate, @unchecked Sendable
{
    private let factory: RTCPeerConnectionFactory
    private let source: RTCVideoSource
    private let sendingTrack: RTCVideoTrack
    private let connection: RTCPeerConnection
    private let frameEncoder: MacMenuWebRTCFrameEncoderV0
    public let negotiationID: UUID
    private let lock = NSLock()
    private var closed = false
    private var capture: ScreenCaptureKitStreamOwnerV0?

    public init(negotiationID: UUID) throws {
        RTCInitializeSSL()
        self.negotiationID = negotiationID
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        source = factory.videoSource(forScreenCast: true)
        sendingTrack = factory.videoTrack(
            with: source, trackId: "interactive-video"
        )
        frameEncoder = MacMenuWebRTCFrameEncoderV0(source: source)
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = []
        configuration.bundlePolicy = .maxBundle
        configuration.tcpCandidatePolicy = .disabled
        guard let connection = factory.peerConnection(
            with: configuration,
            constraints: RTCMediaConstraints(
                mandatoryConstraints: nil, optionalConstraints: nil
            ),
            delegate: nil
        ) else {
            throw MacMenuWebRTCVideoPeerErrorV0.unavailable
        }
        self.connection = connection
        super.init()
        connection.delegate = self
        let initOptions = RTCRtpTransceiverInit()
        initOptions.direction = .sendOnly
        initOptions.streamIds = ["interactive"]
        guard let transceiver = connection.addTransceiver(
            with: sendingTrack, init: initOptions
        ) else {
            connection.close()
            throw MacMenuWebRTCVideoPeerErrorV0.unavailable
        }
        let h264 = factory.rtpSenderCapabilities(forKind: "video")
            .codecs.filter { $0.name == "H264" }
        guard !h264.isEmpty else {
            connection.close()
            throw MacMenuWebRTCVideoPeerErrorV0.missingH264
        }
        transceiver.setCodecPreferences(Optional(h264))
        let parameters = transceiver.sender.parameters
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = 4_000_000
            encoding.maxFramerate = 30
        }
        transceiver.sender.parameters = parameters
    }

    public func makeOffer() async throws -> String {
        guard isOpen else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
        let offer = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<RTCSessionDescription,
                any Error>) in
            connection.offer(for: RTCMediaConstraints(
                mandatoryConstraints: nil, optionalConstraints: nil
            )) { offer, error in
                if let error { continuation.resume(throwing: error) }
                else if let offer { continuation.resume(returning: offer) }
                else {
                    continuation.resume(throwing:
                        MacMenuWebRTCVideoPeerErrorV0.missingDescription)
                }
            }
        }
        guard isOpen else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.setLocalDescription(offer) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        // The authenticated local request has a four-second deadline.
        for _ in 0..<150 {
            guard isOpen else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
            if connection.iceGatheringState == .complete,
               let sdp = connection.localDescription?.sdp,
               sdp.contains("a=candidate:") {
                return sdp
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MacMenuWebRTCVideoPeerErrorV0.incompleteICE
    }

    public func acceptAnswer(_ sdp: String) async throws {
        guard isOpen else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: sdp)
            ) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        guard isOpen else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
    }

    public func startCapture(
        filter: sending SCContentFilter,
        profile: ScreenCaptureKitCaptureProfileV0,
        sourceRect: CGRect? = nil
    ) async throws {
        let session = ScreenCaptureKitStreamingSessionAdapterV0(
            filter: filter, profile: profile, sourceRect: sourceRect
        )
        let owner = ScreenCaptureKitStreamOwnerV0(
            session: session,
            encoder: frameEncoder,
            terminal: { [weak self] reason in
                guard reason != .localStop else { return }
                Task { await self?.close() }
            }
        )
        let admitted = lock.withLock { () -> Bool in
            guard !closed, capture == nil else { return false }
            capture = owner
            return true
        }
        guard admitted else { throw MacMenuWebRTCVideoPeerErrorV0.closed }
        do {
            try await owner.start()
            guard isOpen else {
                await close()
                throw MacMenuWebRTCVideoPeerErrorV0.closed
            }
        } catch {
            lock.withLock {
                if capture === owner { capture = nil }
            }
            await close()
            throw error
        }
    }

    public func close() async {
        let (shouldClose, owner) = lock.withLock {
            () -> (Bool, ScreenCaptureKitStreamOwnerV0?) in
            guard !closed else { return (false, nil) }
            closed = true
            defer { capture = nil }
            return (true, capture)
        }
        guard shouldClose else { return }
        try? await owner?.stop()
        await frameEncoder.stop()
        sendingTrack.isEnabled = false
        connection.close()
    }

    private var isOpen: Bool { lock.withLock { !closed } }

    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange newState: RTCIceConnectionState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didGenerate candidate: RTCIceCandidate) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didOpen dataChannel: RTCDataChannel) {
        dataChannel.close()
    }
}
#endif
