import CompanionClient
import CompanionInteractiveShared
import CompanionPresentation
import Foundation

public enum ClientPairingSurfaceV0: Equatable, Sendable {
    case scan
    case preview(PairingScanPreview)
    case securing(PairingSecurityProgress)
    case compareOnMac(PairingAuthenticationPresentation)
    case recovering(PairingAuthenticationPresentation)
    case saving
    case paired(PairedHostPresentation)
    case failed(PairingClientPresentationFailure)

    public init(presentation: PairingClientPresentation) {
        switch presentation.phase {
        case .scanning:
            self = .scan
        case .preview:
            self = presentation.preview.map(Self.preview)
                ?? .failed(.unknown)
        case .starting:
            self = .securing(.connecting)
        case .securing:
            self = .securing(
                presentation.securityProgress ?? .connecting
            )
        case .compareOnMac:
            self = presentation.authentication.map(Self.compareOnMac)
                ?? .failed(.unknown)
        case .recovering:
            self = presentation.authentication.map(Self.recovering)
                ?? .failed(.unknown)
        case .saving:
            self = .saving
        case .paired:
            self = presentation.pairedHost.map(Self.paired)
                ?? .failed(.unknown)
        case .failed:
            self = .failed(presentation.failure ?? .unknown)
        }
    }
}

public enum ClientHostPrimaryActionV0: String, Equatable, Sendable {
    case reconnect
    case startInteractiveControl
    case stopInteractiveControl
}

public enum ClientHostStatusV0: Equatable, Sendable {
    case background
    case noNetwork
    case connecting
    case retryScheduled
    case actionRequired
    case disconnected
    case ready
    case approvalRequired
    case starting
    case viewing
    case controlling
    case paused(HostLockPresentation)
    case ending
}

public struct ClientHostSurfaceProjectionV0: Equatable, Sendable {
    public let displayName: String
    public let route: PairedMacRoutePresentation?
    public let status: ClientHostStatusV0
    public let surface: InteractiveSurfaceKind?
    public let recoveryCause: InteractiveRecoveryPresentationCause?
    public let primaryAction: ClientHostPrimaryActionV0?

    public init(snapshot: InteractiveClientPresentationSnapshot) {
        displayName = snapshot.macDisplayName.rawValue
        route = snapshot.route
        surface = snapshot.activeSurface
        recoveryCause = snapshot.recoveryCause

        guard snapshot.connection == .connected else {
            status = Self.connectionStatus(snapshot.connection)
            switch snapshot.connection {
            case .actionRequired, .disconnectedByUser, .noNetwork:
                primaryAction = .reconnect
            case .background, .connecting, .retryScheduled, .connected:
                primaryAction = nil
            }
            return
        }

        switch snapshot.mode {
        case .unreachable:
            status = .disconnected
            primaryAction = .reconnect
        case .inactive:
            status = .ready
            primaryAction = .startInteractiveControl
        case .approvalRequired:
            status = .approvalRequired
            primaryAction = nil
        case .starting:
            status = .starting
            primaryAction = nil
        case .viewing:
            status = .viewing
            primaryAction = .stopInteractiveControl
        case .controlling:
            status = .controlling
            primaryAction = .stopInteractiveControl
        case .paused:
            status = .paused(snapshot.hostLock)
            primaryAction = .stopInteractiveControl
        case .ending:
            status = .ending
            primaryAction = nil
        }
    }

    private static func connectionStatus(
        _ value: ConnectionPresentationState
    ) -> ClientHostStatusV0 {
        switch value {
        case .background: .background
        case .noNetwork: .noNetwork
        case .connecting: .connecting
        case .retryScheduled: .retryScheduled
        case .actionRequired: .actionRequired
        case .disconnectedByUser: .disconnected
        case .connected: .ready
        }
    }
}
