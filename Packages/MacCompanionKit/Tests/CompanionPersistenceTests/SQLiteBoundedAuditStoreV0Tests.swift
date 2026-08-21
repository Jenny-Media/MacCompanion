import CompanionDomain
import CompanionPersistence
import Darwin
import Foundation
import SQLite3
import Testing

private let auditDeviceA = UUID(
    uuidString: "018f9700-0000-7000-8000-000000000001"
)!
private let auditDeviceB = UUID(
    uuidString: "018f9700-0000-7000-8000-000000000002"
)!

private func auditConfiguration(
    bytes: Int = 16 * 1_024 * 1_024,
    rows: Int = 50_000,
    retention: Int64 = 30 * 24 * 60 * 60 * 1_000,
    rate: Int = 120,
    window: Int64 = 60_000
) throws -> AuditStoreConfigurationV0 {
    try AuditStoreConfigurationV0(
        logicalByteLimit: bytes,
        retainedRowLimit: rows,
        retentionMilliseconds: retention,
        rateLimitAttempts: rate,
        rateLimitWindowMilliseconds: window
    )
}

private func auditDraft(
    eventID: UUID = UUID(),
    time: Int64,
    actor: AuditActorV0 = .pairedDevice,
    visibility: AuditVisibilityV0 = .subjectDevice,
    deviceID: UUID? = auditDeviceA,
    code: AuditEventCodeV0 = .operationRequested,
    capabilityID: String? = "maccompanion.status.read",
    importance: AuditImportanceV0 = .bestEffort
) throws -> AuditEventDraftV0 {
    try AuditEventDraftV0(
        eventID: eventID,
        observedAtUnixMilliseconds: time,
        actor: actor,
        visibility: visibility,
        subjectDeviceID: deviceID,
        correlationID: UUID(
            uuidString: "018f9700-0000-7000-8000-000000000010"
        ),
        operationID: code == .operationRequested ? UUID(
            uuidString: "018f9700-0000-7000-8000-000000000011"
        ) : nil,
        code: code,
        capabilityID: capabilityID,
        policyRevision: .init(rawValue: 3),
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        outcome: .succeeded,
        importance: importance
    )
}

private func globalAuditDraft(
    eventID: UUID = UUID(),
    time: Int64
) throws -> AuditEventDraftV0 {
    try AuditEventDraftV0(
        eventID: eventID,
        observedAtUnixMilliseconds: time,
        actor: .system,
        visibility: .allPairedDevices,
        code: .hostAvailabilityChanged,
        outcome: .unavailable,
        importance: .bestEffort
    )
}

private func auditStoragePressureDraft(
    index: Int,
    importance: AuditImportanceV0 = .bestEffort
) throws -> AuditEventDraftV0 {
    let eventID = try #require(UUID(uuidString: String(
        format: "018f9800-0000-7000-8000-%012x",
        index
    )))
    return try auditDraft(
        eventID: eventID,
        time: Int64(index),
        importance: importance
    )
}

