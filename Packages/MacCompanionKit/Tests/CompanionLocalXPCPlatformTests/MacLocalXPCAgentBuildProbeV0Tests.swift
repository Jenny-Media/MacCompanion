#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Foundation
import Testing

@available(macOS 26.0, *)
private final class BuildProbeClientV0:
    MacLocalXPCAgentBuildProbeClientV0,
    @unchecked Sendable
{
    enum StartError: Error { case failed }

    private let lock = NSLock()
    private let onStart: @Sendable () throws -> Void
    private(set) var cancelCount = 0

    init(onStart: @escaping @Sendable () throws -> Void = {}) {
        self.onStart = onStart
    }

    func start() throws { try onStart() }

    func cancel() {
        lock.lock()
        cancelCount += 1
        lock.unlock()
    }

    func observedCancelCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCount
    }
}

@Test
@available(macOS 26.0, *)
func buildProbeReturnsFirstAuthenticatedBuildAndCancelsClient() async throws {
    let eventBox = BuildProbeEventBoxV0()
    let client = BuildProbeClientV0 {
        eventBox.emit(.authenticatedAgent(build: 42))
        eventBox.emit(.invalidated)
    }
    let probe = MacLocalXPCAgentBuildProbeV0 { handler in
        eventBox.install(handler)
        return client
    }

    #expect(try await probe.readBuild() == 42)
    #expect(client.observedCancelCount() == 1)
}

@Test
@available(macOS 26.0, *)
func buildProbeMapsStartFailureAndCancelsClient() async {
    let client = BuildProbeClientV0 { throw BuildProbeClientV0.StartError.failed }
    let probe = MacLocalXPCAgentBuildProbeV0 { _ in client }

    await #expect(throws: MacLocalXPCAgentBuildProbeErrorV0.startFailed) {
        try await probe.readBuild()
    }
    #expect(client.observedCancelCount() == 1)
}

@Test
@available(macOS 26.0, *)
func buildProbeRejectsInvalidationAndUnexpectedTraffic() async {
    let cases: [(
        MacLocalXPCClientEventV1,
        MacLocalXPCAgentBuildProbeErrorV0
    )] = [
        (.invalidated, .invalidated),
        (.menuReadyAcknowledged, .unexpectedEvent),
    ]
    for (event, expected) in cases {
        let eventBox = BuildProbeEventBoxV0()
        let client = BuildProbeClientV0 { eventBox.emit(event) }
        let probe = MacLocalXPCAgentBuildProbeV0 { handler in
            eventBox.install(handler)
            return client
        }
        await #expect(throws: expected) {
            try await probe.readBuild()
        }
        #expect(client.observedCancelCount() == 1)
    }
}

@Test
@available(macOS 26.0, *)
func buildProbeTimesOutAndRejectsZeroTimeout() async {
    let client = BuildProbeClientV0()
    let probe = MacLocalXPCAgentBuildProbeV0 { _ in client }

    await #expect(throws: MacLocalXPCAgentBuildProbeErrorV0.timedOut) {
        try await probe.readBuild(timeoutNanoseconds: 1_000_000)
    }
    #expect(client.observedCancelCount() == 1)
    await #expect(throws: MacLocalXPCAgentBuildProbeErrorV0.invalidTimeout) {
        try await probe.readBuild(timeoutNanoseconds: 0)
    }
    #expect(client.observedCancelCount() == 1)
}

@available(macOS 26.0, *)
private final class BuildProbeEventBoxV0: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: MacLocalXPCClientV1.EventHandler?
    private var pending: [MacLocalXPCClientEventV1] = []

    func install(_ handler: @escaping MacLocalXPCClientV1.EventHandler) {
        lock.lock()
        self.handler = handler
        let pending = self.pending
        self.pending.removeAll()
        lock.unlock()
        pending.forEach(handler)
    }

    func emit(_ event: MacLocalXPCClientEventV1) {
        lock.lock()
        if let handler {
            lock.unlock()
            handler(event)
        } else {
            pending.append(event)
            lock.unlock()
        }
    }
}
#endif
