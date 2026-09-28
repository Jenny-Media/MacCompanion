import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let controlSessionID = UUID(
    uuidString: "019a6000-0000-7000-8000-000000000001"
)!
private let controlInitialSurfaceID = UUID(
    uuidString: "019a6100-0000-7000-8000-000000000001"
)!
private let controlReplacementSurfaceID = UUID(
    uuidString: "019a6100-0000-7000-8000-000000000002"
)!

private func controlDescriptor(
    surfaceID: UUID,
    revision: UInt64,
    coordinateRevision: UInt64
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: controlSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: revision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
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

private func controlMediaHeader(
    _ type: MediaRecordType,
    descriptor: AdaptiveSurfaceDescriptor,
    sequence: UInt64,
    clean: Bool = false
) throws -> MediaRecordHeader {
    let carriesPayload = type == .decoderConfiguration
        || type == .videoAccessUnit
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
        encodedWidth: carriesPayload ? descriptor.encodedWidth : 0,
        encodedHeight: carriesPayload ? descriptor.encodedHeight : 0
    )
}

private func selectedResponse(
    requestMessageID: WireUUID,
    descriptor: AdaptiveSurfaceDescriptor,
    transitionID: WireUUID,
    mediaSequenceBeforeTransition: Int64 = 0,
    serverSequence: Int64 = 1
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestMessageID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveSurfaceSelectedBodyV0(
            transitionID: transitionID,
            descriptor: InteractiveSurfaceWireDescriptorV0(
                descriptor: descriptor,
                validForMilliseconds: 5_000
            ),
            mediaSequenceBeforeTransition: mediaSequenceBeforeTransition,
            sequence: serverSequence
        )
    ))
}

private func targetInventoryResponse(
    requestMessageID: WireUUID,
    targetToken: WireUUID,
    serverSequence: Int64 = 1,
    validForMilliseconds: Int64 = 100
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestMessageID,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveSurfaceTargetsResponseBodyV0(
            interactiveSessionID: WireUUID(controlSessionID),
            authorizationEpoch: .init(rawValue: 4),
            inventoryRevision: 1,
            validForMilliseconds: validForMilliseconds,
            candidates: [
                try InteractiveSurfaceTargetCandidateV0(
                    targetToken: targetToken,
                    kind: .application,
                    applicationToken: targetToken,
                    applicationName: "Notes",
                    windowOrdinal: nil,
                    currentWindowAvailable: true
                ),
            ],
            sequence: serverSequence
        )
    ))
}

private func controlFocus() throws -> SurfaceFocus {
    try SurfaceFocus(
        token: UUID(
            uuidString: "019a6200-0000-7000-8000-000000000001"
        )!,
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 1_000,
            y: 2_000,
            width: 30_000,
            height: 12_000
        ),
        editable: true,
        secure: false
    )
}

private func controlFocusEvent(
    current: AdaptiveSurfaceDescriptor,
    targetToken: WireUUID,
    focus: SurfaceFocus,
    eventSequence: Int64,
    inputPaused: Bool = false,
    messageID: WireUUID = WireUUID(UUID())
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: messageID,
        correlationID: nil,
        channel: .events,
        sentAtUnixMilliseconds: 1_001,
        body: try InteractiveSurfaceFocusChangedBodyV0(
            interactiveSessionID: WireUUID(controlSessionID),
            authorizationEpoch: .init(rawValue: 4),
            currentSurfaceID: WireUUID(current.surfaceID),
            currentSurfaceRevision: current.surfaceRevision,
            currentCoordinateSpaceRevision:
                current.coordinateSpaceRevision,
            recommendedTargetKind: .focusedRegion,
            targetToken: targetToken,
            focus: InteractiveSurfaceWireFocusV0(focus),
            inputPaused: inputPaused,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000,
            eventSequence: eventSequence
        )
    ))
}

