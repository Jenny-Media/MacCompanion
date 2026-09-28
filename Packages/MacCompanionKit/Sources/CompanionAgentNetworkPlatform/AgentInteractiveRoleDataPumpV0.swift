import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveWire
import CompanionNetworkPlatform
import Dispatch
import Foundation
import OSLog

private let agentInteractiveRoleDataPumpLoggerV0 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-role-data-pump"
)

public enum AgentInteractiveRoleDataPumpErrorV0:
    Error, Equatable, Sendable
{
    case alreadyStarted
    case invalidRolePair
    case invalidClock
    case invalidInputFrameLength(UInt32)
    case invalidInputRead
    case remoteClosed
    case malformedInput
    case inputFenceMismatch
    case mediaSourceClosed
    case mediaPayloadMismatch
    case mediaFenceMismatch
    case mediaSequenceMismatch
    case routeFailed
    case sendFailed
    case cancelled
}

public struct AgentInteractiveReadyRolePairV0: Sendable {
    public let input: NetworkHostInteractiveReadyRoleConnectionV0
    public let media: NetworkHostInteractiveReadyRoleConnectionV0
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch

    public init(
        input: NetworkHostInteractiveReadyRoleConnectionV0,
        media: NetworkHostInteractiveReadyRoleConnectionV0
    ) throws {
        let inputChannel = input.channel
        let mediaChannel = media.channel
        guard inputChannel.role == .input,
              mediaChannel.role == .media,
              inputChannel.channelID != mediaChannel.channelID,
              inputChannel.clientID == mediaChannel.clientID,
              inputChannel.primaryConnectionID
                == mediaChannel.primaryConnectionID,
              inputChannel.interactiveSessionID
                == mediaChannel.interactiveSessionID,
              inputChannel.authorizationEpoch
                == mediaChannel.authorizationEpoch else {
            throw AgentInteractiveRoleDataPumpErrorV0.invalidRolePair
        }
        self.input = input
        self.media = media
        clientID = inputChannel.clientID.rawValue
        primaryConnectionID = inputChannel.primaryConnectionID.rawValue
        interactiveSessionID = inputChannel.interactiveSessionID.rawValue
        authorizationEpoch = inputChannel.authorizationEpoch
    }
}

public struct AgentInteractiveOutboundMediaRecordV0:
    Equatable, Sendable
{
    public let header: MediaRecordHeader
    public let payload: Data

    public init(header: MediaRecordHeader, payload: Data) throws {
        try header.validate()
        guard payload.count == Int(header.payloadLength) else {
            throw AgentInteractiveRoleDataPumpErrorV0.mediaPayloadMismatch
        }
        self.header = header
        self.payload = payload
    }

    public var encodedRecord: Data { header.encode() + payload }
}

/// The eventual local-XPC adapter implements these two facets against one
/// authenticated menu generation. Input acknowledgement means the menu runtime
/// accepted the exact action; media retrieval is one-at-a-time backpressure.
public protocol AgentInteractiveMenuRoleDataRoutingV0: Sendable {
    func retireInteractiveMedia(pair: AgentInteractiveReadyRolePairV0) async

    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        pair: AgentInteractiveReadyRolePairV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws

    func nextInteractiveMediaRecord(
        pair: AgentInteractiveReadyRolePairV0
    ) async throws -> AgentInteractiveOutboundMediaRecordV0?
}

public enum AgentInteractiveRoleDataPumpPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case running
    case closed
}

