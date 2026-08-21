import CompanionInteractiveWire
import CompanionTransport
import CompanionWire
import Foundation

public enum ClientInteractiveRoleHandshakePumpErrorV0:
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
    case cancelled
}

public struct ClientInteractiveRoleReadChunkV0: Equatable, Sendable {
    public let data: Data
    public let isComplete: Bool

    public init(data: Data, isComplete: Bool = false) {
        self.data = data
        self.isComplete = isComplete
    }
}

/// Exact-read transport boundary for one already-connected, already-verified
/// secondary TLS connection. Implementations must return no more than
/// `maximumLength`; the pump never asks for bytes beyond the current handshake
/// prefix or body, so the accepted frame cannot consume following role bytes.
public protocol ClientInteractiveRoleHandshakeIOV0: Sendable {
    func receive(maximumLength: Int) async throws
        -> ClientInteractiveRoleReadChunkV0
    func send(_ data: Data) async throws
    func cancel()
}

public struct ClientInteractiveReadyRoleChannelV0: Equatable, Sendable {
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName

    public init(channelID: WireUUID, role: InteractiveChannelRoleName) {
        self.channelID = channelID
        self.role = role
    }
}

public enum ClientInteractiveRoleHandshakePumpPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case authenticating
    case ready
    case closed
}

