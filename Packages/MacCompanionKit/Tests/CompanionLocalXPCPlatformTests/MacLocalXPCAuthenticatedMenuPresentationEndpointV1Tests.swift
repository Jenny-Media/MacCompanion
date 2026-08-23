@testable import CompanionLocalXPCPlatform
import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
import CompanionWire
import Foundation
import Testing

private actor MenuPresentationSenderProbeV1:
    MacLocalXPCMenuPresentationSendingV1,
    MacLocalXPCGenerationBoundInteractiveLeaseSendingV1
{
    enum Response: Sendable {
        case acknowledged
        case rejected
        case failed(MacLocalXPCMenuPresentationSendErrorV1)
        case cancelledBeforeSend
    }

    private var responses: [Response]
    private var requests: [MacLocalXPCMenuPresentationRequestV1] = []
    private var retirements: [(UInt64, UUID)] = []
    private var desktopReceipt:
        LocalInteractiveInitialDesktopPreparedReceiptV1?
    private var surfaceFailureReceipt:
        LocalInteractiveSurfaceFailureReceiptV1?
    private var focusSnapshotReceipt:
        LocalInteractiveFocusSnapshotReceiptV1?
    private var interactiveGenerations: [UInt64] = []
    private var interactiveTokens: [UUID] = []

    init(
        _ responses: [Response],
        desktopReceipt:
            LocalInteractiveInitialDesktopPreparedReceiptV1? = nil,
        surfaceFailureReceipt:
            LocalInteractiveSurfaceFailureReceiptV1? = nil,
        focusSnapshotReceipt:
            LocalInteractiveFocusSnapshotReceiptV1? = nil
    ) {
        self.responses = responses
        self.desktopReceipt = desktopReceipt
        self.surfaceFailureReceipt = surfaceFailureReceipt
        self.focusSnapshotReceipt = focusSnapshotReceipt
    }

    func sendMenuPresentation(
        generation: UInt64,
        endpointToken: UUID,
        request: MacLocalXPCMenuPresentationRequestV1
    ) async throws -> MacLocalXPCMenuPresentationSendOutcomeV1 {
        requests.append(request)
        let response = responses.isEmpty
            ? Response.acknowledged
            : responses.removeFirst()
        switch response {
        case .acknowledged:
            return .acknowledged
        case .rejected:
            return .rejectedWithoutRetainedState
        case .failed(let error):
            throw error
        case .cancelledBeforeSend:
            throw CancellationError()
        }
    }

    func retireMenuPresentationEndpoint(
        generation: UInt64,
        endpointToken: UUID
    ) {
        retirements.append((generation, endpointToken))
    }

    func recordedRequests() -> [MacLocalXPCMenuPresentationRequestV1] {
        requests
    }

    func retirementCount() -> Int { retirements.count }

    func prepareInitialInteractiveDesktop(
        generation: UInt64,
        endpointToken: UUID,
        command _: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        interactiveGenerations.append(generation)
        interactiveTokens.append(endpointToken)
        guard let desktopReceipt else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        return desktopReceipt
    }

    func installInteractiveLease(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    func renewInteractiveLease(
        generation _: UInt64,
        endpointToken _: UUID,
        renewal _: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    func revokeInteractiveLease(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    func terminateInteractiveSurfaceFailure(
        generation: UInt64,
        endpointToken: UUID,
        command _: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        interactiveGenerations.append(generation)
        interactiveTokens.append(endpointToken)
        guard let surfaceFailureReceipt else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        return surfaceFailureReceipt
    }

    func interactiveFocusSnapshot(
        generation: UInt64,
        endpointToken: UUID,
        command _: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        interactiveGenerations.append(generation)
        interactiveTokens.append(endpointToken)
        guard let focusSnapshotReceipt else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        return focusSnapshotReceipt
    }

    func recordedInteractiveGenerations() -> [UInt64] {
        interactiveGenerations
    }

    func recordedInteractiveTokens() -> [UUID] { interactiveTokens }
}

private func endpointPairingReviewV1() throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: UUID(uuidString: "018f4300-0000-7000-8000-0000000000b1")!,
        pairingID: UUID(uuidString: "018f4000-0000-7000-8000-0000000000b1")!,
        clientID: UUID(uuidString: "018f2000-0000-7000-8000-0000000000b1")!,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x61, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x62, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x63, count: 32)),
        authenticationString: PairingAuthenticationString("23F-6F5"),
        expectedPolicyRevision: PolicyRevision(rawValue: 7),
        expiresAtUnixMilliseconds: 1_787_198_700_000
    )
}

