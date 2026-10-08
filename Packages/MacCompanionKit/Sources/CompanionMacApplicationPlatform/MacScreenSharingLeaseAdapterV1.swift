#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CoreGraphics

/// Keeps the existing lease/indicator lifecycle without creating a second video
/// producer. Actual pixels and input belong to the separately authorized RFB
/// tunnel and the system Screen Sharing service.
@available(macOS 26.0, *)
package actor MacScreenSharingLeaseAdapterV1: InteractiveRuntimeCaptureControllingV0 {
    private var activeCommand: InteractiveRuntimeInstallCommandV0?
    private let screenPermission: @Sendable () -> Bool

    package init(screenPermission: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.screenPermission = screenPermission
    }

    package func startInteractiveCapture(_ command: InteractiveRuntimeInstallCommandV0) async throws -> Set<SurfaceInteractionClass> {
        try command.validate()
        guard activeCommand == nil, command.surfaceDescriptor.kind == .desktop else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.bindingMismatch
        }
        guard screenPermission() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.screenRecordingPermissionDenied
        }
        activeCommand = command
        return Set(command.lease.allowedInteractionClasses)
    }

    package func adoptInteractiveLeaseRenewal(_ renewal: InteractiveRuntimeLeaseRenewalV0) async throws {
        guard let activeCommand else { throw MacInteractiveControlRuntimeCompositionErrorV1.bindingMismatch }
        try renewal.validate(current: activeCommand.lease)
        guard screenPermission() else {
            throw MacInteractiveControlRuntimeCompositionErrorV1.screenRecordingPermissionDenied
        }
        self.activeCommand = try InteractiveRuntimeInstallCommandV0(
            protocolVersion: activeCommand.protocolVersion, commandID: activeCommand.commandID,
            lease: renewal.replacement, deviceDisplayName: activeCommand.deviceDisplayName,
            surfaceDescriptor: activeCommand.surfaceDescriptor,
            sessionDeadlineMonotonicNanoseconds: activeCommand.sessionDeadlineMonotonicNanoseconds)
    }

    package func prepareInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0) async throws -> Set<SurfaceInteractionClass> {
        throw MacInteractiveControlRuntimeCompositionErrorV1.surfaceTransitionUnavailable
    }

    package func activatePreparedInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64) async throws {
        throw MacInteractiveControlRuntimeCompositionErrorV1.surfaceTransitionUnavailable
    }

    package func stopInteractiveCapture() async throws { activeCommand = nil }
}
#endif
