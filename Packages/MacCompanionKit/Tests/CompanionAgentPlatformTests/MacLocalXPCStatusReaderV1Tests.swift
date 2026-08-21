#if os(macOS)
import CompanionAgent
import CompanionAgentPlatform
import CompanionDomain
import CompanionIPC
import CompanionLocalXPCPlatform
import Testing

private struct StatusReaderStubV1: AgentLocalStatusReadingV1 {
    let result: Result<LocalAgentStatusSnapshot, AgentLocalStatusReadServiceErrorV1>

    func read() async throws -> LocalAgentStatusSnapshot {
        try result.get()
    }
}

private func statusSnapshotV1() throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: .active,
        agentProcess: .ready,
        menuAppProcess: .ready,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 2,
        activeRemoteSessionCount: 0,
        providerCount: 1,
        warningCodes: [],
        diagnosticSequence: 7,
        generatedAtUnixMilliseconds: 1_724_000_000_000
    )
}

@Test
func localXPCStatusReaderIssuesOnlyTypedContentFreeSnapshot() async throws {
    let expected = try statusSnapshotV1()
    let adapter = MacLocalXPCStatusReaderV1(
        statusReader: StatusReaderStubV1(result: .success(expected))
    )

    let result = await adapter.readStatus()
    #expect(try result.get() == expected)
}

@Test
func localXPCStatusReaderMapsEverySourceFailureToClosedError() async {
    let adapter = MacLocalXPCStatusReaderV1(
        statusReader: StatusReaderStubV1(
            result: .failure(.sourceUnavailable)
        )
    )

    #expect(
        await adapter.readStatus()
            == .failure(.sourceUnavailable)
    )
}
#endif
