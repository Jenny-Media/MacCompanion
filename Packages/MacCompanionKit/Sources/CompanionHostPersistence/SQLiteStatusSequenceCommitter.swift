import CompanionHost
import CompanionPersistence
import Foundation

public struct StatusSequenceBootstrap: Sendable {
    public let state: StatusSequenceState
    public let committer: SQLiteStatusSequenceCommitter
}

public struct SQLiteStatusSequenceCommitter: StatusSequenceCommitting, Sendable {
    private let store: SQLiteSecurityStore

    public init(store: SQLiteSecurityStore) {
        self.store = store
    }

    public func commit(
        expected: StatusSequenceState,
        replacement: StatusSequenceState
    ) async throws {
        try await store.compareAndSwapStatusSequence(
            expected: try stored(expected),
            replacement: try stored(replacement)
        )
    }

    public static func bootstrap(
        store: SQLiteSecurityStore,
        initialGeneration: UUID
    ) async throws -> StatusSequenceBootstrap {
        let record: StoredStatusSequenceRecord
        if let existing = try await store.statusSequence() {
            record = existing
        } else {
            let initial = try StoredStatusSequenceRecord(
                generation: initialGeneration,
                nextRevision: 0,
                exhausted: false
            )
            try await store.initializeStatusSequence(initial)
            record = initial
        }
        return StatusSequenceBootstrap(
            state: try state(record),
            committer: SQLiteStatusSequenceCommitter(store: store)
        )
    }

    private func stored(
        _ state: StatusSequenceState
    ) throws -> StoredStatusSequenceRecord {
        try Self.stored(state)
    }

    private static func stored(
        _ state: StatusSequenceState
    ) throws -> StoredStatusSequenceRecord {
        try StoredStatusSequenceRecord(
            generation: state.generation,
            nextRevision: state.nextRevision,
            exhausted: state.exhausted
        )
    }

    private static func state(
        _ record: StoredStatusSequenceRecord
    ) throws -> StatusSequenceState {
        try StatusSequenceState(
            generation: record.generation,
            nextRevision: record.nextRevision,
            exhausted: record.exhausted
        )
    }
}
