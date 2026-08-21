import CompanionDiscovery
import CompanionDomain
import CompanionInteractiveShared
import CompanionPresentation
import Foundation
import Testing

private let presentationHostID = UUID(
    uuidString: "018f1000-0000-7000-8000-000000000001"
)!
private let presentationMacName = try! PairedMacDisplayName("Studio Mac")

private func presentation(
    connection: ConnectionPresentationState = .connected,
    session: InteractiveSessionState? = .activeUnlocked,
    classes: Set<SurfaceInteractionClass> = [.view, .pointer],
    surface: InteractiveSurfaceKind? = .desktop,
    recovery: InteractiveRecoveryPresentationCause? = nil
) throws -> InteractiveClientPresentationSnapshot {
    try .make(
        hostID: presentationHostID,
        locallyConfirmedMacName: presentationMacName,
        endpointKind: .bonjour,
        connection: connection,
        sessionState: session,
        interactionClasses: classes,
        activeSurface: surface,
        recoveryCause: recovery
    )
}

@Test func connectedInteractivePresentationIdentifiesMacRouteAndControl() throws {
    let value = try presentation()
    #expect(value.hostID == presentationHostID)
    #expect(value.macDisplayName == presentationMacName)
    #expect(value.route == .localDiscovery)
    #expect(value.mode == .controlling)
    #expect(value.hostLock == .unlocked)
    #expect(value.activeSurface == .desktop)
}

@Test func viewOnlyAndLockedControlRemainExplicitlyDifferent() throws {
    let viewOnly = try presentation(classes: [.view])
    #expect(viewOnly.mode == .viewing)
    #expect(viewOnly.hostLock == .unlocked)

    let locked = try presentation(
        session: .activeLocked,
        classes: [.view, .pointer]
    )
    #expect(locked.mode == .controlling)
    #expect(locked.hostLock == .lockedControlAvailable)
}

@Test func unavailableLockBlanksSurfaceAndCannotClaimControl() throws {
    let value = try presentation(
        session: .lockedInteractionUnavailable,
        surface: .desktop,
        recovery: .hostStateAmbiguous
    )
    #expect(value.mode == .paused)
    #expect(value.hostLock == .lockedInteractionUnavailable)
    #expect(value.activeSurface == nil)
    #expect(value.recoveryCause == .hostStateAmbiguous)
}

@Test func disconnectionOverridesRetainedActiveSessionAndSurface() throws {
    let value = try presentation(
        connection: .noNetwork,
        session: .activeUnlocked,
        surface: .window
    )
    #expect(value.mode == .unreachable)
    #expect(value.hostLock == .unknown)
    #expect(value.activeSurface == nil)
    #expect(value.recoveryCause == .noNetwork)
}

@Test func activePresentationRejectsImpossibleAuthorityClasses() throws {
    #expect(throws: InteractiveClientPresentationError.activeSessionMissingView) {
        try presentation(classes: [.pointer])
    }
    #expect(
        throws: InteractiveClientPresentationError
            .inconsistentInteractionClasses
    ) {
        try presentation(classes: [.view, .text])
    }
}

@Test func everySessionEndReasonHasAClosedPresentationCause() {
    #expect(Set(InteractiveSessionEndReason.allCases.map {
        InteractiveRecoveryPresentationCause(endReason: $0)
    }).count == InteractiveSessionEndReason.allCases.count)
}
