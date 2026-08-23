#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionMacApp
import Foundation
import Testing

@available(macOS 26.0, *)
private struct ProductMenuPairingCommandHandlerV1:
    MacLocalXPCMenuPairingCommandHandlingV1
{
    func createPairingSession(
        _: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    func dismissPairingSession(
        _: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    func resolveLocalApproval(
        _: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }
}

@available(macOS 26.0, *)
private struct ProductInteractiveAdmissionHandlerV1:
    MacLocalXPCInteractiveAdmissionHandlingV1
{
    func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1,
        transportGeneration _: UInt64
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        try LocalInteractiveAdmissionPublishedReceiptV1(
            correlationID: publication.commandID,
            menuAppGeneration: publication.menuAppGeneration,
            revision: publication.revision,
            selectedDisplayID: publication.selectedDisplayID
        )
    }

    func invalidateInteractiveAdmission(
        transportGeneration _: UInt64
    ) async {}
}

private func eventuallyV1(
    _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<500 {
        if await predicate() { return true }
        await Task.yield()
    }
    return false
}

private func eventuallyTimedV1(
    _ predicate: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<200 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

private final class ProductAsyncGateV1: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var entered = false
    private var cancelled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func arm() {
        lock.withLock {
            precondition(!armed && continuation == nil)
            armed = true
            entered = false
            cancelled = false
        }
    }

    func waitIfArmed() async {
        let shouldWait = lock.withLock {
            guard armed else { return false }
            entered = true
            return true
        }
        guard shouldWait else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeImmediately = lock.withLock {
                    guard armed else { return true }
                    self.continuation = continuation
                    return false
                }
                if resumeImmediately { continuation.resume() }
            }
        } onCancel: {
            self.lock.withLock { self.cancelled = true }
        }
    }

    func release() {
        let continuation = lock.withLock {
            armed = false
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func snapshot() -> (entered: Bool, cancelled: Bool) {
        lock.withLock { (entered, cancelled) }
    }
}

private final class ProductSyncStartGateV1: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    private var cancelled = false

    func waitForRelease() {
        condition.lock()
        entered = true
        condition.broadcast()
        while !released {
            if Task.isCancelled { cancelled = true }
            _ = condition.wait(until: Date().addingTimeInterval(0.005))
        }
        if Task.isCancelled { cancelled = true }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> (entered: Bool, cancelled: Bool) {
        condition.lock()
        let result = (entered, cancelled)
        condition.unlock()
        return result
    }
}

private final class ProductFlagV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    func isSet() -> Bool { lock.withLock { value } }
}

private actor ProductLifecycleConnectionV1:
    MacLocalXPCMenuLifecycleConnectionV1
{
    private let readyDisposition:
        MacLifecycleProcessObservationDispositionV1
    private var readyCalls = 0
    private var invalidationCalls = 0

    init(
        readyDisposition: MacLifecycleProcessObservationDispositionV1 =
            .accepted
    ) {
        self.readyDisposition = readyDisposition
    }

    func publishReady() async -> MacLifecycleProcessObservationReceiptV1 {
        readyCalls += 1
        return MacLifecycleProcessObservationReceiptV1(
            token: nil,
            disposition: readyDisposition,
            transition: nil
        )
    }

    func invalidate() async -> MacLifecycleProcessObservationReceiptV1 {
        invalidationCalls += 1
        return MacLifecycleProcessObservationReceiptV1(
            token: nil,
            disposition: .accepted,
            transition: nil
        )
    }

    func counts() -> (ready: Int, invalidated: Int) {
        (readyCalls, invalidationCalls)
    }
}

private actor ProductLifecycleFactoryV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    private let connection: any MacLocalXPCMenuLifecycleConnectionV1

    init(connection: any MacLocalXPCMenuLifecycleConnectionV1) {
        self.connection = connection
    }

    func makeLocalXPCMenuLifecycleConnection(
        generation _: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        connection
    }
}

private struct ProductStatusReaderV1: MacLocalXPCStatusReadingV1 {
    func readStatus() async
        -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
    {
        .failure(.sourceUnavailable)
    }
}

