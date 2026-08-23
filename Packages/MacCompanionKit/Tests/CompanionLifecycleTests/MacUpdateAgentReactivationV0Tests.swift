@testable import CompanionLifecycle
import Testing

private enum UpdateAgentHarnessFailureV0: Error {
    case injected
}

private enum UpdateAgentHarnessFaultV0: Equatable {
    case readReceipt
    case writePreparedConflict
    case writeStoppedConflict
    case unregister
    case register
    case clearConflict
    case observeBuild
}

private actor UpdateAgentHarnessV0 {
    private var registration: MacUpdateAgentRegistrationStateV0
    private var receipt: MacUpdateAgentReactivationReceiptV0?
    private var agentBuild: UInt64?
    private let fault: UpdateAgentHarnessFaultV0?
    private var events: [String] = []

    init(
        registration: MacUpdateAgentRegistrationStateV0 = .enabled,
        receipt: MacUpdateAgentReactivationReceiptV0? = nil,
        agentBuild: UInt64? = 10,
        fault: UpdateAgentHarnessFaultV0? = nil
    ) {
        self.registration = registration
        self.receipt = receipt
        self.agentBuild = agentBuild
        self.fault = fault
    }

    func dependencies() -> MacUpdateAgentReactivationDependenciesV0 {
        MacUpdateAgentReactivationDependenciesV0(
            registrationState: { await self.registrationState() },
            currentReceipt: { try await self.readReceipt() },
            replaceReceipt: { expected, replacement in
                try await self.replace(
                    expected: expected,
                    replacement: replacement
                )
            },
            clearReceipt: { expected in
                try await self.clear(expected: expected)
            },
            currentAgentBuild: { try await self.observeBuild() },
            unregisterAndWait: { try await self.unregister() },
            registerAndWait: { try await self.register() }
        )
    }

    func snapshot() -> (
        MacUpdateAgentRegistrationStateV0,
        MacUpdateAgentReactivationReceiptV0?,
        [String]
    ) {
        (registration, receipt, events)
    }

    private func registrationState()
        -> MacUpdateAgentRegistrationStateV0
    {
        events.append("status")
        return registration
    }

    private func readReceipt() throws
        -> MacUpdateAgentReactivationReceiptV0?
    {
        events.append("readReceipt")
        if fault == .readReceipt {
            throw UpdateAgentHarnessFailureV0.injected
        }
        return receipt
    }

    private func replace(
        expected: MacUpdateAgentReactivationReceiptV0?,
        replacement: MacUpdateAgentReactivationReceiptV0
    ) throws -> Bool {
        events.append("write:\(replacement.phase.rawValue)")
        if replacement.phase == .prepared,
           fault == .writePreparedConflict {
            return false
        }
        if replacement.phase == .agentStopped,
           fault == .writeStoppedConflict {
            return false
        }
        guard receipt == expected else { return false }
        receipt = replacement
        return true
    }

    private func clear(
        expected: MacUpdateAgentReactivationReceiptV0
    ) throws -> Bool {
        events.append("clear")
        if fault == .clearConflict { return false }
        guard receipt == expected else { return false }
        receipt = nil
        return true
    }

    private func observeBuild() throws -> UInt64? {
        events.append("build")
        if fault == .observeBuild {
            throw UpdateAgentHarnessFailureV0.injected
        }
        return agentBuild
    }

    private func unregister() throws {
        events.append("unregister")
        if fault == .unregister {
            throw UpdateAgentHarnessFailureV0.injected
        }
        registration = .notRegistered
    }

    private func register() throws {
        events.append("register")
        if fault == .register {
            throw UpdateAgentHarnessFailureV0.injected
        }
        registration = .enabled
    }
}

private func updateAgentReceiptV0(
    phase: MacUpdateAgentReactivationReceiptPhaseV0 = .agentStopped
) throws -> MacUpdateAgentReactivationReceiptV0 {
    try MacUpdateAgentReactivationReceiptV0(
        sourceBuild: 10,
        candidateBuild: 11,
        phase: phase
    )
}

@Test func updateAgentReceiptRequiresExactProfileAndIncreasingBuild() {
    #expect(throws: MacUpdateAgentReactivationErrorV0.invalidReceipt) {
        _ = try MacUpdateAgentReactivationReceiptV0(
            profile: "changed",
            sourceBuild: 10,
            candidateBuild: 11,
            phase: .prepared
        )
    }
    #expect(throws: MacUpdateAgentReactivationErrorV0.invalidReceipt) {
        _ = try MacUpdateAgentReactivationReceiptV0(
            sourceBuild: 10,
            candidateBuild: 10,
            phase: .prepared
        )
    }
}

@Test func unregisteredAgentNeedsNoReceiptAndRecoveryIsNoOp()
async throws {
    let harness = UpdateAgentHarnessV0(
        registration: .notRegistered,
        agentBuild: nil
    )
    let owner = try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: await harness.dependencies()
    )

    #expect(try await owner.stopForUpdate())
    try await owner.recoverSourceBuild()

    let snapshot = await harness.snapshot()
    #expect(snapshot.0 == .notRegistered)
    #expect(snapshot.1 == nil)
    #expect(snapshot.2 == ["status", "readReceipt"])
    #expect(await owner.currentPhase() == .finished)
}

