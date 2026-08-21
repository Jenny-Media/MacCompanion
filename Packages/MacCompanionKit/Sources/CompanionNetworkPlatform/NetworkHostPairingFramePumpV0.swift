import CompanionTransport
import CompanionWire
import Foundation

public enum NetworkHostPairingResponseDispositionV0:
    Equatable,
    Sendable
{
    case awaitPeer
    case awaitLocalDecision
    case terminal
}

public struct NetworkHostPairingSessionResponseV0: Sendable {
    public let frame: Data
    public let disposition: NetworkHostPairingResponseDispositionV0

    public init(
        frame: Data,
        disposition: NetworkHostPairingResponseDispositionV0
    ) {
        self.frame = frame
        self.disposition = disposition
    }
}

public protocol NetworkHostPairingSessionHandlingV0: Sendable {
    func receivePairingRequest(
        requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> NetworkHostPairingSessionResponseV0

    func takePairingCompletionIfAvailable(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data?

    func nextPairingDeadlineMonotonicMilliseconds() async -> UInt64?

    func cancelPairing(at monotonicNowMilliseconds: UInt64) async
}

public struct NetworkHostPairingRequestContextV0: Sendable {
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64
    public let responseMessageID: WireUUID

    public init(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) {
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.responseMessageID = responseMessageID
    }
}

public enum NetworkHostPairingFramePumpErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case alreadyStarted
    case receiveFailed
    case remoteClosed
    case sendFailed
    case protocolOrSessionFailure
}

public enum NetworkHostPairingTerminationReasonV0:
    String,
    Equatable,
    Sendable
{
    case localCancel
    case receiveFailed
    case remoteClosed
    case sendFailed
    case protocolOrSessionFailure
    case sessionDeadline
    case terminalResponseSent
}

/// Pairing-role adapter for one classified verified-ready connection. The
/// preserved first frame is replayed through the semantic owner before another
/// read is scheduled. Local-outcome checks are byte-independent and serialize
/// terminal sends through this actor.
public actor NetworkHostPairingFramePumpV0 {
    public static let maximumReceiveChunkBytes = 16_384
    public static let completionPollMilliseconds: UInt64 = 100

    public let tlsBinding: HostApplicationTLSBinding

    private let io: any NetworkHostIngressFrameIOV0
    private let initialFrame: Data
    private let session: any NetworkHostPairingSessionHandlingV0
    private let context: @Sendable () -> NetworkHostPairingRequestContextV0
    private let terminal: @Sendable (
        NetworkHostPairingTerminationReasonV0
    ) -> Void
    private let pollMilliseconds: UInt64
    private var decoder = LengthPrefixedFrameDecoder()
    private var started = false
    private var stopped = false
    private var receiveInFlight = false
    private var awaitingLocalDecision = false
    private var wakeTask: Task<Void, Never>?

    public init(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        session: any NetworkHostPairingSessionHandlingV0,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        let consumed = try classifiedConnection.consume(
            expectedRole: .pairing
        )
        io = consumed.io
        initialFrame = consumed.initialFrame
        tlsBinding = consumed.tlsBinding
        self.session = session
        self.context = context
        self.terminal = terminal
        pollMilliseconds = Self.completionPollMilliseconds
    }

    init(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        session: any NetworkHostPairingSessionHandlingV0,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        pollMilliseconds: UInt64,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        guard pollMilliseconds > 0 else {
            throw NetworkHostPairingFramePumpErrorV0.invalidConfiguration
        }
        let consumed = try classifiedConnection.consume(
            expectedRole: .pairing
        )
        io = consumed.io
        initialFrame = consumed.initialFrame
        tlsBinding = consumed.tlsBinding
        self.session = session
        self.context = context
        self.terminal = terminal
        self.pollMilliseconds = pollMilliseconds
    }

    public func beginOnClassifiedConnection() async throws {
        guard !started else {
            throw NetworkHostPairingFramePumpErrorV0.alreadyStarted
        }
        guard !stopped else {
            throw NetworkHostPairingFramePumpErrorV0.invalidConfiguration
        }
        started = true
        do {
            try await process(initialFrame)
            if !stopped {
                receiveNext()
                scheduleWake()
            }
        } catch {
            await stop(reason: Self.mapTerminal(error))
            if let error = error as? NetworkHostPairingFramePumpErrorV0 {
                throw error
            }
            throw NetworkHostPairingFramePumpErrorV0
                .protocolOrSessionFailure
        }
    }

    public func cancel() async {
        await stop(reason: .localCancel)
    }

    private func receiveNext() {
        guard started, !stopped, !receiveInFlight else { return }
        receiveInFlight = true
        let io = self.io
        Task { [weak self] in
            do {
                let chunk = try await io.receive(
                    maximumLength: Self.maximumReceiveChunkBytes
                )
                await self?.received(chunk)
            } catch {
                await self?.receiveFailed()
            }
        }
    }

    private func received(_ chunk: NetworkHostIngressFrameChunkV0) async {
        guard !stopped else { return }
        receiveInFlight = false
        do {
            if !chunk.data.isEmpty {
                let frames = try decoder.append(chunk.data)
                for frame in frames {
                    try await process(frame)
                    if stopped { return }
                }
                scheduleWake()
            }
            if chunk.isComplete {
                await stop(reason: .remoteClosed)
            } else {
                receiveNext()
            }
        } catch {
            await stop(reason: Self.mapTerminal(error))
        }
    }

    private func receiveFailed() async {
        guard !stopped else { return }
        receiveInFlight = false
        await stop(reason: .receiveFailed)
    }

    private func process(_ frame: Data) async throws {
        let current = context()
        let response = try await session.receivePairingRequest(
            requestJSON: frame,
            wallNowUnixMilliseconds: current.wallNowUnixMilliseconds,
            monotonicNowMilliseconds: current.monotonicNowMilliseconds,
            responseMessageID: current.responseMessageID
        )
        try await sendFrame(response.frame)
        switch response.disposition {
        case .awaitPeer:
            awaitingLocalDecision = false
        case .awaitLocalDecision:
            awaitingLocalDecision = true
        case .terminal:
            await stop(reason: .terminalResponseSent)
        }
    }

    private func sendFrame(_ frame: Data) async throws {
        let encoded: Data
        do {
            encoded = try LengthPrefixedFrameDecoder.encode(frame)
        } catch {
            throw NetworkHostPairingFramePumpErrorV0
                .protocolOrSessionFailure
        }
        do {
            try await io.send(encoded)
        } catch {
            throw NetworkHostPairingFramePumpErrorV0.sendFailed
        }
    }

    private func scheduleWake() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            guard let self,
                  let deadline = await self.session
                    .nextPairingDeadlineMonotonicMilliseconds()
            else { return }
            let current = self.context()
            let deadlineDelay = deadline > current.monotonicNowMilliseconds
                ? deadline - current.monotonicNowMilliseconds
                : 0
            let polling = await self.awaitingLocalDecision
            let delayMilliseconds = polling
                ? min(deadlineDelay, self.pollMilliseconds)
                : deadlineDelay
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
            await self.wakeReached(deadline: deadline)
        }
    }

    private func wakeReached(deadline: UInt64) async {
        guard !stopped else { return }
        let current = context()
        if awaitingLocalDecision {
            do {
                if let completion = try await session
                    .takePairingCompletionIfAvailable(
                        wallNowUnixMilliseconds:
                            current.wallNowUnixMilliseconds,
                        monotonicNowMilliseconds:
                            current.monotonicNowMilliseconds,
                        responseMessageID: current.responseMessageID
                    ) {
                    try await sendFrame(completion)
                    await stop(reason: .terminalResponseSent)
                    return
                }
            } catch {
                await stop(reason: Self.mapTerminal(error))
                return
            }
            scheduleWake()
            return
        }
        if current.monotonicNowMilliseconds >= deadline {
            await stop(reason: .sessionDeadline)
        } else {
            scheduleWake()
        }
    }

    private func stop(
        reason: NetworkHostPairingTerminationReasonV0
    ) async {
        guard !stopped else { return }
        stopped = true
        wakeTask?.cancel()
        wakeTask = nil
        io.cancel()
        await session.cancelPairing(
            at: context().monotonicNowMilliseconds
        )
        terminal(reason)
    }

    private static func mapTerminal(
        _ error: Error
    ) -> NetworkHostPairingTerminationReasonV0 {
        guard let error = error as? NetworkHostPairingFramePumpErrorV0 else {
            return .protocolOrSessionFailure
        }
        switch error {
        case .receiveFailed:
            return .receiveFailed
        case .remoteClosed:
            return .remoteClosed
        case .sendFailed:
            return .sendFailed
        case .invalidConfiguration, .alreadyStarted,
             .protocolOrSessionFailure:
            return .protocolOrSessionFailure
        }
    }
}