private func auditRawSQLiteInteger(
    _ database: OpaquePointer?,
    sql: String
) throws -> Int32 {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            == SQLITE_OK,
          let statement else {
        throw AuditStoreErrorV0.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw AuditStoreErrorV0.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    return sqlite3_column_int(statement, 0)
}

private func auditRawSQLiteText(
    _ database: OpaquePointer?,
    sql: String
) throws -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            == SQLITE_OK,
          let statement else {
        throw AuditStoreErrorV0.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW,
          let text = sqlite3_column_text(statement, 0) else {
        throw AuditStoreErrorV0.sqlite(
            operation: sql,
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }
    return String(cString: text)
}

@Test func auditModelRejectsIdentityAndGlobalPrivacyContradictions() throws {
    #expect(throws: AuditRecordErrorV0.invalidRecord) {
        try AuditEventDraftV0(
            eventID: UUID(),
            observedAtUnixMilliseconds: 1,
            actor: .pairedDevice,
            visibility: .localOnly,
            code: .authenticationRejected,
            importance: .bestEffort
        )
    }
    #expect(throws: AuditRecordErrorV0.invalidRecord) {
        try AuditEventDraftV0(
            eventID: UUID(),
            observedAtUnixMilliseconds: 1,
            actor: .localUser,
            visibility: .allPairedDevices,
            code: .hostAvailabilityChanged,
            importance: .bestEffort
        )
    }
    #expect(throws: AuditRecordErrorV0.invalidRecord) {
        try AuditEventDraftV0(
            eventID: UUID(),
            observedAtUnixMilliseconds: 1,
            actor: .system,
            visibility: .allPairedDevices,
            subjectDeviceID: auditDeviceA,
            code: .operationRequested,
            capabilityID: "not valid",
            importance: .bestEffort
        )
    }
    #expect(throws: AuditRecordErrorV0.invalidRecord) {
        try AuditEventDraftV0(
            eventID: UUID(),
            observedAtUnixMilliseconds: 1,
            actor: .system,
            visibility: .allPairedDevices,
            correlationID: UUID(),
            code: .hostSecurityStateChanged,
            authorizationEpoch: .init(rawValue: 2),
            importance: .bestEffort
        )
    }
    #expect(try globalAuditDraft(time: 1).logicalSize <= 1_024)
}

@Test func appendPaginationDuplicateAndRestartPreserveExactOrdering() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let firstID = UUID()
    var store: SQLiteBoundedAuditStoreV0? = try .init(
        path: temporary.database.path
    )
    #expect(try await store?.append(
        auditDraft(eventID: firstID, time: 1)
    ) == .recorded(.init(
        sequence: 1,
        draft: auditDraft(eventID: firstID, time: 1)
    )))
    _ = try await store?.append(auditDraft(time: 2))
    _ = try await store?.append(auditDraft(time: 3))
    let newest = try await store?.page(
        scope: .localAdministration,
        limit: 2
    )
    #expect(newest?.events.map(\.sequence) == [3, 2])
    #expect(newest?.nextBeforeSequence == 2)
    let older = try await store?.page(
        scope: .localAdministration,
        beforeSequence: newest?.nextBeforeSequence,
        limit: 2
    )
    #expect(older?.events.map(\.sequence) == [1])
    #expect(older?.nextBeforeSequence == nil)
    await #expect(throws: AuditStoreErrorV0.duplicateEventID(firstID)) {
        _ = try await store?.append(auditDraft(eventID: firstID, time: 4))
    }

    store = nil
    let reopened = try SQLiteBoundedAuditStoreV0(path: temporary.database.path)
    _ = try await reopened.append(auditDraft(time: 5))
    #expect(try await reopened.page(
        scope: .localAdministration,
        limit: 10
    ).events.map(\.sequence) == [4, 3, 2, 1])
}

@Test func auditStoreRequiresOwnerControlledNonSymlinkedSQLiteArtifacts()
    async throws
{
    let created = try TemporaryDatabase()
    defer { created.remove() }
    let store = try SQLiteBoundedAuditStoreV0(path: created.database.path)
    _ = try await store.append(auditDraft(time: 1))
    #expect(try sqliteTestPermissions(at: created.directory.path) == 0o700)
    #expect(try sqliteTestPermissions(at: created.database.path) == 0o600)
    #expect(try sqliteTestPermissions(at: created.database.path + "-wal") == 0o600)
    #expect(try sqliteTestPermissions(at: created.database.path + "-shm") == 0o600)

    let insecureFile = try TemporaryDatabase()
    defer { insecureFile.remove() }
    #expect(chmod(insecureFile.database.path, 0o644) == 0)
    #expect(throws: AuditStoreErrorV0.insecureStoragePath) {
        _ = try SQLiteBoundedAuditStoreV0(
            path: insecureFile.database.path
        )
    }

    let symlinked = try TemporaryDatabase()
    defer { symlinked.remove() }
    let link = symlinked.directory.appendingPathComponent("linked.sqlite3")
    #expect(Darwin.symlink(symlinked.database.path, link.path) == 0)
    #expect(throws: AuditStoreErrorV0.insecureStoragePath) {
        _ = try SQLiteBoundedAuditStoreV0(path: link.path)
    }
}

