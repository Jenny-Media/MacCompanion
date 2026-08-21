import CompanionDomain
import CompanionPersistence
import Foundation
import Testing

private let operationProviderGeneration = UUID(
    uuidString: "018f8100-0000-7000-8000-000000000001"
)!
private let operationExecutionRevision = UUID(
    uuidString: "018f8200-0000-7000-8000-000000000001"
)!

private func operationRecord(
    identity: TestIdentity,
    suffix: Int,
    state: OperationState = .queued,
    digestByte: UInt8? = nil,
    createdAt: Int64 = 1_100,
    expiresAt: Int64 = 10_000
) throws -> StoredDurableOperationRecord {
    try StoredDurableOperationRecord(
        operationID: UUID(uuidString: String(
            format: "018f8000-0000-7000-8000-%012x",
            suffix
        ))!,
        deviceID: identity.deviceID,
        clientID: identity.clientID,
        requestDigest: Data(repeating: digestByte ?? UInt8(suffix), count: 32),
        state: state,
        capabilityID: "maccompanion.system.setAudioMuted",
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: operationProviderGeneration,
        executionRevision: operationExecutionRevision,
        authorizationEpoch: 2,
        grantRevision: 2,
        policyRevision: 1,
        requiredHostState: .userSessionActive,
        expiresAtUnixMilliseconds: expiresAt,
        createdAtUnixMilliseconds: createdAt,
        updatedAtUnixMilliseconds: createdAt
    )
}

private func grantOperationCapability(
    _ store: SQLiteSecurityStore,
    identity: TestIdentity
) async throws {
    _ = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet(["maccompanion.system.setAudioMuted"]),
        occurredAtUnixMilliseconds: 1_050
    )
}

private func matchingSnapshot(
    now: Int64 = 1_500,
    providerGeneration: UUID = operationProviderGeneration
) throws -> DurableOperationExecutionSnapshot {
    try DurableOperationExecutionSnapshot(
        providerGeneration: providerGeneration,
        executionRevision: operationExecutionRevision,
        hostState: .userSessionActive,
        nowUnixMilliseconds: now
    )
}

@Test func durableAdmissionIsIdempotentAndDigestConflictFailsClosed() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    try await grantOperationCapability(store, identity: identity)
    let operation = try operationRecord(identity: identity, suffix: 1)

    #expect(try await store.admitDurableOperation(operation) == .created(operation))
    #expect(try await store.admitDurableOperation(operation) == .existing(operation))
    #expect(try await store.securityEventCount() == 3)

    let conflicting = try operationRecord(
        identity: identity,
        suffix: 1,
        digestByte: 0xFE
    )
    await #expect(throws: SecurityStoreError.operationIDConflict(operation.operationID)) {
        _ = try await store.admitDurableOperation(conflicting)
    }
    #expect(try await store.durableOperation(operation.operationID) == operation)
    #expect(try await store.securityEventCount() == 3)
}

@Test func durableAdmissionFaultsRollBackRecordAndEventTogether() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        let operation = try operationRecord(identity: identity, suffix: 1)
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record()
            )
            try await grantOperationCapability(setup, identity: identity)
        }
        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            _ = try await store.admitDurableOperation(operation)
        }
        #expect(try await store.durableOperation(operation.operationID) == nil)
        #expect(try await store.securityEventCount() == 2)
    }
}

