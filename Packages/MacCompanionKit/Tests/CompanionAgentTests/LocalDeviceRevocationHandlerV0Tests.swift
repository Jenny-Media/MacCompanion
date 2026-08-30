#if os(macOS)
import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import CryptoKit
import Foundation
import Testing

private let localRevokeDeviceID = UUID(
    uuidString: "019c8000-0000-7000-8000-000000000001"
)!
private let localRevokeClientID = UUID(
    uuidString: "019c8000-0000-7000-8000-000000000002"
)!
private let localRevokePairingID = UUID(
    uuidString: "019c8000-0000-7000-8000-000000000003"
)!
private let localRevokeName = try! DeviceDisplayName("Local iPhone")

private struct LocalRevokeTemporaryDatabaseV0 {
    let directory: URL
    let database: URL
    let latch: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-local-revoke-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        database = directory.appendingPathComponent("security.sqlite3")
        latch = directory.appendingPathComponent("emergency-deny.latch")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func makeLocalRevokeStore(
    at database: URL,
    faults: Set<PersistenceFaultPoint> = []
) async throws -> SQLiteSecurityStore {
    let store = try SQLiteSecurityStore(
        path: database.path,
        injectedFaults: faults
    )
    if faults.isEmpty,
       try await store.device(localRevokeDeviceID) == nil {
        let record = try StoredDeviceRecord(
            deviceID: localRevokeDeviceID,
            clientID: localRevokeClientID,
            sessionPublicKeyX963:
                P256.Signing.PrivateKey().publicKey.x963Representation,
            approvalPublicKeyX963:
                P256.Signing.PrivateKey().publicKey.x963Representation,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
        try await store.commitPairing(
            pairingID: localRevokePairingID,
            record: record,
            displayName: localRevokeName
        )
    }
    return store
}

private actor LocalRevokeEventProbeV0 {
    private var values: [String] = []

    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private actor LocalRevokePrimaryProbeV0:
    AgentDeviceRevocationPrimaryFencingV0
{
    private let events: LocalRevokeEventProbeV0
    private var denied = false

    init(events: LocalRevokeEventProbeV0) { self.events = events }

    package func fenceForSecurityAdministration() async {
        denied = true
        await events.append("fence-and-close")
    }

    package func releaseSecurityAdministrationFence() async {
        denied = false
        await events.append("release")
    }

    func isDenied() -> Bool { denied }
}

private actor LocalRevokeStatusProbeV0:
    AgentDeviceRevocationStatusRefreshingV0
{
    private enum ProbeError: Error { case unavailable }

    private let events: LocalRevokeEventProbeV0
    private let posture: LocalSecurityPosture
    private var inventoryFailuresRemaining: Int
    private var securityFailuresRemaining: Int

    init(
        events: LocalRevokeEventProbeV0,
        posture: LocalSecurityPosture = .nominal,
        inventoryFailuresRemaining: Int = 0,
        securityFailuresRemaining: Int = 0
    ) {
        self.events = events
        self.posture = posture
        self.inventoryFailuresRemaining = inventoryFailuresRemaining
        self.securityFailuresRemaining = securityFailuresRemaining
    }

    package func refreshInventory() async throws {
        await events.append("inventory")
        if inventoryFailuresRemaining > 0 {
            inventoryFailuresRemaining -= 1
            throw ProbeError.unavailable
        }
    }

    package func refreshSecurity() async -> LocalSecurityPosture {
        await events.append("security")
        if securityFailuresRemaining > 0 {
            securityFailuresRemaining -= 1
            return .storageUnavailable
        }
        return posture
    }
}

private final class LocalRevokeClockV0: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init(_ value: Int64) { self.value = value }
    func now() -> Int64 { lock.withLock { value } }
    func set(_ value: Int64) { lock.withLock { self.value = value } }
}

private func localRevokeHandlerV0(
    store: SQLiteSecurityStore,
    latch: EmergencyDenyLatch,
    primary: LocalRevokePrimaryProbeV0,
    status: LocalRevokeStatusProbeV0,
    clock: LocalRevokeClockV0
) -> LocalDeviceRevocationHandlerV0 {
    LocalDeviceRevocationHandlerV0(
        store: store,
        coordinator: DeviceRevocationCoordinator(
            securityStore: store,
            denyLatch: latch
        ),
        primary: primary,
        status: status,
        wallNowUnixMilliseconds: { clock.now() }
    )
}

@Test func localDeviceRevokeFencesCommitsRefreshesAndReplaysExactly()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let events = LocalRevokeEventProbeV0()
    let primary = LocalRevokePrimaryProbeV0(events: events)
    let status = LocalRevokeStatusProbeV0(events: events)
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: primary,
        status: status,
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_001
    )

    let first = try await handler.revoke(command)
    let replay = try await handler.revoke(command)

