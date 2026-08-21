import CompanionIPC
import CompanionLifecycle
import CompanionMacApp
import Foundation
import Testing

private func ownerDashboardStatusV0(
    sequence: UInt64,
    generatedAt: Int64,
    providerCount: UInt16 = 1
) throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: .active,
        agentProcess: .ready,
        menuAppProcess: .ready,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 0,
        activeRemoteSessionCount: 0,
        providerCount: providerCount,
        warningCodes: [],
        diagnosticSequence: sequence,
        generatedAtUnixMilliseconds: generatedAt
    )
}

private actor DashboardSourceProbeV0 {
    private var values: [MacAgentDashboardSourceV0] = []
    func append(_ value: MacAgentDashboardSourceV0) { values.append(value) }
    func snapshots() -> [MacAgentDashboardSourceV0] { values }
}

@Test func dashboardOwnerPublishesOnlyValidatedIncreasingStatus() async throws {
    let probe = DashboardSourceProbeV0()
    let owner = MacAgentDashboardApplicationOwnerV0(
        stateChanged: { await probe.append($0) }
    )
    let token = try await owner.beginConnection()
    let first = try ownerDashboardStatusV0(
        sequence: 1,
        generatedAt: 1_724_000_000_000
    )
    let second = try ownerDashboardStatusV0(
        sequence: 2,
        generatedAt: 1_724_000_000_000
    )
    try await owner.receive(first, from: token)
    try await owner.receive(second, from: token)

    #expect(await owner.snapshot() == .status(second))
    #expect(await probe.snapshots() == [
        .loading,
        .status(first),
        .status(second),
    ])
}

@Test func newDashboardConnectionFencesEveryReplyFromTheOldGeneration()
    async throws
{
    let owner = MacAgentDashboardApplicationOwnerV0()
    let old = try await owner.beginConnection()
    let replacement = try await owner.beginConnection()
    let value = try ownerDashboardStatusV0(
        sequence: 1,
        generatedAt: 1_724_000_000_000
    )

    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.staleConnection
    ) {
        try await owner.receive(value, from: old)
    }
    try await owner.receive(value, from: replacement)
    #expect(await owner.snapshot() == .status(value))
}

@Test func dashboardOwnerRejectsSequenceReplayAndClockRegression()
    async throws
{
    let owner = MacAgentDashboardApplicationOwnerV0()
    let token = try await owner.beginConnection()
    let first = try ownerDashboardStatusV0(
        sequence: 5,
        generatedAt: 1_724_000_000_100
    )
    try await owner.receive(first, from: token)

    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.staleStatus
    ) {
        try await owner.receive(first, from: token)
    }
    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.staleStatus
    ) {
        try await owner.receive(
            ownerDashboardStatusV0(
                sequence: 6,
                generatedAt: 1_724_000_000_099
            ),
            from: token
        )
    }
    #expect(await owner.snapshot() == .status(first))
}

@Test func unavailableDashboardGenerationCannotBeResurrectedByLateStatus()
    async throws
{
    let owner = MacAgentDashboardApplicationOwnerV0()
    let token = try await owner.beginConnection()
    try await owner.connectionUnavailable(token)

    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.staleConnection
    ) {
        try await owner.receive(
            ownerDashboardStatusV0(
                sequence: 1,
                generatedAt: 1_724_000_000_000
            ),
            from: token
        )
    }
    #expect(await owner.snapshot() == .unavailable)
}

@Test func dashboardOwnerMapsInvalidDecodedStatusToClosedFailure()
    async throws
{
    let owner = MacAgentDashboardApplicationOwnerV0()
    let token = try await owner.beginConnection()
    let valid = try ownerDashboardStatusV0(
        sequence: 1,
        generatedAt: 1_724_000_000_000
    )
    let encoded = try JSONEncoder().encode(valid)
    let text = try #require(String(data: encoded, encoding: .utf8))
    let malformed = Data(
        text.replacingOccurrences(
            of: "\"providerCount\":1",
            with: "\"providerCount\":129"
        ).utf8
    )
    let decoded = try JSONDecoder().decode(
        LocalAgentStatusSnapshot.self,
        from: malformed
    )

    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.invalidStatus
    ) {
        try await owner.receive(decoded, from: token)
    }
    #expect(await owner.snapshot() == .loading)
}

@Test func applicationInvalidationRetiresTheCurrentDashboardGeneration()
    async throws
{
    let owner = MacAgentDashboardApplicationOwnerV0()
    let token = try await owner.beginConnection()
    await owner.applicationInvalidated()

    await #expect(
        throws: MacAgentDashboardApplicationOwnerErrorV0.staleConnection
    ) {
        try await owner.connectionUnavailable(token)
    }
    #expect(await owner.snapshot() == .unavailable)
}
