@testable import CompanionAgentPlatform
import CompanionLocalXPCPlatform
import Foundation
import Testing

private actor LocalXPCLifecycleConnectionV1:
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

private actor LocalXPCLifecycleFactoryV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    private var connections: [
        any MacLocalXPCMenuLifecycleConnectionV1
    ]
    private var generations: [UUID] = []

    init(_ connections: [any MacLocalXPCMenuLifecycleConnectionV1]) {
        self.connections = connections
    }

    func makeLocalXPCMenuLifecycleConnection(
        generation: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        generations.append(generation)
        guard !connections.isEmpty else { throw FactoryError.empty }
        return connections.removeFirst()
    }

    func recordedGenerations() -> [UUID] { generations }

    enum FactoryError: Error { case empty }
}

private actor SuspendedLocalXPCLifecycleFactoryV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    private let connection: any MacLocalXPCMenuLifecycleConnectionV1
    private var continuation: CheckedContinuation<Void, Never>?

    init(connection: any MacLocalXPCMenuLifecycleConnectionV1) {
        self.connection = connection
    }

    func makeLocalXPCMenuLifecycleConnection(
        generation _: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return connection
    }

    func waitUntilSuspended() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private actor LocalXPCFailureRecorderV1 {
    private var generations: [UInt64] = []

    func record(_ generation: UInt64) {
        generations.append(generation)
    }

    func values() -> [UInt64] { generations }
}

private actor SuspendedReadyLifecycleConnectionV1:
    MacLocalXPCMenuLifecycleConnectionV1
{
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var readyCalls = 0
    private var invalidationCalls = 0

    func publishReady() async -> MacLifecycleProcessObservationReceiptV1 {
        readyCalls += 1
        await withCheckedContinuation { continuation in
            readyContinuation = continuation
        }
        return MacLifecycleProcessObservationReceiptV1(
            token: nil,
            disposition: .accepted,
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

    func waitUntilReadyIsSuspended() async {
        while readyContinuation == nil {
            await Task.yield()
        }
    }

    func resumeReady() {
        let continuation = readyContinuation
        readyContinuation = nil
        continuation?.resume()
    }

    func counts() -> (ready: Int, invalidated: Int) {
        (readyCalls, invalidationCalls)
    }
}

private actor LocalXPCShutdownRecorderV1 {
    private var callCount = 0

    func record() {
        callCount += 1
    }

    func waitForCall() async {
        while callCount == 0 {
            await Task.yield()
        }
    }

    func count() -> Int { callCount }
}

private let localXPCGenerationUUIDV1 = UUID(
    uuidString: "12345678-1234-4234-8234-1234567890ab"
)!

@Test
func authenticatedHelloCreatesObservationButDoesNotPublishReadiness() async {
    let connection = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(
        factory: factory,
        generationIDSource: { _ in localXPCGenerationUUIDV1 }
    )

    let result = await binding.receive(
        .authenticatedMenu(generation: 7)
    )

    #expect(result == .authenticatedWithoutReadiness(generation: 7))
    #expect(await connection.counts().ready == 0)
    #expect(await factory.recordedGenerations() == [
        localXPCGenerationUUIDV1,
    ])
}

@Test
func exactReadyAndInvalidationReachOnlyCurrentGeneration() async {
    let connection = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 4))
    let stale = await binding.receive(.menuReady(generation: 3))
    let ready = await binding.receive(.menuReady(generation: 4))
    let duplicate = await binding.receive(.menuReady(generation: 4))
    let invalidated = await binding.receive(
        .invalidatedMenu(generation: 4)
    )

    #expect(stale == .ignoredStale(generation: 3))
    #expect(ready == .readinessPublished(generation: 4))
    #expect(duplicate == .ignoredStale(generation: 4))
    #expect(invalidated == .invalidated(generation: 4))
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 1)
}

