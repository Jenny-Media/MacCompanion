import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let interactiveClientSessionID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000001"
)!
private let interactiveClientSurfaceID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000002"
)!

private func clientDesktopDescriptor(
    surfaceID: UUID = interactiveClientSurfaceID,
    surfaceRevision: UInt64 = 1,
    coordinateRevision: UInt64 = 1,
    interactionClasses: Set<SurfaceInteractionClass> = [
        .view, .pointer, .keyboard,
    ]
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: interactionClasses,
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 100,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func clientFocusedDescriptor(
    surfaceRevision: UInt64 = 1,
    coordinateRevision: UInt64 = 1,
    secure: Bool = false
) throws -> AdaptiveSurfaceDescriptor {
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(x: 1, y: 1, width: 2_000, height: 500),
        editable: true,
        secure: secure
    )
    return try AdaptiveSurfaceDescriptor(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: UUID(),
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        applicationToken: UUID(),
        parentSurfaceID: UUID(),
        fallbackSurfaceID: UUID(),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard, .text],
        privacyProfile: secure ? .secureOpaque : .assistedVisual,
        metadataFields: [.editable, .focusBounds, .focusCategory, .secure],
        focus: focus,
        createdAtMonotonicMilliseconds: 100,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func clientMediaHeader(
    _ type: MediaRecordType,
    descriptor: AdaptiveSurfaceDescriptor,
    sequence: UInt64,
    presentationTime: UInt64? = nil,
    clean: Bool = false,
    payloadLength: UInt32? = nil,
    width: UInt16? = nil,
    height: UInt16? = nil
) throws -> MediaRecordHeader {
    let carriesPayload = type == .decoderConfiguration || type == .videoAccessUnit
    return try MediaRecordHeader(
        type: type,
        flags: clean ? [.cleanKeyframe] : [],
        payloadLength: payloadLength ?? (type == .decoderConfiguration ? 16 : (
            type == .videoAccessUnit ? 128 : 0
        )),
        interactiveSessionID: descriptor.interactiveSessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: descriptor.surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: sequence,
        presentationTimeNanoseconds: presentationTime ?? sequence * 1_000,
        encodedWidth: width ?? (carriesPayload ? descriptor.encodedWidth : 0),
        encodedHeight: height ?? (carriesPayload ? descriptor.encodedHeight : 0)
    )
}

@Test func clientMediaRequiresConfigurationAndCleanKeyframeBeforeAcknowledgement() throws {
    let descriptor = try clientDesktopDescriptor()
    var media = try ClientMediaStreamAuthorityV0(
        initialDescriptor: descriptor
    )
    #expect(try media.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: descriptor,
            sequence: 1
        ),
        payloadByteCount: 16
    ) == .decoderConfiguration)
    #expect(throws: ClientMediaStreamErrorV0.acknowledgementNotReady) {
        _ = try media.takeAcknowledgementFence()
    }

    #expect(try media.admit(
        header: clientMediaHeader(
            .videoAccessUnit,
            descriptor: descriptor,
            sequence: 2,
            clean: true
        ),
        payloadByteCount: 128
    ) == .videoAccessUnit(cleanKeyframe: true))
    let fence = try media.takeAcknowledgementFence()
    #expect(fence.surface.surfaceID == descriptor.surfaceID)
    #expect(fence.surface.coordinateSpaceRevision == descriptor.coordinateSpaceRevision)
    #expect(fence.readyMediaSequence == 2)
    #expect(try media.admit(
        header: clientMediaHeader(
            .videoAccessUnit,
            descriptor: descriptor,
            sequence: 3
        ),
        payloadByteCount: 128
    ) == .videoAccessUnit(cleanKeyframe: false))
}

