import CompanionDomain
import CompanionHostSession
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Network

public enum NetworkHostPrimaryFramePumpErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case connectionClosed
    case sendFailed
}

public enum NetworkHostPrimaryTerminationReasonV0: String, Equatable, Sendable {
    case localCancel
    case connectionFailed
    case connectionCancelled
    case unknownConnectionState
    case receiveFailed
    case remoteClosed
    case protocolOrSessionFailure
    case sessionDeadline
}

public struct NetworkHostRequestContextV0: Sendable {
    public let hostState: HostState
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64
    public let responseMessageID: WireUUID

    public init(
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) {
        self.hostState = hostState
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.responseMessageID = responseMessageID
    }
}

enum NetworkHostPrimaryFrameIOStateV0: Equatable, Sendable {
    case setup
    case preparing
    case waiting
    case ready
    case failed
    case cancelled
    case invalid
}

protocol NetworkHostPrimaryFrameIOV0: Sendable {
    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostPrimaryFrameIOStateV0
        ) -> Void
    )
    func start(queue: DispatchQueue)
    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (
            _ data: Data?,
            _ isComplete: Bool,
            _ failed: Bool
        ) -> Void
    )
    func send(_ data: Data) async throws
    func cancel()
}

private final class NetworkHostPrimaryNWFrameIOV0:
    NetworkHostPrimaryFrameIOV0,
    @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostPrimaryFrameIOStateV0
        ) -> Void
    ) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .setup:
                handler(.setup)
            case .preparing:
                handler(.preparing)
            case .waiting:
                handler(.waiting)
            case .ready:
                handler(.ready)
            case .failed:
                handler(.failed)
            case .cancelled:
                handler(.cancelled)
            @unknown default:
                handler(.invalid)
            }
        }
    }

    func start(queue: DispatchQueue) {
        connection.start(queue: queue)
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (
            _ data: Data?,
            _ isComplete: Bool,
            _ failed: Bool
        ) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: maximumLength
        ) { data, _, isComplete, error in
            completion(data, isComplete, error != nil)
        }
    }

    func send(_ data: Data) async throws {
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
                                NetworkHostPrimaryFramePumpErrorV0.sendFailed
                        )
                    }
                }
            )
        }
    }

    func cancel() {
        connection.cancel()
    }
}

private final class NetworkHostPrimaryClassifiedFrameIOV0:
    NetworkHostPrimaryFrameIOV0,
    @unchecked Sendable
{
    private let io: any NetworkHostIngressFrameIOV0

    init(io: any NetworkHostIngressFrameIOV0) {
        self.io = io
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostPrimaryFrameIOStateV0
        ) -> Void
    ) {}

    func start(queue: DispatchQueue) {}

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (
            _ data: Data?,
            _ isComplete: Bool,
            _ failed: Bool
        ) -> Void
    ) {
        Task {
            do {
                let chunk = try await io.receive(
                    maximumLength: maximumLength
                )
                completion(chunk.data, chunk.isComplete, false)
            } catch {
                completion(nil, false, true)
            }
        }
    }

    func send(_ data: Data) async throws {
        try await io.send(data)
    }

    func cancel() {
        io.cancel()
    }
}

