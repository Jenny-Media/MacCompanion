import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

public enum ClientInputProducerPhaseV0: String, Equatable, Sendable {
    case paused
    case active
    case closed
}

public enum ClientInputProducerErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPhase(ClientInputProducerPhaseV0)
    case staleDescriptor
    case wrongSession
    case authorizationChanged
    case sequenceExhausted
    case clientTimeWentBackward
    case interactionClassDenied
    case textFocusDenied
    case repeatedButtonDown
    case unmatchedButtonUp
    case repeatedKeyDown
    case unmatchedKeyUp
}

/// Produces reliable input only from one acknowledged current descriptor.
/// Pointer coalescing happens before this authority is called; after sequence
/// assignment no event may be dropped or reordered by the socket adapter.
public struct ClientInputProducerV0: Sendable {
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public private(set) var phase: ClientInputProducerPhaseV0 = .paused
    public private(set) var lastSequence: UInt64 = 0
    public private(set) var lastClientMonotonicMilliseconds: UInt64 = 0
    public private(set) var pressedButtons: Set<InteractivePointerButton> = []
    public private(set) var pressedKeyboardUsages: Set<UInt16> = []
    public private(set) var modifierMask: InteractiveModifierMask = []

    private var descriptor: AdaptiveSurfaceDescriptor?
    private var lastSurfaceRevision: SurfaceRevision?
    private var lastCoordinateSpaceRevision: CoordinateSpaceRevision?

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch
    ) throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw ClientInputProducerErrorV0.invalidConfiguration
        }
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
    }

    public mutating func activate(
        acknowledged descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        guard phase == .paused else {
            throw ClientInputProducerErrorV0.invalidPhase(phase)
        }
        do {
            try descriptor.validate()
        } catch {
            throw ClientInputProducerErrorV0.staleDescriptor
        }
        guard descriptor.interactiveSessionID == interactiveSessionID else {
            throw ClientInputProducerErrorV0.wrongSession
        }
        guard descriptor.authorizationEpoch == authorizationEpoch else {
            throw ClientInputProducerErrorV0.authorizationChanged
        }
        if let lastSurfaceRevision, let lastCoordinateSpaceRevision {
            guard descriptor.surfaceRevision.rawValue
                    > lastSurfaceRevision.rawValue,
                  descriptor.coordinateSpaceRevision.rawValue
                    > lastCoordinateSpaceRevision.rawValue else {
                throw ClientInputProducerErrorV0.staleDescriptor
            }
        }
        self.descriptor = descriptor
        lastSurfaceRevision = descriptor.surfaceRevision
        lastCoordinateSpaceRevision = descriptor.coordinateSpaceRevision
        phase = .active
    }

    public mutating func makeInput(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64,
        payload: InteractiveInputPayload
    ) throws -> InteractiveInputEnvelope {
        guard phase == .active, let descriptor else {
            throw ClientInputProducerErrorV0.invalidPhase(phase)
        }
        guard lastSequence < UInt64(WireLimits.maximumSafeInteger) else {
            throw ClientInputProducerErrorV0.sequenceExhausted
        }
        guard lastSequence == 0
                || clientMonotonicMilliseconds
                    >= lastClientMonotonicMilliseconds else {
            throw ClientInputProducerErrorV0.clientTimeWentBackward
        }
        try authorize(payload, descriptor: descriptor)

        var nextButtons = pressedButtons
        var nextKeys = pressedKeyboardUsages
        var nextModifiers = modifierMask
        switch payload {
        case let .button(button, transition):
            switch transition {
            case .down:
                guard nextButtons.insert(button).inserted else {
                    throw ClientInputProducerErrorV0.repeatedButtonDown
                }
            case .up:
                guard nextButtons.remove(button) != nil else {
                    throw ClientInputProducerErrorV0.unmatchedButtonUp
                }
            }
        case let .physicalKey(usage, transition, modifiers):
            switch transition {
            case .down:
                guard nextKeys.insert(usage).inserted else {
                    throw ClientInputProducerErrorV0.repeatedKeyDown
                }
            case .up:
                guard nextKeys.remove(usage) != nil else {
                    throw ClientInputProducerErrorV0.unmatchedKeyUp
                }
            }
            nextModifiers = modifiers
        case let .modifiers(modifiers):
            nextModifiers = modifiers
        case .reset:
            nextButtons.removeAll(keepingCapacity: true)
            nextKeys.removeAll(keepingCapacity: true)
            nextModifiers = []
        case .pointerMove, .scroll, .text:
            break
        }

        let nextSequence = lastSequence + 1
        let focus = descriptor.focus
        let envelope = try InteractiveInputEnvelope(
            messageID: messageID,
            interactiveSessionID: WireUUID(interactiveSessionID),
            authorizationEpoch: authorizationEpoch,
            sequence: nextSequence,
            clientMonotonicMilliseconds: clientMonotonicMilliseconds,
            surfaceID: WireUUID(descriptor.surfaceID),
            surfaceRevision: descriptor.surfaceRevision,
            coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
            focusToken: focus.map { WireUUID($0.token) },
            focusRevision: focus?.revision,
            input: payload
        )
        lastSequence = nextSequence
        lastClientMonotonicMilliseconds = clientMonotonicMilliseconds
        pressedButtons = nextButtons
        pressedKeyboardUsages = nextKeys
        modifierMask = nextModifiers
        return envelope
    }

    /// Creates the final reliable reset under the old acknowledged fence and
    /// then pauses. The caller must send the returned envelope before allowing
    /// a new descriptor to become active.
    public mutating func pauseAndReset(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64
    ) throws -> InteractiveInputEnvelope? {
        guard phase != .closed else {
            throw ClientInputProducerErrorV0.invalidPhase(phase)
        }
        guard phase == .active else { return nil }
        let reset = try makeInput(
            messageID: messageID,
            clientMonotonicMilliseconds: clientMonotonicMilliseconds,
            payload: .reset
        )
        phase = .paused
        descriptor = nil
        return reset
    }

    public mutating func closeAndReset(
        messageID: WireUUID,
        clientMonotonicMilliseconds: UInt64
    ) throws -> InteractiveInputEnvelope? {
        guard phase != .closed else { return nil }
        let reset = try pauseAndReset(
            messageID: messageID,
            clientMonotonicMilliseconds: clientMonotonicMilliseconds
        )
        phase = .closed
        descriptor = nil
        pressedButtons.removeAll(keepingCapacity: true)
        pressedKeyboardUsages.removeAll(keepingCapacity: true)
        modifierMask = []
        return reset
    }

    package func isActive(
        on acknowledgedDescriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        phase == .active
            && descriptor == acknowledgedDescriptor
            && interactiveSessionID
                == acknowledgedDescriptor.interactiveSessionID
            && authorizationEpoch
                == acknowledgedDescriptor.authorizationEpoch
    }

    private func authorize(
        _ payload: InteractiveInputPayload,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        let required: SurfaceInteractionClass?
        switch payload {
        case .pointerMove, .button, .scroll:
            required = .pointer
        case .physicalKey, .modifiers:
            required = .keyboard
        case .text:
            required = .text
        case .reset:
            required = nil
        }
        if let required,
           !descriptor.interactionClasses.contains(required) {
            throw ClientInputProducerErrorV0.interactionClassDenied
        }
        if case .text = payload {
            guard descriptor.focus?.secure != true else {
                throw ClientInputProducerErrorV0.textFocusDenied
            }
        }
    }
}
