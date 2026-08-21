@testable import CompanionAgent
import CompanionIPC
import CompanionLifecycle
import CompanionWire
import Foundation
import Testing

private final class AuthenticatedRouteTestClockV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) { self.value = value }

    func now() -> Int64 { lock.withLock { value } }

    func set(_ value: Int64) { lock.withLock { self.value = value } }
}

private func authenticatedRouteTestAuthoritiesV1(
    clock: AuthenticatedRouteTestClockV1
) throws -> (
    AgentLocalStatusAuthorityV1,
    AgentLocalRouteMonitorAuthorityV1,
    AgentLocalAuthenticatedRouteEvidenceAuthorityV1
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
        AgentLocalAuthenticatedRouteEvidenceAuthorityV1(
            routes: routes,
            monotonicNowMilliseconds: clock.now
        )
    )
}

@Test func authenticatedRouteReplacesOnlyConfiguredClassAndPreservesLAN()
    async throws
{
    let clock = AuthenticatedRouteTestClockV1(103)
    let authorities = try authenticatedRouteTestAuthoritiesV1(clock: clock)
    _ = try await authorities.1.publishLANAvailability(
        available: true,
        observedAtMonotonicMilliseconds: 99
    )
    let publisher = try await authorities.2.makePublisher()
    let connection = Data(repeating: 0x11, count: 16)

    await publisher.publish(
        connectionID: connection,
        routeClass: .privateDNS,
        observedAtMonotonicMilliseconds: 100
    )
    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 1
    )
    #expect(local.routeKinds == [.lan, .privateDNS])

    await publisher.publish(
        connectionID: connection,
        routeClass: .privateNetwork,
        observedAtMonotonicMilliseconds: 101
    )
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 2
    )
    #expect(local.routeKinds == [.lan, .privateNetwork])

    await publisher.withdraw(connectionID: connection)
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 3
    )
    #expect(local.routeKinds == [.lan])
    #expect(local.warningCodes.isEmpty)
}

@Test func replacementPublisherFencesDelayedPublicationAndWithdrawal()
    async throws
{
    let clock = AuthenticatedRouteTestClockV1(203)
    let authorities = try authenticatedRouteTestAuthoritiesV1(clock: clock)
    let first = try await authorities.2.makePublisher()
    let firstConnection = Data(repeating: 0x21, count: 16)
    await first.publish(
        connectionID: firstConnection,
        routeClass: .privateDNS,
        observedAtMonotonicMilliseconds: 200
    )

    let replacement = try await authorities.2.makePublisher()
    let replacementConnection = Data(repeating: 0x22, count: 16)
    await replacement.publish(
        connectionID: replacementConnection,
        routeClass: .privateNetwork,
        observedAtMonotonicMilliseconds: 201
    )
    await first.publish(
        connectionID: firstConnection,
        routeClass: .privateDNS,
        observedAtMonotonicMilliseconds: 202
    )
    await first.withdraw(connectionID: firstConnection)

    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 4
    )
    #expect(local.routeKinds == [.privateNetwork])

    await replacement.withdraw(connectionID: replacementConnection)
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 5
    )
    #expect(local.routeKinds.isEmpty)
}

@Test func wrongConnectionAndDiagnosticClockFailureAreFailIsolated()
    async throws
{
    let clock = AuthenticatedRouteTestClockV1(-1)
    let authorities = try authenticatedRouteTestAuthoritiesV1(clock: clock)
    let publisher = try await authorities.2.makePublisher()
    let connection = Data(repeating: 0x31, count: 16)
    await publisher.publish(
        connectionID: connection,
        routeClass: .privateDNS,
        observedAtMonotonicMilliseconds: 300
    )

    await publisher.withdraw(
        connectionID: Data(repeating: 0x32, count: 16)
    )
    var local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 6
    )
    #expect(local.routeKinds == [.privateDNS])

    // The invalid diagnostic clock is rejected internally and never escapes
    // through the non-authorizing publisher protocol.
    await publisher.withdraw(connectionID: connection)
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 7
    )
    #expect(local.routeKinds == [.privateDNS])

    await publisher.publish(
        connectionID: connection,
        routeClass: .privateNetwork,
        observedAtMonotonicMilliseconds: UInt64.max
    )
    local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 8
    )
    #expect(local.routeKinds == [.privateDNS])
}

@Test func validRegressedWithdrawalClockClampsForwardAndRemovesRoute()
    async throws
{
    let clock = AuthenticatedRouteTestClockV1(499)
    let authorities = try authenticatedRouteTestAuthoritiesV1(clock: clock)
    let publisher = try await authorities.2.makePublisher()
    let connection = Data(repeating: 0x51, count: 16)
    await publisher.publish(
        connectionID: connection,
        routeClass: .privateDNS,
        observedAtMonotonicMilliseconds: 500
    )

    await publisher.withdraw(connectionID: connection)
    let local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 10
    )
    #expect(local.routeKinds.isEmpty)
    #expect(local.warningCodes == [.routeUnavailable])
}

@Test func configuredRouteFreshnessCannotExtendOrExpireLANEvidence()
    async throws
{
    let clock = AuthenticatedRouteTestClockV1(401)
    let authorities = try authenticatedRouteTestAuthoritiesV1(clock: clock)
    _ = try await authorities.1.publishLANAvailability(
        available: true,
        observedAtMonotonicMilliseconds: 400
    )
    let publisher = try await authorities.2.makePublisher()
    await publisher.publish(
        connectionID: Data(repeating: 0x41, count: 16),
        routeClass: .privateNetwork,
        observedAtMonotonicMilliseconds: 401
    )

    let atDeadline = try await authorities.1.snapshot(
        nowMonotonicMilliseconds: 30_401
    )
    #expect(atDeadline.routeKinds == [.lan, .privateNetwork])
    let expired = try await authorities.1.snapshot(
        nowMonotonicMilliseconds: 30_402
    )
    #expect(expired.state == .observing)
    #expect(expired.routeKinds == [.lan])
    #expect(expired.freshUntilMonotonicMilliseconds == nil)

    let local = try await authorities.0.snapshot(
        generatedAtUnixMilliseconds: 9
    )
    #expect(local.routeKinds == [.lan])
    #expect(local.warningCodes.isEmpty)
}
