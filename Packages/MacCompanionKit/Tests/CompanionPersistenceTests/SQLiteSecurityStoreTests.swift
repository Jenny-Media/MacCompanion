import CompanionDomain
import CompanionPersistence
import CryptoKit
import Darwin
import Foundation
import SQLite3
import Testing

struct TemporaryDatabase {
    let directory: URL
    let database: URL

    init() throws {
        var resolvedTemporary = [CChar](
            repeating: 0,
            count: Int(PATH_MAX)
        )
        guard realpath(
            FileManager.default.temporaryDirectory.path,
            &resolvedTemporary
        ) != nil else {
            throw SQLiteStorePathSecurityTestError.resolutionFailed
        }
        guard let resolvedEnd = resolvedTemporary.firstIndex(of: 0) else {
            throw SQLiteStorePathSecurityTestError.resolutionFailed
        }
        let resolvedPath = String(
            decoding: resolvedTemporary[..<resolvedEnd].map {
                UInt8(bitPattern: $0)
            },
            as: UTF8.self
        )
        directory = URL(fileURLWithPath: resolvedPath)
            .appendingPathComponent("maccompanion-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        database = directory.appendingPathComponent("security.sqlite3")
        guard FileManager.default.createFile(
            atPath: database.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw SQLiteStorePathSecurityTestError.creationFailed
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum SQLiteStorePathSecurityTestError: Error {
    case creationFailed
    case resolutionFailed
}

func sqliteTestPermissions(at path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return try #require(
        attributes[.posixPermissions] as? NSNumber
    ).intValue
}

struct TestIdentity {
    let pairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!
    let deviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
    let clientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
    let sessionPublicKey = P256.Signing.PrivateKey().publicKey.x963Representation
    let approvalPublicKey = P256.Signing.PrivateKey().publicKey.x963Representation

    func record() throws -> StoredDeviceRecord {
        try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKey,
            approvalPublicKeyX963: approvalPublicKey,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
    }
}

private func storedHostIdentity(
    suffix: Int = 1,
    timestamp: Int64 = 500
) throws -> StoredHostIdentityRecord {
    try StoredHostIdentityRecord(
        hostID: UUID(uuidString: String(
            format: "018f1000-0000-7000-8000-%012x",
            suffix
        ))!,
        keyApplicationTag: Data(repeating: UInt8(suffix), count: 16),
        hostFingerprint: Data(repeating: UInt8(0x80 + suffix), count: 32),
        certificateDER: Data([0x30, UInt8(suffix)]),
        certificateNotBeforeUnixMilliseconds: 0,
        certificateNotAfterUnixMilliseconds: 10_000,
        establishedAtUnixMilliseconds: timestamp,
        updatedAtUnixMilliseconds: timestamp
    )
}

private func storedHostIdentityBootstrap(
    suffix: Int = 1,
    timestamp: Int64 = 400
) throws -> StoredHostIdentityBootstrapRecord {
    try StoredHostIdentityBootstrapRecord(
        hostID: UUID(uuidString: String(
            format: "018f1000-0000-7000-8000-%012x",
            suffix
        ))!,
        keyApplicationTag: Data(repeating: UInt8(suffix), count: 16),
        startedAtUnixMilliseconds: timestamp
    )
}

private func storedRecoveryIntent(
    recoveryID: UUID,
    expectedHostID: UUID,
    expectedHostFingerprint: Data,
    confirmedAt: Int64 = 1_500
) throws -> StoredHostIdentityRecoveryIntent {
    try StoredHostIdentityRecoveryIntent(
        commandID: UUID(
            uuidString: "018f6900-0000-7000-8000-000000000010"
        )!,
        recoveryID: recoveryID,
        reviewID: UUID(
            uuidString: "018f6900-0000-7000-8000-000000000011"
        )!,
        expectedHostID: expectedHostID,
        expectedHostFingerprint: expectedHostFingerprint,
        cause: .userRequestedReset,
        reviewCreatedAtUnixMilliseconds: confirmedAt - 1,
        reviewExpiresAtUnixMilliseconds: confirmedAt + 299_999,
        confirmedAtUnixMilliseconds: confirmedAt
    )
}

private func storagePressureRecord(
    index: Int,
    sessionPublicKey: Data,
    approvalPublicKey: Data
) throws -> (pairingID: UUID, record: StoredDeviceRecord) {
    let suffix = String(format: "%012x", index)
    let pairingID = try #require(UUID(
        uuidString: "018f4100-0000-7000-8000-\(suffix)"
    ))
    let deviceID = try #require(UUID(
        uuidString: "018f2200-0000-7000-8000-\(suffix)"
    ))
    let clientID = try #require(UUID(
        uuidString: "018f2300-0000-7000-8000-\(suffix)"
    ))
    return (
        pairingID,
        try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKey,
            approvalPublicKeyX963: approvalPublicKey,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: Int64(index),
            updatedAtUnixMilliseconds: Int64(index)
        )
    )
}

