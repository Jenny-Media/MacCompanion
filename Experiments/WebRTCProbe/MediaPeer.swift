import CoreVideo
import Foundation
@preconcurrency import WebRTC

enum MediaProbeError: Error { case timeout(String), missingPeer, missingDescription, noH264, invalidFrame }

/// Only bounded synchronous waits on a non-UI owner; WebRTC supplies its own workers.
final class ProbeReply<Value>: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<Value, Error>?
    func complete(_ result: Result<Value, Error>) {
        condition.lock(); defer { condition.unlock() }
        guard self.result == nil else { return }
        self.result = result; condition.signal()
    }
    func wait(_ label: String, seconds: TimeInterval = 10) throws -> Value {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock(); defer { condition.unlock() }
        while result == nil {
            if !condition.wait(until: deadline) { throw MediaProbeError.timeout(label) }
        }
        return try result!.get()
    }
}

final class MediaPeer: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    private let factory: RTCPeerConnectionFactory
    private(set) var connection: RTCPeerConnection!
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private var sendingTrack: RTCVideoTrack?
    private var receivingTrack: RTCVideoTrack?
    private let lock = NSRecursiveLock()
    private var retired = false
    private let sink: FrameSink

    init(sending: Bool, sink: FrameSink, localNetworkOnly: Bool = false) throws {
        let peerFactory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                                  decoderFactory: RTCDefaultVideoDecoderFactory())
        if localNetworkOnly {
            let options = RTCPeerConnectionFactoryOptions()
            options.ignoreVPNNetworkAdapter = true
            options.ignoreCellularNetworkAdapter = true
            peerFactory.setOptions(options)
        }
        factory = peerFactory
        source = factory.videoSource(forScreenCast: true)
        capturer = RTCVideoCapturer(delegate: source)
        self.sink = sink
        super.init()
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = []
        config.bundlePolicy = .maxBundle
        config.tcpCandidatePolicy = .disabled
        connection = factory.peerConnection(with: config,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self)
        guard let connection else { throw MediaProbeError.missingPeer }
        if sending {
            let track = factory.videoTrack(with: source, trackId: "experiment-video")
            sendingTrack = track
            let settings = RTCRtpTransceiverInit()
            settings.direction = .sendOnly
            settings.streamIds = ["experiment"]
            guard let transceiver = connection.addTransceiver(with: track, init: settings) else {
                throw MediaProbeError.missingPeer
            }
            let codecs = factory.rtpSenderCapabilities(forKind: "video").codecs.filter { $0.name == "H264" }
            guard !codecs.isEmpty else { throw MediaProbeError.noH264 }
            try transceiver.setCodecPreferences(Optional(codecs))
            let parameters = transceiver.sender.parameters
            for encoding in parameters.encodings {
                encoding.maxBitrateBps = 4_000_000
                encoding.maxFramerate = 30
            }
            transceiver.sender.parameters = parameters
        }
    }

    func offer(restart: Bool = false) throws -> String {
        if restart { connection.restartIce() }
        let reply = ProbeReply<RTCSessionDescription>()
        connection.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in
            if let error { reply.complete(.failure(error)) }
            else if let sdp { reply.complete(.success(sdp)) }
            else { reply.complete(.failure(MediaProbeError.missingDescription)) }
        }
        return try local(reply.wait("offer"))
    }

    func answer(_ offer: String) throws -> String {
        try remote(offer, type: .offer)
        let reply = ProbeReply<RTCSessionDescription>()
        connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in
            if let error { reply.complete(.failure(error)) }
            else if let sdp { reply.complete(.success(sdp)) }
            else { reply.complete(.failure(MediaProbeError.missingDescription)) }
        }
        return try local(reply.wait("answer"))
    }

    func acceptAnswer(_ answer: String) throws { try remote(answer, type: .answer) }

    private func remote(_ sdp: String, type: RTCSdpType) throws {
        guard sdp.utf8.count <= 262_144 else { throw MediaProbeError.missingDescription }
        let reply = ProbeReply<Bool>()
        connection.setRemoteDescription(RTCSessionDescription(type: type, sdp: sdp)) { error in
            if let error { reply.complete(.failure(error)) } else { reply.complete(.success(true)) }
        }
        _ = try reply.wait("remote description")
    }

    private func local(_ sdp: RTCSessionDescription) throws -> String {
        let reply = ProbeReply<Bool>()
        connection.setLocalDescription(sdp) { error in
            if let error { reply.complete(.failure(error)) } else { reply.complete(.success(true)) }
        }
        _ = try reply.wait("local description")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if connection.iceGatheringState == .complete,
               connection.localDescription?.sdp.contains("a=candidate:") == true { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard connection.iceGatheringState == .complete,
              let sdp = connection.localDescription?.sdp, sdp.contains("a=candidate:") else {
            throw MediaProbeError.timeout("ICE gathering state=\(connection.iceGatheringState.rawValue) candidates=\(connection.localDescription?.sdp.components(separatedBy: "a=candidate:").count ?? 1)")
        }
        return sdp
    }

    func submit(_ buffer: CVPixelBuffer, timestampNs: Int64) {
        lock.lock(); defer { lock.unlock() }
        guard !retired else { return }
        source.capturer(capturer, didCapture: RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer),
            rotation: ._0, timeStampNs: timestampNs))
    }

    func statistics() throws -> [[String: Any]] {
        let reply = ProbeReply<RTCStatisticsReport>()
        connection.statistics { reply.complete(.success($0)) }
        let report = try reply.wait("statistics")
        let allowed = Set(["mimeType", "codecId", "kind", "framesEncoded", "framesDecoded", "framesReceived",
            "framesDropped", "packetsSent", "packetsReceived", "packetsLost", "bytesSent", "bytesReceived",
            "encoderImplementation", "decoderImplementation", "powerEfficientEncoder", "powerEfficientDecoder",
            "totalEncodeTime", "totalDecodeTime", "qualityLimitationReason", "currentRoundTripTime",
            "state", "nominated", "candidateType", "protocol", "dtlsState", "networkType",
            "selectedCandidatePairId", "localCandidateId", "remoteCandidateId", "availableOutgoingBitrate",
            "requestsSent", "responsesReceived", "consentRequestsSent", "framesPerSecond",
            "freezeCount", "totalFreezesDuration", "pliCount", "nackCount"])
        return report.statistics.values.filter { ["inbound-rtp", "outbound-rtp", "codec", "candidate-pair", "transport", "local-candidate", "remote-candidate"].contains($0.type) }.map {
            var values: [String: Any] = ["type": $0.type, "id": $0.id]
            for (key, value) in $0.values where allowed.contains(key) { values[key] = value }
            return values
        }
    }

    func close() {
        lock.lock()
        guard !retired else { lock.unlock(); return }
        retired = true
        sink.retire()
        let track = receivingTrack
        receivingTrack = nil
        sendingTrack?.isEnabled = false
        lock.unlock()
        track?.remove(sink)
        connection.close()
    }

    private func receive(_ track: RTCVideoTrack?) {
        lock.lock(); defer { lock.unlock() }
        guard !retired, let track, receivingTrack !== track else { return }
        receivingTrack?.remove(sink)
        receivingTrack = track
        track.add(sink)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) { receive(stream.videoTracks.first) }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) { dataChannel.close() }
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        receive(transceiver.receiver.track as? RTCVideoTrack)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        receive(rtpReceiver.track as? RTCVideoTrack)
    }
}
