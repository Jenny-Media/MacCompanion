import CompanionClient
import CompanionDiscovery
import CompanionTransport
import Foundation

public enum ClientPrivateRouteGuidanceConnectionV1:
    Equatable, Sendable
{
    case notEvaluated
    case waitingForForeground
    case waitingForNetwork
    case ready
    case connecting
    case retrying(failedRounds: UInt)
    case authenticated(endpoint: EndpointCandidate)
    case requiresUserAction
    case manuallyDisconnected
    case closed
    case statusUnavailable
}

public enum ClientPrivateRouteGuidanceToneV1:
    Equatable, Sendable
{
    case neutral
    case progress
    case success
    case needsAttention
}

public struct ClientPrivateRouteGuidanceStatusV1:
    Equatable, Sendable
{
    public let title: String
    public let detail: String
    public let tone: ClientPrivateRouteGuidanceToneV1
}

public enum ClientPrivateRouteSetupMethodIDV1:
    String, Equatable, Identifiable, Sendable
{
    case sameLocalNetwork
    case userManagedPrivateNetwork

    public var id: String { rawValue }
}

public struct ClientPrivateRouteSetupMethodV1:
    Equatable, Identifiable, Sendable
{
    public let id: ClientPrivateRouteSetupMethodIDV1
    public let title: String
    public let summary: String
    public let steps: [String]
}

