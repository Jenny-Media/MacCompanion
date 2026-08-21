#if os(macOS)
import CompanionDomain
import CompanionPersistence
import Foundation
import Testing

private let durableRevocationName = try! DeviceDisplayName("Local iPhone")

private func durableRevocationIntent(
    identity: TestIdentity,
    commandID: UUID = UUID(),
    reviewID: UUID = UUID()
) throws -> StoredDeviceRevocationIntent {
    try StoredDeviceRevocationIntent(
        commandID: commandID,
        reviewID: reviewID,
        deviceID: identity.deviceID,
        deviceDisplayName: durableRevocationName,
        reviewedState: .activeMonitorOnly,
        authorizationEpoch: .init(rawValue: 1),
        grantRevision: .init(rawValue: 1),
        reviewCreatedAtUnixMilliseconds: 1_500,
        reviewExpiresAtUnixMilliseconds: 301_500,
        confirmedAtUnixMilliseconds: 1_600
    )
}

@Test func coordinatedRevocationPrearmsCommitsAndClears() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    let latch = try EmergencyDenyLatch(
        url: temporary.directory.appendingPathComponent("emergency-deny.latch")
    )
    let coordinator = DeviceRevocationCoordinator(
        securityStore: store,
        denyLatch: latch
    )

    let result = try await coordinator.revoke(
        deviceID: identity.deviceID,
        occurredAtUnixMilliseconds: 2_000
    )

    guard case let .committed(record) = result else {
        Issue.record("expected newly committed revocation")
        return
    }
    #expect(record.authorization.state == .revoked)
    #expect(try await latch.snapshot().health == .clear)
    #expect(try await latch.snapshot().generation == 2)
}

@Test func failedDatabaseRevocationLeavesDurableLatchForRestartRecovery() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    do {
        let setup = try SQLiteSecurityStore(path: temporary.database.path)
        try await setup.commitPairing(pairingID: identity.pairingID, record: identity.record())
    }
    let latchURL = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let latch = try EmergencyDenyLatch(url: latchURL)
    let faultingStore = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    let faultingCoordinator = DeviceRevocationCoordinator(
        securityStore: faultingStore,
        denyLatch: latch
    )

    await #expect(throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)) {
        _ = try await faultingCoordinator.revoke(
            deviceID: identity.deviceID,
            occurredAtUnixMilliseconds: 2_000
        )
    }
    let pending = try await latch.snapshot()
    #expect(pending.health == .active)
    #expect(pending.pendingDeviceID == identity.deviceID)
    #expect(try await faultingStore.device(identity.deviceID)?.authorization.state == .activeMonitorOnly)

    let recoveredStore = try SQLiteSecurityStore(path: temporary.database.path)
    let reopenedLatch = try EmergencyDenyLatch(url: latchURL)
    let recovery = DeviceRevocationCoordinator(
        securityStore: recoveredStore,
        denyLatch: reopenedLatch
    )
    #expect(try await recovery.recoverPendingRevocation(
        occurredAtUnixMilliseconds: 3_000
    ) == .committed(identity.deviceID))
    #expect(try await recoveredStore.device(identity.deviceID)?.authorization.state == .revoked)
    #expect(try await reopenedLatch.snapshot().health == .clear)
}

@Test func alreadyDurablePendingRevocationClearsWithoutSecondTransition() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    _ = try await store.transitionDevice(
        identity.deviceID,
        event: .revoke,
        occurredAtUnixMilliseconds: 2_000
    )
    let latch = try EmergencyDenyLatch(
        url: temporary.directory.appendingPathComponent("emergency-deny.latch")
    )
    _ = try await latch.activate(
        pendingDeviceID: identity.deviceID,
        reason: .revocationInProgress,
        recordedAtUnixMilliseconds: 2_000
    )
    let coordinator = DeviceRevocationCoordinator(
        securityStore: store,
        denyLatch: latch
    )

    #expect(try await coordinator.recoverPendingRevocation(
        occurredAtUnixMilliseconds: 3_000
    ) == .alreadyDurable(identity.deviceID))
    #expect(try await store.securityEventCount() == 2)
    #expect(try await latch.snapshot().health == .clear)
}

@Test func staleRevocationReviewMutatesNothingAndClearsItsLatch() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )
    let latch = try EmergencyDenyLatch(
        url: temporary.directory.appendingPathComponent(
            "emergency-deny.latch"
        )
    )
    let coordinator = DeviceRevocationCoordinator(
        securityStore: store,
        denyLatch: latch
    )
    let stale = try DeviceRevocationExpectation(
        deviceID: identity.deviceID,
        state: .activeMonitorOnly,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 1)
    )

    await #expect(throws: DeviceRevocationCoordinatorError.staleReview) {
        _ = try await coordinator.revoke(
            expected: stale,
            occurredAtUnixMilliseconds: 2_000
        )
    }
    #expect(try await store.device(identity.deviceID)?.authorization.state
        == .activeMonitorOnly)
    #expect(try await latch.snapshot().health == .clear)
    #expect(try await store.securityEventCount() == 1)
}

