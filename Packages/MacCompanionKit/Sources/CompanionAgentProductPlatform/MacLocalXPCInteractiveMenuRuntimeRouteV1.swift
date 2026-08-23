#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import Foundation

/// Product-layer type adapter that gives the pure Agent runtime owner only the
/// initial Desktop preparation plus the three lease lifecycle operations. It does not expose the local-XPC server,
/// peer generation, presentation surfaces, or status authority.
@available(macOS 26.0, *)
package struct MacLocalXPCInteractiveMenuRuntimeRouteV1:
    AgentInteractiveInitialDesktopPreparingV1,
    AgentInteractiveMenuRuntimeRoutingV1,
    AgentInteractiveSurfaceMenuRoutingV1,
    InteractiveSurfaceRuntimeRoutingV0,
    InteractiveSurfaceTargetResolvingV0,
    InteractiveSurfaceTargetInventoryProvidingV0
{
    private let sender: any MacLocalXPCInteractiveLeaseSendingV1
    private let identifier: @Sendable () -> UUID

    package init(
        sender: any MacLocalXPCInteractiveLeaseSendingV1,
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.sender = sender
        self.identifier = identifier
    }

    package func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor {
        let command = try
            LocalInteractiveInitialDesktopPreparationCommandV1(
                commandID: identifier(),
                interactiveSessionID: request.interactiveSessionID,
                authorizationEpoch: request.authorizationEpoch,
                selectedDisplayID: request.selectedDisplayID,
                interactionClasses: request.interactionClasses
            )
        let receipt = try await sender.prepareInitialInteractiveDesktop(
            command
        )
        try receipt.validate(against: command)
        return receipt.descriptor
    }

    package func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await sender.installInteractiveLease(command)
    }

    package func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await sender.renewInteractiveLease(renewal)
    }

    package func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await sender.revokeInteractiveLease(command)
    }

    package func snapshot(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        guard request.authorizationEpoch == context.authorizationEpoch else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let command = try LocalInteractiveSurfaceTargetsCommandV1(
            commandID: identifier(),
            interactiveSessionID: request.interactiveSessionID.rawValue,
            authorizationEpoch: request.authorizationEpoch
        )
        let receipt = try await sender.interactiveSurfaceTargets(command)
        try receipt.validate(against: command)
        return try receipt.materialize()
    }

    package func resolve(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceDescriptor {
        guard request.authorizationEpoch == context.authorizationEpoch else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let command = try LocalInteractiveSurfaceResolveCommandV1(
            commandID: identifier(),
            interactiveSessionID: request.interactiveSessionID.rawValue,
            authorizationEpoch: request.authorizationEpoch,
            currentSurfaceID: request.currentSurfaceID.rawValue,
            expectedSurfaceRevision: request.expectedSurfaceRevision,
            expectedCoordinateSpaceRevision:
                request.expectedCoordinateSpaceRevision,
            targetKind: request.targetKind,
            targetToken: request.targetToken?.rawValue
        )
        let receipt = try await sender.resolveInteractiveSurface(command)
        try receipt.validate(against: command)
        return receipt.descriptor
    }

    package func focusCandidate(
        current descriptor: AdaptiveSurfaceDescriptor
    ) async throws -> InteractiveFocusEventCandidateV0 {
        let command = try LocalInteractiveFocusSnapshotCommandV1(
            commandID: identifier(),
            interactiveSessionID: descriptor.interactiveSessionID,
            authorizationEpoch: descriptor.authorizationEpoch,
            currentSurfaceID: descriptor.surfaceID,
            expectedSurfaceRevision: descriptor.surfaceRevision,
            expectedCoordinateSpaceRevision:
                descriptor.coordinateSpaceRevision
        )
        let receipt = try await sender.interactiveFocusSnapshot(command)
        try receipt.validate(against: command)
        return try InteractiveFocusEventCandidateV0(
            recommendedTargetKind:
                receipt.candidate.recommendedTargetKind,
            focus: receipt.candidate.focus,
            inputPaused: receipt.candidate.inputPaused,
            reason: receipt.candidate.reason,
            validForMilliseconds:
                receipt.candidate.validForMilliseconds
        )
    }

    package func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await sender.prepareInteractiveSurfaceTransition(command)
    }

    package func acknowledgeSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try await sender.acknowledgeInteractiveSurface(command)
    }

    package func terminateSurfaceFailure(
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) async throws -> Bool {
        let command = LocalInteractiveSurfaceFailureCommandV1(
            commandID: identifier(),
            interactiveSessionID: interactiveSessionID,
            reason: reason
        )
        let receipt = try await sender
            .terminateInteractiveSurfaceFailure(command)
        try receipt.validate(against: command)
        return receipt.terminated
    }
}
#endif
