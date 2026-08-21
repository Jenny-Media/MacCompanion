import CompanionClient
import CompanionWire
import Foundation
import Testing

private func clientAuditEvent(_ sequence: Int64) throws -> AuditSelfEventWireV1 {
    try AuditSelfEventWireV1(
        sequence: sequence,
        eventID: WireUUID(UUID()),
        observedAtUnixMilliseconds: sequence,
        scope: .selfDevice,
        actor: .agent,
        code: .connectionOpened,
        outcome: .succeeded
    )
}

private func clientAuditResponse(
    correlationID: WireUUID,
    sequences: [Int64],
    next: Int64?
) throws -> Data {
    let events = try sequences.map(clientAuditEvent)
    return try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: correlationID,
        sentAtUnixMilliseconds: 100,
        body: AuditListResponseBodyV1(
            events: events,
            nextBeforeSequence: next,
            oldestVisibleSequence: 1,
            newestVisibleSequence: 10,
            gaps: AuditGapWireV1(
                prunedThroughSequence: nil,
                droppedEventCount: 0
            )
        )
    ))
}

@Test func auditPagerBuildsExactFirstAndContinuationRequests() throws {
    var pager = ClientAuditPagerV1()
    let firstID = WireUUID(UUID())
    let firstRequest = try WireCodec.decode(
        WireEnvelope<AuditListRequestBodyV1>.self,
        from: pager.requestNextPage(
            messageID: firstID,
            limit: 2,
            sentAtUnixMilliseconds: 1
        )
    )
    #expect(firstRequest.body.beforeSequence == nil)
    let first = try pager.acceptPage(clientAuditResponse(
        correlationID: firstID,
        sequences: [10, 9],
        next: 9
    ))
    #expect(first.events.map(\.sequence) == [10, 9])
    #expect(pager.state == .readyForContinuation)

    let secondID = WireUUID(UUID())
    let secondRequest = try WireCodec.decode(
        WireEnvelope<AuditListRequestBodyV1>.self,
        from: pager.requestNextPage(
            messageID: secondID,
            limit: 2,
            sentAtUnixMilliseconds: 2
        )
    )
    #expect(secondRequest.body.beforeSequence == 9)
    _ = try pager.acceptPage(clientAuditResponse(
        correlationID: secondID,
        sequences: [8, 7],
        next: nil
    ))
    #expect(pager.state == .exhausted)
    #expect(pager.nextBeforeSequence == nil)
}

@Test func auditPagerCorrelationFailureInvalidatesAllContinuationState() throws {
    var pager = ClientAuditPagerV1()
    _ = try pager.requestNextPage(
        messageID: WireUUID(UUID()),
        limit: 20,
        sentAtUnixMilliseconds: 1
    )
    #expect(throws: ClientAuditPagerErrorV1.invalidCorrelation) {
        _ = try pager.acceptPage(clientAuditResponse(
            correlationID: WireUUID(UUID()),
            sequences: [2, 1],
            next: nil
        ))
    }
    #expect(pager.state == .invalidated)
}

@Test func auditPagerRejectsReplayAtExclusiveContinuationCursor() throws {
    var pager = ClientAuditPagerV1()
    let firstID = WireUUID(UUID())
    _ = try pager.requestNextPage(
        messageID: firstID,
        limit: 2,
        sentAtUnixMilliseconds: 1
    )
    _ = try pager.acceptPage(clientAuditResponse(
        correlationID: firstID,
        sequences: [10, 9],
        next: 9
    ))
    let secondID = WireUUID(UUID())
    _ = try pager.requestNextPage(
        messageID: secondID,
        limit: 2,
        sentAtUnixMilliseconds: 2
    )
    #expect(throws: ClientAuditPagerErrorV1.cursorViolation) {
        _ = try pager.acceptPage(clientAuditResponse(
            correlationID: secondID,
            sequences: [9, 8],
            next: nil
        ))
    }
    #expect(pager.state == .invalidated)
}

@Test func auditPagerNeverRestartsAfterExhaustionWithoutExplicitReset() throws {
    var pager = ClientAuditPagerV1()
    let requestID = WireUUID(UUID())
    _ = try pager.requestNextPage(
        messageID: requestID,
        limit: 20,
        sentAtUnixMilliseconds: 1
    )
    _ = try pager.acceptPage(clientAuditResponse(
        correlationID: requestID,
        sequences: [],
        next: nil
    ))
    #expect(throws: ClientAuditPagerErrorV1.invalidState(.exhausted)) {
        _ = try pager.requestNextPage(
            messageID: WireUUID(UUID()),
            limit: 20,
            sentAtUnixMilliseconds: 2
        )
    }
    pager.reset()
    #expect(pager.state == .idle)
}