@Test func exactAgentStopPersistsBeforeUnregisterAndLeavesReceipt()
async throws {
    let harness = UpdateAgentHarnessV0()
    let owner = try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: await harness.dependencies()
    )

    #expect(try await owner.stopForUpdate())

    let snapshot = await harness.snapshot()
    #expect(snapshot.0 == .notRegistered)
    #expect(snapshot.1?.phase == .agentStopped)
    #expect(snapshot.2 == [
        "status", "build", "readReceipt", "write:prepared",
        "unregister", "write:agentStopped",
    ])
    #expect(await owner.currentPhase() == .stopped)
}

@Test func versionMismatchDoesNotMutateRegistrationOrPersistence()
async throws {
    let harness = UpdateAgentHarnessV0(agentBuild: 9)
    let owner = try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: await harness.dependencies()
    )

    #expect(try await owner.stopForUpdate() == false)
    try await owner.recoverSourceBuild()

    let snapshot = await harness.snapshot()
    #expect(snapshot.0 == .enabled)
    #expect(snapshot.1 == nil)
    #expect(snapshot.2 == ["status", "build", "readReceipt"])
}

@Test func failedUnregisterRetainsPreparedReceiptUntilRecovery()
async throws {
    let stoppingHarness = UpdateAgentHarnessV0(fault: .unregister)
    let owner = try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: await stoppingHarness.dependencies()
    )

    await #expect(throws: MacUpdateAgentReactivationErrorV0.effectFailed) {
        _ = try await owner.stopForUpdate()
    }
    #expect(
        await stoppingHarness.snapshot().1?.phase == .prepared
    )
    try await owner.recoverSourceBuild()
    let recovered = await stoppingHarness.snapshot()
    #expect(recovered.0 == .enabled)
    #expect(recovered.1 == nil)
}

@Test func startupReactivatesOnlySourceOrCandidateBuild() async throws {
    for runningBuild: UInt64 in [10, 11] {
        let harness = UpdateAgentHarnessV0(
            registration: .notRegistered,
            receipt: try updateAgentReceiptV0(),
            agentBuild: runningBuild
        )
        let reactivator = MacUpdateAgentStartupReactivatorV0(
            runningBuild: runningBuild,
            dependencies: await harness.dependencies()
        )
        #expect(try await reactivator.reactivateIfNeeded())
        let snapshot = await harness.snapshot()
        #expect(snapshot.0 == .enabled)
        #expect(snapshot.1 == nil)
    }

    let unrelated = UpdateAgentHarnessV0(
        registration: .notRegistered,
        receipt: try updateAgentReceiptV0(),
        agentBuild: 12
    )
    let rejected = MacUpdateAgentStartupReactivatorV0(
        runningBuild: 12,
        dependencies: await unrelated.dependencies()
    )
    await #expect(
        throws: MacUpdateAgentReactivationErrorV0.invalidReceipt
    ) {
        _ = try await rejected.reactivateIfNeeded()
    }
    #expect(await unrelated.snapshot().1 != nil)
}

@Test func recoveryRequiresExactBuildAndReceiptClear() async throws {
    for fault: UpdateAgentHarnessFaultV0 in [
        .register, .observeBuild, .clearConflict,
    ] {
        let harness = UpdateAgentHarnessV0(
            registration: .notRegistered,
            receipt: try updateAgentReceiptV0(),
            agentBuild: 10,
            fault: fault
        )
        let reactivator = MacUpdateAgentStartupReactivatorV0(
            runningBuild: 10,
            dependencies: await harness.dependencies()
        )
        await #expect(throws: MacUpdateAgentReactivationErrorV0.self) {
            _ = try await reactivator.reactivateIfNeeded()
        }
        #expect(await harness.snapshot().1 != nil)
    }

    let mismatch = UpdateAgentHarnessV0(
        registration: .notRegistered,
        receipt: try updateAgentReceiptV0(),
        agentBuild: 9
    )
    let reactivator = MacUpdateAgentStartupReactivatorV0(
        runningBuild: 10,
        dependencies: await mismatch.dependencies()
    )
    await #expect(
        throws: MacUpdateAgentReactivationErrorV0.agentVersionMismatch
    ) {
        _ = try await reactivator.reactivateIfNeeded()
    }
    #expect(await mismatch.snapshot().1 != nil)
}

@Test func concurrentStopCallsReserveOneOwner() async throws {
    let harness = UpdateAgentHarnessV0()
    let owner = try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: await harness.dependencies()
    )

    let first = Task { try? await owner.stopForUpdate() }
    let second = Task { try? await owner.stopForUpdate() }
    let firstOutcome = await first.value
    let secondOutcome = await second.value
    let outcomes = [firstOutcome, secondOutcome]
    #expect(outcomes.compactMap { $0 }.count == 1)
}
