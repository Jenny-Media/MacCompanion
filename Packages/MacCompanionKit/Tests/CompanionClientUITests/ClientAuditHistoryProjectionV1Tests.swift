import CompanionClientUI
import CompanionWire
import Foundation
import Testing

private func clientUIAuditEvent(
    sequence: Int64,
    scope: AuditSelfEventScopeWireV1,
    code: AuditEventCodeWireV1,
    capabilityID: String? = nil,
    outcome: AuditOutcomeWireV1? = nil
) throws -> AuditSelfEventWireV1 {
    try AuditSelfEventWireV1(
        sequence: sequence,
        eventID: WireUUID(UUID()),
        observedAtUnixMilliseconds: 1_710_000_000_000 + sequence,
        scope: scope,
        actor: scope == .host ? .system : .agent,
        code: code,
        capabilityID: capabilityID,
        outcome: outcome
    )
}

private func clientUIAuditPage(
    events: [AuditSelfEventWireV1],
    next: Int64? = nil,
    pruned: Int64? = nil,
    dropped: Int64 = 0
) throws -> AuditListResponseBodyV1 {
    try AuditListResponseBodyV1(
        events: events,
        nextBeforeSequence: next,
        oldestVisibleSequence: events.isEmpty ? nil : 1,
        newestVisibleSequence: events.isEmpty ? nil : 100,
        gaps: AuditGapWireV1(
            prunedThroughSequence: pruned,
            droppedEventCount: dropped
        )
    )
}

@Test func clientAuditProjectionUsesClosedCopyWithoutRemoteIdentityText() throws {
    let page = try clientUIAuditPage(events: [
        clientUIAuditEvent(
            sequence: 2,
            scope: .selfDevice,
            code: .operationCompleted,
            capabilityID: "maccompanion.system.setAudioMuted",
            outcome: .succeeded
        ),
        clientUIAuditEvent(
            sequence: 1,
            scope: .host,
            code: .hostAvailabilityChanged,
            outcome: .unavailable
        ),
    ])
    let projection = ClientAuditHistoryProjectionV1(page: page)
    #expect(projection.rows.map(\.title) == [
        "Action completed",
        "Mac availability changed",
    ])
    #expect(projection.rows.map(\.scopeLabel) == ["This device", "Mac"])
    #expect(projection.rows[0].details == [
        "Capability: maccompanion.system.setAudioMuted",
        "Succeeded",
    ])
    #expect(projection.rows[1].details == ["Unavailable"])
}

@Test func clientAuditProjectionNeverHidesRetentionOrDropGaps() throws {
    let page = try clientUIAuditPage(
        events: [],
        pruned: 8,
        dropped: 2
    )
    let projection = ClientAuditHistoryProjectionV1(page: page)
    #expect(projection.rows.isEmpty)
    #expect(projection.gaps.historyIsIncomplete)
    #expect(projection.gaps.messages == [
        "Some older activity has expired or was compacted.",
        "2 scoped events were not retained.",
    ])
}

@Test func clientAuditProjectionOffersOnlyServerDeclaredContinuation() throws {
    let event = try clientUIAuditEvent(
        sequence: 3,
        scope: .selfDevice,
        code: .connectionOpened
    )
    #expect(ClientAuditHistoryProjectionV1(
        page: try clientUIAuditPage(events: [event], next: 3)
    ).canLoadOlder)
    #expect(!ClientAuditHistoryProjectionV1(
        page: try clientUIAuditPage(events: [event])
    ).canLoadOlder)
}
