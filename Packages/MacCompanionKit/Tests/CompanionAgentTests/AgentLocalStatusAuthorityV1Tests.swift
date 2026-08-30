import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionIPC
import CompanionLifecycle
import CompanionOperations
import CompanionPersistence
import Foundation
import Testing

private enum LocalStatusSourceTestErrorV1: Error {
    case unavailable
}

private struct FixedPairedDeviceCountV1:
    AgentActivePairedDeviceCountReadingV1
{
    let value: Int

    func activePairedDeviceCount() async throws -> Int { value }
}

private struct FailingPairedDeviceCountV1:
    AgentActivePairedDeviceCountReadingV1
{
    func activePairedDeviceCount() async throws -> Int {
        throw LocalStatusSourceTestErrorV1.unavailable
    }
}

private struct FixedProviderCountV1: AgentActiveProviderCountReadingV1 {
    let value: Int

    func activeProviderCount() async -> Int { value }
}

private func readyLocalStatusLifecycleV1() -> ProductLifecycleState {
    ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .active,
        agent: .ready,
        menuApp: .ready
    )
}

private func makeLocalStatusAuthorityV1() throws
    -> AgentLocalStatusAuthorityV1
{
    try AgentLocalStatusAuthorityV1(
        lifecycle: readyLocalStatusLifecycleV1(),
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 1,
        activeRemoteSessionCount: 0,
        providerCount: 1
    )
}

@Test func localStatusSnapshotDerivesOnlyClosedWarningsFromOneActorVersion() async throws {
    let authority = try AgentLocalStatusAuthorityV1(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .locked,
            agent: .starting,
            menuApp: .starting
        ),
        networkState: .degraded,
        networkWarnings: [.routeUnavailable],
        securityPosture: .denyLatched,
        routeKinds: [.privateNetwork, .lan],
        pairedDeviceCount: 1,
        activeRemoteSessionCount: 0,
        providerCount: 3,
        auditHistoryDegraded: true
    )

    let value = try await authority.snapshot(
        generatedAtUnixMilliseconds: 10
    )

    #expect(value.desiredEnabled)
    #expect(value.consoleSession == .locked)
    #expect(value.agentProcess == .starting)
    #expect(value.menuAppProcess == .starting)
    #expect(value.networkState == .degraded)
    #expect(value.securityPosture == .denyLatched)
    #expect(value.routeKinds == [.lan, .privateNetwork])
    #expect(value.pairedDeviceCount == 1)
    #expect(value.providerCount == 3)
    #expect(value.warningCodes == [
        .agentUnavailable,
        .auditHistoryDegraded,
        .denyLatchArmed,
        .menuAppUnavailable,
        .routeUnavailable,
    ])
    #expect(value.diagnosticSequence == 1)
}

@Test func localStatusRejectsInvalidUpdatesWithoutChangingPriorFactsOrSequence() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    let first = try await authority.snapshot(generatedAtUnixMilliseconds: 1)

    await #expect(throws: AgentLocalStatusAuthorityErrorV1.invalidCount) {
        try await authority.updateNetwork(
            state: .listening,
            activeRemoteSessionCount: 2,
            warningCodes: [],
            generation: 1
        )
    }
    await #expect(
        throws: AgentLocalStatusAuthorityErrorV1.invalidNetworkWarning
    ) {
        try await authority.updateNetwork(
            state: .degraded,
            activeRemoteSessionCount: 0,
            warningCodes: [.captureUnavailable],
            generation: 2
        )
    }
    await #expect(throws: AgentLocalStatusAuthorityErrorV1.invalidCount) {
        try await authority.updateInventory(
            pairedDeviceCount:
                AgentLocalStatusAuthorityV1.maximumPairedDeviceCount + 1,
            providerCount: 1
        )
    }
    await #expect(throws: AgentLocalStatusAuthorityErrorV1.invalidTime) {
        _ = try await authority.snapshot(generatedAtUnixMilliseconds: -1)
    }

    let second = try await authority.snapshot(generatedAtUnixMilliseconds: 2)
    #expect(first.networkState == second.networkState)
    #expect(first.routeKinds == second.routeKinds)
    #expect(first.pairedDeviceCount == second.pairedDeviceCount)
    #expect(first.providerCount == second.providerCount)
    #expect(second.diagnosticSequence == 2)
}

@Test func concurrentLocalStatusReadsReceiveUniqueMonotonicSequences() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    let sequences = try await withThrowingTaskGroup(
        of: UInt64.self,
        returning: [UInt64].self
    ) { group in
        for _ in 0..<32 {
            group.addTask {
                try await authority.snapshot(
                    generatedAtUnixMilliseconds: 10
                ).diagnosticSequence
            }
        }
        var values: [UInt64] = []
        for try await value in group { values.append(value) }
        return values.sorted()
    }

    #expect(sequences == (1...32).map(UInt64.init))
}

