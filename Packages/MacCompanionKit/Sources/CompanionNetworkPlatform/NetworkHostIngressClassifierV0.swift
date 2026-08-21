import CompanionTransport
import CompanionWire
import Foundation
import Network

public enum NetworkHostIngressRoleV0: String, Equatable, Sendable {
    case applicationPrimary
    case pairing
}

public enum NetworkHostIngressClassifierErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case alreadyStarted
    case invalidClock
    case deadlineExpired
    case receiveFailed
    case remoteClosed
    case protocolFailure
    case unexpectedFirstMessage(WireMessageKind)
    case classifiedConnectionAlreadyConsumed
    case roleMismatch
    case sendFailed
}

struct NetworkHostIngressFrameChunkV0: Sendable {
    let data: Data
    let isComplete: Bool
}

protocol NetworkHostIngressFrameIOV0: Sendable {
    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
    func send(_ data: Data) async throws
    func cancel()
}

private final class NetworkHostIngressNWFrameIOV0:
    NetworkHostIngressFrameIOV0,
    @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
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
                                NetworkHostIngressClassifierErrorV0
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
                                    NetworkHostIngressClassifierErrorV0
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

    func cancel() {
        connection.cancel()
    }
}

struct NetworkHostConsumedClassifiedConnectionV0: Sendable {
    let io: any NetworkHostIngressFrameIOV0
    let tlsBinding: HostApplicationTLSBinding
    let initialFrame: Data
}

/// Opaque one-use authority for the exact verified TLS connection and first
/// application frame. Only this module can construct or consume its byte I/O.
public final class NetworkHostClassifiedConnectionV0: @unchecked Sendable {
    public let role: NetworkHostIngressRoleV0
    public let tlsBinding: HostApplicationTLSBinding

    private let lock = NSLock()
    private var io: (any NetworkHostIngressFrameIOV0)?
    private var initialFrame: Data?

    init(
        role: NetworkHostIngressRoleV0,
        tlsBinding: HostApplicationTLSBinding,
        io: any NetworkHostIngressFrameIOV0,
        initialFrame: Data
    ) {
        self.role = role
        self.tlsBinding = tlsBinding
        self.io = io
        self.initialFrame = initialFrame
    }

    func consume(
        expectedRole: NetworkHostIngressRoleV0
    ) throws -> NetworkHostConsumedClassifiedConnectionV0 {
        try lock.withLock {
            guard role == expectedRole else {
                throw NetworkHostIngressClassifierErrorV0.roleMismatch
            }
            guard let io, let initialFrame else {
                throw NetworkHostIngressClassifierErrorV0
                    .classifiedConnectionAlreadyConsumed
            }
            self.io = nil
            self.initialFrame = nil
            return NetworkHostConsumedClassifiedConnectionV0(
                io: io,
                tlsBinding: tlsBinding,
                initialFrame: initialFrame
            )
        }
    }

    public func cancel() {
        let io = lock.withLock { () -> (any NetworkHostIngressFrameIOV0)? in
            let io = self.io
            self.io = nil
            initialFrame = nil
            return io
        }
        io?.cancel()
    }
}

