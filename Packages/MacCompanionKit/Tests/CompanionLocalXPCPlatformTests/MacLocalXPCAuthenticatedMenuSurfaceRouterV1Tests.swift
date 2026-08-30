@testable import CompanionLocalXPCPlatform
import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private actor MenuSurfaceSuspensionV1 {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func suspend() async {
        entered = true
        let enteredWaiters = self.enteredWaiters
        self.enteredWaiters.removeAll()
        for waiter in enteredWaiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let releaseWaiters = self.releaseWaiters
        self.releaseWaiters.removeAll()
        for waiter in releaseWaiters { waiter.resume() }
    }
}

private actor AuthenticatedMenuSurfaceEndpointProbeV1:
    MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
{
    enum Event: Equatable, Sendable {
        case pairingPresented(UUID)
        case pairingWithdrawn(UUID)
        case recoveryReviewPresented(UUID)
        case recoveryResumePresented(UUID)
        case recoveryWithdrawn(UUID)
        case invalidated
    }

    private let pairingSuspension: MenuSurfaceSuspensionV1?
    private let recoverySuspension: MenuSurfaceSuspensionV1?
    private let invalidationSuspension: MenuSurfaceSuspensionV1?
    private let invalidationHook: (@Sendable () async -> Void)?
    private let requestFinishOnInvalidation: Bool
    private let detachedFinishRequest: Bool
    private var terminalFence: MacLocalXPCMenuSurfaceTerminalFenceV1?
    private var terminalFenceInstallCount = 0
    private var events: [Event] = []

    init(
        pairingSuspension: MenuSurfaceSuspensionV1? = nil,
        recoverySuspension: MenuSurfaceSuspensionV1? = nil,
        invalidationSuspension: MenuSurfaceSuspensionV1? = nil,
        invalidationHook: (@Sendable () async -> Void)? = nil,
        requestFinishOnInvalidation: Bool = false,
        detachedFinishRequest: Bool = false
    ) {
        self.pairingSuspension = pairingSuspension
        self.recoverySuspension = recoverySuspension
        self.invalidationSuspension = invalidationSuspension
        self.invalidationHook = invalidationHook
        self.requestFinishOnInvalidation = requestFinishOnInvalidation
        self.detachedFinishRequest = detachedFinishRequest
    }

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        events.append(.pairingPresented(review.reviewID))
        await pairingSuspension?.suspend()
    }

    func withdrawLocalPairingReview(reviewID: UUID) {
        events.append(.pairingWithdrawn(reviewID))
    }

    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async {
        events.append(.recoveryReviewPresented(review.reviewID))
        await recoverySuspension?.suspend()
    }

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) {
        events.append(.recoveryResumePresented(command.review.reviewID))
    }

    func withdrawHostIdentityRecovery(reviewID: UUID) {
        events.append(.recoveryWithdrawn(reviewID))
    }

    func installAuthenticatedMenuTerminalFence(
        _ fence: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) {
        terminalFence = fence
        terminalFenceInstallCount += 1
    }

    func invalidateAuthenticatedMenuSurface() async {
        events.append(.invalidated)
        await invalidationHook?()
        if requestFinishOnInvalidation, let terminalFence {
            if detachedFinishRequest {
                await Task.detached {
                    await terminalFence.requestFinish()
                }.value
            } else {
                await terminalFence.requestFinish()
            }
        }
        await invalidationSuspension?.suspend()
    }

    func recordedEvents() -> [Event] { events }
    func recordedTerminalFenceInstallCount() -> Int {
        terminalFenceInstallCount
    }

    func requestInstalledTerminalFinish(detached: Bool = false) async {
        guard let terminalFence else { return }
        if detached {
            await Task.detached {
                await terminalFence.requestFinish()
            }.value
        } else {
            await terminalFence.requestFinish()
        }
    }
}

private actor MenuSurfaceCompletionProbeV1 {
    private var complete = false

    func markComplete() { complete = true }
    func isComplete() -> Bool { complete }
}

private actor MenuSurfaceInvalidationCountProbeV1 {
    private var count = 0

    func record() { count += 1 }
    func recordedCount() -> Int { count }
}

private extension MacLocalXPCAuthenticatedMenuSurfaceRouterV1 {
    func bindAuthenticated(
        generation: UInt64,
        endpoint:
            any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
    ) async throws -> MacLocalXPCAuthenticatedMenuSurfacesV1 {
        try await bindAuthenticated(
            generation: generation,
            endpointFactory: { endpoint }
        )
    }
}

