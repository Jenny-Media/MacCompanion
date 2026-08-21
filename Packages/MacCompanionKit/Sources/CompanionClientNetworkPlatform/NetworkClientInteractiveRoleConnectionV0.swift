import CompanionDiscovery
import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Network

public enum NetworkClientInteractiveRoleConnectionErrorV0:
    Error, Equatable, Sendable
{
    case invalidConfiguration
    case connectionFailed
    case tlsVerificationFailed
    case handshakeFailed
    case rolePairFailed
    case primaryReplaced
    case alreadyStarted
}

private final class NetworkClientInteractiveRoleNWIOV0:
    ClientInteractiveRoleHandshakeIOV0, @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) { self.connection = connection }

    func receive(
        maximumLength: Int
    ) async throws -> ClientInteractiveRoleReadChunkV0 {
        guard maximumLength > 0 else {
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        }
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<
                ClientInteractiveRoleReadChunkV0, any Error
            >) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning:
                        ClientInteractiveRoleReadChunkV0(
                            data: data ?? Data(),
                            isComplete: isComplete
                        )
                    )
                }
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    func cancel() { connection.cancel() }
}

package struct NetworkClientInteractiveReadyRoleConnectionV0: Sendable {
    package let endpoint: EndpointCandidate
    package let role: InteractiveChannelRoleName
    package let channelID: WireUUID
    private let receiveOperation: @Sendable (
        Int
    ) async throws -> ClientInteractiveRoleReadChunkV0
    private let sendOperation: @Sendable (Data) async throws -> Void
    private let cancelOperation: @Sendable () async -> Void

    package init(
        endpoint: EndpointCandidate,
        role: InteractiveChannelRoleName,
        channelID: WireUUID,
        receive: @escaping @Sendable (
            Int
        ) async throws -> ClientInteractiveRoleReadChunkV0 = { _ in
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        },
        send: @escaping @Sendable (Data) async throws -> Void = { _ in
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        },
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.endpoint = endpoint
        self.role = role
        self.channelID = channelID
        receiveOperation = receive
        sendOperation = send
        cancelOperation = cancel
    }

    package func receiveRoleBytes(
        maximumLength: Int
    ) async throws -> ClientInteractiveRoleReadChunkV0 {
        try await receiveOperation(maximumLength)
    }

    package func sendRoleBytes(_ value: Data) async throws {
        try await sendOperation(value)
    }

    package func cancel() async { await cancelOperation() }
}

package protocol NetworkClientInteractiveRoleConnectingV0: Sendable {
    func connect(
        endpoint: EndpointCandidate,
        session: ClientInteractiveAcceptedSessionV0,
        role: InteractiveChannelRoleName
    ) async throws -> NetworkClientInteractiveReadyRoleConnectionV0
}

