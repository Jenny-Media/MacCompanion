#if os(macOS)
@testable import CompanionAgentProductPlatform
import CompanionDomain
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionWire
import Foundation
import Testing

private actor PreparedMenuSurfaceGateV1 {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor PreparedMenuEndpointProbeV1:
    MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
{
    enum Event: Equatable, Sendable {
        case pairingPresented(UUID)
        case pairingWithdrawn(UUID)
        case invalidated
    }

    private let pairingGate: PreparedMenuSurfaceGateV1?
    private var events: [Event] = []

    init(pairingGate: PreparedMenuSurfaceGateV1? = nil) {
        self.pairingGate = pairingGate
    }

    func installAuthenticatedMenuTerminalFence(
        _: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) {}

    func invalidateAuthenticatedMenuSurface() {
        events.append(.invalidated)
    }

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async {
        events.append(.pairingPresented(review.reviewID))
        await pairingGate?.suspend()
    }

    func withdrawLocalPairingReview(reviewID: UUID) {
        events.append(.pairingWithdrawn(reviewID))
    }

    func presentHostIdentityRecoveryReview(
        _: LocalHostIdentityRecoveryReviewV0
    ) async throws {}

    func presentHostIdentityRecoveryResume(
        _: LocalHostIdentityRecoveryCommandV0
    ) async throws {}

    func withdrawHostIdentityRecovery(reviewID _: UUID) {}
    func recordedEvents() -> [Event] { events }
}

private func preparedMenuPairingReviewV1() throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: UUID(
            uuidString: "018f4300-0000-7000-8000-0000000000c1"
        )!,
        pairingID: UUID(
            uuidString: "018f4000-0000-7000-8000-0000000000c1"
        )!,
        clientID: UUID(
            uuidString: "018f2000-0000-7000-8000-0000000000c1"
        )!,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x71, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x72, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x73, count: 32)),
        authenticationString: PairingAuthenticationString("24A-7B6"),
        expectedPolicyRevision: PolicyRevision(rawValue: 8),
        expiresAtUnixMilliseconds: 1_787_198_700_000
    )
}

@Test
@available(macOS 26.0, *)
func preparedMenuAuthorityRequiresAReadyGenerationAndRejectsRollback()
    async throws
{
    let authority = MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    let review = try preparedMenuPairingReviewV1()
    await #expect(
        throws: MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.unavailable
    ) {
        try await authority.presentLocalPairingReview(review)
    }

    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let first = PreparedMenuEndpointProbeV1()
    let firstSurfaces = try await router.bindAuthenticated(
        generation: 91,
        endpointFactory: { first }
    )
    try await authority.install(firstSurfaces)
    try await authority.presentLocalPairingReview(review)
    #expect(
        await first.recordedEvents()
            == [.pairingPresented(review.reviewID)]
    )

    await authority.invalidate(generation: 90)
    #expect(await authority.currentGeneration() == 91)
    await authority.invalidate(generation: 91)
    #expect(await authority.currentGeneration() == nil)
    await #expect(
        throws:
            MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .staleGeneration(91)
    ) {
        try await authority.install(firstSurfaces)
    }

    await authority.finish()
    let second = PreparedMenuEndpointProbeV1()
    let secondSurfaces = try await router.bindAuthenticated(
        generation: 92,
        endpointFactory: { second }
    )
    await #expect(
        throws: MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.terminal
    ) {
        try await authority.install(secondSurfaces)
    }
    await router.finish()
}

@Test
@available(macOS 26.0, *)
func preparedMenuAuthorityFencesPresentationAcrossReplacement()
    async throws
{
    let gate = PreparedMenuSurfaceGateV1()
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let authority = MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    let first = PreparedMenuEndpointProbeV1(pairingGate: gate)
    let firstSurfaces = try await router.bindAuthenticated(
        generation: 101,
        endpointFactory: { first }
    )
    try await authority.install(firstSurfaces)
    let review = try preparedMenuPairingReviewV1()

    let presentation = Task {
        try await authority.presentLocalPairingReview(review)
    }
    await gate.waitUntilEntered()
    let second = PreparedMenuEndpointProbeV1()
    let secondSurfaces = try await router.bindAuthenticated(
        generation: 102,
        endpointFactory: { second }
    )
    try await authority.install(secondSurfaces)
    await gate.release()

    await #expect(throws: (any Error).self) {
        try await presentation.value
    }
    #expect(
        await first.recordedEvents() == [
            .pairingPresented(review.reviewID),
            .invalidated,
            .pairingWithdrawn(review.reviewID),
        ]
    )
    try await authority.presentLocalPairingReview(review)
    #expect(
        await second.recordedEvents()
            == [.pairingPresented(review.reviewID)]
    )
    await authority.finish()
    await router.finish()
}

@Test
@available(macOS 26.0, *)
func preparedMenuAuthorityAvailabilityWaitersResolveAndFinishTerminally()
    async throws
{
    let authority = MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    let firstWaiter = Task {
        try await authority.waitForAvailableGeneration()
    }
    for _ in 0..<50 { await Task.yield() }
    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 111,
        endpointFactory: { PreparedMenuEndpointProbeV1() }
    )
    try await authority.install(surfaces)
    #expect(try await firstWaiter.value == 111)
    #expect(try await authority.waitForAvailableGeneration() == 111)

    await authority.invalidate(generation: 111)
    let terminalWaiter = Task {
        try await authority.waitForAvailableGeneration()
    }
    for _ in 0..<50 { await Task.yield() }
    await authority.finish()
    await #expect(
        throws: MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.terminal
    ) {
        try await terminalWaiter.value
    }
    await router.finish()
}

@Test
@available(macOS 26.0, *)
func preparedMenuAuthorityCancelledWaiterCannotPublishAvailability()
    async throws
{
    let authority = MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    let waiter = Task {
        try await authority.waitForAvailableGeneration()
    }
    for _ in 0..<50 { await Task.yield() }
    waiter.cancel()

    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 121,
        endpointFactory: { PreparedMenuEndpointProbeV1() }
    )
    try await authority.install(surfaces)

    await #expect(throws: CancellationError.self) {
        try await waiter.value
    }
    #expect(try await authority.waitForAvailableGeneration() == 121)
    await authority.finish()
    await router.finish()
}
#endif