@available(macOS 26.0, *)
private final class ProductAgentServerV1:
    MacLocalXPCAgentServerV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var handler: MacLocalXPCServerV1.EventHandler?
    private var starts = 0
    private var cancels = 0
    private var cancelledPeers: [UInt64] = []
    private var endpointRequests: [UInt64] = []
    private var presentationEndpoint:
        (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)?

    init(
        presentationEndpoint:
            (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)? = nil
    ) {
        self.presentationEndpoint = presentationEndpoint
    }

    func install(_ handler: @escaping MacLocalXPCServerV1.EventHandler) {
        lock.withLock { self.handler = handler }
    }

    func start() throws { lock.withLock { starts += 1 } }
    func cancel() { lock.withLock { cancels += 1 } }
    func cancelPeer(generation: UInt64) {
        lock.withLock { cancelledPeers.append(generation) }
    }

    func authenticatedMenuPresentationEndpoint(
        generation: UInt64
    ) async -> (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)? {
        lock.withLock {
            endpointRequests.append(generation)
            return presentationEndpoint
        }
    }

    func emit(_ event: MacLocalXPCServerEventV1) {
        lock.withLock { handler }?(event)
    }

    func snapshot() -> (
        starts: Int,
        cancels: Int,
        peers: [UInt64],
        endpointRequests: [UInt64]
    ) {
        lock.withLock {
            (starts, cancels, cancelledPeers, endpointRequests)
        }
    }
}

@available(macOS 26.0, *)
private actor ProductMenuPresentationEndpointV1:
    MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
{
    private var fence: MacLocalXPCMenuSurfaceTerminalFenceV1?
    private var invalidations = 0

    func installAuthenticatedMenuTerminalFence(
        _ fence: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) {
        self.fence = fence
    }

    func invalidateAuthenticatedMenuSurface() {
        invalidations += 1
    }

    func presentLocalPairingReview(_: LocalPairingReviewV0) async throws {}
    func withdrawLocalPairingReview(reviewID _: UUID) async {}
    func presentHostIdentityRecoveryReview(
        _: LocalHostIdentityRecoveryReviewV0
    ) async throws {}
    func presentHostIdentityRecoveryResume(
        _: LocalHostIdentityRecoveryCommandV0
    ) async throws {}
    func withdrawHostIdentityRecovery(reviewID _: UUID) async {}

    func invalidationCount() -> Int { invalidations }

    func requestTerminalFinish() async {
        await fence?.requestFinish()
    }
}

private actor ProductPresentedGenerationProbeV1 {
    private var generations: [UInt64] = []

    func record(_ generation: UInt64) { generations.append(generation) }
    func values() -> [UInt64] { generations }
}

@available(macOS 26.0, *)
private final class ProductBlockingAgentServerV1:
    MacLocalXPCAgentServerV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let gate: ProductSyncStartGateV1
    private var starts = 0
    private var cancels = 0
    private var active = false

    init(gate: ProductSyncStartGateV1) {
        self.gate = gate
    }

    func start() throws {
        lock.withLock { starts += 1 }
        gate.waitForRelease()
        lock.withLock { active = true }
    }

    func cancel() {
        lock.withLock {
            cancels += 1
            active = false
        }
    }

    func cancelPeer(generation _: UInt64) {}

    func snapshot() -> (starts: Int, cancels: Int, active: Bool) {
        lock.withLock { (starts, cancels, active) }
    }
}

@available(macOS 26.0, *)
private final class ProductAgentFactoryProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var profile: MacLocalXPCServerProfileV1?

    func record(_ profile: MacLocalXPCServerProfileV1) {
        lock.withLock { self.profile = profile }
    }

    func recordedProfile() -> MacLocalXPCServerProfileV1? {
        lock.withLock { profile }
    }
}

