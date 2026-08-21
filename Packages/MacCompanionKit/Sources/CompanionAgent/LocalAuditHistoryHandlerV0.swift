import CompanionIPC
import CompanionPersistence
import Foundation

public enum LocalAuditHistoryHandlerErrorV0: Error, Equatable, Sendable {
    case storageUnavailable
    case unmappableRecord
}

/// Maps an already-authenticated menu-app request to local-administration
/// scope. Caller identity is established by the future XPC adapter, never by
/// this payload.
public actor LocalAuditHistoryHandlerV0 {
    private let store: SQLiteBoundedAuditStoreV0

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func handle(
        _ request: LocalAuditPageRequestV0
    ) async throws -> LocalAuditPageResponseV0 {
        let page: AuditPageV0
        do {
            page = try await store.page(
                scope: .localAdministration,
                beforeSequence: request.beforeSequence,
                limit: Int(request.limit)
            )
        } catch {
            throw LocalAuditHistoryHandlerErrorV0.storageUnavailable
        }
        do {
            let response = try LocalAuditPageResponseV0(
                correlationID: request.requestID,
                events: try page.events.map(Self.map),
                nextBeforeSequence: page.nextBeforeSequence,
                oldestVisibleSequence: page.oldestVisibleSequence,
                newestVisibleSequence: page.newestVisibleSequence,
                gaps: try LocalAuditGapSummaryV0(
                    prunedThroughSequence: page.gaps.prunedThroughSequence,
                    droppedEventCount: page.gaps.droppedEventCount
                )
            )
            try response.validate(against: request)
            return response
        } catch {
            throw LocalAuditHistoryHandlerErrorV0.unmappableRecord
        }
    }

    private static func map(
        _ stored: StoredAuditEventV0
    ) throws -> LocalAuditEventV0 {
        let value = stored.draft
        return try LocalAuditEventV0(
            sequence: stored.sequence,
            eventID: value.eventID,
            observedAtUnixMilliseconds: value.observedAtUnixMilliseconds,
            actor: value.actor,
            visibility: value.visibility,
            subjectDeviceID: value.subjectDeviceID,
            code: value.code,
            capabilityID: value.capabilityID,
            routeClass: value.routeClass,
            surfaceKind: value.surfaceKind,
            outcome: value.outcome
        )
    }
}
