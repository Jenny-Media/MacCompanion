import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire

/// The host refreshes short-lived focus authority before it expires. Those
/// refreshes carry new message/sequence/expiry values, but they do not
/// necessarily describe a new visual transition. Keep the original debounce
/// deadline for one unchanged target so a refresh interval shorter than the
/// presentation delay cannot postpone the transition forever.
package struct UIKitClientAutomaticFocusIntentV0: Equatable, Sendable {
    package let recommendedTargetKind: InteractiveSurfaceKind
    package let targetToken: WireUUID?
    package let focus: SurfaceFocus?

    package init(_ event: ClientSurfaceFocusEventV0) {
        recommendedTargetKind = event.recommendedTargetKind
        targetToken = event.targetToken
        focus = event.focus
    }
}

/// Stable visual identity for one focus target. Host authority tokens and
/// revisions may rotate while the same control remains focused; those refresh
/// details must not undo a user's explicit Fit Screen or pinch-out choice.
package struct UIKitClientFocusPresentationIdentityV0:
    Equatable,
    Sendable
{
    package let category: FocusElementCategory
    package let bounds: NormalizedSurfaceRect
    package let editable: Bool
    package let secure: Bool

    package init(_ focus: SurfaceFocus) {
        category = focus.category
        bounds = focus.bounds
        editable = focus.editable
        secure = focus.secure
    }
}

/// Session-scoped presentation ownership. Smart Zoom may suggest an initial
/// viewport, but the first explicit viewport gesture transfers control to the
/// user until they deliberately resume automation or start a new session.
package struct UIKitClientAutomaticZoomSessionPolicyV0:
    Equatable,
    Sendable
{
    package private(set) var preferenceEnabled = true
    package private(set) var manuallyOverridden = false

    package var presentsAutomatically: Bool {
        preferenceEnabled && !manuallyOverridden
    }

    package mutating func setPreferenceEnabled(_ enabled: Bool) {
        preferenceEnabled = enabled
        manuallyOverridden = false
    }

    package mutating func userChangedViewport() {
        guard preferenceEnabled else { return }
        manuallyOverridden = true
    }

    package mutating func resume() {
        preferenceEnabled = true
        manuallyOverridden = false
    }

    package func admitsFocusEvent(inputPaused: Bool) -> Bool {
        presentsAutomatically || inputPaused
    }
}