private func focusedControlDescriptor(
    focus: SurfaceFocus
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: controlSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: controlReplacementSurfaceID,
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: UUID(),
        parentSurfaceID: controlInitialSurfaceID,
        fallbackSurfaceID: controlInitialSurfaceID,
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .assistedVisual,
        metadataFields: [
            .focusCategory, .focusBounds, .editable, .secure,
        ],
        focus: focus,
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

@Test func focusRefreshDuringSelectionDoesNotCloseTransition() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let focus = try controlFocus()
    let firstTargetToken = WireUUID(UUID())
    _ = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: firstTargetToken,
            focus: focus,
            eventSequence: 1
        ),
        clientMonotonicNowMilliseconds: 100
    )

    let requestID = WireUUID(UUID())
    _ = try coordinator.beginSelection(
        targetKind: .focusedRegion,
        targetToken: firstTargetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: requestID,
        sentAtUnixMilliseconds: 1_002,
        clientMonotonicMilliseconds: 101
    )

    let refresh = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: WireUUID(UUID()),
            focus: focus,
            eventSequence: 2
        ),
        clientMonotonicNowMilliseconds: 102
    )
    #expect(refresh.eventSequence == 2)
    #expect(coordinator.phase == .awaitingSelection)

    _ = try coordinator.receiveSelected(
        selectedResponse(
            requestMessageID: requestID,
            descriptor: focusedControlDescriptor(focus: focus),
            transitionID: WireUUID(UUID())
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(coordinator.phase == .awaitingMedia)
}

@Test func focusedSelectionAcceptsSafeDesktopFallbackAfterHostFocusChurn()
    throws
{
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let targetToken = WireUUID(UUID())
    _ = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: targetToken,
            focus: controlFocus(),
            eventSequence: 1
        ),
        clientMonotonicNowMilliseconds: 100
    )
    let requestID = WireUUID(UUID())
    _ = try coordinator.beginSelection(
        targetKind: .focusedRegion,
        targetToken: targetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: requestID,
        sentAtUnixMilliseconds: 1_002,
        clientMonotonicMilliseconds: 101
    )
    let fallback = try controlDescriptor(
        surfaceID: controlReplacementSurfaceID,
        revision: 2,
        coordinateRevision: 2
    )
    let selected = try coordinator.receiveSelected(
        selectedResponse(
            requestMessageID: requestID,
            descriptor: fallback,
            transitionID: WireUUID(UUID())
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(selected.kind == .desktop)
    #expect(selected.focus == nil)
    #expect(coordinator.phase == .awaitingMedia)
}

@Test func supersededFocusTokenIsRecoverableBeforeSelection() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let focus = try controlFocus()
    let supersededTargetToken = WireUUID(UUID())
    _ = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: supersededTargetToken,
            focus: focus,
            eventSequence: 1
        ),
        clientMonotonicNowMilliseconds: 100
    )
    let currentTargetToken = WireUUID(UUID())
    _ = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: currentTargetToken,
            focus: focus,
            eventSequence: 2
        ),
        clientMonotonicNowMilliseconds: 101
    )

    #expect(throws: ClientSurfaceControlErrorV0.targetInventoryRequired) {
        _ = try coordinator.beginSelection(
            targetKind: .focusedRegion,
            targetToken: supersededTargetToken,
            resetMessageID: WireUUID(UUID()),
            requestMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_002,
            clientMonotonicMilliseconds: 102
        )
    }
    #expect(coordinator.phase == .active)

    _ = try coordinator.beginSelection(
        targetKind: .focusedRegion,
        targetToken: currentTargetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_003,
        clientMonotonicMilliseconds: 103
    )
    #expect(coordinator.phase == .awaitingSelection)
}

@Test func duplicateFocusEventClosesTheCoordinator() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let messageID = WireUUID(UUID())
    let eventJSON = try controlFocusEvent(
        current: initial,
        targetToken: WireUUID(UUID()),
        focus: controlFocus(),
        eventSequence: 1,
        messageID: messageID
    )
    _ = try coordinator.receiveFocusEvent(
        eventJSON,
        clientMonotonicNowMilliseconds: 100
    )

    #expect(throws: ClientSurfaceControlErrorV0.duplicateMessage) {
        _ = try coordinator.receiveFocusEvent(
            eventJSON,
            clientMonotonicNowMilliseconds: 101
        )
    }
    #expect(coordinator.phase == .closed)
}

