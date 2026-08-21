import CompanionDomain
import Testing

@Test func pairingAlwaysStartsMonitorOnly() throws {
    let pending = try DeviceAuthorization().applying(.startPairing)
    let active = try pending.applying(.commitMonitorOnlyPairing)

    #expect(active.state == .activeMonitorOnly)
    #expect(active.authorizationEpoch.rawValue == 1)
    #expect(active.grantRevision.rawValue == 1)
    #expect(active.state.canAuthenticate)
}

@Test func suspendAndResumeFenceOldAuthorization() throws {
    let paired = try DeviceAuthorization()
        .applying(.startPairing)
        .applying(.commitMonitorOnlyPairing)
        .applying(.expandGrant)
    let suspended = try paired.applying(.suspend)
    let resumed = try suspended.applying(.resumeGranted)

    #expect(!suspended.state.canAuthenticate)
    #expect(suspended.authorizationEpoch > paired.authorizationEpoch)
    #expect(resumed.authorizationEpoch > suspended.authorizationEpoch)
    #expect(resumed.grantRevision > paired.grantRevision)
}

@Test func revokedIdentityCannotReactivate() throws {
    let revoked = try DeviceAuthorization()
        .applying(.startPairing)
        .applying(.commitMonitorOnlyPairing)
        .applying(.revoke)

    #expect(throws: InvalidDeviceAuthorizationTransition.self) {
        try revoked.applying(.resumeMonitorOnly)
    }
}

@Test func revisionOverflowFailsClosed() {
    let revision = AuthorizationEpoch(rawValue: AuthorizationEpoch.maximumWireValue)
    #expect(throws: RevisionError.exhausted) {
        try revision.advanced()
    }
}
