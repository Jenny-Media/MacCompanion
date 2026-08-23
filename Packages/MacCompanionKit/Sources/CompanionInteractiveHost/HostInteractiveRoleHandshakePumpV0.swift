import CompanionDomain
import CompanionInteractiveWire
import CompanionWire
import Foundation

public enum HostInteractiveRoleHandshakePumpErrorV0:
    Error, Equatable, Sendable
{
    case alreadyStarted
    case invalidConfiguration
    case invalidClock
    case invalidFrameLength(UInt32)
    case invalidRead
    case remoteClosed
    case deadlineExceeded
    case sendFailed
    case authorityRejected
    case cancelled
}

public struct HostInteractiveRoleReadChunkV0: Equatable, Sendable {
    public let data: Data
    public let isComplete: Bool

    public init(data: Data, isComplete: Bool = false) {
        self.data = data
        self.isComplete = isComplete
    }
}

/// Exact-read boundary for one already-verified secondary TLS connection.
/// The first hello has already been removed by the ingress classifier; later
/// reads are sized to the outstanding proof prefix/body only.
public protocol HostInteractiveRoleHandshakeIOV0: Sendable {
    func receive(maximumLength: Int) async throws
        -> HostInteractiveRoleReadChunkV0
    func send(_ data: Data) async throws
    func cancel()
}

/// The Agent retains both one-time credentials behind this serialized facet.
/// A handshake owner can challenge, consume, or invalidate one exact offered
/// role but can never take or inspect credential bytes.
public protocol HostInteractiveChannelAuthenticatingV0: Sendable {
    func beginInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        hostNonce: WireBytes32,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelChallengeBody

    func consumeInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        proof: InteractiveChannelProofBody,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelAcceptedBody

    func invalidateInteractiveChannel(
        channelID: UUID,
        role: InteractiveChannelRoleName
    ) async
}

public struct HostInteractiveReadyRoleChannelV0: Equatable, Sendable {
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName
    public let clientID: WireUUID
    public let primaryConnectionID: WireBytes16
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch

    public init(hello: InteractiveChannelHelloBody) {
        channelID = hello.channelID
        role = hello.role
        clientID = hello.clientID
        primaryConnectionID = hello.primaryConnectionID
        interactiveSessionID = hello.interactiveSessionID
        authorizationEpoch = hello.authorizationEpoch
    }
}

public enum HostInteractiveRoleHandshakePumpPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case authenticating
    case ready
    case closed
}