    #expect(first == replay)
    #expect(first.state == .revoked)
    #expect(try await store.device(localRevokeDeviceID)?.authorization.state
        == .revoked)
    #expect(try await store.deviceGrants(localRevokeDeviceID).isEmpty)
    #expect(try await store.activePairedDeviceCount() == 0)
    #expect(try await store.securityEventCount() == 2)
    #expect(try await latch.snapshot().health == .clear)
    #expect(await primary.isDenied() == false)
    #expect(await events.snapshot()
        == ["fence-and-close", "inventory", "security", "release"])

    let conflicting = try LocalDeviceRevocationCommandV0(
        commandID: command.commandID,
        review: review,
        confirmedAtUnixMilliseconds: 2_002
    )
    await #expect(
        throws: LocalDeviceRevocationHandlerErrorV0.commandConflict
    ) {
        _ = try await handler.revoke(conflicting)
    }
}

@Test func revokingOnePairedDevicePreservesTheOtherDeviceAuthority()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let otherDeviceID = UUID(
        uuidString: "019c8000-0000-7000-8000-000000000011"
    )!
    let otherRecord = try StoredDeviceRecord(
        deviceID: otherDeviceID,
        clientID: UUID(
            uuidString: "019c8000-0000-7000-8000-000000000012"
        )!,
        sessionPublicKeyX963:
            P256.Signing.PrivateKey().publicKey.x963Representation,
        approvalPublicKeyX963:
            P256.Signing.PrivateKey().publicKey.x963Representation,
        authorization: DeviceAuthorization(
            state: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1)
        ),
        policyRevision: .init(rawValue: 1),
        createdAtUnixMilliseconds: 1_100,
        updatedAtUnixMilliseconds: 1_100
    )
    try await store.commitPairing(
        pairingID: UUID(
            uuidString: "019c8000-0000-7000-8000-000000000013"
        )!,
        record: otherRecord,
        displayName: DeviceDisplayName("iPad Pro")
    )
    let events = LocalRevokeEventProbeV0()
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: try EmergencyDenyLatch(url: temporary.latch),
        primary: LocalRevokePrimaryProbeV0(events: events),
        status: LocalRevokeStatusProbeV0(events: events),
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    _ = try await handler.revoke(
        LocalDeviceRevocationCommandV0(
            commandID: UUID(),
            review: review,
            confirmedAtUnixMilliseconds: 2_001
        )
    )

    #expect(try await store.device(localRevokeDeviceID)?.authorization.state
        == .revoked)
    #expect(try await store.device(otherDeviceID)?.authorization.state
        == .activeMonitorOnly)
    #expect(try await store.activePairedDeviceCount() == 1)
}

@Test func staleLocalDeviceRevokeReleasesOnlyAfterNominalLatchRefresh()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let events = LocalRevokeEventProbeV0()
    let primary = LocalRevokePrimaryProbeV0(events: events)
    let status = LocalRevokeStatusProbeV0(events: events)
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: primary,
        status: status,
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    _ = try await store.replaceDeviceGrants(
        localRevokeDeviceID,
        grants: CapabilityGrantSet(["maccompanion.test.changed"]),
        occurredAtUnixMilliseconds: 2_001
    )
    clock.set(2_002)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_000
    )

    await #expect(
        throws: LocalDeviceRevocationHandlerErrorV0.reviewNotCurrent
    ) {
        _ = try await handler.revoke(command)
    }
    #expect(try await store.device(localRevokeDeviceID)?.authorization.state
        == .activeGranted)
    #expect(try await latch.snapshot().health == .clear)
    #expect(await primary.isDenied() == false)
    #expect(await events.snapshot()
        == ["fence-and-close", "security", "release"])
}

@Test func failedLocalDeviceRevokeKeepsLatchAndIngressDenied() async throws {
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    _ = try await makeLocalRevokeStore(at: temporary.database)
    let store = try await makeLocalRevokeStore(
        at: temporary.database,
        faults: [.beforeSecurityEvent]
    )
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let events = LocalRevokeEventProbeV0()
    let primary = LocalRevokePrimaryProbeV0(events: events)
    let status = LocalRevokeStatusProbeV0(events: events)
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: primary,
        status: status,
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_001
    )

    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        _ = try await handler.revoke(command)
    }
    #expect(await primary.isDenied())
    #expect(try await latch.snapshot().health == .active)
    #expect(try await store.device(localRevokeDeviceID)?.authorization.state
        == .activeMonitorOnly)
    #expect(await events.snapshot() == ["fence-and-close"])
}

