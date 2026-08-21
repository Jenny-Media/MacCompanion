import CompanionIPC
import CompanionMacUI
import CompanionPersistence
import Foundation
import Testing

private let macAuditKnownDevice = UUID(
    uuidString: "018f9a00-0000-7000-8000-000000000001"
)!

private func macAuditStoredEvent(
    sequence: UInt64,
    deviceID: UUID?,
    code: AuditEventCodeV0,
    outcome: AuditOutcomeV0? = nil
) throws -> LocalAuditEventV0 {
    try LocalAuditEventV0(
        sequence: sequence,
        eventID: UUID(),
        observedAtUnixMilliseconds: Int64(sequence),
        actor: deviceID == nil ? .system : .pairedDevice,
        visibility: deviceID == nil ? .localOnly : .subjectDevice,
        subjectDeviceID: deviceID,
        code: code,
        capabilityID: nil,
        routeClass: nil,
        surfaceKind: nil,
        outcome: outcome
    )
}

private func macAuditPage(
    events: [LocalAuditEventV0],
    next: UInt64? = nil,
    pruned: UInt64? = nil,
    dropped: UInt64 = 0
) throws -> LocalAuditPageResponseV0 {
    try LocalAuditPageResponseV0(
        correlationID: UUID(),
        events: events,
        nextBeforeSequence: next,
        oldestVisibleSequence: events.map(\.sequence).min(),
        newestVisibleSequence: events.map(\.sequence).max(),
        gaps: try LocalAuditGapSummaryV0(
            prunedThroughSequence: pruned,
            droppedEventCount: dropped
        )
    )
}

@Test func macAuditProjectionUsesOnlyLocallyConfirmedDeviceNames() throws {
    let unknownDevice = UUID()
    let projection = MacAuditHistoryProjectionV0(
        page: try macAuditPage(events: [
            try macAuditStoredEvent(
                sequence: 3,
                deviceID: macAuditKnownDevice,
                code: .interactiveStarted
            ),
            try macAuditStoredEvent(
                sequence: 2,
                deviceID: unknownDevice,
                code: .authenticationRejected
            ),
            try macAuditStoredEvent(
                sequence: 1,
                deviceID: nil,
                code: .policyChanged
            ),
        ]),
        locallyConfirmedDeviceNames: [macAuditKnownDevice: "Jenny’s iPhone"]
    )
    #expect(projection.rows.map(\.deviceLabel) == [
        "Jenny’s iPhone",
        "Paired device",
        nil,
    ])
    #expect(!projection.rows.map(\.deviceLabel).contains(unknownDevice.uuidString))
    #expect(projection.rows.map(\.actorLabel) == [
        "Paired device",
        "Paired device",
        "macOS",
    ])
}

@Test func macAuditProjectionPreservesClosedOutcomeAndContinuation() throws {
    let projection = MacAuditHistoryProjectionV0(
        page: try macAuditPage(
            events: [try macAuditStoredEvent(
                sequence: 5,
                deviceID: macAuditKnownDevice,
                code: .operationOutcomeUnknown,
                outcome: .outcomeUnknown
            )],
            next: 5
        ),
        locallyConfirmedDeviceNames: [:]
    )
    #expect(projection.rows.first?.title == "Action outcome unknown")
    #expect(projection.rows.first?.details == ["Outcome unknown"])
    #expect(projection.canLoadOlder)
}

@Test func macAuditProjectionMakesIncompleteEmptyHistoryExplicit() throws {
    let projection = MacAuditHistoryProjectionV0(
        page: try macAuditPage(events: [], pruned: 9, dropped: 1),
        locallyConfirmedDeviceNames: [:]
    )
    #expect(projection.rows.isEmpty)
    #expect(projection.gaps.historyIsIncomplete)
    #expect(projection.gaps.messages == [
        "Some older activity has expired or was compacted.",
        "1 scoped event was not retained.",
    ])
}