private func menuSurfacePairingReviewV1() throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: UUID(
            uuidString: "018f4300-0000-7000-8000-0000000000b1"
        )!,
        pairingID: UUID(
            uuidString: "018f4000-0000-7000-8000-0000000000b1"
        )!,
        clientID: UUID(
            uuidString: "018f2000-0000-7000-8000-0000000000b1"
        )!,
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

private func menuSurfaceRecoveryReviewV1()
    throws -> LocalHostIdentityRecoveryReviewV0
{
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(
            uuidString: "11111111-1111-4111-8111-111111111111"
        )!,
        hostID: UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )!,
        hostFingerprint: WireFingerprint(
            Data(repeating: 0x31, count: 32)
        ),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: 1_787_284_800_000,
        expiresAtUnixMilliseconds: 1_787_285_100_000
    )
}

private func menuSurfaceRecoveryCommandV1()
    throws -> LocalHostIdentityRecoveryCommandV0
{
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(
            uuidString: "33333333-3333-4333-8333-333333333333"
        )!,
        recoveryID: UUID(
            uuidString: "44444444-4444-4444-8444-444444444444"
        )!,
        review: menuSurfaceRecoveryReviewV1(),
        confirmedAtUnixMilliseconds: 1_787_284_800_001
    )
}

@Test
func authenticatedMenuSurfacesRouteOnlyTheClosedPresentationFacets()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 7,
        endpoint: endpoint
    )
    let pairing = try menuSurfacePairingReviewV1()
    let recovery = try menuSurfaceRecoveryReviewV1()
    let resume = try menuSurfaceRecoveryCommandV1()

    try await surfaces.pairingReviews.presentLocalPairingReview(pairing)
    await surfaces.pairingReviews.withdrawLocalPairingReview(
        reviewID: pairing.reviewID
    )
    try await surfaces.hostIdentityRecovery
        .presentHostIdentityRecoveryReview(recovery)
    try await surfaces.hostIdentityRecovery
        .presentHostIdentityRecoveryResume(resume)
    await surfaces.hostIdentityRecovery.withdrawHostIdentityRecovery(
        reviewID: recovery.reviewID
    )

    #expect(surfaces.generation == 7)
    #expect(await router.currentGeneration() == 7)
    #expect(await endpoint.recordedEvents() == [
        .pairingPresented(pairing.reviewID),
        .pairingWithdrawn(pairing.reviewID),
        .recoveryReviewPresented(recovery.reviewID),
        .recoveryResumePresented(recovery.reviewID),
        .recoveryWithdrawn(recovery.reviewID),
    ])
}

@Test
func authenticatedMenuReplacementInvalidatesOldFacetsBeforeReturning()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let old = try await router.bindAuthenticated(
        generation: 10,
        endpoint: oldEndpoint
    )
    let newEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let replacement = try await router.bindAuthenticated(
        generation: 11,
        endpoint: newEndpoint
    )
    let pairing = try menuSurfacePairingReviewV1()

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(10)
    ) {
        try await old.pairingReviews.presentLocalPairingReview(pairing)
    }
    await old.pairingReviews.withdrawLocalPairingReview(
        reviewID: pairing.reviewID
    )
    try await replacement.pairingReviews
        .presentLocalPairingReview(pairing)

    #expect(await oldEndpoint.recordedEvents() == [.invalidated])
    #expect(await newEndpoint.recordedEvents() == [
        .pairingPresented(pairing.reviewID),
    ])
}

@Test
func exactDuplicateAuthenticationReissuesFacetsWithoutInvalidatingPeer()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 12,
        endpoint: endpoint
    )
    let replay = try await router.bindAuthenticated(
        generation: 12,
        endpoint: endpoint
    )
    let pairing = try menuSurfacePairingReviewV1()
    try await replay.pairingReviews.presentLocalPairingReview(pairing)

    let conflictingEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .duplicateGeneration(12)
    ) {
        _ = try await router.bindAuthenticated(
            generation: 12,
            endpoint: conflictingEndpoint
        )
    }

    #expect(await router.currentGeneration() == 12)
    #expect(await endpoint.recordedEvents() == [
        .pairingPresented(pairing.reviewID),
    ])
    #expect(await endpoint.recordedTerminalFenceInstallCount() == 1)
    #expect(await conflictingEndpoint.recordedEvents() == [.invalidated])
    #expect(
        await conflictingEndpoint.recordedTerminalFenceInstallCount() == 0
    )
}

