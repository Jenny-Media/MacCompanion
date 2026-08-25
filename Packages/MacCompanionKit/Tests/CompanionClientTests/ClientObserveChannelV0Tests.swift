@testable import CompanionClient
import CompanionObservation
import CompanionWire
import Dispatch
import Foundation
import Testing

private let observeClientID = UUID(
    uuidString: "018fa700-0000-7000-8000-000000000001"
)!
private let observeHostID = UUID(
    uuidString: "018fa700-0000-7000-8000-000000000002"
)!
private let observeDeviceID = UUID(
    uuidString: "018fa700-0000-7000-8000-000000000003"
)!
private let observeGeneration = WireUUID(UUID(
    uuidString: "018fa700-0000-7000-8000-000000000004"
)!)

private enum ObserveTransportError: Error { case injected }

private actor ObserveTransport: ClientAuthenticatedCommandSendingV1 {
    private var frames: [Data] = []
    private var shouldFailNext = false
    private var shouldSuspendNext = false
    private var suspended = false
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeSuspended: CheckedContinuation<Void, Never>?

    func sendAuthenticatedCommand(_ frame: Data) async throws {
        if shouldFailNext {
            shouldFailNext = false
            throw ObserveTransportError.injected
        }
        if shouldSuspendNext {
            shouldSuspendNext = false
            suspended = true
            for waiter in suspendedWaiters { waiter.resume() }
            suspendedWaiters.removeAll()
            await withCheckedContinuation { resumeSuspended = $0 }
        }
        frames.append(frame)
    }

    func failNext() { shouldFailNext = true }
    func suspendNext() { shouldSuspendNext = true }
    func capturedFrames() -> [Data] { frames }

    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { suspendedWaiters.append($0) }
    }

    func resume() {
        suspended = false
        resumeSuspended?.resume()
        resumeSuspended = nil
    }
}

private final class ObserveIDSource: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacCompanionTests.ObserveIDs")
    private var nextValue: UInt64 = 10

    func next() -> WireUUID {
        queue.sync {
            defer { nextValue += 1 }
            let text = String(format: "%012llx", nextValue)
            return WireUUID(UUID(
                uuidString: "018fa700-0000-7000-8000-\(text)"
            )!)
        }
    }
}

private final class ObserveClock: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacCompanionTests.ObserveClock")
    private var wallStorage: Int64 = 10_200
    private var monotonicStorage: Int64 = 1_000

    var wall: Int64 { queue.sync { wallStorage } }
    var monotonic: Int64 { queue.sync { monotonicStorage } }

    func setMonotonic(_ value: Int64) {
        queue.sync { monotonicStorage = value }
    }
}

private final class ObserveEventRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacCompanionTests.ObserveEvents")
    private var storage: [ClientObserveChannelEventV0] = []

    var events: [ClientObserveChannelEventV0] { queue.sync { storage } }
    func record(_ event: ClientObserveChannelEventV0) {
        queue.sync { storage.append(event) }
    }
}

private struct ObserveHarness {
    let transport: ObserveTransport
    let router: ClientPrimaryCommandRouterV0
    let channel: ClientObserveChannelV0
    let clock: ObserveClock
    let events: ObserveEventRecorder
}

private func observeSession() -> ClientAuthenticatedSessionV0 {
    ClientAuthenticatedSessionV0(
        clientID: observeClientID,
        hostID: observeHostID,
        deviceID: observeDeviceID,
        connectionID: Data(repeating: 0x70, count: 16),
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 3),
        policyRevision: .init(rawValue: 4),
        hostState: .userSessionActive,
        features: ["audit.readSelf", "status.snapshot"],
        serverTimeUnixMilliseconds: 10_200
    )
}

private func makeObserveHarness() async throws -> ObserveHarness {
    let transport = ObserveTransport()
    let clock = ObserveClock()
    let events = ObserveEventRecorder()
    let ids = ObserveIDSource()
    let router = try ClientPrimaryCommandRouterV0(
        authenticatedSession: observeSession(),
        transport: transport,
        monotonicNowNanoseconds: { 1_000_000 }
    )
    let channel = try ClientObserveChannelV0(
        authenticatedSession: observeSession(),
        sender: router.sender(for: .observe),
        environment: ClientObserveChannelEnvironmentV0(
            makeMessageID: { ids.next() },
            wallNowUnixMilliseconds: { clock.wall },
            monotonicNowMilliseconds: { clock.monotonic }
        ),
        publish: { events.record($0) }
    )
    try await router.installReceiver(channel, for: .observe)
    try await router.activate()
    return ObserveHarness(
        transport: transport,
        router: router,
        channel: channel,
        clock: clock,
        events: events
    )
}