@Test
@available(macOS 26.0, *)
func agentProductBindsFullProfileReadinessAndShutdown() async throws {
    let connection = ProductLifecycleConnectionV1()
    let lifecycle = ProductLifecycleFactoryV1(connection: connection)
    let server = ProductAgentServerV1()
    let factory = ProductAgentFactoryProbeV1()
    let product = MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: lifecycle,
        statusReader: ProductStatusReaderV1(),
        serverFactory: { profile, _, handler in
            factory.record(profile)
            server.install(handler)
            return server
        }
    )

    #expect(
        factory.recordedProfile() == .menuLifecycleReadinessAndStatus
    )
    try await product.start()
    server.emit(.authenticatedMenu(generation: 31))
    server.emit(.menuReady(generation: 31))
    #expect(await eventuallyV1 { await connection.counts().ready == 1 })

    await product.finish()
    #expect(await connection.counts().invalidated == 1)
    #expect(server.snapshot().starts == 1)
    #expect(server.snapshot().cancels >= 1)
}

@Test
@available(macOS 26.0, *)
func agentProductFailureCancelsOnlyCurrentTransportGeneration() async {
    let connection = ProductLifecycleConnectionV1(
        readyDisposition: .notEligible
    )
    let server = ProductAgentServerV1()
    let product = MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: connection
        ),
        statusReader: ProductStatusReaderV1(),
        serverFactory: { _, _, handler in
            server.install(handler)
            return server
        }
    )

    try? await product.start()
    server.emit(.authenticatedMenu(generation: 8))
    server.emit(.menuReady(generation: 8))
    #expect(await eventuallyV1 { server.snapshot().peers == [8] })
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func agentPresentationProductBindsOnlyAfterAcceptedReadiness() async throws {
    let endpoint = ProductMenuPresentationEndpointV1()
    let server = ProductAgentServerV1(presentationEndpoint: endpoint)
    let factory = ProductAgentFactoryProbeV1()
    let generations = ProductPresentedGenerationProbeV1()
    let invalidatedGenerations = ProductPresentedGenerationProbeV1()
    let connection = ProductLifecycleConnectionV1()
    let product = MacLocalXPCAgentProductV1.composeWithMenuPresentation(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: connection
        ),
        statusReader: ProductStatusReaderV1(),
        menuPairingCommandHandler: ProductMenuPairingCommandHandlerV1(),
        interactiveAdmissionHandler:
            ProductInteractiveAdmissionHandlerV1(),
        onSurfaces: { await generations.record($0.generation) },
        onSurfaceInvalidated: {
            await invalidatedGenerations.record($0)
        },
        serverFactory: { profile, _, _, _, _, handler in
            factory.record(profile)
            server.install(handler)
            return server
        }
    )

    #expect(
        factory.recordedProfile()
            == .menuLifecycleReadinessStatusAndPresentation
    )
    try await product.start()
    server.emit(.authenticatedMenu(generation: 71))
    for _ in 0..<50 { await Task.yield() }
    #expect(server.snapshot().endpointRequests.isEmpty)
    #expect(await connection.counts().ready == 0)
    server.emit(.menuReady(generation: 71))
    #expect(await eventuallyV1 { await generations.values() == [71] })
    #expect(server.snapshot().endpointRequests == [71])

    await endpoint.requestTerminalFinish()
    #expect(await eventuallyV1 { await endpoint.invalidationCount() == 1 })
    #expect(await invalidatedGenerations.values() == [71])
    #expect(server.snapshot().peers == [71])

    // The transport's later invalidation is a replay of the same exact loss.
    server.emit(.invalidatedMenu(generation: 71))
    for _ in 0..<50 { await Task.yield() }
    #expect(await invalidatedGenerations.values() == [71])
    #expect(server.snapshot().peers == [71])
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func authenticatedReplacementRevokesReadyPresentationBeforeNewReadiness()
    async throws
{
    let endpoint = ProductMenuPresentationEndpointV1()
    let server = ProductAgentServerV1(presentationEndpoint: endpoint)
    let generations = ProductPresentedGenerationProbeV1()
    let invalidatedGenerations = ProductPresentedGenerationProbeV1()
    let product = MacLocalXPCAgentProductV1.composeWithMenuPresentation(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: ProductLifecycleConnectionV1()
        ),
        statusReader: ProductStatusReaderV1(),
        menuPairingCommandHandler: ProductMenuPairingCommandHandlerV1(),
        interactiveAdmissionHandler:
            ProductInteractiveAdmissionHandlerV1(),
        onSurfaces: { await generations.record($0.generation) },
        onSurfaceInvalidated: {
            await invalidatedGenerations.record($0)
        },
        serverFactory: { _, _, _, _, _, handler in
            server.install(handler)
            return server
        }
    )

    try await product.start()
    server.emit(.authenticatedMenu(generation: 81))
    server.emit(.menuReady(generation: 81))
    #expect(await eventuallyV1 { await generations.values() == [81] })

    server.emit(.authenticatedMenu(generation: 82))
    #expect(await eventuallyV1 {
        await invalidatedGenerations.values() == [81]
    })
    #expect(await endpoint.invalidationCount() == 1)
    #expect(server.snapshot().endpointRequests == [81])
    #expect(server.snapshot().peers.isEmpty)

    // A later stale invalidation for the replaced generation is idempotent.
    server.emit(.invalidatedMenu(generation: 81))
    for _ in 0..<50 { await Task.yield() }
    #expect(await invalidatedGenerations.values() == [81])
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func agentPresentationProductFailsCurrentPeerWhenEndpointIsAbsent() async {
    let server = ProductAgentServerV1()
    let product = MacLocalXPCAgentProductV1.composeWithMenuPresentation(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: ProductLifecycleConnectionV1()
        ),
        statusReader: ProductStatusReaderV1(),
        menuPairingCommandHandler: ProductMenuPairingCommandHandlerV1(),
        interactiveAdmissionHandler:
            ProductInteractiveAdmissionHandlerV1(),
        onSurfaces: { _ in },
        serverFactory: { _, _, _, _, _, handler in
            server.install(handler)
            return server
        }
    )

    try? await product.start()
    server.emit(.authenticatedMenu(generation: 72))
    server.emit(.menuReady(generation: 72))
    #expect(await eventuallyV1 { server.snapshot().peers == [72] })
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func agentProductCannotStartAfterTerminalFinish() async {
    let server = ProductAgentServerV1()
    let product = MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: ProductLifecycleConnectionV1()
        ),
        statusReader: ProductStatusReaderV1(),
        serverFactory: { _, _, handler in
            server.install(handler)
            return server
        }
    )

    await product.finish()
    await #expect(throws: MacLocalXPCConstructionErrorV1.alreadyStarted) {
        try await product.start()
    }
    #expect(server.snapshot().starts == 0)
}