private func rawSQLiteInteger(
    _ database: OpaquePointer?,
    sql: String
) throws -> Int32 {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            == SQLITE_OK,
          let statement else {
        throw SecurityStoreError.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SecurityStoreError.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    return sqlite3_column_int(statement, 0)
}

private func rawSQLiteText(
    _ database: OpaquePointer?,
    sql: String
) throws -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            == SQLITE_OK,
          let statement else {
        throw SecurityStoreError.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW,
          let text = sqlite3_column_text(statement, 0) else {
        throw SecurityStoreError.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    return String(cString: text)
}

@Test func freshDatabaseMigratesAndStoresInitialPairingAtomically() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)

    #expect(try await store.currentSchemaVersion() == 8)
    #expect(try await store.activePairedDeviceCount() == 0)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    #expect(try await store.activePairedDeviceCount() == 1)

    let stored = try await store.device(identity.deviceID)
    #expect(stored?.clientID == identity.clientID)
    #expect(stored?.authorization.state == .activeMonitorOnly)
    #expect(stored?.authorization.authorizationEpoch.rawValue == 1)
    #expect(stored?.policyRevision.rawValue == 1)
    #expect(try await store.pairingConsumptionDeviceID(identity.pairingID) == identity.deviceID)
    #expect(try await store.securityEventCount() == 1)
}

@Test func securityStoreRequiresOwnerControlledNonSymlinkedSQLiteArtifacts()
    async throws
{
    let created = try TemporaryDatabase()
    defer { created.remove() }
    try FileManager.default.removeItem(at: created.database)
    let store = try SQLiteSecurityStore(path: created.database.path)
    let identity = TestIdentity()
    try await store.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )
    #expect(try sqliteTestPermissions(at: created.directory.path) == 0o700)
    #expect(try sqliteTestPermissions(at: created.database.path) == 0o600)
    #expect(try sqliteTestPermissions(at: created.database.path + "-wal") == 0o600)
    #expect(try sqliteTestPermissions(at: created.database.path + "-shm") == 0o600)

    let insecureFile = try TemporaryDatabase()
    defer { insecureFile.remove() }
    #expect(chmod(insecureFile.database.path, 0o644) == 0)
    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try SQLiteSecurityStore(path: insecureFile.database.path)
    }

    let insecureDirectory = try TemporaryDatabase()
    defer { insecureDirectory.remove() }
    #expect(chmod(insecureDirectory.directory.path, 0o777) == 0)
    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try SQLiteSecurityStore(path: insecureDirectory.database.path)
    }

    let symlinked = try TemporaryDatabase()
    defer { symlinked.remove() }
    let link = symlinked.directory.appendingPathComponent("linked.sqlite3")
    #expect(Darwin.symlink(symlinked.database.path, link.path) == 0)
    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try SQLiteSecurityStore(path: link.path)
    }

    let sidecarSymlink = try TemporaryDatabase()
    defer { sidecarSymlink.remove() }
    #expect(Darwin.symlink(
        sidecarSymlink.database.path,
        sidecarSymlink.database.path + "-wal"
    ) == 0)
    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try SQLiteSecurityStore(path: sidecarSymlink.database.path)
    }
}

