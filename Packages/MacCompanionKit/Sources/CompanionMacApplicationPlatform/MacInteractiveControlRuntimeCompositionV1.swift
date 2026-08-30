#if os(macOS)
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

private let macInteractiveCaptureLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion",
    category: "interactive-capture"
)

public enum MacInteractiveControlRuntimeCompositionErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case bindingMismatch
    case screenRecordingPermissionDenied
    case surfaceTransitionUnavailable
}

@available(macOS 26.0, *)
public struct MacInteractiveControlRuntimeCompositionV1: Sendable {
    public let runtime: InteractiveMenuRuntimeOwnerV0
    public let mediaQueue: BoundedInteractiveMediaQueueV0
    public let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1

    public static func make(
        indicator: MacInteractiveActivityIndicatorV1,
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1
    ) throws -> Self {
        let queue = try BoundedInteractiveMediaQueueV0(
            // Capture necessarily starts before the client can open its
            // authenticated media role. Retain two seconds of 30 fps startup
            // output (plus configuration/keyframe records) so an ordinary
            // role handshake cannot be mistaken for terminal backpressure.
            // The independent byte bound remains the hard memory ceiling.
            maximumRecords: 64,
            maximumBytes: 16 * 1_024 * 1_024
        )
        let input = MacCoreGraphicsInteractiveInputAdapterV1()
        let runtimeReference = MacInteractiveRuntimeReferenceV1()
        let surfaceTargets = MacInteractiveSurfaceTargetOwnerV1()
        let capture = MacInteractiveDesktopCaptureAdapterV1(
            displaySelection: displaySelection,
            input: input,
            runtimeReference: runtimeReference,
            surfaceTargets: surfaceTargets
        )
        let frame = QueuePurgingInteractiveFrameControllerV0(
            queue: queue,
            renderer: MacInteractiveNoRetainedRendererV1()
        )
        let runtime = InteractiveMenuRuntimeOwnerV0(
            indicator: indicator,
            capture: capture,
            input: input,
            frame: frame,
            inputPoster: input,
            mediaQueue: queue
        )
        runtimeReference.install(runtime)
        return Self(
            runtime: runtime,
            mediaQueue: queue,
            surfaceTargets: surfaceTargets
        )
    }
}

@available(macOS 26.0, *)
private final class MacInteractiveRuntimeReferenceV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private weak var runtime: InteractiveMenuRuntimeOwnerV0?

    func install(_ runtime: InteractiveMenuRuntimeOwnerV0) {
        lock.withLock { self.runtime = runtime }
    }

    func value() -> InteractiveMenuRuntimeOwnerV0? {
        lock.withLock { runtime }
    }
}

@available(macOS 26.0, *)
private final class MacInteractiveStreamOwnerReferenceV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private weak var owner: ScreenCaptureKitStreamOwnerV0?

    func install(_ owner: ScreenCaptureKitStreamOwnerV0) {
        lock.withLock { self.owner = owner }
    }

    func value() -> ScreenCaptureKitStreamOwnerV0? {
        lock.withLock { owner }
    }
}

private struct MacInteractiveNoRetainedRendererV1:
    InteractiveRuntimeRenderedFrameBlankingV0
{
    func blankRenderedInteractiveFrame() async throws {}
}

