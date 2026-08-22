#if os(macOS)
import CompanionAgent
@testable import CompanionAgentApplicationPlatform
import CompanionAgentPlatform
import CompanionAgentProductPlatform
import CompanionLifecycle
import Foundation
import Testing

private enum InertStartupTestErrorV1: Error, Equatable {
    case preparation
    case authentication
}

private final class InertStartupProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@available(macOS 26.0, *)
private func inertStartupPreparedLifecycleV1(
    base: URL,
    finishProbe: InertStartupProbeV1
) throws -> MacAgentInertApplicationLifecycleV1 {
    let storage = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    let state = ProductLifecycleState(
        consoleSession: .otherConsoleUserActive
    )
    let prepared = MacAgentPreparedProductHandleV1(
        hostID: UUID(
            uuidString: "018f6000-0000-7000-8000-000000000002"
        )!,
        storagePaths: storage.paths,
        currentLifecycle: {
            AgentRemoteLifecycleSnapshotV1(revision: 0, state: state)
        },
        finish: { finishProbe.record("finish") }
    )
    return MacAgentInertApplicationLifecycleV1(
        requestContexts: MacAgentConservativeRequestContextProductV1(),
        prepared: prepared
    )
}

@available(macOS 26.0, *)
private func inertStartupPreparedOwnerV1(
    base: URL,
    finishProbe: InertStartupProbeV1
) throws -> MacCompanionAgentInertSystemOwnerV1 {
    MacCompanionAgentInertSystemOwnerV1(
        prepared: try inertStartupPreparedLifecycleV1(
            base: base,
            finishProbe: finishProbe
        )
    )
}

private func inertStartupTemporaryBaseV1() throws -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-inert-startup-\(UUID())",
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
@Test func preparationMappingPreservesReadyAndEveryClosedDeferral()
    async throws
{
    let base = try inertStartupTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let finishProbe = InertStartupProbeV1()
    guard case let .ready(owner) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .prepared(try inertStartupPreparedLifecycleV1(
                base: base,
                finishProbe: finishProbe
            ))
        )
    else {
        Issue.record("expected ready preparation")
        return
    }
    await owner.finish()
    #expect(finishProbe.snapshot() == ["finish"])

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
        Issue.record("expected local-recovery deferral")
        return
    }
    let recoveryID = UUID()
    guard case .deferred(.recoveryFenced) =
        MacCompanionAgentInertSystemPreparationV1.map(
            .recoveryFenced(recoveryID)
        )
    else {
        Issue.record("expected recovery-fenced deferral")
        return
    }
}

@available(macOS 26.0, *)
@Test func startupRetriesOnlyFirstUnlockAndIdlesDurableRecovery()
    async throws
{
    let firstUnlockProbe = InertStartupProbeV1()
    let firstUnlock = try await
        MacCompanionAgentInertStartupCoordinatorV1
            .prepareAndStartAuthentication(
                prepare: {
                    firstUnlockProbe.record("prepare")
                    return .deferred(.firstUnlockRequired)
                },
                startAuthentication: {
                    firstUnlockProbe.record("authentication")
                }
            )
    guard case .retryAfterFirstUnlock = firstUnlock else {
        Issue.record("expected retry-after-first-unlock")
        return
    }
    #expect(firstUnlockProbe.snapshot() == ["prepare"])

    for reason in [
        MacCompanionAgentInertPreparationDeferralV1.localRecoveryRequired,
        .recoveryFenced,
    ] {
        let probe = InertStartupProbeV1()
        let retention = try await
            MacCompanionAgentInertStartupCoordinatorV1
                .prepareAndStartAuthentication(
                    prepare: {
                        probe.record("prepare")
                        return .deferred(reason)
                    },
                    startAuthentication: {
                        probe.record("authentication")
                    }
                )
        guard case let .authenticationOnly(retainedReason) = retention else {
            Issue.record("expected authentication-only recovery wait")
            return
        }
        #expect(retainedReason == reason)
        #expect(probe.snapshot() == ["prepare", "authentication"])
    }
}

@available(macOS 26.0, *)
@Test func startupOrdersReadyAuthenticationAndCompensatesStartFailure()
    async throws
{
    let base = try inertStartupTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let finishProbe = InertStartupProbeV1()
    let owner = try inertStartupPreparedOwnerV1(
        base: base,
        finishProbe: finishProbe
    )
    let order = InertStartupProbeV1()
    let retention = try await MacCompanionAgentInertStartupCoordinatorV1
        .prepareAndStartAuthentication(
            prepare: {
                order.record("prepare")
                return .ready(owner)
            },
            startAuthentication: {
                order.record("authentication")
            }
        )
    guard case let .prepared(retainedOwner) = retention else {
        Issue.record("expected prepared retention")
        return
    }
    #expect(order.snapshot() == ["prepare", "authentication"])
    #expect(finishProbe.snapshot().isEmpty)
    await retainedOwner.finish()
    await retainedOwner.finish()
    #expect(finishProbe.snapshot() == ["finish"])

    let failureBase = try inertStartupTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: failureBase) }
    let failureFinishProbe = InertStartupProbeV1()
    let failureOwner = try inertStartupPreparedOwnerV1(
        base: failureBase,
        finishProbe: failureFinishProbe
    )
    await #expect(throws: InertStartupTestErrorV1.authentication) {
        try await MacCompanionAgentInertStartupCoordinatorV1
            .prepareAndStartAuthentication(
                prepare: { .ready(failureOwner) },
                startAuthentication: {
                    throw InertStartupTestErrorV1.authentication
                }
            )
    }
    #expect(failureFinishProbe.snapshot() == ["finish"])
}

@available(macOS 26.0, *)
@Test func startupPreparationFailureNeverStartsAuthentication() async {
    let probe = InertStartupProbeV1()
    await #expect(throws: InertStartupTestErrorV1.preparation) {
        try await MacCompanionAgentInertStartupCoordinatorV1
            .prepareAndStartAuthentication(
                prepare: {
                    probe.record("prepare")
                    throw InertStartupTestErrorV1.preparation
                },
                startAuthentication: {
                    probe.record("authentication")
                }
            )
    }
    #expect(probe.snapshot() == ["prepare"])
}

@available(macOS 26.0, *)
@Test func narrowOwnerDeinitBeginsPreparedRetirement() async throws {
    let base = try inertStartupTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let probe = InertStartupProbeV1()
    var owner: MacCompanionAgentInertSystemOwnerV1? =
        try inertStartupPreparedOwnerV1(base: base, finishProbe: probe)
    #expect(owner != nil)
    owner = nil
    for _ in 0..<100 where probe.snapshot().isEmpty {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(probe.snapshot() == ["finish"])
}
#endif