@Test func realSQLiteFullRollsBackAuditRowsAndRecoversAfterCheckpoint()
    async throws
{
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let configuration = try auditConfiguration(rate: 10_000)
    var store: SQLiteBoundedAuditStoreV0? = try .init(
        path: temporary.database.path,
        configuration: configuration
    )
    let seed = try auditStoragePressureDraft(index: 1)
    _ = try await store?.append(seed)
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
    let initialPageCount = try auditRawSQLiteInteger(
        rawDatabase,
        sql: "PRAGMA page_count"
    )
    #expect(initialPageCount > 1)
    sqlite3_close(rawDatabase)
    rawDatabase = nil
    #expect(throws: AuditStoreErrorV0.storageQuotaBelowCurrentUsage(
        requested: initialPageCount - 1,
        current: initialPageCount
    )) {
        _ = try SQLiteBoundedAuditStoreV0(
            path: temporary.database.path,
            configuration: configuration,
            maximumPageCount: initialPageCount - 1
        )
    }
    store = try .init(
        path: temporary.database.path,
        configuration: configuration,
        maximumPageCount: initialPageCount
    )

    var committedCount = 1
    var rejectedDraft: AuditEventDraftV0?
    for index in 2...5_000 {
        let draft = try auditStoragePressureDraft(index: index)
        do {
            _ = try await store?.append(draft)
            committedCount += 1
        } catch let AuditStoreErrorV0.sqlite(_, code, _)
            where code == SQLITE_FULL {
            rejectedDraft = draft
            break
        }
    }
    let rejected = try #require(rejectedDraft)
    #expect(committedCount <= SQLiteBoundedAuditStoreV0.maximumPageSize)
    let afterBestEffortFailure = try #require(try await store?.page(
        scope: .localAdministration,
        limit: SQLiteBoundedAuditStoreV0.maximumPageSize
    ))
    #expect(afterBestEffortFailure.events.count == committedCount)
    #expect(!afterBestEffortFailure.events.contains {
        $0.draft.eventID == rejected.eventID
    })
    #expect(!afterBestEffortFailure.gaps.historyIsIncomplete)

    let required = try auditStoragePressureDraft(
        index: 6_000,
        importance: .requiredBeforeEffect
    )
    do {
        _ = try await store?.append(required)
        Issue.record("required audit append unexpectedly bypassed page cap")
    } catch let AuditStoreErrorV0.sqlite(_, code, _)
        where code == SQLITE_FULL {
    }
    let afterRequiredFailure = try #require(try await store?.page(
        scope: .localAdministration,
        limit: SQLiteBoundedAuditStoreV0.maximumPageSize
    ))
    #expect(afterRequiredFailure == afterBestEffortFailure)

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
    #expect(try auditRawSQLiteText(
        rawDatabase,
        sql: "PRAGMA integrity_check"
    ) == "ok")
    sqlite3_close(rawDatabase)
    rawDatabase = nil

    let reopened = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: configuration,
        maximumPageCount: initialPageCount + 128
    )
    #expect(try await reopened.append(rejected) == .recorded(.init(
        sequence: UInt64(committedCount + 1),
        draft: rejected
    )))
    #expect(try await reopened.append(required) == .recorded(.init(
        sequence: UInt64(committedCount + 2),
        draft: required
    )))
}

