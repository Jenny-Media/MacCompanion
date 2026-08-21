import CompanionDiscovery
import CompanionIPC
import CompanionLifecycle
import CompanionMacApp
import CompanionWire
import Foundation
import Testing

private enum DashboardActionTestErrorV0: Error {
    case injected
}

private actor DashboardActionSourceProbeV0:
    MacAgentDashboardSourceReadingV0
{
    private var value: MacAgentDashboardSourceV0

    init(_ value: MacAgentDashboardSourceV0) { self.value = value }

    func snapshot() -> MacAgentDashboardSourceV0 { value }
    func set(_ value: MacAgentDashboardSourceV0) { self.value = value }
}

private actor DashboardActionEffectProbeV0:
    MacAgentDashboardLifecycleCommandingV0,
    MacAgentDashboardStatusRetryingV0,
    MacAgentDashboardPairingStartingV0
{
    private var lifecycleOutcome: MacAgentDashboardEffectOutcomeV0 = .completed
    private var statusOutcome: MacAgentDashboardEffectOutcomeV0 = .completed
    private var pairingOutcome: MacAgentDashboardEffectOutcomeV0 = .completed
    private var lifecycleValues: [Bool] = []
    private var statusCalls = 0
    private var pairingCalls = 0
    private var suspendNextLifecycle = false
    private var suspendedLifecycle:
        CheckedContinuation<MacAgentDashboardEffectOutcomeV0, Never>?
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []

    func setLifecycleOutcome(_ value: MacAgentDashboardEffectOutcomeV0) {
        lifecycleOutcome = value
    }

    func setStatusOutcome(_ value: MacAgentDashboardEffectOutcomeV0) {
        statusOutcome = value
    }

    func setPairingOutcome(_ value: MacAgentDashboardEffectOutcomeV0) {
        pairingOutcome = value
    }

    func suspendLifecycleOnce() { suspendNextLifecycle = true }

    func waitForLifecycleCall() async {
        if !lifecycleValues.isEmpty { return }
        await withCheckedContinuation { lifecycleWaiters.append($0) }
    }

    func resumeLifecycle(
        with value: MacAgentDashboardEffectOutcomeV0
    ) throws {
        guard let suspendedLifecycle else {
            throw DashboardActionTestErrorV0.injected
        }
        self.suspendedLifecycle = nil
        suspendedLifecycle.resume(returning: value)
    }

    func counts() -> (lifecycle: Int, status: Int, pairing: Int) {
        (lifecycleValues.count, statusCalls, pairingCalls)
    }

    func lifecycleArguments() -> [Bool] { lifecycleValues }

    func setEnabled(_ enabled: Bool) async
        -> MacAgentDashboardEffectOutcomeV0
    {
        lifecycleValues.append(enabled)
        let waiters = lifecycleWaiters
        lifecycleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if suspendNextLifecycle {
            suspendNextLifecycle = false
            return await withCheckedContinuation {
                suspendedLifecycle = $0
            }
        }
        return lifecycleOutcome
    }

    func retryStatus() -> MacAgentDashboardEffectOutcomeV0 {
        statusCalls += 1
        return statusOutcome
    }

    func startPairingFromDashboard()
        -> MacAgentDashboardEffectOutcomeV0
    {
        pairingCalls += 1
        return pairingOutcome
    }
}

private actor DashboardDiagnosticProbeV0:
    MacAgentDashboardDiagnosticExportingV0
{
    private var value: LocalDiagnosticExport?
    private var shouldFail = false
    private var calls = 0

    init(value: LocalDiagnosticExport) { self.value = value }

    func setValue(_ value: LocalDiagnosticExport) { self.value = value }
    func fail() { shouldFail = true }
    func callCount() -> Int { calls }

    func exportDiagnostics() throws -> LocalDiagnosticExport {
        calls += 1
        guard !shouldFail, let value else {
            throw DashboardActionTestErrorV0.injected
        }
        return value
    }
}

private actor DashboardActionStateProbeV0 {
    private var values: [MacAgentDashboardActionStateV0] = []
    func append(_ value: MacAgentDashboardActionStateV0) { values.append(value) }
    func snapshots() -> [MacAgentDashboardActionStateV0] { values }
}

