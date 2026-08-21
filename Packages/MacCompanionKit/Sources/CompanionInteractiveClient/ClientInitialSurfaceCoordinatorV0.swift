import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTransport
import CompanionWire
import Foundation

public enum ClientInitialSurfacePhaseV0: String, Equatable, Sendable {
    case awaitingRequest
    case awaitingDescriptor
    case awaitingMedia
    case awaitingAcknowledgement
    case active
    case closed
}

public enum ClientInitialSurfaceErrorV0: Error, Equatable, Sendable {
    case invalidPhase(ClientInitialSurfacePhaseV0)
    case correlationMismatch
    case sequenceMismatch(expected: Int64, actual: Int64)
    case sessionMismatch
    case authorizationChanged
    case descriptorMismatch
    case mediaBoundaryMismatch
    case renderedFrameMismatch
    case duplicateMessage
    case unexpectedMessage(WireMessageKind)
}

/// Owns first-Desktop activation from the accepted session through a locally
/// materialized descriptor, clean media, exact acknowledgement, and input
/// activation. It hands replacement control the same per-direction sequences.
public struct ClientInitialSurfaceCoordinatorV0: Sendable {
    private struct PendingAcknowledgement: Sendable {
        let requestMessageID: WireUUID
        let body: InteractiveInitialSurfaceAcknowledgementBodyV0
    }

    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    public private(set) var phase: ClientInitialSurfacePhaseV0 = .awaitingRequest
    public private(set) var descriptor: AdaptiveSurfaceDescriptor?
    public private(set) var media: ClientMediaStreamAuthorityV0?
    public private(set) var input: ClientInputProducerV0

