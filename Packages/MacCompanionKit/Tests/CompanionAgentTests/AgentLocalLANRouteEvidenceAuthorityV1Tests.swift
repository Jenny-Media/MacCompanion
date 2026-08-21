@testable import CompanionAgent
import CompanionIPC
import CompanionLifecycle
import Foundation
import Testing

private final class LANRouteTestClockV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) { self.value = value }

    func now() -> Int64 { lock.withLock { value } }

    func set(_ value: Int64) { lock.withLock { self.value = value } }
}

private func lanRouteTestAuthoritiesV1(
    clock: LANRouteTestClockV1
) throws -> (
    AgentLocalStatusAuthorityV1,
    AgentLocalRouteMonitorAuthorityV1,
    AgentLocalLANRouteEvidenceAuthorityV1
) {
    let status = try AgentLocalStatusAuthorityV1(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [],
        pairedDeviceCount: 0,
        activeRemoteSessionCount: 0,
        providerCount: 0
    )
    let routes = AgentLocalRouteMonitorAuthorityV1(localStatus: status)
    return (
        status,
        routes,
        AgentLocalLANRouteEvidenceAuthorityV1(
            routes: routes,
            monotonicNowMilliseconds: clock.now
        )
    )
}

@Test func lanRequiresExactListenerAndAdvertisementReadiness() async throws {
    let clock = LANRouteTestClockV1(10)
    let authorities = try lanRouteTestAuthoritiesV1(clock: clock)

    try await authorities.2.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 1
    )
    #expect(local.routeKinds.isEmpty)

    clock.set(11)
    try await authorities.2.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 2
    )
    #expect(local.routeKinds == [.lan])

    clock.set(12)
    try await authorities.2.publishListenerReadiness(
        ready: false,
        generation: 2
    )
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 3
    )
    #expect(local.routeKinds.isEmpty)
}

@Test func lanWithdrawalPreservesAuthenticatedRouteKinds() async throws {
    let clock = LANRouteTestClockV1(20)
    let authorities = try lanRouteTestAuthoritiesV1(clock: clock)
    _ = try await authorities.1.publishAvailable(
        routeKinds: [.privateNetwork],
        observedAtMonotonicMilliseconds: 19
    )
    try await authorities.2.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    clock.set(21)
    try await authorities.2.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 4
    )
    #expect(local.routeKinds == [.lan, .privateNetwork])

    clock.set(22)
    try await authorities.2.publishAdvertisementReadiness(
        ready: false,
        generation: 2
    )
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 5
    )
    #expect(local.routeKinds == [.privateNetwork])
}

@Test func staleReadinessCannotResurrectLANAndStopIsPermanent() async throws {
    let clock = LANRouteTestClockV1(30)
    let authorities = try lanRouteTestAuthoritiesV1(clock: clock)
    try await authorities.2.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    try await authorities.2.publishListenerReadiness(
        ready: false,
        generation: 2
    )
    await #expect(
        throws: AgentLocalLANRouteEvidenceErrorV1
            .staleListenerGeneration
    ) {
        try await authorities.2.publishListenerReadiness(
            ready: true,
            generation: 1
        )
    }
    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 6
    )
    #expect(local.routeKinds.isEmpty)

    try await authorities.2.stop(
        observedAtMonotonicMilliseconds: 31
    )
    await #expect(throws: AgentLocalLANRouteEvidenceErrorV1.sourceStopped) {
        try await authorities.2.publishListenerReadiness(
            ready: true,
            generation: 3
        )
    }
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 7
    )
    #expect(local.routeKinds.isEmpty)
    #expect((await authorities.2.snapshot()).stopped)
}

@Test func failedLANPublicationDoesNotCommitSourceGeneration() async throws {
    let clock = LANRouteTestClockV1(-1)
    let authorities = try lanRouteTestAuthoritiesV1(clock: clock)

    await #expect(throws: AgentLocalRouteMonitorErrorV1.invalidTime) {
        try await authorities.2.publishListenerReadiness(
            ready: true,
            generation: 1
        )
    }
    #expect((await authorities.2.snapshot()).listenerGeneration == 0)
    #expect(!(await authorities.2.snapshot()).listenerReady)

    clock.set(40)
    try await authorities.2.publishListenerReadiness(
        ready: true,
        generation: 1
    )
    #expect((await authorities.2.snapshot()).listenerGeneration == 1)
}
