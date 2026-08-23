#if os(macOS)
import CompanionAgent
@testable import CompanionAgentApplicationPlatform
import CompanionAgentPlatform
import CompanionAgentProductPlatform
import CompanionLifecycle
import Foundation
import Testing

private enum AgentLocalServiceStartupTestErrorV1: Error, Equatable {
    case selectedStart
}

private final class AgentLocalServiceStartupProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ value: String) {
        lock.withLock { values.append(value) }
    }

    func snapshot() -> [String] {
        lock.withLock { values }
    }
}

private actor AgentLocalServiceOneShotGateV1 {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func enterAndWait() async throws {
        entered = true
        let entryWaiters = self.entryWaiters
        self.entryWaiters.removeAll()
        entryWaiters.forEach { $0.resume() }
        guard !released else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { releaseWaiters.append($0) }
        } onCancel: {
            Task { await self.release() }
        }
        try Task.checkCancellation()
    }

    func release() {
        guard !released else { return }
        released = true
        let releaseWaiters = self.releaseWaiters
        self.releaseWaiters.removeAll()
        releaseWaiters.forEach { $0.resume() }
    }
}

@available(macOS 26.0, *)
private final class AgentLocalServiceTestRuntimeV1:
    @unchecked Sendable,
    MacCompanionAgentSelectedServiceRuntimeV1
{
    private let probe: AgentLocalServiceStartupProbeV1
    private let label: String
    private let onStart: @Sendable () async throws -> Void
    private let lock = NSLock()
    private var finished = false

    init(
        label: String,
        probe: AgentLocalServiceStartupProbeV1,
        onStart: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.label = label
        self.probe = probe
        self.onStart = onStart
    }

    func start() async throws {
        probe.record("\(label).start")
        try await onStart()
    }

    func finish() async {
        let shouldRecord = lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
        if shouldRecord { probe.record("\(label).finish") }
    }
}

private func agentLocalServiceTemporaryBaseV1() throws -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-local-service-startup-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return base
}

@available(macOS 26.0, *)
private func agentLocalServicePreparedOwnerV1(
    base: URL,
    enabled: Bool,
    revision: UInt64 = 0,
    agentObservationEpoch: UInt64 = 0,
    menuAppObservationEpoch: UInt64 = 0,
    probe: AgentLocalServiceStartupProbeV1,
    startLocalService: @escaping @Sendable () async throws -> Void = {}
) throws -> MacCompanionAgentInertSystemOwnerV1 {
    let storage = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    let intentStore = try AtomicFileMacRemoteAccessIntentStoreV1(
        directory: storage.paths.remoteAccessIntentDirectory
    )
    let processState: ManagedProcessState = enabled ? .starting : .stopped
    let state = ProductLifecycleState(
        desiredEnabled: enabled,
        consoleSession: .otherConsoleUserActive,
        agent: processState,
        menuApp: processState
    )
    let prepared = MacAgentPreparedProductHandleV1(
        hostID: UUID(
            uuidString: "018f6000-0000-7000-8000-000000000002"
        )!,
        storagePaths: storage.paths,
        currentLifecycle: {
            AgentRemoteLifecycleSnapshotV1(
                revision: revision,
                agentObservationEpoch: agentObservationEpoch,
                menuAppObservationEpoch: menuAppObservationEpoch,
                state: state
            )
        },
        startLocalService: {
            probe.record("status.start")
            try await startLocalService()
        },
        finish: { probe.record("prepared.finish") }
    )
    return MacCompanionAgentInertSystemOwnerV1(
        prepared: MacAgentInertApplicationLifecycleV1(
            requestContexts: MacAgentConservativeRequestContextProductV1(),
            prepared: prepared,
            intentStore: intentStore
        )
    )
}

@available(macOS 26.0, *)
private func runningOwnerV1(
    _ outcome: MacCompanionAgentLocalServiceStartupOutcomeV1
) -> MacCompanionAgentLocalServiceOwnerV1? {
    guard case let .running(owner) = outcome else { return nil }
    return owner
}