private func dashboardActionStatusV0(
    desiredEnabled: Bool = true,
    consoleSession: ConsoleSessionState = .active,
    agent: ManagedProcessState = .ready,
    menuApp: ManagedProcessState = .ready,
    network: LocalAgentNetworkState = .listening,
    security: LocalSecurityPosture = .nominal,
    pairedDeviceCount: UInt16 = 0,
    sequence: UInt64 = 1
) throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: desiredEnabled,
        consoleSession: consoleSession,
        agentProcess: agent,
        menuAppProcess: menuApp,
        networkState: network,
        securityPosture: security,
        routeKinds: [.lan],
        pairedDeviceCount: pairedDeviceCount,
        activeRemoteSessionCount: 0,
        providerCount: 1,
        warningCodes: [],
        diagnosticSequence: sequence,
        generatedAtUnixMilliseconds: 1_787_198_400_000
    )
}

private func dashboardDiagnosticExportV0() throws -> LocalDiagnosticExport {
    try LocalDiagnosticExport(
        status: dashboardActionStatusV0(),
        events: [
            try SanitizedDiagnosticEvent(
                sequence: 1,
                occurredAtUnixMilliseconds: 1_787_198_399_000,
                component: .network,
                severity: .information,
                code: .routeUnavailable
            ),
        ]
    )
}

private func dashboardActionCoordinatorV0(
    source: DashboardActionSourceProbeV0,
    effects: DashboardActionEffectProbeV0,
    diagnostics: DashboardDiagnosticProbeV0,
    stateChanged: @escaping MacAgentDashboardActionCoordinatorV0.StateChanged = { _ in }
) -> MacAgentDashboardActionCoordinatorV0 {
    MacAgentDashboardActionCoordinatorV0(
        source: source,
        lifecycle: effects,
        statusRetry: effects,
        pairing: effects,
        diagnostics: diagnostics,
        stateChanged: stateChanged
    )
}

@Test func dashboardActionPolicyOwnsEveryUIAdmissionDecision() throws {
    for action in MacAgentDashboardActionV0.allCases {
        #expect(!MacAgentDashboardActionPolicyV0.isEnabled(action, in: .loading))
        #expect(
            MacAgentDashboardActionPolicyV0.isEnabled(action, in: .unavailable)
                == (action == .retryStatus)
        )
    }

    let ready = MacAgentDashboardSourceV0.status(
        try dashboardActionStatusV0()
    )
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.disable, in: ready))
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.startPairing, in: ready))
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.openActivityHistory, in: ready))
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.exportDiagnostics, in: ready))
    #expect(!MacAgentDashboardActionPolicyV0.isEnabled(.enable, in: ready))
    #expect(!MacAgentDashboardActionPolicyV0.isEnabled(.openDevices, in: ready))

    let paired = MacAgentDashboardSourceV0.status(
        try dashboardActionStatusV0(pairedDeviceCount: 1)
    )
    #expect(!MacAgentDashboardActionPolicyV0.isEnabled(.startPairing, in: paired))
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.openDevices, in: paired))

    let locked = MacAgentDashboardSourceV0.status(
        try dashboardActionStatusV0(consoleSession: .locked)
    )
    #expect(!MacAgentDashboardActionPolicyV0.isEnabled(.startPairing, in: locked))
    #expect(!MacAgentDashboardActionPolicyV0.isEnabled(.openActivityHistory, in: locked))
    #expect(MacAgentDashboardActionPolicyV0.isEnabled(.exportDiagnostics, in: locked))
}

@Test func dashboardCoordinatorPublishesOnlyCompletedLifecyclePostcondition()
    async throws
{
    let source = DashboardActionSourceProbeV0(.status(
        try dashboardActionStatusV0(
            desiredEnabled: false,
            agent: .stopped,
            menuApp: .ready,
            network: .stopped
        )
    ))
    let effects = DashboardActionEffectProbeV0()
    let states = DashboardActionStateProbeV0()
    let coordinator = dashboardActionCoordinatorV0(
        source: source,
        effects: effects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        ),
        stateChanged: { await states.append($0) }
    )

    let result = try await coordinator.perform(.enable)
    #expect(result == .completed(action: .enable, completion: .enabled))
    #expect(await effects.lifecycleArguments() == [true])
    #expect(await coordinator.snapshot() == .finished(result))
    #expect(await states.snapshots() == [
        .performing(.enable),
        .finished(result),
    ])
}

@Test func dashboardCoordinatorDeniesActionsBeforeInvokingAnyEffect()
    async throws
{
    let source = DashboardActionSourceProbeV0(.status(
        try dashboardActionStatusV0()
    ))
    let effects = DashboardActionEffectProbeV0()
    let diagnostics = DashboardDiagnosticProbeV0(
        value: try dashboardDiagnosticExportV0()
    )
    let coordinator = dashboardActionCoordinatorV0(
        source: source,
        effects: effects,
        diagnostics: diagnostics
    )

    await #expect(
        throws: MacAgentDashboardActionCoordinatorErrorV0
            .actionDenied(.enable)
    ) {
        _ = try await coordinator.perform(.enable)
    }
    #expect(await effects.counts().lifecycle == 0)
    #expect(await diagnostics.callCount() == 0)
    #expect(await coordinator.snapshot() == .idle)
}