@Test func clientMediaRejectsDeltaBeforeCleanKeyframeAndCloses() throws {
    let descriptor = try clientDesktopDescriptor()
    var media = try ClientMediaStreamAuthorityV0(initialDescriptor: descriptor)
    _ = try media.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: descriptor,
            sequence: 1
        ),
        payloadByteCount: 16
    )
    #expect(throws: ClientMediaStreamErrorV0.cleanKeyframeRequired) {
        _ = try media.admit(
            header: clientMediaHeader(
                .videoAccessUnit,
                descriptor: descriptor,
                sequence: 2
            ),
            payloadByteCount: 128
        )
    }
    #expect(media.phase == .closed)
}

@Test func clientMediaTransitionRequiresNewFenceDiscontinuityConfigurationAndKeyframe() throws {
    let first = try clientDesktopDescriptor()
    let second = try clientDesktopDescriptor(
        surfaceID: UUID(),
        surfaceRevision: 2,
        coordinateRevision: 2
    )
    var media = try ClientMediaStreamAuthorityV0(initialDescriptor: first)
    _ = try media.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: first,
            sequence: 1
        ),
        payloadByteCount: 16
    )
    _ = try media.admit(
        header: clientMediaHeader(
            .videoAccessUnit,
            descriptor: first,
            sequence: 2,
            clean: true
        ),
        payloadByteCount: 128
    )
    _ = try media.takeAcknowledgementFence()
    try media.beginSurfaceTransition(to: second)
    #expect(try media.admit(
        header: clientMediaHeader(
            .discontinuity,
            descriptor: second,
            sequence: 3
        ),
        payloadByteCount: 0
    ) == .discontinuity)
    _ = try media.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: second,
            sequence: 4
        ),
        payloadByteCount: 16
    )
    _ = try media.admit(
        header: clientMediaHeader(
            .videoAccessUnit,
            descriptor: second,
            sequence: 5,
            clean: true
        ),
        payloadByteCount: 128
    )
    let fence = try media.takeAcknowledgementFence()
    #expect(fence.surface.surfaceID == second.surfaceID)
    #expect(fence.readyMediaSequence == 5)
    #expect(media.currentDescriptor == second)
}

@Test func clientMediaRejectsStaleFenceLengthDimensionsSequenceAndTimeline() throws {
    let descriptor = try clientDesktopDescriptor()

    var wrongLength = try ClientMediaStreamAuthorityV0(initialDescriptor: descriptor)
    #expect(throws: ClientMediaStreamErrorV0.payloadLengthMismatch) {
        _ = try wrongLength.admit(
            header: clientMediaHeader(
                .decoderConfiguration,
                descriptor: descriptor,
                sequence: 1
            ),
            payloadByteCount: 15
        )
    }

    var dimensions = try ClientMediaStreamAuthorityV0(initialDescriptor: descriptor)
    #expect(throws: ClientMediaStreamErrorV0.dimensionsMismatch) {
        _ = try dimensions.admit(
            header: clientMediaHeader(
                .decoderConfiguration,
                descriptor: descriptor,
                sequence: 1,
                width: 640
            ),
            payloadByteCount: 16
        )
    }

    var sequence = try ClientMediaStreamAuthorityV0(initialDescriptor: descriptor)
    _ = try sequence.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: descriptor,
            sequence: 2,
            presentationTime: 2_000
        ),
        payloadByteCount: 16
    )
    #expect(throws: ClientMediaStreamErrorV0.sequenceNotIncreasing) {
        _ = try sequence.admit(
            header: clientMediaHeader(
                .decoderConfiguration,
                descriptor: descriptor,
                sequence: 2,
                presentationTime: 2_001
            ),
            payloadByteCount: 16
        )
    }

    var timeline = try ClientMediaStreamAuthorityV0(initialDescriptor: descriptor)
    _ = try timeline.admit(
        header: clientMediaHeader(
            .decoderConfiguration,
            descriptor: descriptor,
            sequence: 1,
            presentationTime: 2_000
        ),
        payloadByteCount: 16
    )
    #expect(throws: ClientMediaStreamErrorV0.presentationTimeWentBackward) {
        _ = try timeline.admit(
            header: clientMediaHeader(
                .decoderConfiguration,
                descriptor: descriptor,
                sequence: 2,
                presentationTime: 1_999
            ),
            payloadByteCount: 16
        )
    }
}