@Test
@available(macOS 26.0, *)
func agentFinishWaitsForAndCancelsAnAdmittedStart() async {
    let gate = ProductSyncStartGateV1()
    let server = ProductBlockingAgentServerV1(gate: gate)
    let product = MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: ProductLifecycleFactoryV1(
            connection: ProductLifecycleConnectionV1()
        ),
        statusReader: ProductStatusReaderV1(),
        serverFactory: { _, _, _ in server }
    )

    let startTask = Task { try await product.start() }
    #expect(await eventuallyV1 { gate.snapshot().entered })
    let finishTask = Task { await product.finish() }
    #expect(
        await eventuallyTimedV1 { gate.snapshot().cancelled }
    )
    gate.release()

    await finishTask.value
    await #expect(throws: MacLocalXPCConstructionErrorV1.alreadyStarted) {
        try await startTask.value
    }
    let snapshot = server.snapshot()
    #expect(snapshot.starts == 1)
    #expect(snapshot.cancels >= 1)
    #expect(!snapshot.active)
}

@available(macOS 26.0, *)
private final class ProductDashboardClientV1:
    MacLocalXPCDashboardClientV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let handler: MacLocalXPCClientV1.EventHandler
    private let startError: Bool
    private let readyGate: ProductSyncStartGateV1?
    private let finishGate: ProductAsyncGateV1?
    private var starts = 0
    private var readyRequests = 0
    private var statusRequests = 0
    private var admissionPublications:
        [LocalInteractiveAdmissionPublicationV1] = []
    private var cancels = 0

    init(
        startError: Bool = false,
        readyGate: ProductSyncStartGateV1? = nil,
        finishGate: ProductAsyncGateV1? = nil,
        handler: @escaping MacLocalXPCClientV1.EventHandler
    ) {
        self.startError = startError
        self.readyGate = readyGate
        self.finishGate = finishGate
        self.handler = handler
    }

    func start() throws {
        lock.withLock { starts += 1 }
        if startError { throw StartError.injected }
    }

    func publishMenuReady() {
        lock.withLock { readyRequests += 1 }
        readyGate?.waitForRelease()
    }

    func readAgentStatus() {
        lock.withLock { statusRequests += 1 }
    }

    func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        lock.withLock { admissionPublications.append(publication) }
        return try LocalInteractiveAdmissionPublishedReceiptV1(
            correlationID: publication.commandID,
            menuAppGeneration: publication.menuAppGeneration,
            revision: publication.revision,
            selectedDisplayID: publication.selectedDisplayID
        )
    }

    func cancel() { lock.withLock { cancels += 1 } }
    func finishMenuPresentationReceiver() async {
        cancel()
        await finishGate?.waitIfArmed()
    }
    func emit(_ event: MacLocalXPCClientEventV1) { handler(event) }

    func snapshot() -> (
        starts: Int,
        ready: Int,
        status: Int,
        admissions: [LocalInteractiveAdmissionPublicationV1],
        cancels: Int
    ) {
        lock.withLock {
            (
                starts,
                readyRequests,
                statusRequests,
                admissionPublications,
                cancels
            )
        }
    }

    enum StartError: Error { case injected }
}