@Test func dashboardCoordinatorRejectsInvalidSourceBeforeAdmission()
    async throws
{
    let valid = try dashboardActionStatusV0()
    let encoded = try JSONEncoder().encode(valid)
    let text = try #require(String(data: encoded, encoding: .utf8))
    let malformed = try JSONDecoder().decode(
        LocalAgentStatusSnapshot.self,
        from: Data(
            text.replacingOccurrences(
                of: "\"providerCount\":1",
                with: "\"providerCount\":129"
            ).utf8
        )
    )
    let effects = DashboardActionEffectProbeV0()
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(malformed)),
        effects: effects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )

    await #expect(
        throws: MacAgentDashboardActionCoordinatorErrorV0.invalidSource
    ) {
        _ = try await coordinator.perform(.disable)
    }
    #expect(await effects.counts().lifecycle == 0)
}

@Test func dashboardCoordinatorSerializesSuspendedEffects() async throws {
    let effects = DashboardActionEffectProbeV0()
    await effects.suspendLifecycleOnce()
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0()
        )),
        effects: effects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )
    let first = Task { try await coordinator.perform(.disable) }
    await effects.waitForLifecycleCall()

    await #expect(
        throws: MacAgentDashboardActionCoordinatorErrorV0.actionInProgress
    ) {
        _ = try await coordinator.perform(.disable)
    }
    try await effects.resumeLifecycle(with: .completed)
    #expect(try await first.value == .completed(
        action: .disable,
        completion: .disabled
    ))
    #expect(await effects.counts().lifecycle == 1)
}

@Test func authorityInvalidationFencesLateActionCompletion() async throws {
    let effects = DashboardActionEffectProbeV0()
    await effects.suspendLifecycleOnce()
    let states = DashboardActionStateProbeV0()
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0()
        )),
        effects: effects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        ),
        stateChanged: { await states.append($0) }
    )
    let task = Task { try await coordinator.perform(.disable) }
    await effects.waitForLifecycleCall()
    await coordinator.authorityInvalidated()
    try await effects.resumeLifecycle(with: .completed)

    #expect(try await task.value == .outcomeUnknown(action: .disable))
    #expect(await coordinator.snapshot() == .idle)
    #expect(await states.snapshots() == [.performing(.disable), .idle])
}

@Test func dashboardCoordinatorPreservesFailedAndUnknownEffectOutcomes()
    async throws
{
    let effects = DashboardActionEffectProbeV0()
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0()
        )),
        effects: effects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )

    await effects.setLifecycleOutcome(.notCompleted)
    #expect(try await coordinator.perform(.disable) == .failed(
        action: .disable,
        reason: .effectNotCompleted
    ))
    await effects.setLifecycleOutcome(.outcomeUnknown)
    #expect(try await coordinator.perform(.disable) == .outcomeUnknown(
        action: .disable
    ))
}

@Test func dashboardCoordinatorReturnsOnlyRevalidatedDiagnosticExport()
    async throws
{
    let valid = try dashboardDiagnosticExportV0()
    let diagnostics = DashboardDiagnosticProbeV0(value: valid)
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0()
        )),
        effects: DashboardActionEffectProbeV0(),
        diagnostics: diagnostics
    )

    #expect(try await coordinator.perform(.exportDiagnostics) == .completed(
        action: .exportDiagnostics,
        completion: .diagnosticExport(valid)
    ))

    let encoded = try JSONEncoder().encode(valid)
    let text = try #require(String(data: encoded, encoding: .utf8))
    let malformed = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: Data(
            text.replacingOccurrences(
                of: "\"privateRouteDetailsOmitted\":true",
                with: "\"privateRouteDetailsOmitted\":false"
            ).utf8
        )
    )
    await diagnostics.setValue(malformed)
    #expect(try await coordinator.perform(.exportDiagnostics) == .failed(
        action: .exportDiagnostics,
        reason: .diagnosticsUnavailable
    ))
}

@Test func dashboardCoordinatorKeepsNavigationLocalAndTyped() async throws {
    let effects = DashboardActionEffectProbeV0()
    let diagnostics = DashboardDiagnosticProbeV0(
        value: try dashboardDiagnosticExportV0()
    )
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0(pairedDeviceCount: 1)
        )),
        effects: effects,
        diagnostics: diagnostics
    )

    #expect(try await coordinator.perform(.openDevices) == .completed(
        action: .openDevices,
        completion: .navigated(.devices)
    ))
    #expect(try await coordinator.perform(.openActivityHistory) == .completed(
        action: .openActivityHistory,
        completion: .navigated(.activityHistory)
    ))
    #expect(await effects.counts().lifecycle == 0)
    #expect(await effects.counts().status == 0)
    #expect(await effects.counts().pairing == 0)
    #expect(await diagnostics.callCount() == 0)
}