@Test func realSQLiteFullRollsBackPairingAndRecoversAfterCheckpoint()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let keys = TestIdentity()
    var store: SQLiteSecurityStore? = try .init(
        path: temporary.database.path
    )
    let seed = try storagePressureRecord(
        index: 1,
        sessionPublicKey: keys.sessionPublicKey,
        approvalPublicKey: keys.approvalPublicKey
    )
    try await store?.commitPairing(
        pairingID: seed.pairingID,
        record: seed.record
    )
    store = nil

    var rawDatabase: OpaquePointer?
    #expect(sqlite3_open_v2(
        temporary.database.path,
        &rawDatabase,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK)
    defer { if let rawDatabase { sqlite3_close(rawDatabase) } }
    var logFrames: Int32 = 0
    var checkpointedFrames: Int32 = 0
    #expect(sqlite3_wal_checkpoint_v2(
        rawDatabase,
        nil,
        SQLITE_CHECKPOINT_TRUNCATE,
        &logFrames,
        &checkpointedFrames
    ) == SQLITE_OK)
    let initialPageCount = try rawSQLiteInteger(
        rawDatabase,
        sql: "PRAGMA page_count"
    )
    #expect(initialPageCount > 1)
    sqlite3_close(rawDatabase)
    rawDatabase = nil
    #expect(throws: SecurityStoreError.storageQuotaBelowCurrentUsage(
        requested: initialPageCount - 1,
        current: initialPageCount
    )) {
        _ = try SQLiteSecurityStore(
            path: temporary.database.path,
            maximumPageCount: initialPageCount - 1
        )
    }
    store = try .init(
        path: temporary.database.path,
        maximumPageCount: initialPageCount
    )

    var committedCount = 1
    var rejected: (pairingID: UUID, record: StoredDeviceRecord)?
    for index in 2...5_000 {
        let candidate = try storagePressureRecord(
            index: index,
            sessionPublicKey: keys.sessionPublicKey,
            approvalPublicKey: keys.approvalPublicKey
        )
        do {
            try await store?.commitPairing(
                pairingID: candidate.pairingID,
                record: candidate.record
            )
            committedCount += 1
        } catch let SecurityStoreError.sqlite(_, code, _)
            where code == SQLITE_FULL {
            rejected = candidate
            break
        }
    }
    let rejectedCandidate = try #require(rejected)
    #expect(try await store?.activePairedDeviceCount() == committedCount)
    #expect(try await store?.securityEventCount() == committedCount)
    #expect(try await store?.device(rejectedCandidate.record.deviceID) == nil)
    #expect(try await store?.pairingConsumptionDeviceID(
        rejectedCandidate.pairingID
    ) == nil)

    store = nil
    #expect(sqlite3_open_v2(
        temporary.database.path,
        &rawDatabase,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK)
    #expect(sqlite3_wal_checkpoint_v2(
        rawDatabase,
        nil,
        SQLITE_CHECKPOINT_TRUNCATE,
        &logFrames,
        &checkpointedFrames
    ) == SQLITE_OK)
    #expect(try rawSQLiteText(
        rawDatabase,
        sql: "PRAGMA integrity_check"
    ) == "ok")
    sqlite3_close(rawDatabase)
    rawDatabase = nil

    let reopened = try SQLiteSecurityStore(
        path: temporary.database.path,
        maximumPageCount: initialPageCount + 128
    )
    try await reopened.commitPairing(
        pairingID: rejectedCandidate.pairingID,
        record: rejectedCandidate.record
    )
    #expect(try await reopened.activePairedDeviceCount()
        == committedCount + 1)
    #expect(try await reopened.securityEventCount() == committedCount + 1)
}

