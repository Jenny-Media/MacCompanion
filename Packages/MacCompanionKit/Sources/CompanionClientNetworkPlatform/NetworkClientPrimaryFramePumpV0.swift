import CompanionClient
import CompanionTransport
import CompanionWire
import Foundation
import Network

public enum NetworkClientPrimaryFramePumpErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case connectionClosed
    case sendFailed
}

public enum NetworkClientPrimaryTerminationReasonV0:
    String,
    Equatable,
    Sendable
{
    case localCancel
    case connectionFailed
    case connectionCancelled
    case unknownConnectionState
    case receiveFailed
    case remoteClosed
    case authenticationDenied
    case protocolOrSessionFailure
    case authenticationDeadline
}

/// Independent evidence value passed only after a live Network.framework TLS
/// callback has parsed and accepted this same connection. Like the host-side
/// binding, this value does not extract metadata itself; that final adapter is
/// still a signed-identity evidence gate.
public struct NetworkClientApplicationTLSHandoffV0: Equatable, Sendable {
    public let evidence: TLSPeerEvidence
    public let hostFingerprint: Data

    public init(
        evidence: TLSPeerEvidence,
        requiredHostFingerprint: Data
    ) throws {
        var authority = try PinnedTLSConnectionAuthority(
            role: .applicationPrimary,
            requiredHostFingerprint: requiredHostFingerprint
        )
        try authority.didConnectTCP()
        try authority.acceptPeer(evidence)
        try authority.admit(.applicationAuthentication)
        guard authority.phase == .awaitingRoleAuthentication,
              authority.observedHostFingerprint == requiredHostFingerprint else {
            throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
        }
        self.evidence = evidence
        hostFingerprint = requiredHostFingerprint
    }
}

public struct NetworkClientHandshakeStartV0: Equatable, Sendable {
    public let clientNonce: WireBytes32
    public let helloMessageID: WireUUID
    public let proofMessageID: WireUUID
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64

    public init(
        clientNonce: WireBytes32,
        helloMessageID: WireUUID,
        proofMessageID: WireUUID,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        guard helloMessageID != proofMessageID,
              wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger,
              monotonicNowMilliseconds <= UInt64(Int64.max) else {
            throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
        }
        self.clientNonce = clientNonce
        self.helloMessageID = helloMessageID
        self.proofMessageID = proofMessageID
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

public struct NetworkClientClockSnapshotV0: Equatable, Sendable {
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64

    public init(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) {
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

enum NetworkClientPrimaryFrameIOStateV0: Equatable, Sendable {
    case ready
    case failed
    case cancelled
    case invalid
}

protocol NetworkClientPrimaryFrameIOV0: Sendable {
    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkClientPrimaryFrameIOStateV0
        ) -> Void
    )
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

private final class NetworkClientPrimaryNWFrameIOV0:
    NetworkClientPrimaryFrameIOV0,
    @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkClientPrimaryFrameIOStateV0
        ) -> Void
    ) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                handler(.ready)
            case .failed, .waiting:
                handler(.failed)
            case .cancelled:
                handler(.cancelled)
            case .setup, .preparing:
                handler(.invalid)
            @unknown default:
                handler(.invalid)
            }
        }
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
                                NetworkClientPrimaryFramePumpErrorV0.sendFailed
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

