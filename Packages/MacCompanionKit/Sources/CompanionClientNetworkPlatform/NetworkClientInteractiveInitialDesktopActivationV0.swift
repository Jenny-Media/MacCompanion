import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum NetworkClientInteractiveInitialDesktopPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case awaitingDescriptor
    case streaming
    case awaitingAcknowledgement
    case active
    case failed
    case closed
}

public enum NetworkClientInteractiveInitialDesktopErrorV0:
    Error, Equatable, Sendable
{
    case invalidPhase
    case unavailable
}

public struct NetworkClientInteractiveInitialDesktopStartV0: Sendable {
    public let activation:
        NetworkClientInteractiveInitialDesktopActivationV0
    public let descriptor: AdaptiveSurfaceDescriptor

    public init(
        activation:
            NetworkClientInteractiveInitialDesktopActivationV0,
        descriptor: AdaptiveSurfaceDescriptor
    ) {
        self.activation = activation
        self.descriptor = descriptor
    }
}

/// Concrete platform adapters validate AVCC, submit VideoToolbox work, and
/// render on their UI authority. `process` returning means submission only;
/// the adapter must separately call `reportRendered` after visible render
/// success.
public protocol ClientInteractiveInitialMediaRenderingV0: Sendable {
    func process(
        header: MediaRecordHeader,
        payload: Data,
        admission: ClientMediaAdmissionV0
    ) async throws
    func close() async
}

package protocol NetworkClientInteractiveInitialPrimaryControllingV0:
    Sendable
{
    func beginInitialSurface() async throws
    func waitForInitialDescriptor(
        timeoutMilliseconds: UInt64
    ) async throws -> AdaptiveSurfaceDescriptor
    func admitInitialMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) async throws -> ClientMediaAdmissionV0
    func confirmInitialRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) async throws -> Bool
    func acknowledgeInitialSurface() async throws
    func initialSurfacePhase() async -> ClientInitialSurfacePhaseV0?
    func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) async throws -> Data
    func closeInitialInputFrame() async throws -> Data?
}

extension ClientInteractivePrimaryChannelV0:
    NetworkClientInteractiveInitialPrimaryControllingV0 {}

private actor NetworkClientInteractiveInitialMediaConsumerV0:
    ClientInteractiveMediaRecordConsumingV0
{
    private let channel:
        any NetworkClientInteractiveInitialPrimaryControllingV0
    private let renderer: any ClientInteractiveInitialMediaRenderingV0

    init(
        channel: any NetworkClientInteractiveInitialPrimaryControllingV0,
        renderer: any ClientInteractiveInitialMediaRenderingV0
    ) {
        self.channel = channel
        self.renderer = renderer
    }

    func consume(header: MediaRecordHeader, payload: Data) async throws {
        let admission = try await channel.admitInitialMedia(
            header: header,
            payloadByteCount: payload.count
        )
        try await renderer.process(
            header: header,
            payload: payload,
            admission: admission
        )
    }
}

/// Owns initial Desktop request ordering, exact media consumption, render
/// proof, and the primary acknowledgement. Input remains inert until the
/// channel validates `interactive.surface.initial.acknowledged`.
public actor NetworkClientInteractiveInitialDesktopActivationV0 {
    public private(set) var phase:
        NetworkClientInteractiveInitialDesktopPhaseV0 = .idle

    private let channel:
        any NetworkClientInteractiveInitialPrimaryControllingV0
    private let renderer: any ClientInteractiveInitialMediaRenderingV0
    private let pump: NetworkClientInteractiveMediaRecordPumpV0
    private let input: NetworkClientInteractiveInputSenderV0
    private var pumpTask: Task<Void, Never>?

    package init(
        channel: any NetworkClientInteractiveInitialPrimaryControllingV0,
        inputConnection:
            NetworkClientInteractiveReadyRoleConnectionV0,
        mediaConnection:
            NetworkClientInteractiveReadyRoleConnectionV0,
        renderer: any ClientInteractiveInitialMediaRenderingV0
    ) throws {
        self.channel = channel
        self.renderer = renderer
        input = try NetworkClientInteractiveInputSenderV0(
            connection: inputConnection,
            primary: channel
        )
        pump = try NetworkClientInteractiveMediaRecordPumpV0(
            connection: mediaConnection,
            consumer: NetworkClientInteractiveInitialMediaConsumerV0(
                channel: channel,
                renderer: renderer
            )
        )
    }

    @discardableResult
    public func start() async throws -> AdaptiveSurfaceDescriptor {
        guard phase == .idle else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        phase = .awaitingDescriptor
        do {
            try await channel.beginInitialSurface()
            let descriptor = try await channel.waitForInitialDescriptor(
                timeoutMilliseconds: 30_000
            )
            guard phase == .awaitingDescriptor else {
                throw NetworkClientInteractiveInitialDesktopErrorV0
                    .invalidPhase
            }
            phase = .streaming
            let pump = self.pump
            pumpTask = Task { [weak self] in
                do {
                    try await pump.run()
                    await self?.mediaEnded()
                } catch {
                    await self?.mediaFailed()
                }
            }
            return descriptor
        } catch {
            await failClosed()
            throw error
        }
    }

    /// Called by the platform adapter only after the renderer accepts the
    /// current decoded frame. Later frames are harmless while the exact first
    /// acknowledgement reply is still in flight.
    public func reportRendered(
        _ receipt: ClientDecodedFrameReceiptV0
    ) async throws {
        if phase == .awaitingAcknowledgement || phase == .active { return }
        guard phase == .streaming else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        do {
            let matched = try await channel.confirmInitialRenderedFrame(
                receipt
            )
            guard matched else { return }
            try await channel.acknowledgeInitialSurface()
            phase = .awaitingAcknowledgement
        } catch {
            await failClosed()
            throw error
        }
    }

    /// Synchronizes product state after the primary reply pump commits the
    /// exact acknowledgement response.
    @discardableResult
    public func refreshPrimaryState() async -> Bool {
        guard phase == .awaitingAcknowledgement else {
            return phase == .active
        }
        if await channel.initialSurfacePhase() == .active {
            phase = .active
            return true
        }
        return false
    }

    public func sendInput(
        _ payloads: [InteractiveInputPayload]
    ) async throws {
        guard phase == .active else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        try await input.send(payloads)
    }

    public func close() async {
        guard phase != .closed else { return }
        phase = .closed
        pumpTask?.cancel()
        pumpTask = nil
        await pump.close()
        await input.close()
        await renderer.close()
    }

    private func mediaEnded() async {
        guard phase != .closed, phase != .failed else { return }
        await failClosed()
    }

    private func mediaFailed() async {
        guard phase != .closed, phase != .failed else { return }
        await failClosed()
    }

    private func failClosed() async {
        guard phase != .closed, phase != .failed else { return }
        phase = .failed
        pumpTask?.cancel()
        pumpTask = nil
        await pump.close()
        await input.close()
        await renderer.close()
    }
}
