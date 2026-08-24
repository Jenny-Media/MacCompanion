#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionAgent
import CompanionLifecycle
import CompanionLocalXPCPlatform
import Foundation
import Testing

@Test
@available(macOS 26.0, *)
func updateAgentPlatformMapsEveryRegistrationStateClosed() {
    #expect(
        MacUpdateAgentReactivationPlatformV0.map(.notRegistered)
            == .notRegistered
    )
    #expect(
        MacUpdateAgentReactivationPlatformV0.map(.enabled) == .enabled
    )
    #expect(
        MacUpdateAgentReactivationPlatformV0.map(.requiresApproval)
            == .requiresApproval
    )
    #expect(
        MacUpdateAgentReactivationPlatformV0.map(.notFound)
            == .unavailable
    )
    #expect(
        MacUpdateAgentReactivationPlatformV0.map(.unknown)
            == .unavailable
    )
}

@Test
@available(macOS 26.0, *)
func updateAgentPlatformForwardsPersistenceBuildAndConvergedEffects() async throws {
    let receipt = try MacUpdateAgentReactivationReceiptV0(
        sourceBuild: 10,
        candidateBuild: 11,
        phase: .prepared
    )
    let role = UpdateAgentRoleV0(state: .enabled)
    let persistence = UpdateAgentPersistenceV0(receipt: receipt)
    let platform = MacUpdateAgentReactivationPlatformV0(
        registration: role,
        service: role,
        persistence: persistence,
        currentAgentBuild: { 10 }
    )
    let dependencies = platform.dependencies()

    #expect(await dependencies.registrationState() == .enabled)
    #expect(try await dependencies.currentReceipt() == receipt)
    #expect(try await dependencies.currentAgentBuild() == 10)
    try await dependencies.unregisterAndWait()
    try await dependencies.registerAndWait()
    #expect(await role.counts() == (register: 1, unregister: 1))
    #expect(try await dependencies.clearReceipt(receipt))
    #expect(try await dependencies.currentReceipt() == nil)
}

@Test
@available(macOS 26.0, *)
func updateAgentRuntimePlatformUsesOnlyActiveDashboardBuild() async throws {
    let role = UpdateAgentRoleV0(state: .enabled)
    let persistence = UpdateAgentPersistenceV0(receipt: nil)
    let activeAgentBuild = MacAuthenticatedAgentBuildLifetimeV0()
    let platform = MacUpdateAgentReactivationPlatformV0(
        registration: role,
        service: role,
        persistence: persistence,
        activeAgentBuild: activeAgentBuild
    )
    let dependencies = platform.dependencies()

    #expect(try await dependencies.currentAgentBuild() == nil)
    try activeAgentBuild.authenticate(build: 42)
    #expect(try await dependencies.currentAgentBuild() == 42)
    activeAgentBuild.retire()
    #expect(try await dependencies.currentAgentBuild() == nil)
}

@Test
@available(macOS 26.0, *)
func updateAgentPlatformRepairsOnlyAnEnabledRegistration() async throws {
    let role = UpdateAgentRoleV0(state: .enabled)
    let platform = MacUpdateAgentReactivationPlatformV0(
        registration: role,
        service: role,
        persistence: UpdateAgentPersistenceV0(receipt: nil),
        currentAgentBuild: { nil }
    )

    try await platform.repairEnabledRegistration()

    #expect(await role.status() == .enabled)
    #expect(await role.counts() == (register: 1, unregister: 1))
}

@Test
@available(macOS 26.0, *)
func updateAgentPlatformRefusesToEnableAUserDisabledRegistration()
async throws {
    let role = UpdateAgentRoleV0(state: .notRegistered)
    let platform = MacUpdateAgentReactivationPlatformV0(
        registration: role,
        service: role,
        persistence: UpdateAgentPersistenceV0(receipt: nil),
        currentAgentBuild: { nil }
    )

    await #expect(
        throws: MacUpdateAgentRegistrationRepairErrorV0
            .registrationNotEnabled
    ) {
        try await platform.repairEnabledRegistration()
    }

    #expect(await role.status() == .notRegistered)
    #expect(await role.counts() == (register: 0, unregister: 0))
}

@Test
@available(macOS 26.0, *)
func updateAgentReadinessRetriesLaunchRacesWithExactDelay() async throws {
    let script = UpdateAgentBuildProbeScriptV0(
        results: [
            .failure(MacLocalXPCAgentBuildProbeErrorV0.startFailed),
            .failure(MacLocalXPCAgentBuildProbeErrorV0.invalidated),
            .success(42),
        ]
    )
    let readiness = try MacUpdateAgentBuildReadinessV0(
        maximumAttempts: 4,
        retryDelayNanoseconds: 7,
        probe: { try await script.next() },
        pause: { await script.pause($0) }
    )

    #expect(try await readiness.readBuild() == 42)
    #expect(await script.snapshot() == (attempts: 3, delays: [7, 7]))
}