@Test func postCommitStatusFailureConvergesWithoutSecondRevocation()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let events = LocalRevokeEventProbeV0()
    let primary = LocalRevokePrimaryProbeV0(events: events)
    let status = LocalRevokeStatusProbeV0(
        events: events,
        inventoryFailuresRemaining: 1
    )
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: primary,
        status: status,
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_001
    )

    await #expect(
        throws: LocalDeviceRevocationHandlerErrorV0.statusUnavailable
    ) {
        _ = try await handler.revoke(command)
    }
    #expect(await primary.isDenied())
    #expect(try await store.device(localRevokeDeviceID)?.authorization.state
        == .revoked)
    #expect(try await store.securityEventCount() == 2)

    let reopenedStore = try SQLiteSecurityStore(path: temporary.database.path)
    let reopenedLatch = try EmergencyDenyLatch(url: temporary.latch)
    let restartedPrimary = LocalRevokePrimaryProbeV0(events: events)
    let restartedHandler = localRevokeHandlerV0(
        store: reopenedStore,
        latch: reopenedLatch,
        primary: restartedPrimary,
        status: status,
        clock: clock
    )
    clock.set(2_002)
    let receipt = try await restartedHandler.revoke(command)
    #expect(receipt.completedAtUnixMilliseconds == 2_001)
    #expect(await primary.isDenied())
    #expect(await restartedPrimary.isDenied() == false)
    #expect(try await reopenedStore.securityEventCount() == 2)
    #expect(await events.snapshot() == [
        "fence-and-close", "inventory",
        "fence-and-close", "inventory", "security", "release",
    ])
}

@Test func completedDeviceRevokeReplaysExactlyAfterRestartAndExpiry()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let firstEvents = LocalRevokeEventProbeV0()
    let firstPrimary = LocalRevokePrimaryProbeV0(events: firstEvents)
    let firstStatus = LocalRevokeStatusProbeV0(events: firstEvents)
    let clock = LocalRevokeClockV0(2_000)
    let firstHandler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: firstPrimary,
        status: firstStatus,
        clock: clock
    )
    let review = try await firstHandler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_001
    )
    let original = try await firstHandler.revoke(command)

    let reopenedStore = try SQLiteSecurityStore(path: temporary.database.path)
    let reopenedLatch = try EmergencyDenyLatch(url: temporary.latch)
    let replayEvents = LocalRevokeEventProbeV0()
    let replayPrimary = LocalRevokePrimaryProbeV0(events: replayEvents)
    let replayStatus = LocalRevokeStatusProbeV0(events: replayEvents)
    let replayHandler = localRevokeHandlerV0(
        store: reopenedStore,
        latch: reopenedLatch,
        primary: replayPrimary,
        status: replayStatus,
        clock: clock
    )
    clock.set(review.expiresAtUnixMilliseconds + 1)
    let replay = try await replayHandler.revoke(command)

    #expect(replay == original)
    #expect(try await reopenedStore.securityEventCount() == 2)
    #expect(try await reopenedLatch.snapshot().health == .clear)
    #expect(await replayEvents.snapshot().isEmpty)

    let conflicting = try LocalDeviceRevocationCommandV0(
        commandID: command.commandID,
        review: review,
        confirmedAtUnixMilliseconds: 2_002
    )
    await #expect(
        throws: LocalDeviceRevocationHandlerErrorV0.commandConflict
    ) {
        _ = try await replayHandler.revoke(conflicting)
    }
}

@Test func clearedLatchStatusRetryReleasesTheExistingPrimaryFence()
    async throws
{
    let temporary = try LocalRevokeTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try await makeLocalRevokeStore(at: temporary.database)
    let latch = try EmergencyDenyLatch(url: temporary.latch)
    let events = LocalRevokeEventProbeV0()
    let primary = LocalRevokePrimaryProbeV0(events: events)
    let status = LocalRevokeStatusProbeV0(
        events: events,
        securityFailuresRemaining: 1
    )
    let clock = LocalRevokeClockV0(2_000)
    let handler = localRevokeHandlerV0(
        store: store,
        latch: latch,
        primary: primary,
        status: status,
        clock: clock
    )
    let review = try await handler.makeReview(
        reviewID: UUID(),
        deviceID: localRevokeDeviceID
    )
    clock.set(2_001)
    let command = try LocalDeviceRevocationCommandV0(
        commandID: UUID(),
        review: review,
        confirmedAtUnixMilliseconds: 2_001
    )

    await #expect(
        throws: LocalDeviceRevocationHandlerErrorV0.statusUnavailable
    ) {
        _ = try await handler.revoke(command)
    }
    #expect(await primary.isDenied())
    #expect(try await latch.snapshot().health == .clear)

    clock.set(2_002)
    let receipt = try await handler.revoke(command)
    #expect(receipt.completedAtUnixMilliseconds == 2_001)
    #expect(await primary.isDenied() == false)
    #expect(try await store.securityEventCount() == 2)
    #expect(await events.snapshot() == [
        "fence-and-close", "inventory", "security",
        "fence-and-close", "inventory", "security", "release",
    ])
}
#endif
