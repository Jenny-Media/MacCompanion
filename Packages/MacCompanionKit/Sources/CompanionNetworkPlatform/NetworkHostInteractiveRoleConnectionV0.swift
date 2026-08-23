import CompanionInteractiveHost
import CompanionInteractiveWire
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Security

public enum NetworkHostInteractiveRoleConnectionErrorV0:
    Error, Equatable, Sendable
{
    case invalidRole
    case invalidConfiguration
    case randomGenerationFailed
}

public struct NetworkHostInteractiveRoleTrafficChunkV0:
    Equatable, Sendable
{
    public let data: Data
    public let isComplete: Bool

    public init(data: Data, isComplete: Bool = false) {
        self.data = data
        self.isComplete = isComplete
    }
}

private final class NetworkHostInteractiveRoleClassifiedIOV0:
    HostInteractiveRoleHandshakeIOV0,
    @unchecked Sendable
{
    let underlying: any NetworkHostIngressFrameIOV0

    init(_ underlying: any NetworkHostIngressFrameIOV0) {
        self.underlying = underlying
    }

    func receive(maximumLength: Int) async throws
        -> HostInteractiveRoleReadChunkV0
    {
        let chunk = try await underlying.receive(
            maximumLength: maximumLength
        )
        return HostInteractiveRoleReadChunkV0(
            data: chunk.data,
            isComplete: chunk.isComplete
        )
    }

    func send(_ data: Data) async throws {
        try await underlying.send(data)
    }

    func cancel() { underlying.cancel() }
}

/// One exact role connection after host mutual proof. Byte operations remain
/// gated by the handshake owner, and the TLS/session fence travels with the
/// same one-use classified connection rather than caller-provided metadata.
public struct NetworkHostInteractiveReadyRoleConnectionV0: Sendable {
    public let tlsBinding: HostApplicationTLSBinding
    public let channel: HostInteractiveReadyRoleChannelV0

    private let receiveOperation: @Sendable (
        Int
    ) async throws -> NetworkHostInteractiveRoleTrafficChunkV0
    private let sendOperation: @Sendable (Data) async throws -> Void
    private let cancelOperation: @Sendable () async -> Void

    init(
        tlsBinding: HostApplicationTLSBinding,
        channel: HostInteractiveReadyRoleChannelV0,
        receive: @escaping @Sendable (
            Int
        ) async throws -> NetworkHostInteractiveRoleTrafficChunkV0,
        send: @escaping @Sendable (Data) async throws -> Void,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.tlsBinding = tlsBinding
        self.channel = channel
        receiveOperation = receive
        sendOperation = send
        cancelOperation = cancel
    }

    public func receiveRoleBytes(
        maximumLength: Int
    ) async throws -> NetworkHostInteractiveRoleTrafficChunkV0 {
        guard maximumLength > 0 else {
            throw NetworkHostInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        }
        return try await receiveOperation(maximumLength)
    }

    public func sendRoleBytes(_ data: Data) async throws {
        guard !data.isEmpty else {
            throw NetworkHostInteractiveRoleConnectionErrorV0
                .invalidConfiguration
        }
        try await sendOperation(data)
    }

    public func cancel() async { await cancelOperation() }
}

/// Consumes the classifier's one-use role connection and transfers it only
/// after the host handshake pump sends the exact accepted frame.
public actor NetworkHostInteractiveRoleConnectionV0 {
    public let tlsBinding: HostApplicationTLSBinding

    private let io: NetworkHostInteractiveRoleClassifiedIOV0
    private let pump: HostInteractiveRoleHandshakePumpV0
    private var started = false

    public init(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        authenticator: any HostInteractiveChannelAuthenticatingV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds / 1_000_000
        },
        hostNonce: @escaping @Sendable () throws -> WireBytes32 = {
            var bytes = Data(repeating: 0, count: 32)
            let status = bytes.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(
                    kSecRandomDefault,
                    buffer.count,
                    buffer.baseAddress!
                )
            }
            guard status == errSecSuccess else {
                throw NetworkHostInteractiveRoleConnectionErrorV0
                    .randomGenerationFailed
            }
            return try WireBytes32(bytes)
        },
        messageID: @escaping @Sendable () -> WireUUID = {
            WireUUID(UUID())
        },
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _ in }
    ) throws {
        let expectedRole: NetworkHostIngressRoleV0
        switch classifiedConnection.role {
        case .interactiveInput:
            expectedRole = .interactiveInput
        case .interactiveMedia:
            expectedRole = .interactiveMedia
        default:
            throw NetworkHostInteractiveRoleConnectionErrorV0.invalidRole
        }
        let consumed = try classifiedConnection.consume(
            expectedRole: expectedRole
        )
        let io = NetworkHostInteractiveRoleClassifiedIOV0(consumed.io)
        self.io = io
        tlsBinding = consumed.tlsBinding
        pump = HostInteractiveRoleHandshakePumpV0(
            io: io,
            initialHelloFrame: consumed.initialFrame,
            authenticator: authenticator,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            hostNonce: hostNonce,
            messageID: messageID,
            terminal: terminal
        )
    }

    public func beginOnClassifiedConnection() async throws
        -> NetworkHostInteractiveReadyRoleConnectionV0
    {
        guard !started else {
            throw HostInteractiveRoleHandshakePumpErrorV0.alreadyStarted
        }
        started = true
        let channel = try await pump.beginOnClassifiedConnection()
        return NetworkHostInteractiveReadyRoleConnectionV0(
            tlsBinding: tlsBinding,
            channel: channel,
            receive: { [pump, io] maximumLength in
                try await pump.admitRoleTraffic()
                let chunk = try await io.receive(
                    maximumLength: maximumLength
                )
                return NetworkHostInteractiveRoleTrafficChunkV0(
                    data: chunk.data,
                    isComplete: chunk.isComplete
                )
            },
            send: { [pump, io] data in
                try await pump.admitRoleTraffic()
                try await io.send(data)
            },
            cancel: { [pump] in await pump.cancel() }
        )
    }

    public func cancel() async { await pump.cancel() }
}