@Test func operationQuotaRejectsRatherThanEvictsAndOldTerminalMayPurge() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(
        path: temporary.database.path,
        retainedOperationLimitPerDevice: 2
    )
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    try await grantOperationCapability(store, identity: identity)
    let first = try operationRecord(identity: identity, suffix: 1)
    let second = try operationRecord(identity: identity, suffix: 2)
    _ = try await store.admitDurableOperation(first)
    _ = try await store.admitDurableOperation(second)

    let blocked = try operationRecord(identity: identity, suffix: 3)
    await #expect(throws: SecurityStoreError.operationQuotaExceeded(identity.deviceID)) {
        _ = try await store.admitDurableOperation(blocked)
    }
    #expect(try await store.durableOperation(first.operationID) == first)
    #expect(try await store.durableOperation(second.operationID) == second)

    _ = try await store.transitionDurableOperation(
        first.operationID,
        to: .cancelled,
        occurredAtUnixMilliseconds: 2_000,
        terminalCode: "operation.cancelled"
    )
    let afterRetention = 2_000 + SQLiteSecurityStore.operationRetentionMilliseconds
    let replacement = try operationRecord(
        identity: identity,
        suffix: 3,
        createdAt: afterRetention,
        expiresAt: afterRetention + 10_000
    )
    #expect(try await store.admitDurableOperation(replacement) == .created(replacement))
    #expect(try await store.durableOperation(first.operationID) == nil)
    #expect(try await store.retainedOperationCount(deviceID: identity.deviceID) == 2)
}

@Test func executionClaimAtomicallyRunsOrFailsOnExactSnapshot() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    try await grantOperationCapability(store, identity: identity)

    let valid = try operationRecord(identity: identity, suffix: 1)
    _ = try await store.admitDurableOperation(valid)
    let claimed = try await store.claimDurableOperationExecution(
        valid.operationID,
        snapshot: matchingSnapshot()
    )
    #expect(claimed == .claimed(try StoredDurableOperationRecord(
        operationID: valid.operationID,
        deviceID: valid.deviceID,
        clientID: valid.clientID,
        requestDigest: valid.requestDigest,
        state: .running,
        capabilityID: valid.capabilityID,
        schemaVersion: valid.schemaVersion,
        providerID: valid.providerID,
        providerVersion: valid.providerVersion,
        providerGeneration: valid.providerGeneration,
        executionRevision: valid.executionRevision,
        authorizationEpoch: valid.authorizationEpoch,
        grantRevision: valid.grantRevision,
        policyRevision: valid.policyRevision,
        requiredHostState: valid.requiredHostState,
        expiresAtUnixMilliseconds: valid.expiresAtUnixMilliseconds,
        createdAtUnixMilliseconds: valid.createdAtUnixMilliseconds,
        updatedAtUnixMilliseconds: 1_500
    )))
    await #expect(throws: SecurityStoreError.operationNotClaimable(
        valid.operationID,
        .running
    )) {
        _ = try await store.claimDurableOperationExecution(
            valid.operationID,
            snapshot: matchingSnapshot(now: 1_600)
        )
    }

    let stale = try operationRecord(identity: identity, suffix: 2)
    _ = try await store.admitDurableOperation(stale)
    let staleResult = try await store.claimDurableOperationExecution(
        stale.operationID,
        snapshot: matchingSnapshot(providerGeneration: UUID())
    )
    guard case let .failed(staleRecord) = staleResult else {
        Issue.record("expected stale execution claim to fail")
        return
    }
    #expect(staleRecord.state == .failed)
    #expect(staleRecord.terminalCode == "operation.authorizationRevoked")

    let expired = try operationRecord(
        identity: identity,
        suffix: 3,
        expiresAt: 1_400
    )
    _ = try await store.admitDurableOperation(expired)
    guard case let .failed(expiredRecord) = try await store.claimDurableOperationExecution(
        expired.operationID,
        snapshot: matchingSnapshot()
    ) else {
        Issue.record("expected expired execution claim to fail")
        return
    }
    #expect(expiredRecord.terminalCode == "operation.expired")
}

@Test func executionClaimFaultNeverLetsQueuedRecordAppearRunning() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        let operation = try operationRecord(identity: identity, suffix: 1)
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record()
            )
            try await grantOperationCapability(setup, identity: identity)
            _ = try await setup.admitDurableOperation(operation)
        }
        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            _ = try await store.claimDurableOperationExecution(
                operation.operationID,
                snapshot: matchingSnapshot()
            )
        }
        #expect(try await store.durableOperation(operation.operationID)?.state == .queued)
        #expect(try await store.securityEventCount() == 3)
    }
}

