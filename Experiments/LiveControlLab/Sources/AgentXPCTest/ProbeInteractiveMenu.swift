#if !DEBUG || !os(macOS)
#error("Disposable Interactive menu is macOS Debug only")
#endif
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import CompanionMacApplicationPlatform
import CoreMedia
import CoreVideo
import Foundation

private func probeFence(_ lease: InteractiveExecutionLease) -> InteractiveCommandFence {
    .init(leaseID: lease.leaseID, hostID: lease.hostID, deviceID: lease.deviceID,
          interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
          selectedDisplayID: lease.selectedDisplayID, surfaceID: lease.surfaceID,
          surfaceRevision: lease.surfaceRevision, coordinateRevision: lease.coordinateRevision)
}

private struct ProbePublisherRuntime: InteractiveMediaRuntimePublishingV0 {
    let runtime: InteractiveMenuRuntimeOwnerV0
    func publishMedia(_ action: InteractiveRuntimeMediaActionV0,
                      nowMonotonicNanoseconds: UInt64) async throws {
        try await runtime.publishMedia(action, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }
}

/// Keeps the production lease/runtime adapter while supplying one generated,
/// privacy-filtered editable focus. This exercises the signed focus/Smart Zoom
/// and keyboard paths without querying Accessibility or naming a real app.
/// Omitting this authenticated method makes the Agent invalidate the entire
/// menu generation when its automatic focus observer first samples.
@available(macOS 26.0, *)
private struct ProbeInteractiveLeaseHandler: MacLocalXPCInteractiveLeaseHandlingV1 {
    let base: MacInteractiveLeaseRuntimeAdapterV1
    let effects: ProbeInteractiveEffects
    let focus: SurfaceFocus

    init(base: MacInteractiveLeaseRuntimeAdapterV1, effects: ProbeInteractiveEffects) throws {
        self.base = base
        self.effects = effects
        focus = try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 1),
            category: .text,
            bounds: NormalizedSurfaceRect(
                x: 8_192,
                y: 12_288,
                width: 32_768,
                height: 16_384
            ),
            editable: true,
            secure: false
        )
    }

    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await base.prepareInitialInteractiveDesktop(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await base.installInteractiveLease(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        try await base.renewInteractiveLease(
            renewal, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await base.revokeInteractiveLease(command)
    }

    func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try await base.interactiveSurfaceTargets(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        if command.targetKind == .focusedRegion {
            guard let targetToken = command.targetToken else {
                throw LocalInteractiveSurfaceRuntimeErrorV1.invalidCommand
            }
            let nextSurfaceRevision = try command.expectedSurfaceRevision.advanced()
            let nextCoordinateRevision = try command
                .expectedCoordinateSpaceRevision.advanced()
            let nowMilliseconds = Int64(
                min(nowMonotonicNanoseconds / 1_000_000, UInt64(Int64.max - 10_000))
            )
            let descriptor = try AdaptiveSurfaceDescriptor(
                interactiveSessionID: command.interactiveSessionID,
                authorizationEpoch: command.authorizationEpoch,
                surfaceID: targetToken,
                kind: .focusedRegion,
                surfaceRevision: nextSurfaceRevision,
                coordinateSpaceRevision: nextCoordinateRevision,
                applicationToken: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                parentSurfaceID: command.currentSurfaceID,
                fallbackSurfaceID: command.currentSurfaceID,
                encodedWidth: 64,
                encodedHeight: 48,
                logicalWidthPoints: 640,
                logicalHeightPoints: 480,
                interactionClasses: [.view, .pointer, .keyboard, .text],
                privacyProfile: .assistedVisual,
                metadataFields: [.focusCategory, .focusBounds, .editable, .secure],
                focus: focus,
                createdAtMonotonicMilliseconds: nowMilliseconds,
                expiresAtMonotonicMilliseconds: nowMilliseconds + 10_000
            )
            let receipt = try LocalInteractiveSurfaceResolvedReceiptV1(
                correlationID: command.commandID,
                descriptor: descriptor
            )
            try receipt.validate(against: command)
            return receipt
        }
        return try await base.resolveInteractiveSurface(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await base.prepareInteractiveSurfaceTransition(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        let receipt = try await base.acknowledgeInteractiveSurface(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
        await effects.recordSurfaceAcknowledgement()
        return receipt
    }

    func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await base.terminateInteractiveSurfaceFailure(command)
    }

    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        let candidate = try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: .focusedRegion,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000)
        let receipt = LocalInteractiveFocusSnapshotReceiptV1(
            correlationID: command.commandID,
            command: command,
            candidate: candidate)
        try receipt.validate(against: command)
        return receipt
    }

    func invalidateAgentAuthority() async {
        await base.invalidateAgentAuthority()
    }
}

private final class ProbeInteractiveInputSink: InteractiveRuntimeInputPostingV0, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func postInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        lock.withLock { count += 1 }
    }
    func snapshot() -> Int { lock.withLock { count } }
}

