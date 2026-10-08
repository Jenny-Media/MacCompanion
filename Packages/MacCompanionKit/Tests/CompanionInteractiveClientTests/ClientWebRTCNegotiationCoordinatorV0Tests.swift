import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let webRTCSessionID = UUID(
    uuidString: "019c6200-0000-7000-8000-000000000001"
)!
private let webRTCSurfaceID = UUID(
    uuidString: "019c6200-0000-7000-8000-000000000002"
)!

private func webRTCDescriptor() throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: webRTCSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: webRTCSurfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func webRTCFence() throws -> InteractiveWebRTCNegotiationFenceV0 {
    try InteractiveWebRTCNegotiationFenceV0(
        interactiveSessionID: WireUUID(webRTCSessionID),
        authorizationEpoch: .init(rawValue: 4),
        negotiationID: WireUUID(UUID(
            uuidString: "019c6200-0000-7000-8000-000000000003"
        )!),
        peerGeneration: 1,
        surfaceID: WireUUID(webRTCSurfaceID),
        surfaceRevision: 1,
        coordinateSpaceRevision: 1
    )
}

private let webRTCFingerprint = String(repeating: "ab", count: 32)
private let webRTCSDP = "v=0\r\n"
    + "a=fingerprint:sha-256 "
    + Array(repeating: "AB", count: 32).joined(separator: ":")
    + "\r\na=candidate:1 1 UDP 1 127.0.0.1 10000 typ host\r\n"

private func webRTCOffer(
    fence: InteractiveWebRTCNegotiationFenceV0
) throws -> WireEnvelope<InteractiveWebRTCOfferBodyV0> {
    try WireEnvelope(
        messageID: WireUUID(UUID(
            uuidString: "019c6200-0000-7000-8000-000000000004"
        )!),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_000,
        body: InteractiveWebRTCOfferBodyV0(
            fence: fence, sdp: webRTCSDP,
            dtlsFingerprintHex: webRTCFingerprint
        )
    )
}

private actor WebRTCSignalingSpy: ClientWebRTCPrimarySignalingV0 {
    let fence: InteractiveWebRTCNegotiationFenceV0
    private(set) var submittedOfferID: WireUUID?
    private(set) var submittedCount = 0

    init(fence: InteractiveWebRTCNegotiationFenceV0) {
        self.fence = fence
    }

    func requestWebRTCOffer(for _: AdaptiveSurfaceDescriptor) async throws
        -> InteractiveWebRTCNegotiationFenceV0
    {
        fence
    }

    func submitWebRTCAnswer(
        for offer: WireEnvelope<InteractiveWebRTCOfferBodyV0>,
        sdp: String,
        dtlsFingerprintHex: String
    ) async throws {
        _ = try InteractiveWebRTCAnswerBodyV0(
            fence: offer.body.fence,
            offerMessageID: offer.messageID,
            sdp: sdp,
            dtlsFingerprintHex: dtlsFingerprintHex
        )
        submittedOfferID = offer.messageID
        submittedCount += 1
    }
}

private actor WebRTCPeerSpy: ClientWebRTCVideoPeerV0 {
    private(set) var closeCount = 0

    func answer(to _: InteractiveWebRTCOfferBodyV0) async throws
        -> ClientWebRTCAnswerV0
    {
        ClientWebRTCAnswerV0(
            sdp: webRTCSDP,
            dtlsFingerprintHex: webRTCFingerprint
        )
    }

    func close() async { closeCount += 1 }
}

@Test func webRTCNegotiationAdmitsOnlyMatchingOfferAndReady() async throws {
    let fence = try webRTCFence()
    let signaling = WebRTCSignalingSpy(fence: fence)
    let peer = WebRTCPeerSpy()
    let owner = ClientWebRTCNegotiationCoordinatorV0(signaling: signaling)
    try await owner.start(descriptor: webRTCDescriptor(), peer: peer)
    let offer = try webRTCOffer(fence: fence)
    await owner.receiveOffer(offer)
    #expect(await signaling.submittedOfferID == offer.messageID)
    #expect(await owner.phase == .awaitingReady(fence))
    let wrongReady = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_001,
        body: InteractiveWebRTCReadyBodyV0(
            fence: fence, offerMessageID: WireUUID(UUID())
        )
    )
    await owner.receiveReady(wrongReady)
    #expect(await owner.phase == .awaitingReady(fence))
    let ready = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_002,
        body: InteractiveWebRTCReadyBodyV0(
            fence: fence, offerMessageID: offer.messageID
        )
    )
    await owner.receiveReady(ready)
    #expect(await owner.phase == .ready(fence))
    await owner.close()
    #expect(await peer.closeCount == 1)
    #expect(await owner.phase == .closed)
}

@Test func webRTCNegotiationRejectsDuplicateAndStaleEvents() async throws {
    let fence = try webRTCFence()
    let signaling = WebRTCSignalingSpy(fence: fence)
    let peer = WebRTCPeerSpy()
    let owner = ClientWebRTCNegotiationCoordinatorV0(signaling: signaling)
    try await owner.start(descriptor: webRTCDescriptor(), peer: peer)
    let offer = try webRTCOffer(fence: fence)
    await owner.receiveOffer(offer)
    await owner.receiveOffer(offer)
    #expect(await signaling.submittedCount == 1)
    await owner.reject()
    #expect(await peer.closeCount == 1)
    #expect(await owner.phase == .idle)
    await owner.receiveOffer(offer)
    #expect(await signaling.submittedCount == 1)
}
