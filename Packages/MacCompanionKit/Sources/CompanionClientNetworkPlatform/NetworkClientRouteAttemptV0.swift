import CompanionClient
import CompanionDiscovery
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Network

public enum NetworkClientConnectionStateDecisionV0:
    String,
    Equatable,
    Sendable
{
    case continueWaiting
    case ready
    case failed

    public static func decide(
        _ state: NWConnection.State
    ) -> NetworkClientConnectionStateDecisionV0 {
        switch state {
        case .ready:
            return .ready
        case .failed, .cancelled:
            return .failed
        case .setup, .preparing, .waiting:
            return .continueWaiting
        @unknown default:
            return .failed
        }
    }
}

public struct NetworkClientRouteAttemptConfigurationV0: Sendable {
    public typealias Nonce = @Sendable () throws -> WireBytes32
    public typealias MessageID = @Sendable () -> WireUUID

    public let clientID: UUID
    public let expectedHostID: UUID
    public let expectedDeviceID: UUID
    public let signer: any ClientSessionAuthenticationSigningV0
    public let clock: @Sendable () -> NetworkClientClockSnapshotV0
    public let nonce: Nonce
    public let messageID: MessageID
    public let pinnedLeafEvaluator: NetworkClientPinnedLeafEvaluatorV0
    public let verificationQueue: DispatchQueue
    public let connectionQueue: DispatchQueue
    public let authenticated: @Sendable (ClientAuthenticatedSessionV0) -> Void
    public let receivedCommand: @Sendable (Data) async throws -> Void
    public let configuredRoutes: ClientConfiguredRouteCatalogV1?
    package let primaryProduct: NetworkClientPrimaryProductConfigurationV0?

    package init(
        clientID: UUID,
        expectedHostID: UUID,
        expectedDeviceID: UUID,
        signer: any ClientSessionAuthenticationSigningV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        nonce: @escaping Nonce,
        messageID: @escaping MessageID,
        pinnedLeafEvaluator: @escaping NetworkClientPinnedLeafEvaluatorV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        authenticated: @escaping @Sendable (
            ClientAuthenticatedSessionV0
        ) -> Void = { _ in },
        receivedCommand: @escaping @Sendable (Data) async throws -> Void = {
            _ in
        },
        configuredRoutes: ClientConfiguredRouteCatalogV1? = nil,
        primaryProduct: NetworkClientPrimaryProductConfigurationV0? = nil
    ) {
        self.clientID = clientID
        self.expectedHostID = expectedHostID
        self.expectedDeviceID = expectedDeviceID
        self.signer = signer
        self.clock = clock
        self.nonce = nonce
        self.messageID = messageID
        self.pinnedLeafEvaluator = pinnedLeafEvaluator
        self.verificationQueue = verificationQueue
        self.connectionQueue = connectionQueue
        self.authenticated = authenticated
        self.receivedCommand = receivedCommand
        self.configuredRoutes = configuredRoutes
        self.primaryProduct = primaryProduct
    }

    public func configuredRoute(
        forExactEndpoint endpoint: EndpointCandidate
    ) throws -> ClientConfiguredRouteRecordV1? {
        guard let configuredRoutes else { return nil }
        return try configuredRoutes.exactRecord(
            forWinningEndpoint: endpoint
        )
    }
}

/// Concrete Network.framework attempt owner for one reconnect-plan route. It
/// starts exactly one one-shot TLS context, waits through transient `.waiting`
/// states only until the plan's connect deadline, consumes evidence only for
/// that exact ready connection, then hands ownership to the client frame pump.
public struct NetworkClientRouteAttemptV0: DialRouteAttemptingV0, Sendable {
    private let configuration: NetworkClientRouteAttemptConfigurationV0

    package init(configuration: NetworkClientRouteAttemptConfigurationV0) {
        self.configuration = configuration
    }