private func observeSystem() throws -> SystemOverview {
    try SystemOverview(
        osName: "macOS",
        osVersion: "26.0",
        osBuild: "25A100",
        uptimeSeconds: 500,
        cpuUtilizationBasisPoints: 1_250,
        memoryTotalBytes: 16_000,
        memoryUsedBytes: 8_000,
        storageTotalBytes: 100_000,
        storageAvailableBytes: 40_000,
        powerSource: .ac,
        batteryLevelPercent: nil
    )
}

private func statusResponse(
    correlationID: WireUUID,
    generation: WireUUID = observeGeneration,
    revision: Int64 = 1
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: correlationID,
        sentAtUnixMilliseconds: 10_100,
        body: StatusSnapshotBody(
            hostID: WireUUID(observeHostID),
            generation: generation,
            revision: revision,
            observedAtUnixMilliseconds: 10_000,
            validForMilliseconds: 1_000,
            hostState: .userSessionActive,
            system: try observeSystem()
        )
    ))
}

private func requestEnvelope<Body: WireBody>(
    _ frame: Data,
    as body: Body.Type
) throws -> WireEnvelope<Body> {
    try WireCodec.decode(WireEnvelope<Body>.self, from: frame)
}

private func observeAuditEvent(_ sequence: Int64) throws
    -> AuditSelfEventWireV1
{
    try AuditSelfEventWireV1(
        sequence: sequence,
        eventID: WireUUID(UUID()),
        observedAtUnixMilliseconds: sequence,
        scope: .selfDevice,
        actor: .agent,
        code: .connectionOpened,
        outcome: .succeeded
    )
}

private func auditResponse(
    correlationID: WireUUID,
    sequences: [Int64],
    next: Int64?,
    dropped: Int64 = 2
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: correlationID,
        sentAtUnixMilliseconds: 10_201,
        body: AuditListResponseBodyV1(
            events: try sequences.map(observeAuditEvent),
            nextBeforeSequence: next,
            oldestVisibleSequence: 1,
            newestVisibleSequence: 10,
            gaps: AuditGapWireV1(
                prunedThroughSequence: 1,
                droppedEventCount: dropped
            )
        )
    ))
}

private func observeError(
    correlationID: WireUUID,
    code: String = "policy.denied"
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: correlationID,
        sentAtUnixMilliseconds: 10_201,
        body: try ProtocolErrorResponseBody(
            code: code,
            retry: .afterReconnect
        )
    ))
}

@Test func observeStatusUsesConservativeFreshnessAndRetainsUnreachable()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestStatus()
    let request = try requestEnvelope(
        try #require(await harness.transport.capturedFrames().last),
        as: StatusSnapshotRequestBody.self
    )
    harness.clock.setMonotonic(1_200)
    try await harness.router.receive(statusResponse(
        correlationID: request.messageID
    ))

    #expect(harness.events.events.count == 1)
    #expect(try await harness.channel.statusAssessment(
        monotonicNowMilliseconds: 1_899
    )?.state == .live)
    #expect(try await harness.channel.statusAssessment(
        monotonicNowMilliseconds: 1_900
    )?.state == .stale)

    await harness.router.invalidate()
    #expect(try await harness.channel.statusAssessment(
        monotonicNowMilliseconds: 1_901
    )?.state == .unreachable)
    #expect(await harness.channel.retainedStatus?.snapshot.revision == 1)
}

@Test func observeLivenessStatusIsCorrelatedWithoutPublishingOrRetaining()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestLivenessStatus()
    let request = try requestEnvelope(
        try #require(await harness.transport.capturedFrames().last),
        as: StatusSnapshotRequestBody.self
    )
    try await harness.router.receive(statusResponse(
        correlationID: request.messageID
    ))

    #expect(await harness.router.state == .ready)
    #expect(await harness.channel.retainedStatus == nil)
    #expect(harness.events.events.isEmpty)

    try await harness.channel.requestLivenessStatus()
    #expect(await harness.transport.capturedFrames().count == 2)
}

