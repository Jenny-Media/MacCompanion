public enum DeviceAuthorizationState: String, Codable, CaseIterable, Sendable {
    case unpaired
    case pairingPending
    case activeMonitorOnly
    case activeGranted
    case suspended
    case revoked

    public var canAuthenticate: Bool {
        self == .activeMonitorOnly || self == .activeGranted
    }
}

public enum DeviceAuthorizationEvent: String, Codable, CaseIterable, Sendable {
    case startPairing
    case pairingFailed
    case commitMonitorOnlyPairing
    case expandGrant
    case replaceGrant
    case reduceToMonitorOnly
    case suspend
    case resumeMonitorOnly
    case resumeGranted
    case revoke
    case expireRevokedTombstone
}

public struct InvalidDeviceAuthorizationTransition: Error, Equatable, Sendable {
    public let state: DeviceAuthorizationState
    public let event: DeviceAuthorizationEvent

    public init(state: DeviceAuthorizationState, event: DeviceAuthorizationEvent) {
        self.state = state
        self.event = event
    }
}

public struct DeviceAuthorization: Codable, Equatable, Sendable {
    public let state: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision

    public init(
        state: DeviceAuthorizationState = .unpaired,
        authorizationEpoch: AuthorizationEpoch = .init(rawValue: 0),
        grantRevision: GrantRevision = .init(rawValue: 0)
    ) {
        self.state = state
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
    }

    public func applying(_ event: DeviceAuthorizationEvent) throws -> Self {
        switch (state, event) {
        case (.unpaired, .startPairing):
            return try replacing(state: .pairingPending)

        case (.pairingPending, .pairingFailed):
            return try replacing(state: .unpaired)

        case (.pairingPending, .commitMonitorOnlyPairing):
            return Self(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            )

        case (.activeMonitorOnly, .expandGrant):
            return try replacing(
                state: .activeGranted,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.activeGranted, .reduceToMonitorOnly):
            return try replacing(
                state: .activeMonitorOnly,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.activeGranted, .replaceGrant):
            return try replacing(
                state: .activeGranted,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.activeMonitorOnly, .suspend), (.activeGranted, .suspend):
            return try replacing(state: .suspended, advanceEpoch: true)

        case (.suspended, .resumeMonitorOnly):
            return try replacing(
                state: .activeMonitorOnly,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.suspended, .resumeGranted):
            return try replacing(
                state: .activeGranted,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.activeMonitorOnly, .revoke), (.activeGranted, .revoke), (.suspended, .revoke):
            return try replacing(
                state: .revoked,
                advanceEpoch: true,
                advanceGrant: true
            )

        case (.revoked, .expireRevokedTombstone):
            return try replacing(state: .unpaired)

        default:
            throw InvalidDeviceAuthorizationTransition(state: state, event: event)
        }
    }

    private func replacing(
        state: DeviceAuthorizationState,
        advanceEpoch: Bool = false,
        advanceGrant: Bool = false
    ) throws -> Self {
        Self(
            state: state,
            authorizationEpoch: advanceEpoch ? try authorizationEpoch.advanced() : authorizationEpoch,
            grantRevision: advanceGrant ? try grantRevision.advanced() : grantRevision
        )
    }
}