@Test func requestingDeviceSeesOnlyItselfAndPrivacySafeGlobalRows() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(path: temporary.database.path)
    _ = try await store.append(auditDraft(time: 1, deviceID: auditDeviceA))
    _ = try await store.append(auditDraft(time: 2, deviceID: auditDeviceB))
    _ = try await store.append(try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: 3,
        actor: .localUser,
        visibility: .localOnly,
        code: .policyChanged,
        importance: .requiredBeforeEffect
    ))
    _ = try await store.append(globalAuditDraft(time: 4))

    let selfPage = try await store.page(
        scope: .requestingDevice(auditDeviceA),
        limit: 10
    )
    #expect(selfPage.events.map(\.sequence) == [4, 1])
    #expect(selfPage.events.allSatisfy {
        $0.draft.subjectDeviceID == nil
            || $0.draft.subjectDeviceID == auditDeviceA
    })
    #expect(try await store.page(
        scope: .localAdministration,
        limit: 10
    ).events.count == 4)
}

@Test func requestingDeviceGapMetadataDoesNotRevealAnotherDeviceDrops() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: auditConfiguration(rate: 1)
    )
    _ = try await store.append(auditDraft(time: 1, deviceID: auditDeviceB))
    #expect(try await store.append(auditDraft(
        time: 2,
        deviceID: auditDeviceB
    )) == .droppedRateLimited)

    let deviceA = try await store.page(
        scope: .requestingDevice(auditDeviceA),
        limit: 10
    )
    #expect(deviceA.events.isEmpty)
    #expect(!deviceA.gaps.historyIsIncomplete)
    let deviceB = try await store.page(
        scope: .requestingDevice(auditDeviceB),
        limit: 10
    )
    #expect(deviceB.gaps.droppedEventCount == 1)
}

@Test func rowCompactionEvictsOnlyOldestBestEffortAndReportsScopedGap() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: auditConfiguration(rows: 2)
    )
    _ = try await store.append(auditDraft(time: 1))
    _ = try await store.append(auditDraft(
        time: 2,
        importance: .requiredBeforeEffect
    ))
    _ = try await store.append(auditDraft(time: 3))

    let local = try await store.page(scope: .localAdministration, limit: 10)
    #expect(local.events.map(\.sequence) == [3, 2])
    #expect(local.gaps.prunedThroughSequence == 1)
    let remote = try await store.page(
        scope: .requestingDevice(auditDeviceA),
        limit: 10
    )
    #expect(remote.gaps.prunedThroughSequence == 1)
    #expect(remote.gaps.droppedEventCount == 0)
}

@Test func fullRequiredQuotaFailsClosedWhileBestEffortCreatesDurableGap() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: auditConfiguration(rows: 2)
    )
    _ = try await store.append(auditDraft(
        time: 1,
        importance: .requiredBeforeEffect
    ))
    _ = try await store.append(auditDraft(
        time: 2,
        importance: .requiredBeforeEffect
    ))
    await #expect(throws: AuditStoreErrorV0.quotaExceeded) {
        _ = try await store.append(auditDraft(
            time: 3,
            importance: .requiredBeforeEffect
        ))
    }
    #expect(try await store.append(auditDraft(time: 3)) == .droppedQuotaExceeded)
    let page = try await store.page(
        scope: .requestingDevice(auditDeviceA),
        limit: 10
    )
    #expect(page.events.map(\.sequence) == [2, 1])
    #expect(page.gaps.droppedEventCount == 1)
}

@Test func logicalByteQuotaCompactsWithoutExceedingConfiguredLimit() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: auditConfiguration(bytes: 1_024, rows: 20)
    )
    for time in 1...8 {
        _ = try await store.append(auditDraft(time: Int64(time)))
    }
    let page = try await store.page(scope: .localAdministration, limit: 20)
    #expect(!page.events.isEmpty)
    #expect(page.events.count < 8)
    #expect(page.events.reduce(0) { $0 + $1.draft.logicalSize } <= 1_024)
    #expect(page.gaps.historyIsIncomplete)
}