/// Explicit substitutes for display/capture/indicator/input. No screen access,
/// CGEvent, user app, permission, or real frame is involved in this lease lane.
@available(macOS 26.0, *)
actor ProbeInteractiveEffects: InteractiveRuntimeIndicatorControllingV0,
    InteractiveRuntimeCaptureControllingV0, InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeFrameControllingV0, MacInteractiveInitialDesktopPreparingV1 {
    enum Failure: Error { case unsupported, badBinding }
    struct Snapshot: Sendable {
        let started: Int
        let renewed: Int
        let stopped: Int
        let released: Int
        let blanked: Int
        let cleared: Int
        let encodedFrames: Int
        let acknowledgements: Int
    }
    nonisolated let menuGeneration = UUID()
    nonisolated let displayID = UUID()
    private var started = 0, renewed = 0, stopped = 0, released = 0, blanked = 0, cleared = 0
    private var encodedFrames = 0
    private var acknowledgements = 0
    private var lease: InteractiveExecutionLease?
    private weak var runtime: InteractiveMenuRuntimeOwnerV0?
    private let queue: BoundedInteractiveMediaQueueV0
    private let streamsMedia: Bool
    private var publisher: VideoToolboxInteractiveMediaPublisherV0?
    private var encoder: VideoToolboxH264EncoderOwnerV0?
    private var encoderGeneration: UUID?
    private var frames: Task<Void, Never>?
    private var pendingTransition: InteractiveRuntimeSurfaceTransitionCommandV0?
    private var pauseDesktop = false
    private(set) var desktopIsWaiting = false
    func pauseNextDesktop() { pauseDesktop = true }
    func resumeDesktop() { pauseDesktop = false }

    init(queue: BoundedInteractiveMediaQueueV0, streamsMedia: Bool) {
        self.queue = queue; self.streamsMedia = streamsMedia
    }
    func bind(_ runtime: InteractiveMenuRuntimeOwnerV0) { self.runtime = runtime }
    func snapshot() -> Snapshot {
        .init(started: started, renewed: renewed, stopped: stopped,
              released: released, blanked: blanked, cleared: cleared,
              encodedFrames: encodedFrames, acknowledgements: acknowledgements)
    }
    func recordSurfaceAcknowledgement() { acknowledgements += 1 }
    func prepareInitialInteractiveDesktop(_ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        guard command.selectedDisplayID == displayID else { throw Failure.badBinding }
        if pauseDesktop {
            desktopIsWaiting = true
            defer { desktopIsWaiting = false }
            let deadline = ContinuousClock.now + .seconds(2)
            while pauseDesktop, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard !pauseDesktop else { throw Failure.unsupported }
        }
        let now = Int64(nowMonotonicNanoseconds / 1_000_000)
        return try .init(correlationID: command.commandID, descriptor: AdaptiveSurfaceDescriptor(
            interactiveSessionID: command.interactiveSessionID, authorizationEpoch: command.authorizationEpoch,
            surfaceID: UUID(), kind: .desktop, surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1), encodedWidth: 64, encodedHeight: 48,
            logicalWidthPoints: 64, logicalHeightPoints: 48,
            interactionClasses: Set(command.interactionClasses), privacyProfile: .visualOnly,
            metadataFields: [], createdAtMonotonicMilliseconds: now, expiresAtMonotonicMilliseconds: now + 60_000))
    }
    func showInteractiveIndicator(deviceDisplayName: DeviceDisplayName,
        interactiveSessionID: UUID) throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        try .init(menuAppGeneration: menuGeneration, menuAppRevision: 1)
    }
    func clearInteractiveIndicator() { cleared += 1 }
    func startInteractiveCapture(_ command: InteractiveRuntimeInstallCommandV0) async throws -> Set<SurfaceInteractionClass> {
        guard lease == nil, command.lease.selectedDisplayID == displayID else { throw Failure.badBinding }
        lease = command.lease
        started += 1
        if streamsMedia { try await startMedia(command) }
        return Set(command.surfaceDescriptor.interactionClasses)
    }
    func adoptInteractiveLeaseRenewal(_ renewal: InteractiveRuntimeLeaseRenewalV0) async throws {
        guard let lease else { throw Failure.badBinding }
        try renewal.validate(current: lease)
        if let publisher {
            guard await publisher.adoptLeaseRenewal(to: try .init(
                fence: probeFence(renewal.replacement), descriptor: try currentDescriptor())) else {
                throw Failure.badBinding
            }
        }
        self.lease = renewal.replacement
        renewed += 1
    }
    func prepareInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        guard let lease, publisher != nil, pendingTransition == nil,
              command.previousLeaseID == lease.leaseID,
              command.replacement.interactiveSessionID == lease.interactiveSessionID,
              command.descriptor.surfaceID == command.replacement.surfaceID else {
            throw Failure.badBinding
        }
        frames?.cancel()
        frames = nil
        retireEncoderWithoutWaitingForPublication()
        encoder = nil
        pendingTransition = command
        return Set(command.descriptor.interactionClasses)
    }
    func activatePreparedInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64
    ) async throws {
        guard pendingTransition == command, publisher != nil, let runtime else {
            throw Failure.badBinding
        }
        let replacement = try InteractiveMediaPublicationBindingV0(
            fence: probeFence(command.replacement),
            descriptor: command.descriptor
        )
        // Do not await the retired publisher here: an in-flight sample may be
        // awaiting this same runtime actor. The replacement publisher resumes
        // the exact media sequence and emits its discontinuity with its first
        // clean frame, which is the transition-safe path provided by the
        // production media publisher.
        let replacementPublisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: replacement,
            runtime: ProbePublisherRuntime(runtime: runtime),
            resumingAfterMediaSequence: mediaSequenceBeforeTransition
        )
        publisher = replacementPublisher
        lease = command.replacement
        descriptor = command.descriptor
        try startEncoderAndFrames(
            publisher: replacementPublisher,
            descriptor: command.descriptor
        )
        pendingTransition = nil
    }
    func stopInteractiveCapture() async {
        frames?.cancel(); frames = nil
        retireEncoderWithoutWaitingForPublication()
        encoder = nil; publisher = nil
        pendingTransition = nil; descriptor = nil; lease = nil; stopped += 1
    }
    func releaseAllInteractiveInput() { released += 1 }
    func blankLastInteractiveFrame() { _ = queue.purge(); blanked += 1 }

    private var descriptor: AdaptiveSurfaceDescriptor?
    private func currentDescriptor() throws -> AdaptiveSurfaceDescriptor {
        guard let descriptor else { throw Failure.badBinding }
        return descriptor
    }
    private func startMedia(_ command: InteractiveRuntimeInstallCommandV0) async throws {
        guard let runtime else { throw Failure.badBinding }
        descriptor = command.surfaceDescriptor
        let publisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: try .init(fence: probeFence(command.lease), descriptor: command.surfaceDescriptor),
            runtime: ProbePublisherRuntime(runtime: runtime))
        self.publisher = publisher
        try startEncoderAndFrames(
            publisher: publisher,
            descriptor: command.surfaceDescriptor
        )
    }

    private func startEncoderAndFrames(
        publisher: VideoToolboxInteractiveMediaPublisherV0,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        let profile = try VideoToolboxH264EncoderProfileV0(
            capture: .init(width: Int(descriptor.encodedWidth),
                           height: Int(descriptor.encodedHeight),
                           framesPerSecond: 15, queueDepth: 3),
            targetBitrateBitsPerSecond: 350_000,
            keyframeIntervalMilliseconds: 1_000)
        let generation = UUID()
        encoderGeneration = generation
        let encoder = VideoToolboxH264EncoderOwnerV0(
            profile: profile,
            session: try VideoToolboxH264CompressionSessionV0(profile: profile),
            output: { [weak self] sample in
                guard await self?.isCurrentEncoder(generation) == true else {
                    return false
                }
                return await publisher.publish(sample)
            })
        self.encoder = encoder
        frames = Task { [weak self] in
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                do {
                    sequence += 1
                    let pixel = try Self.pixel(width: profile.capture.width,
                                               height: profile.capture.height,
                                               tick: sequence)
                    _ = try await encoder.submit(.init(sourceSequence: sequence, pixelBuffer: pixel,
                        presentationTime: CMTime(value: Int64(DispatchTime.now().uptimeNanoseconds),
                                                timescale: 1_000_000_000),
                        duration: CMTime(value: 1, timescale: 15)))
                    await self?.recordEncodedFrame()
                    try await Task.sleep(for: .milliseconds(66))
                } catch { return }
            }
        }
    }
    private func isCurrentEncoder(_ generation: UUID) -> Bool {
        encoderGeneration == generation
    }
    /// The encoder serializes publication inside its own actor. Waiting for
    /// `stop()` while the Agent runtime is synchronously asking this seam to
    /// transition can deadlock an in-flight publisher on that runtime actor.
    /// Fence the generation first, then retire outside this call chain.
    private func retireEncoderWithoutWaitingForPublication() {
        encoderGeneration = nil
        guard let encoder else { return }
        Task { await encoder.stop() }
    }
    private func recordEncodedFrame() { encodedFrames += 1 }
    private static func pixel(width: Int, height: Int, tick: UInt64) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &result) == kCVReturnSuccess, let result else { throw Failure.unsupported }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        for plane in 0..<2 {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(result, plane) else {
                throw Failure.unsupported
            }
            let rows = CVPixelBufferGetHeightOfPlane(result, plane)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(result, plane)
            memset(base, plane == 0 ? Int32(45 + (tick % 140)) : 128, rows * stride)
        }
        return result
    }
}

