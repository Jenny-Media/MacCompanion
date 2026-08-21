#if canImport(Network)
@testable import CompanionClientPlatform
import Foundation
import Testing

private final class CoarseReachabilityMonitorHarnessV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var handler: (@Sendable (NetworkClientPathStatusV1) -> Void)?
    private var startCountStorage = 0
    private var cancelCountStorage = 0

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCountStorage
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCountStorage
    }

    func start(
        _ handler: @escaping @Sendable (
            NetworkClientPathStatusV1
        ) -> Void
    ) {
        lock.lock()
        startCountStorage += 1
        self.handler = handler
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelCountStorage += 1
        handler = nil
        lock.unlock()
    }

    func send(_ status: NetworkClientPathStatusV1) {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?(status)
    }
}

private actor CoarseReachabilityEventRecorderV1 {
    private(set) var values: [Bool] = []

    func consume(_ events: AsyncStream<Bool>) async {
        for await value in events { values.append(value) }
    }
}

@MainActor
@Test func coarseReachabilityMapsOnlySchedulingAvailability() async throws {
    let monitor = CoarseReachabilityMonitorHarnessV1()
    let source = NetworkClientCoarseReachabilitySourceV1(
        startMonitor: { monitor.start($0) },
        cancelMonitor: { monitor.cancel() }
    )
    let recorder = CoarseReachabilityEventRecorderV1()
    let consumer = Task { await recorder.consume(source.events) }

    #expect(source.phase == .idle)
    #expect(await recorder.values.isEmpty)
    try source.start()
    #expect(source.phase == .running)
    #expect(monitor.startCount == 1)

    monitor.send(.satisfied)
    for _ in 0..<2_000 {
        if await recorder.values == [true] { break }
        await Task.yield()
    }
    #expect(await recorder.values == [true])

    monitor.send(.requiresConnection)
    for _ in 0..<2_000 {
        if await recorder.values == [true, false] { break }
        await Task.yield()
    }
    #expect(await recorder.values == [true, false])

    monitor.send(.unsatisfied)
    for _ in 0..<2_000 {
        if await recorder.values == [true, false, false] { break }
        await Task.yield()
    }
    #expect(await recorder.values == [true, false, false])

    source.stop()
    await consumer.value
    #expect(source.phase == .stopped)
    #expect(monitor.cancelCount == 1)
    source.stop()
    #expect(monitor.cancelCount == 1)
}

@MainActor
@Test func coarseReachabilityRejectsRestartAndDropsLateEvents() async throws {
    let monitor = CoarseReachabilityMonitorHarnessV1()
    let source = NetworkClientCoarseReachabilitySourceV1(
        startMonitor: { monitor.start($0) },
        cancelMonitor: { monitor.cancel() }
    )
    let recorder = CoarseReachabilityEventRecorderV1()
    let consumer = Task { await recorder.consume(source.events) }

    try source.start()
    #expect(throws: NetworkClientCoarseReachabilityErrorV1.invalidPhase) {
        try source.start()
    }
    source.stop()
    monitor.send(.satisfied)
    await consumer.value

    #expect(await recorder.values.isEmpty)
    #expect(throws: NetworkClientCoarseReachabilityErrorV1.invalidPhase) {
        try source.start()
    }
    #expect(monitor.startCount == 1)
    #expect(monitor.cancelCount == 1)
}
#endif
