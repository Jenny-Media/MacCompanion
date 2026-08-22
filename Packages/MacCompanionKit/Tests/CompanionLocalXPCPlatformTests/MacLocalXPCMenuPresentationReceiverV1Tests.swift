@testable import CompanionLocalXPCPlatform
import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let receiverPairingReviewID = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000d1"
)!
private let receiverRecoveryReviewID = UUID(
    uuidString: "018f7100-0000-7000-8000-0000000000d1"
)!
private let receiverCreatedAt: Int64 = 1_787_198_400_000
private let receiverExpiresAt: Int64 = receiverCreatedAt + 300_000

private func receiverPairingReview(
    expiresAt: Int64 = 1_787_198_700_000
) throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: receiverPairingReviewID,
        pairingID: UUID(
            uuidString: "018f4000-0000-7000-8000-0000000000d1"
        )!,
        clientID: UUID(
            uuidString: "018f2000-0000-7000-8000-0000000000d1"
        )!,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x51, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x52, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x53, count: 32)),
        authenticationString: PairingAuthenticationString("23F-6F5"),
        expectedPolicyRevision: PolicyRevision(rawValue: 7),
        expiresAtUnixMilliseconds: expiresAt
    )
}

private func receiverRecoveryReview(
    cause: LocalHostIdentityRecoveryCauseV0 = .userRequestedReset
) throws -> LocalHostIdentityRecoveryReviewV0 {
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: receiverRecoveryReviewID,
        hostID: UUID(
            uuidString: "018f1000-0000-7000-8000-0000000000d1"
        )!,
        hostFingerprint: WireFingerprint(Data(repeating: 0x61, count: 32)),
        cause: cause,
        createdAtUnixMilliseconds: receiverCreatedAt,
        expiresAtUnixMilliseconds: receiverExpiresAt
    )
}

private func receiverRecoveryResume(
    commandID: UUID = UUID(
        uuidString: "018f7200-0000-7000-8000-0000000000d1"
    )!
) throws -> LocalHostIdentityRecoveryCommandV0 {
    try LocalHostIdentityRecoveryCommandV0(
        commandID: commandID,
        recoveryID: UUID(
            uuidString: "018f7300-0000-7000-8000-0000000000d1"
        )!,
        review: receiverRecoveryReview(),
        confirmedAtUnixMilliseconds: receiverCreatedAt + 1
    )
}

private actor ReceiverSurfaceProbe:
    LocalPairingReviewSurfaceV0,
    LocalHostIdentityRecoverySurfaceV0
{
    enum Event: Equatable, Hashable, Sendable {
        case pairingPublish(UUID)
        case pairingWithdrawal(UUID)
        case recoveryReviewPublish(UUID)
        case recoveryResumePublish(UUID)
        case recoveryWithdrawal(UUID)
    }

    private var events: [Event] = []

    func presentLocalPairingReview(_ review: LocalPairingReviewV0) {
        events.append(.pairingPublish(review.reviewID))
    }

    func withdrawLocalPairingReview(reviewID: UUID) {
        events.append(.pairingWithdrawal(reviewID))
    }

    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) {
        events.append(.recoveryReviewPublish(review.reviewID))
    }

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) {
        events.append(.recoveryResumePublish(command.review.reviewID))
    }

    func withdrawHostIdentityRecovery(reviewID: UUID) {
        events.append(.recoveryWithdrawal(reviewID))
    }

    func recordedEvents() -> [Event] { events }
}