@available(macOS 26.0, *)
final class ProbeInteractiveMenu: Sendable {
    enum Scenario: String, Sendable { case lifecycle, admissionRace, menuLoss, revoke, revocationRace, simulator }
    let scenario: Scenario
    let effects: ProbeInteractiveEffects
    private let input: ProbeInteractiveInputSink
    let mediaQueue: BoundedInteractiveMediaQueueV0
    let runtime: InteractiveMenuRuntimeOwnerV0
    let adapter: MacInteractiveLeaseRuntimeAdapterV1
    let leaseHandler: any MacLocalXPCInteractiveLeaseHandlingV1
    init(scenario: Scenario = .lifecycle) throws {
        self.scenario = scenario
        let queue = try BoundedInteractiveMediaQueueV0(maximumRecords: 64,
                                                       maximumBytes: 16 * 1_024 * 1_024)
        let effects = ProbeInteractiveEffects(queue: queue, streamsMedia: scenario == .simulator)
        let input = ProbeInteractiveInputSink()
        let runtime = InteractiveMenuRuntimeOwnerV0(indicator: effects, capture: effects,
            input: effects, frame: effects, inputPoster: input, mediaQueue: queue)
        self.effects = effects; self.input = input; mediaQueue = queue
        self.runtime = runtime
        let adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime, desktop: effects)
        self.adapter = adapter
        leaseHandler = try ProbeInteractiveLeaseHandler(base: adapter, effects: effects)
        Task { await effects.bind(runtime) }
    }

    func simulatorSnapshot() async -> (captureActive: Bool, inputEvents: Int,
                                       encodedFrames: Int, runtimeIdle: Bool,
                                       queuedRecords: Int, acknowledgements: Int) {
        let effects = await effects.snapshot()
        let state = await runtime.state()
        return (effects.started > effects.stopped, input.snapshot(), effects.encodedFrames,
                state == .idle, mediaQueue.status().recordCount, effects.acknowledgements)
    }
}