/// Concrete one-role connector. It creates exactly one TLS 1.3 connection on
/// the supplied selected endpoint, consumes evidence only from that exact
/// connection, then transfers byte ownership to the exact-read role pump.
package struct NetworkClientInteractiveRoleConnectorV0:
    NetworkClientInteractiveRoleConnectingV0, Sendable
{
    package typealias Nonce = @Sendable () throws -> WireBytes32
    package typealias MessageID = @Sendable () -> WireUUID

    private let pinnedLeafEvaluator: NetworkClientPinnedLeafEvaluatorV0
    private let verificationQueue: DispatchQueue
    private let connectionQueue: DispatchQueue
    private let monotonicNowMilliseconds: @Sendable () -> UInt64
    private let nonce: Nonce
    private let messageID: MessageID

    package init(
        pinnedLeafEvaluator: @escaping NetworkClientPinnedLeafEvaluatorV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        nonce: @escaping Nonce,
        messageID: @escaping MessageID
    ) {
        self.pinnedLeafEvaluator = pinnedLeafEvaluator
        self.verificationQueue = verificationQueue
        self.connectionQueue = connectionQueue
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.nonce = nonce
        self.messageID = messageID
    }

    package func connect(
        endpoint: EndpointCandidate,
        session: ClientInteractiveAcceptedSessionV0,
        role: InteractiveChannelRoleName
    ) async throws -> NetworkClientInteractiveReadyRoleConnectionV0 {
        let context: NetworkClientTLSAttemptContextV0
        let connection: NWConnection
        do {
            context = try NetworkClientTLSAttemptContextV0(
                endpoint: endpoint,
                requiredHostFingerprint: session.primary.hostFingerprint,
                verificationQueue: verificationQueue,
                pinnedLeafEvaluator: pinnedLeafEvaluator
            )
            connection = try context.makeUnstartedConnection()
        } catch {
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        }

        return try await withTaskCancellationHandler {
            let readiness = NetworkClientConnectionReadinessLatchV0()
            connection.stateUpdateHandler = { readiness.observe($0) }
            connection.start(queue: connectionQueue)
            let ready = await readiness.wait(timeoutMilliseconds: Int64(
                ClientInteractiveChannelAuthorityV0
                    .maximumUnusedLifetimeMilliseconds
            ))
            guard ready == .ready, !Task.isCancelled else {
                connection.cancel()
                throw NetworkClientInteractiveRoleConnectionErrorV0
                    .connectionFailed
            }
            connection.stateUpdateHandler = nil

            let evidence: TLSPeerEvidence
            let startNonce: WireBytes32
            let helloID: WireUUID
            let proofID: WireUUID
            do {
                evidence = try context.consumeVerifiedPeerEvidence(
                    for: connection
                )
                startNonce = try nonce()
                helloID = messageID()
                proofID = messageID()
                guard helloID != proofID else {
                    throw NetworkClientInteractiveRoleConnectionErrorV0
                        .invalidConfiguration
                }
            } catch {
                connection.cancel()
                throw NetworkClientInteractiveRoleConnectionErrorV0
                    .tlsVerificationFailed
            }

            let io = NetworkClientInteractiveRoleNWIOV0(
                connection: connection
            )
            let authority: ClientInteractiveChannelAuthorityV0
            do {
                authority = try ClientInteractiveChannelAuthorityV0(
                    session: session,
                    role: role
                )
            } catch {
                connection.cancel()
                throw NetworkClientInteractiveRoleConnectionErrorV0
                    .invalidConfiguration
            }
            let pump = ClientInteractiveRoleHandshakePumpV0(
                io: io,
                authority: authority,
                evidence: evidence,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            do {
                let handoff = try await pump.beginOnVerifiedReadyConnection(
                    clientNonce: startNonce,
                    helloMessageID: helloID,
                    proofMessageID: proofID
                )
                guard handoff.role == role else {
                    await pump.cancel()
                    throw NetworkClientInteractiveRoleConnectionErrorV0
                        .handshakeFailed
                }
                return NetworkClientInteractiveReadyRoleConnectionV0(
                    endpoint: endpoint,
                    role: role,
                    channelID: handoff.channelID,
                    receive: { maximumLength in
                        try await pump.admitRoleTraffic()
                        return try await io.receive(
                            maximumLength: maximumLength
                        )
                    },
                    send: { value in
                        try await pump.admitRoleTraffic()
                        try await io.send(value)
                    },
                    cancel: { await pump.cancel() }
                )
            } catch {
                await pump.cancel()
                throw NetworkClientInteractiveRoleConnectionErrorV0
                    .handshakeFailed
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

package struct NetworkClientInteractiveReadyRolePairV0: Sendable {
    package let endpoint: EndpointCandidate
    package let input: NetworkClientInteractiveReadyRoleConnectionV0
    package let media: NetworkClientInteractiveReadyRoleConnectionV0
}

package protocol NetworkClientInteractiveRolePairOwningV0: Sendable {
    func connect() async throws -> NetworkClientInteractiveReadyRolePairV0
    func primaryTerminated(hostID: UUID, connectionID: Data) async
    func close() async
}

/// All-or-none owner for the two role connections from one accepted session.
/// A current-primary callback is sampled before dialing and again after both
/// proofs complete. Any failure or replacement closes every connection that
/// reached ready and publishes no pair.
package actor NetworkClientInteractiveRolePairOwnerV0 {
    package enum Phase: String, Equatable, Sendable {
        case idle
        case connecting
        case ready
        case closed
    }

    package private(set) var phase: Phase = .idle

    private let composition: NetworkClientInteractiveRoleCompositionV0
    private let connector: any NetworkClientInteractiveRoleConnectingV0
    private let isCurrent: @Sendable (UUID, Data) -> Bool
    private var readyPair: NetworkClientInteractiveReadyRolePairV0?

    package init(
        composition: NetworkClientInteractiveRoleCompositionV0,
        connector: any NetworkClientInteractiveRoleConnectingV0,
        isCurrent: @escaping @Sendable (UUID, Data) -> Bool
    ) {
        self.composition = composition
        self.connector = connector
        self.isCurrent = isCurrent
    }

    package func connect() async throws
        -> NetworkClientInteractiveReadyRolePairV0
    {
        guard phase == .idle else {
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .alreadyStarted
        }
        guard currentPrimary() else {
            phase = .closed
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .primaryReplaced
        }
        phase = .connecting

        let endpoint = composition.endpoint
        let session = composition.interactiveSession
        let connector = self.connector
        let outcomes = await withTaskGroup(
            of: RoleOutcome.self,
            returning: [RoleOutcome].self
        ) { group in
            for role in [InteractiveChannelRoleName.input, .media] {
                group.addTask {
                    do {
                        return .ready(try await connector.connect(
                            endpoint: endpoint,
                            session: session,
                            role: role
                        ))
                    } catch {
                        return .failed
                    }
                }
            }
            var values: [RoleOutcome] = []
            while let value = await group.next() {
                values.append(value)
                if case .failed = value { group.cancelAll() }
            }
            return values
        }

        let ready = outcomes.compactMap { outcome in
            if case let .ready(value) = outcome { return value }
            return nil
        }
        guard outcomes.count == 2,
              ready.count == 2,
              let input = ready.first(where: { $0.role == .input }),
              let media = ready.first(where: { $0.role == .media }),
              input.endpoint == endpoint,
              media.endpoint == endpoint,
              input.channelID == session.inputChannel.channelID,
              media.channelID == session.mediaChannel.channelID,
              input.channelID != media.channelID,
              currentPrimary() else {
            for connection in ready { await connection.cancel() }
            phase = .closed
            throw currentPrimary()
                ? NetworkClientInteractiveRoleConnectionErrorV0.rolePairFailed
                : NetworkClientInteractiveRoleConnectionErrorV0.primaryReplaced
        }
        let value = NetworkClientInteractiveReadyRolePairV0(
            endpoint: endpoint,
            input: input,
            media: media
        )
        readyPair = value
        phase = .ready
        return value
    }

    package func primaryTerminated(hostID: UUID, connectionID: Data) async {
        guard hostID == composition.authenticatedSession.hostID,
              connectionID
                == composition.authenticatedSession.connectionID else { return }
        await close()
    }

    package func close() async {
        guard phase != .closed else { return }
        phase = .closed
        if let readyPair {
            await readyPair.input.cancel()
            await readyPair.media.cancel()
        }
        readyPair = nil
    }

    private func currentPrimary() -> Bool {
        isCurrent(
            composition.authenticatedSession.hostID,
            composition.authenticatedSession.connectionID
        )
    }

    private enum RoleOutcome: Sendable {
        case ready(NetworkClientInteractiveReadyRoleConnectionV0)
        case failed
    }
}

extension NetworkClientInteractiveRolePairOwnerV0:
    NetworkClientInteractiveRolePairOwningV0 {}
