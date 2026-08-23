import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTransport
import CompanionWire
import Foundation

public enum ClientSurfaceControlPhaseV0: String, Equatable, Sendable {
    case active
    case awaitingSelection
    case awaitingMedia
    case awaitingAcknowledgement
    case closed
}

public enum ClientSurfaceControlErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPhase(ClientSurfaceControlPhaseV0)
    case sequenceExhausted
    case unexpectedMessage(WireMessageKind)
    case correlationMismatch
    case sequenceMismatch(expected: Int64, actual: Int64)
    case sessionMismatch
    case authorizationChanged
    case descriptorMismatch
    case mediaBoundaryMismatch
    case duplicateMessage
    case targetInventoryRequired
    case targetUnavailable
    case focusEventSequenceMismatch(expected: Int64, actual: Int64)
    case focusEventFenceMismatch
    case focusEventExpired
    case inputPausedByFocusEvent
}

public struct ClientSurfaceSelectionRequestV0: Equatable, Sendable {
    public let reset: InteractiveInputEnvelope?
    public let requestJSON: Data

    public init(reset: InteractiveInputEnvelope?, requestJSON: Data) {
        self.reset = reset
        self.requestJSON = requestJSON
    }
}

public struct ClientSurfaceFocusEventV0: Equatable, Sendable {
    public let messageID: WireUUID
    public let eventSequence: Int64
    public let recommendedTargetKind: InteractiveSurfaceKind
    public let targetToken: WireUUID?
    public let focus: SurfaceFocus?
    public let inputPaused: Bool
    public let reason: InteractiveFocusEventReasonV0
    public let expiresAtMonotonicMilliseconds: Int64

    package init(
        messageID: WireUUID,
        eventSequence: Int64,
        recommendedTargetKind: InteractiveSurfaceKind,
        targetToken: WireUUID?,
        focus: SurfaceFocus?,
        inputPaused: Bool,
        reason: InteractiveFocusEventReasonV0,
        expiresAtMonotonicMilliseconds: Int64
    ) {
        self.messageID = messageID
        self.eventSequence = eventSequence
        self.recommendedTargetKind = recommendedTargetKind
        self.targetToken = targetToken
        self.focus = focus
        self.inputPaused = inputPaused
        self.reason = reason
        self.expiresAtMonotonicMilliseconds =
            expiresAtMonotonicMilliseconds
    }
}

/// Owns the replacement-only client path from an already acknowledged surface
/// through reliable reset, selection, media readiness, acknowledgement, and
/// input reactivation. Initial Desktop activation remains a separate gate.
public struct ClientSurfaceControlCoordinatorV0: Sendable {
    private struct PendingSelection: Sendable {
        let requestMessageID: WireUUID
        let requestedKind: InteractiveSurfaceKind
        let requestedFocus: SurfaceFocus?
    }

    private struct PendingTargetInventory: Sendable {
        let requestMessageID: WireUUID
    }

    private struct TargetInventory: Sendable {
        let revision: Int64
        let expiresAtMonotonicMilliseconds: Int64
        let candidates: [InteractiveSurfaceTargetCandidateV0]
    }

    private struct PendingTransition: Sendable {
        let transitionID: WireUUID
        let descriptor: AdaptiveSurfaceDescriptor
    }

    private struct PendingAcknowledgement: Sendable {
        let requestMessageID: WireUUID
        let body: InteractiveSurfaceAcknowledgementBodyV0
        let descriptor: AdaptiveSurfaceDescriptor
    }

    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    public private(set) var phase: ClientSurfaceControlPhaseV0 = .active
    public private(set) var media: ClientMediaStreamAuthorityV0
    public private(set) var input: ClientInputProducerV0
    public private(set) var targetCandidates:
        [InteractiveSurfaceTargetCandidateV0] = []
    public private(set) var latestFocusEvent: ClientSurfaceFocusEventV0?
    public private(set) var inputPausedByFocusEvent = false