/// Serialized, bounded handshake pump. Cryptographic and role decisions remain
/// exclusively in `ClientInteractiveChannelAuthorityV0`; this owner supplies
/// exact framing, transport cancellation, and an independently scheduled
/// monotonic deadline.
public actor ClientInteractiveRoleHandshakePumpV0 {
    public static let maximumHandshakeJSONBytes = 4_096

    public private(set) var phase:
        ClientInteractiveRoleHandshakePumpPhaseV0 = .idle

    private let io: any ClientInteractiveRoleHandshakeIOV0
    private let authority: ClientInteractiveChannelAuthorityV0
    private let evidence: TLSPeerEvidence
    private let clock: @Sendable () -> UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let terminal: @Sendable (
        ClientInteractiveRoleHandshakePumpErrorV0
    ) -> Void
    private var deadlineTask: Task<Void, Never>?
    private var lastMonotonicMilliseconds: UInt64?
    private var deadlineMonotonicMilliseconds: UInt64?
    private var terminalReason:
        ClientInteractiveRoleHandshakePumpErrorV0?

    public init(
        io: any ClientInteractiveRoleHandshakeIOV0,
        authority: ClientInteractiveChannelAuthorityV0,
        evidence: TLSPeerEvidence,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        terminal: @escaping @Sendable (
            ClientInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.authority = authority
        self.evidence = evidence
        clock = monotonicNowMilliseconds
        sleep = { try await Task.sleep(nanoseconds: $0) }
        self.terminal = terminal
    }

    init(
        io: any ClientInteractiveRoleHandshakeIOV0,
        authority: ClientInteractiveChannelAuthorityV0,
        evidence: TLSPeerEvidence,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        sleep: @escaping @Sendable (UInt64) async throws -> Void,
        terminal: @escaping @Sendable (
            ClientInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _ in }
    ) {
        self.io = io
        self.authority = authority
        self.evidence = evidence
        clock = monotonicNowMilliseconds
        self.sleep = sleep
        self.terminal = terminal
    }

    public func beginOnVerifiedReadyConnection(
        clientNonce: WireBytes32,
        helloMessageID: WireUUID,
        proofMessageID: WireUUID
    ) async throws -> ClientInteractiveReadyRoleChannelV0 {
        guard phase == .idle else {
            throw ClientInteractiveRoleHandshakePumpErrorV0.alreadyStarted
        }
        guard helloMessageID != proofMessageID else {
            throw ClientInteractiveRoleHandshakePumpErrorV0
                .invalidConfiguration
        }
        phase = .authenticating
        do {
            let connectedAt = try observeClock()
            try await authority.didConnectTCP(at: connectedAt)
            let (deadline, overflow) = connectedAt.addingReportingOverflow(
                ClientInteractiveChannelAuthorityV0
                    .maximumUnusedLifetimeMilliseconds
            )
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientInteractiveRoleHandshakePumpErrorV0.invalidClock
            }
            deadlineMonotonicMilliseconds = deadline
            try await authority.acceptPinnedPeer(evidence, at: observeClock())
            await scheduleDeadline()

            let hello = try await authority.begin(
                clientNonce: clientNonce,
                messageID: helloMessageID,
                monotonicNowMilliseconds: observeClock()
            )
            try await sendHandshakeFrame(hello)

            let challenge = try await readHandshakeFrame()
            let proof = try await authority.receiveChallenge(
                challenge,
                proofMessageID: proofMessageID,
                monotonicNowMilliseconds: observeClock()
            )
            try await sendHandshakeFrame(proof)

            let accepted = try await readHandshakeFrame()
            try await authority.receiveAcceptance(
                accepted,
                monotonicNowMilliseconds: observeClock()
            )
            guard phase == .authenticating,
                  await authority.phase == .ready else {
                throw ClientInteractiveRoleHandshakePumpErrorV0.cancelled
            }
            deadlineTask?.cancel()
            deadlineTask = nil
            phase = .ready
            let offer = authority.offer
            return ClientInteractiveReadyRoleChannelV0(
                channelID: offer.channelID,
                role: offer.role
            )
        } catch {
            if phase == .closed, let terminalReason {
                throw terminalReason
            }
            await failClosed(Self.pumpError(for: error))
            throw error
        }
    }

    public func admitRoleTraffic() async throws {
        guard phase == .ready else {
            throw ClientInteractiveRoleHandshakePumpErrorV0
                .invalidConfiguration
        }
        do {
            try await authority.admitRoleTraffic()
        } catch {
            await failClosed(.invalidConfiguration)
            throw error
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
            throw ClientInteractiveRoleHandshakePumpErrorV0
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
                throw ClientInteractiveRoleHandshakePumpErrorV0.cancelled
            }
            let remaining = count - result.count
            let chunk: ClientInteractiveRoleReadChunkV0
            do {
                chunk = try await io.receive(maximumLength: remaining)
            } catch {
                throw ClientInteractiveRoleHandshakePumpErrorV0.invalidRead
            }
            _ = try observeClock()
            guard !chunk.data.isEmpty,
                  chunk.data.count <= remaining else {
                throw ClientInteractiveRoleHandshakePumpErrorV0.invalidRead
            }
            result.append(chunk.data)
            if chunk.isComplete {
                throw ClientInteractiveRoleHandshakePumpErrorV0.remoteClosed
            }
        }
        return result
    }

    private func sendHandshakeFrame(_ body: Data) async throws {
        guard !body.isEmpty,
              body.count <= Self.maximumHandshakeJSONBytes else {
            throw ClientInteractiveRoleHandshakePumpErrorV0
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
            throw ClientInteractiveRoleHandshakePumpErrorV0.sendFailed
        }
    }

    private func observeClock() throws -> UInt64 {
        let now = clock()
        guard now <= UInt64(Int64.max),
              lastMonotonicMilliseconds.map({ now >= $0 }) ?? true else {
            throw ClientInteractiveRoleHandshakePumpErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = now
        if phase == .authenticating,
           let deadlineMonotonicMilliseconds,
           now >= deadlineMonotonicMilliseconds {
            throw ClientInteractiveRoleHandshakePumpErrorV0.deadlineExceeded
        }
        return now
    }

    private func scheduleDeadline() async {
        guard let deadline = deadlineMonotonicMilliseconds else {
            await failClosed(.invalidClock)
            return
        }
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
        let now = clock()
        if await authority.expireIfRequired(at: now) {
            await failClosed(.deadlineExceeded)
        } else {
            await scheduleDeadline()
        }
    }

    private func failClosed(
        _ reason: ClientInteractiveRoleHandshakePumpErrorV0
    ) async {
        guard phase != .closed else { return }
        phase = .closed
        terminalReason = reason
        deadlineTask?.cancel()
        deadlineTask = nil
        io.cancel()
        await authority.close()
        terminal(reason)
    }

    private static func pumpError(
        for error: any Error
    ) -> ClientInteractiveRoleHandshakePumpErrorV0 {
        if let value = error as?
            ClientInteractiveRoleHandshakePumpErrorV0 {
            return value
        }
        if error is ClientInteractiveChannelErrorV0 {
            return .invalidConfiguration
        }
        return .invalidConfiguration
    }
}