@Test func tornWALTailNeverPublishesAPartialPairingTransaction()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let keys = TestIdentity()
    let seed = try storagePressureRecord(
        index: 1,
        sessionPublicKey: keys.sessionPublicKey,
        approvalPublicKey: keys.approvalPublicKey
    )
    do {
        let setup = try SQLiteSecurityStore(path: temporary.database.path)
        try await setup.commitPairing(
            pairingID: seed.pairingID,
            record: seed.record
        )
    }

    let candidate = try storagePressureRecord(
        index: 2,
        sessionPublicKey: keys.sessionPublicKey,
        approvalPublicKey: keys.approvalPublicKey
    )
    let live = try SQLiteSecurityStore(path: temporary.database.path)
    try await live.commitPairing(
        pairingID: candidate.pairingID,
        record: candidate.record
    )
    let sourceWAL = temporary.database.path + "-wal"
    let walSize = try #require(
        FileManager.default.attributesOfItem(atPath: sourceWAL)[.size]
            as? NSNumber
    ).int64Value
    #expect(walSize > 64)
    let cuts = Set<Int64>([1, 64, walSize / 2]).sorted()
    var rejectedOrRolledBackCases = 0

    for (index, cut) in cuts.enumerated() {
        let caseDirectory = temporary.directory.appendingPathComponent(
            "torn-wal-\(index)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: caseDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let database = caseDirectory.appendingPathComponent("security.sqlite3")
        let wal = database.path + "-wal"
        try FileManager.default.copyItem(
            at: temporary.database,
            to: database
        )
        try FileManager.default.copyItem(
            atPath: sourceWAL,
            toPath: wal
        )
        #expect(chmod(database.path, 0o600) == 0)
        #expect(chmod(wal, 0o600) == 0)
        #expect(truncate(wal, off_t(walSize - cut)) == 0)

        do {
            let recovered = try SQLiteSecurityStore(path: database.path)
            let candidateDevice = try await recovered.device(
                candidate.record.deviceID
            )
            let candidateConsumption = try await recovered
                .pairingConsumptionDeviceID(candidate.pairingID)
            let candidateIsVisible = candidateDevice != nil
            if !candidateIsVisible {
                rejectedOrRolledBackCases += 1
            }
            #expect((candidateConsumption != nil) == candidateIsVisible)
            #expect(candidateConsumption == (
                candidateIsVisible ? candidate.record.deviceID : nil
            ))
            #expect(try await recovered.activePairedDeviceCount()
                == (candidateIsVisible ? 2 : 1))
            #expect(try await recovered.securityEventCount()
                == (candidateIsVisible ? 2 : 1))
            #expect(try await recovered.device(seed.record.deviceID)
                == seed.record)
            #expect(try await recovered.pairingConsumptionDeviceID(
                seed.pairingID
            ) == seed.record.deviceID)
        } catch let SecurityStoreError.sqlite(_, code, _) {
            #expect(code != SQLITE_OK)
            rejectedOrRolledBackCases += 1
        }
    }
    #expect(rejectedOrRolledBackCases >= 1)
}

@Test func hostIdentityEstablishmentIsAtomicAndSingleAssignment() async throws {
    let identity = try storedHostIdentity()
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.establishHostIdentity(identity)
    #expect(try await store.hostIdentity() == identity)
    #expect(try await store.securityEventCount() == 1)
    await #expect(throws: SecurityStoreError.hostIdentityAlreadyEstablished) {
        try await store.establishHostIdentity(identity)
    }

    for point in PersistenceFaultPoint.allCases {
        let faulted = try TemporaryDatabase()
        defer { faulted.remove() }
        let faultingStore = try SQLiteSecurityStore(
            path: faulted.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            try await faultingStore.establishHostIdentity(identity)
        }
        #expect(try await faultingStore.hostIdentity() == nil)
        #expect(try await faultingStore.securityEventCount() == 0)
    }
}

@Test func hostIdentityBootstrapResumesExactCandidateAndCompletesAtomically()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let pending = try storedHostIdentityBootstrap()
    let other = try storedHostIdentityBootstrap(suffix: 2)
    let identity = try storedHostIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)

    #expect(
        try await store.beginHostIdentityBootstrap(candidate: pending)
            == pending
    )
    #expect(
        try await store.beginHostIdentityBootstrap(candidate: other)
            == pending
    )
    #expect(try await store.hostIdentityBootstrap() == pending)
    #expect(try await store.hostIdentity() == nil)
    #expect(try await store.securityEventCount() == 0)

    try await store.completeHostIdentityBootstrap(
        expected: pending,
        identity: identity
    )
    #expect(try await store.hostIdentityBootstrap() == nil)
    #expect(try await store.hostIdentity() == identity)
    #expect(try await store.securityEventCount() == 1)

    await #expect(throws: SecurityStoreError.hostIdentityAlreadyEstablished) {
        _ = try await store.beginHostIdentityBootstrap(candidate: other)
    }
}

@Test func hostIdentityBootstrapCompletionFaultPreservesExactPendingCandidate()
    async throws
{
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let pending = try storedHostIdentityBootstrap()
        let identity = try storedHostIdentity()
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            _ = try await setup.beginHostIdentityBootstrap(candidate: pending)
        }
        let faulting = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            try await faulting.completeHostIdentityBootstrap(
                expected: pending,
                identity: identity
            )
        }
        #expect(try await faulting.hostIdentityBootstrap() == pending)
        #expect(try await faulting.hostIdentity() == nil)
        #expect(try await faulting.securityEventCount() == 0)
    }
}

@Test func hostIdentityBootstrapCandidateIsNotPublishedWhenCommitFails()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let pending = try storedHostIdentityBootstrap()
    let store = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeTransactionCommit]
    )

    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeTransactionCommit)
    ) {
        _ = try await store.beginHostIdentityBootstrap(candidate: pending)
    }
    #expect(try await store.hostIdentityBootstrap() == nil)
    #expect(try await store.hostIdentity() == nil)
    #expect(try await store.securityEventCount() == 0)
}