@Test
@available(macOS 26.0, *)
func updateAgentReadinessDoesNotRetryProtocolViolation() async throws {
    let script = UpdateAgentBuildProbeScriptV0(
        results: [
            .failure(MacLocalXPCAgentBuildProbeErrorV0.unexpectedEvent),
            .success(42),
        ]
    )
    let readiness = try MacUpdateAgentBuildReadinessV0(
        maximumAttempts: 4,
        retryDelayNanoseconds: 7,
        probe: { try await script.next() },
        pause: { await script.pause($0) }
    )

    await #expect(throws: MacUpdateAgentBuildReadinessErrorV0.unavailable) {
        try await readiness.readBuild()
    }
    #expect(await script.snapshot() == (attempts: 1, delays: []))
}

@Test
@available(macOS 26.0, *)
func updateAgentReadinessDoesNotRetryUnknownFailure() async throws {
    let script = UpdateAgentBuildProbeScriptV0(
        results: [
            .failure(UpdateAgentReadinessTestErrorV0.unknown),
            .success(42),
        ]
    )
    let readiness = try MacUpdateAgentBuildReadinessV0(
        maximumAttempts: 4,
        retryDelayNanoseconds: 7,
        probe: { try await script.next() },
        pause: { await script.pause($0) }
    )

    await #expect(throws: MacUpdateAgentBuildReadinessErrorV0.unavailable) {
        try await readiness.readBuild()
    }
    #expect(await script.snapshot() == (attempts: 1, delays: []))
}

@Test
@available(macOS 26.0, *)
func updateAgentReadinessPreservesCancellation() async throws {
    let script = UpdateAgentBuildProbeScriptV0(
        results: [.failure(CancellationError())]
    )
    let readiness = try MacUpdateAgentBuildReadinessV0(
        maximumAttempts: 4,
        retryDelayNanoseconds: 7,
        probe: { try await script.next() },
        pause: { await script.pause($0) }
    )

    await #expect(throws: CancellationError.self) {
        try await readiness.readBuild()
    }
    #expect(await script.snapshot() == (attempts: 1, delays: []))
}

@Test
@available(macOS 26.0, *)
func updateAgentReadinessExhaustsAndValidatesPolicy() async throws {
    let script = UpdateAgentBuildProbeScriptV0(
        results: Array(
            repeating: .failure(
                MacLocalXPCAgentBuildProbeErrorV0.timedOut
            ),
            count: 3
        )
    )
    let readiness = try MacUpdateAgentBuildReadinessV0(
        maximumAttempts: 3,
        retryDelayNanoseconds: 9,
        probe: { try await script.next() },
        pause: { await script.pause($0) }
    )
    await #expect(throws: MacUpdateAgentBuildReadinessErrorV0.unavailable) {
        try await readiness.readBuild()
    }
    #expect(await script.snapshot() == (attempts: 3, delays: [9, 9]))
    #expect(throws: MacUpdateAgentBuildReadinessErrorV0.invalidPolicy) {
        try MacUpdateAgentBuildReadinessV0(
            maximumAttempts: 0,
            retryDelayNanoseconds: 1
        )
    }
}

private enum UpdateAgentReadinessTestErrorV0: Error {
    case unknown
}

@available(macOS 26.0, *)
private actor UpdateAgentRoleV0:
    AgentLoginRoleRawServiceV1,
    AgentLoginRoleServiceV1
{
    private var state: AgentLoginRoleRegistrationStateV1
    private var registerCount = 0
    private var unregisterCount = 0

    init(state: AgentLoginRoleRegistrationStateV1) {
        self.state = state
    }

    func status() -> AgentLoginRoleRegistrationStateV1 { state }
    func register() {
        registerCount += 1
        state = .enabled
    }
    func unregister() {
        unregisterCount += 1
        state = .notRegistered
    }
    func unregisterAndWait() { unregister() }

    func counts() -> (register: Int, unregister: Int) {
        (registerCount, unregisterCount)
    }
}

private actor UpdateAgentPersistenceV0:
    MacUpdateAgentReactivationPersistenceV0
{
    private var receipt: MacUpdateAgentReactivationReceiptV0?

    init(receipt: MacUpdateAgentReactivationReceiptV0?) {
        self.receipt = receipt
    }

    func current() -> MacUpdateAgentReactivationReceiptV0? { receipt }

    func replace(
        expected: MacUpdateAgentReactivationReceiptV0?,
        with replacement: MacUpdateAgentReactivationReceiptV0
    ) -> Bool {
        guard receipt == expected else { return false }
        receipt = replacement
        return true
    }

    func clear(expected: MacUpdateAgentReactivationReceiptV0) -> Bool {
        guard receipt == expected else { return false }
        receipt = nil
        return true
    }
}

private actor UpdateAgentBuildProbeScriptV0 {
    private var results: [Result<UInt64, Error>]
    private var attempts = 0
    private var delays: [UInt64] = []

    init(results: [Result<UInt64, Error>]) {
        self.results = results
    }

    func next() throws -> UInt64 {
        attempts += 1
        guard !results.isEmpty else {
            throw MacLocalXPCAgentBuildProbeErrorV0.invalidated
        }
        return try results.removeFirst().get()
    }

    func pause(_ delay: UInt64) { delays.append(delay) }

    func snapshot() -> (attempts: Int, delays: [UInt64]) {
        (attempts, delays)
    }
}
#endif