@available(macOS 26.0, *)
private final class ProductDashboardClientBoxV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProductDashboardClientV1?

    func install(_ value: ProductDashboardClientV1) {
        lock.withLock { self.value = value }
    }

    func client() -> ProductDashboardClientV1? {
        lock.withLock { value }
    }
}

private func productDashboardStatusV1(
    sequence: UInt64,
    generatedAt: Int64
) throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: .active,
        agentProcess: .ready,
        menuAppProcess: .ready,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 1,
        activeRemoteSessionCount: 0,
        providerCount: 1,
        warningCodes: [],
        diagnosticSequence: sequence,
        generatedAtUnixMilliseconds: generatedAt
    )
}

@Test
@available(macOS 26.0, *)
func dashboardProductPublishesTypedStatusAndRecoversUnavailable() async throws {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())

    client.emit(.authenticatedAgent)
    #expect(await eventuallyV1 { client.snapshot().ready == 1 })
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 { client.snapshot().status == 1 })
    #expect(await product.retryStatus() == .notCompleted)
    #expect(client.snapshot().status == 1)
    client.emit(.agentStatusUnavailable(generation: 12))
    #expect(await eventuallyV1 { await owner.snapshot() == .unavailable })
    #expect(await product.retryStatus() == .completed)
    #expect(await owner.snapshot() == .loading)
    #expect(client.snapshot().status == 2)

    let recovered = try productDashboardStatusV1(
        sequence: 2,
        generatedAt: 1_724_000_000_001
    )
    client.emit(.agentStatus(generation: 12, snapshot: recovered))
    #expect(
        await eventuallyV1 { await owner.snapshot() == .status(recovered) }
    )

    client.emit(.invalidated)
    #expect(await eventuallyV1 { await owner.snapshot() == .unavailable })
    #expect(await product.retryStatus() == .notCompleted)
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func presentationDashboardPublishesInitialAdmissionBeforeStatus() async throws {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    let selectedDisplayID = UUID()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        publishesInteractiveAdmission: true,
        initialSelectedDisplayID: selectedDisplayID,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())

    client.emit(.authenticatedAgent)
    #expect(await eventuallyV1 { client.snapshot().ready == 1 })
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 {
        client.snapshot().admissions.count == 1
            && client.snapshot().status == 1
    })
    let publication = try #require(client.snapshot().admissions.first)
    #expect(publication.revision == 1)
    #expect(publication.selectedDisplayID == selectedDisplayID)

    await product.finish()
}

