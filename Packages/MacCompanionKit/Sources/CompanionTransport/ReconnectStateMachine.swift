import CompanionDiscovery
import Foundation

public enum ReconnectError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidTime
    case invalidTransition
    case staleRound
}

public struct DialAttempt: Equatable, Sendable {
    public let endpoint: EndpointCandidate
    public let startAfterMilliseconds: Int64
    public let connectTimeoutMilliseconds: Int64
    public let authenticationTimeoutMilliseconds: Int64
}

public struct DialRound: Equatable, Sendable {
    public let roundID: UUID
    public let requiredHostFingerprint: Data
    public let attempts: [DialAttempt]
}

public enum ReconnectPhase: Equatable, Sendable {
    case waitingForForeground
    case waitingForNetwork
    case ready
    case dialing(UUID)
    case backoff(untilMonotonicMilliseconds: Int64)
    case connected(EndpointCandidate)
    case requiresUserAction
    case manuallyDisconnected
}

public enum ReconnectEvent: Equatable, Sendable {
    case setForeground(Bool, monotonicNowMilliseconds: Int64)
    case setNetworkReachable(Bool, monotonicNowMilliseconds: Int64)
    case replaceCandidates([EndpointCandidate], monotonicNowMilliseconds: Int64)
    case tick(monotonicNowMilliseconds: Int64, roundID: UUID)
    case roundExhausted(UUID, monotonicNowMilliseconds: Int64, jitterBasisPoints: UInt16)
    case authenticated(UUID, EndpointCandidate)
    case authenticationDenied(UUID)
    case connectionLost(monotonicNowMilliseconds: Int64)
    case manualDisconnect
    case resumeManualConnection
    case resumeAfterUserAction
}

public enum ReconnectEffect: Equatable, Sendable {
    case startDialRound(DialRound)
    case scheduleRetry(atMonotonicMilliseconds: Int64)
    case cancelPendingDials
    case closeConnection
}

public struct ReconnectStateMachine: Equatable, Sendable {
    public static let routeStaggerMilliseconds: Int64 = 250
    public static let connectTimeoutMilliseconds: Int64 = 10_000
    public static let authenticationTimeoutMilliseconds: Int64 = 10_000
    public static let backoffMilliseconds: [Int64] = [500, 1_000, 2_000, 4_000, 8_000, 15_000, 30_000]

    public private(set) var candidates: [EndpointCandidate]
    public let requiredHostFingerprint: Data
    public private(set) var foreground: Bool
    public private(set) var networkReachable: Bool
    public private(set) var phase: ReconnectPhase
    public private(set) var failedRounds: Int

    private var manualDisconnectActive: Bool
    private var userActionRequired: Bool

    public init(
        candidates: [EndpointCandidate],
        requiredHostFingerprint: Data,
        foreground: Bool,
        networkReachable: Bool
    ) throws {
        guard Self.validCandidates(candidates), requiredHostFingerprint.count == 32 else {
            throw ReconnectError.invalidConfiguration
        }
        self.candidates = candidates
        self.requiredHostFingerprint = requiredHostFingerprint
        self.foreground = foreground
        self.networkReachable = networkReachable
        self.failedRounds = 0
        self.manualDisconnectActive = false
        self.userActionRequired = false
        if !foreground {
            phase = .waitingForForeground
        } else if !networkReachable {
            phase = .waitingForNetwork
        } else {
            phase = .ready
        }
    }