@Test func clientInputUsesOnlyAcknowledgedFenceAndBalancedReliableSequence() throws {
    let descriptor = try clientDesktopDescriptor()
    var input = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try input.activate(acknowledged: descriptor)
    let move = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 100,
        payload: .pointerMove(x: 100, y: 200)
    )
    #expect(move.sequence == 1)
    #expect(move.surfaceID == WireUUID(descriptor.surfaceID))
    let down = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 101,
        payload: .button(button: .primary, transition: .down)
    )
    #expect(down.sequence == 2)
    #expect(input.pressedButtons == [.primary])
    let up = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 102,
        payload: .button(button: .primary, transition: .up)
    )
    #expect(up.sequence == 3)
    #expect(input.pressedButtons.isEmpty)
    #expect(try InteractiveInputCodec.decode(
        InteractiveInputCodec.encode(up)
    ) == up)
}

@Test func clientInputAllowsMissingFocusTextAndDeniesSecureFocus() throws {
    let desktop = try clientDesktopDescriptor(interactionClasses: [.view])
    var input = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try input.activate(acknowledged: desktop)
    #expect(throws: ClientInputProducerErrorV0.interactionClassDenied) {
        _ = try input.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: 100,
            payload: .pointerMove(x: 1, y: 1)
        )
    }
    #expect(input.lastSequence == 0)

    var ordinary = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try ordinary.activate(acknowledged: clientDesktopDescriptor(
        interactionClasses: [.view, .keyboard, .text]
    ))
    let text = try ordinary.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 100,
        payload: .text("hello")
    )
    #expect(text.focusToken == nil)
    #expect(text.focusRevision == nil)
    #expect(text.input == .text("hello"))

    var secure = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try secure.activate(acknowledged: clientFocusedDescriptor(secure: true))
    #expect(throws: ClientInputProducerErrorV0.textFocusDenied) {
        _ = try secure.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: 100,
            payload: .text("secret")
        )
    }
    #expect(secure.lastSequence == 0)
}

@Test func clientInputPauseSendsResetBeforeAdvancingDescriptor() throws {
    let first = try clientDesktopDescriptor()
    let second = try clientDesktopDescriptor(
        surfaceID: UUID(),
        surfaceRevision: 2,
        coordinateRevision: 2
    )
    var input = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try input.activate(acknowledged: first)
    _ = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 100,
        payload: .physicalKey(
            usage: 0x04,
            transition: .down,
            modifiers: [.leftCommand]
        )
    )
    let reset = try #require(try input.pauseAndReset(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 101
    ))
    #expect(reset.input == .reset)
    #expect(reset.sequence == 2)
    #expect(input.phase == .paused)
    #expect(input.pressedKeyboardUsages.isEmpty)
    try input.activate(acknowledged: second)
    let move = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 102,
        payload: .pointerMove(x: 2, y: 3)
    )
    #expect(move.sequence == 3)
    #expect(move.surfaceID == WireUUID(second.surfaceID))
}

@Test func clientInputRejectsBalanceTimeAndStaleDescriptorWithoutMutation() throws {
    let descriptor = try clientDesktopDescriptor()
    var input = try ClientInputProducerV0(
        interactiveSessionID: interactiveClientSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    try input.activate(acknowledged: descriptor)
    #expect(throws: ClientInputProducerErrorV0.unmatchedButtonUp) {
        _ = try input.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: 100,
            payload: .button(button: .primary, transition: .up)
        )
    }
    #expect(input.lastSequence == 0)
    _ = try input.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 101,
        payload: .modifiers([.leftShift])
    )
    #expect(throws: ClientInputProducerErrorV0.clientTimeWentBackward) {
        _ = try input.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: 100,
            payload: .modifiers([])
        )
    }
    #expect(input.lastSequence == 1)
    _ = try input.pauseAndReset(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 102
    )
    #expect(throws: ClientInputProducerErrorV0.staleDescriptor) {
        try input.activate(acknowledged: descriptor)
    }
}