@Test func observeStatusRejectsGenerationOrRevisionRegression()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestStatus()
    var frames = await harness.transport.capturedFrames()
    var request = try requestEnvelope(
        try #require(frames.last),
        as: StatusSnapshotRequestBody.self
    )
    harness.clock.setMonotonic(1_100)
    try await harness.router.receive(statusResponse(
        correlationID: request.messageID
    ))

    try await harness.channel.requestStatus()
    frames = await harness.transport.capturedFrames()
    request = try requestEnvelope(
        try #require(frames.last),
        as: StatusSnapshotRequestBody.self
    )
    harness.clock.setMonotonic(1_200)
    await #expect(throws: ClientPrimaryCommandRouterErrorV0.routingRejected) {
        try await harness.router.receive(statusResponse(
            correlationID: request.messageID,
            revision: 1
        ))
    }
    #expect(await harness.router.state == .invalidated)
    #expect(harness.events.events.count == 1)
}

@Test func observeStatusSendFailurePreservesPriorSnapshotAndCanRetry()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestStatus()
    let first = try requestEnvelope(
        try #require(await harness.transport.capturedFrames().last),
        as: StatusSnapshotRequestBody.self
    )
    harness.clock.setMonotonic(1_100)
    try await harness.router.receive(statusResponse(
        correlationID: first.messageID
    ))

    await harness.transport.failNext()
    await #expect(throws: ClientObserveChannelErrorV0.sendFailed) {
        try await harness.channel.requestStatus()
    }
    #expect(await harness.router.state == .ready)
    #expect(await harness.channel.retainedStatus?.snapshot.revision == 1)
    #expect(harness.events.events.count == 1)

    try await harness.channel.requestStatus()
    #expect(await harness.transport.capturedFrames().count == 2)
}

@Test func observeAuditPagesKeepExclusiveCursorAndGapEvidence()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestNextAuditPage(limit: 2)
    var request = try requestEnvelope(
        try #require(await harness.transport.capturedFrames().last),
        as: AuditListRequestBodyV1.self
    )
    #expect(request.body.beforeSequence == nil)
    try await harness.router.receive(auditResponse(
        correlationID: request.messageID,
        sequences: [10, 9],
        next: 9
    ))

    try await harness.channel.requestNextAuditPage(limit: 2)
    request = try requestEnvelope(
        try #require(await harness.transport.capturedFrames().last),
        as: AuditListRequestBodyV1.self
    )
    #expect(request.body.beforeSequence == 9)
    try await harness.router.receive(auditResponse(
        correlationID: request.messageID,
        sequences: [8, 7],
        next: nil,
        dropped: 3
    ))

    let pages = harness.events.events.compactMap { event in
        if case let .auditPage(page) = event { return page }
        return nil
    }
    #expect(pages.map(\.events).map { $0.map(\.sequence) } == [[10, 9], [8, 7]])
    #expect(pages.map(\.gaps.droppedEventCount) == [2, 3])
    #expect(await harness.channel.auditPager.state == .exhausted)
}

@Test func observeSharedErrorsRouteByExactStatusOrAuditCorrelation()
    async throws
{
    let harness = try await makeObserveHarness()
    try await harness.channel.requestStatus()
    try await harness.channel.requestNextAuditPage(limit: 2)
    let frames = await harness.transport.capturedFrames()
    let status = try requestEnvelope(
        frames[0],
        as: StatusSnapshotRequestBody.self
    )
    let audit = try requestEnvelope(
        frames[1],
        as: AuditListRequestBodyV1.self
    )

    try await harness.router.receive(observeError(
        correlationID: audit.messageID
    ))
    #expect(await harness.channel.auditPager.state == .invalidated)
    #expect(harness.events.events.count == 1)
    if case let .remoteError(request, error) = harness.events.events[0] {
        #expect(request == .audit)
        #expect(error.code == "policy.denied")
    } else {
        Issue.record("Expected a correlated audit error")
    }

    harness.clock.setMonotonic(1_100)
    try await harness.router.receive(statusResponse(
        correlationID: status.messageID
    ))
    #expect(harness.events.events.count == 2)
}

@Test func observeInvalidationDuringSendCannotPublishOrLeavePendingWork()
    async throws
{
    let harness = try await makeObserveHarness()
    await harness.transport.suspendNext()
    let request = Task { try await harness.channel.requestStatus() }
    await harness.transport.waitUntilSuspended()
    await harness.router.invalidate()
    await harness.transport.resume()

    await #expect(
        throws: ClientObserveChannelErrorV0.invalidState(.invalidated)
    ) {
        try await request.value
    }
    #expect(await harness.channel.state == .invalidated)
    #expect(harness.events.events.isEmpty)
    #expect(await harness.channel.retainedStatus == nil)
}