/// Host counterpart to the client role pump. It owns exact framing and
/// correlation while the Agent-owned authenticator retains credential state.
public actor HostInteractiveRoleHandshakePumpV0 {
    public static let maximumHandshakeJSONBytes = 4_096
    public static let maximumHandshakeMilliseconds: UInt64 = 30_000

    public private(set) var phase:
        HostInteractiveRoleHandshakePumpPhaseV0 = .idle

    private let io: any HostInteractiveRoleHandshakeIOV0
    private let authenticator: any HostInteractiveChannelAuthenticatingV0
    private let initialHelloFrame: Data
    private let clock: @Sendable () -> UInt64
    private let hostNonce: @Sendable () throws -> WireBytes32
    private let messageID: @Sendable () -> WireUUID
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let terminal: @Sendable (
        HostInteractiveRoleHandshakePumpErrorV0
    ) -> Void
    private var deadlineTask: Task<Void, Never>?
    private var lastMonotonicMilliseconds: UInt64?
    private var deadlineMonotonicMilliseconds: UInt64?
    private var hello: InteractiveChannelHelloBody?
    private var terminalReason:
        HostInteractiveRoleHandshakePumpErrorV0?

    public init(
        io: any HostInteractiveRoleHandshakeIOV0,
        initialHelloFrame: Data,
        authenticator: any HostInteractiveChannelAuthenticatingV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        hostNonce: @escaping @Sendable () throws -> WireBytes32,
        messageID: @escaping @Sendable () -> WireUUID,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.initialHelloFrame = initialHelloFrame
        self.authenticator = authenticator
        clock = monotonicNowMilliseconds
        self.hostNonce = hostNonce
        self.messageID = messageID
        sleep = { try await Task.sleep(nanoseconds: $0) }
        self.terminal = terminal
    }

    init(
        io: any HostInteractiveRoleHandshakeIOV0,
        initialHelloFrame: Data,
        authenticator: any HostInteractiveChannelAuthenticatingV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        hostNonce: @escaping @Sendable () throws -> WireBytes32,
        messageID: @escaping @Sendable () -> WireUUID,
        sleep: @escaping @Sendable (UInt64) async throws -> Void,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.initialHelloFrame = initialHelloFrame
        self.authenticator = authenticator
        clock = monotonicNowMilliseconds
        self.hostNonce = hostNonce
        self.messageID = messageID
        self.sleep = sleep
        self.terminal = terminal
    }

    public func beginOnClassifiedConnection() async throws
        -> HostInteractiveReadyRoleChannelV0
    {
        guard phase == .idle else {
            throw HostInteractiveRoleHandshakePumpErrorV0.alreadyStarted
        }
        phase = .authenticating
        do {
            let startedAt = try observeClock()
            let (deadline, overflow) = startedAt.addingReportingOverflow(
                Self.maximumHandshakeMilliseconds
            )
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw HostInteractiveRoleHandshakePumpErrorV0.invalidClock
            }
            deadlineMonotonicMilliseconds = deadline
            scheduleDeadline()

            guard !initialHelloFrame.isEmpty,
                  initialHelloFrame.count
                    <= Self.maximumHandshakeJSONBytes else {
                throw HostInteractiveRoleHandshakePumpErrorV0
                    .invalidFrameLength(
                        UInt32(clamping: initialHelloFrame.count)
                    )
            }
            let helloEnvelope = try InteractiveChannelCodec.decode(
                InteractiveChannelEnvelope<
                    InteractiveChannelHelloBody
                >.self,
                from: initialHelloFrame
            )
            let hello = helloEnvelope.body
            self.hello = hello

            let challengeID = messageID()
            let acceptedID = messageID()
            guard challengeID != helloEnvelope.messageID,
                  acceptedID != helloEnvelope.messageID,
                  acceptedID != challengeID else {
                throw HostInteractiveRoleHandshakePumpErrorV0
                    .invalidConfiguration
            }
            let challengeBody = try await authenticator
                .beginInteractiveChannel(
                    hello: hello,
                    hostNonce: try hostNonce(),
                    monotonicNowMilliseconds: try observeClock()
                )
            let challenge = try InteractiveChannelEnvelope(
                messageID: challengeID,
                correlationID: helloEnvelope.messageID,
                body: challengeBody
            )
            try await sendHandshakeFrame(
                InteractiveChannelCodec.encode(challenge)
            )

            let proofFrame = try await readHandshakeFrame()
            let proof = try InteractiveChannelCodec.decode(
                InteractiveChannelEnvelope<
                    InteractiveChannelProofBody
                >.self,
                from: proofFrame
            )
            guard proof.correlationID == challengeID,
                  proof.messageID != helloEnvelope.messageID,
                  proof.messageID != challengeID,
                  proof.messageID != acceptedID else {
                throw HostInteractiveRoleHandshakePumpErrorV0
                    .invalidConfiguration
            }
            let acceptedBody = try await authenticator
                .consumeInteractiveChannel(
                    hello: hello,
                    proof: proof.body,
                    monotonicNowMilliseconds: try observeClock()
                )
            let accepted = try InteractiveChannelEnvelope(
                messageID: acceptedID,
                correlationID: proof.messageID,
                body: acceptedBody
            )
            try await sendHandshakeFrame(
                InteractiveChannelCodec.encode(accepted)
            )
            guard phase == .authenticating else {
                throw HostInteractiveRoleHandshakePumpErrorV0.cancelled
            }
            deadlineTask?.cancel()
            deadlineTask = nil
            phase = .ready
            return HostInteractiveReadyRoleChannelV0(hello: hello)
        } catch {
            if phase == .closed, let terminalReason {
                throw terminalReason
            }
            await failClosed(Self.pumpError(for: error))
            throw error
        }
    }

    public func admitRoleTraffic() throws {
        guard phase == .ready else {
            throw HostInteractiveRoleHandshakePumpErrorV0
                .invalidConfiguration
        }
    }

    public func cancel() async {
        guard phase != .closed else { return }
        await failClosed(.cancelled)
    }

    private func readHandshakeFrame() async throws -> Data {
        let prefix = try await readExactly(4)
        let length = prefix.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        guard (1...UInt32(Self.maximumHandshakeJSONBytes))
            .contains(length) else {
            throw HostInteractiveRoleHandshakePumpErrorV0
                .invalidFrameLength(length)
        }
        return try await readExactly(Int(length))
    }

    private func readExactly(_ count: Int) async throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            _ = try observeClock()
            guard phase == .authenticating else {
                throw HostInteractiveRoleHandshakePumpErrorV0.cancelled
            }
            let remaining = count - result.count
            let chunk: HostInteractiveRoleReadChunkV0
            do {
                chunk = try await io.receive(maximumLength: remaining)
            } catch {
                throw HostInteractiveRoleHandshakePumpErrorV0.invalidRead
            }
            _ = try observeClock()
            guard !chunk.data.isEmpty,
                  chunk.data.count <= remaining else {
                throw HostInteractiveRoleHandshakePumpErrorV0.invalidRead
            }
            result.append(chunk.data)
            if chunk.isComplete {
                throw HostInteractiveRoleHandshakePumpErrorV0.remoteClosed
            }
        }
        return result
    }

    private func sendHandshakeFrame(_ body: Data) async throws {
        guard !body.isEmpty,
              body.count <= Self.maximumHandshakeJSONBytes else {
            throw HostInteractiveRoleHandshakePumpErrorV0
                .invalidFrameLength(UInt32(clamping: body.count))
        }
        let length = UInt32(body.count)
        let frame = Data([
            UInt8(length >> 24),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ]) + body
        do {
            try await io.send(frame)
        } catch {
            throw HostInteractiveRoleHandshakePumpErrorV0.sendFailed
        }
    }

    private func observeClock() throws -> UInt64 {
        let now = clock()
        guard now <= UInt64(Int64.max),
              lastMonotonicMilliseconds.map({ now >= $0 }) ?? true else {
            throw HostInteractiveRoleHandshakePumpErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = now
        if phase == .authenticating,
           let deadlineMonotonicMilliseconds,
           now >= deadlineMonotonicMilliseconds {
            throw HostInteractiveRoleHandshakePumpErrorV0.deadlineExceeded
        }
        return now
    }

    private func scheduleDeadline() {
        guard let deadline = deadlineMonotonicMilliseconds else { return }
        let now = clock()
        let delayMilliseconds = deadline > now ? deadline - now : 0
        let delayNanoseconds = min(
            delayMilliseconds,
            UInt64.max / 1_000_000
        ) * 1_000_000
        deadlineTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(delayNanoseconds)
            } catch {
                return
            }
            await self.deadlineReached()
        }
    }

    private func deadlineReached() async {
        guard phase == .authenticating else { return }
        await failClosed(.deadlineExceeded)
    }

    private func failClosed(
        _ reason: HostInteractiveRoleHandshakePumpErrorV0
    ) async {
        guard phase != .closed else { return }
        phase = .closed
        terminalReason = reason
        deadlineTask?.cancel()
        deadlineTask = nil
        io.cancel()
        if let hello {
            await authenticator.invalidateInteractiveChannel(
                channelID: hello.channelID.rawValue,
                role: hello.role
            )
        }
        terminal(reason)
    }

    private static func pumpError(
        for error: any Error
    ) -> HostInteractiveRoleHandshakePumpErrorV0 {
        if let value = error as?
            HostInteractiveRoleHandshakePumpErrorV0 {
            return value
        }
        if error is InteractiveSecurityAuthorityError {
            return .authorityRejected
        }
        return .invalidConfiguration
    }
}
