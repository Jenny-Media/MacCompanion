import CompanionIPC
import CompanionLifecycle
import CompanionMacApp
import CompanionMacUI
import Foundation
import Testing

private func dashboardStatusV0(
    desiredEnabled: Bool = true,
    consoleSession: ConsoleSessionState = .active,
    agent: ManagedProcessState = .ready,
    menu: ManagedProcessState = .ready,
    network: LocalAgentNetworkState = .listening,
    security: LocalSecurityPosture = .nominal,
    routes: Set<LocalRouteKind> = [.lan],
    pairedDevices: UInt16 = 0,
    activeSessions: UInt16 = 0,
    providers: UInt16 = 1,
    warnings: Set<SanitizedDiagnosticCode> = []
) throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: desiredEnabled,
        consoleSession: consoleSession,
        agentProcess: agent,
        menuAppProcess: menu,
        networkState: network,
        securityPosture: security,
        routeKinds: routes,
        pairedDeviceCount: pairedDevices,
        activeRemoteSessionCount: activeSessions,
        providerCount: providers,
        warningCodes: warnings,
        diagnosticSequence: 1,
        generatedAtUnixMilliseconds: 1_724_000_000_000
    )
}

private func dashboardActionV0(
    _ action: MacAgentDashboardActionV0,
    in projection: MacAgentDashboardProjectionV0
) throws -> MacAgentDashboardActionProjectionV0 {
    try #require(projection.secondaryActions.first { $0.action == action })
}

@Test func dashboardLoadingAndUnavailableNeverInventAgentFacts() throws {
    let loading = try MacAgentDashboardProjectionV0(source: .loading)
    #expect(loading.state == .loading)
    #expect(loading.facts.isEmpty)
    #expect(loading.primaryAction == nil)

    let unavailable = try MacAgentDashboardProjectionV0(source: .unavailable)
    #expect(unavailable.state == .unavailable)
    #expect(unavailable.facts.isEmpty)
    #expect(unavailable.warnings.isEmpty)
    #expect(unavailable.primaryAction?.action == .retryStatus)
    #expect(unavailable.secondaryActions.isEmpty)
}

@Test func disabledDashboardOffersOnlyAnExplicitEnablePath() throws {
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(
            desiredEnabled: false,
            agent: .stopped,
            menu: .stopped,
            network: .stopped,
            routes: [],
            providers: 0
        )
    ))

    #expect(projection.state == .off)
    #expect(projection.primaryAction?.action == .enable)
    #expect(projection.primaryAction?.enabled == true)
    #expect(try !dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openDevices, in: projection).enabled)
    #expect(try !dashboardActionV0(.openActivityHistory, in: projection).enabled)
    #expect(try !dashboardActionV0(.exportDiagnostics, in: projection).enabled)
}

@Test func readyDashboardKeepsObserveActAndControlAdministrationIndependent()
    throws
{
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(routes: [.lan, .privateNetwork])
    ))

    #expect(projection.state == .ready)
    #expect(projection.title == "Mac Companion is on")
    #expect(projection.detail.contains("Observe, Act, and Control"))
    #expect(projection.primaryAction?.action == .disable)
    #expect(try dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openDevices, in: projection).enabled)
    #expect(try dashboardActionV0(.openActivityHistory, in: projection).enabled)
    #expect(try dashboardActionV0(.exportDiagnostics, in: projection).enabled)
    #expect(projection.facts.first { $0.id == "routes" }?.value
        == "Local network, Private network")
}

@Test func pairedDashboardAllowsAnotherPairingAndKeepsDeviceAdministration()
    throws
{
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(pairedDevices: 1)
    ))

    #expect(try dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try dashboardActionV0(.openDevices, in: projection).enabled)
    #expect(projection.facts.first { $0.id == "devices" }?.value == "1")
}

@Test func lockedDashboardMakesTheGenuineLockSurfaceLimitExplicit() throws {
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(consoleSession: .locked)
    ))

    #expect(projection.state == .ready)
    #expect(projection.systemImage == "lock.shield")
    #expect(projection.detail.contains("genuine lock surface"))
    #expect(projection.facts.first { $0.id == "session" }?.value == "Locked")
    #expect(try !dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openDevices, in: projection).enabled)
    #expect(try !dashboardActionV0(.openActivityHistory, in: projection).enabled)
}

@Test func otherConsoleUserDashboardPreservesOnlyStatusSemantics() throws {
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(consoleSession: .otherConsoleUserActive)
    ))

    #expect(projection.state == .ready)
    #expect(projection.systemImage == "person.2.fill")
    #expect(projection.detail.contains("not confirmed active"))
    #expect(projection.detail.contains("Status may remain available"))
    #expect(projection.detail.contains("Act and Control are unavailable"))
    #expect(projection.facts.first { $0.id == "session" }?.value
        == "Configured session not confirmed active")
    #expect(try !dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openDevices, in: projection).enabled)
    #expect(try !dashboardActionV0(.openActivityHistory, in: projection).enabled)
    #expect(projection.primaryAction?.action == .disable)
    #expect(projection.primaryAction?.enabled == true)
    #expect(try dashboardActionV0(.exportDiagnostics, in: projection).enabled)
}

@Test func degradedDashboardProjectsOnlyClosedSanitizedWarnings() throws {
    let warningSet = Set(SanitizedDiagnosticCode.allCases)
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(
            network: .degraded,
            security: .denyLatched,
            warnings: warningSet
        )
    ))

    #expect(projection.state == .needsAttention)
    #expect(Set(projection.warnings.map(\.id))
        == Set(warningSet.map(\.rawValue)))
    #expect(projection.warnings.allSatisfy {
        !$0.title.isEmpty && !$0.detail.isEmpty
    })
    #expect(try !dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openDevices, in: projection).enabled)
}

@Test func startingDashboardDoesNotClaimReadyBeforeAllComponentsReportReady()
    throws
{
    let projection = try MacAgentDashboardProjectionV0(source: .status(
        dashboardStatusV0(
            agent: .starting,
            menu: .starting,
            network: .starting
        )
    ))

    #expect(projection.state == .starting)
    #expect(projection.title == "Mac Companion is starting")
    #expect(try !dashboardActionV0(.startPairing, in: projection).enabled)
    #expect(try !dashboardActionV0(.openActivityHistory, in: projection).enabled)
    #expect(try !dashboardActionV0(.exportDiagnostics, in: projection).enabled)
}

@Test func dashboardRevalidatesDecodedStatusBeforePresentation() throws {
    let valid = try dashboardStatusV0()
    let data = try JSONEncoder().encode(valid)
    let text = try #require(String(data: data, encoding: .utf8))
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

    #expect(throws: LocalDiagnosticsValidationError.boundsExceeded) {
        try MacAgentDashboardProjectionV0(source: .status(decoded))
    }
}