@Test
func replacementDoesNotReturnBeforeOldEndpointRetirementCompletes()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: suspension
    )
    _ = try await router.bindAuthenticated(
        generation: 13,
        endpoint: oldEndpoint
    )
    let completion = MenuSurfaceCompletionProbeV1()
    let replacement = Task {
        let value = try await router.bindAuthenticated(
            generation: 14,
            endpoint: AuthenticatedMenuSurfaceEndpointProbeV1()
        )
        await completion.markComplete()
        return value
    }

    await suspension.waitUntilEntered()
    #expect(!(await completion.isComplete()))
    await suspension.release()
    let value = try await replacement.value
    #expect(value.generation == 14)
    #expect(await completion.isComplete())
}

@Test
func duplicateBindDuringReplacementAwaitsTheSameActivationBarrier()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: suspension
    )
    _ = try await router.bindAuthenticated(
        generation: 15,
        endpoint: oldEndpoint
    )
    let replacementEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let firstCompletion = MenuSurfaceCompletionProbeV1()
    let duplicateCompletion = MenuSurfaceCompletionProbeV1()
    let first = Task {
        let value = try await router.bindAuthenticated(
            generation: 16,
            endpoint: replacementEndpoint
        )
        await firstCompletion.markComplete()
        return value
    }
    await suspension.waitUntilEntered()
    let duplicate = Task {
        let value = try await router.bindAuthenticated(
            generation: 16,
            endpoint: replacementEndpoint
        )
        await duplicateCompletion.markComplete()
        return value
    }
    await Task.yield()

    #expect(!(await firstCompletion.isComplete()))
    #expect(!(await duplicateCompletion.isComplete()))
    await suspension.release()
    #expect(try await first.value.generation == 16)
    #expect(try await duplicate.value.generation == 16)
    #expect(await firstCompletion.isComplete())
    #expect(await duplicateCompletion.isComplete())
}

@Test
func lowerOrRetiredGenerationCannotRestoreAuthorityOrOldFacets()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let firstEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let first = try await router.bindAuthenticated(
        generation: 50,
        endpoint: firstEndpoint
    )
    #expect(await router.invalidate(generation: 50))

    let rollback = AuthenticatedMenuSurfaceEndpointProbeV1()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(49)
    ) {
        _ = try await router.bindAuthenticated(
            generation: 49,
            endpoint: rollback
        )
    }
    let reused = AuthenticatedMenuSurfaceEndpointProbeV1()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(50)
    ) {
        _ = try await router.bindAuthenticated(
            generation: 50,
            endpoint: reused
        )
    }
    let replacement = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 51,
        endpoint: replacement
    )
    let pairing = try menuSurfacePairingReviewV1()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(50)
    ) {
        try await first.pairingReviews.presentLocalPairingReview(pairing)
    }

    #expect(await router.currentGeneration() == 51)
    #expect(await rollback.recordedEvents().isEmpty)
    #expect(await reused.recordedEvents().isEmpty)
}

@Test
func delayedOldPresentationAcknowledgementCannotCrossReplacement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        pairingSuspension: suspension
    )
    let old = try await router.bindAuthenticated(
        generation: 20,
        endpoint: oldEndpoint
    )
    let pairing = try menuSurfacePairingReviewV1()

    let delayed = Task {
        try await old.pairingReviews.presentLocalPairingReview(pairing)
    }
    await suspension.waitUntilEntered()
    let newEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 21,
        endpoint: newEndpoint
    )
    await suspension.release()

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(20)
    ) {
        try await delayed.value
    }
    #expect(await oldEndpoint.recordedEvents() == [
        .pairingPresented(pairing.reviewID),
        .invalidated,
        .pairingWithdrawn(pairing.reviewID),
    ])
    #expect(await router.currentGeneration() == 21)
}