@Test func clientFocusEventUsesOneCurrentTokenAndProvenTransitionPath()
    throws
{
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let targetToken = WireUUID(UUID())
    let focus = try controlFocus()
    let admitted = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: targetToken,
            focus: focus,
            eventSequence: 1
        ),
        clientMonotonicNowMilliseconds: 100
    )
    #expect(admitted.focus == focus)
    #expect(admitted.expiresAtMonotonicMilliseconds == 1_100)
    #expect(coordinator.input.phase == .active)

    let requestID = WireUUID(UUID())
    let selection = try coordinator.beginSelection(
        targetKind: .focusedRegion,
        targetToken: targetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: requestID,
        sentAtUnixMilliseconds: 1_002,
        clientMonotonicMilliseconds: 101
    )
    #expect(selection.reset?.input == .reset)
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
        from: selection.requestJSON
    )
    #expect(request.body.targetKind == .focusedRegion)
    #expect(request.body.targetToken == targetToken)

    let replacement = try focusedControlDescriptor(focus: focus)
    let selected = try coordinator.receiveSelected(
        selectedResponse(
            requestMessageID: requestID,
            descriptor: replacement,
            transitionID: WireUUID(UUID())
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(selected.focus == focus)
    #expect(coordinator.phase == .awaitingMedia)
}

@Test func pausedFocusEventSuppressesInputAndSequenceGapCloses() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let focus = try controlFocus()
    _ = try coordinator.receiveFocusEvent(
        controlFocusEvent(
            current: initial,
            targetToken: WireUUID(UUID()),
            focus: focus,
            eventSequence: 1,
            inputPaused: true
        ),
        clientMonotonicNowMilliseconds: 100
    )
    #expect(coordinator.inputPausedByFocusEvent)
    #expect(throws: ClientSurfaceControlErrorV0.inputPausedByFocusEvent) {
        _ = try coordinator.makeInput(
            messageID: WireUUID(UUID()),
            clientMonotonicMilliseconds: 101,
            payload: .pointerMove(x: 1, y: 2)
        )
    }
    #expect(coordinator.phase == .active)

    #expect(throws: ClientSurfaceControlErrorV0
        .focusEventSequenceMismatch(expected: 2, actual: 3)) {
        _ = try coordinator.receiveFocusEvent(
            controlFocusEvent(
                current: initial,
                targetToken: WireUUID(UUID()),
                focus: focus,
                eventSequence: 3,
                inputPaused: true
            ),
            clientMonotonicNowMilliseconds: 102
        )
    }
    #expect(coordinator.phase == .closed)
}