    /// `nil` means no current inventory has completed. An empty array is a
    /// valid privacy-limited inventory and must not be confused with a reply
    /// that is still pending.
    public var availableTargetCandidates:
        [InteractiveSurfaceTargetCandidateV0]?
    {
        targetInventory?.candidates
    }

    public var descriptor: AdaptiveSurfaceDescriptor {
        pendingTransition?.descriptor
            ?? pendingAcknowledgement?.descriptor
            ?? currentDescriptor
    }

    private var currentDescriptor: AdaptiveSurfaceDescriptor
    private var pendingSelection: PendingSelection?
    private var pendingTargetInventory: PendingTargetInventory?
    private var targetInventory: TargetInventory?
    private var pendingTransition: PendingTransition?
    private var pendingAcknowledgement: PendingAcknowledgement?
    private var renderedReadyMediaSequence: UInt64?
    private var nextClientSequence: Int64 = 1
    private var expectedServerSequence: Int64 = 1
    private var expectedFocusEventSequence: Int64 = 1
    private var replay = ConnectionReplayWindow()

    public init(
        acknowledgedDescriptor: AdaptiveSurfaceDescriptor,
        sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>,
        initialNextClientSequence: Int64 = 1,
        initialExpectedServerSequence: Int64 = 1
    ) throws {
        let media = try ClientMediaStreamAuthorityV0(
            initialDescriptor: acknowledgedDescriptor
        )
        var input = try ClientInputProducerV0(
            interactiveSessionID:
                acknowledgedDescriptor.interactiveSessionID,
            authorizationEpoch:
                acknowledgedDescriptor.authorizationEpoch
        )
        try input.activate(acknowledged: acknowledgedDescriptor)
        try self.init(
            acknowledgedDescriptor: acknowledgedDescriptor,
            sessionAllowedInteractionClasses:
                sessionAllowedInteractionClasses,
            media: media,
            input: input,
            initialNextClientSequence: initialNextClientSequence,
            initialExpectedServerSequence: initialExpectedServerSequence
        )
    }

    package init(
        acknowledgedDescriptor: AdaptiveSurfaceDescriptor,
        sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>,
        media: ClientMediaStreamAuthorityV0,
        input: ClientInputProducerV0,
        initialNextClientSequence: Int64,
        initialExpectedServerSequence: Int64
    ) throws {
        try acknowledgedDescriptor.validate()
        guard Set(acknowledgedDescriptor.interactionClasses)
                .isSubset(of: sessionAllowedInteractionClasses),
              sessionAllowedInteractionClasses.contains(.view),
              media.phase == .active,
              media.pendingDescriptor == nil,
              media.currentDescriptor == acknowledgedDescriptor,
              input.isActive(on: acknowledgedDescriptor),
              initialNextClientSequence >= 1,
              initialNextClientSequence <= WireLimits.maximumSafeInteger,
              initialExpectedServerSequence >= 1,
              initialExpectedServerSequence <= WireLimits.maximumSafeInteger else {
            throw ClientSurfaceControlErrorV0.invalidConfiguration
        }
        interactiveSessionID = acknowledgedDescriptor.interactiveSessionID
        authorizationEpoch = acknowledgedDescriptor.authorizationEpoch
        self.sessionAllowedInteractionClasses = sessionAllowedInteractionClasses
        currentDescriptor = acknowledgedDescriptor
        self.media = media
        self.input = input
        nextClientSequence = initialNextClientSequence
        expectedServerSequence = initialExpectedServerSequence
    }