/// Desktop-only release capture owner. It re-resolves the opaque display
/// after ScreenCaptureKit enumeration, constructs the complete H.264 graph,
/// and retains that graph until ordered runtime cleanup stops it.
@available(macOS 26.0, *)
private actor MacInteractiveDesktopCaptureAdapterV1:
    InteractiveRuntimeCaptureControllingV0
{
    private struct PreparedTransition {
        let command: InteractiveRuntimeSurfaceTransitionCommandV0
        let replacementCommand: InteractiveRuntimeInstallCommandV0
        let resolved: ScreenCaptureKitResolvedSurfaceV0
        let binding: InteractiveMediaPublicationBindingV0
        let readyClasses: Set<SurfaceInteractionClass>
    }

    private let displaySelection: MacInteractiveOpaqueDisplaySelectionV1
    private let input: MacCoreGraphicsInteractiveInputAdapterV1
    private let runtimeReference: MacInteractiveRuntimeReferenceV1
    private let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1
    private let surfaceActivator =
        MacInteractiveSelectedSurfaceActivatorV1()
    private var streamOwner: ScreenCaptureKitStreamOwnerV0?
    private var streamGeneration: UUID?
    private var publisher: VideoToolboxInteractiveMediaPublisherV0?
    private var activeCommand: InteractiveRuntimeInstallCommandV0?
    private var preparedTransition: PreparedTransition?

    init(
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1,
        input: MacCoreGraphicsInteractiveInputAdapterV1,
        runtimeReference: MacInteractiveRuntimeReferenceV1,
        surfaceTargets: MacInteractiveSurfaceTargetOwnerV1
    ) {
        self.displaySelection = displaySelection
        self.input = input
        self.runtimeReference = runtimeReference
        self.surfaceTargets = surfaceTargets
    }

    func startInteractiveCapture(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        macInteractiveCaptureLoggerV1.notice("capture preparation started")
        guard streamOwner == nil, publisher == nil,
              activeCommand == nil, preparedTransition == nil,
              command.surfaceDescriptor.kind == .desktop,
              command.surfaceDescriptor.interactionClasses
                == command.lease.allowedInteractionClasses,
              let runtime = runtimeReference.value() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.unavailable
        }
        try command.validate()
        guard CGPreflightScreenCaptureAccess() else {
            macInteractiveCaptureLoggerV1.error(
                "screen recording permission is unavailable"
            )
            // Control was already granted locally for this named device and
            // freshly approved on the phone. Ask macOS for its independent
            // capture consent, but never treat displaying that prompt as a
            // grant or continue into capture in this attempt.
            _ = CGRequestScreenCaptureAccess()
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .screenRecordingPermissionDenied
        }
        macInteractiveCaptureLoggerV1.notice(
            "screen recording permission is available"
        )
        let physicalDisplayID = try displaySelection
            .resolvePhysicalDisplayID(
                selectedDisplayID: command.lease.selectedDisplayID
            )
        macInteractiveCaptureLoggerV1.notice(
            "shareable content request started"
        )
        let content = try await SCShareableContent.current
        macInteractiveCaptureLoggerV1.notice(
            "shareable content request completed"
        )
        let revalidatedDisplayID = try displaySelection
            .resolvePhysicalDisplayID(
                selectedDisplayID: command.lease.selectedDisplayID
            )
        guard revalidatedDisplayID == physicalDisplayID,
              let display = content.displays.first(where: {
                $0.displayID == physicalDisplayID
              }) else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.unavailable
        }
        let captureProfile = try ScreenCaptureKitCaptureProfileV0(
            width: Int(command.surfaceDescriptor.encodedWidth),
            height: Int(command.surfaceDescriptor.encodedHeight),
            framesPerSecond: 30,
            queueDepth: 3
        )
        guard display.width > 0, display.height > 0 else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        let ready = try input.configure(
            command: command,
            physicalDisplayID: physicalDisplayID
        )
        macInteractiveCaptureLoggerV1.notice(
            "interactive input configuration completed"
        )
        do {
            try await surfaceTargets.bindInstalledLease(command)
            let binding = try InteractiveMediaPublicationBindingV0(
                fence: Self.fence(command.lease),
                descriptor: command.surfaceDescriptor
            )
            let publisher = VideoToolboxInteractiveMediaPublisherV0(
                binding: binding,
                runtime: runtime
            )
            let generation = UUID()
            let owner = try Self.makeStreamOwner(
                filter: ScreenCaptureKitCaptureConfigurationV0
                    .makeDesktopFilter(display: display),
                profile: captureProfile,
                publisher: publisher,
                terminated: { [weak self] reason in
                    Task {
                        await self?.streamTerminated(
                            reason,
                            generation: generation
                        )
                    }
                }
            )
            streamGeneration = generation
            macInteractiveCaptureLoggerV1.notice(
                "screen capture stream start requested"
            )
            try await owner.start()
            macInteractiveCaptureLoggerV1.notice(
                "screen capture stream started"
            )
            streamOwner = owner
            self.publisher = publisher
            activeCommand = command
            return ready
        } catch {
            streamGeneration = nil
            macInteractiveCaptureLoggerV1.error(
                "capture preparation failed: \(String(describing: error), privacy: .public)"
            )
            input.retireConfiguration()
            await surfaceTargets.invalidate()
            throw error
        }
    }

    func adoptInteractiveLeaseRenewal(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        guard let activeCommand, let publisher,
              preparedTransition == nil else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        try renewal.validate(current: activeCommand.lease)
        let replacementCommand = try InteractiveRuntimeInstallCommandV0(
            protocolVersion: activeCommand.protocolVersion,
            commandID: activeCommand.commandID,
            lease: renewal.replacement,
            deviceDisplayName: activeCommand.deviceDisplayName,
            surfaceDescriptor: activeCommand.surfaceDescriptor,
            sessionDeadlineMonotonicNanoseconds:
                activeCommand.sessionDeadlineMonotonicNanoseconds
        )
        let replacementBinding = try InteractiveMediaPublicationBindingV0(
            fence: Self.fence(renewal.replacement),
            descriptor: activeCommand.surfaceDescriptor
        )
        guard await publisher.adoptLeaseRenewal(
            to: replacementBinding
        ) else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        try await surfaceTargets.adoptRenewedLease(renewal)
        self.activeCommand = replacementCommand
        macInteractiveCaptureLoggerV1.notice(
            "capture lease fence adopted counter=\(renewal.replacement.renewalCounter, privacy: .public)"
        )
    }

    func prepareInteractiveCaptureTransition(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        guard let activeCommand, let owner = streamOwner,
              publisher != nil, preparedTransition == nil,
              transition.previousLeaseID
                == activeCommand.lease.leaseID,
              transition.replacement.interactiveSessionID
                == activeCommand.lease.interactiveSessionID,
              transition.descriptor.kind == .desktop
                || transition.descriptor.kind == .application
                || transition.descriptor.kind == .window
                || transition.descriptor.kind == .focusedRegion else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        let physicalDisplayID = try displaySelection
            .resolvePhysicalDisplayID(
                selectedDisplayID: transition.replacement.selectedDisplayID
            )
        let resolved = try await surfaceTargets.takePreparedSurface(
            for: transition
        )
        guard resolved.descriptor == transition.descriptor,
              resolved.profile.width
                == Int(transition.descriptor.encodedWidth),
              resolved.profile.height
                == Int(transition.descriptor.encodedHeight) else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        streamGeneration = nil
        try await owner.stop()
        streamOwner = nil
        // In-flight old-source output keeps only its old publisher/fence.
        // Never let a delayed completion mutate replacement media state.
        publisher = nil
        input.retireConfiguration()
        let replacementCommand = try InteractiveRuntimeInstallCommandV0(
            protocolVersion: activeCommand.protocolVersion,
            commandID: activeCommand.commandID,
            lease: transition.replacement,
            deviceDisplayName: activeCommand.deviceDisplayName,
            surfaceDescriptor: transition.descriptor,
            sessionDeadlineMonotonicNanoseconds:
                activeCommand.sessionDeadlineMonotonicNanoseconds
        )
        let ready = try input.configure(
            command: replacementCommand,
            physicalDisplayID: physicalDisplayID,
            inputBounds: resolved.inputBounds,
            inputBackingScaleFactor:
                resolved.inputBackingScaleFactor,
            activationTarget: resolved.localActivationTarget
        )
        let binding = try InteractiveMediaPublicationBindingV0(
            fence: Self.fence(transition.replacement),
            descriptor: transition.descriptor
        )
        preparedTransition = PreparedTransition(
            command: transition,
            replacementCommand: replacementCommand,
            resolved: resolved,
            binding: binding,
            readyClasses: ready
        )
        return ready
    }

    func activatePreparedInteractiveCaptureTransition(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64
    ) async throws {
        guard let prepared = preparedTransition,
              prepared.command == transition,
              streamOwner == nil,
              publisher == nil,
              let runtime = runtimeReference.value() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        switch prepared.resolved.descriptor.kind {
        case .application, .window:
            guard prepared.resolved.localActivationTarget != nil else {
                throw MacInteractiveControlRuntimeCompositionErrorV1
                    .bindingMismatch
            }
        case .desktop:
            guard prepared.resolved.localActivationTarget == nil else {
                throw MacInteractiveControlRuntimeCompositionErrorV1
                    .bindingMismatch
            }
        case .focusedRegion:
            break
        }
        try await surfaceActivator.activate(
            prepared.resolved.localActivationTarget
        )
        let publisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: prepared.binding,
            runtime: runtime,
            resumingAfterMediaSequence: mediaSequenceBeforeTransition
        )
        let generation = UUID()
        let owner = try Self.makeStreamOwner(
            filter: prepared.resolved.filter,
            profile: prepared.resolved.profile,
            sourceRect: prepared.resolved.sourceRect,
            publisher: publisher,
            terminated: { [weak self] reason in
                Task {
                    await self?.streamTerminated(
                        reason,
                        generation: generation
                    )
                }
            }
        )
        streamGeneration = generation
        try await owner.start()
        try await surfaceTargets.commit(transition)
        streamOwner = owner
        self.publisher = publisher
        activeCommand = prepared.replacementCommand
        preparedTransition = nil
    }

    func stopInteractiveCapture() async throws {
        streamGeneration = nil
        if let owner = streamOwner {
            let phase = await owner.phase()
            switch phase {
            case .failed, .stopped:
                break
            case .active, .starting:
                try await owner.stop()
            default:
                throw MacInteractiveControlRuntimeCompositionErrorV1
                    .unavailable
            }
        }
        streamOwner = nil
        publisher = nil
        activeCommand = nil
        preparedTransition = nil
        input.retireConfiguration()
        await surfaceTargets.invalidate()
    }

    /// ScreenCaptureKit stops an otherwise healthy display stream when the
    /// console locks. Keep the approved session and its renewing lease, but
    /// retire input immediately and rebuild capture only after the platform
    /// can produce a new stream. Every attempt inserts a decoder
    /// discontinuity; the replacement encoder must then publish fresh
    /// configuration and a clean keyframe before the client renders again.
    private func streamTerminated(
        _ reason: ScreenCaptureKitStreamTerminationReasonV0,
        generation: UUID
    ) async {
        guard streamGeneration == generation else { return }
        streamGeneration = nil
        streamOwner = nil
        input.retireConfiguration()

        guard reason == .captureStoppedBySystem,
              activeCommand != nil, publisher != nil,
              preparedTransition == nil else {
            if let runtime = runtimeReference.value() {
                try? await runtime.invalidateAgentAuthority()
            }
            return
        }
        macInteractiveCaptureLoggerV1.notice(
            "system-stopped capture scheduled for recovery"
        )
        scheduleCaptureRecovery()
    }

    private nonisolated func scheduleCaptureRecovery() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.recoverSystemStoppedCapture()
        }
    }

    private func recoverSystemStoppedCapture() async {
        guard streamOwner == nil, streamGeneration == nil,
              let activeCommand, let publisher,
              preparedTransition == nil else { return }
        do {
            let physicalDisplayID = try displaySelection
                .resolvePhysicalDisplayID(
                    selectedDisplayID:
                        activeCommand.lease.selectedDisplayID
                )
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: {
                $0.displayID == physicalDisplayID
            }) else {
                throw MacInteractiveControlRuntimeCompositionErrorV1
                    .unavailable
            }
            let profile = try ScreenCaptureKitCaptureProfileV0(
                width: Int(activeCommand.surfaceDescriptor.encodedWidth),
                height: Int(activeCommand.surfaceDescriptor.encodedHeight),
                framesPerSecond: 30,
                queueDepth: 3
            )
            _ = try input.configure(
                command: activeCommand,
                physicalDisplayID: physicalDisplayID
            )
            guard await publisher.publishDiscontinuity(
                presentationTimeNanoseconds:
                    DispatchTime.now().uptimeNanoseconds
            ) else {
                throw MacInteractiveControlRuntimeCompositionErrorV1
                    .unavailable
            }
            let generation = UUID()
            let owner = try Self.makeStreamOwner(
                filter: ScreenCaptureKitCaptureConfigurationV0
                    .makeDesktopFilter(display: display),
                profile: profile,
                publisher: publisher,
                terminated: { [weak self] reason in
                    Task {
                        await self?.streamTerminated(
                            reason,
                            generation: generation
                        )
                    }
                }
            )
            streamGeneration = generation
            try await owner.start()
            guard streamGeneration == generation,
                  await owner.phase() == .active else { return }
            streamOwner = owner
            macInteractiveCaptureLoggerV1.notice(
                "system-stopped capture recovered"
            )
        } catch {
            streamGeneration = nil
            streamOwner = nil
            input.retireConfiguration()
            macInteractiveCaptureLoggerV1.notice(
                "system-stopped capture retry pending error=\(String(describing: error), privacy: .public)"
            )
            guard self.activeCommand != nil, self.publisher != nil,
                  preparedTransition == nil else { return }
            scheduleCaptureRecovery()
        }
    }

    private static func makeStreamOwner(
        filter: sending SCContentFilter,
        profile: ScreenCaptureKitCaptureProfileV0,
        sourceRect: CGRect? = nil,
        publisher: VideoToolboxInteractiveMediaPublisherV0,
        terminated: @escaping @Sendable (
            ScreenCaptureKitStreamTerminationReasonV0
        ) -> Void
    ) throws -> ScreenCaptureKitStreamOwnerV0 {
        let encoderProfile = try VideoToolboxH264EncoderProfileV0(
            capture: profile,
            targetBitrateBitsPerSecond: 8_000_000,
            keyframeIntervalMilliseconds: 2_000
        )
        let compression = try VideoToolboxH264CompressionSessionV0(
            profile: encoderProfile
        )
        let streamReference = MacInteractiveStreamOwnerReferenceV1()
        let encoder = VideoToolboxH264EncoderOwnerV0(
            profile: encoderProfile,
            session: compression,
            output: { sample in await publisher.publish(sample) },
            terminal: { reason in
                macInteractiveCaptureLoggerV1.error(
                    "interactive encoder terminated reason=\(reason.rawValue, privacy: .public)"
                )
                Task {
                    await streamReference.value()?.encoderTerminated()
                }
            }
        )
        let session = ScreenCaptureKitStreamingSessionAdapterV0(
            filter: filter,
            profile: profile,
            sourceRect: sourceRect
        )
        let owner = ScreenCaptureKitStreamOwnerV0(
            session: session,
            encoder: encoder,
            terminal: { reason in
                macInteractiveCaptureLoggerV1.error(
                    "interactive capture terminated reason=\(reason.rawValue, privacy: .public)"
                )
                terminated(reason)
            }
        )
        streamReference.install(owner)
        return owner
    }

    private static func fence(
        _ lease: InteractiveExecutionLease
    ) -> InteractiveCommandFence {
        InteractiveCommandFence(
            leaseID: lease.leaseID,
            hostID: lease.hostID,
            deviceID: lease.deviceID,
            interactiveSessionID: lease.interactiveSessionID,
            authorizationEpoch: lease.authorizationEpoch,
            selectedDisplayID: lease.selectedDisplayID,
            surfaceID: lease.surfaceID,
            surfaceRevision: lease.surfaceRevision,
            coordinateRevision: lease.coordinateRevision
        )
    }
}
#endif