    @discardableResult
    public mutating func apply(_ event: ReconnectEvent) throws -> [ReconnectEffect] {
        switch event {
        case let .setForeground(value, now):
            try requireTime(now)
            guard value != foreground else { return [] }
            let interruption = interruptionEffects()
            foreground = value
            if value { failedRounds = 0 }
            phase = availablePhase()
            return interruption

        case let .setNetworkReachable(value, now):
            try requireTime(now)
            guard value != networkReachable else { return [] }
            let interruption = interruptionEffects()
            networkReachable = value
            if value { failedRounds = 0 }
            phase = availablePhase()
            return interruption

        case let .replaceCandidates(replacement, now):
            try requireTime(now)
            guard Self.validCandidates(replacement) else {
                throw ReconnectError.invalidConfiguration
            }
            let interruption = interruptionEffects()
            candidates = replacement
            failedRounds = 0
            phase = availablePhase()
            return interruption

        case let .tick(now, roundID):
            try requireTime(now)
            let mayStart: Bool
            switch phase {
            case .ready:
                mayStart = true
            case let .backoff(deadline):
                mayStart = now >= deadline
            default:
                mayStart = false
            }
            guard mayStart, foreground, networkReachable,
                  !manualDisconnectActive, !userActionRequired else { return [] }
            let round = DialRound(
                roundID: roundID,
                requiredHostFingerprint: requiredHostFingerprint,
                attempts: candidates.enumerated().map { index, endpoint in
                    DialAttempt(
                        endpoint: endpoint,
                        startAfterMilliseconds: Int64(index) * Self.routeStaggerMilliseconds,
                        connectTimeoutMilliseconds: Self.connectTimeoutMilliseconds,
                        authenticationTimeoutMilliseconds: Self.authenticationTimeoutMilliseconds
                    )
                }
            )
            phase = .dialing(roundID)
            return [.startDialRound(round)]

        case let .roundExhausted(roundID, now, jitterBasisPoints):
            try requireTime(now)
            guard case let .dialing(activeRoundID) = phase,
                  activeRoundID == roundID else { throw ReconnectError.staleRound }
            guard (8_000...12_000).contains(jitterBasisPoints) else {
                throw ReconnectError.invalidConfiguration
            }
            let index = min(failedRounds, Self.backoffMilliseconds.count - 1)
            let base = Self.backoffMilliseconds[index]
            let delay = base * Int64(jitterBasisPoints) / 10_000
            guard now <= Int64.max - delay else { throw ReconnectError.invalidTime }
            let deadline = now + delay
            failedRounds += 1
            phase = .backoff(untilMonotonicMilliseconds: deadline)
            return [.scheduleRetry(atMonotonicMilliseconds: deadline)]

        case let .authenticated(roundID, endpoint):
            guard case let .dialing(activeRoundID) = phase,
                  activeRoundID == roundID else { throw ReconnectError.staleRound }
            guard candidates.contains(endpoint) else { throw ReconnectError.invalidConfiguration }
            failedRounds = 0
            phase = .connected(endpoint)
            return [.cancelPendingDials]

        case let .authenticationDenied(roundID):
            guard case let .dialing(activeRoundID) = phase,
                  activeRoundID == roundID else { throw ReconnectError.staleRound }
            userActionRequired = true
            phase = .requiresUserAction
            return [.cancelPendingDials]

        case let .connectionLost(now):
            try requireTime(now)
            guard case .connected = phase else { throw ReconnectError.invalidTransition }
            phase = availablePhase()
            return []

        case .manualDisconnect:
            guard !manualDisconnectActive else { throw ReconnectError.invalidTransition }
            let effects = interruptionEffects()
            manualDisconnectActive = true
            phase = .manuallyDisconnected
            return effects

        case .resumeManualConnection:
            guard manualDisconnectActive else { throw ReconnectError.invalidTransition }
            manualDisconnectActive = false
            failedRounds = 0
            phase = availablePhase()
            return []

        case .resumeAfterUserAction:
            guard userActionRequired else { throw ReconnectError.invalidTransition }
            userActionRequired = false
            failedRounds = 0
            phase = availablePhase()
            return []
        }
    }

    private func availablePhase() -> ReconnectPhase {
        if manualDisconnectActive { return .manuallyDisconnected }
        if userActionRequired { return .requiresUserAction }
        if !foreground { return .waitingForForeground }
        if !networkReachable { return .waitingForNetwork }
        return .ready
    }

    private func interruptionEffects() -> [ReconnectEffect] {
        switch phase {
        case .dialing:
            return [.cancelPendingDials]
        case .connected:
            return [.closeConnection]
        default:
            return []
        }
    }

    private func requireTime(_ value: Int64) throws {
        guard value >= 0 else { throw ReconnectError.invalidTime }
    }

    private static func validCandidates(_ values: [EndpointCandidate]) -> Bool {
        (1...8).contains(values.count) && Set(values).count == values.count
    }
}
