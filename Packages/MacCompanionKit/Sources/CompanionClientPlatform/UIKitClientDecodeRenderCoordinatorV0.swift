#if os(iOS)
import CompanionInteractiveClient
import CompanionInteractiveWire
import Foundation

public enum UIKitClientDecodeRenderFailureV0: Equatable, Sendable {
    case decoderConstruction
    case currentDecode(generation: UInt64, mediaSequence: UInt64)
    case renderer
    case interrupted
}

private final class ClientDecodeGenerationGateV0: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64?
    private var requiredRenderSequence: UInt64?

    func set(_ value: UInt64?) {
        lock.withLock {
            generation = value
            requiredRenderSequence = nil
        }
    }

    func requireRender(generation: UInt64, sequence: UInt64) {
        lock.withLock {
            guard self.generation == generation else { return }
            requiredRenderSequence = sequence
        }
    }

    func isRequired(generation: UInt64, sequence: UInt64) -> Bool {
        lock.withLock {
            self.generation == generation
                && requiredRenderSequence == sequence
        }
    }

    func rendered(generation: UInt64, sequence: UInt64) {
        lock.withLock {
            guard self.generation == generation,
                  requiredRenderSequence == sequence else { return }
            requiredRenderSequence = nil
        }
    }

    func contains(_ value: UInt64) -> Bool {
        lock.withLock { generation == value }
    }
}

/// The sole main-actor composition point for pure decoder authority,
/// VideoToolbox, the one-slot callback mailbox, and the visible surface.
@MainActor
public final class UIKitClientDecodeRenderCoordinatorV0 {
    public private(set) var authority = ClientDecoderRenderAuthorityV0()
    public private(set) var terminalFailure:
        UIKitClientDecodeRenderFailureV0?
    public private(set) var isClosed = false

    private let renderer: any UIKitClientPixelBufferRenderingV0
    private let rendered: @MainActor (ClientDecodedFrameReceiptV0) -> Void
    private let mailbox =
        ClientLatestResultMailboxV0<VideoToolboxClientDecodeResultV0>()
    private let generationGate = ClientDecodeGenerationGateV0()
    private lazy var decoder: VideoToolboxClientDecoderV0 = makeDecoder()

    public init(
        renderer: any UIKitClientPixelBufferRenderingV0,
        rendered: @escaping @MainActor (
            ClientDecodedFrameReceiptV0
        ) -> Void = { _ in }
    ) {
        self.renderer = renderer
        self.rendered = rendered
    }

    @discardableResult
    public func process(
        header: MediaRecordHeader,
        payload: Data,
        admission: ClientMediaAdmissionV0
    ) throws -> ClientDecoderActionV0 {
        let action: ClientDecoderActionV0
        let requiresFirstRender = authority.latestFrame == nil
        do {
            action = try authority.process(
                header: header,
                payload: payload,
                admission: admission
            )
        } catch {
            terminate(.decoderConstruction)
            throw error
        }
        do {
            switch action {
            case let .configure(command):
                generationGate.set(command.generation)
                _ = mailbox.discardPending()
                renderer.blank()
                try decoder.configure(command)
            case let .decode(command):
                if command.cleanKeyframe && requiresFirstRender {
                    generationGate.requireRender(
                        generation: command.generation,
                        sequence: command.mediaSequence
                    )
                }
                try decoder.decode(command)
            case let .reset(generation, _):
                generationGate.set(generation)
                _ = mailbox.discardPending()
                decoder.invalidate()
                renderer.blank()
            case .end:
                generationGate.set(nil)
                _ = mailbox.close()
                decoder.invalidate()
                renderer.blank()
            }
            return action
        } catch {
            terminate(.decoderConstruction)
            throw error
        }
    }

    public func interruptAndBlank() {
        terminate(.interrupted)
    }

    public func closeAndBlank() {
        terminate(nil)
    }

    private func makeDecoder() -> VideoToolboxClientDecoderV0 {
        let mailbox = mailbox
        let generationGate = generationGate
        return VideoToolboxClientDecoderV0 { [weak self] result in
            let generation: UInt64
            let sequence: UInt64
            let terminal: Bool
            switch result {
            case let .frame(frame):
                generation = frame.receipt.generation
                sequence = frame.receipt.mediaSequence
                terminal = generationGate.isRequired(
                    generation: generation,
                    sequence: sequence
                )
            case let .failure(value, mediaSequence):
                generation = value
                sequence = mediaSequence
                terminal = generationGate.contains(value)
            }
            let offer = mailbox.offer(
                result,
                order: .init(generation: generation, sequence: sequence),
                terminal: terminal
            )
            let shouldSchedule: Bool
            switch offer {
            case let .accepted(schedule, _),
                 let .acceptedTerminal(schedule, _):
                shouldSchedule = schedule
            case .discardedNotNewer,
                 .rejectedTerminalPending,
                 .rejectedClosed:
                shouldSchedule = false
            }
            guard shouldSchedule else { return }
            Task { @MainActor [weak self] in
                self?.drainOneResult()
            }
        }
    }

    private func drainOneResult() {
        guard let result = mailbox.takePendingForScheduledDrain() else {
            _ = mailbox.completeDrain()
            return
        }
        switch result {
        case let .frame(frame):
            switch authority.admitDecodedFrame(frame.receipt) {
            case .accepted, .replaced:
                do {
                    try renderer.present(frame)
                    generationGate.rendered(
                        generation: frame.receipt.generation,
                        sequence: frame.receipt.mediaSequence
                    )
                    rendered(frame.receipt)
                } catch {
                    terminate(.renderer)
                    return
                }
            case .discardedStale:
                break
            }
        case let .failure(generation, mediaSequence):
            if generation == authority.generation,
               mediaSequence <= authority.lastSubmittedMediaSequence {
                terminate(.currentDecode(
                    generation: generation,
                    mediaSequence: mediaSequence
                ))
                return
            }
        }
        if mailbox.completeDrain() {
            Task { @MainActor [weak self] in
                self?.drainOneResult()
            }
        }
    }

    private func terminate(
        _ failure: UIKitClientDecodeRenderFailureV0?
    ) {
        guard !isClosed else { return }
        isClosed = true
        terminalFailure = failure
        generationGate.set(nil)
        _ = mailbox.close()
        decoder.invalidate()
        authority.close()
        renderer.blank()
    }
}
#endif
