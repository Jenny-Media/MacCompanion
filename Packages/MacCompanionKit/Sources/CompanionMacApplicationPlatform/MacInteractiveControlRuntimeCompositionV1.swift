#if os(macOS)
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum MacInteractiveControlRuntimeCompositionErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case bindingMismatch
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
            maximumRecords: 8,
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
    private var streamOwner: ScreenCaptureKitStreamOwnerV0?
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
        guard streamOwner == nil, publisher == nil,
              activeCommand == nil, preparedTransition == nil,
              command.surfaceDescriptor.kind == .desktop,
              command.surfaceDescriptor.interactionClasses
                == command.lease.allowedInteractionClasses,
              let runtime = runtimeReference.value() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.unavailable
        }
        try command.validate()
        let physicalDisplayID = try displaySelection
            .resolvePhysicalDisplayID(
                selectedDisplayID: command.lease.selectedDisplayID
            )
        let content = try await SCShareableContent.current
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
            let owner = try Self.makeStreamOwner(
                filter: ScreenCaptureKitCaptureConfigurationV0
                    .makeDesktopFilter(display: display),
                profile: captureProfile,
                publisher: publisher,
                runtime: runtime
            )
            try await owner.start()
            streamOwner = owner
            self.publisher = publisher
            activeCommand = command
            return ready
        } catch {
            input.retireConfiguration()
            await surfaceTargets.invalidate()
            throw error
        }
    }

    func prepareInteractiveCaptureTransition(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        guard let activeCommand, let owner = streamOwner,
              let publisher, preparedTransition == nil,
              transition.previousLeaseID
                == activeCommand.lease.leaseID,
              transition.replacement.interactiveSessionID
                == activeCommand.lease.interactiveSessionID,
              transition.descriptor.kind == .desktop
                || transition.descriptor.kind == .application
                || transition.descriptor.kind == .window else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        _ = publisher
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
        try await owner.stop()
        streamOwner = nil
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
                resolved.inputBackingScaleFactor
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
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws {
        guard let prepared = preparedTransition,
              prepared.command == transition,
              streamOwner == nil,
              let publisher,
              let runtime = runtimeReference.value() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .bindingMismatch
        }
        guard await publisher.transition(
            to: prepared.binding,
            presentationTimeNanoseconds:
                DispatchTime.now().uptimeNanoseconds
        ) else {
            throw MacInteractiveControlRuntimeCompositionErrorV1
                .unavailable
        }
        let owner = try Self.makeStreamOwner(
            filter: prepared.resolved.filter,
            profile: prepared.resolved.profile,
            publisher: publisher,
            runtime: runtime
        )
        try await owner.start()
        try await surfaceTargets.commit(transition)
        streamOwner = owner
        activeCommand = prepared.replacementCommand
        preparedTransition = nil
    }

    func stopInteractiveCapture() async throws {
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

    private static func makeStreamOwner(
        filter: sending SCContentFilter,
        profile: ScreenCaptureKitCaptureProfileV0,
        publisher: VideoToolboxInteractiveMediaPublisherV0,
        runtime: InteractiveMenuRuntimeOwnerV0
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
            terminal: { _ in
                Task {
                    await streamReference.value()?.encoderTerminated()
                }
            }
        )
        let session = ScreenCaptureKitStreamingSessionAdapterV0(
            filter: filter,
            profile: profile
        )
        let owner = ScreenCaptureKitStreamOwnerV0(
            session: session,
            encoder: encoder,
            terminal: { [weak runtime] _ in
                Task { try? await runtime?.invalidateAgentAuthority() }
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