@Test func dashboardCoordinatorRoutesRetryAndPairingThroughDistinctEffects()
    async throws
{
    let retryEffects = DashboardActionEffectProbeV0()
    let retry = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.unavailable),
        effects: retryEffects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )
    #expect(try await retry.perform(.retryStatus) == .completed(
        action: .retryStatus,
        completion: .statusRefreshed
    ))
    #expect(await retryEffects.counts().status == 1)
    #expect(await retryEffects.counts().pairing == 0)

    let pairingEffects = DashboardActionEffectProbeV0()
    let pairing = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.status(
            try dashboardActionStatusV0()
        )),
        effects: pairingEffects,
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )
    #expect(try await pairing.perform(.startPairing) == .completed(
        action: .startPairing,
        completion: .pairingPresented
    ))
    #expect(await pairingEffects.counts().status == 0)
    #expect(await pairingEffects.counts().pairing == 1)
}

@Test func applicationInvalidationIsTerminalForDashboardActions()
    async throws
{
    let coordinator = dashboardActionCoordinatorV0(
        source: DashboardActionSourceProbeV0(.unavailable),
        effects: DashboardActionEffectProbeV0(),
        diagnostics: DashboardDiagnosticProbeV0(
            value: try dashboardDiagnosticExportV0()
        )
    )
    await coordinator.applicationInvalidated()

    await #expect(
        throws: MacAgentDashboardActionCoordinatorErrorV0
            .applicationInvalidated
    ) {
        _ = try await coordinator.perform(.retryStatus)
    }
    #expect(await coordinator.snapshot() == .invalidated)
}

private actor DashboardPairingClientV0: MacPairingLocalIPCClientV0 {
    private let shouldFail: Bool

    init(shouldFail: Bool) { self.shouldFail = shouldFail }

    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        guard !shouldFail else { throw DashboardActionTestErrorV0.injected }
        let createdAt: Int64 = 1_787_198_400_000
        let pairingID = UUID()
        let payload = try PairingQRCodePayload(
            pairingID: WireUUID(pairingID),
            oneTimeSecret: WireBytes32(Data(repeating: 0x6a, count: 32)),
            expiresAtUnixMilliseconds: createdAt + 300_000,
            hostFingerprint: WireFingerprint(Data(repeating: 0xb4, count: 32)),
            endpoints: [
                try EndpointCandidate(
                    kind: .bonjour,
                    value: "studio._maccompanion._tcp.local.",
                    port: 47_474
                ),
            ]
        )
        return try LocalPairingSessionCreatedReceiptV0(
            correlationID: command.commandID,
            pairingID: pairingID,
            encodedQRCode: PairingQRCodeCodec.encode(payload),
            createdAtUnixMilliseconds: createdAt,
            expiresAtUnixMilliseconds: createdAt + 300_000
        )
    }

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        throw DashboardActionTestErrorV0.injected
    }
}

private struct DashboardPairingClockV0: MacPairingWallClockV0 {
    func nowUnixMilliseconds() -> Int64 { 1_787_198_400_000 }
}

private final class DashboardPairingCancellationV0:
    MacPairingExpiryCancellationV0,
    @unchecked Sendable
{
    func cancel() {}
}

private struct DashboardPairingSchedulerV0: MacPairingExpirySchedulingV0 {
    func schedule(
        afterMilliseconds: Int64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacPairingExpiryCancellationV0 {
        DashboardPairingCancellationV0()
    }
}

@Test func existingPairingOwnerReportsOnlyVisiblePresentationAsCompleted()
    async throws
{
    let success = MacPairingApplicationOwnerV0(
        client: DashboardPairingClientV0(shouldFail: false),
        clock: DashboardPairingClockV0(),
        expiryScheduler: DashboardPairingSchedulerV0()
    )
    #expect(await success.startPairingFromDashboard() == .completed)
    #expect(await success.snapshot().visibleReceipt != nil)

    let failure = MacPairingApplicationOwnerV0(
        client: DashboardPairingClientV0(shouldFail: true),
        clock: DashboardPairingClockV0(),
        expiryScheduler: DashboardPairingSchedulerV0()
    )
    #expect(await failure.startPairingFromDashboard() == .notCompleted)
    #expect(await failure.snapshot().visibleReceipt == nil)
}