@Test func hostIdentityBootstrapRejectsMismatchedCompletionAndLegacyBypass()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let pending = try storedHostIdentityBootstrap()
    let mismatched = try storedHostIdentity(suffix: 2)
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    _ = try await store.beginHostIdentityBootstrap(candidate: pending)

    await #expect(throws: SecurityStoreError.hostIdentityBootstrapConflict) {
        try await store.completeHostIdentityBootstrap(
            expected: pending,
            identity: mismatched
        )
    }
    await #expect(throws: SecurityStoreError.hostIdentityBootstrapConflict) {
        try await store.establishHostIdentity(try storedHostIdentity())
    }
    #expect(try await store.hostIdentityBootstrap() == pending)
    #expect(try await store.hostIdentity() == nil)
}

@Test func hostIdentityCertificateReplacementIsSameKeyAndStaleWriteFenced()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let original = try storedHostIdentity()
    let replacement = try StoredHostIdentityRecord(
        hostID: original.hostID,
        keyApplicationTag: original.keyApplicationTag,
        hostFingerprint: original.hostFingerprint,
        certificateDER: Data([0x30, 0x55]),
        certificateNotBeforeUnixMilliseconds: 900,
        certificateNotAfterUnixMilliseconds: 20_000,
        establishedAtUnixMilliseconds:
            original.establishedAtUnixMilliseconds,
        updatedAtUnixMilliseconds: 1_000
    )
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.establishHostIdentity(original)
    try await store.replaceHostIdentityCertificate(
        expected: original,
        replacement: replacement
    )
    #expect(try await store.hostIdentity() == replacement)
    #expect(try await store.securityEventCount() == 2)

    await #expect(throws: SecurityStoreError.hostIdentityWriteConflict) {
        try await store.replaceHostIdentityCertificate(
            expected: original,
            replacement: replacement
        )
    }
}

@Test func hostIdentityCertificateReplacementFaultKeepsPriorCertificate()
    async throws
{
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let original = try storedHostIdentity()
        let replacement = try StoredHostIdentityRecord(
            hostID: original.hostID,
            keyApplicationTag: original.keyApplicationTag,
            hostFingerprint: original.hostFingerprint,
            certificateDER: Data([0x30, 0x66]),
            certificateNotBeforeUnixMilliseconds: 900,
            certificateNotAfterUnixMilliseconds: 20_000,
            establishedAtUnixMilliseconds:
                original.establishedAtUnixMilliseconds,
            updatedAtUnixMilliseconds: 1_000
        )
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.establishHostIdentity(original)
        }
        let faulting = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            try await faulting.replaceHostIdentityCertificate(
                expected: original,
                replacement: replacement
            )
        }
        #expect(try await faulting.hostIdentity() == original)
        #expect(try await faulting.securityEventCount() == 1)
    }
}