private final class ReceiverGenerationSurfaceProbe: @unchecked Sendable,
    LocalPairingReviewSurfaceV0,
    LocalHostIdentityRecoverySurfaceV0
{
    enum PairingBehavior: Sendable {
        case immediate
        case suspendAfterRetention
        case failAfterRetention
    }

    private let lock = NSLock()
    private let pairingBehavior: PairingBehavior
    private let deadlineWasInstalled: @Sendable () -> Bool
    private var pairingContinuation: CheckedContinuation<Void, Never>?
    private var pairingIDs: Set<UUID> = []
    private var recoveryIDs: Set<UUID> = []
    private var events: [ReceiverSurfaceProbe.Event] = []
    private var deadlineInstalledAtPairingStart = false

    init(
        pairingBehavior: PairingBehavior = .immediate,
        deadlineWasInstalled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.pairingBehavior = pairingBehavior
        self.deadlineWasInstalled = deadlineWasInstalled
    }

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        lock.withLock {
            deadlineInstalledAtPairingStart = deadlineWasInstalled()
            pairingIDs.insert(review.reviewID)
            events.append(.pairingPublish(review.reviewID))
        }
        switch pairingBehavior {
        case .immediate:
            return
        case .suspendAfterRetention:
            await withCheckedContinuation { continuation in
                lock.withLock {
                    pairingContinuation = continuation
                }
            }
        case .failAfterRetention:
            struct AmbiguousFailure: Error {}
            throw AmbiguousFailure()
        }
    }

    func withdrawLocalPairingReview(reviewID: UUID) async {
        lock.withLock {
            pairingIDs.remove(reviewID)
            events.append(.pairingWithdrawal(reviewID))
        }
    }

    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        lock.withLock {
            recoveryIDs.insert(review.reviewID)
            events.append(.recoveryReviewPublish(review.reviewID))
        }
    }

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        lock.withLock {
            recoveryIDs.insert(command.review.reviewID)
            events.append(.recoveryResumePublish(command.review.reviewID))
        }
    }

    func withdrawHostIdentityRecovery(reviewID: UUID) async {
        lock.withLock {
            recoveryIDs.remove(reviewID)
            events.append(.recoveryWithdrawal(reviewID))
        }
    }

    func resumePairingPresentation() {
        lock.lock()
        let continuation = pairingContinuation
        pairingContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func snapshot() -> (
        events: [ReceiverSurfaceProbe.Event],
        pairingIDs: Set<UUID>,
        deadlineInstalledAtPairingStart: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            events,
            pairingIDs,
            deadlineInstalledAtPairingStart
        )
    }
}

private final class ReceiverGenerationTransportProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var retainedRequests: [Int] = []
    private var releasedRequests: [Int] = []
    private var repliedRequests: [Int] = []
    private var replyObservedRetainedState: [Bool] = []
    private var terminalCountValue = 0
    var replySucceeds = true

    func retain(_ request: Int) {
        lock.lock()
        retainedRequests.append(request)
        lock.unlock()
    }

    func release(_ request: Int) {
        lock.lock()
        releasedRequests.append(request)
        lock.unlock()
    }

    func reply(_ request: Int, observedRetainedState: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        repliedRequests.append(request)
        replyObservedRetainedState.append(observedRetainedState)
        return replySucceeds
    }

    func terminal() {
        lock.lock()
        terminalCountValue += 1
        lock.unlock()
    }

    func snapshot() -> (
        retained: [Int],
        released: [Int],
        replied: [Int],
        replyObservedRetainedState: [Bool],
        terminalCount: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            retainedRequests,
            releasedRequests,
            repliedRequests,
            replyObservedRetainedState,
            terminalCountValue
        )
    }
}

private final class ReceiverManualDeadlineScheduler: @unchecked Sendable {
    private final class Entry: @unchecked Sendable {
        private let lock = NSLock()
        private let queue: DispatchQueue
        private let operation: @Sendable () -> Void
        private var cancelled = false

        init(queue: DispatchQueue, operation: @escaping @Sendable () -> Void) {
            self.queue = queue
            self.operation = operation
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func fire() {
            lock.lock()
            let shouldFire = !cancelled
            lock.unlock()
            if shouldFire { queue.async(execute: operation) }
        }
    }

    private let lock = NSLock()
    private let queue: DispatchQueue
    private var entries: [Entry] = []

    init(queue: DispatchQueue) { self.queue = queue }