    public func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0 {
        guard requiredHostFingerprint.count == 32,
              attempt.connectTimeoutMilliseconds
                == ReconnectStateMachine.connectTimeoutMilliseconds,
              attempt.authenticationTimeoutMilliseconds
                == ReconnectStateMachine.authenticationTimeoutMilliseconds
        else {
            return .authenticationDenied
        }

        let context: NetworkClientTLSAttemptContextV0
        let connection: NWConnection
        do {
            context = try NetworkClientTLSAttemptContextV0(
                endpoint: attempt.endpoint,
                requiredHostFingerprint: requiredHostFingerprint,
                verificationQueue: configuration.verificationQueue,
                pinnedLeafEvaluator: configuration.pinnedLeafEvaluator
            )
            connection = try context.makeUnstartedConnection()
        } catch {
            return .authenticationDenied
        }

        return await withTaskCancellationHandler {
            let readiness = NetworkClientConnectionReadinessLatchV0()
            connection.stateUpdateHandler = { state in
                readiness.observe(state)
            }
            connection.start(queue: configuration.connectionQueue)
            let ready = await readiness.wait(
                timeoutMilliseconds: attempt.connectTimeoutMilliseconds
            )
            guard ready == .ready, !Task.isCancelled else {
                connection.cancel()
                return .transientFailure
            }
            connection.stateUpdateHandler = nil

            let handoff: NetworkClientApplicationTLSHandoffV0
            let session: ClientPrimarySessionV0
            let start: NetworkClientHandshakeStartV0
            let authenticatedRouteClass:
                NetworkClientAuthenticatedRouteClassV1?
            do {
                handoff = try context.consumeVerifiedHandoff(for: connection)
                let configuredRoute = try configuration.configuredRoute(
                    forExactEndpoint: attempt.endpoint
                )
                authenticatedRouteClass =
                    NetworkClientAuthenticatedRouteClassV1.project(
                        configuredRoute
                    )
                session = try ClientPrimarySessionV0(
                    clientID: configuration.clientID,
                    expectedHostID: configuration.expectedHostID,
                    expectedDeviceID: configuration.expectedDeviceID,
                    requiredHostFingerprint: requiredHostFingerprint,
                    signer: configuration.signer,
                    configuredRoute: configuredRoute
                )
                let helloID = configuration.messageID()
                let proofID = configuration.messageID()
                let now = configuration.clock()
                start = try NetworkClientHandshakeStartV0(
                    clientNonce: configuration.nonce(),
                    helloMessageID: helloID,
                    proofMessageID: proofID,
                    wallNowUnixMilliseconds: now.wallNowUnixMilliseconds,
                    monotonicNowMilliseconds: now.monotonicNowMilliseconds
                )
            } catch {
                connection.cancel()
                return .authenticationDenied
            }

            let completion = NetworkClientAuthenticationLatchV0()
            let productCandidate = configuration.primaryProduct.map {
                NetworkClientPrimaryProductCandidateV0(
                    endpoint: attempt.endpoint,
                    authenticatedRouteClass: authenticatedRouteClass,
                    configuration: $0
                )
            }
            let pump = NetworkClientPrimaryFramePumpV0(
                connection: connection,
                tlsHandoff: handoff,
                session: session,
                clock: configuration.clock,
                authenticated: { value in
                    if let productCandidate {
                        try await productCandidate.authenticated(value)
                    } else {
                        configuration.authenticated(value)
                    }
                },
                readyForAuthenticatedTraffic: {
                    completion.finish(.authenticated)
                },
                receivedCommand: { frame in
                    if let productCandidate {
                        try await productCandidate.receive(frame)
                    } else {
                        try await configuration.receivedCommand(frame)
                    }
                },
                routeMessageID: configuration.messageID,
                terminal: { reason in
                    completion.finish(
                        reason == .authenticationDenied
                            ? .authenticationDenied
                            : .failed
                    )
                    if let productCandidate {
                        Task { await productCandidate.primaryTerminated() }
                    }
                }
            )
            do {
                if let productCandidate {
                    try await productCandidate.bind(pump)
                }
                try await pump.beginOnVerifiedReadyConnection(start)
            } catch {
                await pump.cancel()
                return productCandidate == nil
                    ? .transientFailure
                    : .authenticationDenied
            }

            switch await completion.wait() {
            case .authenticated:
                guard !Task.isCancelled else {
                    await pump.cancel()
                    return .transientFailure
                }
                return .authenticated(AuthenticatedDialRouteV0(
                    endpoint: attempt.endpoint,
                    send: { frame in
                        try await pump.sendAuthenticatedCommand(frame)
                    },
                    selected: {
                        await productCandidate?.selectedAsPrimary()
                    },
                    close: { await pump.cancel() }
                ))
            case .authenticationDenied:
                return .authenticationDenied
            case .failed, .cancelled:
                return .transientFailure
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

enum NetworkClientConnectionReadinessV0: Equatable, Sendable {
    case ready
    case failed
    case timedOut
    case cancelled
}

final class NetworkClientConnectionReadinessLatchV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var result: NetworkClientConnectionReadinessV0?
    private var continuation: CheckedContinuation<
        NetworkClientConnectionReadinessV0,
        Never
    >?
    private var timeoutTask: Task<Void, Never>?

    func observe(_ state: NWConnection.State) {
        switch NetworkClientConnectionStateDecisionV0.decide(state) {
        case .continueWaiting:
            break
        case .ready:
            finish(.ready)
        case .failed:
            finish(.failed)
        }
    }

    func wait(timeoutMilliseconds: Int64) async
        -> NetworkClientConnectionReadinessV0
    {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                    return
                }
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    let bounded = UInt64(max(0, timeoutMilliseconds))
                    try? await Task.sleep(
                        nanoseconds: bounded * 1_000_000
                    )
                    guard !Task.isCancelled else { return }
                    self?.finish(.timedOut)
                }
                lock.unlock()
            }
        } onCancel: {
            finish(.cancelled)
        }
    }

    private func finish(_ value: NetworkClientConnectionReadinessV0) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()
        timeoutTask?.cancel()
        continuation?.resume(returning: value)
    }
}

enum NetworkClientAuthenticationCompletionV0: Sendable {
    case authenticated
    case authenticationDenied
    case failed
    case cancelled
}

final class NetworkClientAuthenticationLatchV0: @unchecked Sendable {
    private let lock = NSLock()
    private var result: NetworkClientAuthenticationCompletionV0?
    private var continuation: CheckedContinuation<
        NetworkClientAuthenticationCompletionV0,
        Never
    >?

    func wait() async -> NetworkClientAuthenticationCompletionV0 {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            finish(.cancelled)
        }
    }

    func finish(_ value: NetworkClientAuthenticationCompletionV0) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