@available(macOS 26.0, *)
@Test func preparationMappingPreservesReadyAndEveryClosedDeferral()
    async throws
{
    let base = try agentLocalServiceTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let probe = AgentLocalServiceStartupProbeV1()
    let storage = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    guard case let .ready(owner) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .prepared(MacAgentInertApplicationLifecycleV1(
                requestContexts:
                    MacAgentConservativeRequestContextProductV1(),
                prepared: MacAgentPreparedProductHandleV1(
                    hostID: UUID(),
                    storagePaths: storage.paths,
                    currentLifecycle: {
                        AgentRemoteLifecycleSnapshotV1(
                            revision: 0,
                            state: ProductLifecycleState(
                                consoleSession: .otherConsoleUserActive
                            )
                        )
                    },
                    finish: { probe.record("prepared.finish") }
                ),
                intentStore: try AtomicFileMacRemoteAccessIntentStoreV1(
                    directory: storage.paths.remoteAccessIntentDirectory
                )
            ))
        )
    else {
        Issue.record("expected ready preparation")
        return
    }
    await owner.finish()
    #expect(probe.snapshot() == ["prepared.finish"])

    let recoveryProduct = MacAgentHostIdentityRecoveryProductV1(
        storage: storage,
        hostIdentityConfiguration:
            try MacCompanionAgentInertSystemPreparationV1.makeInputs(
                registryGeneration: UUID(),
                wallNowUnixMilliseconds: 1
            ).hostIdentityConfiguration,
        mode: .fresh(.invalidEstablishedKey)
    )
    guard case let .recovery(mappedRecovery) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .hostIdentityRecovery(recoveryProduct)
        )
    else {
        Issue.record("expected recovery service preparation")
        return
    }
    #expect(mappedRecovery === recoveryProduct)
    await mappedRecovery.finish()

    guard case .deferred(.firstUnlockRequired) =
        MacCompanionAgentInertSystemPreparationV1.map(.waitForFirstUnlock)
    else {
        Issue.record("expected first-unlock deferral")
        return
    }
    guard case .deferred(.localRecoveryRequired) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .requireLocalRecovery(.invalidEstablishedKey)
        )
    else {
        Issue.record("expected local recovery")
        return
    }
    guard case .deferred(.recoveryFenced) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .recoveryFenced(UUID())
        )
    else {
        Issue.record("expected recovery fence")
        return
    }
}

@available(macOS 26.0, *)
@Test func enabledStartsReadinessWhileDisabledStartsOnlyBootstrap()
    async throws
{
    for enabled in [true, false] {
        let base = try agentLocalServiceTemporaryBaseV1()
        defer { try? FileManager.default.removeItem(at: base) }
        let probe = AgentLocalServiceStartupProbeV1()
        let prepared = try agentLocalServicePreparedOwnerV1(
            base: base,
            enabled: enabled,
            probe: probe
        )
        let outcome = try await MacCompanionAgentLocalServiceStartupV1.start(
            prepare: { .ready(prepared) },
            makeAuthenticationOnly: {
                probe.record("auth.construct")
                return AgentLocalServiceTestRuntimeV1(
                    label: "auth",
                    probe: probe
                )
            },
            makeDisabledBootstrap: { _, _ in
                probe.record("bootstrap.construct")
                return AgentLocalServiceTestRuntimeV1(
                    label: "bootstrap",
                    probe: probe
                )
            }
        )
        let owner = try #require(runningOwnerV1(outcome))
        await owner.finish()
        await owner.finish()
        #expect(
            probe.snapshot() == (enabled
                ? ["status.start", "prepared.finish"]
                : [
                    "bootstrap.construct", "bootstrap.start",
                    "bootstrap.finish",
                    "prepared.finish",
                ])
        )
    }
}

