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

    func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try await enqueue { try await $0.nativeBackend(command) }
    }

    func nativeRuntimeSnapshot(_ command: LocalInteractiveNativeSnapshotCommandV1) async throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        try await enqueue { try await $0.nativeRuntimeSnapshot(command) }
    }

    func makeWebRTCOffer(
        _ command: LocalInteractiveWebRTCOfferCommandV1
    ) async throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        try await enqueue { try await $0.makeWebRTCOffer(command) }
    }

    func acceptWebRTCAnswer(
        _ command: LocalInteractiveWebRTCAnswerCommandV1
    ) async throws {
        try await enqueue { try await $0.acceptWebRTCAnswer(command) }
    }

    func closeWebRTC(
        _ command: LocalInteractiveWebRTCCloseCommandV1
    ) async throws {
        try await enqueue { try await $0.closeWebRTC(command) }
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
    InteractiveSurfaceTargetInventoryProvidingV0,
    InteractiveWebRTCNegotiatingV0,
    InteractiveNativeVideoRuntimeProvidingV0
{
    private let sender: any MacLocalXPCInteractiveLeaseSendingV1
    private let nativeBackendFactory: (@Sendable (InteractiveNativeVideoRuntimeSnapshotV0) async throws -> any InteractiveNativeVideoEnrollmentBackendV0)?
    private let identifier: @Sendable () -> UUID

    package init(
        sender: any MacLocalXPCInteractiveLeaseSendingV1,
        identifier: @escaping @Sendable () -> UUID = { UUID() },
        nativeBackendFactory: (@Sendable (InteractiveNativeVideoRuntimeSnapshotV0) async throws -> any InteractiveNativeVideoEnrollmentBackendV0)? = nil
    ) {
        self.sender = MacLocalXPCSerializedInteractiveLeaseSenderV1(sender)
        self.identifier = identifier
        self.nativeBackendFactory = nativeBackendFactory
    }

    package func snapshot(fence: InteractiveNativeVideoRequestFenceV0,
        context: InteractiveSessionCommandContextV0) async throws -> InteractiveNativeVideoRuntimeSnapshotV0? {
        guard fence.authorizationEpoch == context.authorizationEpoch else { return nil }
        let command = try LocalInteractiveNativeSnapshotCommandV1(commandID: identifier(), fence: fence)
        let receipt = try await sender.nativeRuntimeSnapshot(command)
        try receipt.validate(against: command)
        let value = receipt.snapshot
        guard value.hostID == context.hostID, value.deviceID == context.deviceID,
              value.isCurrent(nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds) else { return nil }
        let binding = try InteractiveNativeVideoBindingV0(hostID: context.hostID, hostFingerprint: context.hostFingerprint,
            clientID: context.clientID, primaryConnectionID: context.primaryConnectionID,
            interactiveSessionID: fence.interactiveSessionID.rawValue, authorizationEpoch: Int64(context.authorizationEpoch.rawValue),
            grantRevision: Int64(context.grantRevision.rawValue), policyRevision: Int64(context.policyRevision.rawValue),
            controlGeneration: value.controlGeneration,
            expiresAtMonotonicMilliseconds: value.sessionDeadlineMonotonicNanoseconds / 1_000_000)
        let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: fence.surfaceID.rawValue,
            surfaceRevision: fence.surfaceRevision, coordinateSpaceRevision: fence.coordinateSpaceRevision,
            encodedWidth: value.encodedWidth, encodedHeight: value.encodedHeight)
        return .init(binding: binding, surface: surface,
            logicalWidthPoints: value.logicalWidthPoints, logicalHeightPoints: value.logicalHeightPoints, rotation: value.rotation,
            selectedDisplayID: value.selectedDisplayID,
            visibleMenuAppGeneration: value.menuAppGeneration, visibleMenuAppRevision: value.menuAppRevision)
    }

    package func makeBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0) async throws -> any InteractiveNativeVideoEnrollmentBackendV0 {
        if let nativeBackendFactory { return try await nativeBackendFactory(snapshot) }
        return MacLocalXPCNativeEnrollmentBackendV1(sender: sender, snapshot: snapshot)
    }
    package func makeReplacementBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0,
        retained: InteractiveNativeVideoRetainedEnrollmentV1) async throws -> any InteractiveNativeVideoEnrollmentBackendV0 {
        guard nativeBackendFactory == nil, let previous = retained.backend as? MacLocalXPCNativeEnrollmentBackendV1 else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return try await previous.replacementBackend(snapshot: snapshot, retained: retained)
    }

    package func makeOffer(
        fence: InteractiveWebRTCNegotiationFenceV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveWebRTCOfferBodyV0 {
        guard fence.authorizationEpoch == context.authorizationEpoch else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let command = try LocalInteractiveWebRTCOfferCommandV1(
            commandID: identifier(), fence: fence
        )
        let receipt = try await sender.makeWebRTCOffer(command)
        try receipt.validate(against: command)
        return receipt.offer
    }

    package func acceptAnswer(
        _ answer: InteractiveWebRTCAnswerBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws {
        guard answer.fence.authorizationEpoch
                == context.authorizationEpoch else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let command = try LocalInteractiveWebRTCAnswerCommandV1(
            commandID: identifier(), answer: answer
        )
        try await sender.acceptWebRTCAnswer(command)
    }

    package func close(interactiveSessionID: UUID) async {
        try? await sender.closeWebRTC(
            LocalInteractiveWebRTCCloseCommandV1(
                commandID: identifier(),
                interactiveSessionID: interactiveSessionID
            )
        )
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
