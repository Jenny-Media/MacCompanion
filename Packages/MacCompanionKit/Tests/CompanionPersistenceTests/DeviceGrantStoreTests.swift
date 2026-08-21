import CompanionDomain
import CompanionPersistence
import Foundation
import Testing

private let audioGrant = "maccompanion.system.setAudioMuted"
private let secondaryGrant = "maccompanion.test.secondaryAction"

@Test func grantReplacementIsAtomicCanonicalAndAdvancesBothFences() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    #expect(try await store.deviceGrants(identity.deviceID).isEmpty)

    let initial = try CapabilityGrantSet([audioGrant])
    let granted = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: initial,
        occurredAtUnixMilliseconds: 2_000
    )
    #expect(granted.authorization.state == .activeGranted)
    #expect(granted.authorization.authorizationEpoch.rawValue == 2)
    #expect(granted.authorization.grantRevision.rawValue == 2)
    #expect(try await store.deviceGrants(identity.deviceID) == initial)

    let replacement = try CapabilityGrantSet([audioGrant, secondaryGrant])
    let replaced = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: replacement,
        occurredAtUnixMilliseconds: 3_000
    )
    #expect(replaced.authorization.state == .activeGranted)
    #expect(replaced.authorization.authorizationEpoch.rawValue == 3)
    #expect(replaced.authorization.grantRevision.rawValue == 3)
    #expect(try await store.deviceGrants(identity.deviceID).capabilityIDs == [
        audioGrant,
        secondaryGrant,
    ])

    let eventCount = try await store.securityEventCount()
    let unchanged = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: replacement,
        occurredAtUnixMilliseconds: 4_000
    )
    #expect(unchanged == replaced)
    #expect(try await store.securityEventCount() == eventCount)

    let monitorOnly = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet([]),
        occurredAtUnixMilliseconds: 5_000
    )
    #expect(monitorOnly.authorization.state == .activeMonitorOnly)
    #expect(monitorOnly.authorization.authorizationEpoch.rawValue == 4)
    #expect(monitorOnly.authorization.grantRevision.rawValue == 4)
    #expect(try await store.deviceGrants(identity.deviceID).isEmpty)
}

@Test func everyGrantReplacementFaultRollsBackRowsFencesAndEvent() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record()
            )
        }
        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            _ = try await store.replaceDeviceGrants(
                identity.deviceID,
                grants: CapabilityGrantSet([audioGrant]),
                occurredAtUnixMilliseconds: 2_000
            )
        }
        let device = try await store.device(identity.deviceID)
        #expect(device?.authorization.state == .activeMonitorOnly)
        #expect(device?.authorization.authorizationEpoch.rawValue == 1)
        #expect(device?.authorization.grantRevision.rawValue == 1)
        #expect(try await store.deviceGrants(identity.deviceID).isEmpty)
        #expect(try await store.securityEventCount() == 1)
    }
}

@Test func suspendedDeviceResumesOnlyWithAtomicallyReviewedGrantSet() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    _ = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet([audioGrant]),
        occurredAtUnixMilliseconds: 2_000
    )
    _ = try await store.transitionDevice(
        identity.deviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 3_000
    )

    await #expect(throws: SecurityStoreError.unsupportedGrantTransition(.suspended)) {
        _ = try await store.replaceDeviceGrants(
            identity.deviceID,
            grants: CapabilityGrantSet([audioGrant]),
            occurredAtUnixMilliseconds: 4_000
        )
    }
    let reviewed = try CapabilityGrantSet([secondaryGrant])
    let resumed = try await store.resumeDevice(
        identity.deviceID,
        grants: reviewed,
        occurredAtUnixMilliseconds: 4_000
    )
    #expect(resumed.authorization.state == .activeGranted)
    #expect(resumed.authorization.authorizationEpoch.rawValue == 4)
    #expect(resumed.authorization.grantRevision.rawValue == 3)
    #expect(try await store.deviceGrants(identity.deviceID) == reviewed)

    await #expect(throws: SecurityStoreError.unsupportedGrantTransition(.activeGranted)) {
        _ = try await store.resumeDevice(
            identity.deviceID,
            grants: reviewed,
            occurredAtUnixMilliseconds: 5_000
        )
    }
}

@Test func resumeWithEmptyReviewedSetReturnsMonitorOnly() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    _ = try await store.transitionDevice(
        identity.deviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 2_000
    )
    let resumed = try await store.resumeDevice(
        identity.deviceID,
        grants: CapabilityGrantSet([]),
        occurredAtUnixMilliseconds: 3_000
    )
    #expect(resumed.authorization.state == .activeMonitorOnly)
    #expect(resumed.authorization.authorizationEpoch.rawValue == 3)
    #expect(resumed.authorization.grantRevision.rawValue == 2)
    #expect(try await store.deviceGrants(identity.deviceID).isEmpty)
}

@Test func grantReplacementFencesQueuedWorkInTheSameTransaction() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    _ = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet([audioGrant]),
        occurredAtUnixMilliseconds: 2_000
    )
    let operation = try StoredDurableOperationRecord(
        operationID: UUID(uuidString: "018f8000-0000-7000-8000-000000000099")!,
        deviceID: identity.deviceID,
        clientID: identity.clientID,
        requestDigest: Data(repeating: 0x99, count: 32),
        state: .queued,
        capabilityID: audioGrant,
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: UUID(),
        executionRevision: UUID(),
        authorizationEpoch: 2,
        grantRevision: 2,
        policyRevision: 1,
        requiredHostState: .userSessionActive,
        expiresAtUnixMilliseconds: 10_000,
        createdAtUnixMilliseconds: 2_100,
        updatedAtUnixMilliseconds: 2_100
    )
    _ = try await store.admitDurableOperation(operation)

    _ = try await store.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet([secondaryGrant]),
        occurredAtUnixMilliseconds: 3_000
    )
    let fenced = try await store.durableOperation(operation.operationID)
    #expect(fenced?.state == .failed)
    #expect(fenced?.terminalCode == "operation.authorizationRevoked")
    #expect(fenced?.terminalAtUnixMilliseconds == 3_000)
}