    func schedule(
        _ interval: DispatchTimeInterval,
        _ operation: @escaping @Sendable () -> Void
    ) -> MacLocalXPCMenuPresentationScheduledDeadlineV1 {
        #expect(interval == .seconds(2))
        let entry = Entry(queue: queue, operation: operation)
        lock.lock()
        entries.append(entry)
        lock.unlock()
        return MacLocalXPCMenuPresentationScheduledDeadlineV1 {
            entry.cancel()
        }
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func fireFirst() {
        lock.lock()
        let entry = entries.first
        lock.unlock()
        entry?.fire()
    }
}

private final class ReceiverRequestIDSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

@available(macOS 26.0, *)
private func makeReceiverGeneration(
    queue: DispatchQueue,
    surface: ReceiverGenerationSurfaceProbe,
    transport: ReceiverGenerationTransportProbe,
    scheduler: ReceiverManualDeadlineScheduler,
    requestIDs: [UUID] = (0..<12).map { _ in UUID() }
) -> MacLocalXPCMenuPresentationReceiverGenerationV1<Int> {
    let requestIDSource = ReceiverRequestIDSource(requestIDs)
    return MacLocalXPCMenuPresentationReceiverGenerationV1(
        surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1(
            pairingReviews: surface,
            hostIdentityRecovery: surface,
            nowUnixMilliseconds: { receiverCreatedAt }
        ),
        retainRequest: transport.retain,
        releaseRequest: transport.release,
        reply: { request, kind in
            let state = surface.snapshot()
            let observedRetained: Bool = switch kind {
            case .pairingReview:
                state.pairingIDs.contains(receiverPairingReviewID)
            case .pairingWithdrawal:
                !state.pairingIDs.contains(receiverPairingReviewID)
            case .hostRecoveryReview, .hostRecoveryResume,
                 .hostRecoveryWithdrawal:
                true
            }
            return transport.reply(
                request,
                observedRetainedState: observedRetained
            )
        },
        enqueue: { operation in queue.async(execute: operation) },
        scheduleDeadline: scheduler.schedule,
        makeRequestID: requestIDSource.next,
        onTerminal: transport.terminal
    )
}

private func waitForReceiverCondition(
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

@Test
func receiverRetainedStateExecutesAllFiveClosedMutations() async throws {
    let probe = ReceiverSurfaceProbe()
    let surfaces = MacLocalXPCMenuPresentationReceiverSurfacesV1(
        pairingReviews: probe,
        hostIdentityRecovery: probe,
        nowUnixMilliseconds: { receiverCreatedAt }
    )
    var state = MacLocalXPCMenuPresentationRetainedStateV1()
    let pairing = try receiverPairingReview()
    let pairingPayload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(pairing)
    let recovery = try receiverRecoveryReview()
    let recoveryPayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(recovery)
    let resume = try receiverRecoveryResume()
    let resumePayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryResume(resume)

    let pairingPublish = try state.prepare(
        .pairingReview(pairingPayload),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try await pairingPublish.execute(using: surfaces)
    try state.apply(pairingPublish)
    #expect(state.pairingReviewID == pairing.reviewID)

    let pairingWithdrawal = try state.prepare(
        .pairingWithdrawal(pairing.reviewID),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try await pairingWithdrawal.execute(using: surfaces)
    try state.apply(pairingWithdrawal)
    #expect(state.pairingReviewID == nil)

    let recoveryPublish = try state.prepare(
        .hostRecoveryReview(recoveryPayload),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try await recoveryPublish.execute(using: surfaces)
    try state.apply(recoveryPublish)

    let recoveryWithdrawal = try state.prepare(
        .hostRecoveryWithdrawal(recovery.reviewID),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try await recoveryWithdrawal.execute(using: surfaces)
    try state.apply(recoveryWithdrawal)

    let resumePublish = try state.prepare(
        .hostRecoveryResume(resumePayload),
        nowUnixMilliseconds: receiverExpiresAt + 10_000
    )
    try await resumePublish.execute(using: surfaces)
    try state.apply(resumePublish)
    let resumeWithdrawal = try state.prepare(
        .hostRecoveryWithdrawal(resume.review.reviewID),
        nowUnixMilliseconds: receiverExpiresAt + 10_000
    )
    try await resumeWithdrawal.execute(using: surfaces)
    try state.apply(resumeWithdrawal)

    #expect(await probe.recordedEvents() == [
        .pairingPublish(pairing.reviewID),
        .pairingWithdrawal(pairing.reviewID),
        .recoveryReviewPublish(recovery.reviewID),
        .recoveryWithdrawal(recovery.reviewID),
        .recoveryResumePublish(resume.review.reviewID),
        .recoveryWithdrawal(resume.review.reviewID),
    ])
}

@Test
func receiverExactReplayAndAbsentWithdrawalAreAcknowledgementOnly() throws {
    var state = MacLocalXPCMenuPresentationRetainedStateV1()
    let pairingPayload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(receiverPairingReview())
    let publish = try state.prepare(
        .pairingReview(pairingPayload),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try state.apply(publish)

    #expect(
        try state.prepare(
            .pairingReview(pairingPayload),
            nowUnixMilliseconds: receiverCreatedAt
        ) == .acknowledgeWithoutMutation
    )
    #expect(
        try state.prepare(
            .pairingWithdrawal(UUID()),
            nowUnixMilliseconds: receiverCreatedAt
        ) == .acknowledgeWithoutMutation
    )
    #expect(
        try state.prepare(
            .hostRecoveryWithdrawal(UUID()),
            nowUnixMilliseconds: receiverCreatedAt
        ) == .acknowledgeWithoutMutation
    )
}

@Test
func receiverSameIdentifierChangedBytesAndModeSubstitutionFailClosed()
    throws
{
    var pairingState = MacLocalXPCMenuPresentationRetainedStateV1()
    let originalPairing = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(receiverPairingReview())
    try pairingState.apply(
        pairingState.prepare(
            .pairingReview(originalPairing),
            nowUnixMilliseconds: receiverCreatedAt
        )
    )
    let changedPairing = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(
            receiverPairingReview(expiresAt: 1_787_198_700_001)
        )
    #expect(
        throws: MacLocalXPCMenuPresentationReceiverErrorV1
            .conflictingRetainedPresentation
    ) {
        try pairingState.prepare(
            .pairingReview(changedPairing),
            nowUnixMilliseconds: receiverCreatedAt
        )
    }

    var recoveryState = MacLocalXPCMenuPresentationRetainedStateV1()
    let reviewPayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(receiverRecoveryReview())
    try recoveryState.apply(
        recoveryState.prepare(
            .hostRecoveryReview(reviewPayload),
            nowUnixMilliseconds: receiverCreatedAt
        )
    )
    let resumePayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryResume(receiverRecoveryResume())
    #expect(
        throws: MacLocalXPCMenuPresentationReceiverErrorV1
            .conflictingRetainedPresentation
    ) {
        try recoveryState.prepare(
            .hostRecoveryResume(resumePayload),
            nowUnixMilliseconds: receiverCreatedAt
        )
    }
}

@Test
func receiverFreshRecoveryReviewUsesClosedWallClockBounds() throws {
    let payload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(receiverRecoveryReview())

    for now in [receiverCreatedAt, receiverExpiresAt - 1] {
        let state = MacLocalXPCMenuPresentationRetainedStateV1()
        #expect(
            try state.prepare(
                .hostRecoveryReview(payload),
                nowUnixMilliseconds: now
            ) != .acknowledgeWithoutMutation
        )
    }
    for now in [receiverCreatedAt - 1, receiverExpiresAt] {
        let state = MacLocalXPCMenuPresentationRetainedStateV1()
        #expect(
            throws: MacLocalXPCMenuPresentationReceiverErrorV1
                .recoveryReviewOutsideFreshWindow
        ) {
            try state.prepare(
                .hostRecoveryReview(payload),
                nowUnixMilliseconds: now
            )
        }
    }

    var retained = MacLocalXPCMenuPresentationRetainedStateV1()
    let first = try retained.prepare(
        .hostRecoveryReview(payload),
        nowUnixMilliseconds: receiverCreatedAt
    )
    try retained.apply(first)
    #expect(
        try retained.prepare(
            .hostRecoveryReview(payload),
            nowUnixMilliseconds: receiverExpiresAt
        ) == .acknowledgeWithoutMutation
    )
}