@Test func retentionPurgesOldRowsAndPreservesExplicitGapAcrossRestart() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let configuration = try auditConfiguration(retention: 1_000)
    var store: SQLiteBoundedAuditStoreV0? = try .init(
        path: temporary.database.path,
        configuration: configuration
    )
    _ = try await store?.append(auditDraft(time: 1))
    _ = try await store?.append(auditDraft(time: 2_000))
    #expect(try await store?.page(
        scope: .localAdministration,
        limit: 10
    ).gaps.prunedThroughSequence == 1)
    store = nil

    let reopened = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: configuration
    )
    let page = try await reopened.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.sequence) == [2])
    #expect(page.gaps.prunedThroughSequence == 1)
}

@Test func rateLimitDurablyDropsBestEffortButRequiredWriteFails() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(
        path: temporary.database.path,
        configuration: auditConfiguration(rate: 2)
    )
    _ = try await store.append(auditDraft(time: 1))
    _ = try await store.append(auditDraft(time: 2))
    #expect(try await store.append(auditDraft(time: 3)) == .droppedRateLimited)
    await #expect(throws: AuditStoreErrorV0.rateLimitExceeded) {
        _ = try await store.append(auditDraft(
            time: 4,
            importance: .requiredBeforeEffect
        ))
    }
    let page = try await store.page(
        scope: .requestingDevice(auditDeviceA),
        limit: 10
    )
    #expect(page.events.map(\.sequence) == [2, 1])
    #expect(page.gaps.droppedEventCount == 1)
}

@Test func everyInjectedAuditFaultRollsBackRowsCompactionAndGapMetadata() async throws {
    for point in AuditStoreFaultPointV0.allCases {
        let temporary = try TemporaryDatabase()
        defer { temporary.remove() }
        let store = try SQLiteBoundedAuditStoreV0(
            path: temporary.database.path,
            injectedFaults: [point]
        )
        await #expect(throws: AuditStoreErrorV0.injectedFault(point)) {
            _ = try await store.append(auditDraft(time: 1))
        }
        let page = try await store.page(
            scope: .localAdministration,
            limit: 10
        )
        #expect(page.events.isEmpty)
        #expect(!page.gaps.historyIsIncomplete)
    }
}

@Test func auditSequenceExhaustionRecordsMaximumOnceThenFailsClosed() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let store = try SQLiteBoundedAuditStoreV0(path: temporary.database.path)
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    let update = "UPDATE audit_control SET next_sequence = "
        + String(SQLiteBoundedAuditStoreV0.maximumSequence)
        + ", exhausted = 0 WHERE singleton = 1"
    #expect(sqlite3_exec(database, update, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let result = try await store.append(auditDraft(time: 1))
    guard case let .recorded(event) = result else {
        Issue.record("expected maximum-sequence event")
        return
    }
    #expect(event.sequence == SQLiteBoundedAuditStoreV0.maximumSequence)
    await #expect(throws: AuditStoreErrorV0.sequenceExhausted) {
        _ = try await store.append(auditDraft(time: 2))
    }
}

@Test func futureAuditSchemaAndInvalidPaginationFailClosed() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    var database: OpaquePointer?
    #expect(sqlite3_open(temporary.database.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(
        database,
        "PRAGMA user_version = 2",
        nil,
        nil,
        nil
    ) == SQLITE_OK)
    sqlite3_close(database)
    #expect(throws: AuditStoreErrorV0.futureSchema(found: 2, supported: 1)) {
        try SQLiteBoundedAuditStoreV0(path: temporary.database.path)
    }

    let valid = try TemporaryDatabase()
    defer { valid.remove() }
    let store = try SQLiteBoundedAuditStoreV0(path: valid.database.path)
    await #expect(throws: AuditStoreErrorV0.invalidPage) {
        _ = try await store.page(scope: .localAdministration, limit: 0)
    }
    await #expect(throws: AuditStoreErrorV0.invalidPage) {
        _ = try await store.page(
            scope: .localAdministration,
            beforeSequence: 0,
            limit: 1
        )
    }
}
