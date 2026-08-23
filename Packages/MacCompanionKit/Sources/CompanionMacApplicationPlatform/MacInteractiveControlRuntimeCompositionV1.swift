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
        let capture = MacInteractiveDesktopCaptureAdapterV1(
            displaySelection: displaySelection,
            input: input,
            runtimeReference: runtimeReference
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
        return Self(runtime: runtime, mediaQueue: queue)
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
    private let displaySelection: MacInteractiveOpaqueDisplaySelectionV1
    private let input: MacCoreGraphicsInteractiveInputAdapterV1
    private let runtimeReference: MacInteractiveRuntimeReferenceV1
    private var streamOwner: ScreenCaptureKitStreamOwnerV0?

    init(
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1,
        input: MacCoreGraphicsInteractiveInputAdapterV1,
        runtimeReference: MacInteractiveRuntimeReferenceV1
    ) {
        self.displaySelection = displaySelection
        self.input = input
        self.runtimeReference = runtimeReference
    }

    func startInteractiveCapture(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        guard streamOwner == nil,
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
            let binding = try InteractiveMediaPublicationBindingV0(
                fence: Self.fence(command.lease),
                descriptor: command.surfaceDescriptor
            )
            let publisher = VideoToolboxInteractiveMediaPublisherV0(
                binding: binding,
                runtime: runtime
            )
            let encoderProfile = try VideoToolboxH264EncoderProfileV0(
                capture: captureProfile,
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
                filter: ScreenCaptureKitCaptureConfigurationV0
                    .makeDesktopFilter(display: display),
                profile: captureProfile
            )
            let owner = ScreenCaptureKitStreamOwnerV0(
                session: session,
                encoder: encoder,
                terminal: { [weak runtime] _ in
                    Task { try? await runtime?.invalidateAgentAuthority() }
                }
            )
            streamReference.install(owner)
            try await owner.start()
            streamOwner = owner
            return ready
        } catch {
            input.retireConfiguration()
            throw error
        }
    }

    func prepareInteractiveCaptureTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        throw MacInteractiveControlRuntimeCompositionErrorV1
            .surfaceTransitionUnavailable
    }

    func stopInteractiveCapture() async throws {
        guard let owner = streamOwner else {
            input.retireConfiguration()
            return
        }
        let phase = await owner.phase()
        switch phase {
        case .failed, .stopped:
            break
        case .active, .starting:
            try await owner.stop()
        default:
            throw MacInteractiveControlRuntimeCompositionErrorV1.unavailable
        }
        streamOwner = nil
        input.retireConfiguration()
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
