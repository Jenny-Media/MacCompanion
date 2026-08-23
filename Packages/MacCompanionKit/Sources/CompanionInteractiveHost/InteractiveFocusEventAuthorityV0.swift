import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

public enum InteractiveFocusEventAuthorityErrorV0:
    Error, Equatable, Sendable
{
    case invalidConfiguration
    case invalidCandidate
    case sequenceExhausted
    case fenceMismatch
    case unavailable
    case expired
    case tokenMismatch
}

/// Privacy-filtered menu-process observation after all Accessibility values,
/// labels, roles, and OS identities have already been discarded.
public struct InteractiveFocusEventCandidateV0: Equatable, Sendable {
    public let recommendedTargetKind: InteractiveSurfaceKind
    public let focus: SurfaceFocus?
    public let inputPaused: Bool
    public let reason: InteractiveFocusEventReasonV0
    public let validForMilliseconds: Int64

    public init(
        recommendedTargetKind: InteractiveSurfaceKind,
        focus: SurfaceFocus?,
        inputPaused: Bool,
        reason: InteractiveFocusEventReasonV0,
        validForMilliseconds: Int64 = 1_000
    ) throws {
        guard (1...InteractiveSurfaceFocusChangedBodyV0
                .maximumValidityMilliseconds).contains(
                    validForMilliseconds
                ) else {
            throw InteractiveFocusEventAuthorityErrorV0.invalidCandidate
        }
        switch recommendedTargetKind {
        case .focusedRegion:
            guard focus != nil, reason == .verifiedFocus else {
                throw InteractiveFocusEventAuthorityErrorV0.invalidCandidate
            }
        case .desktop:
            guard focus == nil, reason != .verifiedFocus else {
                throw InteractiveFocusEventAuthorityErrorV0.invalidCandidate
            }
        case .application, .window:
            throw InteractiveFocusEventAuthorityErrorV0.invalidCandidate
        }
        self.recommendedTargetKind = recommendedTargetKind
        self.focus = focus
        self.inputPaused = inputPaused
        self.reason = reason
        self.validForMilliseconds = validForMilliseconds
    }
}

public struct InteractivePreparedFocusEventV0: Equatable, Sendable {
    public let eventJSON: Data
    public let eventSequence: Int64
    public let targetToken: WireUUID?

    public init(
        eventJSON: Data,
        eventSequence: Int64,
        targetToken: WireUUID?
    ) {
        self.eventJSON = eventJSON
        self.eventSequence = eventSequence
        self.targetToken = targetToken
    }
}

/// Agent-side capability authority for one accepted Interactive session. It
/// knows no Accessibility object or capture source; it binds the sanitized
/// focus projection to one exact event and one ordinary surface selection.
public struct InteractiveFocusEventAuthorityV0: Sendable {
    public static let maximumEventsPerSession = 100_000