private func endpointRecoveryReviewV1()
    throws -> LocalHostIdentityRecoveryReviewV0
{
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        hostFingerprint: WireFingerprint(Data(repeating: 0x31, count: 32)),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: 1_787_284_800_000,
        expiresAtUnixMilliseconds: 1_787_285_100_000
    )
}

private func endpointRecoveryCommandV1()
    throws -> LocalHostIdentityRecoveryCommandV0
{
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        review: endpointRecoveryReviewV1(),
        confirmedAtUnixMilliseconds: 1_787_284_800_001
    )
}

private func endpointV1(
    sender: MenuPresentationSenderProbeV1,
    generation: UInt64 = 7,
    token: UUID = UUID()
) -> MacLocalXPCAuthenticatedMenuPresentationEndpointV1 {
    MacLocalXPCAuthenticatedMenuPresentationEndpointV1(
        generation: generation,
        endpointToken: token,
        sender: sender
    )
}

private func endpointInitialDesktopCommandV1()
    throws -> LocalInteractiveInitialDesktopPreparationCommandV1
{
    try LocalInteractiveInitialDesktopPreparationCommandV1(
        commandID: UUID(),
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 1),
        selectedDisplayID: UUID(),
        interactionClasses: [.view]
    )
}

private func endpointInitialDesktopReceiptV1(
    command: LocalInteractiveInitialDesktopPreparationCommandV1
) throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
    try LocalInteractiveInitialDesktopPreparedReceiptV1(
        correlationID: command.commandID,
        descriptor: AdaptiveSurfaceDescriptor(
            interactiveSessionID: command.interactiveSessionID,
            authorizationEpoch: command.authorizationEpoch,
            surfaceID: UUID(),
            kind: .desktop,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: 100,
            encodedHeight: 100,
            logicalWidthPoints: 100,
            logicalHeightPoints: 100,
            interactionClasses: [.view],
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1,
            expiresAtMonotonicMilliseconds: 10_001
        )
    )
}

@Test
func endpointIssuanceRequiresExactReadinessAndCachesOneOpaqueToken() {
    var gate = MacLocalXPCMenuPresentationEndpointIssuanceGateV1(
        generation: 7
    )
    let token = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    #expect(gate.issue(generation: 7, permitted: true) == nil)
    let wrongReadiness = gate.publishReadiness(generation: 8)
    #expect(!wrongReadiness)
    let exactReadiness = gate.publishReadiness(generation: 7)
    #expect(exactReadiness)
    #expect(gate.issue(generation: 7, permitted: false) == nil)
    #expect(gate.issue(generation: 8, permitted: true) == nil)
    #expect(
        gate.issue(generation: 7, permitted: true, makeToken: { token })
            == token
    )
    #expect(
        gate.issue(generation: 7, permitted: true, makeToken: { UUID() })
            == token
    )
    gate.invalidate(generation: 7)
    #expect(gate.issue(generation: 7, permitted: true) == nil)
}

@Test
@available(macOS 26.0, *)
func presentationProfileIsExplicitAndKeepsPermanentProfileInert() {
    #expect(
        !MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus
            .admitsMenuPresentation
    )
    #expect(
        !MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus
            .admitsMenuPairingCommands
    )
    #expect(
        !MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus
            .admitsUpdateQuiescence
    )
    #expect(
        MacLocalXPCServerProfileV1
            .menuLifecycleReadinessStatusAndPresentation
            .admitsMenuLifecycleReadiness
    )
    #expect(
        MacLocalXPCServerProfileV1
            .menuLifecycleReadinessStatusAndPresentation
            .admitsAgentStatus
    )
    #expect(
        MacLocalXPCServerProfileV1
            .menuLifecycleReadinessStatusAndPresentation
            .admitsMenuPresentation
    )
    #expect(
        MacLocalXPCServerProfileV1
            .menuLifecycleReadinessStatusAndPresentation
            .admitsMenuPairingCommands
    )
    #expect(
        MacLocalXPCServerProfileV1
            .menuLifecycleReadinessStatusAndPresentation
            .admitsUpdateQuiescence
    )
    #expect(
        MacLocalXPCServerV1.maximumAdmittedPresentationsPerGeneration == 8
    )
    #expect(MacLocalXPCServerV1.presentationReplyTimeoutSeconds == 3)
    #expect(MacLocalXPCServerV1.menuPairingCommandTimeoutSeconds == 4)
    #expect(MacLocalXPCServerV1.updateQuiescenceCommandTimeoutSeconds == 4)
}

