#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionMacApp
import Foundation
import Testing

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

    func install(_ handler: @escaping MacLocalXPCServerV1.EventHandler) {
        lock.withLock { self.handler = handler }
    }

    func start() throws { lock.withLock { starts += 1 } }
    func cancel() { lock.withLock { cancels += 1 } }
    func cancelPeer(generation: UInt64) {
        lock.withLock { cancelledPeers.append(generation) }
    }

    func emit(_ event: MacLocalXPCServerEventV1) {
        lock.withLock { handler }?(event)
    }

    func snapshot() -> (starts: Int, cancels: Int, peers: [UInt64]) {
        lock.withLock { (starts, cancels, cancelledPeers) }
    }
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
    private var starts = 0
    private var readyRequests = 0
    private var statusRequests = 0
    private var cancels = 0

    init(
        startError: Bool = false,
        readyGate: ProductSyncStartGateV1? = nil,
        handler: @escaping MacLocalXPCClientV1.EventHandler
    ) {
        self.startError = startError
        self.readyGate = readyGate
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

    func cancel() { lock.withLock { cancels += 1 } }
    func emit(_ event: MacLocalXPCClientEventV1) { handler(event) }

    func snapshot() -> (starts: Int, ready: Int, status: Int, cancels: Int) {
        lock.withLock { (starts, readyRequests, statusRequests, cancels) }
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