@Test
func replacementFencesLateEventsFromOldTransportGeneration() async {
    let old = LocalXPCLifecycleConnectionV1()
    let replacement = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([old, replacement])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 1))
    _ = await binding.receive(.menuReady(generation: 1))
    _ = await binding.receive(.authenticatedMenu(generation: 2))
    let staleInvalidation = await binding.receive(
        .invalidatedMenu(generation: 1)
    )
    let replacementReady = await binding.receive(
        .menuReady(generation: 2)
    )

    #expect(staleInvalidation == .ignoredStale(generation: 1))
    #expect(replacementReady == .readinessPublished(generation: 2))
    #expect(await old.counts().ready == 1)
    #expect(await replacement.counts().ready == 1)
}

@Test
func rejectedLifecycleReceiptInvalidatesAndClosesBinding() async {
    let connection = LocalXPCLifecycleConnectionV1(
        readyDisposition: .notEligible
    )
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 8))
    let rejected = await binding.receive(.menuReady(generation: 8))
    let late = await binding.receive(.invalidatedMenu(generation: 8))

    #expect(rejected == .failedClosed(generation: 8))
    #expect(late == .ignoredStale(generation: 8))
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 1)
}

@Test
func failedReplacementFactoryInvalidatesPriorLifecycleConnection() async {
    let old = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([old])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 10))
    _ = await binding.receive(.menuReady(generation: 10))
    let failedReplacement = await binding.receive(
        .authenticatedMenu(generation: 11)
    )
    let lateOldReady = await binding.receive(.menuReady(generation: 10))

    #expect(failedReplacement == .failedClosed(generation: 11))
    #expect(lateOldReady == .ignoredStale(generation: 10))
    let counts = await old.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 1)
}

@Test
@available(macOS 26.0, *)
func eventPumpPreservesAuthenticationReadyInvalidationOrder() async {
    let connection = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        onFailedClosed: { _ in },
        onShutdown: {}
    )

    pump.consume(.authenticatedMenu(generation: 9))
    pump.consume(.menuReady(generation: 9))
    pump.consume(.invalidatedMenu(generation: 9))
    while (await connection.counts()).invalidated == 0 {
        await Task.yield()
    }
    await pump.finish()

    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 1)
}

@Test
@available(macOS 26.0, *)
func eventPumpEscalatesFailedClosedGenerationToTransportOwner() async {
    let connection = LocalXPCLifecycleConnectionV1(
        readyDisposition: .notEligible
    )
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let failures = LocalXPCFailureRecorderV1()
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        onFailedClosed: { generation in
            await failures.record(generation)
        },
        onShutdown: {}
    )

    pump.consume(.authenticatedMenu(generation: 12))
    pump.consume(.menuReady(generation: 12))
    while (await failures.values()).isEmpty {
        await Task.yield()
    }
    await pump.finish()

    #expect(await failures.values() == [12])
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 1)
}

@Test
func suspendedReadinessCannotResurrectInvalidatedGeneration() async {
    let connection = SuspendedReadyLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 20))
    let readyTask = Task {
        await binding.receive(.menuReady(generation: 20))
    }
    await connection.waitUntilReadyIsSuspended()

    let invalidated = await binding.receive(
        .invalidatedMenu(generation: 20)
    )
    await connection.resumeReady()
    let lateReady = await readyTask.value

    #expect(invalidated == .invalidated(generation: 20))
    #expect(lateReady == .ignoredStale(generation: 20))
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 2)
}

@Test
func suspendedReadinessCannotOverwriteReplacementGeneration() async {
    let old = SuspendedReadyLifecycleConnectionV1()
    let replacement = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([old, replacement])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 30))
    let oldReadyTask = Task {
        await binding.receive(.menuReady(generation: 30))
    }
    await old.waitUntilReadyIsSuspended()

    let replaced = await binding.receive(
        .authenticatedMenu(generation: 31)
    )
    await old.resumeReady()
    let lateOldReady = await oldReadyTask.value
    let replacementReady = await binding.receive(
        .menuReady(generation: 31)
    )

    #expect(
        replaced == .authenticatedWithoutReadiness(generation: 31)
    )
    #expect(lateOldReady == .ignoredStale(generation: 30))
    #expect(replacementReady == .readinessPublished(generation: 31))
    #expect(await old.counts().invalidated == 1)
    #expect(await replacement.counts().ready == 1)
}