@Test
func opaqueEndpointEncodesAllFiveClosedRequests() async throws {
    let sender = MenuPresentationSenderProbeV1(
        Array(repeating: .acknowledged, count: 5)
    )
    let endpoint = endpointV1(sender: sender)
    let pairing = try endpointPairingReviewV1()
    let recovery = try endpointRecoveryReviewV1()
    let resume = try endpointRecoveryCommandV1()

    try await endpoint.presentLocalPairingReview(pairing)
    await endpoint.withdrawLocalPairingReview(reviewID: pairing.reviewID)
    try await endpoint.presentHostIdentityRecoveryReview(recovery)
    try await endpoint.presentHostIdentityRecoveryResume(resume)
    await endpoint.withdrawHostIdentityRecovery(reviewID: recovery.reviewID)

    #expect(await sender.recordedRequests() == [
        .pairingReview(
            try LocalMenuPresentationWireCodecV1.encodePairingReview(pairing)
        ),
        .pairingWithdrawal(pairing.reviewID),
        .hostRecoveryReview(
            try LocalMenuPresentationWireCodecV1
                .encodeHostIdentityRecoveryReview(recovery)
        ),
        .hostRecoveryResume(
            try LocalMenuPresentationWireCodecV1
                .encodeHostIdentityRecoveryResume(resume)
        ),
        .hostRecoveryWithdrawal(recovery.reviewID),
    ])
}

@Test func opaqueEndpointBindsInteractiveRuntimeToExactGenerationAndToken()
    async throws
{
    let command = try endpointInitialDesktopCommandV1()
    let receipt = try endpointInitialDesktopReceiptV1(command: command)
    let surfaceFailureCommand = LocalInteractiveSurfaceFailureCommandV1(
        commandID: UUID(),
        interactiveSessionID: command.interactiveSessionID,
        reason: .protocolViolation
    )
    let surfaceFailureReceipt = try LocalInteractiveSurfaceFailureReceiptV1(
        correlationID: surfaceFailureCommand.commandID,
        interactiveSessionID: surfaceFailureCommand.interactiveSessionID,
        terminated: true
    )
    let focusSnapshotCommand = try LocalInteractiveFocusSnapshotCommandV1(
        commandID: UUID(),
        interactiveSessionID: command.interactiveSessionID,
        authorizationEpoch: command.authorizationEpoch,
        currentSurfaceID: receipt.descriptor.surfaceID,
        expectedSurfaceRevision: receipt.descriptor.surfaceRevision,
        expectedCoordinateSpaceRevision:
            receipt.descriptor.coordinateSpaceRevision
    )
    let focusSnapshotReceipt = LocalInteractiveFocusSnapshotReceiptV1(
        correlationID: focusSnapshotCommand.commandID,
        command: focusSnapshotCommand,
        candidate: try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: .desktop,
            focus: nil,
            inputPaused: false,
            reason: .noVerifiedFocus,
            validForMilliseconds: 1_000
        )
    )
    let token = UUID()
    let sender = MenuPresentationSenderProbeV1(
        [],
        desktopReceipt: receipt,
        surfaceFailureReceipt: surfaceFailureReceipt,
        focusSnapshotReceipt: focusSnapshotReceipt
    )
    let endpoint = endpointV1(
        sender: sender,
        generation: 7,
        token: token
    )
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 7,
        endpointFactory: { endpoint }
    )

    #expect(
        try await surfaces.interactiveRuntime
            .prepareInitialInteractiveDesktop(command) == receipt
    )
    #expect(
        try await surfaces.interactiveRuntime
            .terminateInteractiveSurfaceFailure(surfaceFailureCommand)
            == surfaceFailureReceipt
    )
    #expect(
        try await surfaces.interactiveRuntime
            .interactiveFocusSnapshot(focusSnapshotCommand)
            == focusSnapshotReceipt
    )
    #expect(await sender.recordedInteractiveGenerations() == [7, 7, 7])
    #expect(await sender.recordedInteractiveTokens() == [token, token, token])

    #expect(await router.invalidate(generation: 7))
    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .endpointClosed
    ) {
        try await surfaces.interactiveRuntime
            .prepareInitialInteractiveDesktop(command)
    }
    #expect(await sender.recordedInteractiveGenerations() == [7, 7, 7])
}