@Test
@available(macOS 26.0, *)
func dashboardProductFailsClosedOnOrderOrGenerationReplacement() async throws {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())
    client.emit(.menuReadyAcknowledged)

    #expect(await eventuallyV1 { client.snapshot().cancels >= 1 })
    #expect(await owner.snapshot() == .unavailable)
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func dashboardProductRejectsStatusFromAReplacementGeneration() async throws {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())
    client.emit(.authenticatedAgent)
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 { client.snapshot().status == 1 })

    client.emit(.agentStatusUnavailable(generation: 20))
    #expect(await eventuallyV1 { await owner.snapshot() == .unavailable })
    #expect(await product.retryStatus() == .completed)
    #expect(client.snapshot().status == 2)

    let replacement = try productDashboardStatusV1(
        sequence: 2,
        generatedAt: 1_724_000_000_001
    )
    client.emit(
        .agentStatus(generation: 21, snapshot: replacement)
    )
    #expect(await eventuallyV1 { client.snapshot().cancels >= 1 })
    #expect(await owner.snapshot() == .unavailable)
    #expect(await product.retryStatus() == .notCompleted)
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func dashboardProductStartFailureRetiresPreparedDashboardGeneration() async {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            ProductDashboardClientV1(
                startError: true,
                handler: handler
            )
        }
    )

    await #expect(throws: ProductDashboardClientV1.StartError.injected) {
        try await product.start()
    }
    #expect(await owner.snapshot() == .unavailable)
    #expect(await product.retryStatus() == .notCompleted)
    await #expect(throws: MacLocalXPCConstructionErrorV1.alreadyStarted) {
        try await product.start()
    }
}

@Test
@available(macOS 26.0, *)
func dashboardProductCannotStartAfterTerminalFinish() async {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { ProductDashboardClientV1(handler: $0) }
    )

    await product.finish()
    await #expect(throws: MacLocalXPCConstructionErrorV1.alreadyStarted) {
        try await product.start()
    }
    #expect(await owner.snapshot() == .loading)
}

@Test
@available(macOS 26.0, *)
func dashboardFinishFencesASuspendedStartBeforeClientActivation() async {
    let gate = ProductAsyncGateV1()
    gate.arm()
    let owner = MacAgentDashboardApplicationOwnerV0(
        stateChanged: { _ in await gate.waitIfArmed() }
    )
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )

    let startTask = Task { try await product.start() }
    #expect(await eventuallyV1 { gate.snapshot().entered })
    let finishTask = Task { await product.finish() }
    #expect(await eventuallyV1 { gate.snapshot().cancelled })
    #expect(box.client()?.snapshot().starts == 0)
    gate.release()

    await finishTask.value
    await #expect(throws: MacLocalXPCConstructionErrorV1.alreadyStarted) {
        try await startTask.value
    }
    #expect(box.client()?.snapshot().starts == 0)
    #expect(await owner.snapshot() == .unavailable)
}

@Test
@available(macOS 26.0, *)
func dashboardRetryReservesSingleFlightBeforeOwnerSuspension() async throws {
    let gate = ProductAsyncGateV1()
    let owner = MacAgentDashboardApplicationOwnerV0(
        stateChanged: { _ in await gate.waitIfArmed() }
    )
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())
    client.emit(.authenticatedAgent)
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 { client.snapshot().status == 1 })
    client.emit(.agentStatusUnavailable(generation: 41))
    #expect(await eventuallyV1 { await owner.snapshot() == .unavailable })

    gate.arm()
    let firstRetry = Task { await product.retryStatus() }
    #expect(await eventuallyV1 { gate.snapshot().entered })
    #expect(await product.retryStatus() == .notCompleted)
    #expect(client.snapshot().status == 1)
    gate.release()

    #expect(await firstRetry.value == .completed)
    #expect(client.snapshot().status == 2)
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func repeatedDashboardFinishAwaitsTheSameCleanupBarrier() async throws {
    let gate = ProductAsyncGateV1()
    let owner = MacAgentDashboardApplicationOwnerV0(
        stateChanged: { _ in await gate.waitIfArmed() }
    )
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { ProductDashboardClientV1(handler: $0) }
    )
    try await product.start()

    gate.arm()
    let firstFinish = Task { await product.finish() }
    #expect(await eventuallyV1 { gate.snapshot().entered })
    let secondCompleted = ProductFlagV1()
    let secondFinish = Task {
        await product.finish()
        secondCompleted.set()
    }
    for _ in 0..<50 { await Task.yield() }
    #expect(!secondCompleted.isSet())
    gate.release()

    await firstFinish.value
    await secondFinish.value
    #expect(secondCompleted.isSet())
    #expect(await owner.snapshot() == .unavailable)
}

