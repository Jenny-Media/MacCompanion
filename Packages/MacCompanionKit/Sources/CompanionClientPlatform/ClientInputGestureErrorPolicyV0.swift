import CompanionInteractiveClient

public enum ClientInputGestureErrorDispositionV0: Equatable, Sendable {
    case ignoreLocally
    case resetVisualZoomLocally
    case failClosed
}

public enum ClientInputSubmissionErrorDispositionV0: Equatable, Sendable {
    case ignoreLocally
    case failClosed
}

/// A verified focus event pauses input before its replacement surface is
/// acknowledged. Input already queued on the main actor can reach that pause;
/// the coordinator deliberately reports this without closing its authority.
/// Dropping that stale local input preserves the pause and lets the authenticated
/// Smart Zoom transition continue.
public enum ClientInputSubmissionErrorPolicyV0 {
    public static func disposition(
        for error: any Error
    ) -> ClientInputSubmissionErrorDispositionV0 {
        if let control = error as? ClientSurfaceControlErrorV0,
           control == .inputPausedByFocusEvent {
            return .ignoreLocally
        }
        return .failClosed
    }
}

/// Separates expected local no-ops from malformed or inconsistent gestures.
/// A letterbox miss or a sub-pixel scroll that rounds to zero produces no
/// remote input and must not tear down an otherwise healthy authenticated
/// Interactive session.
public enum ClientInputGestureErrorPolicyV0 {
    public static func disposition(
        for error: any Error
    ) -> ClientInputGestureErrorDispositionV0 {
        if error is ClientVisualZoomTransformErrorV0 {
            return .resetVisualZoomLocally
        }
        guard let mapping = error as? ClientViewportInputMapperErrorV0 else {
            return .failClosed
        }
        switch mapping {
        case .pointOutsideContent, .zeroScroll:
            return .ignoreLocally
        case .invalidGeometry, .invalidSensitivity, .nonFiniteInput,
             .modeMismatch, .dragAlreadyActive, .dragNotActive:
            return .failClosed
        }
    }
}
