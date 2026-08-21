import CompanionClientApp
import CompanionDiscovery
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Network

public enum NetworkClientPairingConnectionErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case invalidPhase
    case expired
    case exhaustedRoutes
    case deadlineMismatch
    case deadlineExpired
    case sendFailed
    case receiveFailed
    case remoteClosed
    case protocolFailure
}

struct NetworkClientPairingFrameChunkV0: Sendable {
    let data: Data
    let isComplete: Bool
}

protocol NetworkClientPairingFrameIOV0: Sendable {
    func send(_ data: Data) async throws
    func receive(maximumLength: Int) async throws
        -> NetworkClientPairingFrameChunkV0
    func cancel()
}

private final class NetworkClientPairingNWFrameIOV0:
    NetworkClientPairingFrameIOV0,
    @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ data: Data) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.send(
                    content: data,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if error == nil {
                            continuation.resume()
                        } else {
                            continuation.resume(
                                throwing:
                                    NetworkClientPairingConnectionErrorV0
                                        .sendFailed
                            )
                        }
                    }
                )
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func receive(maximumLength: Int) async throws
        -> NetworkClientPairingFrameChunkV0
    {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: maximumLength
                ) { data, _, isComplete, error in
                    guard error == nil else {
                        continuation.resume(
                            throwing:
                                NetworkClientPairingConnectionErrorV0
                                    .receiveFailed
                        )
                        return
                    }
                    continuation.resume(returning: .init(
                        data: data ?? Data(),
                        isComplete: isComplete
                    ))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func cancel() {
        connection.cancel()
    }
}

actor NetworkClientPairingFrameChannelV0 {
    static let maximumReceiveChunkBytes = 16_384

    private let io: any NetworkClientPairingFrameIOV0
    private let clock: @Sendable () -> NetworkClientClockSnapshotV0
    private var decoder = LengthPrefixedFrameDecoder()
    private var pendingFrames: [Data] = []
    private var remoteComplete = false
    private var closed = false
    private var receiveInFlight = false

    init(
        io: any NetworkClientPairingFrameIOV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0
    ) {
        self.io = io
        self.clock = clock
    }

    func send(
        _ frame: Data,
        deadlineMonotonicMilliseconds: UInt64
    ) async throws {
        guard !closed else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        let encoded: Data
        do {
            encoded = try LengthPrefixedFrameDecoder.encode(frame)
        } catch {
            await failClosed()
            throw NetworkClientPairingConnectionErrorV0.protocolFailure
        }
        do {
            try await bounded(
                deadlineMonotonicMilliseconds: deadlineMonotonicMilliseconds
            ) { [io] in
                try await io.send(encoded)
            }
        } catch {
            await failClosed()
            throw Self.map(error, send: true)
        }
    }

    func receive(
        deadlineMonotonicMilliseconds: UInt64
    ) async throws -> Data {
        guard !closed, !receiveInFlight else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        if !pendingFrames.isEmpty {
            return pendingFrames.removeFirst()
        }
        if remoteComplete {
            await failClosed()
            throw NetworkClientPairingConnectionErrorV0.remoteClosed
        }

        receiveInFlight = true
        defer { receiveInFlight = false }
        do {
            while true {
                let chunk = try await bounded(
                    deadlineMonotonicMilliseconds:
                        deadlineMonotonicMilliseconds
                ) { [io] in
                    try await io.receive(
                        maximumLength: Self.maximumReceiveChunkBytes
                    )
                }
                if !chunk.data.isEmpty {
                    let frames = try decoder.append(chunk.data)
                    pendingFrames.append(contentsOf: frames)
                }
                if chunk.isComplete { remoteComplete = true }
                if !pendingFrames.isEmpty {
                    return pendingFrames.removeFirst()
                }
                if remoteComplete {
                    throw NetworkClientPairingConnectionErrorV0.remoteClosed
                }
            }
        } catch {
            await failClosed()
            throw Self.map(error, send: false)
        }
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        io.cancel()
        pendingFrames.removeAll()
    }

    private func bounded<T: Sendable>(
        deadlineMonotonicMilliseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let now = clock().monotonicNowMilliseconds
        guard now <= UInt64(Int64.max),
              deadlineMonotonicMilliseconds <= UInt64(Int64.max),
              now < deadlineMonotonicMilliseconds else {
            throw NetworkClientPairingConnectionErrorV0.deadlineExpired
        }
        let delay = deadlineMonotonicMilliseconds - now
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: min(delay, UInt64.max / 1_000_000)
                        * 1_000_000
                )
                throw NetworkClientPairingConnectionErrorV0.deadlineExpired
            }
            guard let first = try await group.next() else {
                throw NetworkClientPairingConnectionErrorV0.protocolFailure
            }
            group.cancelAll()
            return first
        }
    }

    private func failClosed() async {
        guard !closed else { return }
        closed = true
        io.cancel()
        pendingFrames.removeAll()
    }

    private static func map(
        _ error: any Error,
        send: Bool
    ) -> NetworkClientPairingConnectionErrorV0 {
        if let error = error as? NetworkClientPairingConnectionErrorV0 {
            switch error {
            case .deadlineExpired, .remoteClosed, .protocolFailure:
                return error
            default:
                break
            }
        }
        if error is WireError { return .protocolFailure }
        return send ? .sendFailed : .receiveFailed
    }
}