@Test
func delayedRecoveryAcknowledgementCannotCrossReplacement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        recoverySuspension: suspension
    )
    let old = try await router.bindAuthenticated(
        generation: 22,
        endpoint: oldEndpoint
    )
    let review = try menuSurfaceRecoveryReviewV1()
    let delayed = Task {
        try await old.hostIdentityRecovery
            .presentHostIdentityRecoveryReview(review)
    }
    await suspension.waitUntilEntered()
    _ = try await router.bindAuthenticated(
        generation: 23,
        endpoint: AuthenticatedMenuSurfaceEndpointProbeV1()
    )
    await suspension.release()

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(22)
    ) {
        try await delayed.value
    }
    #expect(await oldEndpoint.recordedEvents() == [
        .recoveryReviewPresented(review.reviewID),
        .invalidated,
        .recoveryWithdrawn(review.reviewID),
    ])
}

@Test
func exactInvalidationAndFinishAreTerminalAndGenerationFenced()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 30,
        endpoint: endpoint
    )
    let pairing = try menuSurfacePairingReviewV1()

    #expect(!(await router.invalidate(generation: 29)))
    try await surfaces.pairingReviews.presentLocalPairingReview(pairing)
    #expect(await router.invalidate(generation: 30))
    #expect(!(await router.invalidate(generation: 30)))
    await router.finish()
    await router.finish()

    let rejected = AuthenticatedMenuSurfaceEndpointProbeV1()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1.invalidated
    ) {
        _ = try await router.bindAuthenticated(
            generation: 31,
            endpoint: rejected
        )
    }
    #expect(await endpoint.recordedEvents() == [
        .pairingPresented(pairing.reviewID),
        .invalidated,
    ])
    #expect(await rejected.recordedEvents().isEmpty)
}

@Test
func concurrentFinishCallsAwaitTheSameEndpointRetirement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: suspension
    )
    _ = try await router.bindAuthenticated(
        generation: 40,
        endpoint: endpoint
    )
    let firstCompletion = MenuSurfaceCompletionProbeV1()
    let secondCompletion = MenuSurfaceCompletionProbeV1()
    let first = Task {
        await router.finish()
        await firstCompletion.markComplete()
    }
    await suspension.waitUntilEntered()
    let second = Task {
        await router.finish()
        await secondCompletion.markComplete()
    }
    await Task.yield()

    #expect(!(await firstCompletion.isComplete()))
    #expect(!(await secondCompletion.isComplete()))
    await suspension.release()
    await first.value
    await second.value
    #expect(await firstCompletion.isComplete())
    #expect(await secondCompletion.isComplete())
    #expect(await endpoint.recordedEvents() == [.invalidated])
}

@Test
func invalidateAndFinishAwaitOneSharedRetirement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: suspension
    )
    _ = try await router.bindAuthenticated(
        generation: 60,
        endpoint: endpoint
    )
    let invalidationCompletion = MenuSurfaceCompletionProbeV1()
    let finishCompletion = MenuSurfaceCompletionProbeV1()
    let invalidation = Task {
        let value = await router.invalidate(generation: 60)
        await invalidationCompletion.markComplete()
        return value
    }
    await suspension.waitUntilEntered()
    let finish = Task {
        await router.finish()
        await finishCompletion.markComplete()
    }
    await Task.yield()

    #expect(!(await invalidationCompletion.isComplete()))
    #expect(!(await finishCompletion.isComplete()))
    await suspension.release()
    #expect(await invalidation.value)
    await finish.value
    #expect(await invalidationCompletion.isComplete())
    #expect(await finishCompletion.isComplete())
    #expect(await endpoint.recordedEvents() == [.invalidated])
}

@Test
func finishDuringReplacementAwaitsAndRetiresBothGenerations()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let oldSuspension = MenuSurfaceSuspensionV1()
    let oldEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: oldSuspension
    )
    _ = try await router.bindAuthenticated(
        generation: 70,
        endpoint: oldEndpoint
    )
    let newEndpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    let replacement = Task {
        try await router.bindAuthenticated(
            generation: 71,
            endpoint: newEndpoint
        )
    }
    await oldSuspension.waitUntilEntered()
    let finishCompletion = MenuSurfaceCompletionProbeV1()
    let finish = Task {
        await router.finish()
        await finishCompletion.markComplete()
    }
    await Task.yield()

    #expect(!(await finishCompletion.isComplete()))
    await oldSuspension.release()
    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(71)
    ) {
        _ = try await replacement.value
    }
    await finish.value
    #expect(await finishCompletion.isComplete())
    #expect(await oldEndpoint.recordedEvents() == [.invalidated])
    #expect(await newEndpoint.recordedEvents() == [.invalidated])
}

