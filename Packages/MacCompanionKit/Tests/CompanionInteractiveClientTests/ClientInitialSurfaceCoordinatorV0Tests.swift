import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let initialClientSessionID = UUID(
    uuidString: "019c6000-0000-7000-8000-000000000001"
)!
private let initialClientSurfaceID = UUID(
    uuidString: "019c6100-0000-7000-8000-000000000001"
)!

private func initialClientDescriptor() throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: initialClientSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: initialClientSurfaceID,
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

private func initialClientMedia(
    _ type: MediaRecordType,
    descriptor: AdaptiveSurfaceDescriptor,
    sequence: UInt64,
    clean: Bool = false
) throws -> MediaRecordHeader {
    let payload = type == .decoderConfiguration || type == .videoAccessUnit
    return try MediaRecordHeader(
        type: type,
        flags: clean ? [.cleanKeyframe] : [],
        payloadLength: type == .decoderConfiguration ? 16
            : (type == .videoAccessUnit ? 128 : 0),
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: sequence,
        presentationTimeNanoseconds: sequence * 1_000,
        encodedWidth: payload ? descriptor.encodedWidth : 0,
        encodedHeight: payload ? descriptor.encodedHeight : 0
    )
}

@Test func initialClientRequiresCleanMediaAndExactReplyBeforeInput() throws {
    var coordinator = try ClientInitialSurfaceCoordinatorV0(
        interactiveSessionID: initialClientSessionID,
        authorizationEpoch: .init(rawValue: 4),
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let requestID = WireUUID(UUID())
    let requestJSON = try coordinator.makeDescriptorRequest(
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceRequestBodyV0>.self,
        from: requestJSON
    )
    #expect(request.body.sequence == 1)

    let hostDescriptor = try initialClientDescriptor()
    let activationID = WireUUID(UUID())
    let descriptorJSON = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveInitialSurfaceDescriptorBodyV0(
            activationID: activationID,
            descriptor: InteractiveSurfaceWireDescriptorV0(
                descriptor: hostDescriptor,
                validForMilliseconds: 5_000
            ),
            sequence: 1
        )
    ))
    let descriptor = try coordinator.receiveDescriptor(
        descriptorJSON,
        clientMonotonicNowMilliseconds: 100
    )
    #expect(coordinator.phase == .awaitingMedia)
    #expect(throws: (any Error).self) {
        try coordinator.makeAcknowledgement(
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_002
        )
    }

    // Recreate after the intentional fail-closed early acknowledgement.
    coordinator = try ClientInitialSurfaceCoordinatorV0(
        interactiveSessionID: initialClientSessionID,
        authorizationEpoch: .init(rawValue: 4),
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    _ = try coordinator.makeDescriptorRequest(
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    _ = try coordinator.receiveDescriptor(
        descriptorJSON,
        clientMonotonicNowMilliseconds: 100
    )
    _ = try coordinator.admitMedia(
        header: initialClientMedia(
            .decoderConfiguration,
            descriptor: descriptor,
            sequence: 1
        ),
        payloadByteCount: 16
    )
    let cleanHeader = try initialClientMedia(
            .videoAccessUnit,
            descriptor: descriptor,
            sequence: 2,
            clean: true
        )
    _ = try coordinator.admitMedia(
        header: cleanHeader,
        payloadByteCount: 128
    )
    let deltaHeader = try initialClientMedia(
        .videoAccessUnit,
        descriptor: descriptor,
        sequence: 3
    )
    _ = try coordinator.admitMedia(
        header: deltaHeader,
        payloadByteCount: 128
    )
    #expect(try coordinator.confirmRenderedFrame(
        ClientDecodedFrameReceiptV0(
            generation: 1,
            fence: ClientDecoderFenceV0(header: deltaHeader),
            mediaSequence: deltaHeader.mediaSequence,
            presentationTimeNanoseconds:
                deltaHeader.presentationTimeNanoseconds,
            frameReference: UUID()
        )
    ) == false)
    #expect(try coordinator.confirmRenderedFrame(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: ClientDecoderFenceV0(header: cleanHeader),
        mediaSequence: cleanHeader.mediaSequence,
        presentationTimeNanoseconds:
            cleanHeader.presentationTimeNanoseconds,
        frameReference: UUID()
    )) == true)
    let ackID = WireUUID(UUID())
    let ackJSON = try coordinator.makeAcknowledgement(
        messageID: ackID,
        sentAtUnixMilliseconds: 1_003
    )
    let ack = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self,
        from: ackJSON
    )
    #expect(ack.body.sequence == 2)
    #expect(ack.body.readyMediaSequence == 2)

    let acknowledgedJSON = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: ackID,
        sentAtUnixMilliseconds: 1_004,
        body: try InteractiveInitialSurfaceAcknowledgedBodyV0(
            acknowledgement: ack.body,
            inputResumed: true,
            sequence: 2
        )
    ))
    try coordinator.receiveAcknowledged(acknowledgedJSON)
    #expect(coordinator.phase == .active)

    var replacements = try coordinator.replacementCoordinator()
    #expect(replacements.media.lastMediaSequence == 3)
    let steadyDelta = try initialClientMedia(
        .videoAccessUnit,
        descriptor: descriptor,
        sequence: 4
    )
    #expect(try replacements.admitMedia(
        header: steadyDelta,
        payloadByteCount: 128
    ) == .videoAccessUnit(cleanKeyframe: false))
    let firstInput = try replacements.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 199,
        payload: .pointerMove(x: 10, y: 20)
    )
    #expect(firstInput.sequence == 1)
    let selection = try replacements.beginSelection(
        targetKind: .desktop,
        targetToken: nil,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_005,
        clientMonotonicMilliseconds: 200
    )
    #expect(selection.reset?.sequence == 2)
    let select = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
        from: selection.requestJSON
    )
    #expect(select.body.sequence == 3)
}
