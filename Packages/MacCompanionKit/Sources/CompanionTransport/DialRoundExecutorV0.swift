import CompanionDiscovery
import Foundation

public struct AuthenticatedDialRouteV0: Sendable {
    public let endpoint: EndpointCandidate
    private let sendAction: @Sendable (Data) async throws -> Void
    private let selectedAction: @Sendable () async -> Void
    private let closeAction: @Sendable () async -> Void

    public init(
        endpoint: EndpointCandidate,
        send: @escaping @Sendable (Data) async throws -> Void = { _ in
            throw AuthenticatedDialRouteErrorV0.commandTransportUnavailable
        },
        selected: @escaping @Sendable () async -> Void = {},
        close: @escaping @Sendable () async -> Void
    ) {
        self.endpoint = endpoint
        sendAction = send
        selectedAction = selected
        closeAction = close
    }

    public func sendCommand(_ frame: Data) async throws {
        try await sendAction(frame)
    }

    /// Called only by the reconnect owner after this exact authenticated route
    /// has become its current primary. Parallel or stale routes are closed
    /// without receiving this publication authority.
    package func selectedAsPrimary() async {
        await selectedAction()
    }

    public func close() async {
        await closeAction()
    }
}

public enum AuthenticatedDialRouteErrorV0: Error, Equatable, Sendable {
    case commandTransportUnavailable
}

public enum DialRouteAttemptOutcomeV0: Sendable {
    case transientFailure
    case authenticationDenied
    case authenticated(AuthenticatedDialRouteV0)
}

public protocol DialRouteAttemptingV0: Sendable {
    /// The implementation must use `requiredHostFingerprint` for the same live
    /// connection represented by any authenticated result. Endpoint text is
    /// routing input only and never identity evidence.
    func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0
}

public enum DialRoundRaceResultV0: Sendable {
    case exhausted
    case authenticationDenied
    case authenticated(AuthenticatedDialRouteV0)
    case cancelled
    case invalidAttemptResult
}

/// Executes one `ReconnectStateMachine` dial plan without owning route policy,
/// sockets, trust extraction, or application authentication. Every attempt is
/// handed the exact immutable pin from the round. Only a fully authenticated
/// result can win; all other or late authenticated routes are closed.
public struct DialRoundExecutorV0: Sendable {
    public typealias StaggerWait = @Sendable (Int64) async -> Void

    private enum ChildResult: Sendable {
        case transientFailure
        case authenticationDenied
        case authenticated(
            expectedEndpoint: EndpointCandidate,
            route: AuthenticatedDialRouteV0
        )
        case cancelled
    }

    private let attempter: any DialRouteAttemptingV0
    private let wait: StaggerWait

    public init(
        attempter: any DialRouteAttemptingV0,
        wait: @escaping StaggerWait = { milliseconds in
            guard milliseconds > 0 else { return }
            let nanoseconds = UInt64(milliseconds) * 1_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.attempter = attempter
        self.wait = wait
    }

    public func execute(_ round: DialRound) async -> DialRoundRaceResultV0 {
        guard round.requiredHostFingerprint.count == 32,
              (1...8).contains(round.attempts.count),
              Set(round.attempts.map(\.endpoint)).count == round.attempts.count,
              round.attempts.allSatisfy({
                  $0.startAfterMilliseconds >= 0
                      && $0.connectTimeoutMilliseconds
                          == ReconnectStateMachine.connectTimeoutMilliseconds
                      && $0.authenticationTimeoutMilliseconds
                          == ReconnectStateMachine.authenticationTimeoutMilliseconds
              })
        else {
            return .invalidAttemptResult
        }

        return await withTaskGroup(
            of: ChildResult.self,
            returning: DialRoundRaceResultV0.self
        ) { group in
            for attempt in round.attempts {
                group.addTask { [attempter, wait] in
                    if Task.isCancelled { return .cancelled }
                    await wait(attempt.startAfterMilliseconds)
                    if Task.isCancelled { return .cancelled }
                    let outcome = await attempter.attempt(
                        attempt,
                        roundID: round.roundID,
                        requiredHostFingerprint: round.requiredHostFingerprint
                    )
                    if Task.isCancelled {
                        if case let .authenticated(route) = outcome {
                            await route.close()
                        }
                        return .cancelled
                    }
                    switch outcome {
                    case .transientFailure:
                        return .transientFailure
                    case .authenticationDenied:
                        return .authenticationDenied
                    case let .authenticated(route):
                        return .authenticated(
                            expectedEndpoint: attempt.endpoint,
                            route: route
                        )
                    }
                }
            }

            var selected: AuthenticatedDialRouteV0?
            var terminal: DialRoundRaceResultV0?

            for await child in group {
                switch child {
                case .transientFailure, .cancelled:
                    break
                case .authenticationDenied:
                    if terminal == nil, selected == nil {
                        terminal = .authenticationDenied
                        group.cancelAll()
                    }
                case let .authenticated(expectedEndpoint, route):
                    guard route.endpoint == expectedEndpoint else {
                        await route.close()
                        if terminal == nil {
                            terminal = .invalidAttemptResult
                            if let selectedRoute = selected {
                                await selectedRoute.close()
                                selected = nil
                            }
                            group.cancelAll()
                        }
                        continue
                    }
                    if terminal != nil || selected != nil {
                        await route.close()
                    } else {
                        selected = route
                        group.cancelAll()
                    }
                }
            }

            if Task.isCancelled {
                if let selected { await selected.close() }
                return .cancelled
            }
            if let terminal { return terminal }
            if let selected { return .authenticated(selected) }
            return .exhausted
        }
    }
}