@Test func suspensionAtomicallyFencesEveryAdmittedOperationState() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    try await grantOperationCapability(store, identity: identity)
    let pending = try operationRecord(identity: identity, suffix: 1, state: .pendingPolicy)
    let approval = try operationRecord(identity: identity, suffix: 2, state: .awaitingApproval)
    let queued = try operationRecord(identity: identity, suffix: 3)
    let running = try operationRecord(identity: identity, suffix: 4)
    for operation in [pending, approval, queued, running] {
        _ = try await store.admitDurableOperation(operation)
    }
    _ = try await store.claimDurableOperationExecution(
        running.operationID,
        snapshot: matchingSnapshot()
    )

    _ = try await store.transitionDevice(
        identity.deviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 2_000
    )
    #expect(try await store.durableOperation(pending.operationID)?.state == .denied)
    #expect(try await store.durableOperation(approval.operationID)?.state == .denied)
    #expect(try await store.durableOperation(queued.operationID)?.state == .failed)
    #expect(try await store.durableOperation(running.operationID)?.state == .cancelRequested)
}

@Test func startupReconciliationFailsQueuedAndMarksInFlightUnknown() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    try await grantOperationCapability(store, identity: identity)
    let running = try operationRecord(identity: identity, suffix: 1)
    let cancelling = try operationRecord(identity: identity, suffix: 2)
    let queued = try operationRecord(identity: identity, suffix: 3)
    for operation in [running, cancelling, queued] {
        _ = try await store.admitDurableOperation(operation)
    }
    _ = try await store.claimDurableOperationExecution(
        running.operationID,
        snapshot: matchingSnapshot()
    )
    _ = try await store.claimDurableOperationExecution(
        cancelling.operationID,
        snapshot: matchingSnapshot()
    )
    _ = try await store.transitionDurableOperation(
        cancelling.operationID,
        to: .cancelRequested,
        occurredAtUnixMilliseconds: 1_600
    )

    #expect(try await store.reconcileOperationsAtStartup(
        atUnixMilliseconds: 2_000
    ) == DurableOperationStartupReconciliation(
        queuedFailed: 1,
        inFlightOutcomeUnknown: 2
    ))
    #expect(try await store.durableOperation(running.operationID)?.state == .outcomeUnknown)
    #expect(try await store.durableOperation(cancelling.operationID)?.state == .outcomeUnknown)
    #expect(try await store.durableOperation(queued.operationID)?.state == .failed)
    #expect(try await store.durableOperation(queued.operationID)?.terminalCode
        == "operation.hostRestarted")
    #expect(try await store.reconcileOperationsAtStartup(
        atUnixMilliseconds: 2_100
    ).totalReconciled == 0)
}

@Test func startupReconciliationRollsBackEveryTransitionAndEventOnFault() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        let queued = try operationRecord(identity: identity, suffix: 1)
        let running = try operationRecord(identity: identity, suffix: 2)
        let cancelling = try operationRecord(identity: identity, suffix: 3)
        var expectedEvents = 0
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record()
            )
            try await grantOperationCapability(setup, identity: identity)
            for operation in [queued, running, cancelling] {
                _ = try await setup.admitDurableOperation(operation)
            }
            for operation in [running, cancelling] {
                _ = try await setup.claimDurableOperationExecution(
                    operation.operationID,
                    snapshot: matchingSnapshot()
                )
            }
            _ = try await setup.transitionDurableOperation(
                cancelling.operationID,
                to: .cancelRequested,
                occurredAtUnixMilliseconds: 1_600
            )
            expectedEvents = try await setup.securityEventCount()
        }

        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            _ = try await store.reconcileOperationsAtStartup(
                atUnixMilliseconds: 2_000
            )
        }
        #expect(try await store.durableOperation(queued.operationID)?.state == .queued)
        #expect(try await store.durableOperation(running.operationID)?.state == .running)
        #expect(try await store.durableOperation(cancelling.operationID)?.state
            == .cancelRequested)
        #expect(try await store.securityEventCount() == expectedEvents)
    }
}
