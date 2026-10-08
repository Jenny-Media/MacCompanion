import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

/// The app's peer supplies an answer only after ICE gathering has completed.
/// Closing must also blank any video retained by the peer's renderer.
public protocol ClientWebRTCVideoPeerV0: Sendable {
    func answer(to offer: InteractiveWebRTCOfferBodyV0) async throws
        -> ClientWebRTCAnswerV0
    func close() async
}

public struct ClientWebRTCAnswerV0: Sendable {
    public let sdp: String
    public let dtlsFingerprintHex: String

    public init(sdp: String, dtlsFingerprintHex: String) {
        self.sdp = sdp
        self.dtlsFingerprintHex = dtlsFingerprintHex
    }
}

public protocol ClientWebRTCPrimarySignalingV0: Sendable {
    func requestWebRTCOffer(for descriptor: AdaptiveSurfaceDescriptor)
        async throws -> InteractiveWebRTCNegotiationFenceV0
    func submitWebRTCAnswer(
        for offer: WireEnvelope<InteractiveWebRTCOfferBodyV0>,
        sdp: String,
        dtlsFingerprintHex: String
    ) async throws
}

extension ClientInteractivePrimaryChannelV0: ClientWebRTCPrimarySignalingV0 {}

public enum ClientWebRTCNegotiationPhaseV0: Equatable, Sendable {
    case idle
    case requesting
    case answering(InteractiveWebRTCNegotiationFenceV0)
    case awaitingReady(InteractiveWebRTCNegotiationFenceV0)
    case ready(InteractiveWebRTCNegotiationFenceV0)
    case closed
}

/// Keeps the existing authenticated primary exchange bound to one current
/// client peer. This actor does not grant input or interpret `ready` as a
/// rendered-frame receipt.
public actor ClientWebRTCNegotiationCoordinatorV0 {
    public private(set) var phase: ClientWebRTCNegotiationPhaseV0 = .idle

    private let signaling: any ClientWebRTCPrimarySignalingV0
    private var peer: (any ClientWebRTCVideoPeerV0)?
    private var offerMessageID: WireUUID?
    private var deferredOffer: WireEnvelope<InteractiveWebRTCOfferBodyV0>?
    private var attempt = UUID()

    public init(signaling: any ClientWebRTCPrimarySignalingV0) {
        self.signaling = signaling
    }

    public func start(
        descriptor: AdaptiveSurfaceDescriptor,
        peer: any ClientWebRTCVideoPeerV0
    ) async throws {
        guard phase != .closed else {
            await peer.close()
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let old = self.peer
        self.peer = peer
        offerMessageID = nil
        deferredOffer = nil
        let token = UUID()
        attempt = token
        phase = .requesting
        await old?.close()
        do {
            let fence = try await signaling.requestWebRTCOffer(
                for: descriptor
            )
            guard attempt == token, phase == .requesting else { return }
            phase = .answering(fence)
            if let deferredOffer {
                self.deferredOffer = nil
                await receiveOffer(deferredOffer)
            }
        } catch {
            guard attempt == token else { return }
            await retireCurrent()
            throw error
        }
    }

    public func receiveOffer(
        _ offer: WireEnvelope<InteractiveWebRTCOfferBodyV0>
    ) async {
        if phase == .requesting {
            // The primary reply can arrive before requestWebRTCOffer returns.
            // Keep at most one response for the current attempt.
            if deferredOffer == nil { deferredOffer = offer }
            else { await retireCurrent() }
            return
        }
        guard case let .answering(fence) = phase,
              offer.body.fence == fence,
              let peer else { return }
        let token = attempt
        offerMessageID = offer.messageID
        do {
            let answer = try await peer.answer(to: offer.body)
            guard attempt == token,
                  case .answering(fence) = phase,
                  offerMessageID == offer.messageID else { return }
            // A fast primary reply may publish `ready` while the send awaits.
            phase = .awaitingReady(fence)
            try await signaling.submitWebRTCAnswer(
                for: offer,
                sdp: answer.sdp,
                dtlsFingerprintHex: answer.dtlsFingerprintHex
            )
            guard attempt == token else { return }
        } catch {
            if attempt == token { await retireCurrent() }
        }
    }

    public func receiveReady(
        _ ready: WireEnvelope<InteractiveWebRTCReadyBodyV0>
    ) async {
        guard case let .awaitingReady(fence) = phase,
              ready.body.fence == fence,
              ready.body.offerMessageID == offerMessageID else { return }
        phase = .ready(fence)
    }

    public func reject() async { await retireCurrent() }

    public func close() async {
        guard phase != .closed else { return }
        attempt = UUID()
        phase = .closed
        let old = peer
        peer = nil
        offerMessageID = nil
        deferredOffer = nil
        await old?.close()
    }

    private func retireCurrent() async {
        guard phase != .closed else { return }
        attempt = UUID()
        phase = .idle
        let old = peer
        peer = nil
        offerMessageID = nil
        deferredOffer = nil
        await old?.close()
    }
}