@Test
func receiverDurableResumeDoesNotRepeatCurrentClockFreshnessCheck() throws {
    let state = MacLocalXPCMenuPresentationRetainedStateV1()
    let resumePayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryResume(receiverRecoveryResume())
    #expect(
        try state.prepare(
            .hostRecoveryResume(resumePayload),
            nowUnixMilliseconds: receiverExpiresAt + 86_400_000
        ) != .acknowledgeWithoutMutation
    )
}

@Test
@available(macOS 26.0, *)
func receiverMalformedPayloadIsTerminalAndTimeoutIsExactlyTwoSeconds() {
    let state = MacLocalXPCMenuPresentationRetainedStateV1()
    #expect(
        throws: MacLocalXPCMenuPresentationReceiverErrorV1.malformedPayload
    ) {
        try state.prepare(
            .pairingReview(Data([0x7b, 0x7d])),
            nowUnixMilliseconds: receiverCreatedAt
        )
    }
    #expect(MacLocalXPCClientV1.menuPresentationReceiverTimeout == .seconds(2))
}

@Test
func retirementPlanWithdrawsRetainedAndPossiblyRetainedExactIDs()
    async throws
{
    var state = MacLocalXPCMenuPresentationRetainedStateV1()
    let pairingPayload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(receiverPairingReview())
    try state.apply(
        state.prepare(
            .pairingReview(pairingPayload),
            nowUnixMilliseconds: receiverCreatedAt
        )
    )
    let recoveryPayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(receiverRecoveryReview())
    try state.apply(
        state.prepare(
            .hostRecoveryReview(recoveryPayload),
            nowUnixMilliseconds: receiverCreatedAt
        )
    )

    let possiblePairingID = UUID()
    let plan = MacLocalXPCMenuPresentationRetirementPlanV1(
        retainedState: &state,
        activeMutation: .withdrawPairingReview(
            reviewID: possiblePairingID
        )
    )
    #expect(plan.pairingReviewIDs == [
        receiverPairingReviewID,
        possiblePairingID,
    ])
    #expect(plan.hostRecoveryReviewIDs == [receiverRecoveryReviewID])
    #expect(state.pairingReviewID == nil)
    #expect(state.hostRecoveryReviewID == nil)

    let probe = ReceiverSurfaceProbe()
    await plan.execute(
        using: MacLocalXPCMenuPresentationReceiverSurfacesV1(
            pairingReviews: probe,
            hostIdentityRecovery: probe
        )
    )
    let events = await probe.recordedEvents()
    #expect(Set(events) == Set([
        .pairingWithdrawal(receiverPairingReviewID),
        .pairingWithdrawal(possiblePairingID),
        .recoveryWithdrawal(receiverRecoveryReviewID),
    ]))
}