/// Serialized byte pump for a Network connection that is already live and was
/// accepted by the platform TLS callback represented by `tlsHandoff`. It does
/// not call `NWConnection.start`; ownership is transferred only after `.ready`.
/// The pump independently replays the same evidence through the client session
/// before sending `auth.hello`, then owns handshake correlation, framed
/// backpressure, authentication timeout, and later command-frame admission.
public actor NetworkClientPrimaryFramePumpV0 {
    public static let maximumReceiveChunkBytes = 16_384

    public let tlsHandoff: NetworkClientApplicationTLSHandoffV0

    private let io: any NetworkClientPrimaryFrameIOV0
    private let session: ClientPrimarySessionV0
    private let clock: @Sendable () -> NetworkClientClockSnapshotV0
    private let authenticated: @Sendable (
        ClientAuthenticatedSessionV0
    ) async throws -> Void
    private let readyForAuthenticatedTraffic: @Sendable () -> Void
    private let receivedCommand: @Sendable (Data) async throws -> Void
    private let terminal: @Sendable (NetworkClientPrimaryTerminationReasonV0) -> Void
    private let routeMessageID: @Sendable () -> WireUUID
    private let routeSleep: @Sendable (UInt64) async throws -> Void
    private var decoder = LengthPrefixedFrameDecoder()
    private var started = false
    private var stopped = false
    private var proofMessageID: WireUUID?
    private var deadlineTask: Task<Void, Never>?
    private var sendTail: Task<Void, Error>?
    private var routeHeartbeatTask: Task<Void, Never>?
    private var routeAcknowledgementTask: Task<Void, Never>?
    private var awaitingRouteAcknowledgement = false

    public init(
        connection: NWConnection,
        tlsHandoff: NetworkClientApplicationTLSHandoffV0,
        session: ClientPrimarySessionV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        authenticated: @escaping @Sendable (
            ClientAuthenticatedSessionV0
        ) async throws -> Void = { _ in },
        readyForAuthenticatedTraffic: @escaping @Sendable () -> Void = {},
        receivedCommand: @escaping @Sendable (Data) async throws -> Void,
        routeMessageID: @escaping @Sendable () -> WireUUID = {
            WireUUID(UUID())
        },
        terminal: @escaping @Sendable (
            NetworkClientPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) {
        io = NetworkClientPrimaryNWFrameIOV0(connection: connection)
        self.tlsHandoff = tlsHandoff
        self.session = session
        self.clock = clock
        self.authenticated = authenticated
        self.readyForAuthenticatedTraffic = readyForAuthenticatedTraffic
        self.receivedCommand = receivedCommand
        self.routeMessageID = routeMessageID
        routeSleep = { try await Task.sleep(nanoseconds: $0) }
        self.terminal = terminal
    }

    init(
        io: any NetworkClientPrimaryFrameIOV0,
        tlsHandoff: NetworkClientApplicationTLSHandoffV0,
        session: ClientPrimarySessionV0,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        authenticated: @escaping @Sendable (
            ClientAuthenticatedSessionV0
        ) async throws -> Void = { _ in },
        readyForAuthenticatedTraffic: @escaping @Sendable () -> Void = {},
        receivedCommand: @escaping @Sendable (Data) async throws -> Void,
        routeMessageID: @escaping @Sendable () -> WireUUID = {
            WireUUID(UUID())
        },
        routeSleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        },
        terminal: @escaping @Sendable (
            NetworkClientPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.tlsHandoff = tlsHandoff
        self.session = session
        self.clock = clock
        self.authenticated = authenticated
        self.readyForAuthenticatedTraffic = readyForAuthenticatedTraffic
        self.receivedCommand = receivedCommand
        self.routeMessageID = routeMessageID
        self.routeSleep = routeSleep
        self.terminal = terminal
    }

    public func beginOnVerifiedReadyConnection(
        _ start: NetworkClientHandshakeStartV0
    ) async throws {
        guard !started, !stopped,
              await session.requiredHostFingerprint
                == tlsHandoff.hostFingerprint else {
            throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
        }
        started = true
        proofMessageID = start.proofMessageID
        do {
            try await session.didConnectTCP(
                at: start.monotonicNowMilliseconds
            )
            try await session.acceptPinnedPeer(
                tlsHandoff.evidence,
                at: start.monotonicNowMilliseconds
            )
            let hello = try await session.beginAuthentication(
                clientNonce: start.clientNonce,
                messageID: start.helloMessageID,
                sentAtUnixMilliseconds: start.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: start.monotonicNowMilliseconds
            )
            io.setStateUpdateHandler { [weak self] state in
                Task { await self?.connectionStateChanged(state) }
            }
            awaitAuthenticationDeadline()
            try await enqueueSend(
                LengthPrefixedFrameDecoder.encode(hello)
            )
            receiveNext()
        } catch {
            await stop(reason: .protocolOrSessionFailure)
            throw error
        }
    }

    public func sendAuthenticatedCommand(_ frame: Data) async throws {
        guard started, !stopped,
              await session.phase == .authenticated else {
            throw NetworkClientPrimaryFramePumpErrorV0.connectionClosed
        }
        do {
            try await session.admitAuthenticatedTraffic(.commandFrame)
            try await enqueueSend(
                LengthPrefixedFrameDecoder.encode(frame)
            )
        } catch {
            await stop(reason: .protocolOrSessionFailure)
            throw error
        }
    }

    public func cancel() async {
        await stop(reason: .localCancel)
    }

    private func connectionStateChanged(
        _ state: NetworkClientPrimaryFrameIOStateV0
    ) async {
        guard !stopped else { return }
        switch state {
        case .ready:
            break
        case .failed:
            await stop(reason: .connectionFailed)
        case .cancelled:
            await stop(reason: .connectionCancelled, cancelIO: false)
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
                for frame in frames { try await process(frame) }
            }
            if isComplete {
                await stop(reason: .remoteClosed)
            } else {
                receiveNext()
            }
        } catch {
            await stop(reason: Self.terminationReason(for: error))
        }
    }

    public static func terminationReason(
        for error: any Error
    ) -> NetworkClientPrimaryTerminationReasonV0 {
        guard let sessionError = error as? ClientPrimarySessionErrorV0 else {
            return .protocolOrSessionFailure
        }
        if case .remoteError = sessionError {
            return .authenticationDenied
        }
        return .protocolOrSessionFailure
    }

    private func process(_ frame: Data) async throws {
        let now = clock()
        switch await session.phase {
        case .awaitingChallenge:
            guard let proofMessageID else {
                throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
            }
            let proof = try await session.receiveChallenge(
                frame,
                proofMessageID: proofMessageID,
                sentAtUnixMilliseconds: now.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: now.monotonicNowMilliseconds
            )
            try await enqueueSend(
                LengthPrefixedFrameDecoder.encode(proof)
            )
            awaitAuthenticationDeadline()
        case .awaitingDescription:
            let result = try await session.receiveSessionDescription(
                frame,
                monotonicNowMilliseconds: now.monotonicNowMilliseconds
            )
            deadlineTask?.cancel()
            deadlineTask = nil
            try await authenticated(result)
            try await sendRouteObservationIfConfigured(now: now)
            readyForAuthenticatedTraffic()
        case .authenticated:
            if try WireCodec.messageKind(from: frame)
                == .routeObservationAck {
                guard awaitingRouteAcknowledgement else {
                    throw NetworkClientPrimaryFramePumpErrorV0
                        .invalidConfiguration
                }
                try await session.receiveConfiguredRouteAcknowledgement(
                    frame,
                    monotonicNowMilliseconds:
                        now.monotonicNowMilliseconds
                )
                awaitingRouteAcknowledgement = false
                routeAcknowledgementTask?.cancel()
                routeAcknowledgementTask = nil
                scheduleRouteHeartbeat()
            } else {
                try await session.admitAuthenticatedTraffic(.commandFrame)
                try await receivedCommand(frame)
            }
        default:
            throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
        }
    }

    private func enqueueSend(_ data: Data) async throws {
        let predecessor = sendTail
        let io = self.io
        let operation = Task {
            if let predecessor {
                try await predecessor.value
            }
            try await io.send(data)
        }
        sendTail = operation
        try await operation.value
    }

    private func stop(
        reason: NetworkClientPrimaryTerminationReasonV0,
        cancelIO: Bool = true
    ) async {
        guard !stopped else { return }
        stopped = true
        deadlineTask?.cancel()
        deadlineTask = nil
        routeHeartbeatTask?.cancel()
        routeHeartbeatTask = nil
        routeAcknowledgementTask?.cancel()
        routeAcknowledgementTask = nil
        awaitingRouteAcknowledgement = false
        if cancelIO { io.cancel() }
        await session.close()
        terminal(reason)
    }

    private func awaitAuthenticationDeadline() {
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            guard let self,
                  let deadline = await self.session
                    .nextAuthenticationDeadlineMonotonicMilliseconds()
            else { return }
            let now = self.clock().monotonicNowMilliseconds
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
            await self.authenticationDeadlineReached()
        }
    }

    private func authenticationDeadlineReached() async {
        guard !stopped else { return }
        let expired = await session.expireAuthenticationIfRequired(
            at: clock().monotonicNowMilliseconds
        )
        if expired {
            await stop(reason: .authenticationDeadline)
        } else {
            awaitAuthenticationDeadline()
        }
    }

    private func sendRouteObservationIfConfigured(
        now: NetworkClientClockSnapshotV0
    ) async throws {
        guard !awaitingRouteAcknowledgement else {
            throw NetworkClientPrimaryFramePumpErrorV0.invalidConfiguration
        }
        guard let request = try await session.beginConfiguredRouteObservation(
            messageID: routeMessageID(),
            sentAtUnixMilliseconds: now.wallNowUnixMilliseconds,
            monotonicNowMilliseconds: now.monotonicNowMilliseconds
        ) else {
            return
        }
        awaitingRouteAcknowledgement = true
        try await enqueueSend(LengthPrefixedFrameDecoder.encode(request))
        scheduleRouteAcknowledgementDeadline()
    }

    private func scheduleRouteHeartbeat() {
        routeHeartbeatTask?.cancel()
        routeHeartbeatTask = Task { [weak self] in
            guard let self,
                  let deadline = await self.session
                    .nextRouteObservationDeadlineMonotonicMilliseconds()
            else { return }
            let now = self.clock().monotonicNowMilliseconds
            let delay = deadline > now ? deadline - now : 0
            do {
                try await self.routeSleep(
                    min(delay, UInt64.max / 1_000_000) * 1_000_000
                )
            } catch {
                return
            }
            await self.routeHeartbeatReached()
        }
    }

    private func routeHeartbeatReached() async {
        guard !stopped else { return }
        do {
            try await sendRouteObservationIfConfigured(now: clock())
        } catch {
            await stop(reason: .protocolOrSessionFailure)
        }
    }

    private func scheduleRouteAcknowledgementDeadline() {
        routeAcknowledgementTask?.cancel()
        routeAcknowledgementTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.routeSleep(30_000_000_000)
            } catch {
                return
            }
            await self.routeAcknowledgementDeadlineReached()
        }
    }

    private func routeAcknowledgementDeadlineReached() async {
        guard !stopped, awaitingRouteAcknowledgement else { return }
        await stop(reason: .protocolOrSessionFailure)
    }
}