/// Value-only private-route setup and troubleshooting guidance. Its inputs are
/// explicit configuration and connection facts; it cannot inspect paths,
/// interfaces, installed apps, DNS results, sockets, or credentials.
public struct ClientPrivateRouteGuidanceProjectionV1:
    Equatable, Sendable
{
    public let status: ClientPrivateRouteGuidanceStatusV1
    public let methods: [ClientPrivateRouteSetupMethodV1]
    public let securityBoundary: String

    public init(
        snapshot: ClientConfiguredRouteCatalogSnapshotV1,
        connection: ClientPrivateRouteGuidanceConnectionV1 = .notEvaluated
    ) {
        status = Self.status(
            catalog: snapshot.catalog,
            connection: connection
        )
        methods = Self.methods
        securityBoundary = "Mac Companion operates no relay, VPN account, or public port-forwarding service. A route provides reachability only; the paired identity, authenticated session, grants, and separate Remote Control approval still apply."
    }

    /// Projects the exact lifecycle composition emitted by the application
    /// binding. Contradictory or transitional snapshots do not get presented
    /// as network, authentication, or authorization failures.
    public init(
        bindingSnapshot: ClientConfiguredRouteApplicationBindingSnapshotV1
    ) {
        let lifecycle = bindingSnapshot.lifecycle
        self.init(
            snapshot: lifecycle.routeSnapshot,
            connection: Self.connection(
                bindingSnapshot: bindingSnapshot
            )
        )
    }

    private static func connection(
        bindingSnapshot: ClientConfiguredRouteApplicationBindingSnapshotV1
    ) -> ClientPrivateRouteGuidanceConnectionV1 {
        let lifecycle = bindingSnapshot.lifecycle
        let owner = lifecycle.reconnect
        let reconnect = owner.reconnect

        guard !bindingSnapshot.isDraining,
              bindingSnapshot.queuedEventCount == 0,
              !lifecycle.isTransitioning,
              !owner.isTransitioning,
              lifecycle.pairedHost.hostID == lifecycle.routeSnapshot.hostID,
              owner.hostID == lifecycle.routeSnapshot.hostID,
              owner.configurationRevision == lifecycle.routeSnapshot.revision,
              owner.foreground == bindingSnapshot.foreground,
              owner.networkReachable == bindingSnapshot.networkReachable,
              reconnect.candidates
                == lifecycle.routeSnapshot.catalog.records.map(\.endpoint),
              reconnect.requiredHostFingerprint
                == lifecycle.pairedHost.hostFingerprint else {
            return .statusUnavailable
        }

        if bindingSnapshot.phase == .closed {
            guard lifecycle.phase == .closed,
                  owner.isClosed,
                  reconnect.isShutdown else {
                return .statusUnavailable
            }
            return .closed
        }

        guard lifecycle.phase
                == (bindingSnapshot.foreground ? .active : .background),
              !owner.isClosed,
              !reconnect.isShutdown else {
            return .statusUnavailable
        }
        return connection(
            reconnectPhase: reconnect.phase,
            failedRounds: reconnect.failedRounds
        )
    }

    package static func connection(
        reconnectPhase: ReconnectPhase,
        failedRounds: Int
    ) -> ClientPrivateRouteGuidanceConnectionV1 {
        switch reconnectPhase {
        case .waitingForForeground:
            .waitingForForeground
        case .waitingForNetwork:
            .waitingForNetwork
        case .ready:
            .ready
        case .dialing:
            .connecting
        case .backoff:
            if let rounds = UInt(exactly: failedRounds), rounds > 0 {
                .retrying(failedRounds: rounds)
            } else {
                .statusUnavailable
            }
        case let .connected(endpoint):
            .authenticated(endpoint: endpoint)
        case .requiresUserAction:
            .requiresUserAction
        case .manuallyDisconnected:
            .manuallyDisconnected
        }
    }

    private static func status(
        catalog: ClientConfiguredRouteCatalogV1,
        connection: ClientPrivateRouteGuidanceConnectionV1
    ) -> ClientPrivateRouteGuidanceStatusV1 {
        switch connection {
        case .notEvaluated:
            return .init(
                title: "Choose how to reach this Mac",
                detail: "Use the same local network or a private network you already manage. Saved route labels are explicit configuration, not detected authority.",
                tone: .neutral
            )
        case .waitingForForeground:
            return .init(
                title: "Waiting for Mac Companion",
                detail: "Return to the app to connect. Background state does not keep a primary command connection open.",
                tone: .neutral
            )
        case .waitingForNetwork:
            return .init(
                title: "No usable network path",
                detail: "Check Wi-Fi, cellular, or your private-network app. This is only a coarse scheduling signal; it does not identify or authorize a route.",
                tone: .needsAttention
            )
        case .ready:
            return .init(
                title: "Ready to try saved routes",
                detail: "Mac Companion will verify the pinned Mac identity and application session on every candidate.",
                tone: .progress
            )
        case .connecting:
            return .init(
                title: "Trying saved routes",
                detail: "A route is usable only after the same connection completes identity pinning and Mac Companion authentication.",
                tone: .progress
            )
        case let .retrying(failedRounds):
            return .init(
                title: "Saved routes have not answered",
                detail: failedRounds == 1
                    ? "One connection round finished without an authenticated route. Mac Companion will retry with bounded backoff."
                    : "Multiple connection rounds finished without an authenticated route. Check the Mac, endpoint, and private network before retrying.",
                tone: .needsAttention
            )
        case let .authenticated(endpoint):
            guard let record = try? catalog.exactRecord(
                forWinningEndpoint: endpoint
            ), let type = ClientRouteConfigurationTypeV1(
                rawValue: record.provenance.rawValue
            ) else {
                return .init(
                    title: "Route configuration changed",
                    detail: "The authenticated endpoint no longer matches this saved route revision. Reconnect before relying on its status.",
                    tone: .needsAttention
                )
            }
            return .init(
                title: "Connected through \(type.title)",
                detail: "The route completed Mac Companion identity pinning and application authentication. It still grants no capability by itself.",
                tone: .success
            )
        case .requiresUserAction:
            return .init(
                title: "Mac Companion authorization needs attention",
                detail: "The network route answered, but authentication or current authorization was denied. Review pairing and device access instead of changing network settings first.",
                tone: .needsAttention
            )
        case .manuallyDisconnected:
            return .init(
                title: "Disconnected by you",
                detail: "Automatic connection stays paused until you explicitly resume it.",
                tone: .neutral
            )
        case .closed:
            return .init(
                title: "Connection owner stopped",
                detail: "Reopen this Mac connection to reload the paired identity and saved route revision.",
                tone: .needsAttention
            )
        case .statusUnavailable:
            return .init(
                title: "Connection status unavailable",
                detail: "Mac Companion withheld a contradictory or changing connection snapshot. Reopen this Mac connection instead of treating the status as route or authorization evidence.",
                tone: .needsAttention
            )
        }
    }

    private static let methods: [ClientPrivateRouteSetupMethodV1] = [
        .init(
            id: .sameLocalNetwork,
            title: "Same Local Network",
            summary: "The simplest setup when the iPhone and Mac share a trusted LAN.",
            steps: [
                "Connect the iPhone and Mac to the same trusted local network.",
                "Start pairing or discovery and allow Local Network access when iOS asks.",
                "Keep the Bonjour route, or explicitly save a private address if discovery is unavailable.",
            ]
        ),
        .init(
            id: .userManagedPrivateNetwork,
            title: "User-Managed Private Network",
            summary: "Use an existing private network such as Tailscale, ZeroTier, or WireGuard; Mac Companion does not create or administer it.",
            steps: [
                "Install and configure the private-network software outside Mac Companion on both devices.",
                "Confirm both devices belong to the intended private network using that provider's own tools.",
                "Save the Mac's private DNS name or address and label it Private Network.",
                "Reconnect and let Mac Companion independently verify the pinned Mac identity and session.",
            ]
        ),
    ]
}