@available(macOS 26.0, *)
@Test func injectedLegacyRecoveryDeferralsStayClosedAndFirstUnlockIsInert()
    async throws
{
    for result in [
        MacCompanionAgentInertSystemPreparationResultV1.deferred(
            .localRecoveryRequired
        ),
        .deferred(.recoveryFenced),
    ] {
        let probe = AgentLocalServiceStartupProbeV1()
        let outcome = try await MacCompanionAgentLocalServiceStartupV1.start(
            prepare: { result },
            makeAuthenticationOnly: {
                probe.record("auth.construct")
                return AgentLocalServiceTestRuntimeV1(
                    label: "auth",
                    probe: probe
                )
            }
        )
        let owner = try #require(runningOwnerV1(outcome))
        await owner.finish()
        #expect(probe.snapshot() == [
            "auth.construct", "auth.start", "auth.finish",
        ])
    }

    let firstUnlockProbe = AgentLocalServiceStartupProbeV1()
    let firstUnlock = try await MacCompanionAgentLocalServiceStartupV1.start(
        prepare: { .deferred(.firstUnlockRequired) },
        makeAuthenticationOnly: {
            firstUnlockProbe.record("auth.construct")
            return AgentLocalServiceTestRuntimeV1(
                label: "auth",
                probe: firstUnlockProbe
            )
        }
    )
    guard case .retryAfterFirstUnlock = firstUnlock else {
        Issue.record("expected retry after first unlock")
        return
    }
    #expect(firstUnlockProbe.snapshot().isEmpty)
}

@available(macOS 26.0, *)
@Test func disabledBootstrapRestartRequestIsLatchedForTheProcessOwner()
    async throws
{
    let base = try agentLocalServiceTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let probe = AgentLocalServiceStartupProbeV1()
    let prepared = try agentLocalServicePreparedOwnerV1(
        base: base,
        enabled: false,
        probe: probe
    )
    let outcome = try await MacCompanionAgentLocalServiceStartupV1.start(
        prepare: { .ready(prepared) },
        makeAuthenticationOnly: {
            AgentLocalServiceTestRuntimeV1(label: "auth", probe: probe)
        },
        makeDisabledBootstrap: { _, restartRequest in
            AgentLocalServiceTestRuntimeV1(
                label: "bootstrap",
                probe: probe,
                onStart: { await restartRequest.request() }
            )
        }
    )
    let owner = try #require(runningOwnerV1(outcome))
    await owner.waitForRestartRequest()
    await owner.finish()
    #expect(probe.snapshot() == [
        "bootstrap.start", "bootstrap.finish", "prepared.finish",
    ])
}

@available(macOS 26.0, *)
@Test func selectedStartFailuresRetirePreparationAndNeverFallBack()
    async throws
{
    for enabled in [true, false] {
        let base = try agentLocalServiceTemporaryBaseV1()
        defer { try? FileManager.default.removeItem(at: base) }
        let probe = AgentLocalServiceStartupProbeV1()
        let prepared = try agentLocalServicePreparedOwnerV1(
            base: base,
            enabled: enabled,
            probe: probe,
            startLocalService: {
                throw AgentLocalServiceStartupTestErrorV1.selectedStart
            }
        )
        await #expect(throws: AgentLocalServiceStartupTestErrorV1.selectedStart) {
            try await MacCompanionAgentLocalServiceStartupV1.start(
                prepare: { .ready(prepared) },
                makeAuthenticationOnly: {
                    probe.record("auth.construct")
                    return AgentLocalServiceTestRuntimeV1(
                        label: "auth",
                        probe: probe,
                        onStart: {
                            throw AgentLocalServiceStartupTestErrorV1
                                .selectedStart
                        }
                    )
                },
                makeDisabledBootstrap: { _, _ in
                    probe.record("bootstrap.construct")
                    return AgentLocalServiceTestRuntimeV1(
                        label: "bootstrap",
                        probe: probe,
                        onStart: {
                            throw AgentLocalServiceStartupTestErrorV1
                                .selectedStart
                        }
                    )
                }
            )
        }
        #expect(
            probe.snapshot() == (enabled
                ? ["status.start", "prepared.finish"]
                : [
                    "bootstrap.construct", "bootstrap.start",
                    "bootstrap.finish",
                    "prepared.finish",
                ])
        )
    }
}

