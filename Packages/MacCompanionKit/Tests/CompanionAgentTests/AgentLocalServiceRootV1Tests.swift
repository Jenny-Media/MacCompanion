import CompanionAgent
import CompanionIPC
import CompanionLifecycle
import CompanionPersistence
import Foundation
import Testing

private enum LocalServiceRootTestErrorV1: Error {
    case unavailable
}

private actor MutableRootPairedCountV1:
    AgentActivePairedDeviceCountReadingV1
{
    private var value: Int

    init(_ value: Int) { self.value = value }

    func activePairedDeviceCount() async throws -> Int { value }
    func set(_ value: Int) { self.value = value }
}

private actor MutableRootProviderCountV1:
    AgentActiveProviderCountReadingV1
{
    private var value: Int

    init(_ value: Int) { self.value = value }

    func activeProviderCount() async -> Int { value }
    func set(_ value: Int) { self.value = value }
}

private struct FailingRootPairedCountV1:
    AgentActivePairedDeviceCountReadingV1
{
    func activePairedDeviceCount() async throws -> Int {
        throw LocalServiceRootTestErrorV1.unavailable
    }
}

private struct RootFixedClockV1: AgentLocalStatusWallClockV1 {
    let value: Int64
    func nowUnixMilliseconds() -> Int64 { value }
}

private func rootReadyLifecycleV1() -> ProductLifecycleState {
    ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .active,
        agent: .ready,
        menuApp: .ready
    )
}

private func rootTemporaryDirectoryV1(_ suffix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-local-root-\(suffix)-\(UUID())",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}

@Test func localServiceRootPublishesNoReaderBeforeAllInitialSources() async throws {
    let directory = try rootTemporaryDirectoryV1("initial")
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = try await AgentLocalServiceRootV1.bootstrap(
        lifecycle: rootReadyLifecycleV1(),
        pairedDevices: MutableRootPairedCountV1(1),
        capabilities: MutableRootProviderCountV1(2),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("deny.latch")
        ),
        auditHistoryDegraded: false,
        wallClock: RootFixedClockV1(value: 1_000)
    )

    #expect(root.bootstrapReport.degradedSources.isEmpty)
    let value = try await root.statusReader.read()
    #expect(value.generatedAtUnixMilliseconds == 1_000)
    #expect(value.networkState == .stopped)
    #expect(value.securityPosture == .nominal)
    #expect(value.routeKinds.isEmpty)
    #expect(value.pairedDeviceCount == 1)
    #expect(value.activeRemoteSessionCount == 0)
    #expect(value.providerCount == 2)
    #expect(value.warningCodes.isEmpty)
}

@Test func localServiceRootReturnsReadableClosedDegradationButRejectsBounds() async throws {
    let directory = try rootTemporaryDirectoryV1("degraded")
    defer { try? FileManager.default.removeItem(at: directory) }
    let latchURL = directory.appendingPathComponent("deny.latch")
    let latch = try EmergencyDenyLatch(url: latchURL)
    _ = try await latch.activate(
        pendingDeviceID: nil,
        reason: .securityStoreUnavailable,
        recordedAtUnixMilliseconds: 1
    )
    let handle = try FileHandle(forUpdating: latchURL)
    try handle.seek(toOffset: 48)
    try handle.write(contentsOf: Data([0xff]))
    try handle.synchronize()
    try handle.close()

    let degraded = try await AgentLocalServiceRootV1.bootstrap(
        lifecycle: rootReadyLifecycleV1(),
        pairedDevices: FailingRootPairedCountV1(),
        capabilities: MutableRootProviderCountV1(0),
        denyLatch: latch,
        auditHistoryDegraded: true,
        wallClock: RootFixedClockV1(value: 2_000)
    )
    #expect(degraded.bootstrapReport.degradedSources == [
        .auditHistory,
        .inventoryStorage,
        .securityStorage,
    ])
    let value = try await degraded.statusReader.read()
    #expect(value.securityPosture == .storageUnavailable)
    #expect(value.pairedDeviceCount == 0)
    #expect(value.providerCount == 0)
    #expect(value.warningCodes == [
        .auditHistoryDegraded,
        .storageUnavailable,
    ])

    let boundedLatch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("bounded-deny.latch")
    )
    await #expect(
        throws: AgentLocalServiceBootstrapErrorV1.inventoryBoundsExceeded
    ) {
        _ = try await AgentLocalServiceRootV1.bootstrap(
            lifecycle: rootReadyLifecycleV1(),
            pairedDevices: MutableRootPairedCountV1(2),
            capabilities: MutableRootProviderCountV1(0),
            denyLatch: boundedLatch,
            auditHistoryDegraded: false
        )
    }
}

@Test func concurrentRootSourcesRemainIsolatedAndTransientStopIsNarrow() async throws {
    let directory = try rootTemporaryDirectoryV1("concurrent")
    defer { try? FileManager.default.removeItem(at: directory) }
    let paired = MutableRootPairedCountV1(0)
    let providers = MutableRootProviderCountV1(0)
    let latch = try EmergencyDenyLatch(
        url: directory.appendingPathComponent("deny.latch")
    )
    let root = try await AgentLocalServiceRootV1.bootstrap(
        lifecycle: rootReadyLifecycleV1(),
        pairedDevices: paired,
        capabilities: providers,
        denyLatch: latch,
        auditHistoryDegraded: false,
        monotonicNowMilliseconds: { 100 },
        wallClock: RootFixedClockV1(value: 3_000)
    )
    await paired.set(1)
    await providers.set(3)
    _ = try await latch.activate(
        pendingDeviceID: nil,
        reason: .securityStoreUnavailable,
        recordedAtUnixMilliseconds: 2
    )
    let menuUnavailable = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .active,
        agent: .ready,
        menuApp: .starting
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await root.networkStatus.publish(
                state: .listening,
                activeRemoteSessionCount: 1,
                warningCodes: [.localNetworkDenied]
            )
        }
        group.addTask {
            try await root.lanRoutes.publishListenerReadiness(
                ready: true,
                generation: 1
            )
            try await root.lanRoutes.publishAdvertisementReadiness(
                ready: true,
                generation: 1
            )
        }
        group.addTask { try await root.refreshInventory() }
        group.addTask { _ = await root.refreshSecurity() }
        group.addTask {
            await root.lifecycleStatus.publish(menuUnavailable)
        }
        group.addTask { await root.auditHealth.publish(degraded: true) }
        try await group.waitForAll()
    }

    var value = try await root.statusReader.read()
    #expect(value.menuAppProcess == .starting)
    #expect(value.networkState == .listening)
    #expect(value.securityPosture == .denyLatched)
    #expect(value.routeKinds == [.lan])
    #expect(value.pairedDeviceCount == 1)
    #expect(value.activeRemoteSessionCount == 1)
    #expect(value.providerCount == 3)
    #expect(value.warningCodes == [
        .auditHistoryDegraded,
        .denyLatchArmed,
        .localNetworkDenied,
        .menuAppUnavailable,
    ])

    try await root.stopTransientSources(
        observedAtMonotonicMilliseconds: 200
    )
    value = try await root.statusReader.read()
    #expect(value.networkState == .stopped)
    #expect(value.activeRemoteSessionCount == 0)
    #expect(value.routeKinds.isEmpty)
    #expect(value.pairedDeviceCount == 1)
    #expect(value.providerCount == 3)
    #expect(value.securityPosture == .denyLatched)
    #expect(value.warningCodes == [
        .auditHistoryDegraded,
        .denyLatchArmed,
        .menuAppUnavailable,
    ])
}