@Test func hostRecoveryAtomicallyFencesDevicesBeforeRotatedIdentity() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try storedHostIdentity()
    let device = TestIdentity()
    try await store.establishHostIdentity(original)
    try await store.commitPairing(pairingID: device.pairingID, record: device.record())

    let recoveryID = UUID(uuidString: "018f6900-0000-7000-8000-000000000001")!
    let intent = try storedRecoveryIntent(
        recoveryID: recoveryID,
        expectedHostID: original.hostID,
        expectedHostFingerprint: original.hostFingerprint
    )
    let result = try await store.beginHostIdentityRecovery(
        intent: intent,
        occurredAtUnixMilliseconds: 2_000
    )
    guard case let .fenced(fenced, count) = result else {
        Issue.record("expected new recovery fence")
        return
    }
    #expect(count == 1)
    #expect(fenced.state == .fencedForReplacement)
    #expect(fenced.recoveryID == recoveryID)
    #expect(try await store.device(device.deviceID)?.authorization.state == .revoked)
    #expect(try await store.activePairedDeviceCount() == 0)
    #expect(try await store.securityEventCount() == 3)
    #expect(try await store.hostIdentityRecoveryIntent() == intent)
    #expect(try await store.beginHostIdentityRecovery(
        intent: intent,
        occurredAtUnixMilliseconds: 2_001
    ) == .alreadyFenced(record: fenced))
    await #expect(throws: SecurityStoreError.hostIdentityRecoveryConflict) {
        _ = try await store.beginHostIdentityRecovery(
            intent: storedRecoveryIntent(
                recoveryID: UUID(),
                expectedHostID: original.hostID,
                expectedHostFingerprint: original.hostFingerprint
            ),
            occurredAtUnixMilliseconds: 2_001
        )
    }

    var unchanged = original
    unchanged = try StoredHostIdentityRecord(
        hostID: unchanged.hostID,
        keyApplicationTag: unchanged.keyApplicationTag,
        hostFingerprint: unchanged.hostFingerprint,
        certificateDER: unchanged.certificateDER,
        certificateNotBeforeUnixMilliseconds: unchanged.certificateNotBeforeUnixMilliseconds,
        certificateNotAfterUnixMilliseconds: unchanged.certificateNotAfterUnixMilliseconds,
        establishedAtUnixMilliseconds: unchanged.establishedAtUnixMilliseconds,
        updatedAtUnixMilliseconds: 3_000
    )
    await #expect(throws: SecurityStoreError.hostIdentityReplacementDidNotRotate) {
        try await store.completeHostIdentityRecovery(
            recoveryID: recoveryID,
            replacement: unchanged
        )
    }

    let replacement = try storedHostIdentity(suffix: 2, timestamp: 3_000)
    try await store.completeHostIdentityRecovery(
        recoveryID: recoveryID,
        replacement: replacement
    )
    #expect(try await store.hostIdentity() == replacement)
    let receipt = try #require(
        try await store.hostIdentityRecoveryReceipt()
    )
    #expect(receipt.recoveryID == recoveryID)
    #expect(receipt.replacedHostID == original.hostID)
    #expect(receipt.replacedHostFingerprint == original.hostFingerprint)
    #expect(receipt.newHostID == replacement.hostID)
    #expect(receipt.newHostFingerprint == replacement.hostFingerprint)
    #expect(try await store.beginHostIdentityRecovery(
        intent: intent,
        occurredAtUnixMilliseconds: 4_000
    ) == .alreadyCompleted(receipt: receipt))
    #expect(try await store.device(device.deviceID)?.authorization.state == .revoked)
    #expect(try await store.securityEventCount() == 4)
    await #expect(throws: SecurityStoreError.hostIdentityRecoveryConflict) {
        try await store.acknowledgeHostIdentityRecoveryCompletion(
            commandID: UUID(),
            receipt: receipt,
            occurredAtUnixMilliseconds: 4_001
        )
    }
    #expect(try await store.hostIdentityRecoveryReceipt() == receipt)
    #expect(try await store.hostIdentityRecoveryIntent() == intent)
    try await store.acknowledgeHostIdentityRecoveryCompletion(
        commandID: intent.commandID,
        receipt: receipt,
        occurredAtUnixMilliseconds: 4_001
    )
    #expect(try await store.hostIdentityRecoveryReceipt() == nil)
    #expect(try await store.hostIdentityRecoveryIntent() == nil)
    #expect(try await store.hostIdentity() == replacement)
    #expect(try await store.securityEventCount() == 5)
}

@Test func hostRecoveryAcknowledgementAuditFailureKeepsReplayJournal()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let original = try storedHostIdentity()
    let recoveryID = UUID(
        uuidString: "018f6900-0000-7000-8000-000000000003"
    )!
    let intent = try storedRecoveryIntent(
        recoveryID: recoveryID,
        expectedHostID: original.hostID,
        expectedHostFingerprint: original.hostFingerprint
    )
    let replacement = try storedHostIdentity(suffix: 3, timestamp: 3_000)
    let receipt: StoredHostIdentityRecoveryReceipt
    do {
        let setup = try SQLiteSecurityStore(path: temporary.database.path)
        try await setup.establishHostIdentity(original)
        _ = try await setup.beginHostIdentityRecovery(
            intent: intent,
            occurredAtUnixMilliseconds: 2_000
        )
        try await setup.completeHostIdentityRecovery(
            recoveryID: recoveryID,
            replacement: replacement
        )
        receipt = try #require(
            try await setup.hostIdentityRecoveryReceipt()
        )
    }
    let faulting = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        try await faulting.acknowledgeHostIdentityRecoveryCompletion(
            commandID: intent.commandID,
            receipt: receipt,
            occurredAtUnixMilliseconds: 4_000
        )
    }
    #expect(try await faulting.hostIdentityRecoveryReceipt() == receipt)
    #expect(try await faulting.hostIdentityRecoveryIntent() == intent)
    #expect(try await faulting.hostIdentity() == replacement)
    #expect(try await faulting.securityEventCount() == 3)
}