@Test func clientUsesOnlyCurrentInventoryTokensAndPreservesSequences() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let inventoryRequestID = WireUUID(UUID())
    let inventoryRequestJSON = try coordinator.makeTargetInventoryRequest(
        messageID: inventoryRequestID,
        sentAtUnixMilliseconds: 1_000
    )
    let inventoryRequest = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceTargetsRequestBodyV0>.self,
        from: inventoryRequestJSON
    )
    #expect(inventoryRequest.body.sequence == 1)

    let targetToken = WireUUID(UUID())
    let candidates = try coordinator.receiveTargetInventory(
        targetInventoryResponse(
            requestMessageID: inventoryRequestID,
            targetToken: targetToken
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(candidates.map(\.applicationName) == ["Notes"])
    #expect(coordinator.targetCandidates == candidates)

    let selection = try coordinator.beginSelection(
        targetKind: .application,
        targetToken: targetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_002,
        clientMonotonicMilliseconds: 299
    )
    let selectionEnvelope = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
        from: selection.requestJSON
    )
    #expect(selectionEnvelope.body.sequence == 2)
    #expect(selectionEnvelope.body.targetToken == targetToken)
    #expect(coordinator.targetCandidates.isEmpty)

    var expired = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let expiredRequestID = WireUUID(UUID())
    _ = try expired.makeTargetInventoryRequest(
        messageID: expiredRequestID,
        sentAtUnixMilliseconds: 1_000
    )
    _ = try expired.receiveTargetInventory(
        targetInventoryResponse(
            requestMessageID: expiredRequestID,
            targetToken: targetToken
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(throws: ClientSurfaceControlErrorV0.targetUnavailable) {
        _ = try expired.beginSelection(
            targetKind: .application,
            targetToken: targetToken,
            resetMessageID: WireUUID(UUID()),
            requestMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_002,
            clientMonotonicMilliseconds: 300
        )
    }
}

@Test func clientCanSelectAfterScrollingLongInventory() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let requestID = WireUUID(UUID())
    let targetToken = WireUUID(UUID())
    _ = try coordinator.makeTargetInventoryRequest(
        messageID: requestID,
        sentAtUnixMilliseconds: 1_000
    )
    _ = try coordinator.receiveTargetInventory(
        targetInventoryResponse(
            requestMessageID: requestID,
            targetToken: targetToken,
            validForMilliseconds: 120_000
        ),
        clientMonotonicNowMilliseconds: 200
    )
    let selection = try coordinator.beginSelection(
        targetKind: .application,
        targetToken: targetToken,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_002,
        clientMonotonicMilliseconds: 20_200
    )
    #expect(!selection.requestJSON.isEmpty)
}

@Test func clientSurfaceControlRequiresResetMediaProofAndExactHostAck() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let replacement = try controlDescriptor(
        surfaceID: controlReplacementSurfaceID,
        revision: 2,
        coordinateRevision: 2
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let selectMessageID = WireUUID(UUID())
    let selection = try coordinator.beginSelection(
        targetKind: .desktop,
        targetToken: nil,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: selectMessageID,
        sentAtUnixMilliseconds: 1_000,
        clientMonotonicMilliseconds: 100
    )
    #expect(selection.reset?.input == .reset)
    #expect(selection.reset?.surfaceID == WireUUID(controlInitialSurfaceID))
    #expect(coordinator.input.phase == .paused)
    let selectionRequest = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
        from: selection.requestJSON
    )
    #expect(selectionRequest.body.sequence == 1)

    let transitionID = WireUUID(UUID())
    let clientDescriptor = try coordinator.receiveSelected(
        selectedResponse(
            requestMessageID: selectMessageID,
            descriptor: replacement,
            transitionID: transitionID
        ),
        clientMonotonicNowMilliseconds: 200
    )
    #expect(clientDescriptor.createdAtMonotonicMilliseconds == 200)
    #expect(clientDescriptor.expiresAtMonotonicMilliseconds == 5_200)
    #expect(coordinator.phase == .awaitingMedia)

    _ = try coordinator.admitMedia(
        header: controlMediaHeader(
            .discontinuity,
            descriptor: clientDescriptor,
            sequence: 1
        ),
        payloadByteCount: 0
    )
    _ = try coordinator.admitMedia(
        header: controlMediaHeader(
            .decoderConfiguration,
            descriptor: clientDescriptor,
            sequence: 2
        ),
        payloadByteCount: 16
    )
    let cleanHeader = try controlMediaHeader(
        .videoAccessUnit,
        descriptor: clientDescriptor,
        sequence: 3,
        clean: true
    )
    _ = try coordinator.admitMedia(
        header: cleanHeader,
        payloadByteCount: 128
    )
    #expect(try coordinator.confirmRenderedFrame(
        ClientDecodedFrameReceiptV0(
            generation: 1,
            fence: ClientDecoderFenceV0(header: cleanHeader),
            mediaSequence: cleanHeader.mediaSequence,
            presentationTimeNanoseconds:
                cleanHeader.presentationTimeNanoseconds,
            frameReference: UUID()
        )
    ))

    let acknowledgementMessageID = WireUUID(UUID())
    let acknowledgementJSON = try coordinator.makeAcknowledgement(
        messageID: acknowledgementMessageID,
        sentAtUnixMilliseconds: 1_002
    )
    let acknowledgement = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self,
        from: acknowledgementJSON
    )
    #expect(acknowledgement.body.sequence == 2)
    #expect(acknowledgement.body.transitionID == transitionID)
    #expect(acknowledgement.body.readyMediaSequence == 3)
    #expect(coordinator.input.phase == .paused)

    let response = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: acknowledgementMessageID,
        sentAtUnixMilliseconds: 1_003,
        body: try InteractiveSurfaceAcknowledgedBodyV0(
            acknowledgement: acknowledgement.body,
            inputResumed: true,
            sequence: 2
        )
    ))
    try coordinator.receiveAcknowledged(response)
    #expect(coordinator.phase == .active)
    #expect(coordinator.input.phase == .active)

    let input = try coordinator.makeInput(
        messageID: WireUUID(UUID()),
        clientMonotonicMilliseconds: 201,
        payload: .pointerMove(x: 10, y: 20)
    )
    #expect(input.surfaceID == WireUUID(controlReplacementSurfaceID))
    #expect(input.surfaceRevision.rawValue == 2)
}

