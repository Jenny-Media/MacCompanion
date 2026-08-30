#if os(macOS)
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionIPC
import Foundation

@available(macOS 26.0, *)
public enum MacInteractiveUnavailableRuntimeEffectErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
}

@available(macOS 26.0, *)
private struct MacInteractiveUnavailableCaptureV1:
    InteractiveRuntimeCaptureControllingV0
{
    func startInteractiveCapture(
        _: InteractiveRuntimeInstallCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        throw MacInteractiveUnavailableRuntimeEffectErrorV1.unavailable
    }

    func adoptInteractiveLeaseRenewal(
        _: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        throw MacInteractiveUnavailableRuntimeEffectErrorV1.unavailable
    }

    func prepareInteractiveCaptureTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        throw MacInteractiveUnavailableRuntimeEffectErrorV1.unavailable
    }

    func activatePreparedInteractiveCaptureTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition _: UInt64
    ) async throws {
        throw MacInteractiveUnavailableRuntimeEffectErrorV1.unavailable
    }

    func stopInteractiveCapture() async throws {}
}

@available(macOS 26.0, *)
private struct MacInteractiveUnavailableInputV1:
    InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeInputPostingV0
{
    func releaseAllInteractiveInput() async throws {}

    func postInteractiveInput(_: InteractiveInputEnvelope) async throws {
        throw MacInteractiveUnavailableRuntimeEffectErrorV1.unavailable
    }
}

@available(macOS 26.0, *)
private struct MacInteractiveUnavailableFrameV1:
    InteractiveRuntimeFrameControllingV0
{
    func blankLastInteractiveFrame() async throws {}
}

@available(macOS 26.0, *)
private struct MacInteractiveUnavailableMediaV1:
    InteractiveRuntimeMediaEnqueuingV0
{
    func enqueueInteractiveMedia(
        header _: MediaRecordHeader,
        payload _: Data
    ) -> Bool {
        false
    }
}

/// Safe permanent composition while concrete capture/media/input effects are
/// still closed. It can prepare Desktop and display the real indicator, but an
/// install fails and fully clears before reporting success because capture is
/// unavailable.
@available(macOS 26.0, *)
public enum MacInteractiveUnavailableRuntimeCompositionV1 {
    @MainActor
    public static func make(
        indicator: MacInteractiveActivityIndicatorV1
    ) -> InteractiveMenuRuntimeOwnerV0 {
        let input = MacInteractiveUnavailableInputV1()
        return InteractiveMenuRuntimeOwnerV0(
            indicator: indicator,
            capture: MacInteractiveUnavailableCaptureV1(),
            input: input,
            frame: MacInteractiveUnavailableFrameV1(),
            inputPoster: input,
            mediaQueue: MacInteractiveUnavailableMediaV1()
        )
    }
}
#endif
