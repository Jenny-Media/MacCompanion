import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum InteractiveInputAdmissionError: Error, Equatable, Sendable {
    case sessionInactive
    case sessionExpired
    case wrongSession
    case authorizationChanged
    case secureTextFocusDenied
}

/// Composes independent authorities in fail-closed order. Platform input
/// injection occurs only after this value returns successfully.
public struct InteractiveInputAdmissionAuthority: Equatable, Sendable {
    public private(set) var stream = InteractiveInputStreamState()

    public init() {}

    public mutating func admit(
        _ envelope: InteractiveInputEnvelope,
        session: InteractiveSessionStateMachine,
        surfaces: AdaptiveSurfaceAuthority,
        hostMonotonicMilliseconds: UInt64
    ) throws {
        guard session.sessionID == envelope.interactiveSessionID.rawValue else {
            throw InteractiveInputAdmissionError.wrongSession
        }
        guard session.authorizationEpoch == envelope.authorizationEpoch else {
            throw InteractiveInputAdmissionError.authorizationChanged
        }
        guard hostMonotonicMilliseconds <= UInt64(Int64.max) else {
            throw InteractiveInputAdmissionError.sessionExpired
        }
        guard let sessionDeadline = session.sessionDeadlineMonotonicMilliseconds,
              Int64(hostMonotonicMilliseconds) < sessionDeadline else {
            throw InteractiveInputAdmissionError.sessionExpired
        }
        switch envelope.input.kind {
        case .text:
            guard session.admitsTextInput else {
                throw InteractiveInputAdmissionError.sessionInactive
            }
        default:
            guard session.admitsPointerAndPhysicalKeyInput else {
                throw InteractiveInputAdmissionError.sessionInactive
            }
        }
        let fence = SurfaceInputFence(
            interactiveSessionID: envelope.interactiveSessionID.rawValue,
            authorizationEpoch: envelope.authorizationEpoch,
            surfaceID: envelope.surfaceID.rawValue,
            surfaceRevision: envelope.surfaceRevision,
            coordinateSpaceRevision: envelope.coordinateSpaceRevision,
            focusToken: envelope.focusToken?.rawValue,
            focusRevision: envelope.focusRevision
        )
        if envelope.input.kind == .text,
           case let .active(descriptor) = surfaces.phase,
           descriptor.focus?.secure == true {
            throw InteractiveInputAdmissionError.secureTextFocusDenied
        }
        try surfaces.validateInput(
            fence,
            requiresFocusBinding: false,
            monotonicNowMilliseconds: Int64(hostMonotonicMilliseconds)
        )
        try stream.admit(
            envelope,
            hostUnlocked: session.state == .activeUnlocked,
            hostMonotonicMilliseconds: hostMonotonicMilliseconds
        )
    }

    public mutating func releaseAll() {
        stream.releaseAll()
    }
}