/// Reads exactly one frame from an already verified-ready connection and
/// classifies only `auth.hello` or `pairing.begin`. Reads are sized to the
/// outstanding prefix/payload byte count, so a second frame is never consumed.
public actor NetworkHostIngressClassifierV0 {
    public static let maximumClassificationMilliseconds: UInt64 = 10_000

    public let tlsBinding: HostApplicationTLSBinding

    private let io: any NetworkHostIngressFrameIOV0
    private let monotonicNowMilliseconds: @Sendable () -> UInt64
    private let deadlineMonotonicMilliseconds: UInt64
    private var lastMonotonicMilliseconds: UInt64
    private var started = false
    private var stopped = false
    private var deadlineTask: Task<Void, Never>?

    public init(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) throws {
        let (deadline, overflow) = acceptedAtMonotonicMilliseconds
            .addingReportingOverflow(
                Self.maximumClassificationMilliseconds
            )
        guard acceptedAtMonotonicMilliseconds <= UInt64(Int64.max),
              !overflow,
              deadline <= UInt64(Int64.max) else {
            throw NetworkHostIngressClassifierErrorV0.invalidConfiguration
        }
        let connection = try verifiedReadyConnection.consumeConnection()
        io = NetworkHostIngressNWFrameIOV0(connection: connection)
        tlsBinding = verifiedReadyConnection.tlsBinding
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        deadlineMonotonicMilliseconds = deadline
        lastMonotonicMilliseconds = acceptedAtMonotonicMilliseconds
    }

    init(
        io: any NetworkHostIngressFrameIOV0,
        tlsBinding: HostApplicationTLSBinding,
        acceptedAtMonotonicMilliseconds: UInt64,
        maximumClassificationMilliseconds: UInt64 =
            NetworkHostIngressClassifierV0
                .maximumClassificationMilliseconds,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) throws {
        let (deadline, overflow) = acceptedAtMonotonicMilliseconds
            .addingReportingOverflow(maximumClassificationMilliseconds)
        guard acceptedAtMonotonicMilliseconds <= UInt64(Int64.max),
              maximumClassificationMilliseconds > 0,
              !overflow,
              deadline <= UInt64(Int64.max) else {
            throw NetworkHostIngressClassifierErrorV0.invalidConfiguration
        }
        self.io = io
        self.tlsBinding = tlsBinding
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        deadlineMonotonicMilliseconds = deadline
        lastMonotonicMilliseconds = acceptedAtMonotonicMilliseconds
    }

    public func classify() async throws
        -> NetworkHostClassifiedConnectionV0
    {
        guard !started else {
            throw NetworkHostIngressClassifierErrorV0.alreadyStarted
        }
        started = true
        do {
            try observeClock()
            scheduleDeadline()
            let prefix = try await readExactly(4)
            let length = prefix.reduce(UInt32(0)) {
                ($0 << 8) | UInt32($1)
            }
            guard length > 0,
                  length <= UInt32(WireLimits.maximumFrameBytes) else {
                throw NetworkHostIngressClassifierErrorV0.protocolFailure
            }
            let frame = try await readExactly(Int(length))
            try observeClock()
            let kind = try WireCodec.messageKind(from: frame)
            let role: NetworkHostIngressRoleV0
            switch kind {
            case .authHello:
                role = .applicationPrimary
            case .pairingBegin:
                role = .pairing
            default:
                throw NetworkHostIngressClassifierErrorV0
                    .unexpectedFirstMessage(kind)
            }
            guard !stopped else {
                throw NetworkHostIngressClassifierErrorV0.deadlineExpired
            }
            stopped = true
            deadlineTask?.cancel()
            deadlineTask = nil
            return NetworkHostClassifiedConnectionV0(
                role: role,
                tlsBinding: tlsBinding,
                io: io,
                initialFrame: frame
            )
        } catch {
            failClosed()
            if let error = error as? NetworkHostIngressClassifierErrorV0 {
                throw error
            }
            throw NetworkHostIngressClassifierErrorV0.protocolFailure
        }
    }

    public func cancel() {
        failClosed()
    }

    private func readExactly(_ count: Int) async throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            try observeClock()
            guard !stopped else {
                throw NetworkHostIngressClassifierErrorV0.deadlineExpired
            }
            let remaining = count - result.count
            let chunk: NetworkHostIngressFrameChunkV0
            do {
                chunk = try await io.receive(maximumLength: remaining)
            } catch {
                if stopped {
                    throw NetworkHostIngressClassifierErrorV0.deadlineExpired
                }
                throw NetworkHostIngressClassifierErrorV0.receiveFailed
            }
            try observeClock()
            guard !chunk.data.isEmpty,
                  chunk.data.count <= remaining else {
                throw NetworkHostIngressClassifierErrorV0.protocolFailure
            }
            result.append(chunk.data)
            if chunk.isComplete {
                throw NetworkHostIngressClassifierErrorV0.remoteClosed
            }
        }
        return result
    }

    private func observeClock() throws {
        let now = monotonicNowMilliseconds()
        guard now <= UInt64(Int64.max),
              now >= lastMonotonicMilliseconds else {
            throw NetworkHostIngressClassifierErrorV0.invalidClock
        }
        guard now < deadlineMonotonicMilliseconds else {
            throw NetworkHostIngressClassifierErrorV0.deadlineExpired
        }
        lastMonotonicMilliseconds = now
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        let now = monotonicNowMilliseconds()
        let delayMilliseconds = deadlineMonotonicMilliseconds > now
            ? deadlineMonotonicMilliseconds - now
            : 0
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: min(
                        delayMilliseconds,
                        UInt64.max / 1_000_000
                    ) * 1_000_000
                )
            } catch {
                return
            }
            await self?.deadlineReached()
        }
    }

    private func deadlineReached() {
        guard !stopped else { return }
        stopped = true
        io.cancel()
    }

    private func failClosed() {
        guard !stopped else { return }
        stopped = true
        deadlineTask?.cancel()
        deadlineTask = nil
        io.cancel()
    }
}
