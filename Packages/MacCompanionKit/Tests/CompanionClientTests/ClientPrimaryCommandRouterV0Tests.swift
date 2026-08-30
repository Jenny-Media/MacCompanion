@testable import CompanionClient
import CompanionDomain
import CompanionTestSupport
import CompanionWire
import Dispatch
import Foundation
import Testing

private let routerClientID = UUID(
    uuidString: "018fa600-0000-7000-8000-000000000001"
)!
private let routerHostID = UUID(
    uuidString: "018fa600-0000-7000-8000-000000000002"
)!
private let routerDeviceID = UUID(
    uuidString: "018fa600-0000-7000-8000-000000000003"
)!

private enum RouterTestError: Error { case sendFailed }

private actor RouterTestTransport: ClientAuthenticatedCommandSendingV1 {
    private var frames: [Data] = []
    private var shouldFailNext = false

    func sendAuthenticatedCommand(_ frame: Data) async throws {
        if shouldFailNext {
            shouldFailNext = false
            throw RouterTestError.sendFailed
        }
        frames.append(frame)
    }

    func failNext() { shouldFailNext = true }
    func capturedFrames() -> [Data] { frames }
}

private final class RouterTestReceiver:
    ClientPrimaryReplyReceivingV0,
    @unchecked Sendable
{
    private let queue = DispatchQueue(label: "MacCompanionTests.RouterReceiver")
    private var preparedStorage: [Data] = []
    private var publishedStorage: [Data] = []
    private var preparedEventStorage: [Data] = []
    private var publishedEventStorage: [Data] = []
    private var invalidationCountStorage = 0

    var prepared: [Data] { queue.sync { preparedStorage } }
    var published: [Data] { queue.sync { publishedStorage } }
    var preparedEvents: [Data] { queue.sync { preparedEventStorage } }
    var publishedEvents: [Data] { queue.sync { publishedEventStorage } }
    var invalidationCount: Int { queue.sync { invalidationCountStorage } }

    func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        queue.sync { preparedStorage.append(frame) }
        return ClientPrimaryPreparedReplyV0 { [self] in
            queue.sync { publishedStorage.append(frame) }
        }
    }

    func preparePrimaryEvent(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedEventV0 {
        queue.sync { preparedEventStorage.append(frame) }
        return ClientPrimaryPreparedEventV0 { [self] in
            queue.sync { publishedEventStorage.append(frame) }
        }
    }

    func invalidatePrimaryReplyReceiver() async {
        queue.sync { invalidationCountStorage += 1 }
    }
}

private final class RouterPublicationRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacCompanionTests.RouterPublish")
    private var countStorage = 0
    var count: Int { queue.sync { countStorage } }
    func publish() { queue.sync { countStorage += 1 } }
}

private actor SuspendedRouterTestReceiver: ClientPrimaryReplyReceivingV0 {
    private let publications: RouterPublicationRecorder
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private(set) var invalidationCount = 0

    init(publications: RouterPublicationRecorder) {
        self.publications = publications
    }

    func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        started = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { finishContinuation = $0 }
        return ClientPrimaryPreparedReplyV0 { [publications] in
            publications.publish()
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func invalidatePrimaryReplyReceiver() async {
        invalidationCount += 1
    }
}

private struct RouterInteractiveRequestBody: WireBody {
    static let kind = WireMessageKind.interactiveSessionRequest
    func validate() throws {}
}

private struct RouterInteractiveApprovalRequiredBody: WireBody {
    static let kind = WireMessageKind.interactiveSessionApprovalRequired
    func validate() throws {}
}

private struct RouterInteractiveApprovalProofBody: WireBody {
    static let kind = WireMessageKind.interactiveSessionApprove
    func validate() throws {}
}

private actor RouterFollowupSendingReceiver:
    ClientPrimaryReplyReceivingV0
{
    private let sender: ClientPrimaryLaneCommandSenderV0
    private let followup: Data
    private(set) var sendCompleted = false

    init(sender: ClientPrimaryLaneCommandSenderV0, followup: Data) {
        self.sender = sender
        self.followup = followup
    }

    func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        try await sender.sendAuthenticatedCommand(followup)
        sendCompleted = true
        return ClientPrimaryPreparedReplyV0()
    }

    func invalidatePrimaryReplyReceiver() async {}
}

private func routerSession() -> ClientAuthenticatedSessionV0 {
    ClientAuthenticatedSessionV0(
        clientID: routerClientID,
        hostID: routerHostID,
        deviceID: routerDeviceID,
        connectionID: Data(0x60...0x6f),
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 3),
        policyRevision: .init(rawValue: 4),
        hostState: .userSessionActive,
        features: ["status.snapshot"],
        serverTimeUnixMilliseconds: 30_000
    )
}

private func routerRequest<Body: WireBody>(
    id: WireUUID,
    body: Body
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: id,
        correlationID: nil,
        sentAtUnixMilliseconds: 30_000,
        body: body
    ))
}

