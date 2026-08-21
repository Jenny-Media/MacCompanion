import CompanionAgent
import CompanionIPC
import CompanionLifecycle
import Foundation
import Testing

private struct FixedLocalStatusWallClockV1: AgentLocalStatusWallClockV1 {
    let value: Int64

    func nowUnixMilliseconds() -> Int64 { value }
}

private func localStatusReadAuthorityV1() throws
    -> AgentLocalStatusAuthorityV1
{
    try AgentLocalStatusAuthorityV1(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 1,
        activeRemoteSessionCount: 0,
        providerCount: 2
    )
}

@Test func localStatusReadSamplesOneClockAndReturnsOneAuthorityVersion() async throws {
    let service = AgentLocalStatusReadServiceV1(
        status: try localStatusReadAuthorityV1(),
        wallClock: FixedLocalStatusWallClockV1(value: 1_000)
    )

    let value = try await service.read()
    #expect(value.generatedAtUnixMilliseconds == 1_000)
    #expect(value.diagnosticSequence == 1)
    #expect(value.routeKinds == [.lan])
    #expect(value.pairedDeviceCount == 1)
    #expect(value.providerCount == 2)
}

@Test func localStatusReadMapsInvalidClockWithoutConsumingSequence() async throws {
    let authority = try localStatusReadAuthorityV1()
    let invalid = AgentLocalStatusReadServiceV1(
        status: authority,
        wallClock: FixedLocalStatusWallClockV1(value: -1)
    )
    await #expect(
        throws: AgentLocalStatusReadServiceErrorV1.sourceUnavailable
    ) {
        _ = try await invalid.read()
    }

    let valid = AgentLocalStatusReadServiceV1(
        status: authority,
        wallClock: FixedLocalStatusWallClockV1(value: 2_000)
    )
    let value = try await valid.read()
    #expect(value.diagnosticSequence == 1)
    #expect(value.generatedAtUnixMilliseconds == 2_000)
}

@Test func concurrentLocalStatusServiceReadsRemainUniquelySequenced() async throws {
    let service = AgentLocalStatusReadServiceV1(
        status: try localStatusReadAuthorityV1(),
        wallClock: FixedLocalStatusWallClockV1(value: 3_000)
    )
    let sequences = try await withThrowingTaskGroup(
        of: UInt64.self,
        returning: [UInt64].self
    ) { group in
        for _ in 0..<32 {
            group.addTask { try await service.read().diagnosticSequence }
        }
        var values: [UInt64] = []
        for try await value in group { values.append(value) }
        return values.sorted()
    }
    #expect(sequences == (1...32).map(UInt64.init))
}

@Test func statusReadAuthorizationPolicyRemainsOutsideReadCapability() throws {
    try LocalIPCAuthorizationPolicy.authorize(
        authenticatedCaller: .menuApp,
        endpoint: .agent,
        method: .readAgentStatus,
        version: .init()
    )
    try LocalIPCAuthorizationPolicy.authorize(
        authenticatedCaller: .diagnosticCLI,
        endpoint: .agent,
        method: .readAgentStatus,
        version: .init()
    )
    #expect(throws: LocalIPCAuthorizationError.sameRoleConnection) {
        try LocalIPCAuthorizationPolicy.authorize(
            authenticatedCaller: .agent,
            endpoint: .agent,
            method: .readAgentStatus,
            version: .init()
        )
    }
    #expect(throws: LocalIPCAuthorizationError.unsupportedVersion(.init(minor: 2))) {
        try LocalIPCAuthorizationPolicy.authorize(
            authenticatedCaller: .menuApp,
            endpoint: .agent,
            method: .readAgentStatus,
            version: .init(minor: 2)
        )
    }
}
