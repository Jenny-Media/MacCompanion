#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import Foundation

/// The local-XPC transport admits one Interactive lease/surface command at a
/// time. Runtime renewal, focus observation, and client-driven surface work
/// originate from independent actors, so they must converge through one FIFO
/// before reaching that single-flight transport gate. A valid renewal must not
/// fail merely because an advisory focus snapshot is already in flight.
@available(macOS 26.0, *)
private actor MacLocalXPCSerializedInteractiveLeaseSenderV1:
    MacLocalXPCInteractiveLeaseSendingV1
{
    private let base: any MacLocalXPCInteractiveLeaseSendingV1
    private var tail = Task<Void, Never> {}

    init(_ base: any MacLocalXPCInteractiveLeaseSendingV1) {
        self.base = base
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable (
            any MacLocalXPCInteractiveLeaseSendingV1
        ) async throws -> Result
    ) async throws -> Result {
        let predecessor = tail
        let base = self.base
        let task = Task {
            await predecessor.value
            return try await operation(base)
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await enqueue { try await $0.prepareInitialInteractiveDesktop(command) }
    }

    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await enqueue { try await $0.installInteractiveLease(command) }
    }

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await enqueue { try await $0.renewInteractiveLease(renewal) }
    }

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await enqueue { try await $0.revokeInteractiveLease(command) }
    }

    func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try await enqueue { try await $0.interactiveSurfaceTargets(command) }
    }

    func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try await enqueue { try await $0.resolveInteractiveSurface(command) }
    }

    func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await enqueue {
            try await $0.prepareInteractiveSurfaceTransition(command)
        }
    }

    func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try await enqueue { try await $0.acknowledgeInteractiveSurface(command) }
    }

    func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await enqueue {
            try await $0.terminateInteractiveSurfaceFailure(command)
        }
    }

    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        try await enqueue { try await $0.interactiveFocusSnapshot(command) }
    }

    func interactiveDisplayCatalog(
        _ command: LocalInteractiveDisplayCatalogCommandV1
    ) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try await enqueue { try await $0.interactiveDisplayCatalog(command) }
    }

    func selectInteractiveDisplay(
        _ command: LocalInteractiveDisplaySelectCommandV1
    ) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try await enqueue { try await $0.selectInteractiveDisplay(command) }
    }
}

/// Product-layer type adapter that gives the pure Agent runtime owner only the
/// initial Desktop preparation plus the three lease lifecycle operations. It does not expose the local-XPC server,
/// peer generation, presentation surfaces, or status authority.
@available(macOS 26.0, *)
package struct MacLocalXPCInteractiveMenuRuntimeRouteV1:
    AgentInteractiveInitialDesktopPreparingV1,
    AgentInteractiveMenuRuntimeRoutingV1,
    AgentInteractiveSurfaceMenuRoutingV1,
    AgentInteractiveDisplayMenuRoutingV1,
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
        self.sender = MacLocalXPCSerializedInteractiveLeaseSenderV1(sender)
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

    package func interactiveDisplayCatalog()
        async throws -> LocalInteractiveDisplayCatalogReceiptV1
    {
        let command = LocalInteractiveDisplayCatalogCommandV1(
            commandID: identifier()
        )
        let receipt = try await sender.interactiveDisplayCatalog(command)
        try receipt.validate(against: command)
        return receipt
    }

    package func selectInteractiveDisplay(_ displayID: UUID)
        async throws -> LocalInteractiveDisplaySelectedReceiptV1
    {
        let command = LocalInteractiveDisplaySelectCommandV1(
            commandID: identifier(),
            displayID: displayID
        )
        let receipt = try await sender.selectInteractiveDisplay(command)
        try receipt.validate(against: command)
        return receipt
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