@Test func staleExpectedHostCannotBeginIdentityRecovery() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let original = try storedHostIdentity()
    try await store.establishHostIdentity(original)

    await #expect(throws: SecurityStoreError.hostIdentityRecoveryConflict) {
        _ = try await store.beginHostIdentityRecovery(
            intent: storedRecoveryIntent(
                recoveryID: UUID(),
                expectedHostID: UUID(),
                expectedHostFingerprint: original.hostFingerprint
            ),
            occurredAtUnixMilliseconds: 2_000
        )
    }
    #expect(try await store.hostIdentity() == original)
    #expect(try await store.hostIdentityRecoveryReceipt() == nil)
    #expect(try await store.hostIdentityRecoveryIntent() == nil)
    #expect(try await store.securityEventCount() == 1)
}

@Test func recoveryFaultRollsBackIdentityFenceAndEveryDeviceEpoch() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let original = try storedHostIdentity()
        let device = TestIdentity()
        do {
            let setup = try SQLiteSecurityStore(path: temporary.database.path)
            try await setup.establishHostIdentity(original)
            try await setup.commitPairing(pairingID: device.pairingID, record: device.record())
        }
        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            _ = try await store.beginHostIdentityRecovery(
                intent: storedRecoveryIntent(
                    recoveryID: UUID(),
                    expectedHostID: original.hostID,
                    expectedHostFingerprint: original.hostFingerprint
                ),
                occurredAtUnixMilliseconds: 2_000
            )
        }
        #expect(try await store.hostIdentity() == original)
        #expect(try await store.hostIdentityRecoveryIntent() == nil)
        #expect(try await store.device(device.deviceID)?.authorization.state == .activeMonitorOnly)
        #expect(try await store.device(device.deviceID)?.authorization.authorizationEpoch.rawValue == 1)
        #expect(try await store.securityEventCount() == 2)
    }
}

@Test func schemaOneMigratesHostIdentityTableWithoutRebuildingDatabase() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "PRAGMA user_version = 1", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let store = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await store.currentSchemaVersion() == 8)
    #expect(try await store.hostIdentity() == nil)
}

@Test func schemaFourAddsEmptyHostIdentityBootstrapWithoutInventingCandidate()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(
        sqlite3_exec(
            database,
            "PRAGMA user_version = 4",
            nil,
            nil,
            nil
        ) == SQLITE_OK
    )
    sqlite3_close(database)

    let store = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await store.currentSchemaVersion() == 8)
    #expect(try await store.hostIdentityBootstrap() == nil)
    #expect(try await store.hostIdentityRecoveryIntent() == nil)
}

@Test func schemaSixAddsEmptyRecoveryIntentWithoutInventingAuthorization()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(
        sqlite3_exec(
            database,
            "PRAGMA user_version = 6",
            nil,
            nil,
            nil
        ) == SQLITE_OK
    )
    sqlite3_close(database)

    let store = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await store.currentSchemaVersion() == 8)
    #expect(try await store.hostIdentityRecoveryIntent() == nil)
}

@Test func schemaSevenAddsEmptyDeviceRevocationJournal() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(
        sqlite3_exec(
            database,
            "PRAGMA user_version = 7",
            nil,
            nil,
            nil
        ) == SQLITE_OK
    )
    sqlite3_close(database)

    let store = try SQLiteSecurityStore(path: temporary.database.path)
    #expect(try await store.currentSchemaVersion() == 8)
    #expect(try await store.pendingDeviceRevocationIntent() == nil)
}

@Test func everyInjectedPairingFaultRollsBackDeviceAndEvent() async throws {
    for point in PersistenceFaultPoint.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let identity = TestIdentity()
        let store = try SQLiteSecurityStore(
            path: temporary.database.path,
            injectedFaults: [point]
        )

        await #expect(throws: SecurityStoreError.injectedFault(point)) {
            try await store.commitPairing(
                pairingID: identity.pairingID,
                record: identity.record()
            )
        }
        #expect(try await store.device(identity.deviceID) == nil)
        #expect(try await store.pairingConsumptionDeviceID(identity.pairingID) == nil)
        #expect(try await store.securityEventCount() == 0)
    }
}

