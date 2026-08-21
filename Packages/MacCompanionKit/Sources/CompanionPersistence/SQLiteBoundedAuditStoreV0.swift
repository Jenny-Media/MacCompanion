#if os(macOS)
import CompanionDomain
import Foundation
import SQLite3

private let auditSQLiteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

private final class AuditSQLiteHandleV0: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}

public enum AuditStoreFaultPointV0: String, CaseIterable, Sendable {
    case afterCompaction
    case beforeInsert
    case beforeCommit
}

public enum AuditStoreErrorV0: Error, Equatable, Sendable {
    case sqlite(operation: String, code: Int32, message: String)
    case storageQuotaBelowCurrentUsage(requested: Int32, current: Int32)
    case insecureStoragePath
    case futureSchema(found: Int32, supported: Int32)
    case invalidConfiguration
    case invalidPage
    case duplicateEventID(UUID)
    case rateLimitExceeded
    case quotaExceeded
    case sequenceExhausted
    case corruptRecord
    case injectedFault(AuditStoreFaultPointV0)
}

public struct AuditStoreConfigurationV0: Equatable, Sendable {
    public static let production = try! AuditStoreConfigurationV0(
        logicalByteLimit: 16 * 1_024 * 1_024,
        retainedRowLimit: 50_000,
        retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
        rateLimitAttempts: 120,
        rateLimitWindowMilliseconds: 60_000
    )

    public let logicalByteLimit: Int
    public let retainedRowLimit: Int
    public let retentionMilliseconds: Int64
    public let rateLimitAttempts: Int
    public let rateLimitWindowMilliseconds: Int64

    public init(
        logicalByteLimit: Int,
        retainedRowLimit: Int,
        retentionMilliseconds: Int64,
        rateLimitAttempts: Int,
        rateLimitWindowMilliseconds: Int64
    ) throws {
        guard logicalByteLimit >= AuditEventDraftV0.maximumLogicalSize,
              logicalByteLimit <= 16 * 1_024 * 1_024,
              (1...50_000).contains(retainedRowLimit),
              retentionMilliseconds > 0,
              retentionMilliseconds <= 30 * 24 * 60 * 60 * 1_000,
              (1...10_000).contains(rateLimitAttempts),
              rateLimitWindowMilliseconds > 0,
              rateLimitWindowMilliseconds <= 60_000 else {
            throw AuditStoreErrorV0.invalidConfiguration
        }
        self.logicalByteLimit = logicalByteLimit
        self.retainedRowLimit = retainedRowLimit
        self.retentionMilliseconds = retentionMilliseconds
        self.rateLimitAttempts = rateLimitAttempts
        self.rateLimitWindowMilliseconds = rateLimitWindowMilliseconds
    }
}