@Test func clientCannotAcknowledgeBeforeCleanMediaBoundary() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let replacement = try controlDescriptor(
        surfaceID: controlReplacementSurfaceID,
        revision: 2,
        coordinateRevision: 2
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let requestID = WireUUID(UUID())
    _ = try coordinator.beginSelection(
        targetKind: .desktop,
        targetToken: nil,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: requestID,
        sentAtUnixMilliseconds: 1_000,
        clientMonotonicMilliseconds: 100
    )
    _ = try coordinator.receiveSelected(
        selectedResponse(
            requestMessageID: requestID,
            descriptor: replacement,
            transitionID: WireUUID(UUID())
        ),
        clientMonotonicNowMilliseconds: 200
    )

    #expect(throws: ClientMediaStreamErrorV0.acknowledgementNotReady) {
        _ = try coordinator.makeAcknowledgement(
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_001
        )
    }
    #expect(coordinator.phase == .closed)
    #expect(coordinator.input.phase == .paused)

    var decodedButNotRendered = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let decodedRequestID = WireUUID(UUID())
    _ = try decodedButNotRendered.beginSelection(
        targetKind: .desktop,
        targetToken: nil,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: decodedRequestID,
        sentAtUnixMilliseconds: 1_010,
        clientMonotonicMilliseconds: 110
    )
    let decodedDescriptor = try decodedButNotRendered.receiveSelected(
        selectedResponse(
            requestMessageID: decodedRequestID,
            descriptor: replacement,
            transitionID: WireUUID(UUID())
        ),
        clientMonotonicNowMilliseconds: 210
    )
    _ = try decodedButNotRendered.admitMedia(
        header: controlMediaHeader(
            .discontinuity,
            descriptor: decodedDescriptor,
            sequence: 1
        ),
        payloadByteCount: 0
    )
    _ = try decodedButNotRendered.admitMedia(
        header: controlMediaHeader(
            .decoderConfiguration,
            descriptor: decodedDescriptor,
            sequence: 2
        ),
        payloadByteCount: 16
    )
    _ = try decodedButNotRendered.admitMedia(
        header: controlMediaHeader(
            .videoAccessUnit,
            descriptor: decodedDescriptor,
            sequence: 3,
            clean: true
        ),
        payloadByteCount: 128
    )
    #expect(throws: ClientSurfaceControlErrorV0.mediaBoundaryMismatch) {
        _ = try decodedButNotRendered.makeAcknowledgement(
            messageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_011
        )
    }
    #expect(decodedButNotRendered.phase == .closed)
}

@Test func selectedResponseMustMatchCorrelationSequenceAndMediaBoundary() throws {
    let initial = try controlDescriptor(
        surfaceID: controlInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let replacement = try controlDescriptor(
        surfaceID: controlReplacementSurfaceID,
        revision: 2,
        coordinateRevision: 2
    )
    var coordinator = try ClientSurfaceControlCoordinatorV0(
        acknowledgedDescriptor: initial,
        sessionAllowedInteractionClasses: [.view, .pointer, .keyboard]
    )
    let requestID = WireUUID(UUID())
    _ = try coordinator.beginSelection(
        targetKind: .desktop,
        targetToken: nil,
        resetMessageID: WireUUID(UUID()),
        requestMessageID: requestID,
        sentAtUnixMilliseconds: 1_000,
        clientMonotonicMilliseconds: 100
    )

    #expect(throws: ClientSurfaceControlErrorV0.mediaBoundaryMismatch) {
        _ = try coordinator.receiveSelected(
            selectedResponse(
                requestMessageID: requestID,
                descriptor: replacement,
                transitionID: WireUUID(UUID()),
                mediaSequenceBeforeTransition: 1
            ),
            clientMonotonicNowMilliseconds: 200
        )
    }
    #expect(coordinator.phase == .closed)
}