    public mutating func makeTargetInventoryRequest(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        do {
            try requirePhase(.active)
            guard pendingTargetInventory == nil else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let sequence = try consumeClientSequenceCandidate()
            let body = try InteractiveSurfaceTargetsRequestBodyV0(
                interactiveSessionID: WireUUID(interactiveSessionID),
                authorizationEpoch: authorizationEpoch,
                sequence: sequence
            )
            let data = try WireCodec.encode(WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            ))
            pendingTargetInventory = PendingTargetInventory(
                requestMessageID: messageID
            )
            targetInventory = nil
            targetCandidates = []
            nextClientSequence = sequence + 1
            return data
        } catch {
            failClosed()
            throw error
        }
    }

    @discardableResult
    public mutating func receiveFocusEvent(
        _ eventJSON: Data,
        clientMonotonicNowMilliseconds: Int64
    ) throws -> ClientSurfaceFocusEventV0 {
        do {
            try requirePhase(.active)
            let envelope = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceFocusChangedBodyV0>.self,
                from: eventJSON
            )
            let body = envelope.body
            guard body.eventSequence == expectedFocusEventSequence else {
                throw ClientSurfaceControlErrorV0
                    .focusEventSequenceMismatch(
                        expected: expectedFocusEventSequence,
                        actual: body.eventSequence
                    )
            }
            guard body.interactiveSessionID.rawValue
                    == interactiveSessionID,
                  body.authorizationEpoch == authorizationEpoch,
                  body.currentSurfaceID.rawValue
                    == currentDescriptor.surfaceID,
                  body.currentSurfaceRevision
                    == currentDescriptor.surfaceRevision,
                  body.currentCoordinateSpaceRevision
                    == currentDescriptor.coordinateSpaceRevision else {
                throw ClientSurfaceControlErrorV0.focusEventFenceMismatch
            }
            if currentDescriptor.kind == .focusedRegion {
                guard body.inputPaused,
                      body.focus?.revision != currentDescriptor.focus?.revision
                        || body.focus?.token.rawValue
                            != currentDescriptor.focus?.token else {
                    throw ClientSurfaceControlErrorV0.focusEventFenceMismatch
                }
            }
            let expiry = try body.clientExpiry(
                receivedAtMonotonicMilliseconds:
                    clientMonotonicNowMilliseconds
            )
            let event = ClientSurfaceFocusEventV0(
                messageID: envelope.messageID,
                eventSequence: body.eventSequence,
                recommendedTargetKind: body.recommendedTargetKind,
                targetToken: body.targetToken,
                focus: try body.focus?.materialize(),
                inputPaused: body.inputPaused,
                reason: body.reason,
                expiresAtMonotonicMilliseconds: expiry
            )
            guard expectedFocusEventSequence
                    <= WireLimits.maximumSafeInteger else {
                throw ClientSurfaceControlErrorV0.sequenceExhausted
            }
            expectedFocusEventSequence += 1
            latestFocusEvent = event
            if event.inputPaused { inputPausedByFocusEvent = true }
            return event
        } catch {
            failClosed()
            throw error
        }
    }

    @discardableResult
    public mutating func receiveTargetInventory(
        _ responseJSON: Data,
        clientMonotonicNowMilliseconds: Int64
    ) throws -> [InteractiveSurfaceTargetCandidateV0] {
        do {
            try requirePhase(.active)
            guard let pendingTargetInventory,
                  clientMonotonicNowMilliseconds >= 0 else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .interactiveSurfaceTargetsResponse else {
                throw ClientSurfaceControlErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID
                    == pendingTargetInventory.requestMessageID else {
                throw ClientSurfaceControlErrorV0.correlationMismatch
            }
            try admitServerSequence(response.body.sequence)
            guard response.body.interactiveSessionID.rawValue
                    == interactiveSessionID else {
                throw ClientSurfaceControlErrorV0.sessionMismatch
            }
            guard response.body.authorizationEpoch == authorizationEpoch else {
                throw ClientSurfaceControlErrorV0.authorizationChanged
            }
            guard clientMonotonicNowMilliseconds
                    <= Int64.max - response.body.validForMilliseconds else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let inventory = TargetInventory(
                revision: response.body.inventoryRevision,
                expiresAtMonotonicMilliseconds:
                    clientMonotonicNowMilliseconds
                        + response.body.validForMilliseconds,
                candidates: response.body.candidates
            )
            self.pendingTargetInventory = nil
            targetInventory = inventory
            targetCandidates = inventory.candidates
            return inventory.candidates
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func beginSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: WireUUID?,
        resetMessageID: WireUUID,
        requestMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        clientMonotonicMilliseconds: UInt64
    ) throws -> ClientSurfaceSelectionRequestV0 {
        do {
            try requirePhase(.active)
            guard pendingTargetInventory == nil else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            if targetKind == .focusedRegion {
                guard clientMonotonicMilliseconds <= UInt64(Int64.max),
                      let targetToken,
                      let focusEvent = latestFocusEvent,
                      focusEvent.recommendedTargetKind == .focusedRegion,
                      focusEvent.targetToken == targetToken else {
                    throw ClientSurfaceControlErrorV0
                        .targetInventoryRequired
                }
                guard Int64(clientMonotonicMilliseconds)
                        < focusEvent.expiresAtMonotonicMilliseconds else {
                    throw ClientSurfaceControlErrorV0.focusEventExpired
                }
            } else if targetKind != .desktop {
                guard clientMonotonicMilliseconds <= UInt64(Int64.max),
                      let targetToken, let targetInventory else {
                    throw ClientSurfaceControlErrorV0
                        .targetInventoryRequired
                }
                guard Int64(clientMonotonicMilliseconds)
                        < targetInventory.expiresAtMonotonicMilliseconds,
                      targetInventory.candidates.contains(where: {
                          $0.targetToken == targetToken
                              && $0.kind == targetKind
                              && $0.currentWindowAvailable
                      }) else {
                    throw ClientSurfaceControlErrorV0.targetUnavailable
                }
            }
            let sequence = try consumeClientSequenceCandidate()
            let body = try InteractiveSurfaceSelectBodyV0(
                interactiveSessionID: WireUUID(interactiveSessionID),
                authorizationEpoch: authorizationEpoch,
                currentSurfaceID: WireUUID(currentDescriptor.surfaceID),
                expectedSurfaceRevision: currentDescriptor.surfaceRevision,
                expectedCoordinateSpaceRevision:
                    currentDescriptor.coordinateSpaceRevision,
                targetKind: targetKind,
                targetToken: targetToken,
                sequence: sequence
            )
            let envelope = try WireEnvelope(
                messageID: requestMessageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            )
            let requestJSON = try WireCodec.encode(envelope)
            let reset = try input.pauseAndReset(
                messageID: resetMessageID,
                clientMonotonicMilliseconds: clientMonotonicMilliseconds
            )
            let requestedFocus = targetKind == .focusedRegion
                ? latestFocusEvent?.focus : nil
            nextClientSequence = sequence + 1
            targetInventory = nil
            targetCandidates = []
            latestFocusEvent = nil
            inputPausedByFocusEvent = false
            pendingSelection = PendingSelection(
                requestMessageID: requestMessageID,
                requestedKind: targetKind,
                requestedFocus: requestedFocus
            )
            phase = .awaitingSelection
            return ClientSurfaceSelectionRequestV0(
                reset: reset,
                requestJSON: requestJSON
            )
        } catch {
            failClosed()
            throw error
        }
    }

    @discardableResult
    public mutating func receiveSelected(
        _ responseJSON: Data,
        clientMonotonicNowMilliseconds: Int64
    ) throws -> AdaptiveSurfaceDescriptor {
        do {
            try requirePhase(.awaitingSelection)
            guard let pendingSelection else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .interactiveSurfaceSelected else {
                throw ClientSurfaceControlErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == pendingSelection.requestMessageID else {
                throw ClientSurfaceControlErrorV0.correlationMismatch
            }
            try admitServerSequence(response.body.sequence)
            let descriptor = try response.body.descriptor.materialize(
                clientMonotonicNowMilliseconds:
                    clientMonotonicNowMilliseconds
            )
            guard descriptor.interactiveSessionID == interactiveSessionID else {
                throw ClientSurfaceControlErrorV0.sessionMismatch
            }
            guard descriptor.authorizationEpoch == authorizationEpoch else {
                throw ClientSurfaceControlErrorV0.authorizationChanged
            }
            let expectedSurfaceRevision = try
                currentDescriptor.surfaceRevision.advanced()
            let expectedCoordinateRevision = try
                currentDescriptor.coordinateSpaceRevision.advanced()
            guard descriptor.kind == pendingSelection.requestedKind,
                  descriptor.focus == pendingSelection.requestedFocus,
                  descriptor.surfaceRevision == expectedSurfaceRevision,
                  descriptor.coordinateSpaceRevision
                    == expectedCoordinateRevision,
                  Set(descriptor.interactionClasses)
                    .isSubset(of: sessionAllowedInteractionClasses) else {
                throw ClientSurfaceControlErrorV0.descriptorMismatch
            }
            guard media.lastMediaSequence <= UInt64(WireLimits.maximumSafeInteger),
                  response.body.mediaSequenceBeforeTransition
                    == Int64(media.lastMediaSequence) else {
                throw ClientSurfaceControlErrorV0.mediaBoundaryMismatch
            }
            try media.beginSurfaceTransition(to: descriptor)
            renderedReadyMediaSequence = nil
            self.pendingSelection = nil
            pendingTransition = PendingTransition(
                transitionID: response.body.transitionID,
                descriptor: descriptor
            )
            phase = .awaitingMedia
            return descriptor
        } catch {
            failClosed()
            throw error
        }
    }

    @discardableResult
    public mutating func admitMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) throws -> ClientMediaAdmissionV0 {
        do {
            guard phase == .active
                    || phase == .awaitingMedia
                    || phase == .awaitingAcknowledgement else {
                throw ClientSurfaceControlErrorV0.invalidPhase(phase)
            }
            return try media.admit(
                header: header,
                payloadByteCount: payloadByteCount
            )
        } catch {
            failClosed()
            throw error
        }
    }

    /// Records concrete render proof for the exact clean replacement frame.
    /// Decoder admission alone never authorizes an acknowledgement.
    @discardableResult
    public mutating func confirmRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) throws -> Bool {
        do {
            try requirePhase(.awaitingMedia)
            guard let pendingTransition,
                  receipt.fence.interactiveSessionID
                    == pendingTransition.descriptor.interactiveSessionID,
                  receipt.fence.authorizationEpoch
                    == pendingTransition.descriptor.authorizationEpoch,
                  receipt.fence.surfaceID
                    == pendingTransition.descriptor.surfaceID,
                  receipt.fence.surfaceRevision
                    == pendingTransition.descriptor.surfaceRevision,
                  receipt.fence.coordinateSpaceRevision
                    == pendingTransition.descriptor.coordinateSpaceRevision,
                  receipt.fence.encodedWidth
                    == pendingTransition.descriptor.encodedWidth,
                  receipt.fence.encodedHeight
                    == pendingTransition.descriptor.encodedHeight,
                  let required = media.pendingAcknowledgementMediaSequence else {
                throw ClientSurfaceControlErrorV0.mediaBoundaryMismatch
            }
            guard receipt.mediaSequence == required else {
                if receipt.mediaSequence > required { return false }
                throw ClientSurfaceControlErrorV0.mediaBoundaryMismatch
            }
            renderedReadyMediaSequence = receipt.mediaSequence
            return true
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func makeAcknowledgement(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        do {
            try requirePhase(.awaitingMedia)
            guard let pendingTransition else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let acknowledgement = try media.takeAcknowledgementFence()
            let fence = acknowledgement.surface
            guard renderedReadyMediaSequence
                    == acknowledgement.readyMediaSequence,
                  acknowledgement.readyMediaSequence > 0,
                  acknowledgement.readyMediaSequence
                    <= UInt64(WireLimits.maximumSafeInteger) else {
                throw ClientSurfaceControlErrorV0.mediaBoundaryMismatch
            }
            let sequence = try consumeClientSequenceCandidate()
            let body = try InteractiveSurfaceAcknowledgementBodyV0(
                interactiveSessionID: WireUUID(fence.interactiveSessionID),
                authorizationEpoch: fence.authorizationEpoch,
                transitionID: pendingTransition.transitionID,
                surfaceID: WireUUID(fence.surfaceID),
                surfaceRevision: fence.surfaceRevision,
                coordinateSpaceRevision: fence.coordinateSpaceRevision,
                focusToken: fence.focusToken.map(WireUUID.init),
                focusRevision: fence.focusRevision,
                readyMediaSequence:
                    Int64(acknowledgement.readyMediaSequence),
                sequence: sequence
            )
            let data = try WireCodec.encode(WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            ))
            nextClientSequence = sequence + 1
            pendingAcknowledgement = PendingAcknowledgement(
                requestMessageID: messageID,
                body: body,
                descriptor: pendingTransition.descriptor
            )
            self.pendingTransition = nil
            renderedReadyMediaSequence = nil
            phase = .awaitingAcknowledgement
            return data
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func receiveAcknowledged(_ responseJSON: Data) throws {
        do {
            try requirePhase(.awaitingAcknowledgement)
            guard let pendingAcknowledgement else {
                throw ClientSurfaceControlErrorV0.invalidConfiguration
            }
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .interactiveSurfaceAcknowledged else {
                throw ClientSurfaceControlErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceAcknowledgedBodyV0>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID
                    == pendingAcknowledgement.requestMessageID else {
                throw ClientSurfaceControlErrorV0.correlationMismatch
            }
            try admitServerSequence(response.body.sequence)
            try response.body.validate(
                against: pendingAcknowledgement.body
            )
            try input.activate(
                acknowledged: pendingAcknowledgement.descriptor
            )
            currentDescriptor = pendingAcknowledgement.descriptor
            self.pendingAcknowledgement = nil
            phase = .active
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func makeInput(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64,
        payload: InteractiveInputPayload
    ) throws -> InteractiveInputEnvelope {
        guard !inputPausedByFocusEvent else {
            throw ClientSurfaceControlErrorV0.inputPausedByFocusEvent
        }
        do {
            try requirePhase(.active)
            return try input.makeInput(
                messageID: messageID,
                clientMonotonicMilliseconds: clientMonotonicMilliseconds,
                payload: payload
            )
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func closeInput(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64
    ) throws -> InteractiveInputEnvelope? {
        defer { failClosed() }
        return try input.closeAndReset(
            messageID: messageID,
            clientMonotonicMilliseconds: clientMonotonicMilliseconds
        )
    }

    private func consumeClientSequenceCandidate() throws -> Int64 {
        guard nextClientSequence >= 1,
              nextClientSequence <= WireLimits.maximumSafeInteger else {
            throw ClientSurfaceControlErrorV0.sequenceExhausted
        }
        return nextClientSequence
    }

    private mutating func admitServerSequence(_ actual: Int64) throws {
        guard actual == expectedServerSequence else {
            throw ClientSurfaceControlErrorV0.sequenceMismatch(
                expected: expectedServerSequence,
                actual: actual
            )
        }
        guard expectedServerSequence <= WireLimits.maximumSafeInteger else {
            throw ClientSurfaceControlErrorV0.sequenceExhausted
        }
        expectedServerSequence += 1
    }

    private mutating func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientSurfaceControlErrorV0.duplicateMessage
        }
    }

    private func requirePhase(_ expected: ClientSurfaceControlPhaseV0) throws {
        guard phase == expected else {
            throw ClientSurfaceControlErrorV0.invalidPhase(phase)
        }
    }

    private mutating func failClosed() {
        phase = .closed
        pendingSelection = nil
        pendingTargetInventory = nil
        targetInventory = nil
        targetCandidates = []
        latestFocusEvent = nil
        inputPausedByFocusEvent = false
        pendingTransition = nil
        pendingAcknowledgement = nil
        renderedReadyMediaSequence = nil
        media.close()
    }
}
