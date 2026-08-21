import CompanionClientUI
import CompanionDomain
import CompanionInteractiveShared
import CompanionPresentation
import Foundation
import Testing

private let clientUIHostID = UUID()
private let clientUIDisplayName = try! DeviceDisplayName("Studio Mac")

private func clientUISnapshot(
    connection: ConnectionPresentationState,
    session: InteractiveSessionState? = nil,
    classes: Set<SurfaceInteractionClass> = [],
    surface: InteractiveSurfaceKind? = nil
) throws -> InteractiveClientPresentationSnapshot {
    try .make(
        hostID: clientUIHostID,
        locallyConfirmedMacName: clientUIDisplayName,
        endpointKind: nil,
        connection: connection,
        sessionState: session,
        interactionClasses: classes,
        activeSurface: surface,
        recoveryCause: nil
    )
}

@Test func pairingProjectionStartsWithScanAndFailsClosed() throws {
    var presentation = PairingClientPresentation()
    #expect(ClientPairingSurfaceV0(presentation: presentation) == .scan)

    #expect(throws: PairingClientPresentationError.invalidOrExpiredQRCode) {
        try presentation.receiveScan(
            "not-a-mac-companion-code",
            nowUnixMilliseconds: 1
        )
    }
    #expect(ClientPairingSurfaceV0(presentation: presentation)
        == .failed(.invalidOrExpiredCode))
}

@Test func disconnectedHostOffersOnlyExplicitReconnect() throws {
    let projection = ClientHostSurfaceProjectionV0(snapshot: try clientUISnapshot(
        connection: .disconnectedByUser
    ))
    #expect(projection.displayName == "Studio Mac")
    #expect(projection.status == .disconnected)
    #expect(projection.primaryAction == .reconnect)
    #expect(projection.surface == nil)
}

@Test func connectedInactiveHostKeepsRemoteControlOptional() throws {
    let projection = ClientHostSurfaceProjectionV0(snapshot: try clientUISnapshot(
        connection: .connected,
        session: .idle
    ))
    #expect(projection.status == .ready)
    #expect(projection.primaryAction == .startInteractiveControl)
}

@Test func activeViewOnlySessionCannotBePresentedAsControl() throws {
    let projection = ClientHostSurfaceProjectionV0(snapshot: try clientUISnapshot(
        connection: .connected,
        session: .activeUnlocked,
        classes: [.view],
        surface: .desktop
    ))
    #expect(projection.status == .viewing)
    #expect(projection.primaryAction == .stopInteractiveControl)
    #expect(projection.surface == .desktop)
}

@Test func pointerSessionIsPresentedAsControlling() throws {
    let projection = ClientHostSurfaceProjectionV0(snapshot: try clientUISnapshot(
        connection: .connected,
        session: .activeUnlocked,
        classes: [.view, .pointer],
        surface: .window
    ))
    #expect(projection.status == .controlling)
    #expect(projection.primaryAction == .stopInteractiveControl)
    #expect(projection.surface == .window)
}

@Test func lockedUnavailableSessionHidesSurfaceAndKeepsStop() throws {
    let projection = ClientHostSurfaceProjectionV0(snapshot: try clientUISnapshot(
        connection: .connected,
        session: .lockedInteractionUnavailable,
        classes: [.view, .pointer],
        surface: .desktop
    ))
    #expect(projection.status == .paused(.lockedInteractionUnavailable))
    #expect(projection.primaryAction == .stopInteractiveControl)
    #expect(projection.surface == nil)
}