struct NetworkClientPairingRouteCandidateV0: Sendable {
    let endpoint: EndpointCandidate
    let evidence: TLSPeerEvidence
    let channel: NetworkClientPairingFrameChannelV0

    func close() async {
        await channel.cancel()
    }
}

protocol NetworkClientPairingRouteAttemptingV0: Sendable {
    func attempt(
        endpoint: EndpointCandidate,
        requiredHostFingerprint: Data,
        connectTimeoutMilliseconds: Int64
    ) async -> NetworkClientPairingRouteCandidateV0?
}

private struct NetworkClientPairingNWRouteAttempterV0:
    NetworkClientPairingRouteAttemptingV0,
    Sendable
{
    let verificationQueue: DispatchQueue
    let connectionQueue: DispatchQueue
    let pinnedLeafEvaluator: NetworkClientPinnedLeafEvaluatorV0
    let clock: @Sendable () -> NetworkClientClockSnapshotV0

    func attempt(
        endpoint: EndpointCandidate,
        requiredHostFingerprint: Data,
        connectTimeoutMilliseconds: Int64
    ) async -> NetworkClientPairingRouteCandidateV0? {
        guard connectTimeoutMilliseconds > 0 else { return nil }
        let context: NetworkClientTLSAttemptContextV0
        let connection: NWConnection
        do {
            context = try NetworkClientTLSAttemptContextV0(
                endpoint: endpoint,
                requiredHostFingerprint: requiredHostFingerprint,
                verificationQueue: verificationQueue,
                pinnedLeafEvaluator: pinnedLeafEvaluator
            )
            connection = try context.makeUnstartedConnection()
        } catch {
            return nil
        }

        return await withTaskCancellationHandler {
            let readiness = NetworkClientConnectionReadinessLatchV0()
            connection.stateUpdateHandler = { state in
                readiness.observe(state)
            }
            connection.start(queue: connectionQueue)
            let result = await readiness.wait(
                timeoutMilliseconds: connectTimeoutMilliseconds
            )
            guard result == .ready, !Task.isCancelled else {
                connection.cancel()
                return nil
            }
            connection.stateUpdateHandler = nil
            do {
                let handoff = try context.consumeVerifiedHandoff(
                    for: connection
                )
                return NetworkClientPairingRouteCandidateV0(
                    endpoint: endpoint,
                    evidence: handoff.evidence,
                    channel: NetworkClientPairingFrameChannelV0(
                        io: NetworkClientPairingNWFrameIOV0(
                            connection: connection
                        ),
                        clock: clock
                    )
                )
            } catch {
                connection.cancel()
                return nil
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

/// Concrete no-relay pairing connection. It races every bounded QR route with
/// one immutable pin, selects only a TLS-verified candidate, cancels every
/// loser, and then serializes all framed traffic on that exact connection.
public actor NetworkClientPairingConnectionV0:
    ClientPairingConnectionV0
{
    public static let routeStaggerMilliseconds: Int64 = 250
    public static let maximumConnectTimeoutMilliseconds: Int64 = 5_000

    public typealias StaggerWait = @Sendable (Int64) async -> Void

    private enum State {
        case idle
        case connecting
        case connected(NetworkClientPairingRouteCandidateV0)
        case active(NetworkClientPairingRouteCandidateV0)
        case closed
    }

    private let request: ClientPairingConnectionRequestV0
    private let attempter: any NetworkClientPairingRouteAttemptingV0
    private let clock: @Sendable () -> NetworkClientClockSnapshotV0
    private let wait: StaggerWait
    private var state: State = .idle
    private var connectTask: Task<NetworkClientPairingRouteCandidateV0?, Never>?
    private var admittedDeadline: UInt64?

    init(
        request: ClientPairingConnectionRequestV0,
        attempter: any NetworkClientPairingRouteAttemptingV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        wait: @escaping StaggerWait = { milliseconds in
            guard milliseconds > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(milliseconds) * 1_000_000
            )
        }
    ) {
        self.request = request
        self.attempter = attempter
        self.clock = clock
        self.wait = wait
    }

    public func connectTCP() async throws {
        guard case .idle = state else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        let now = clock()
        guard now.wallNowUnixMilliseconds >= 0,
              now.monotonicNowMilliseconds <= UInt64(Int64.max),
              now.wallNowUnixMilliseconds
                < request.expiresAtUnixMilliseconds else {
            state = .closed
            throw NetworkClientPairingConnectionErrorV0.expired
        }
        let remaining = request.expiresAtUnixMilliseconds
            - now.wallNowUnixMilliseconds
        let timeout = min(
            Self.maximumConnectTimeoutMilliseconds,
            remaining
        )
        guard timeout > 0 else {
            state = .closed
            throw NetworkClientPairingConnectionErrorV0.expired
        }

        state = .connecting
        let task = Task { [request, attempter, wait] in
            await Self.race(
                request: request,
                timeoutMilliseconds: timeout,
                attempter: attempter,
                wait: wait
            )
        }
        connectTask = task
        let candidate = await task.value
        connectTask = nil
        guard case .connecting = state else {
            if let candidate { await candidate.close() }
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        guard let candidate else {
            state = .closed
            throw NetworkClientPairingConnectionErrorV0.exhaustedRoutes
        }
        state = .connected(candidate)
    }

    public func acceptPinnedTLS() async throws -> TLSPeerEvidence {
        guard case let .connected(candidate) = state else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        state = .active(candidate)
        return candidate.evidence
    }

    public func send(
        _ frame: Data,
        deadlineMonotonicMilliseconds: UInt64
    ) async throws {
        guard case let .active(candidate) = state else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        do {
            try admit(deadlineMonotonicMilliseconds)
            try await candidate.channel.send(
                frame,
                deadlineMonotonicMilliseconds:
                    deadlineMonotonicMilliseconds
            )
        } catch {
            await closeCandidate(candidate)
            throw error
        }
    }

    public func receive(
        deadlineMonotonicMilliseconds: UInt64
    ) async throws -> Data {
        guard case let .active(candidate) = state else {
            throw NetworkClientPairingConnectionErrorV0.invalidPhase
        }
        do {
            try admit(deadlineMonotonicMilliseconds)
            return try await candidate.channel.receive(
                deadlineMonotonicMilliseconds:
                    deadlineMonotonicMilliseconds
            )
        } catch {
            await closeCandidate(candidate)
            throw error
        }
    }

    public func close() async {
        connectTask?.cancel()
        connectTask = nil
        switch state {
        case let .connected(candidate), let .active(candidate):
            state = .closed
            await candidate.close()
        case .idle, .connecting:
            state = .closed
        case .closed:
            break
        }
    }

    private func admit(_ deadline: UInt64) throws {
        let now = clock().monotonicNowMilliseconds
        guard deadline <= UInt64(Int64.max), now < deadline else {
            throw NetworkClientPairingConnectionErrorV0.deadlineExpired
        }
        if let admittedDeadline {
            guard admittedDeadline == deadline else {
                throw NetworkClientPairingConnectionErrorV0.deadlineMismatch
            }
        } else {
            admittedDeadline = deadline
        }
    }

    private func closeCandidate(
        _ candidate: NetworkClientPairingRouteCandidateV0
    ) async {
        state = .closed
        await candidate.close()
    }

    private static func race(
        request: ClientPairingConnectionRequestV0,
        timeoutMilliseconds: Int64,
        attempter: any NetworkClientPairingRouteAttemptingV0,
        wait: @escaping StaggerWait
    ) async -> NetworkClientPairingRouteCandidateV0? {
        await withTaskGroup(
            of: NetworkClientPairingRouteCandidateV0?.self,
            returning: NetworkClientPairingRouteCandidateV0?.self
        ) { group in
            for (index, endpoint) in request.endpoints.enumerated() {
                let stagger = Int64(index) * routeStaggerMilliseconds
                guard stagger < timeoutMilliseconds else { continue }
                group.addTask {
                    await wait(stagger)
                    guard !Task.isCancelled else { return nil }
                    let candidate = await attempter.attempt(
                        endpoint: endpoint,
                        requiredHostFingerprint:
                            request.requiredHostFingerprint,
                        connectTimeoutMilliseconds:
                            timeoutMilliseconds - stagger
                    )
                    if Task.isCancelled {
                        if let candidate { await candidate.close() }
                        return nil
                    }
                    return candidate
                }
            }

            var selected: NetworkClientPairingRouteCandidateV0?
            for await candidate in group {
                guard let candidate else { continue }
                if selected == nil, !Task.isCancelled {
                    selected = candidate
                    group.cancelAll()
                } else {
                    await candidate.close()
                }
            }
            if Task.isCancelled {
                if let selected { await selected.close() }
                return nil
            }
            return selected
        }
    }
}

public struct NetworkClientPairingConnectionFactoryV0:
    ClientPairingConnectionCreatingV0,
    Sendable
{
    private let attempter: any NetworkClientPairingRouteAttemptingV0
    private let clock: @Sendable () -> NetworkClientClockSnapshotV0
    private let wait: NetworkClientPairingConnectionV0.StaggerWait

    public init(
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0
    ) {
        self.init(
            pinnedLeafEvaluator: SecurityClientPinnedLeafEvaluatorV0.make(
                wallNowUnixMilliseconds: {
                    clock().wallNowUnixMilliseconds
                }
            ),
            verificationQueue: verificationQueue,
            connectionQueue: connectionQueue,
            clock: clock
        )
    }

    package init(
        pinnedLeafEvaluator: @escaping NetworkClientPinnedLeafEvaluatorV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0
    ) {
        self.clock = clock
        attempter = NetworkClientPairingNWRouteAttempterV0(
            verificationQueue: verificationQueue,
            connectionQueue: connectionQueue,
            pinnedLeafEvaluator: pinnedLeafEvaluator,
            clock: clock
        )
        wait = { milliseconds in
            guard milliseconds > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(milliseconds) * 1_000_000
            )
        }
    }

    init(
        attempter: any NetworkClientPairingRouteAttemptingV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        wait: @escaping NetworkClientPairingConnectionV0.StaggerWait
    ) {
        self.attempter = attempter
        self.clock = clock
        self.wait = wait
    }

    public func makeConnection(
        _ request: ClientPairingConnectionRequestV0
    ) async throws -> any ClientPairingConnectionV0 {
        NetworkClientPairingConnectionV0(
            request: request,
            attempter: attempter,
            clock: clock,
            wait: wait
        )
    }
}
