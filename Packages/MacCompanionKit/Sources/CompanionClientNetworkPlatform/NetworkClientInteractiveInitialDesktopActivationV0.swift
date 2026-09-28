import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import Dispatch
import Foundation

public enum NetworkClientInteractiveInitialDesktopPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case awaitingDescriptor
    case streaming
    case awaitingAcknowledgement
    case active
    case ending
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
    func requestReplacementSurfaceTargets() async throws
    func replacementSurfaceTargets() async
        -> [InteractiveSurfaceTargetCandidateV0]?
    func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws -> ClientSurfaceSelectionRequestV0
    func prepareReplacementDisplaySelection(
        displayID: UUID
    ) async throws -> ClientSurfaceSelectionRequestV0
    func sendReplacementSurfaceSelection(_ frame: Data) async throws
    func replacementSurfacePhase() async -> ClientSurfaceControlPhaseV0?
    func replacementSurfaceDescriptor() async
        -> AdaptiveSurfaceDescriptor?
    func latestFocusEvent() async -> ClientSurfaceFocusEventV0?
    func confirmReplacementRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) async throws -> Bool
    func acknowledgeReplacementSurface() async throws
    func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
}

extension ClientInteractivePrimaryChannelV0:
    NetworkClientInteractiveInitialPrimaryControllingV0 {}

package extension NetworkClientInteractiveInitialPrimaryControllingV0 {
    func latestFocusEvent() async -> ClientSurfaceFocusEventV0? { nil }
    func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
    }
    func prepareReplacementDisplaySelection(
        displayID _: UUID
    ) async throws -> ClientSurfaceSelectionRequestV0 {
        throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
    }
}

package extension ClientInteractivePrimaryChannelV0 {
    func prepareReplacementDisplaySelection(
        displayID: UUID
    ) throws -> ClientSurfaceSelectionRequestV0 {
        try prepareReplacementSurfaceSelection(
            targetKind: .desktop,
            targetToken: nil,
            targetDisplayID: displayID
        )
    }
}