private func routerError(
    id: WireUUID = WireUUID(UUID()),
    correlationID: WireUUID
) throws -> Data {
    try WireCodec.encode(WireEnvelope(
        messageID: id,
        correlationID: correlationID,
        sentAtUnixMilliseconds: 30_001,
        body: try ProtocolErrorResponseBody(
            code: "capability.registryChanged",
            retry: .afterReconnect
        )
    ))
}

private func makeRouter(
    transport: RouterTestTransport,
    clock: UInt64 = 1_000
) throws -> ClientPrimaryCommandRouterV0 {
    try ClientPrimaryCommandRouterV0(
        authenticatedSession: routerSession(),
        transport: transport,
        monotonicNowNanoseconds: { clock }
    )
}

private func routerFocusEvent() throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent(
                "valid/interactive-surface-focus-changed.json"
            )
    )
}

@Test func primaryRouterRoutesSharedErrorKindOnlyByCorrelation()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let observe = RouterTestReceiver()
    let act = RouterTestReceiver()
    try await router.installReceiver(observe, for: .observe)
    try await router.installReceiver(act, for: .act)
    try await router.activate()
    let observeID = WireUUID(UUID())
    let actID = WireUUID(UUID())

    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: observeID, body: StatusSnapshotRequestBody())
    )
    try await router.sender(for: .act).sendAuthenticatedCommand(
        routerRequest(
            id: actID,
            body: try CapabilityRegistryRequestBody()
        )
    )
    try await router.receive(routerError(correlationID: actID))
    #expect(act.published.count == 1)
    #expect(observe.published.isEmpty)
    try await router.receive(routerError(correlationID: observeID))
    #expect(observe.published.count == 1)
    #expect(await router.state == .ready)
}

@Test func primaryRouterPermitsCorrelatedControlFollowupFromReplyPreparation()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let requestID = WireUUID(UUID())
    let challengeID = WireUUID(UUID())
    let proofID = WireUUID(UUID())
    let proof = try WireCodec.encode(WireEnvelope(
        messageID: proofID,
        correlationID: challengeID,
        sentAtUnixMilliseconds: 30_002,
        body: RouterInteractiveApprovalProofBody()
    ))
    let receiver = RouterFollowupSendingReceiver(
        sender: router.sender(for: .control),
        followup: proof
    )
    try await router.installReceiver(receiver, for: .control)
    try await router.activate()
    try await router.sender(for: .control).sendAuthenticatedCommand(
        routerRequest(id: requestID, body: RouterInteractiveRequestBody())
    )
    let challenge = try WireCodec.encode(WireEnvelope(
        messageID: challengeID,
        correlationID: requestID,
        sentAtUnixMilliseconds: 30_001,
        body: RouterInteractiveApprovalRequiredBody()
    ))

    try await router.receive(challenge)

    #expect(await receiver.sendCompleted)
    #expect(await transport.capturedFrames().count == 2)
    #expect(await router.state == .ready)
}

@Test func primaryRouterInterleavesFocusEventsWithoutConsumingCommands()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let observe = RouterTestReceiver()
    let control = RouterTestReceiver()
    try await router.installReceiver(observe, for: .observe)
    try await router.installReceiver(control, for: .control)
    try await router.activate()
    let requestID = WireUUID(UUID())
    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: requestID, body: StatusSnapshotRequestBody())
    )

    let event = try routerFocusEvent()
    try await router.receive(event)
    #expect(control.preparedEvents.count == 1)
    #expect(control.publishedEvents.count == 1)
    #expect(control.published.isEmpty)
    #expect(observe.published.isEmpty)

    try await router.receive(routerError(correlationID: requestID))
    #expect(observe.published.count == 1)
    #expect(await router.state == .ready)

    await #expect(throws: ClientPrimaryCommandRouterErrorV0.routingRejected) {
        try await router.receive(event)
    }
    #expect(await router.state == .invalidated)
    #expect(control.publishedEvents.count == 1)
    #expect(control.invalidationCount == 1)
    #expect(observe.invalidationCount == 1)
}

@Test func primaryRouterRejectsCrossLaneRequestsBeforeTransport()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    try await router.installReceiver(RouterTestReceiver(), for: .observe)
    try await router.activate()
    let frame = try routerRequest(
        id: WireUUID(UUID()),
        body: CapabilityRegistryRequestBody()
    )

    do {
        try await router.sender(for: .observe).sendAuthenticatedCommand(frame)
        Issue.record("Cross-lane request unexpectedly reached transport")
    } catch let error as ClientPrimaryCommandRouterErrorV0 {
        #expect(error == .wrongLaneKind(.observe, .capabilityRegistryRequest))
    }
    #expect(await transport.capturedFrames().isEmpty)
    #expect(await router.state == .ready)
}

