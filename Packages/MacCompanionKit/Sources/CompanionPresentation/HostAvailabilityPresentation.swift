import CompanionDomain
import CompanionObservation
import CompanionTransport

public enum ConnectionPresentationState: String, Codable, CaseIterable, Sendable {
    case background
    case noNetwork
    case connecting
    case retryScheduled
    case actionRequired
    case disconnectedByUser
    case connected
}

public struct HostAvailabilityPresentation: Equatable, Sendable {
    public let connection: ConnectionPresentationState
    public let retryAtMonotonicMilliseconds: Int64?
    public let observation: ObservationAssessment?

    public static func make(
        reconnectPhase: ReconnectPhase,
        retainedObservation: ObservationFreshness?,
        monotonicNowMilliseconds: Int64
    ) throws -> Self {
        let connection: ConnectionPresentationState
        let retryAt: Int64?
        let reachability: ClientReachabilityState

        switch reconnectPhase {
        case .waitingForForeground:
            connection = .background
            retryAt = nil
            reachability = .unreachable
        case .waitingForNetwork:
            connection = .noNetwork
            retryAt = nil
            reachability = .unreachable
        case .ready, .dialing:
            connection = .connecting
            retryAt = nil
            reachability = .unreachable
        case let .backoff(deadline):
            connection = .retryScheduled
            retryAt = deadline
            reachability = .unreachable
        case .requiresUserAction:
            connection = .actionRequired
            retryAt = nil
            reachability = .unreachable
        case .manuallyDisconnected:
            connection = .disconnectedByUser
            retryAt = nil
            reachability = .unreachable
        case .connected:
            connection = .connected
            retryAt = nil
            reachability = .reachable
        }

        return try Self(
            connection: connection,
            retryAtMonotonicMilliseconds: retryAt,
            observation: retainedObservation.map {
                try $0.assess(
                    reachability: reachability,
                    monotonicNowMilliseconds: monotonicNowMilliseconds
                )
            }
        )
    }
}