/// Network.framework adapter for one accepted and verified-ready host-side
/// application-primary connection. The public construction path consumes the
/// one-shot authority produced by `NetworkHostAcceptedConnectionV0`, so a
/// caller cannot pair an unrelated connection with reconstructed TLS facts.
///
/// Receives are serialized: another read is scheduled only after every frame
/// in the current chunk has produced and sent its response. This gives the
/// session owner bounded backpressure and prevents accidental parallel command
/// admission in the first adapter.
public actor NetworkHostPrimaryFramePumpV0 {
    public static let maximumReceiveChunkBytes = 16_384

    public let tlsBinding: HostApplicationTLSBinding

    private let io: any NetworkHostPrimaryFrameIOV0
    private let session: AuthenticatedPrimarySessionV0
    private let context: @Sendable () -> NetworkHostRequestContextV0
    private let terminal: @Sendable (NetworkHostPrimaryTerminationReasonV0) -> Void
    private var initialClassifiedFrame: Data?
    private var decoder = LengthPrefixedFrameDecoder()
    private var started = false
    private var stopped = false
    private var deadlineTask: Task<Void, Never>?
    private var classifiedActivationContinuation:
        CheckedContinuation<Void, Error>?

    public init(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        session: AuthenticatedPrimarySessionV0,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        let connection = try verifiedReadyConnection.consumeConnection()
        io = NetworkHostPrimaryNWFrameIOV0(connection: connection)
        tlsBinding = verifiedReadyConnection.tlsBinding
        self.session = session
        self.context = context
        self.terminal = terminal
        initialClassifiedFrame = nil
    }

    init(
        connection: NWConnection,
        tlsBinding: HostApplicationTLSBinding,
        session: AuthenticatedPrimarySessionV0,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) {
        io = NetworkHostPrimaryNWFrameIOV0(connection: connection)
        self.tlsBinding = tlsBinding
        self.session = session
        self.context = context
        self.terminal = terminal
        initialClassifiedFrame = nil
    }

    init(
        io: any NetworkHostPrimaryFrameIOV0,
        tlsBinding: HostApplicationTLSBinding,
        session: AuthenticatedPrimarySessionV0,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.tlsBinding = tlsBinding
        self.session = session
        self.context = context
        self.terminal = terminal
        initialClassifiedFrame = nil
    }

    public init(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        session: AuthenticatedPrimarySessionV0,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        let consumed = try classifiedConnection.consume(
            expectedRole: .applicationPrimary
        )
        io = NetworkHostPrimaryClassifiedFrameIOV0(io: consumed.io)
        tlsBinding = consumed.tlsBinding
        initialClassifiedFrame = consumed.initialFrame
        self.session = session
        self.context = context
        self.terminal = terminal
    }

    func start(queue: DispatchQueue) throws {
        guard !started, !stopped else {
            throw NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
        }
        started = true
        io.setStateUpdateHandler { [weak self] state in
            Task { await self?.connectionStateChanged(state) }
        }
        io.start(queue: queue)
        awaitDeadline()
    }

    /// Begins reads on the exact connection that was already started and
    /// verified ready by `NetworkHostAcceptedConnectionV0`. This transfer path
    /// deliberately does not start the connection a second time.
    public func beginOnVerifiedReadyConnection() throws {
        guard !started, !stopped else {
            throw NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
        }
        started = true
        io.setStateUpdateHandler { [weak self] state in
            Task { await self?.connectionStateChanged(state) }
        }
        receiveNext()
        awaitDeadline()
    }

    /// Replays the exact first frame retained by the one-use ingress
    /// classifier through the primary semantic owner before scheduling another
    /// socket read.
    public func beginOnClassifiedConnection() async throws {
        guard !started, !stopped, let initialClassifiedFrame else {
            throw NetworkHostPrimaryFramePumpErrorV0.invalidConfiguration
        }
        started = true
        self.initialClassifiedFrame = nil
        io.setStateUpdateHandler { [weak self] state in
            Task { await self?.connectionStateChanged(state) }
        }
        do {
            let current = context()
            let response = try await session.receive(
                requestJSON: initialClassifiedFrame,
                hostState: current.hostState,
                wallNowUnixMilliseconds: current.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: current.monotonicNowMilliseconds,
                responseMessageID: current.responseMessageID
            )
            try await send(LengthPrefixedFrameDecoder.encode(response))
            receiveNext()
            awaitDeadline()
            try await withCheckedThrowingContinuation { continuation in
                classifiedActivationContinuation = continuation
            }
        } catch {
            await stop(reason: .protocolOrSessionFailure)
            if let error = error as? NetworkHostPrimaryFramePumpErrorV0 {
                throw error
            }
            throw NetworkHostPrimaryFramePumpErrorV0.connectionClosed
        }
    }

    public func cancel() async {
        await stop(reason: .localCancel)
    }

    private func connectionStateChanged(
        _ state: NetworkHostPrimaryFrameIOStateV0
    ) async {
        guard !stopped else { return }
        switch state {
        case .ready:
            receiveNext()
        case .failed:
            await stop(reason: .connectionFailed)
        case .cancelled:
            await stop(reason: .connectionCancelled, cancelIO: false)
        case .setup, .preparing, .waiting:
            break
        case .invalid:
            await stop(reason: .unknownConnectionState)
        }
    }

    private func receiveNext() {
        guard started, !stopped else { return }
        io.receive(maximumLength: Self.maximumReceiveChunkBytes) {
            [weak self] data, isComplete, failed in
            Task {
                await self?.received(
                    data,
                    isComplete: isComplete,
                    failed: failed
                )
            }
        }
    }

    private func received(
        _ data: Data?,
        isComplete: Bool,
        failed: Bool
    ) async {
        guard !stopped else { return }
        if failed {
            await stop(reason: .receiveFailed)
            return
        }
        do {
            if let data, !data.isEmpty {
                let frames = try decoder.append(data)
                for frame in frames {
                    let current = context()
                    let response = try await session.receive(
                        requestJSON: frame,
                        hostState: current.hostState,
                        wallNowUnixMilliseconds: current.wallNowUnixMilliseconds,
                        monotonicNowMilliseconds: current.monotonicNowMilliseconds,
                        responseMessageID: current.responseMessageID
                    )
                    try await send(LengthPrefixedFrameDecoder.encode(response))
                    if await session.phase == .ready {
                        completeClassifiedActivation()
                    }
                }
                awaitDeadline()
            }
            if isComplete {
                await stop(reason: .remoteClosed)
            } else {
                receiveNext()
            }
        } catch {
            await stop(reason: .protocolOrSessionFailure)
        }
    }

    private func send(_ data: Data) async throws {
        try await io.send(data)
    }

    private func stop(
        reason: NetworkHostPrimaryTerminationReasonV0,
        cancelIO: Bool = true
    ) async {
        guard !stopped else { return }
        stopped = true
        deadlineTask?.cancel()
        deadlineTask = nil
        if cancelIO {
            io.cancel()
        }
        classifiedActivationContinuation?.resume(
            throwing: NetworkHostPrimaryFramePumpErrorV0.connectionClosed
        )
        classifiedActivationContinuation = nil
        await session.close()
        terminal(reason)
    }

    private func completeClassifiedActivation() {
        classifiedActivationContinuation?.resume()
        classifiedActivationContinuation = nil
    }

    private func awaitDeadline() {
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            guard let self,
                  let deadline = await self.session.nextDeadlineMonotonicMilliseconds()
            else { return }
            let now = self.context().monotonicNowMilliseconds
            let delayMilliseconds = deadline > now ? deadline - now : 0
            let delayNanoseconds = min(
                delayMilliseconds,
                UInt64.max / 1_000_000
            ) * 1_000_000
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            await self.deadlineReached()
        }
    }

    private func deadlineReached() async {
        guard !stopped else { return }
        let expired = await session.expireIfRequired(
            at: context().monotonicNowMilliseconds
        )
        if expired {
            await stop(reason: .sessionDeadline)
        } else {
            awaitDeadline()
        }
    }
}
