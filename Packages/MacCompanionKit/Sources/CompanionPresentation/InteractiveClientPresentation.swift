import CompanionDiscovery
import CompanionDomain
import CompanionInteractiveShared
import Foundation

public typealias PairedMacDisplayName = DeviceDisplayName

public enum PairedMacRoutePresentation: String, Codable, CaseIterable, Sendable {
    case localDiscovery
    case directPrivateAddress
    case privateHostname

    public init(endpointKind: EndpointKind) {
        switch endpointKind {
        case .bonjour: self = .localDiscovery
        case .ipv4, .ipv6: self = .directPrivateAddress
        case .dns: self = .privateHostname
        }
    }
}

public enum InteractiveClientModePresentation: String, Codable, CaseIterable, Sendable {
    case unreachable
    case inactive
    case approvalRequired
    case starting
    case viewing
    case controlling
    case paused
    case ending
}

public enum HostLockPresentation: String, Codable, CaseIterable, Sendable {
    case unknown
    case unlocked
    case lockedControlAvailable
    case lockedInteractionUnavailable
}

public enum InteractiveRecoveryPresentationCause: String, Codable, CaseIterable, Sendable {
    case background
    case noNetwork
    case reconnecting
    case userActionRequired
    case disconnectedByUser
    case approvalExpired
    case clientRequested
    case clientDisconnected
    case maximumDurationReached
    case localSuspension
    case authorizationChanged
    case menuAppUnavailable
    case permissionLost
    case configuredUserUnavailable
    case hostStateAmbiguous
    case displayUnavailable
    case protocolViolation

    public init(endReason: InteractiveSessionEndReason) {
        switch endReason {
        case .approvalExpired: self = .approvalExpired
        case .clientRequested: self = .clientRequested
        case .clientDisconnected: self = .clientDisconnected
        case .maximumDurationReached: self = .maximumDurationReached
        case .localSuspension: self = .localSuspension
        case .authorizationChanged: self = .authorizationChanged
        case .menuAppUnavailable: self = .menuAppUnavailable
        case .permissionLost: self = .permissionLost
        case .configuredUserUnavailable: self = .configuredUserUnavailable
        case .hostStateAmbiguous: self = .hostStateAmbiguous
        case .displayUnavailable: self = .displayUnavailable
        case .protocolViolation: self = .protocolViolation
        }
    }
}

public enum InteractiveClientPresentationError: Error, Equatable, Sendable {
    case inconsistentInteractionClasses
    case activeSessionMissingView
}

public struct InteractiveClientPresentationSnapshot: Equatable, Sendable {
    public let hostID: UUID
    public let macDisplayName: PairedMacDisplayName
    public let route: PairedMacRoutePresentation?
    public let connection: ConnectionPresentationState
    public let mode: InteractiveClientModePresentation
    public let hostLock: HostLockPresentation
    public let activeSurface: InteractiveSurfaceKind?
    public let recoveryCause: InteractiveRecoveryPresentationCause?

    public static func make(
        hostID: UUID,
        locallyConfirmedMacName: PairedMacDisplayName,
        endpointKind: EndpointKind?,
        connection: ConnectionPresentationState,
        sessionState: InteractiveSessionState?,
        interactionClasses: Set<SurfaceInteractionClass>,
        activeSurface: InteractiveSurfaceKind?,
        recoveryCause: InteractiveRecoveryPresentationCause?
    ) throws -> Self {
        guard !interactionClasses.contains(.text)
                || interactionClasses.contains(.keyboard) else {
            throw InteractiveClientPresentationError
                .inconsistentInteractionClasses
        }
        let route = endpointKind.map(PairedMacRoutePresentation.init)
        guard connection == .connected else {
            return .init(
                hostID: hostID,
                macDisplayName: locallyConfirmedMacName,
                route: route,
                connection: connection,
                mode: .unreachable,
                hostLock: .unknown,
                activeSurface: nil,
                recoveryCause: recoveryCause
                    ?? Self.connectionCause(connection)
            )
        }

        let mode: InteractiveClientModePresentation
        let lock: HostLockPresentation
        let visibleSurface: InteractiveSurfaceKind?
        switch sessionState {
        case nil, .idle, .ended:
            mode = .inactive
            lock = .unknown
            visibleSurface = nil
        case .approvalRequired:
            mode = .approvalRequired
            lock = .unknown
            visibleSurface = nil
        case .starting:
            mode = .starting
            lock = .unknown
            visibleSurface = activeSurface
        case .activeUnlocked:
            guard interactionClasses.contains(.view) else {
                throw InteractiveClientPresentationError.activeSessionMissingView
            }
            mode = Self.activeMode(classes: interactionClasses)
            lock = .unlocked
            visibleSurface = activeSurface
        case .activeLocked:
            guard interactionClasses.contains(.view) else {
                throw InteractiveClientPresentationError.activeSessionMissingView
            }
            mode = Self.activeMode(classes: interactionClasses)
            lock = .lockedControlAvailable
            visibleSurface = activeSurface
        case .lockedInteractionUnavailable:
            mode = .paused
            lock = .lockedInteractionUnavailable
            visibleSurface = nil
        case .suspended:
            mode = .paused
            lock = .unknown
            visibleSurface = nil
        case .ending:
            mode = .ending
            lock = .unknown
            visibleSurface = nil
        }
        return .init(
            hostID: hostID,
            macDisplayName: locallyConfirmedMacName,
            route: route,
            connection: connection,
            mode: mode,
            hostLock: lock,
            activeSurface: visibleSurface,
            recoveryCause: recoveryCause
        )
    }

    private static func activeMode(
        classes: Set<SurfaceInteractionClass>
    ) -> InteractiveClientModePresentation {
        classes.contains(.pointer) || classes.contains(.keyboard)
            || classes.contains(.text) ? .controlling : .viewing
    }

    private static func connectionCause(
        _ connection: ConnectionPresentationState
    ) -> InteractiveRecoveryPresentationCause? {
        switch connection {
        case .background: .background
        case .noNetwork: .noNetwork
        case .connecting, .retryScheduled: .reconnecting
        case .actionRequired: .userActionRequired
        case .disconnectedByUser: .disconnectedByUser
        case .connected: nil
        }
    }
}