@Test
func recoverablePublishRejectionLeavesRouterGenerationCurrent() async throws {
    let sender = MenuPresentationSenderProbeV1([.rejected])
    let endpoint = endpointV1(sender: sender)
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 7,
        endpointFactory: { endpoint }
    )

    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .presentationRejected
    ) {
        try await surfaces.pairingReviews.presentLocalPairingReview(
            endpointPairingReviewV1()
        )
    }
    #expect(await router.currentGeneration() == 7)
    #expect(await sender.retirementCount() == 0)
}

@Test
func transportFailureRequestsOneTerminalFenceAndOneRetirement() async throws {
    let sender = MenuPresentationSenderProbeV1([
        .failed(.transportFailure),
    ])
    let endpoint = endpointV1(sender: sender)
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 7,
        endpointFactory: { endpoint }
    )

    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .endpointClosed
    ) {
        try await surfaces.pairingReviews.presentLocalPairingReview(
            endpointPairingReviewV1()
        )
    }
    await router.finish()
    #expect(await router.currentGeneration() == nil)
    #expect(await sender.retirementCount() == 1)
}

@Test
func failureBeforeFenceInstallationLatchesUntilBinding() async throws {
    let sender = MenuPresentationSenderProbeV1([
        .failed(.replyTimedOut),
    ])
    let endpoint = endpointV1(sender: sender)

    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .endpointClosed
    ) {
        try await endpoint.presentLocalPairingReview(endpointPairingReviewV1())
    }

    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    await #expect(throws: (any Error).self) {
        _ = try await router.bindAuthenticated(
            generation: 7,
            endpointFactory: { endpoint }
        )
    }
    await router.finish()
    #expect(await sender.retirementCount() == 1)
}

@Test
func ownerRetirementIsIdempotentAndDoesNotRequestTerminalFinish()
    async throws
{
    let sender = MenuPresentationSenderProbeV1([])
    let endpoint = endpointV1(sender: sender)
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    _ = try await router.bindAuthenticated(
        generation: 7,
        endpointFactory: { endpoint }
    )

    #expect(await router.invalidate(generation: 7))
    #expect(await sender.retirementCount() == 1)
    let replacementSender = MenuPresentationSenderProbeV1([])
    _ = try await router.bindAuthenticated(
        generation: 8,
        endpointFactory: {
            endpointV1(sender: replacementSender, generation: 8)
        }
    )
    #expect(await router.currentGeneration() == 8)
}

@Test
func cancellationBeforeSendDoesNotTerminallyFenceTheEndpoint() async throws {
    let sender = MenuPresentationSenderProbeV1([
        .cancelledBeforeSend,
        .acknowledged,
    ])
    let endpoint = endpointV1(sender: sender)
    let review = try endpointPairingReviewV1()

    await #expect(throws: CancellationError.self) {
        try await endpoint.presentLocalPairingReview(review)
    }
    try await endpoint.presentLocalPairingReview(review)
    #expect(await sender.recordedRequests().count == 2)
}

@Test
func missingWeakSenderBeforeFenceInstallationLatchesTerminalFailure()
    async throws
{
    var sender: MenuPresentationSenderProbeV1? =
        MenuPresentationSenderProbeV1([])
    let endpoint = endpointV1(sender: try #require(sender))
    sender = nil

    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .endpointClosed
    ) {
        try await endpoint.presentLocalPairingReview(endpointPairingReviewV1())
    }
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    await #expect(throws: (any Error).self) {
        _ = try await router.bindAuthenticated(
            generation: 7,
            endpointFactory: { endpoint }
        )
    }
    await router.finish()
    #expect(await router.currentGeneration() == nil)
}

@Test
func missingWeakSenderAfterBindingTerminallyFinishesRouter() async throws {
    var sender: MenuPresentationSenderProbeV1? =
        MenuPresentationSenderProbeV1([])
    let endpoint = endpointV1(sender: try #require(sender))
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 7,
        endpointFactory: { endpoint }
    )
    sender = nil

    await #expect(
        throws: MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
            .endpointClosed
    ) {
        try await surfaces.pairingReviews.presentLocalPairingReview(
            endpointPairingReviewV1()
        )
    }
    await router.finish()
    #expect(await router.currentGeneration() == nil)
}