@Test
func retirementBarrierWaitsForActiveWorkBeforeExactCleanup() async throws {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let activeTask = Task {
        for await _ in stream { break }
    }
    var state = MacLocalXPCMenuPresentationRetainedStateV1()
    let plan = MacLocalXPCMenuPresentationRetirementPlanV1(
        retainedState: &state,
        activeMutation: .presentPairingReview(
            try receiverPairingReview(),
            canonicalPayload: Data([1])
        )
    )
    let probe = ReceiverSurfaceProbe()
    let surfaces = MacLocalXPCMenuPresentationReceiverSurfacesV1(
        pairingReviews: probe,
        hostIdentityRecovery: probe
    )
    let barrier = Task {
        await MacLocalXPCMenuPresentationRetirementBarrierV1.finish(
            awaiting: [activeTask],
            plan: plan,
            surfaces: surfaces
        )
    }

    await Task.yield()
    #expect(await probe.recordedEvents().isEmpty)
    continuation.yield()
    continuation.finish()
    await barrier.value
    #expect(await probe.recordedEvents() == [
        .pairingWithdrawal(receiverPairingReviewID),
    ])
}

@Test
@available(macOS 26.0, *)
func productionReceiverDeniesPrematureUnauthorizedAndMalformedTraffic()
    throws
{
    let payload = try LocalMenuPresentationWireCodecV1.encodePairingReview(
        receiverPairingReview()
    )
    for input in [
        (
            Optional(MacLocalXPCMenuPresentationRequestV1.pairingReview(payload)),
            false,
            true
        ),
        (
            Optional(MacLocalXPCMenuPresentationRequestV1.pairingReview(payload)),
            true,
            false
        ),
        (nil, true, true),
    ] {
        let queue = DispatchQueue(label: "receiver-denial-\(UUID())")
        let transport = ReceiverGenerationTransportProbe()
        let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
        let surface = ReceiverGenerationSurfaceProbe()
        let receiver = makeReceiverGeneration(
            queue: queue,
            surface: surface,
            transport: transport,
            scheduler: scheduler
        )
        queue.sync {
            receiver.receive(
                copiedRequest: input.0,
                borrowedRequest: 1,
                authenticatedAndReady: input.1,
                authorized: input.2
            )
        }
        let snapshot = transport.snapshot()
        #expect(receiver.isTerminal)
        #expect(snapshot.terminalCount == 1)
        #expect(snapshot.retained.isEmpty)
        #expect(snapshot.released.isEmpty)
        #expect(snapshot.replied.isEmpty)
        #expect(scheduler.count() == 0)
    }
}

