import CompanionDomain
import CompanionPersistence
import Foundation
import SQLite3
import Testing

@Test func pairingHasNoRemoteNameUntilLocalConfirmation() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )

    #expect(try await store.deviceDisplayName(identity.deviceID) == nil)
    #expect(try await store.deviceGrantIdentitySnapshot(identity.deviceID)
        .displayName == nil)
}

@Test func localDisplayNamePersistsAndJoinsDeviceGrantSnapshot() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )
    let name = try DeviceDisplayName("Jenny’s iPhone")
    try await store.setDeviceDisplayName(
        identity.deviceID,
        displayName: name,
        occurredAtUnixMilliseconds: 1_001
    )

    #expect(try await store.deviceDisplayName(identity.deviceID) == name)
    let snapshot = try await store.deviceGrantIdentitySnapshot(identity.deviceID)
    #expect(snapshot.displayName == name)
    #expect(snapshot.device.authorization.authorizationEpoch.rawValue == 1)
    #expect(snapshot.device.authorization.grantRevision.rawValue == 1)
    #expect(try await store.securityEventCount() == 2)

    let reopened = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await reopened.deviceDisplayName(identity.deviceID) == name)
}

@Test func everyInjectedDisplayNameFaultRollsBackNameAndEvent() async throws {
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
            try await store.setDeviceDisplayName(
                identity.deviceID,
                displayName: DeviceDisplayName("Local iPhone"),
                occurredAtUnixMilliseconds: 1_001
            )
        }
        #expect(try await store.deviceDisplayName(identity.deviceID) == nil)
        #expect(try await store.securityEventCount() == 1)
    }
}

@Test func schemaThreeMigratesDeviceDisplayNameTableWithoutRebuild() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(
        database,
        "CREATE TABLE device_authorizations(device_id TEXT PRIMARY KEY)",
        nil,
        nil,
        nil
    ) == SQLITE_OK)
    #expect(sqlite3_exec(database, "PRAGMA user_version = 3", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let store = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await store.currentSchemaVersion() == 8)
}