@Test
func reentrantSameGenerationInvalidationCompletesWithoutSelfAwait()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationHook: {
            #expect(!(await router.invalidate(generation: 80)))
        }
    )
    _ = try await router.bindAuthenticated(
        generation: 80,
        endpoint: endpoint
    )

    #expect(await router.invalidate(generation: 80))
    #expect(await endpoint.recordedEvents() == [.invalidated])
    #expect(await router.currentGeneration() == nil)
}

@Test
func endpointInvalidationCanRequestFinishWithoutDoubleRetirement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let invalidations = MenuSurfaceInvalidationCountProbeV1()
    _ = try await router.bindAuthenticated(generation: 81) {
        AuthenticatedMenuSurfaceEndpointProbeV1(
            invalidationHook: {
                await invalidations.record()
            },
            requestFinishOnInvalidation: true
        )
    }

    await router.finish()
    await router.finish()
    #expect(await invalidations.recordedCount() == 1)
    #expect(await router.currentGeneration() == nil)
}

@Test
func detachedEndpointCallbackCanRequestFinishWithoutSelfAwait()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let invalidations = MenuSurfaceInvalidationCountProbeV1()
    _ = try await router.bindAuthenticated(generation: 82) {
        AuthenticatedMenuSurfaceEndpointProbeV1(
            invalidationHook: {
                await invalidations.record()
            },
            requestFinishOnInvalidation: true,
            detachedFinishRequest: true
        )
    }

    await router.finish()
    #expect(await invalidations.recordedCount() == 1)
    #expect(await router.currentGeneration() == nil)
}

@Test
func retiredEndpointTerminalFenceCannotRetireReplacementGeneration()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let invalidations = MenuSurfaceInvalidationCountProbeV1()
    _ = try await router.bindAuthenticated(generation: 90) {
        AuthenticatedMenuSurfaceEndpointProbeV1(
            invalidationHook: {
                await invalidations.record()
            },
            requestFinishOnInvalidation: true
        )
    }
    let replacement = AuthenticatedMenuSurfaceEndpointProbeV1()

    _ = try await router.bindAuthenticated(
        generation: 91,
        endpoint: replacement
    )

    #expect(await invalidations.recordedCount() == 1)
    #expect(await router.currentGeneration() == 91)
    #expect(await replacement.recordedEvents().isEmpty)
}

@Test
func rejectedDuplicateTerminalFenceCannotRetireCurrentGeneration()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let active = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 100,
        endpoint: active
    )
    let rejectedInvalidations = MenuSurfaceInvalidationCountProbeV1()

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .duplicateGeneration(100)
    ) {
        _ = try await router.bindAuthenticated(generation: 100) {
            AuthenticatedMenuSurfaceEndpointProbeV1(
                invalidationHook: {
                    await rejectedInvalidations.record()
                },
                requestFinishOnInvalidation: true
            )
        }
    }

    #expect(await rejectedInvalidations.recordedCount() == 1)
    #expect(await router.currentGeneration() == 100)
    #expect(await active.recordedEvents().isEmpty)
}

@Test
func activeEndpointTerminalFenceRequestsAndOwnerAwaitsOneRetirement()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let suspension = MenuSurfaceSuspensionV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1(
        invalidationSuspension: suspension
    )
    _ = try await router.bindAuthenticated(
        generation: 110,
        endpoint: endpoint
    )

    await endpoint.requestInstalledTerminalFinish(detached: true)
    await suspension.waitUntilEntered()
    let finishCompletion = MenuSurfaceCompletionProbeV1()
    let finish = Task {
        await router.finish()
        await finishCompletion.markComplete()
    }
    await Task.yield()

    #expect(await router.currentGeneration() == nil)
    #expect(!(await finishCompletion.isComplete()))
    await suspension.release()
    await finish.value
    #expect(await finishCompletion.isComplete())
    #expect(await endpoint.recordedEvents() == [.invalidated])
    #expect(await endpoint.recordedTerminalFenceInstallCount() == 1)
}