@Test func reviewedRevocationPersistsReceiptAndRetainsLatchUntilConvergence()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record(),
        displayName: durableRevocationName
    )
    let latchURL = temporary.directory.appendingPathComponent(
        "emergency-deny.latch"
    )
    let latch = try EmergencyDenyLatch(url: latchURL)
    let coordinator = DeviceRevocationCoordinator(
        securityStore: store,
        denyLatch: latch
    )
    let intent = try durableRevocationIntent(identity: identity)

    #expect(try await coordinator.prepare(intent) == .prepared)
    guard case let .committed(record, receipt) = try await coordinator.revoke(
        intent: intent,
        occurredAtUnixMilliseconds: 2_000
    ) else {
        Issue.record("expected newly committed reviewed revocation")
        return
    }
    #expect(record.authorization.state == .revoked)
    #expect(receipt.completedAtUnixMilliseconds == 2_000)
    #expect(try await latch.snapshot().health == .active)
    #expect(try await store.deviceRevocationRecord(
        commandID: intent.commandID
    )?.receipt == receipt)

    let reopenedStore = try SQLiteSecurityStore(
        path: temporary.database.path
    )
    let reopenedLatch = try EmergencyDenyLatch(url: latchURL)
    let recovery = DeviceRevocationCoordinator(
        securityStore: reopenedStore,
        denyLatch: reopenedLatch
    )
    #expect(try await recovery.recoverReviewedRevocation(
        occurredAtUnixMilliseconds: 2_001
    ) == .convergenceRequired(identity.deviceID))
    #expect(try await reopenedStore.securityEventCount() == 2)
    try await recovery.finishStatusConvergence(
        deviceID: identity.deviceID,
        occurredAtUnixMilliseconds: 2_001
    )
    #expect(try await reopenedLatch.snapshot().health == .clear)
    guard case let .alreadyDurable(_, replayed) = try await reopenedStore
        .completeDeviceRevocation(
            intent,
            occurredAtUnixMilliseconds: 2_002
        ) else {
        Issue.record("expected exact durable receipt replay")
        return
    }
    #expect(replayed == receipt)
    #expect(try await reopenedStore.securityEventCount() == 2)
}

@Test func pendingReviewedRevocationBlocksCompetingDeviceMutations()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record(),
        displayName: durableRevocationName
    )
    let intent = try durableRevocationIntent(identity: identity)
    #expect(try await store.beginDeviceRevocation(intent) == .prepared)

    await #expect(throws: SecurityStoreError.deviceRevocationConflict) {
        try await store.setDeviceDisplayName(
            identity.deviceID,
            displayName: DeviceDisplayName("Changed"),
            occurredAtUnixMilliseconds: 2_000
        )
    }
    await #expect(throws: SecurityStoreError.deviceRevocationConflict) {
        _ = try await store.replaceDeviceGrants(
            identity.deviceID,
            grants: CapabilityGrantSet(["maccompanion.test"]),
            occurredAtUnixMilliseconds: 2_000
        )
    }
    await #expect(throws: SecurityStoreError.deviceRevocationConflict) {
        _ = try await store.transitionDevice(
            identity.deviceID,
            event: .suspend,
            occurredAtUnixMilliseconds: 2_000
        )
    }
    #expect(try await store.device(identity.deviceID)?.authorization.state
        == .activeMonitorOnly)
    #expect(try await store.securityEventCount() == 1)
}

@Test func reviewedRevocationFaultsRollBackReceiptAuthorityAndEvent()
    async throws
{
    for fault in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        let intent = try durableRevocationIntent(identity: identity)
        do {
            let setup = try SQLiteSecurityStore(
                path: temporary.database.path
            )
            try await setup.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record(),
                displayName: durableRevocationName
            )
            #expect(try await setup.beginDeviceRevocation(intent) == .prepared)
        }
        let faulting = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [fault]
        )
        await #expect(throws: SecurityStoreError.injectedFault(fault)) {
            _ = try await faulting.completeDeviceRevocation(
                intent,
                occurredAtUnixMilliseconds: 2_000
            )
        }
        #expect(try await faulting.device(identity.deviceID)?.authorization.state
            == .activeMonitorOnly)
        #expect(try await faulting.deviceRevocationRecord(
            commandID: intent.commandID
        )?.receipt == nil)
        #expect(try await faulting.securityEventCount() == 1)

        let recovered = try SQLiteSecurityStore(
            path: temporary.database.path
        )
        guard case .committed = try await recovered.completeDeviceRevocation(
            intent,
            occurredAtUnixMilliseconds: 2_001
        ) else {
            Issue.record("expected recovered transaction to commit")
            continue
        }
        #expect(try await recovered.securityEventCount() == 2)
    }
}

@Test func revocationReceiptExpiresWithItsDeviceTombstone() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record(),
        displayName: durableRevocationName
    )
    let intent = try durableRevocationIntent(identity: identity)
    _ = try await store.beginDeviceRevocation(intent)
    _ = try await store.completeDeviceRevocation(
        intent,
        occurredAtUnixMilliseconds: 2_000
    )
    _ = try await store.transitionDevice(
        identity.deviceID,
        event: .expireRevokedTombstone,
        occurredAtUnixMilliseconds: 3_000
    )
    #expect(try await store.device(identity.deviceID) == nil)
    #expect(try await store.deviceRevocationRecord(
        commandID: intent.commandID
    ) == nil)
}
#endif
