#if os(iOS) && MACCOMPANION_WEBRTC_DEVELOPMENT && canImport(WebRTC)
import CompanionInteractiveClient
import CompanionInteractiveWire
import Foundation
import UIKit
@preconcurrency import WebRTC

public enum UIKitClientWebRTCVideoPeerErrorV0: Error, Sendable {
    case unavailable
    case missingDescription
    case incompleteICE
    case invalidFingerprint
}

/// Keeps WebRTC callbacks out of UIKit state and rejects them after retirement.
private final class UIKitWebRTCFrameSinkV0:
    NSObject, RTCVideoRenderer, @unchecked Sendable
{
    private let lock = NSLock()
    private let display: RTCMTLVideoView
    private let firstFrame: @Sendable () -> Void
    private var active = true
    private var hasFrame = false
    private var scheduled = false
    private var latest: RTCVideoFrame?

    init(display: RTCMTLVideoView,
         firstFrame: @escaping @Sendable () -> Void) {
        self.display = display
        self.firstFrame = firstFrame
    }

    func setSize(_ size: CGSize) {
        // The next admitted frame carries the dimensions to the main actor.
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        let enqueue = lock.withLock { () -> Bool in
            guard active, let frame else { return false }
            latest = frame
            if scheduled { return false }
            scheduled = true
            return true
        }
        if enqueue {
            Task { @MainActor [weak self] in self?.flush() }
        }
    }

    func retire() {
        let retired = lock.withLock { () -> Bool in
            guard active else { return false }
            active = false
            latest = nil
            return true
        }
        if retired {
            Task { @MainActor [weak self] in
                self?.display.renderFrame(nil)
            }
        }
    }

    @MainActor
    private func flush() {
        let next = lock.withLock { () -> (RTCVideoFrame, Bool)? in
            defer { latest = nil; scheduled = false }
            guard active, let latest else { return nil }
            let first = !hasFrame
            hasFrame = true
            return (latest, first)
        }
        guard let (frame, first) = next else { return }
        display.setSize(CGSize(width: Int(frame.width),
                               height: Int(frame.height)))
        display.renderFrame(frame)
        if first { firstFrame() }
    }
}

private final class UIKitWebRTCPeerDelegateV0:
    NSObject, RTCPeerConnectionDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private let sink: UIKitWebRTCFrameSinkV0
    private var track: RTCVideoTrack?
    private var active = true

    init(sink: UIKitWebRTCFrameSinkV0) { self.sink = sink }

    private func receive(_ next: RTCVideoTrack?) {
        lock.withLock {
            guard active, let next, track !== next else { return }
            track?.remove(sink)
            track = next
            next.add(sink)
        }
    }

    func retire() {
        lock.withLock {
            active = false
            track?.remove(sink)
            track = nil
            sink.retire()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd stream: RTCMediaStream) {
        receive(stream.videoTracks.first)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didOpen dataChannel: RTCDataChannel) {
        dataChannel.close()
    }
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didStartReceivingOn transceiver: RTCRtpTransceiver) {
        receive(transceiver.receiver.track as? RTCVideoTrack)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd rtpReceiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        receive(rtpReceiver.track as? RTCVideoTrack)
    }
}

/// A development-only concrete peer for the normal Remote Control surface.
/// It uses only candidates gathered locally and never starts signaling itself.
@MainActor
public final class UIKitClientWebRTCVideoPeerV0: ClientWebRTCVideoPeerV0 {
    private let display = RTCMTLVideoView(frame: .zero)
    private let surface: UIKitClientLiveSurfaceViewV0
    private let sink: UIKitWebRTCFrameSinkV0
    private let delegate: UIKitWebRTCPeerDelegateV0
    private let factory: RTCPeerConnectionFactory
    private let connection: RTCPeerConnection
    private var closed = false

    public init(surface: UIKitClientLiveSurfaceViewV0) throws {
        RTCInitializeSSL()
        self.surface = surface
        let display = self.display
        display.videoContentMode = .scaleAspectFit
        sink = UIKitWebRTCFrameSinkV0(display: display) { [weak display] in
            Task { @MainActor in display?.isHidden = false }
        }
        delegate = UIKitWebRTCPeerDelegateV0(sink: sink)
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
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
            delegate: delegate
        ) else {
            throw UIKitClientWebRTCVideoPeerErrorV0.unavailable
        }
        self.connection = connection
        surface.installWebRTCVideoView(display)
    }

    public func answer(to offer: InteractiveWebRTCOfferBodyV0)
        async throws -> ClientWebRTCAnswerV0
    {
        guard !closed else {
            throw UIKitClientWebRTCVideoPeerErrorV0.unavailable
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.setRemoteDescription(
                RTCSessionDescription(type: .offer, sdp: offer.sdp)
            ) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        guard !closed else {
            throw UIKitClientWebRTCVideoPeerErrorV0.unavailable
        }
        let answer = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<RTCSessionDescription,
                any Error>) in
            connection.answer(for: RTCMediaConstraints(
                mandatoryConstraints: nil, optionalConstraints: nil
            )) { answer, error in
                if let error { continuation.resume(throwing: error) }
                else if let answer { continuation.resume(returning: answer) }
                else {
                    continuation.resume(throwing:
                        UIKitClientWebRTCVideoPeerErrorV0.missingDescription)
                }
            }
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.setLocalDescription(answer) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        for _ in 0..<500 {
            guard !closed else {
                throw UIKitClientWebRTCVideoPeerErrorV0.unavailable
            }
            if connection.iceGatheringState == .complete,
               let sdp = connection.localDescription?.sdp,
               sdp.contains("a=candidate:") {
                let fingerprint = try Self.fingerprintHex(from: sdp)
                _ = try InteractiveWebRTCAnswerBodyV0(
                    fence: offer.fence,
                    offerMessageID: .init(UUID()),
                    sdp: sdp,
                    dtlsFingerprintHex: fingerprint
                )
                return ClientWebRTCAnswerV0(
                    sdp: sdp, dtlsFingerprintHex: fingerprint
                )
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw UIKitClientWebRTCVideoPeerErrorV0.incompleteICE
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        delegate.retire()
        connection.close()
        surface.removeWebRTCVideoView(display)
    }

    private static func fingerprintHex(from sdp: String) throws -> String {
        guard let line = sdp.components(separatedBy: "\r\n")
            .first(where: { $0.hasPrefix("a=fingerprint:sha-256 ") })
        else { throw UIKitClientWebRTCVideoPeerErrorV0.invalidFingerprint }
        return String(line.dropFirst("a=fingerprint:sha-256 ".count))
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
    }
}
#endif