@Test func primaryRouterWrongReplyKindInvalidatesEveryLane()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let observe = RouterTestReceiver()
    let act = RouterTestReceiver()
    try await router.installReceiver(observe, for: .observe)
    try await router.installReceiver(act, for: .act)
    try await router.activate()
    let requestID = WireUUID(UUID())
    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: requestID, body: StatusSnapshotRequestBody())
    )
    let wrongReply = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: requestID,
        sentAtUnixMilliseconds: 30_001,
        body: try OperationStatusResponseBody(
            operationID: WireUUID(UUID()),
            state: .queued,
            terminalCode: nil,
            result: nil
        )
    ))

    await #expect(throws: ClientPrimaryCommandRouterErrorV0.routingRejected) {
        try await router.receive(wrongReply)
    }
    #expect(await router.state == .invalidated)
    #expect(observe.invalidationCount == 1)
    #expect(act.invalidationCount == 1)
    await router.invalidate()
    #expect(observe.invalidationCount == 1)
}

@Test func primaryRouterRejectsDuplicateReplyAcrossPendingRequests()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let observe = RouterTestReceiver()
    try await router.installReceiver(observe, for: .observe)
    try await router.activate()
    let firstID = WireUUID(UUID())
    let secondID = WireUUID(UUID())
    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: firstID, body: StatusSnapshotRequestBody())
    )
    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: secondID, body: StatusSnapshotRequestBody())
    )
    let replyID = WireUUID(UUID())
    try await router.receive(routerError(
        id: replyID,
        correlationID: firstID
    ))
    #expect(observe.published.count == 1)

    await #expect(throws: ClientPrimaryCommandRouterErrorV0.routingRejected) {
        try await router.receive(routerError(
            id: replyID,
            correlationID: secondID
        ))
    }
    #expect(await router.state == .invalidated)
    #expect(observe.published.count == 1)
}

@Test func primaryRouterReturnsSendFailureBeforeConnectionInvalidation()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let observe = RouterTestReceiver()
    try await router.installReceiver(observe, for: .observe)
    try await router.activate()
    await transport.failNext()
    let failedID = WireUUID(UUID())

    await #expect(
        throws: ClientPrimaryCommandRouterErrorV0.transportSendFailed
    ) {
        try await router.sender(for: .observe).sendAuthenticatedCommand(
            routerRequest(
                id: failedID,
                body: StatusSnapshotRequestBody()
            )
        )
    }
    #expect(await router.state == .ready)
    #expect(observe.invalidationCount == 0)

    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(
            id: WireUUID(UUID()),
            body: StatusSnapshotRequestBody()
        )
    )
    #expect(await transport.capturedFrames().count == 1)
}

@Test func primaryRouterInvalidationSuppressesSuspendedReplyPublication()
    async throws
{
    let transport = RouterTestTransport()
    let router = try makeRouter(transport: transport)
    let publications = RouterPublicationRecorder()
    let receiver = SuspendedRouterTestReceiver(publications: publications)
    try await router.installReceiver(receiver, for: .observe)
    try await router.activate()
    let requestID = WireUUID(UUID())
    try await router.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(id: requestID, body: StatusSnapshotRequestBody())
    )
    let receiveTask = Task {
        try await router.receive(routerError(correlationID: requestID))
    }
    await receiver.waitUntilStarted()
    await router.invalidate()
    await receiver.finish()

    do {
        try await receiveTask.value
        Issue.record("Invalidated reply unexpectedly published")
    } catch let error as ClientPrimaryCommandRouterErrorV0 {
        #expect(error == .invalidated)
    }
    #expect(publications.count == 0)
    #expect(await receiver.invalidationCount == 1)
}

@Test func primaryRouterReplacementCannotResurrectOldLaneSender()
    async throws
{
    let oldTransport = RouterTestTransport()
    let oldRouter = try makeRouter(transport: oldTransport)
    let oldReceiver = RouterTestReceiver()
    try await oldRouter.installReceiver(oldReceiver, for: .observe)
    try await oldRouter.activate()
    let oldSender = oldRouter.sender(for: .observe)
    await oldRouter.invalidate()

    let newTransport = RouterTestTransport()
    let newRouter = try makeRouter(transport: newTransport)
    try await newRouter.installReceiver(RouterTestReceiver(), for: .observe)
    try await newRouter.activate()
    try await newRouter.sender(for: .observe).sendAuthenticatedCommand(
        routerRequest(
            id: WireUUID(UUID()),
            body: StatusSnapshotRequestBody()
        )
    )

    do {
        try await oldSender.sendAuthenticatedCommand(routerRequest(
            id: WireUUID(UUID()),
            body: StatusSnapshotRequestBody()
        ))
        Issue.record("Old connection sender unexpectedly resurrected")
    } catch let error as ClientPrimaryCommandRouterErrorV0 {
        #expect(error == .invalidState(.invalidated))
    }
    #expect(await oldTransport.capturedFrames().isEmpty)
    #expect(await newTransport.capturedFrames().count == 1)
    #expect(oldReceiver.invalidationCount == 1)
}