@Test
@available(macOS 26.0, *)
func dashboardFinishAwaitsMenuReceiverRetirement() async throws {
    let receiverGate = ProductAsyncGateV1()
    receiverGate.arm()
    let completed = ProductFlagV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: MacAgentDashboardApplicationOwnerV0(),
        clientFactory: {
            ProductDashboardClientV1(
                finishGate: receiverGate,
                handler: $0
            )
        }
    )
    try await product.start()

    let finish = Task {
        await product.finish()
        completed.set()
    }
    #expect(await eventuallyV1 { receiverGate.snapshot().entered })
    #expect(!completed.isSet())
    receiverGate.release()
    await finish.value
    #expect(completed.isSet())
}

@Test
@available(macOS 26.0, *)
func dashboardProductDeinitRetiresAnExternallyRetainedOwner() async throws {
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    var product: MacLocalXPCDashboardProductV1? =
        MacLocalXPCDashboardProductV1(
            owner: owner,
            clientFactory: { handler in
                let client = ProductDashboardClientV1(handler: handler)
                box.install(client)
                return client
            }
        )
    try await product?.start()
    let client = try #require(box.client())
    client.emit(.authenticatedAgent)
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 { client.snapshot().status == 1 })
    let status = try productDashboardStatusV1(
        sequence: 1,
        generatedAt: 1_724_000_000_000
    )
    client.emit(.agentStatus(generation: 52, snapshot: status))
    #expect(await eventuallyV1 { await owner.snapshot() == .status(status) })

    product = nil

    #expect(
        await eventuallyV1 { await owner.snapshot() == .unavailable }
    )
    #expect(client.snapshot().cancels >= 1)
}

@Test
@available(macOS 26.0, *)
func dashboardOverflowSynchronouslyFencesAdmissionAndFailsClosed() async throws {
    let readyGate = ProductSyncStartGateV1()
    let owner = MacAgentDashboardApplicationOwnerV0()
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        bufferCapacity: 1,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(
                readyGate: readyGate,
                handler: handler
            )
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())
    client.emit(.authenticatedAgent)
    #expect(await eventuallyV1 { readyGate.snapshot().entered })

    client.emit(.menuReadyAcknowledged)
    client.emit(.invalidated)
    client.emit(.menuReadyAcknowledged)
    #expect(
        await eventuallyTimedV1 { readyGate.snapshot().cancelled }
    )
    readyGate.release()
    await product.finish()

    #expect(client.snapshot().status == 0)
    #expect(client.snapshot().cancels >= 1)
    #expect(await owner.snapshot() == .unavailable)
}

@Test
@available(macOS 26.0, *)
func dashboardInvalidationRetiresRetryBeforeOwnerSuspension() async throws {
    let gate = ProductAsyncGateV1()
    let owner = MacAgentDashboardApplicationOwnerV0(
        stateChanged: { _ in await gate.waitIfArmed() }
    )
    let box = ProductDashboardClientBoxV1()
    let product = MacLocalXPCDashboardProductV1(
        owner: owner,
        clientFactory: { handler in
            let client = ProductDashboardClientV1(handler: handler)
            box.install(client)
            return client
        }
    )
    try await product.start()
    let client = try #require(box.client())
    client.emit(.authenticatedAgent)
    client.emit(.menuReadyAcknowledged)
    #expect(await eventuallyV1 { client.snapshot().status == 1 })
    client.emit(.agentStatusUnavailable(generation: 61))
    #expect(await eventuallyV1 { await owner.snapshot() == .unavailable })

    gate.arm()
    client.emit(.invalidated)
    #expect(await eventuallyV1 { gate.snapshot().entered })
    #expect(await product.retryStatus() == .notCompleted)
    gate.release()
    await product.finish()

    #expect(await owner.snapshot() == .unavailable)
    #expect(client.snapshot().status == 1)
}
#endif