@Test
func endpointFailureUnwindsBeforeProductCleanupJoinsItsOperation() async throws {
    let notification = MenuSurfaceSuspensionV1()
    let notifications = MenuSurfaceInvalidationCountProbeV1()
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1(onEndpointTerminal: { _ in
        await notifications.record()
        await notification.suspend()
    })
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(generation: 111, endpoint: endpoint)
    let requestCompletion = MenuSurfaceCompletionProbeV1()
    let request = Task {
        await endpoint.requestInstalledTerminalFinish()
        await requestCompletion.markComplete()
    }
    await notification.waitUntilEntered()
    for _ in 0..<100 {
        if await requestCompletion.isComplete() { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await requestCompletion.isComplete())
    #expect(await router.currentGeneration() == nil)
    await #expect(throws: MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1.staleGeneration(111)) {
        _ = try await router.bindAuthenticated(generation: 111,
            endpoint: AuthenticatedMenuSurfaceEndpointProbeV1())
    }
    let finishCompletion = MenuSurfaceCompletionProbeV1()
    let finish = Task {
        await router.finish()
        await finishCompletion.markComplete()
    }
    for _ in 0..<100 { await Task.yield() }
    #expect(!(await finishCompletion.isComplete()))
    await notification.release()
    await request.value
    await finish.value
    await endpoint.requestInstalledTerminalFinish()
    #expect(await notifications.recordedCount() == 1)
    #expect(await endpoint.recordedEvents() == [.invalidated])
    #expect(await finishCompletion.isComplete())
}

@Test
func failedEndpointAllowsFreshGenerationOnlyAfterCleanup() async throws {
    let notification = MenuSurfaceSuspensionV1()
    let notifications = MenuSurfaceInvalidationCountProbeV1()
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1(onEndpointTerminal: { _ in
        await notifications.record()
        await notification.suspend()
    })
    let failed = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(generation: 130, endpoint: failed)
    await failed.requestInstalledTerminalFinish()
    await notification.waitUntilEntered()
    let replacement = AuthenticatedMenuSurfaceEndpointProbeV1()
    let completion = MenuSurfaceCompletionProbeV1()
    let bind = Task {
        let surfaces = try await router.bindAuthenticated(generation: 131, endpoint: replacement)
        await completion.markComplete()
        return surfaces
    }
    for _ in 0..<100 { await Task.yield() }
    #expect(!(await completion.isComplete()))
    await notification.release()
    let surfaces = try await bind.value
    #expect(surfaces.generation == 131)
    await failed.requestInstalledTerminalFinish()
    #expect(await router.currentGeneration() == 131)
    #expect(await notifications.recordedCount() == 1)
    #expect(await failed.recordedEvents() == [.invalidated])
    #expect(await replacement.recordedEvents().isEmpty)
    await replacement.requestInstalledTerminalFinish()
    let third = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(generation: 132, endpoint: third)
    await failed.requestInstalledTerminalFinish()
    await replacement.requestInstalledTerminalFinish()
    #expect(await router.currentGeneration() == 132)
    #expect(await notifications.recordedCount() == 2)
    #expect(await replacement.recordedEvents() == [.invalidated])
    await router.finish()
    #expect(await third.recordedEvents() == [.invalidated])
}

@Test
func oneEndpointObjectCannotRepresentTwoTransportGenerations()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let endpoint = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 120,
        endpoint: endpoint
    )

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .endpointReusedAcrossGenerations(121)
    ) {
        _ = try await router.bindAuthenticated(
            generation: 121,
            endpoint: endpoint
        )
    }

    #expect(await router.currentGeneration() == 120)
    #expect(await endpoint.recordedEvents().isEmpty)
    #expect(await endpoint.recordedTerminalFenceInstallCount() == 1)
}

@Test
func retiredEndpointObjectCannotReturnForALaterGeneration()
    async throws
{
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let first = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 130,
        endpoint: first
    )
    let second = AuthenticatedMenuSurfaceEndpointProbeV1()
    _ = try await router.bindAuthenticated(
        generation: 131,
        endpoint: second
    )

    await #expect(
        throws:
            MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .endpointReusedAcrossGenerations(132)
    ) {
        _ = try await router.bindAuthenticated(
            generation: 132,
            endpoint: first
        )
    }

    #expect(await router.currentGeneration() == 131)
    #expect(await first.recordedEvents() == [.invalidated])
    #expect(await first.recordedTerminalFenceInstallCount() == 1)
    #expect(await second.recordedEvents().isEmpty)
    #expect(await second.recordedTerminalFenceInstallCount() == 1)
}
