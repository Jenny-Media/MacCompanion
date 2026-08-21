@testable import CompanionAgent
import CompanionIPC
import CompanionLifecycle
import CompanionWire
import Foundation
import Testing

private func routeStatusAuthorityV1() throws -> AgentLocalStatusAuthorityV1 {
    try AgentLocalStatusAuthorityV1(
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
}

@Test func routeMonitorPublishesClosedPathLossRecoveryAndStop() async throws {
    let status = try routeStatusAuthorityV1()
    let monitor = AgentLocalRouteMonitorAuthorityV1(localStatus: status)

    let available = try await monitor.publishAvailable(
        routeKinds: [.lan, .privateNetwork],
        observedAtMonotonicMilliseconds: 100
    )
    #expect(available.state == .observing)
    #expect(available.generation == 1)
    #expect(available.routeKinds == [.lan, .privateNetwork])
    #expect(available.freshUntilMonotonicMilliseconds == 30_100)
    var local = try await status.snapshot(generatedAtUnixMilliseconds: 1)
    #expect(local.routeKinds == [.lan, .privateNetwork])
    #expect(!local.warningCodes.contains(.routeUnavailable))

    let disappeared = try await monitor.publishAvailable(
        routeKinds: [],
        observedAtMonotonicMilliseconds: 110
    )
    #expect(disappeared.state == .observing)
    #expect(disappeared.generation == 2)
    local = try await status.snapshot(generatedAtUnixMilliseconds: 2)
    #expect(local.routeKinds.isEmpty)
    #expect(local.warningCodes == [.routeUnavailable])

    _ = try await monitor.publishAvailable(
        routeKinds: [.privateDNS],
        observedAtMonotonicMilliseconds: 120
    )
    _ = try await monitor.publishUnavailable(
        observedAtMonotonicMilliseconds: 130
    )
    local = try await status.snapshot(generatedAtUnixMilliseconds: 3)
    #expect(local.routeKinds.isEmpty)
    #expect(local.warningCodes == [.routeUnavailable])

    let stopped = try await monitor.stop(
        observedAtMonotonicMilliseconds: 140
    )
    #expect(stopped.state == .stopped)
    #expect(stopped.generation == 5)
    local = try await status.snapshot(generatedAtUnixMilliseconds: 4)
    #expect(local.routeKinds.isEmpty)
    #expect(local.warningCodes.isEmpty)
}

@Test func routeFreshnessExpiresAfterInclusiveDeadlineExactlyOnce() async throws {
    let status = try routeStatusAuthorityV1()
    let monitor = AgentLocalRouteMonitorAuthorityV1(localStatus: status)
    _ = try await monitor.publishAvailable(
        routeKinds: [.lan],
        observedAtMonotonicMilliseconds: 1_000
    )

    let atDeadline = try await monitor.snapshot(
        nowMonotonicMilliseconds: 31_000
    )
    #expect(atDeadline.state == .observing)
    #expect(atDeadline.generation == 1)
    let expired = try await monitor.snapshot(
        nowMonotonicMilliseconds: 31_001
    )
    #expect(expired.state == .unavailable)
    #expect(expired.generation == 2)
    #expect(expired.routeKinds.isEmpty)
    #expect(expired.freshUntilMonotonicMilliseconds == nil)
    let repeated = try await monitor.snapshot(
        nowMonotonicMilliseconds: 31_002
    )
    #expect(repeated.generation == 2)

    let local = try await status.snapshot(generatedAtUnixMilliseconds: 5)
    #expect(local.routeKinds.isEmpty)
    #expect(local.warningCodes == [.routeUnavailable])
}

@Test func invalidOrRegressedRouteClocksPreservePublishedVersion() async throws {
    let status = try routeStatusAuthorityV1()
    let monitor = AgentLocalRouteMonitorAuthorityV1(localStatus: status)
    let accepted = try await monitor.publishAvailable(
        routeKinds: [.privateNetwork],
        observedAtMonotonicMilliseconds: 10
    )

    await #expect(throws: AgentLocalRouteMonitorErrorV1.timeRegressed) {
        _ = try await monitor.publishUnavailable(
            observedAtMonotonicMilliseconds: 9
        )
    }
    await #expect(throws: AgentLocalRouteMonitorErrorV1.timeRegressed) {
        _ = try await monitor.snapshot(nowMonotonicMilliseconds: 9)
    }
    await #expect(throws: AgentLocalRouteMonitorErrorV1.invalidTime) {
        _ = try await monitor.publishAvailable(
            routeKinds: [.lan],
            observedAtMonotonicMilliseconds:
                WireLimits.maximumSafeInteger
                    - AgentLocalRouteMonitorAuthorityV1
                        .freshnessWindowMilliseconds + 1
        )
    }
    let current = try await monitor.snapshot(nowMonotonicMilliseconds: 10)
    #expect(current == accepted)
    let local = try await status.snapshot(generatedAtUnixMilliseconds: 6)
    #expect(local.routeKinds == [.privateNetwork])
    #expect(local.warningCodes.isEmpty)
}

@Test func localStatusRejectsDelayedRouteGenerationWithoutRollback() async throws {
    let status = try routeStatusAuthorityV1()
    try await status.updateRoutes(
        routeKinds: [.privateDNS],
        routeUnavailable: false,
        generation: 2
    )
    await #expect(
        throws: AgentLocalStatusAuthorityErrorV1.staleRouteGeneration
    ) {
        try await status.updateRoutes(
            routeKinds: [],
            routeUnavailable: true,
            generation: 1
        )
    }

    let value = try await status.snapshot(generatedAtUnixMilliseconds: 7)
    #expect(value.routeKinds == [.privateDNS])
    #expect(value.warningCodes.isEmpty)
}