@Test func consumedPairingIDCannotCreateAnotherIdentity() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())

    await #expect(throws: SecurityStoreError.pairingAlreadyConsumed(identity.pairingID)) {
        try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())
    }
    #expect(try await store.securityEventCount() == 1)
}

@Test func suspendAndRevokeAdvanceEpochAndPersistEvents() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())

    let suspended = try await store.transitionDevice(
        identity.deviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 2_000
    )
    #expect(suspended?.authorization.state == .suspended)
    #expect(suspended?.authorization.authorizationEpoch.rawValue == 2)

    let revoked = try await store.transitionDevice(
        identity.deviceID,
        event: .revoke,
        occurredAtUnixMilliseconds: 3_000
    )
    #expect(revoked?.authorization.state == .revoked)
    #expect(revoked?.authorization.authorizationEpoch.rawValue == 3)
    #expect(revoked?.authorization.grantRevision.rawValue == 2)
    #expect(revoked?.revokedAtUnixMilliseconds == 3_000)
    #expect(try await store.securityEventCount() == 3)
}

@Test func transitionFaultLeavesPriorDurableAuthorizationUntouched() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    do {
        let setup = try SQLiteSecurityStore(path: temporary.database.path)
        try await setup.commitPairing(pairingID: identity.pairingID, record: identity.record())
    }

    let faulting = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    await #expect(throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)) {
        _ = try await faulting.transitionDevice(
            identity.deviceID,
            event: .suspend,
            occurredAtUnixMilliseconds: 2_000
        )
    }

    let stored = try await faulting.device(identity.deviceID)
    #expect(stored?.authorization.state == .activeMonitorOnly)
    #expect(stored?.authorization.authorizationEpoch.rawValue == 1)
    #expect(try await faulting.securityEventCount() == 1)
}

@Test func revokedTombstoneCanOnlyExpireThroughExplicitTransition() async throws {
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

    let result = try await store.transitionDevice(
        identity.deviceID,
        event: .expireRevokedTombstone,
        occurredAtUnixMilliseconds: 3_000
    )
    #expect(result == nil)
    #expect(try await store.device(identity.deviceID) == nil)
    #expect(try await store.securityEventCount() == 3)
}

@Test func grantedResumeIsRejectedUntilGrantRowsCanCommitAtomically() async throws {
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

    await #expect(throws: SecurityStoreError.unsupportedTransitionEvent(.resumeGranted)) {
        _ = try await store.transitionDevice(
            identity.deviceID,
            event: .resumeGranted,
            occurredAtUnixMilliseconds: 3_000
        )
    }
    #expect(try await store.device(identity.deviceID)?.authorization.state == .suspended)
}

@Test func epochExhaustionAndBackwardTimeRollBack() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let identity = TestIdentity()
    let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.commitPairing(pairingID: identity.pairingID, record: identity.record())

    var rawDatabase: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &rawDatabase) == SQLITE_OK)
    #expect(sqlite3_exec(
        rawDatabase,
        "UPDATE device_authorizations SET authorization_epoch = \(maximum)",
        nil,
        nil,
        nil
    ) == SQLITE_OK)
    sqlite3_close(rawDatabase)

    await #expect(throws: RevisionError.exhausted) {
        _ = try await store.transitionDevice(
            identity.deviceID,
            event: .suspend,
            occurredAtUnixMilliseconds: 2_000
        )
    }
    await #expect(throws: SecurityStoreError.invalidRecord) {
        _ = try await store.transitionDevice(
            identity.deviceID,
            event: .suspend,
            occurredAtUnixMilliseconds: 999
        )
    }
    #expect(try await store.device(identity.deviceID)?.authorization.state == .activeMonitorOnly)
    #expect(try await store.device(identity.deviceID)?.authorization.authorizationEpoch.rawValue == maximum)
}

@Test func futureSchemaAndCorruptDatabaseAreRefused() throws {
    let future = try TemporaryDatabase()
    defer { future.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(future.database.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "PRAGMA user_version = 99", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    #expect(throws: SecurityStoreError.futureSchema(found: 99, supported: 8)) {
        _ = try SQLiteSecurityStore(path: future.database.path)
    }

    let corrupt = try TemporaryDatabase()
    defer { corrupt.remove() }
    try Data("not a sqlite database".utf8).write(to: corrupt.database)
    #expect(throws: SecurityStoreError.self) {
        _ = try SQLiteSecurityStore(path: corrupt.database.path)
    }
}