@Test
@available(macOS 26.0, *)
func productionReceiverRetainsPresentsThenAcknowledgesAndReleases()
    async throws
{
    let queue = DispatchQueue(label: "receiver-success")
    let transport = ReceiverGenerationTransportProbe()
    let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
    let surface = ReceiverGenerationSurfaceProbe(
        deadlineWasInstalled: { scheduler.count() == 1 }
    )
    let receiver = makeReceiverGeneration(
        queue: queue,
        surface: surface,
        transport: transport,
        scheduler: scheduler
    )
    let payload = try LocalMenuPresentationWireCodecV1.encodePairingReview(
        receiverPairingReview()
    )

    queue.sync {
        receiver.receive(
            copiedRequest: .pairingReview(payload),
            borrowedRequest: 41,
            authenticatedAndReady: true,
            authorized: true
        )
    }
    #expect(await waitForReceiverCondition {
        transport.snapshot().replied == [41]
    })
    let snapshot = transport.snapshot()
    #expect(snapshot.retained == [41])
    #expect(snapshot.released == [41])
    #expect(snapshot.replied == [41])
    #expect(snapshot.replyObservedRetainedState == [true])
    #expect(snapshot.terminalCount == 0)
    #expect(receiver.pendingCount == 0)
    #expect(receiver.retainedPairingReviewID == receiverPairingReviewID)
    #expect(surface.snapshot().deadlineInstalledAtPairingStart)
}

@Test
@available(macOS 26.0, *)
func productionReceiverPreservesCrossFamilyFIFOOrder() async throws {
    let queue = DispatchQueue(label: "receiver-fifo")
    let transport = ReceiverGenerationTransportProbe()
    let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
    let surface = ReceiverGenerationSurfaceProbe(
        pairingBehavior: .suspendAfterRetention
    )
    let receiver = makeReceiverGeneration(
        queue: queue,
        surface: surface,
        transport: transport,
        scheduler: scheduler
    )
    let pairingPayload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(receiverPairingReview())
    let recoveryPayload = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(receiverRecoveryReview())

    queue.sync {
        receiver.receive(
            copiedRequest: .pairingReview(pairingPayload),
            borrowedRequest: 51,
            authenticatedAndReady: true,
            authorized: true
        )
        receiver.receive(
            copiedRequest: .hostRecoveryReview(recoveryPayload),
            borrowedRequest: 52,
            authenticatedAndReady: true,
            authorized: true
        )
    }
    #expect(await waitForReceiverCondition {
        surface.snapshot().events == [
            .pairingPublish(receiverPairingReviewID),
        ]
    })
    #expect(transport.snapshot().replied.isEmpty)
    surface.resumePairingPresentation()
    #expect(await waitForReceiverCondition {
        transport.snapshot().replied == [51, 52]
    })
    #expect(surface.snapshot().events == [
        .pairingPublish(receiverPairingReviewID),
        .recoveryReviewPublish(receiverRecoveryReviewID),
    ])
    #expect(transport.snapshot().released == [51, 52])
}