    private var descriptorRequestID: WireUUID?
    private var activationID: WireUUID?
    private var pendingAcknowledgement: PendingAcknowledgement?
    private var renderedReadyMediaSequence: UInt64?
    private var replay = ConnectionReplayWindow()

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              sessionAllowedInteractionClasses.contains(.view) else {
            throw ClientInitialSurfaceErrorV0.descriptorMismatch
        }
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.sessionAllowedInteractionClasses = sessionAllowedInteractionClasses
        input = try ClientInputProducerV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch
        )
    }

    public mutating func makeDescriptorRequest(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        do {
            try require(.awaitingRequest)
            let body = try InteractiveInitialSurfaceRequestBodyV0(
                interactiveSessionID: WireUUID(interactiveSessionID),
                authorizationEpoch: authorizationEpoch,
                sequence: 1
            )
            let data = try WireCodec.encode(WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            ))
            descriptorRequestID = messageID
            phase = .awaitingDescriptor
            return data
        } catch {
            failClosed()
            throw error
        }
    }

    @discardableResult
    public mutating func receiveDescriptor(
        _ responseJSON: Data,
        clientMonotonicNowMilliseconds: Int64
    ) throws -> AdaptiveSurfaceDescriptor {
        do {
            try require(.awaitingDescriptor)
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .interactiveInitialSurfaceDescriptor else {
                throw ClientInitialSurfaceErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveInitialSurfaceDescriptorBodyV0>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == descriptorRequestID else {
                throw ClientInitialSurfaceErrorV0.correlationMismatch
            }
            guard response.body.sequence == 1 else {
                throw ClientInitialSurfaceErrorV0.sequenceMismatch(
                    expected: 1,
                    actual: response.body.sequence
                )
            }
            guard response.body.mediaSequenceBeforeActivation == 0 else {
                throw ClientInitialSurfaceErrorV0.mediaBoundaryMismatch
            }
            let descriptor = try response.body.descriptor.materialize(
                clientMonotonicNowMilliseconds:
                    clientMonotonicNowMilliseconds
            )
            guard descriptor.interactiveSessionID == interactiveSessionID else {
                throw ClientInitialSurfaceErrorV0.sessionMismatch
            }
            guard descriptor.authorizationEpoch == authorizationEpoch else {
                throw ClientInitialSurfaceErrorV0.authorizationChanged
            }
            guard descriptor.kind == .desktop,
                  descriptor.surfaceRevision.rawValue == 1,
                  descriptor.coordinateSpaceRevision.rawValue == 1,
                  Set(descriptor.interactionClasses)
                    .isSubset(of: sessionAllowedInteractionClasses) else {
                throw ClientInitialSurfaceErrorV0.descriptorMismatch
            }
            self.descriptor = descriptor
            activationID = response.body.activationID
            media = try ClientMediaStreamAuthorityV0(
                initialDescriptor: descriptor
            )
            renderedReadyMediaSequence = nil
            descriptorRequestID = nil
            phase = .awaitingMedia
            return descriptor
        } catch {
            failClosed()
            throw error
        }
    }

    /// Invoke only after the current decoder callback passes authority
    /// admission and the concrete renderer accepts the frame.
    @discardableResult
    public mutating func confirmRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) throws -> Bool {
        do {
            guard phase == .awaitingMedia,
                  let descriptor,
                  let authority = media,
                  receipt.fence.interactiveSessionID
                    == descriptor.interactiveSessionID,
                  receipt.fence.authorizationEpoch
                    == descriptor.authorizationEpoch,
                  receipt.fence.surfaceID == descriptor.surfaceID,
                  receipt.fence.surfaceRevision
                    == descriptor.surfaceRevision,
                  receipt.fence.coordinateSpaceRevision
                    == descriptor.coordinateSpaceRevision,
                  receipt.fence.encodedWidth == descriptor.encodedWidth,
                  receipt.fence.encodedHeight == descriptor.encodedHeight else {
                throw ClientInitialSurfaceErrorV0.renderedFrameMismatch
            }
            guard let required =
                    authority.pendingAcknowledgementMediaSequence else {
                throw ClientInitialSurfaceErrorV0.renderedFrameMismatch
            }
            guard receipt.mediaSequence == required else {
                if receipt.mediaSequence > required { return false }
                throw ClientInitialSurfaceErrorV0.renderedFrameMismatch
            }
            renderedReadyMediaSequence = receipt.mediaSequence
            return true
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
            guard (phase == .awaitingMedia
                    || phase == .awaitingAcknowledgement),
                  var authority = media else {
                throw ClientInitialSurfaceErrorV0.invalidPhase(phase)
            }
            let result = try authority.admit(
                header: header,
                payloadByteCount: payloadByteCount
            )
            media = authority
            return result
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
            try require(.awaitingMedia)
            guard var authority = media,
                  let activationID else {
                throw ClientInitialSurfaceErrorV0.descriptorMismatch
            }
            let acknowledgement = try authority.takeAcknowledgementFence()
            let fence = acknowledgement.surface
            guard renderedReadyMediaSequence
                    == acknowledgement.readyMediaSequence,
                  acknowledgement.readyMediaSequence > 0,
                  acknowledgement.readyMediaSequence
                    <= UInt64(WireLimits.maximumSafeInteger) else {
                throw ClientInitialSurfaceErrorV0.mediaBoundaryMismatch
            }
            media = authority
            let body = try InteractiveInitialSurfaceAcknowledgementBodyV0(
                interactiveSessionID: WireUUID(fence.interactiveSessionID),
                authorizationEpoch: fence.authorizationEpoch,
                activationID: activationID,
                surfaceID: WireUUID(fence.surfaceID),
                surfaceRevision: fence.surfaceRevision,
                coordinateSpaceRevision: fence.coordinateSpaceRevision,
                readyMediaSequence:
                    Int64(acknowledgement.readyMediaSequence),
                sequence: 2
            )
            let data = try WireCodec.encode(WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            ))
            pendingAcknowledgement = PendingAcknowledgement(
                requestMessageID: messageID,
                body: body
            )
            phase = .awaitingAcknowledgement
            return data
        } catch {
            failClosed()
            throw error
        }
    }

    public mutating func receiveAcknowledged(_ responseJSON: Data) throws {
        do {
            try require(.awaitingAcknowledgement)
            guard let pendingAcknowledgement,
                  let descriptor else {
                throw ClientInitialSurfaceErrorV0.descriptorMismatch
            }
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .interactiveInitialSurfaceAcknowledged else {
                throw ClientInitialSurfaceErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveInitialSurfaceAcknowledgedBodyV0>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID
                    == pendingAcknowledgement.requestMessageID else {
                throw ClientInitialSurfaceErrorV0.correlationMismatch
            }
            guard response.body.sequence == 2 else {
                throw ClientInitialSurfaceErrorV0.sequenceMismatch(
                    expected: 2,
                    actual: response.body.sequence
                )
            }
            try response.body.validate(against: pendingAcknowledgement.body)
            try input.activate(acknowledged: descriptor)
            self.pendingAcknowledgement = nil
            phase = .active
        } catch {
            failClosed()
            throw error
        }
    }

    public func replacementCoordinator() throws
        -> ClientSurfaceControlCoordinatorV0
    {
        guard phase == .active,
              let descriptor,
              let media else {
            throw ClientInitialSurfaceErrorV0.invalidPhase(phase)
        }
        return try ClientSurfaceControlCoordinatorV0(
            acknowledgedDescriptor: descriptor,
            sessionAllowedInteractionClasses:
                sessionAllowedInteractionClasses,
            media: media,
            input: input,
            initialNextClientSequence: 3,
            initialExpectedServerSequence: 3
        )
    }

    public mutating func makeInput(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64,
        payload: InteractiveInputPayload
    ) throws -> InteractiveInputEnvelope {
        do {
            try require(.active)
            return try input.makeInput(
                messageID: messageID,
                clientMonotonicMilliseconds:
                    clientMonotonicMilliseconds,
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

    private func require(_ expected: ClientInitialSurfacePhaseV0) throws {
        guard phase == expected else {
            throw ClientInitialSurfaceErrorV0.invalidPhase(phase)
        }
    }

    private mutating func admitReplay(_ messageID: WireUUID) throws {
        do { try replay.admit(messageID) }
        catch TransportGuardError.duplicateMessage {
            throw ClientInitialSurfaceErrorV0.duplicateMessage
        }
    }

    private mutating func failClosed() {
        phase = .closed
        descriptorRequestID = nil
        activationID = nil
        pendingAcknowledgement = nil
        renderedReadyMediaSequence = nil
        media?.close()
    }
}