@available(macOS 26.0, *)
@Test func noncanonicalReadySnapshotFailsBeforeEitherServiceStarts()
    async throws
{
    for (revision, agentEpoch, menuEpoch) in [
        (UInt64(1), UInt64(0), UInt64(0)),
        (UInt64(0), UInt64(1), UInt64(0)),
        (UInt64(0), UInt64(0), UInt64(1)),
    ] {
        let base = try agentLocalServiceTemporaryBaseV1()
        defer { try? FileManager.default.removeItem(at: base) }
        let probe = AgentLocalServiceStartupProbeV1()
        let prepared = try agentLocalServicePreparedOwnerV1(
            base: base,
            enabled: true,
            revision: revision,
            agentObservationEpoch: agentEpoch,
            menuAppObservationEpoch: menuEpoch,
            probe: probe
        )
        await #expect(throws: MacAgentApplicationPreparationErrorV1.self) {
            try await MacCompanionAgentLocalServiceStartupV1.start(
                prepare: { .ready(prepared) },
                makeAuthenticationOnly: {
                    probe.record("auth.construct")
                    return AgentLocalServiceTestRuntimeV1(
                        label: "auth",
                        probe: probe
                    )
                }
            )
        }
        #expect(probe.snapshot() == ["prepared.finish"])
    }
}

@available(macOS 26.0, *)
@Test func cancellationImmediatelyAfterReadyPreparationRetiresOwner()
    async throws
{
    let base = try agentLocalServiceTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let probe = AgentLocalServiceStartupProbeV1()
    let prepared = try agentLocalServicePreparedOwnerV1(
        base: base,
        enabled: true,
        probe: probe
    )
    let startup = Task {
        try await MacCompanionAgentLocalServiceStartupV1.start(
            prepare: {
                withUnsafeCurrentTask { $0?.cancel() }
                return .ready(prepared)
            },
            makeAuthenticationOnly: {
                probe.record("auth.construct")
                return AgentLocalServiceTestRuntimeV1(
                    label: "auth",
                    probe: probe
                )
            }
        )
    }
    await #expect(throws: CancellationError.self) {
        _ = try await startup.value
    }
    #expect(probe.snapshot() == ["prepared.finish"])
}

@available(macOS 26.0, *)
@Test func callerCancellationDuringSelectedStartJoinsTerminalCleanup()
    async throws
{
    let base = try agentLocalServiceTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let probe = AgentLocalServiceStartupProbeV1()
    let gate = AgentLocalServiceOneShotGateV1()
    let prepared = try agentLocalServicePreparedOwnerV1(
        base: base,
        enabled: true,
        probe: probe,
        startLocalService: { try await gate.enterAndWait() }
    )
    let startup = Task {
        try await MacCompanionAgentLocalServiceStartupV1.start(
            prepare: { .ready(prepared) },
            makeAuthenticationOnly: {
                probe.record("auth.construct")
                return AgentLocalServiceTestRuntimeV1(
                    label: "auth",
                    probe: probe
                )
            }
        )
    }
    await gate.waitUntilEntered()
    startup.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await startup.value
    }
    #expect(probe.snapshot() == ["status.start", "prepared.finish"])
}

@available(macOS 26.0, *)
@Test func runningOwnerConcurrentFinishSharesOneCompleteBarrier()
    async throws
{
    let probe = AgentLocalServiceStartupProbeV1()
    let runtime = AgentLocalServiceTestRuntimeV1(
        label: "auth",
        probe: probe
    )
    let outcome = try await MacCompanionAgentLocalServiceStartupV1.start(
        prepare: { .deferred(.localRecoveryRequired) },
        makeAuthenticationOnly: { runtime }
    )
    let owner = try #require(runningOwnerV1(outcome))
    async let first: Void = owner.finish()
    async let second: Void = owner.finish()
    _ = await (first, second)
    #expect(probe.snapshot() == ["auth.start", "auth.finish"])
}
#endif