private actor NetworkClientInteractiveInitialMediaConsumerV0:
    ClientInteractiveMediaRecordConsumingV0
{
    private let channel:
        any NetworkClientInteractiveInitialPrimaryControllingV0
    private let renderer: any ClientInteractiveInitialMediaRenderingV0

    private var ending = false
    private var suppressedSurfaceID: UUID?

    func suppressRendering(surfaceID: UUID) {
        suppressedSurfaceID = surfaceID
    }

    func beginEnding() async {
        ending = true
        await renderer.close()
    }

    init(
        channel: any NetworkClientInteractiveInitialPrimaryControllingV0,
        renderer: any ClientInteractiveInitialMediaRenderingV0
    ) {
        self.channel = channel
        self.renderer = renderer
    }

    func consume(header: MediaRecordHeader, payload: Data) async throws {
        do {
            let admission: ClientMediaAdmissionV0
            do {
                admission = try await channel.admitInitialMedia(
                    header: header,
                    payloadByteCount: payload.count
                )
            } catch {
                IOSClientRuntimeDiagnosticLogV0.record(
                    "interactive.media-admission.failed", error: error
                )
                throw error
            }
            guard !ending, header.surfaceID != suppressedSurfaceID else { return }
            do {
                try await renderer.process(
                    header: header,
                    payload: payload,
                    admission: admission
                )
            } catch {
                IOSClientRuntimeDiagnosticLogV0.record(
                    "interactive.media-render.failed", error: error
                )
                throw error
            }
        } catch {
#if DEBUG
            print("[MacCompanion live-control] media consumer rejected type=\(header.type) sequence=\(header.mediaSequence) error=\(String(describing: error))")
#endif
            throw error
        }
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
    private let consumer: NetworkClientInteractiveInitialMediaConsumerV0
    private let input: NetworkClientInteractiveInputSenderV0
    private let failure: @Sendable () async -> Void
    private var pumpTask: Task<Void, Never>?
    private var surfaceTransitionInFlight = false
    private var automaticSmartZoomEnabled = true

    package init(
        channel: any NetworkClientInteractiveInitialPrimaryControllingV0,
        inputConnection:
            NetworkClientInteractiveReadyRoleConnectionV0,
        mediaConnection:
            NetworkClientInteractiveReadyRoleConnectionV0,
        renderer: any ClientInteractiveInitialMediaRenderingV0,
        failure: @escaping @Sendable () async -> Void = {}
    ) throws {
        self.channel = channel
        self.renderer = renderer
        self.failure = failure
        input = try NetworkClientInteractiveInputSenderV0(
            connection: inputConnection,
            primary: channel
        )
        let consumer = NetworkClientInteractiveInitialMediaConsumerV0(channel: channel, renderer: renderer)
        self.consumer = consumer
        pump = try NetworkClientInteractiveMediaRecordPumpV0(
            connection: mediaConnection,
            consumer: consumer
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
                    IOSClientRuntimeDiagnosticLogV0.record(
                        "interactive.media-task.terminal",
                        error: error
                    )
                    print(
                        "[MacCompanion live-control] media pump failed error=\(String(describing: error))"
                    )
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
        // Rendering is asynchronous to transport teardown. A frame accepted
        // before the media/lease path failed may reach the main actor after
        // this activation has already failed or closed. It carries no new
        // authority and must not turn a completed fail-closed transition into
        // a second user-visible command failure.
        if phase == .failed || phase == .closed || phase == .ending { return }
        if phase == .active, surfaceTransitionInFlight {
            do {
                let matched = try await channel
                    .confirmReplacementRenderedFrame(receipt)
                guard matched else { return }
                try await channel.acknowledgeReplacementSurface()
                return
            } catch {
                await failClosed()
                throw error
            }
        }
        if phase == .awaitingAcknowledgement || phase == .active { return }
        guard phase == .streaming else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        do {
            let matched = try await channel.confirmInitialRenderedFrame(
                receipt
            )
            guard matched, phase == .streaming else { return }
            // Another decoder callback or an early host reply can run while
            // this send suspends. Neither may enqueue or rewind this transition.
            phase = .awaitingAcknowledgement
            try await channel.acknowledgeInitialSurface()
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
        guard phase == .active, !surfaceTransitionInFlight else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        try await input.send(payloads)
    }

    public func requestSurfaceTargets(
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> [InteractiveSurfaceTargetCandidateV0] {
        guard phase == .active, !surfaceTransitionInFlight,
              timeoutMilliseconds > 0 else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        do {
            try await channel.requestReplacementSurfaceTargets()
            let attempts = max(1, timeoutMilliseconds / 50)
            for _ in 0..<attempts {
                if let candidates = await channel.replacementSurfaceTargets() {
                    return candidates
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ClientInteractivePrimaryChannelErrorV0
                .surfaceTransitionDeadlineExceeded
        } catch {
            await failClosed()
            throw error
        }
    }

    public func setAutomaticSmartZoomEnabled(_ enabled: Bool) {
        automaticSmartZoomEnabled = enabled
    }

    public func isAutomaticSmartZoomEnabled() -> Bool {
        automaticSmartZoomEnabled
    }

    public func applyLatestFocusEvent(
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor? {
        guard let event = await channel.latestFocusEvent() else { return nil }
        return try await applyFocusEvent(
            event,
            timeoutMilliseconds: timeoutMilliseconds
        )
    }

    /// Confirms that the current acknowledged surface has Keyboard and Text
    /// authority. Accessibility focus is an optional Smart Zoom signal, not a
    /// prerequisite for ordinary remote keyboard entry. A positively known
    /// secure focus remains a local refusal.
    public func prepareTextInput(
        focusAcquisitionTimeoutMilliseconds: UInt64 = 2_000,
        surfaceTransitionTimeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor? {
        guard phase == .active, !surfaceTransitionInFlight,
              focusAcquisitionTimeoutMilliseconds > 0,
              surfaceTransitionTimeoutMilliseconds > 0 else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        if let event = await channel.latestFocusEvent(),
           Self.monotonicMilliseconds()
                < event.expiresAtMonotonicMilliseconds,
           event.focus?.secure == true {
            return nil
        }
        guard let current = await channel.replacementSurfaceDescriptor(),
              Self.authorizesText(current) else { return nil }
        return current
    }

    /// Returns an exact, content-free binding only for a currently
    /// acknowledged, verified, editable, non-secure focused surface. The
    /// caller may keep an uncommitted draft locally, but must present this
    /// binding again before any composed text is admitted.
    public func prepareNativeTextComposer() async throws
        -> SurfaceInputFence?
    {
        guard phase == .active, !surfaceTransitionInFlight,
              await channel.latestFocusEvent() == nil,
              let current = await channel.replacementSurfaceDescriptor(),
              Self.authorizesNativeComposer(current),
              Self.monotonicMilliseconds()
                < current.expiresAtMonotonicMilliseconds else {
            return nil
        }
        return SurfaceInputFence(
            interactiveSessionID: current.interactiveSessionID,
            authorizationEpoch: current.authorizationEpoch,
            surfaceID: current.surfaceID,
            surfaceRevision: current.surfaceRevision,
            coordinateSpaceRevision: current.coordinateSpaceRevision,
            focusToken: current.focus?.token,
            focusRevision: current.focus?.revision
        )
    }

    /// Sends one bounded local draft only while its original verified focus
    /// remains the exact acknowledged input authority. Focus or surface
    /// changes reject the draft locally before it reaches the transport.
    public func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws {
        guard phase == .active, !surfaceTransitionInFlight,
              await channel.latestFocusEvent() == nil,
              let current = await channel.replacementSurfaceDescriptor(),
              Self.authorizesNativeComposer(current),
              binding == SurfaceInputFence(
                interactiveSessionID: current.interactiveSessionID,
                authorizationEpoch: current.authorizationEpoch,
                surfaceID: current.surfaceID,
                surfaceRevision: current.surfaceRevision,
                coordinateSpaceRevision: current.coordinateSpaceRevision,
                focusToken: current.focus?.token,
                focusRevision: current.focus?.revision
              ) else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        let payload = InteractiveInputPayload.text(text)
        try payload.validate()
        try await input.send([payload])
    }

    /// Applies only an event already admitted by the ordered primary channel.
    /// The ordinary replacement path remains the sole transition authority.
    /// Returning `false` means local policy or an in-flight manual transition
    /// intentionally ignored the recommendation; protocol failures still
    /// converge through the existing fail-closed path.
    @discardableResult
    public func applyFocusEvent(
        _ event: ClientSurfaceFocusEventV0,
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor? {
        guard phase == .active, !surfaceTransitionInFlight,
              timeoutMilliseconds > 0 else { return nil }

        // Turning Smart Zoom off changes presentation policy; it cannot
        // retain a host-enforced focus pause indefinitely. Resolve any paused
        // event to the safe Desktop surface so ordinary input authority is
        // acknowledged again without opting the user back into Smart Zoom.
        if !automaticSmartZoomEnabled {
            guard event.inputPaused else { return nil }
            return try await transitionSurface(
                targetKind: .desktop,
                targetToken: nil,
                timeoutMilliseconds: timeoutMilliseconds
            )
        }

        let targetKind: InteractiveSurfaceKind
        let targetToken: UUID?
        switch event.recommendedTargetKind {
        case .focusedRegion:
            guard event.reason == .verifiedFocus,
                  event.focus != nil,
                  let token = event.targetToken?.rawValue else {
                return nil
            }
            targetKind = .focusedRegion
            targetToken = token
        case .desktop:
            guard event.reason != .verifiedFocus,
                  event.focus == nil,
                  event.targetToken == nil,
                  await channel.replacementSurfaceDescriptor()?.kind
                    != .desktop else { return nil }
            targetKind = .desktop
            targetToken = nil
        case .application, .window:
            return nil
        }
        do {
            return try await transitionSurface(
                targetKind: targetKind,
                targetToken: targetToken,
                timeoutMilliseconds: timeoutMilliseconds,
                recoverSupersededFocus: targetKind == .focusedRegion
            )
        } catch {
            guard targetKind == .focusedRegion,
                  Self.isRecoverableFocusSelectionError(error) else {
                throw error
            }
            // No reset or selection request was emitted for these errors.
            // Select a fresh Desktop descriptor to clear the host's paused
            // focus fence without terminating an otherwise healthy Control
            // session.
            return try await transitionSurface(
                targetKind: .desktop,
                targetToken: nil,
                timeoutMilliseconds: timeoutMilliseconds
            )
        }
    }

    /// Performs reset-before-select ordering and returns only after the exact
    /// replacement acknowledgement reply reactivates input.
    public func selectSurface(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?,
        nativeReplacement: Bool = false,
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor {
        return try await transitionSurface(
            targetKind: targetKind,
            targetToken: targetToken,
            targetDisplayID: nil,
            timeoutMilliseconds: timeoutMilliseconds,
            suppressOldMediaRendering: nativeReplacement
        )
    }

    public func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        guard phase == .active, !surfaceTransitionInFlight else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        return try await channel.requestDisplayCatalog()
    }

    public func selectDisplay(
        _ displayID: UUID,
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor {
        try await transitionSurface(
            targetKind: .desktop,
            targetToken: nil,
            targetDisplayID: displayID,
            timeoutMilliseconds: timeoutMilliseconds
        )
    }

    private func transitionSurface(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?,
        targetDisplayID: UUID? = nil,
        timeoutMilliseconds: UInt64,
        recoverSupersededFocus: Bool = false,
        suppressOldMediaRendering: Bool = false
    ) async throws -> AdaptiveSurfaceDescriptor {
        guard phase == .active, !surfaceTransitionInFlight,
              timeoutMilliseconds > 0 else {
            IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.invalid-phase")
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        surfaceTransitionInFlight = true
        do {
            if suppressOldMediaRendering {
                guard let previous = await channel.replacementSurfaceDescriptor() else {
                    throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
                }
                await consumer.suppressRendering(surfaceID: previous.surfaceID)
            }
            let selection: ClientSurfaceSelectionRequestV0
            if let targetDisplayID {
                selection = try await channel
                    .prepareReplacementDisplaySelection(
                        displayID: targetDisplayID
                    )
            } else {
                selection = try await channel
                    .prepareReplacementSurfaceSelection(
                        targetKind: targetKind,
                        targetToken: targetToken
                    )
            }
            IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.prepared")
            try await input.sendPreparedReset(selection.reset)
            IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.reset-sent")
            try await channel.sendReplacementSurfaceSelection(
                selection.requestJSON
            )
            IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.select-sent")
            let attempts = max(1, timeoutMilliseconds / 50)
            for _ in 0..<attempts {
                let surfacePhase = await channel.replacementSurfacePhase()
                if surfacePhase == .active,
                   let descriptor = await channel
                    .replacementSurfaceDescriptor() {
                    surfaceTransitionInFlight = false
                    return descriptor
                }
                if surfacePhase == .closed || surfacePhase == nil {
                    IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.coordinator-closed")
                    throw NetworkClientInteractiveInitialDesktopErrorV0
                        .unavailable
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ClientInteractivePrimaryChannelErrorV0
                .surfaceTransitionDeadlineExceeded
        } catch {
            IOSClientRuntimeDiagnosticLogV0.record("interactive.surface-selection.terminal", error: error)
            if recoverSupersededFocus,
               Self.isRecoverableFocusSelectionError(error) {
                surfaceTransitionInFlight = false
                throw error
            }
            await failClosed()
            throw error
        }
    }

    public func beginEnding() async {
        guard phase != .closed, phase != .failed, phase != .ending else { return }
        phase = .ending
        surfaceTransitionInFlight = false
        await input.fenceForStop()
        await consumer.beginEnding()
    }

    public func close() async {
        guard phase != .closed else { return }
        phase = .closed
        surfaceTransitionInFlight = false
        pumpTask?.cancel()
        pumpTask = nil
        await pump.close()
        await input.close()
        await renderer.close()
    }

    private func mediaEnded() async {
        guard phase != .closed, phase != .failed else { return }
        IOSClientRuntimeDiagnosticLogV0.record(
            "interactive.media-task.unexpected-end"
        )
        await failClosed()
    }

    private func mediaFailed() async {
        guard phase != .closed, phase != .failed else { return }
        IOSClientRuntimeDiagnosticLogV0.record(
            "interactive.activation.media-failed"
        )
        await failClosed()
    }

    private func failClosed() async {
        guard phase != .closed, phase != .failed else { return }
        IOSClientRuntimeDiagnosticLogV0.record(
            "interactive.activation.fail-closed"
        )
        phase = .failed
        surfaceTransitionInFlight = false
        pumpTask?.cancel()
        pumpTask = nil
        await pump.close()
        await input.close()
        await renderer.close()
        // A media EOF does not necessarily produce another renderer callback.
        // Report terminal progress even after the initial surface was active.
        await failure()
    }

    private static func authorizesText(
        _ descriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        guard descriptor.interactionClasses.contains(.keyboard),
              descriptor.interactionClasses.contains(.text) else {
            return false
        }
        return descriptor.focus?.secure != true
    }

    private static func authorizesNativeComposer(
        _ descriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        guard authorizesText(descriptor),
              descriptor.kind == .focusedRegion,
              descriptor.privacyProfile == .assistedVisual,
              let focus = descriptor.focus else { return false }
        return focus.category == .text && focus.editable && !focus.secure
    }

    private static func isRecoverableFocusSelectionError(
        _ error: any Error
    ) -> Bool {
        guard let value = error as? ClientSurfaceControlErrorV0 else {
            return false
        }
        switch value {
        case .targetInventoryRequired, .focusEventExpired:
            return true
        default:
            return false
        }
    }

    private static func monotonicMilliseconds() -> Int64 {
        let value = DispatchTime.now().uptimeNanoseconds / 1_000_000
        guard value <= UInt64(Int64.max) else { return Int64.max }
        return Int64(value)
    }
}