@Test
@available(macOS 26.0, *)
func boundedEventPumpOverflowFailsTransportAndLifecycleClosed() async {
    let connection = SuspendedReadyLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let shutdowns = LocalXPCShutdownRecorderV1()
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        bufferCapacity: 1,
        onFailedClosed: { _ in },
        onShutdown: {
            await shutdowns.record()
        }
    )

    pump.consume(.authenticatedMenu(generation: 40))
    while !(await binding.isCurrent(generation: 40)) {
        await Task.yield()
    }
    pump.consume(.menuReady(generation: 40))
    await connection.waitUntilReadyIsSuspended()
    pump.consume(.invalidatedMenu(generation: 40))
    pump.consume(.authenticatedMenu(generation: 41))

    await shutdowns.waitForCall()
    await connection.resumeReady()
    await pump.finish()

    #expect(await shutdowns.count() == 1)
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated >= 1)
}

@Test
func invalidationFencesSuspendedAuthenticationFactory() async {
    let connection = LocalXPCLifecycleConnectionV1()
    let factory = SuspendedLocalXPCLifecycleFactoryV1(
        connection: connection
    )
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let authenticationTask = Task {
        await binding.receive(.authenticatedMenu(generation: 45))
    }
    await factory.waitUntilSuspended()

    let invalidated = await binding.receive(
        .invalidatedMenu(generation: 45)
    )
    await factory.resume()
    let lateAuthentication = await authenticationTask.value

    #expect(invalidated == .invalidated(generation: 45))
    #expect(lateAuthentication == .ignoredStale(generation: 45))
    #expect(await connection.counts().invalidated == 1)
    #expect(!(await binding.isCurrent(generation: 45)))
}

@Test
@available(macOS 26.0, *)
func finishingEventPumpInvalidatesResidualAuthorityAndRejectsLaterEvents()
    async
{
    let connection = LocalXPCLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let shutdowns = LocalXPCShutdownRecorderV1()
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        onFailedClosed: { _ in },
        onShutdown: {
            await shutdowns.record()
        }
    )

    pump.consume(.authenticatedMenu(generation: 50))
    while !(await binding.isCurrent(generation: 50)) {
        await Task.yield()
    }
    await pump.finish()
    pump.consume(.menuReady(generation: 50))

    #expect(await shutdowns.count() == 1)
    let counts = await connection.counts()
    #expect(counts.ready == 0)
    #expect(counts.invalidated == 1)
}
private actor ReplacementSuspendingLocalXPCLifecycleFactoryV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    private let first: any MacLocalXPCMenuLifecycleConnectionV1
    private let replacement: any MacLocalXPCMenuLifecycleConnectionV1
    private var calls = 0
    private var replacementContinuation: CheckedContinuation<Void, Never>?

    init(
        first: any MacLocalXPCMenuLifecycleConnectionV1,
        replacement: any MacLocalXPCMenuLifecycleConnectionV1
    ) {
        self.first = first
        self.replacement = replacement
    }

    func makeLocalXPCMenuLifecycleConnection(
        generation _: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        calls += 1
        if calls == 1 {
            return first
        }
        await withCheckedContinuation { continuation in
            replacementContinuation = continuation
        }
        return replacement
    }

    func waitUntilReplacementSuspended() async {
        while replacementContinuation == nil {
            await Task.yield()
        }
    }

    func resumeReplacement() {
        let continuation = replacementContinuation
        replacementContinuation = nil
        continuation?.resume()
    }
}

@Test
func staleOldInvalidationDoesNotFencePendingReplacementAuthentication()
    async
{
    let old = LocalXPCLifecycleConnectionV1()
    let replacement = LocalXPCLifecycleConnectionV1()
    let factory = ReplacementSuspendingLocalXPCLifecycleFactoryV1(
        first: old,
        replacement: replacement
    )
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)

    _ = await binding.receive(.authenticatedMenu(generation: 60))
    let replacementTask = Task {
        await binding.receive(.authenticatedMenu(generation: 61))
    }
    await factory.waitUntilReplacementSuspended()

    let oldInvalidation = await binding.receive(
        .invalidatedMenu(generation: 60)
    )
    await factory.resumeReplacement()
    let replacementAuthentication = await replacementTask.value

    #expect(oldInvalidation == .invalidated(generation: 60))
    #expect(
        replacementAuthentication
            == .authenticatedWithoutReadiness(generation: 61)
    )
    #expect(await old.counts().invalidated == 1)
    #expect(await binding.isCurrent(generation: 61))
}