@Test
func productionFIFOStartsOnlyItsCrossFamilyHeadInArrivalOrder() throws {
    var fifo = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    let requests = (0..<3).map { _ in UUID() }

    #expect(
        fifo.admit(requestID: requests[0], cancelled: false)
            == .admitted(operation: 1, startsImmediately: true)
    )
    #expect(
        fifo.admit(requestID: requests[1], cancelled: false)
            == .admitted(operation: 2, startsImmediately: false)
    )
    #expect(
        fifo.admit(requestID: requests[2], cancelled: false)
            == .admitted(operation: 3, startsImmediately: false)
    )
    let firstClaim = fifo.claimHeadForSend(
        requestID: requests[0],
        operation: 1
    )
    #expect(firstClaim)
    #expect(fifo.head?.requestID == requests[0])
    let firstCompletion = fifo.completeHead(
        requestID: requests[0],
        operation: 1
    )
    #expect(firstCompletion)
    #expect(fifo.head?.requestID == requests[1])
    #expect(!fifo.head!.sent)
}

@Test
func productionFIFOAdmitsEightAndMakesTheNinthTerminal() {
    var fifo = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    let requests = (0..<9).map { _ in UUID() }
    for request in requests.prefix(8) {
        _ = fifo.admit(requestID: request, cancelled: false)
    }

    #expect(fifo.count == 8)
    #expect(
        fifo.admit(requestID: requests[8], cancelled: false)
            == .overflow(drainedRequestIDs: Array(requests.prefix(8)))
    )
    #expect(fifo.isTerminal)
    #expect(fifo.count == 0)
    #expect(
        fifo.admit(requestID: UUID(), cancelled: false) == .terminal
    )
}

@Test
func productionFIFODistinguishesQueuedAndActiveCancellation() {
    var queued = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    let activeID = UUID()
    let queuedID = UUID()
    _ = queued.admit(requestID: activeID, cancelled: false)
    _ = queued.admit(requestID: queuedID, cancelled: false)
    let activeClaim = queued.claimHeadForSend(
        requestID: activeID,
        operation: 1
    )
    #expect(activeClaim)
    #expect(
        queued.cancel(requestID: queuedID) == .cancelledBeforeSend
    )
    #expect(!queued.isTerminal)
    #expect(queued.head?.requestID == activeID)

    var active = queued
    #expect(
        active.cancel(requestID: activeID)
            == .terminalAfterSend(drainedRequestIDs: [activeID])
    )
    #expect(active.isTerminal)
}

@Test
func productionFIFOFenceRejectsTimeoutLateReplyAndReplacementCallback() {
    let requestID = UUID()
    var old = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    _ = old.admit(requestID: requestID, cancelled: false)
    let oldClaim = old.claimHeadForSend(
        requestID: requestID,
        operation: 1
    )
    #expect(oldClaim)
    let drained = old.fence()
    #expect(drained == [requestID])
    #expect(
        !old.admitsActiveCallback(requestID: requestID, operation: 1)
    )
    let lateCompletion = old.completeHead(
        requestID: requestID,
        operation: 1
    )
    #expect(!lateCompletion)

    var replacement = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    let replacementID = UUID()
    _ = replacement.admit(requestID: replacementID, cancelled: false)
    #expect(
        !replacement.admitsActiveCallback(
            requestID: requestID,
            operation: 1
        )
    )
    #expect(replacement.head?.requestID == replacementID)
}

@Test
func productionFIFOHandlesCancellationBeforeAdmissionAndExhaustion() {
    var cancelled = MacLocalXPCMenuPresentationFIFOStateV1(limit: 8)
    #expect(
        cancelled.admit(requestID: UUID(), cancelled: true)
            == .cancelledBeforeAdmission
    )
    #expect(cancelled.count == 0)

    var exhausted = MacLocalXPCMenuPresentationFIFOStateV1(
        limit: 8,
        nextOperation: UInt64.max
    )
    #expect(
        exhausted.admit(requestID: UUID(), cancelled: false)
            == .operationExhausted(drainedRequestIDs: [])
    )
    #expect(exhausted.isTerminal)
}

@Test
func peerWideFencePrecedesAndDeduplicatesSessionCancellation() {
    var fence = MacLocalXPCPostAuthenticationTrafficFenceV1()

    #expect(fence.admitsTraffic)
    let prematureCancellation = fence.claimSessionCancellation()
    #expect(!prematureCancellation)
    let firstFence = fence.fence()
    #expect(firstFence)
    #expect(!fence.admitsTraffic)
    let duplicateFence = fence.fence()
    #expect(!duplicateFence)
    let firstCancellation = fence.claimSessionCancellation()
    #expect(firstCancellation)
    let duplicateCancellation = fence.claimSessionCancellation()
    #expect(!duplicateCancellation)
}