    private struct Binding: Sendable {
        let eventMessageID: WireUUID
        let eventSequence: Int64
        let targetToken: WireUUID
        let surfaceID: UUID
        let surfaceRevision: SurfaceRevision
        let coordinateSpaceRevision: CoordinateSpaceRevision
        let focus: SurfaceFocus
        let expiresAtMonotonicMilliseconds: Int64
    }

    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    private let targetIdentifier: @Sendable () -> UUID
    private var nextEventSequence: Int64 = 1
    private var current: Binding?
    private var issuedTargetTokens: Set<UUID> = []
    private var invalidated = false

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        targetIdentifier: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              authorizationEpoch.rawValue
                <= UInt64(WireLimits.maximumSafeInteger) else {
            throw InteractiveFocusEventAuthorityErrorV0
                .invalidConfiguration
        }
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.targetIdentifier = targetIdentifier
    }

    public mutating func prepare(
        candidate: InteractiveFocusEventCandidateV0,
        current descriptor: AdaptiveSurfaceDescriptor,
        eventMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        hostMonotonicNowMilliseconds: Int64
    ) throws -> InteractivePreparedFocusEventV0 {
        guard !invalidated,
              descriptor.interactiveSessionID == interactiveSessionID,
              descriptor.authorizationEpoch == authorizationEpoch,
              hostMonotonicNowMilliseconds >= 0,
              descriptor.createdAtMonotonicMilliseconds
                <= hostMonotonicNowMilliseconds,
              descriptor.expiresAtMonotonicMilliseconds
                > hostMonotonicNowMilliseconds else {
            throw InteractiveFocusEventAuthorityErrorV0.fenceMismatch
        }
        if descriptor.kind == .focusedRegion {
            guard candidate.inputPaused,
                  candidate.focus != descriptor.focus else {
                throw InteractiveFocusEventAuthorityErrorV0.fenceMismatch
            }
        }
        guard nextEventSequence >= 1,
              nextEventSequence <= WireLimits.maximumSafeInteger,
              issuedTargetTokens.count < Self.maximumEventsPerSession else {
            throw InteractiveFocusEventAuthorityErrorV0.sequenceExhausted
        }
        let targetToken: WireUUID?
        let nextBinding: Binding?
        if let focus = candidate.focus {
            let rawTargetToken = targetIdentifier()
            guard !issuedTargetTokens.contains(rawTargetToken),
                  rawTargetToken != focus.token else {
                throw InteractiveFocusEventAuthorityErrorV0
                    .invalidConfiguration
            }
            targetToken = WireUUID(rawTargetToken)
            guard hostMonotonicNowMilliseconds
                    <= Int64.max - candidate.validForMilliseconds else {
                throw InteractiveFocusEventAuthorityErrorV0
                    .invalidConfiguration
            }
            nextBinding = Binding(
                eventMessageID: eventMessageID,
                eventSequence: nextEventSequence,
                targetToken: WireUUID(rawTargetToken),
                surfaceID: descriptor.surfaceID,
                surfaceRevision: descriptor.surfaceRevision,
                coordinateSpaceRevision:
                    descriptor.coordinateSpaceRevision,
                focus: focus,
                expiresAtMonotonicMilliseconds:
                    hostMonotonicNowMilliseconds
                        + candidate.validForMilliseconds
            )
        } else {
            targetToken = nil
            nextBinding = nil
        }
        let body = try InteractiveSurfaceFocusChangedBodyV0(
            interactiveSessionID: WireUUID(interactiveSessionID),
            authorizationEpoch: authorizationEpoch,
            currentSurfaceID: WireUUID(descriptor.surfaceID),
            currentSurfaceRevision: descriptor.surfaceRevision,
            currentCoordinateSpaceRevision:
                descriptor.coordinateSpaceRevision,
            recommendedTargetKind: candidate.recommendedTargetKind,
            targetToken: targetToken,
            focus: candidate.focus.map(InteractiveSurfaceWireFocusV0.init),
            inputPaused: candidate.inputPaused,
            reason: candidate.reason,
            validForMilliseconds: candidate.validForMilliseconds,
            eventSequence: nextEventSequence
        )
        let envelope = try WireEnvelope(
            messageID: eventMessageID,
            correlationID: nil,
            channel: .events,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        )
        let eventJSON = try WireCodec.encode(envelope)
        let prepared = InteractivePreparedFocusEventV0(
            eventJSON: eventJSON,
            eventSequence: nextEventSequence,
            targetToken: targetToken
        )
        if let targetToken {
            issuedTargetTokens.insert(targetToken.rawValue)
        }
        current = nextBinding
        nextEventSequence += 1
        return prepared
    }

    /// Consumes only the latest event's one-use target. The returned focus is
    /// the exact projection that the resolver's descriptor must reproduce.
    public mutating func consume(
        _ request: InteractiveSurfaceSelectBodyV0,
        current descriptor: AdaptiveSurfaceDescriptor,
        hostMonotonicNowMilliseconds: Int64
    ) throws -> SurfaceFocus {
        guard !invalidated, let current else {
            throw InteractiveFocusEventAuthorityErrorV0.unavailable
        }
        guard request.targetKind == .focusedRegion,
              request.interactiveSessionID.rawValue == interactiveSessionID,
              request.authorizationEpoch == authorizationEpoch,
              descriptor.interactiveSessionID == interactiveSessionID,
              descriptor.authorizationEpoch == authorizationEpoch,
              request.currentSurfaceID.rawValue == current.surfaceID,
              request.expectedSurfaceRevision == current.surfaceRevision,
              request.expectedCoordinateSpaceRevision
                == current.coordinateSpaceRevision,
              descriptor.surfaceID == current.surfaceID,
              descriptor.surfaceRevision == current.surfaceRevision,
              descriptor.coordinateSpaceRevision
                == current.coordinateSpaceRevision else {
            throw InteractiveFocusEventAuthorityErrorV0.fenceMismatch
        }
        guard request.targetToken == current.targetToken else {
            throw InteractiveFocusEventAuthorityErrorV0.tokenMismatch
        }
        guard hostMonotonicNowMilliseconds >= 0,
              hostMonotonicNowMilliseconds
                < current.expiresAtMonotonicMilliseconds else {
            throw InteractiveFocusEventAuthorityErrorV0.expired
        }
        self.current = nil
        return current.focus
    }

    public mutating func revokeCurrent() { current = nil }

    public mutating func invalidate() {
        invalidated = true
        current = nil
        issuedTargetTokens.removeAll(keepingCapacity: false)
    }
}