public actor SQLiteBoundedAuditStoreV0 {
    public static let schemaVersion: Int32 = 1
    public static let maximumSequence: UInt64 = 9_007_199_254_740_991
    public static let maximumPageSize = 100

    private let handle: AuditSQLiteHandleV0
    private let configuration: AuditStoreConfigurationV0
    private let injectedFaults: Set<AuditStoreFaultPointV0>

    private var database: OpaquePointer { handle.pointer }

    public init(
        path: String,
        configuration: AuditStoreConfigurationV0 = .production,
        injectedFaults: Set<AuditStoreFaultPointV0> = [],
        maximumPageCount: Int32? = nil
    ) throws {
        guard maximumPageCount.map({
            (1...1_073_741_823).contains($0)
        }) ?? true else {
            throw AuditStoreErrorV0.invalidConfiguration
        }
        let preparedPath: String
        do {
            preparedPath = try SQLiteStorePathSecurity.prepareDatabase(
                at: path
            )
        } catch {
            throw AuditStoreErrorV0.insecureStoragePath
        }
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            preparedPath,
            &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = opened.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "unable to allocate SQLite handle"
            if let opened { sqlite3_close(opened) }
            throw AuditStoreErrorV0.sqlite(
                operation: "open",
                code: result,
                message: message
            )
        }
        handle = AuditSQLiteHandleV0(opened)
        self.configuration = configuration
        self.injectedFaults = injectedFaults
        do {
            try Self.configure(database: opened)
            try Self.migrate(database: opened)
            if let maximumPageCount {
                let effectivePageCount = try Self.setMaximumPageCount(
                    maximumPageCount,
                    database: opened
                )
                guard effectivePageCount <= maximumPageCount else {
                    throw AuditStoreErrorV0.storageQuotaBelowCurrentUsage(
                        requested: maximumPageCount,
                        current: effectivePageCount
                    )
                }
            }
            try SQLiteStorePathSecurity.validateDatabaseArtifacts(
                at: preparedPath
            )
        } catch is SQLiteStorePathSecurityError {
            throw AuditStoreErrorV0.insecureStoragePath
        }
    }

    public func append(
        _ draft: AuditEventDraftV0
    ) throws -> AuditAppendResultV0 {
        try execute("BEGIN IMMEDIATE", operation: "begin append")
        do {
            if try eventExists(draft.eventID) {
                throw AuditStoreErrorV0.duplicateEventID(draft.eventID)
            }
            let cutoff = max(
                0,
                draft.observedAtUnixMilliseconds
                    - configuration.retentionMilliseconds
            )
            try pruneExpired(before: cutoff)
            if injectedFaults.contains(.afterCompaction) {
                throw AuditStoreErrorV0.injectedFault(.afterCompaction)
            }

            let admittedByRateLimit = try consumeRateAttempt(for: draft)
            guard admittedByRateLimit else {
                if draft.importance == .requiredBeforeEffect {
                    throw AuditStoreErrorV0.rateLimitExceeded
                }
                try recordDropped(for: draft)
                try failIfInjected(.beforeCommit)
                try execute("COMMIT", operation: "commit rate drop")
                return .droppedRateLimited
            }

            try compactForInsertion(logicalSize: draft.logicalSize)
            let control = try readControl()
            let rowCount = try retainedRowCount()
            guard rowCount < configuration.retainedRowLimit,
                  control.logicalBytes <= configuration.logicalByteLimit
                    - draft.logicalSize else {
                if draft.importance == .requiredBeforeEffect {
                    throw AuditStoreErrorV0.quotaExceeded
                }
                try recordDropped(for: draft)
                try failIfInjected(.beforeCommit)
                try execute("COMMIT", operation: "commit quota drop")
                return .droppedQuotaExceeded
            }
            guard !control.exhausted else {
                throw AuditStoreErrorV0.sequenceExhausted
            }
            let sequence = control.nextSequence
            guard sequence >= 1, sequence <= Self.maximumSequence else {
                throw AuditStoreErrorV0.sequenceExhausted
            }
            try failIfInjected(.beforeInsert)
            try insert(draft, sequence: sequence)
            try advanceControl(
                from: control,
                addedLogicalBytes: draft.logicalSize
            )
            try failIfInjected(.beforeCommit)
            try execute("COMMIT", operation: "commit append")
            return .recorded(.init(sequence: sequence, draft: draft))
        } catch {
            try? execute("ROLLBACK", operation: "rollback append")
            throw error
        }
    }

    public func page(
        scope: AuditReadScopeV0,
        beforeSequence: UInt64? = nil,
        limit: Int
    ) throws -> AuditPageV0 {
        guard (1...Self.maximumPageSize).contains(limit),
              beforeSequence.map({ $0 >= 1 && $0 <= Self.maximumSequence })
                ?? true else {
            throw AuditStoreErrorV0.invalidPage
        }
        let events = try readEvents(
            scope: scope,
            beforeSequence: beforeSequence,
            limit: limit + 1
        )
        let hasMore = events.count > limit
        let visibleEvents = Array(events.prefix(limit))
        let nextCursor = hasMore ? visibleEvents.last?.sequence : nil
        let bounds = try visibleSequenceBounds(scope: scope)
        return AuditPageV0(
            events: visibleEvents,
            nextBeforeSequence: nextCursor,
            oldestVisibleSequence: bounds.oldest,
            newestVisibleSequence: bounds.newest,
            gaps: try gapSummary(scope: scope)
        )
    }

    private struct Control {
        let nextSequence: UInt64
        let exhausted: Bool
        let logicalBytes: Int
    }

    private struct PrunableRow {
        let sequence: UInt64
        let logicalSize: Int
        let visibility: AuditVisibilityV0
        let subjectDeviceID: UUID?
    }

    private func failIfInjected(_ point: AuditStoreFaultPointV0) throws {
        if injectedFaults.contains(point) {
            throw AuditStoreErrorV0.injectedFault(point)
        }
    }

    private func eventExists(_ eventID: UUID) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM audit_events WHERE event_id = ? LIMIT 1",
            operation: "prepare event lookup"
        )
        defer { sqlite3_finalize(statement) }
        try bind(eventID.uuidString.lowercased(), at: 1, to: statement)
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw sqliteError(operation: "read event lookup", code: result)
        }
    }

    private func readControl() throws -> Control {
        let statement = try prepare(
            "SELECT next_sequence, exhausted, logical_bytes FROM audit_control WHERE singleton = 1",
            operation: "prepare control read"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let next = UInt64(exactly: sqlite3_column_int64(statement, 0)),
              let bytes = Int(exactly: sqlite3_column_int64(statement, 2)) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return Control(
            nextSequence: next,
            exhausted: sqlite3_column_int(statement, 1) != 0,
            logicalBytes: bytes
        )
    }

    private func retainedRowCount() throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM audit_events",
            operation: "prepare row count"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let count = Int(exactly: sqlite3_column_int64(statement, 0)) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return count
    }

    private func pruneExpired(before cutoff: Int64) throws {
        while let row = try oldestRow(
            whereClause: "observed_at < ?",
            integerParameter: cutoff
        ) {
            try delete(row)
        }
    }

    private func compactForInsertion(logicalSize: Int) throws {
        while true {
            let control = try readControl()
            let count = try retainedRowCount()
            if count < configuration.retainedRowLimit,
               control.logicalBytes <= configuration.logicalByteLimit
                    - logicalSize {
                return
            }
            guard let victim = try oldestRow(
                whereClause: "importance = ?",
                textParameter: AuditImportanceV0.bestEffort.rawValue
            ) else {
                return
            }
            try delete(victim)
        }
    }

    private func oldestRow(
        whereClause: String,
        integerParameter: Int64? = nil,
        textParameter: String? = nil
    ) throws -> PrunableRow? {
        let statement = try prepare(
            "SELECT sequence, logical_size, visibility, subject_device_id "
                + "FROM audit_events WHERE \(whereClause) ORDER BY sequence ASC LIMIT 1",
            operation: "prepare compaction candidate"
        )
        defer { sqlite3_finalize(statement) }
        if let integerParameter {
            try bind(integerParameter, at: 1, to: statement)
        } else if let textParameter {
            try bind(textParameter, at: 1, to: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let sequence = UInt64(exactly: sqlite3_column_int64(statement, 0)),
              let size = Int(exactly: sqlite3_column_int64(statement, 1)),
              let visibilityText = text(statement, column: 2),
              let visibility = AuditVisibilityV0(rawValue: visibilityText) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        let subject = try optionalUUID(statement, column: 3)
        return PrunableRow(
            sequence: sequence,
            logicalSize: size,
            visibility: visibility,
            subjectDeviceID: subject
        )
    }

    private func delete(_ row: PrunableRow) throws {
        let statement = try prepare(
            "DELETE FROM audit_events WHERE sequence = ?",
            operation: "prepare compact delete"
        )
        defer { sqlite3_finalize(statement) }
        try bind(row.sequence, at: 1, to: statement)
        try stepDone(statement, operation: "compact delete")

        let update = try prepare(
            "UPDATE audit_control SET logical_bytes = logical_bytes - ? WHERE singleton = 1",
            operation: "prepare compact bytes"
        )
        defer { sqlite3_finalize(update) }
        try bind(row.logicalSize, at: 1, to: update)
        try stepDone(update, operation: "compact bytes")
        try recordPruned(row.sequence, scope: "local")
        if let scope = visibilityGapScope(
            row.visibility,
            subjectDeviceID: row.subjectDeviceID
        ) {
            try recordPruned(row.sequence, scope: scope)
        }
    }

    private func consumeRateAttempt(
        for draft: AuditEventDraftV0
    ) throws -> Bool {
        let statement = try prepare(
            "SELECT window_started_at, attempts FROM audit_rate_windows WHERE bucket = ?",
            operation: "prepare rate read"
        )
        defer { sqlite3_finalize(statement) }
        try bind(draft.rateLimitBucket, at: 1, to: statement)
        let result = sqlite3_step(statement)
        let now = draft.observedAtUnixMilliseconds
        if result == SQLITE_DONE {
            try upsertRateWindow(
                bucket: draft.rateLimitBucket,
                startedAt: now,
                attempts: 1
            )
            return true
        }
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: "read rate window", code: result)
        }
        let started = sqlite3_column_int64(statement, 0)
        let attempts = Int(sqlite3_column_int64(statement, 1))
        if now >= started,
           now - started >= configuration.rateLimitWindowMilliseconds {
            try upsertRateWindow(
                bucket: draft.rateLimitBucket,
                startedAt: now,
                attempts: 1
            )
            return true
        }
        try upsertRateWindow(
            bucket: draft.rateLimitBucket,
            startedAt: started,
            attempts: attempts + 1
        )
        return attempts < configuration.rateLimitAttempts
    }

    private func upsertRateWindow(
        bucket: String,
        startedAt: Int64,
        attempts: Int
    ) throws {
        let statement = try prepare(
            "INSERT INTO audit_rate_windows(bucket, window_started_at, attempts) "
                + "VALUES(?, ?, ?) ON CONFLICT(bucket) DO UPDATE SET "
                + "window_started_at = excluded.window_started_at, attempts = excluded.attempts",
            operation: "prepare rate update"
        )
        defer { sqlite3_finalize(statement) }
        try bind(bucket, at: 1, to: statement)
        try bind(startedAt, at: 2, to: statement)
        try bind(attempts, at: 3, to: statement)
        try stepDone(statement, operation: "update rate window")
    }

    private func recordDropped(for draft: AuditEventDraftV0) throws {
        try recordDropped(scope: "local")
        if let scope = visibilityGapScope(
            draft.visibility,
            subjectDeviceID: draft.subjectDeviceID
        ) {
            try recordDropped(scope: scope)
        }
    }

    private func recordDropped(scope: String) throws {
        let statement = try prepare(
            "INSERT INTO audit_gaps(scope, pruned_through_sequence, dropped_count) "
                + "VALUES(?, NULL, 1) ON CONFLICT(scope) DO UPDATE SET "
                + "dropped_count = dropped_count + 1",
            operation: "prepare drop gap"
        )
        defer { sqlite3_finalize(statement) }
        try bind(scope, at: 1, to: statement)
        try stepDone(statement, operation: "record drop gap")
    }

    private func recordPruned(_ sequence: UInt64, scope: String) throws {
        let statement = try prepare(
            "INSERT INTO audit_gaps(scope, pruned_through_sequence, dropped_count) "
                + "VALUES(?, ?, 0) ON CONFLICT(scope) DO UPDATE SET "
                + "pruned_through_sequence = CASE "
                + "WHEN pruned_through_sequence IS NULL OR pruned_through_sequence < excluded.pruned_through_sequence "
                + "THEN excluded.pruned_through_sequence ELSE pruned_through_sequence END",
            operation: "prepare prune gap"
        )
        defer { sqlite3_finalize(statement) }
        try bind(scope, at: 1, to: statement)
        try bind(sequence, at: 2, to: statement)
        try stepDone(statement, operation: "record prune gap")
    }

    private func visibilityGapScope(
        _ visibility: AuditVisibilityV0,
        subjectDeviceID: UUID?
    ) -> String? {
        switch visibility {
        case .localOnly:
            nil
        case .subjectDevice:
            subjectDeviceID.map {
                "device:" + $0.uuidString.lowercased()
            }
        case .allPairedDevices:
            "all"
        }
    }

    private func insert(
        _ draft: AuditEventDraftV0,
        sequence: UInt64
    ) throws {
        let statement = try prepare(
            "INSERT INTO audit_events("
                + "sequence,event_id,observed_at,actor,visibility,subject_device_id,"
                + "correlation_id,operation_id,interactive_session_id,event_code,"
                + "capability_id,policy_revision,authorization_epoch,grant_revision,"
                + "route_class,surface_kind,outcome,importance,logical_size"
                + ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            operation: "prepare audit insert"
        )
        defer { sqlite3_finalize(statement) }
        try bind(sequence, at: 1, to: statement)
        try bind(draft.eventID.uuidString.lowercased(), at: 2, to: statement)
        try bind(draft.observedAtUnixMilliseconds, at: 3, to: statement)
        try bind(draft.actor.rawValue, at: 4, to: statement)
        try bind(draft.visibility.rawValue, at: 5, to: statement)
        try bind(draft.subjectDeviceID, at: 6, to: statement)
        try bind(draft.correlationID, at: 7, to: statement)
        try bind(draft.operationID, at: 8, to: statement)
        try bind(draft.interactiveSessionID, at: 9, to: statement)
        try bind(draft.code.rawValue, at: 10, to: statement)
        try bind(draft.capabilityID, at: 11, to: statement)
        try bind(draft.policyRevision?.rawValue, at: 12, to: statement)
        try bind(draft.authorizationEpoch?.rawValue, at: 13, to: statement)
        try bind(draft.grantRevision?.rawValue, at: 14, to: statement)
        try bind(draft.routeClass?.rawValue, at: 15, to: statement)
        try bind(draft.surfaceKind?.rawValue, at: 16, to: statement)
        try bind(draft.outcome?.rawValue, at: 17, to: statement)
        try bind(draft.importance.rawValue, at: 18, to: statement)
        try bind(draft.logicalSize, at: 19, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_CONSTRAINT {
            throw AuditStoreErrorV0.duplicateEventID(draft.eventID)
        }
        guard result == SQLITE_DONE else {
            throw sqliteError(operation: "insert audit event", code: result)
        }
    }

    private func advanceControl(
        from control: Control,
        addedLogicalBytes: Int
    ) throws {
        let reachedEnd = control.nextSequence == Self.maximumSequence
        let next = reachedEnd
            ? control.nextSequence
            : control.nextSequence + 1
        let statement = try prepare(
            "UPDATE audit_control SET next_sequence = ?, exhausted = ?, "
                + "logical_bytes = logical_bytes + ? WHERE singleton = 1",
            operation: "prepare control advance"
        )
        defer { sqlite3_finalize(statement) }
        try bind(next, at: 1, to: statement)
        try bind(reachedEnd ? 1 : 0, at: 2, to: statement)
        try bind(addedLogicalBytes, at: 3, to: statement)
        try stepDone(statement, operation: "advance control")
    }

    private func readEvents(
        scope: AuditReadScopeV0,
        beforeSequence: UInt64?,
        limit: Int
    ) throws -> [StoredAuditEventV0] {
        let clause: String
        switch scope {
        case .localAdministration:
            clause = "1 = 1"
        case .requestingDevice:
            clause = "(visibility = 'allPairedDevices' OR "
                + "(visibility = 'subjectDevice' AND subject_device_id = ?))"
        }
        var sql = "SELECT sequence,event_id,observed_at,actor,visibility,"
            + "subject_device_id,correlation_id,operation_id,interactive_session_id,"
            + "event_code,capability_id,policy_revision,authorization_epoch,"
            + "grant_revision,route_class,surface_kind,outcome,importance "
            + "FROM audit_events WHERE \(clause)"
        if beforeSequence != nil { sql += " AND sequence < ?" }
        sql += " ORDER BY sequence DESC LIMIT ?"
        let statement = try prepare(sql, operation: "prepare audit page")
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if case let .requestingDevice(deviceID) = scope {
            try bind(deviceID.uuidString.lowercased(), at: index, to: statement)
            index += 1
        }
        if let beforeSequence {
            try bind(beforeSequence, at: index, to: statement)
            index += 1
        }
        try bind(limit, at: index, to: statement)
        var events: [StoredAuditEventV0] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw sqliteError(operation: "read audit page", code: result)
            }
            events.append(try decodeEvent(statement))
        }
        return events
    }

    private func decodeEvent(
        _ statement: OpaquePointer
    ) throws -> StoredAuditEventV0 {
        guard let sequence = UInt64(exactly: sqlite3_column_int64(statement, 0)),
              let eventID = try optionalUUID(statement, column: 1),
              let actorText = text(statement, column: 3),
              let actor = AuditActorV0(rawValue: actorText),
              let visibilityText = text(statement, column: 4),
              let visibility = AuditVisibilityV0(rawValue: visibilityText),
              let codeText = text(statement, column: 9),
              let code = AuditEventCodeV0(rawValue: codeText),
              let importanceText = text(statement, column: 17),
              let importance = AuditImportanceV0(rawValue: importanceText) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        let draft: AuditEventDraftV0
        do {
            draft = try AuditEventDraftV0(
                eventID: eventID,
                observedAtUnixMilliseconds: sqlite3_column_int64(statement, 2),
                actor: actor,
                visibility: visibility,
                subjectDeviceID: try optionalUUID(statement, column: 5),
                correlationID: try optionalUUID(statement, column: 6),
                operationID: try optionalUUID(statement, column: 7),
                interactiveSessionID: try optionalUUID(statement, column: 8),
                code: code,
                capabilityID: text(statement, column: 10),
                policyRevision: try optionalRevision(statement, column: 11),
                authorizationEpoch: try optionalRevision(statement, column: 12),
                grantRevision: try optionalRevision(statement, column: 13),
                routeClass: try optionalEnum(statement, column: 14),
                surfaceKind: try optionalEnum(statement, column: 15),
                outcome: try optionalEnum(statement, column: 16),
                importance: importance
            )
        } catch {
            throw AuditStoreErrorV0.corruptRecord
        }
        return StoredAuditEventV0(sequence: sequence, draft: draft)
    }

    private func visibleSequenceBounds(
        scope: AuditReadScopeV0
    ) throws -> (oldest: UInt64?, newest: UInt64?) {
        let clause: String
        switch scope {
        case .localAdministration:
            clause = "1 = 1"
        case .requestingDevice:
            clause = "(visibility = 'allPairedDevices' OR "
                + "(visibility = 'subjectDevice' AND subject_device_id = ?))"
        }
        let statement = try prepare(
            "SELECT MIN(sequence), MAX(sequence) FROM audit_events WHERE \(clause)",
            operation: "prepare visible bounds"
        )
        defer { sqlite3_finalize(statement) }
        if case let .requestingDevice(deviceID) = scope {
            try bind(deviceID.uuidString.lowercased(), at: 1, to: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return (
            optionalUInt64(statement, column: 0),
            optionalUInt64(statement, column: 1)
        )
    }

    private func gapSummary(
        scope: AuditReadScopeV0
    ) throws -> AuditGapSummaryV0 {
        let scopes: [String] = switch scope {
        case .localAdministration:
            ["local"]
        case let .requestingDevice(deviceID):
            ["device:" + deviceID.uuidString.lowercased(), "all"]
        }
        let statement = try prepare(
            "SELECT MAX(pruned_through_sequence), COALESCE(SUM(dropped_count), 0) "
                + "FROM audit_gaps WHERE scope IN (?, ?)",
            operation: "prepare gap summary"
        )
        defer { sqlite3_finalize(statement) }
        try bind(scopes[0], at: 1, to: statement)
        if scopes.count == 2 {
            try bind(scopes[1], at: 2, to: statement)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AuditStoreErrorV0.corruptRecord
        }
        let droppedRaw = sqlite3_column_int64(statement, 1)
        guard droppedRaw >= 0 else { throw AuditStoreErrorV0.corruptRecord }
        return AuditGapSummaryV0(
            prunedThroughSequence: optionalUInt64(statement, column: 0),
            droppedEventCount: UInt64(droppedRaw)
        )
    }

    private static func configure(database: OpaquePointer) throws {
        try execute(
            database: database,
            sql: "PRAGMA journal_mode = WAL",
            operation: "enable WAL"
        )
        try execute(
            database: database,
            sql: "PRAGMA synchronous = FULL",
            operation: "enable full sync"
        )
        try execute(
            database: database,
            sql: "PRAGMA foreign_keys = ON",
            operation: "enable foreign keys"
        )
    }

    private static func setMaximumPageCount(
        _ maximumPageCount: Int32,
        database: OpaquePointer
    ) throws -> Int32 {
        let sql = "PRAGMA max_page_count = \(maximumPageCount)"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        )
        guard prepareResult == SQLITE_OK, let statement else {
            throw AuditStoreErrorV0.sqlite(
                operation: "configure maximum page count",
                code: prepareResult,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw AuditStoreErrorV0.sqlite(
                operation: "configure maximum page count",
                code: stepResult,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func migrate(database: OpaquePointer) throws {
        let version = currentVersion(database)
        guard version <= schemaVersion else {
            throw AuditStoreErrorV0.futureSchema(
                found: version,
                supported: schemaVersion
            )
        }
        if version == schemaVersion { return }
        try execute(
            database: database,
            sql: "BEGIN IMMEDIATE",
            operation: "begin audit migration"
        )
        do {
            try execute(
                database: database,
                sql: """
                CREATE TABLE audit_control(
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    next_sequence INTEGER NOT NULL CHECK(next_sequence >= 1),
                    exhausted INTEGER NOT NULL CHECK(exhausted IN (0,1)),
                    logical_bytes INTEGER NOT NULL CHECK(logical_bytes >= 0)
                );
                INSERT INTO audit_control VALUES(1, 1, 0, 0);
                CREATE TABLE audit_events(
                    sequence INTEGER PRIMARY KEY,
                    event_id TEXT NOT NULL UNIQUE,
                    observed_at INTEGER NOT NULL CHECK(observed_at >= 0),
                    actor TEXT NOT NULL,
                    visibility TEXT NOT NULL,
                    subject_device_id TEXT,
                    correlation_id TEXT,
                    operation_id TEXT,
                    interactive_session_id TEXT,
                    event_code TEXT NOT NULL,
                    capability_id TEXT,
                    policy_revision INTEGER,
                    authorization_epoch INTEGER,
                    grant_revision INTEGER,
                    route_class TEXT,
                    surface_kind TEXT,
                    outcome TEXT,
                    importance TEXT NOT NULL,
                    logical_size INTEGER NOT NULL CHECK(logical_size > 0)
                );
                CREATE INDEX audit_events_time ON audit_events(observed_at);
                CREATE INDEX audit_events_device_sequence
                    ON audit_events(subject_device_id, sequence DESC);
                CREATE TABLE audit_rate_windows(
                    bucket TEXT PRIMARY KEY,
                    window_started_at INTEGER NOT NULL CHECK(window_started_at >= 0),
                    attempts INTEGER NOT NULL CHECK(attempts >= 1)
                );
                CREATE TABLE audit_gaps(
                    scope TEXT PRIMARY KEY,
                    pruned_through_sequence INTEGER,
                    dropped_count INTEGER NOT NULL CHECK(dropped_count >= 0)
                );
                PRAGMA user_version = 1;
                """,
                operation: "create audit schema"
            )
            try execute(
                database: database,
                sql: "COMMIT",
                operation: "commit audit migration"
            )
        } catch {
            try? execute(
                database: database,
                sql: "ROLLBACK",
                operation: "rollback audit migration"
            )
            throw error
        }
    }

    private static func currentVersion(_ database: OpaquePointer) -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA user_version",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            return Int32.max
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return Int32.max }
        return sqlite3_column_int(statement, 0)
    }

    private static func execute(
        database: OpaquePointer,
        sql: String,
        operation: String
    ) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw AuditStoreErrorV0.sqlite(
                operation: operation,
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
    }

    private func execute(_ sql: String, operation: String) throws {
        try Self.execute(database: database, sql: sql, operation: operation)
    }

    private func prepare(
        _ sql: String,
        operation: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw sqliteError(operation: operation, code: result)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, operation: String) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteError(operation: operation, code: result)
        }
    }

    private func sqliteError(
        operation: String,
        code: Int32
    ) -> AuditStoreErrorV0 {
        .sqlite(
            operation: operation,
            code: code,
            message: String(cString: sqlite3_errmsg(database))
        )
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(
                statement,
                index,
                value,
                -1,
                auditSQLiteTransient
            )
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind text", code: result)
        }
    }

    private func bind(
        _ value: UUID?,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        try bind(value?.uuidString.lowercased(), at: index, to: statement)
    }

    private func bind(
        _ value: Int,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        guard let converted = Int64(exactly: value) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        try bind(converted, at: index, to: statement)
    }

    private func bind(
        _ value: Int64,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind integer", code: result)
        }
    }

    private func bind(
        _ value: UInt64?,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        if let value {
            guard let converted = Int64(exactly: value) else {
                throw AuditStoreErrorV0.corruptRecord
            }
            try bind(converted, at: index, to: statement)
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else {
                throw sqliteError(operation: "bind null", code: result)
            }
        }
    }

    private func bind(
        _ value: UInt64,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        try bind(Optional(value), at: index, to: statement)
    }

    private func text(
        _ statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: bytes)
    }

    private func optionalUUID(
        _ statement: OpaquePointer,
        column: Int32
    ) throws -> UUID? {
        guard let value = text(statement, column: column) else { return nil }
        guard let uuid = UUID(uuidString: value),
              uuid.uuidString.lowercased() == value else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return uuid
    }

    private func optionalUInt64(
        _ statement: OpaquePointer,
        column: Int32
    ) -> UInt64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return UInt64(exactly: sqlite3_column_int64(statement, column))
    }

    private func optionalRevision<Tag>(
        _ statement: OpaquePointer,
        column: Int32
    ) throws -> MonotonicRevision<Tag>? {
        guard let raw = optionalUInt64(statement, column: column) else {
            return nil
        }
        guard raw >= 1, raw <= Self.maximumSequence else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return MonotonicRevision<Tag>(rawValue: raw)
    }

    private func optionalEnum<Value: RawRepresentable>(
        _ statement: OpaquePointer,
        column: Int32
    ) throws -> Value? where Value.RawValue == String {
        guard let raw = text(statement, column: column) else { return nil }
        guard let value = Value(rawValue: raw) else {
            throw AuditStoreErrorV0.corruptRecord
        }
        return value
    }
}
#endif