/// Owns both directions of one authenticated role pair. Either direction is
/// terminal for the pair: the owner cancels both connections before invoking
/// the exact-session termination route.
public actor AgentInteractiveRoleDataPumpV0 {
    public static let maximumInputJSONBytes = 65_536

    public private(set) var phase: AgentInteractiveRoleDataPumpPhaseV0 = .idle

    private let pair: AgentInteractiveReadyRolePairV0
    private let route: any AgentInteractiveMenuRoleDataRoutingV0
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let terminal: @Sendable (
        AgentInteractiveReadyRolePairV0,
        AgentInteractiveRoleDataPumpErrorV0
    ) async -> Void
    private var mediaRetirement: Task<Void, Never>?
    private var terminalReason: AgentInteractiveRoleDataPumpErrorV0?
    private var lastMonotonicNanoseconds: UInt64?

    public init(
        pair: AgentInteractiveReadyRolePairV0,
        route: any AgentInteractiveMenuRoleDataRoutingV0,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        terminal: @escaping @Sendable (
            AgentInteractiveReadyRolePairV0,
            AgentInteractiveRoleDataPumpErrorV0
        ) async -> Void
    ) {
        self.pair = pair
        self.route = route
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.terminal = terminal
    }

    public func run() async throws {
        guard phase == .idle else {
            throw AgentInteractiveRoleDataPumpErrorV0.alreadyStarted
        }
        phase = .running
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.runInput() }
                group.addTask { try await self.runMedia() }
                _ = try await group.next()
                group.cancelAll()
                throw AgentInteractiveRoleDataPumpErrorV0.remoteClosed
            }
        } catch {
            let reason = Self.map(error)
            await failClosed(reason)
            throw terminalReason ?? reason
        }
    }

    public func cancel() async {
        await failClosed(.cancelled)
    }

    private func runInput() async throws {
        while true {
            try Task.checkCancellation()
            let prefix = try await readInputExactly(4)
            let length = prefix.reduce(UInt32(0)) {
                ($0 << 8) | UInt32($1)
            }
            guard (1...UInt32(Self.maximumInputJSONBytes))
                .contains(length) else {
                throw AgentInteractiveRoleDataPumpErrorV0
                    .invalidInputFrameLength(length)
            }
            let body = try await readInputExactly(Int(length))
            let envelope: InteractiveInputEnvelope
            do {
                envelope = try InteractiveInputCodec.decode(body)
            } catch {
                throw AgentInteractiveRoleDataPumpErrorV0.malformedInput
            }
            guard envelope.interactiveSessionID.rawValue
                    == pair.interactiveSessionID,
                  envelope.authorizationEpoch
                    == pair.authorizationEpoch else {
                throw AgentInteractiveRoleDataPumpErrorV0
                    .inputFenceMismatch
            }
            do {
                try await route.applyInteractiveInput(
                    envelope,
                    pair: pair,
                    nowMonotonicNanoseconds: try sampleClock()
                )
                agentInteractiveRoleDataPumpLoggerV0.debug(
                    "input route accepted sequence=\(envelope.sequence, privacy: .public) kind=\(envelope.input.kind.rawValue, privacy: .public)"
                )
            } catch {
                agentInteractiveRoleDataPumpLoggerV0.error(
                    "input route rejected sequence=\(envelope.sequence, privacy: .public) kind=\(String(describing: envelope.input), privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .public)"
                )
                throw AgentInteractiveRoleDataPumpErrorV0.routeFailed
            }
        }
    }

    private func runMedia() async throws {
        var lastSequence: UInt64?
        while true {
            try Task.checkCancellation()
            let record: AgentInteractiveOutboundMediaRecordV0
            do {
                guard let value = try await route
                    .nextInteractiveMediaRecord(pair: pair) else {
                    throw AgentInteractiveRoleDataPumpErrorV0
                        .mediaSourceClosed
                }
                record = value
            } catch let error as AgentInteractiveRoleDataPumpErrorV0 {
                throw error
            } catch {
                throw AgentInteractiveRoleDataPumpErrorV0.routeFailed
            }
            guard record.payload.count == Int(record.header.payloadLength)
            else {
                throw AgentInteractiveRoleDataPumpErrorV0
                    .mediaPayloadMismatch
            }
            guard record.header.interactiveSessionID
                    == pair.interactiveSessionID,
                  record.header.authorizationEpoch
                    == pair.authorizationEpoch else {
                throw AgentInteractiveRoleDataPumpErrorV0
                    .mediaFenceMismatch
            }
            if let lastSequence,
               record.header.mediaSequence <= lastSequence {
                throw AgentInteractiveRoleDataPumpErrorV0
                    .mediaSequenceMismatch
            }
            do {
                try await pair.media.sendRoleBytes(record.encodedRecord)
            } catch {
                throw AgentInteractiveRoleDataPumpErrorV0.sendFailed
            }
            lastSequence = record.header.mediaSequence
        }
    }

    private func readInputExactly(_ count: Int) async throws -> Data {
        var value = Data()
        value.reserveCapacity(count)
        while value.count < count {
            try Task.checkCancellation()
            let remaining = count - value.count
            let chunk: NetworkHostInteractiveRoleTrafficChunkV0
            do {
                chunk = try await pair.input.receiveRoleBytes(
                    maximumLength: remaining
                )
            } catch {
                if Task.isCancelled {
                    throw AgentInteractiveRoleDataPumpErrorV0.cancelled
                }
                throw AgentInteractiveRoleDataPumpErrorV0.invalidInputRead
            }
            guard !chunk.data.isEmpty,
                  chunk.data.count <= remaining else {
                throw AgentInteractiveRoleDataPumpErrorV0.invalidInputRead
            }
            value.append(chunk.data)
            if chunk.isComplete {
                throw AgentInteractiveRoleDataPumpErrorV0.remoteClosed
            }
        }
        return value
    }

    private func sampleClock() throws -> UInt64 {
        let now = monotonicNowNanoseconds()
        guard now <= UInt64(Int64.max),
              lastMonotonicNanoseconds.map({ now >= $0 }) ?? true else {
            throw AgentInteractiveRoleDataPumpErrorV0.invalidClock
        }
        lastMonotonicNanoseconds = now
        return now
    }

    private func failClosed(
        _ reason: AgentInteractiveRoleDataPumpErrorV0
    ) async {
        guard phase != .closed else {
            await mediaRetirement?.value
            return
        }
        phase = .closed
        terminalReason = reason
        let retirement = Task { [route, pair] in await route.retireInteractiveMedia(pair: pair) }
        mediaRetirement = retirement
        await retirement.value
        await pair.input.cancel()
        await pair.media.cancel()
        await terminal(pair, reason)
    }

    private static func map(_ error: Error)
        -> AgentInteractiveRoleDataPumpErrorV0
    {
        if let value = error as? AgentInteractiveRoleDataPumpErrorV0 {
            return value
        }
        if error is CancellationError { return .cancelled }
        return .routeFailed
    }
}