@Test
@available(macOS 26.0, *)
func finishingPumpFencesSuspendedReadinessBeforeTransportShutdown() async {
    let connection = SuspendedReadyLifecycleConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let shutdowns = LocalXPCShutdownRecorderV1()
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        onFailedClosed: { _ in },
        onShutdown: {
            await shutdowns.record()
        }
    )

    pump.consume(.authenticatedMenu(generation: 62))
    while !(await binding.isCurrent(generation: 62)) {
        await Task.yield()
    }
    pump.consume(.menuReady(generation: 62))
    await connection.waitUntilReadyIsSuspended()

    let finishTask = Task {
        await pump.finish()
    }
    await shutdowns.waitForCall()
    await connection.resumeReady()
    await finishTask.value

    #expect(await shutdowns.count() == 1)
    #expect(!(await binding.isCurrent(generation: 62)))
    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 2)
}

private actor OperationSerializedSuspendedReadyConnectionV1:
    MacLocalXPCMenuLifecycleConnectionV1
{
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var invalidationWaiters: [CheckedContinuation<Void, Never>] = []
    private var operationLocked = false
    private var readyCalls = 0
    private var invalidationCalls = 0

    func publishReady() async -> MacLifecycleProcessObservationReceiptV1 {
        operationLocked = true
        readyCalls += 1
        await withCheckedContinuation { continuation in
            readyContinuation = continuation
        }
        operationLocked = false
        let waiters = invalidationWaiters
        invalidationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return MacLifecycleProcessObservationReceiptV1(
            token: nil,
            disposition: .accepted,
            transition: nil
        )
    }

    func invalidate() async -> MacLifecycleProcessObservationReceiptV1 {
        if operationLocked {
            await withCheckedContinuation { continuation in
                invalidationWaiters.append(continuation)
            }
        }
        invalidationCalls += 1
        return MacLifecycleProcessObservationReceiptV1(
            token: nil,
            disposition: .accepted,
            transition: nil
        )
    }

    func waitUntilReadyIsSuspended() async {
        while readyContinuation == nil {
            await Task.yield()
        }
    }

    func resumeReady() {
        let continuation = readyContinuation
        readyContinuation = nil
        continuation?.resume()
    }

    func counts() -> (ready: Int, invalidated: Int) {
        (readyCalls, invalidationCalls)
    }
}

@Test
@available(macOS 26.0, *)
func pumpShutdownDoesNotWaitBehindSerializedLifecycleRetirement() async {
    let connection = OperationSerializedSuspendedReadyConnectionV1()
    let factory = LocalXPCLifecycleFactoryV1([connection])
    let binding = MacLocalXPCLifecycleBindingV1(factory: factory)
    let shutdowns = LocalXPCShutdownRecorderV1()
    let pump = MacLocalXPCLifecycleEventPumpV1(
        binding: binding,
        onFailedClosed: { _ in },
        onShutdown: {
            await shutdowns.record()
        }
    )

    pump.consume(.authenticatedMenu(generation: 63))
    while !(await binding.isCurrent(generation: 63)) {
        await Task.yield()
    }
    pump.consume(.menuReady(generation: 63))
    await connection.waitUntilReadyIsSuspended()

    let finishTask = Task {
        await pump.finish()
    }
    await shutdowns.waitForCall()

    #expect(!(await binding.isCurrent(generation: 63)))
    #expect(await shutdowns.count() == 1)
    await connection.resumeReady()
    await finishTask.value

    let counts = await connection.counts()
    #expect(counts.ready == 1)
    #expect(counts.invalidated == 2)
}