@Test func networkProjectionUpdatesOnlyItsOwnedLocalStatusFields() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    try await AgentLocalNetworkStatusPublisherV1(
        status: authority
    ).publish(
        AgentNetworkListenerDiagnosticsV1(
            networkState: .degraded,
            activeRemoteSessionCount: 1,
            warningCodes: [.routeUnavailable]
        )
    )
    await authority.updateSecurityPosture(.storageUnavailable)

    let value = try await authority.snapshot(
        generatedAtUnixMilliseconds: 3
    )
    #expect(value.networkState == .degraded)
    #expect(value.activeRemoteSessionCount == 1)
    #expect(value.securityPosture == .storageUnavailable)
    #expect(value.routeKinds == [.lan])
    #expect(value.pairedDeviceCount == 1)
    #expect(value.providerCount == 1)
    #expect(value.warningCodes == [.routeUnavailable, .storageUnavailable])
}

@Test func delayedNetworkGenerationCannotRollStatusBackward() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    let publisher = AgentLocalNetworkStatusPublisherV1(status: authority)
    let older = try await publisher.reserveGeneration()
    let newer = try await publisher.reserveGeneration()

    try await publisher.publish(
        state: .listening,
        activeRemoteSessionCount: 1,
        warningCodes: [],
        generation: newer
    )
    await #expect(
        throws: AgentLocalStatusAuthorityErrorV1.staleNetworkGeneration
    ) {
        try await publisher.publish(
            state: .degraded,
            activeRemoteSessionCount: 0,
            warningCodes: [.routeUnavailable],
            generation: older
        )
    }

    let value = try await authority.snapshot(
        generatedAtUnixMilliseconds: 4
    )
    #expect(value.networkState == .listening)
    #expect(value.activeRemoteSessionCount == 1)
    #expect(value.warningCodes.isEmpty)
}

@Test func inventoryProjectionCommitsOneBoundedContentFreeVersion() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    let refresher = AgentLocalStatusInventoryRefresherV1(
        pairedDevices: FixedPairedDeviceCountV1(value: 0),
        capabilities: FixedProviderCountV1(value: 3),
        localStatus: authority
    )

    try await refresher.refresh()

    let value = try await authority.snapshot(
        generatedAtUnixMilliseconds: 4
    )
    #expect(value.routeKinds == [.lan])
    #expect(value.pairedDeviceCount == 0)
    #expect(value.providerCount == 3)
    #expect(value.securityPosture == .nominal)
}

@Test func inventoryFailuresPreserveFactsAndSanitizeStorageFailure() async throws {
    let authority = try makeLocalStatusAuthorityV1()
    let unavailable = AgentLocalStatusInventoryRefresherV1(
        pairedDevices: FailingPairedDeviceCountV1(),
        capabilities: FixedProviderCountV1(value: 0),
        localStatus: authority
    )
    await #expect(
        throws: AgentLocalStatusSourceRefreshErrorV1.storageUnavailable
    ) {
        try await unavailable.refresh()
    }
    let afterStorageFailure = try await authority.snapshot(
        generatedAtUnixMilliseconds: 5
    )
    #expect(afterStorageFailure.routeKinds == [.lan])
    #expect(afterStorageFailure.pairedDeviceCount == 1)
    #expect(afterStorageFailure.providerCount == 1)
    #expect(afterStorageFailure.securityPosture == .storageUnavailable)
    #expect(afterStorageFailure.warningCodes == [.storageUnavailable])

    let outOfBounds = AgentLocalStatusInventoryRefresherV1(
        pairedDevices: FixedPairedDeviceCountV1(
            value: Int(
                AgentLocalStatusAuthorityV1.maximumPairedDeviceCount
            ) + 1
        ),
        capabilities: FixedProviderCountV1(value: 0),
        localStatus: authority
    )
    await #expect(
        throws: AgentLocalStatusSourceRefreshErrorV1.boundsExceeded
    ) {
        try await outOfBounds.refresh()
    }
    let afterBoundsFailure = try await authority.snapshot(
        generatedAtUnixMilliseconds: 6
    )
    #expect(afterBoundsFailure.routeKinds == [.lan])
    #expect(afterBoundsFailure.pairedDeviceCount == 1)
    #expect(afterBoundsFailure.providerCount == 1)
}

#if os(macOS)
@Test func denyLatchProjectionIsClosedAndFailsClosedOnCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-local-status-latch-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let latchURL = directory.appendingPathComponent("emergency-deny.latch")
    let latch = try EmergencyDenyLatch(url: latchURL)
    let authority = try makeLocalStatusAuthorityV1()
    let refresher = AgentLocalStatusSecurityRefresherV1(
        denyLatch: latch,
        localStatus: authority
    )

    #expect(await refresher.refresh() == .nominal)
    _ = try await latch.activate(
        pendingDeviceID: nil,
        reason: .securityStoreUnavailable,
        recordedAtUnixMilliseconds: 10
    )
    #expect(await refresher.refresh() == .denyLatched)
    let active = try await authority.snapshot(
        generatedAtUnixMilliseconds: 11
    )
    #expect(active.securityPosture == .denyLatched)
    #expect(active.warningCodes == [.denyLatchArmed])

    let handle = try FileHandle(forUpdating: latchURL)
    try handle.seek(toOffset: 48)
    try handle.write(contentsOf: Data([0xff]))
    try handle.synchronize()
    try handle.close()
    #expect(await refresher.refresh() == .storageUnavailable)
    let corrupt = try await authority.snapshot(
        generatedAtUnixMilliseconds: 12
    )
    #expect(corrupt.securityPosture == .storageUnavailable)
    #expect(corrupt.warningCodes == [.storageUnavailable])
}
#endif