@Test
@available(macOS 26.0, *)
func productionReceiverOverflowRetirementWaitsAndNeverStartsQueuedWork()
    async throws
{
    let queue = DispatchQueue(label: "receiver-overflow")
    let transport = ReceiverGenerationTransportProbe()
    let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
    let surface = ReceiverGenerationSurfaceProbe(
        pairingBehavior: .suspendAfterRetention
    )
    let receiver = makeReceiverGeneration(
        queue: queue,
        surface: surface,
        transport: transport,
        scheduler: scheduler
    )
    let payload = try LocalMenuPresentationWireCodecV1.encodePairingReview(
        receiverPairingReview()
    )
    queue.sync {
        receiver.receive(
            copiedRequest: .pairingReview(payload),
            borrowedRequest: 1,
            authenticatedAndReady: true,
            authorized: true
        )
    }
    #expect(await waitForReceiverCondition {
        !surface.snapshot().events.isEmpty
    })
    queue.sync {
        for request in 2...8 {
            receiver.receive(
                copiedRequest: .pairingWithdrawal(UUID()),
                borrowedRequest: request,
                authenticatedAndReady: true,
                authorized: true
            )
        }
        receiver.receive(
            copiedRequest: .pairingWithdrawal(UUID()),
            borrowedRequest: 9,
            authenticatedAndReady: true,
            authorized: true
        )
    }
    #expect(receiver.isTerminal)
    #expect(receiver.pendingCount == 8)
    #expect(surface.snapshot().events == [
        .pairingPublish(receiverPairingReviewID),
    ])
    let cleanup = queue.sync { receiver.retire() }
    #expect(transport.snapshot().retained == Array(1...8))
    #expect(Set(transport.snapshot().released) == Set(1...8))
    #expect(transport.snapshot().released.count == 8)
    #expect(transport.snapshot().replied.isEmpty)

    surface.resumePairingPresentation()
    await cleanup.value
    #expect(transport.snapshot().replied.isEmpty)
    #expect(surface.snapshot().events == [
        .pairingPublish(receiverPairingReviewID),
        .pairingWithdrawal(receiverPairingReviewID),
    ])
}

@Test
@available(macOS 26.0, *)
func productionReceiverTimeoutFencesLateCompletionAndAwaitsCleanup()
    async throws
{
    let queue = DispatchQueue(label: "receiver-timeout")
    let transport = ReceiverGenerationTransportProbe()
    let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
    let surface = ReceiverGenerationSurfaceProbe(
        pairingBehavior: .suspendAfterRetention
    )
    let receiver = makeReceiverGeneration(
        queue: queue,
        surface: surface,
        transport: transport,
        scheduler: scheduler
    )
    let payload = try LocalMenuPresentationWireCodecV1.encodePairingReview(
        receiverPairingReview()
    )
    queue.sync {
        receiver.receive(
            copiedRequest: .pairingReview(payload),
            borrowedRequest: 61,
            authenticatedAndReady: true,
            authorized: true
        )
    }
    #expect(await waitForReceiverCondition {
        !surface.snapshot().events.isEmpty
    })
    scheduler.fireFirst()
    #expect(await waitForReceiverCondition {
        transport.snapshot().terminalCount == 1
    })
    let cleanup = queue.sync { receiver.retire() }
    #expect(transport.snapshot().released == [61])
    #expect(transport.snapshot().replied.isEmpty)
    surface.resumePairingPresentation()
    await cleanup.value
    #expect(transport.snapshot().replied.isEmpty)
    #expect(surface.snapshot().events.last ==
        .pairingWithdrawal(receiverPairingReviewID))
}

@Test
@available(macOS 26.0, *)
func productionReceiverAmbiguousThrowAndReplyFailureBothCleanExactState()
    async throws
{
    for (label, behavior, replySucceeds) in [
        ("throw", ReceiverGenerationSurfaceProbe.PairingBehavior.failAfterRetention, true),
        ("reply", .immediate, false),
    ] {
        let queue = DispatchQueue(label: "receiver-\(label)")
        let transport = ReceiverGenerationTransportProbe()
        transport.replySucceeds = replySucceeds
        let scheduler = ReceiverManualDeadlineScheduler(queue: queue)
        let surface = ReceiverGenerationSurfaceProbe(
            pairingBehavior: behavior
        )
        let receiver = makeReceiverGeneration(
            queue: queue,
            surface: surface,
            transport: transport,
            scheduler: scheduler
        )
        let payload = try LocalMenuPresentationWireCodecV1
            .encodePairingReview(receiverPairingReview())
        queue.sync {
            receiver.receive(
                copiedRequest: .pairingReview(payload),
                borrowedRequest: 71,
                authenticatedAndReady: true,
                authorized: true
            )
        }
        #expect(await waitForReceiverCondition {
            transport.snapshot().terminalCount == 1
        })
        let cleanup = queue.sync { receiver.retire() }
        await cleanup.value
        let snapshot = transport.snapshot()
        #expect(snapshot.retained == [71])
        #expect(snapshot.released == [71])
        #expect(snapshot.replyObservedRetainedState.allSatisfy { $0 })
        #expect(surface.snapshot().events.last ==
            .pairingWithdrawal(receiverPairingReviewID))
    }
}
