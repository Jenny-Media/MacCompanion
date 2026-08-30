@testable import CompanionClientPlatform
import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

@Test func automaticFocusIntentIgnoresAuthorityRefreshMetadata()
    throws
{
    let first = try automaticFocusEventV0(
        messageID: UUID(),
        sequence: 7,
        expiry: 1_000
    )
    let refresh = try automaticFocusEventV0(
        messageID: UUID(),
        sequence: 8,
        expiry: 1_500
    )

    #expect(
        UIKitClientAutomaticFocusIntentV0(first)
            == UIKitClientAutomaticFocusIntentV0(refresh)
    )
}

@Test func automaticFocusIntentChangesWithTarget() throws {
    let desktop = try automaticFocusEventV0(
        messageID: UUID(),
        sequence: 7,
        expiry: 1_000
    )
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 1_000,
            y: 2_000,
            width: 20_000,
            height: 5_000
        ),
        editable: true,
        secure: false
    )
    let focused = ClientSurfaceFocusEventV0(
        messageID: WireUUID(UUID()),
        eventSequence: 8,
        recommendedTargetKind: .focusedRegion,
        targetToken: WireUUID(UUID()),
        focus: focus,
        inputPaused: true,
        reason: .verifiedFocus,
        expiresAtMonotonicMilliseconds: 1_500
    )

    #expect(
        UIKitClientAutomaticFocusIntentV0(desktop)
            != UIKitClientAutomaticFocusIntentV0(focused)
    )
}

@Test func focusedIntentIgnoresRotatedFocusAuthority() throws {
    let firstFocus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 1_000,
            y: 2_000,
            width: 20_000,
            height: 5_000
        ),
        editable: false,
        secure: false
    )
    let refreshedFocus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 9),
        category: firstFocus.category,
        bounds: firstFocus.bounds,
        editable: true,
        secure: true
    )
    let first = ClientSurfaceFocusEventV0(
        messageID: WireUUID(UUID()),
        eventSequence: 7,
        recommendedTargetKind: .focusedRegion,
        targetToken: WireUUID(firstFocus.token),
        focus: firstFocus,
        inputPaused: false,
        reason: .verifiedFocus,
        expiresAtMonotonicMilliseconds: 1_000
    )
    let refresh = ClientSurfaceFocusEventV0(
        messageID: WireUUID(UUID()),
        eventSequence: 8,
        recommendedTargetKind: .focusedRegion,
        targetToken: WireUUID(refreshedFocus.token),
        focus: refreshedFocus,
        inputPaused: false,
        reason: .verifiedFocus,
        expiresAtMonotonicMilliseconds: 1_500
    )

    #expect(
        UIKitClientAutomaticFocusIntentV0(first)
            == UIKitClientAutomaticFocusIntentV0(refresh)
    )
}

@Test func focusPresentationIdentityIgnoresRotatedAuthorityToken()
    throws
{
    let first = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 1_000,
            y: 2_000,
            width: 20_000,
            height: 5_000
        ),
        editable: true,
        secure: false
    )
    let refresh = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 9),
        category: first.category,
        bounds: first.bounds,
        editable: !first.editable,
        secure: !first.secure
    )

    #expect(
        UIKitClientFocusPresentationIdentityV0(first)
            == UIKitClientFocusPresentationIdentityV0(refresh)
    )
}

@Test func manualViewportChangeSuppressesAutomaticZoomForTheSession() {
    var policy = UIKitClientAutomaticZoomSessionPolicyV0()

    #expect(policy.presentsAutomatically)
    policy.userChangedViewport()
    #expect(!policy.presentsAutomatically)
    #expect(policy.manuallyOverridden)
    #expect(!policy.admitsFocusEvent(inputPaused: false))
    #expect(policy.admitsFocusEvent(inputPaused: true))

    policy.resume()
    #expect(policy.presentsAutomatically)
    #expect(!policy.manuallyOverridden)
}

@Test func preferenceToggleExplicitlyResetsManualZoomOwnership() {
    var policy = UIKitClientAutomaticZoomSessionPolicyV0()
    policy.userChangedViewport()

    policy.setPreferenceEnabled(false)
    #expect(!policy.presentsAutomatically)
    #expect(!policy.manuallyOverridden)

    policy.setPreferenceEnabled(true)
    #expect(policy.presentsAutomatically)
}

private func automaticFocusEventV0(
    messageID: UUID,
    sequence: Int64,
    expiry: Int64
) throws -> ClientSurfaceFocusEventV0 {
    ClientSurfaceFocusEventV0(
        messageID: WireUUID(messageID),
        eventSequence: sequence,
        recommendedTargetKind: .desktop,
        targetToken: nil,
        focus: nil,
        inputPaused: true,
        reason: .noVerifiedFocus,
        expiresAtMonotonicMilliseconds: expiry
    )
}
