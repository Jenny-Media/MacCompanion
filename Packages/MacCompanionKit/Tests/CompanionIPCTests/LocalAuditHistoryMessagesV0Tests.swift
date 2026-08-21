import CompanionIPC
import CompanionPersistence
import Foundation
import Testing

private let localAuditDeviceID = UUID(
    uuidString: "018fa100-0000-7000-8000-000000000001"
)!

private func localAuditEvent(
    sequence: UInt64,
    visibility: AuditVisibilityV0 = .subjectDevice,
    deviceID: UUID? = localAuditDeviceID,
    code: AuditEventCodeV0 = .operationCompleted
) throws -> LocalAuditEventV0 {
    try LocalAuditEventV0(
        sequence: sequence,
        eventID: UUID(),
        observedAtUnixMilliseconds: Int64(sequence),
        actor: deviceID == nil ? .system : .pairedDevice,
        visibility: visibility,
        subjectDeviceID: deviceID,
        code: code,
        capabilityID: deviceID == nil
            ? nil
            : "maccompanion.system.setAudioMuted",
        routeClass: nil,
        surfaceKind: nil,
        outcome: deviceID == nil ? nil : .succeeded
    )
}

@Test func localAuditRequestIsBoundedAndRejectsUnknownFields() throws {
    let request = try LocalAuditPageRequestV0(
        requestID: UUID(),
        beforeSequence: 9,
        limit: 100
    )
    let encoded = try JSONEncoder().encode(request)
    #expect(try JSONDecoder().decode(
        LocalAuditPageRequestV0.self,
        from: encoded
    ) == request)
    #expect(throws: LocalAuditHistoryMessageErrorV0.invalidRequest) {
        _ = try LocalAuditPageRequestV0(
            requestID: UUID(),
            beforeSequence: 0,
            limit: 1
        )
    }
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            LocalAuditPageRequestV0.self,
            from: Data("""
                {"protocolVersion":{"major":0,"minor":1},"requestID":"018fa200-0000-7000-8000-000000000001","limit":10,"unknown":true}
                """.utf8)
        )
    }
}

@Test func localAuditPageRoundTripsAndCorrelatesExclusiveCursor() throws {
    let request = try LocalAuditPageRequestV0(
        requestID: UUID(),
        beforeSequence: 10,
        limit: 2
    )
    let page = try LocalAuditPageResponseV0(
        correlationID: request.requestID,
        events: [try localAuditEvent(sequence: 9), try localAuditEvent(sequence: 8)],
        nextBeforeSequence: 8,
        oldestVisibleSequence: 1,
        newestVisibleSequence: 9,
        gaps: try LocalAuditGapSummaryV0(
            prunedThroughSequence: nil,
            droppedEventCount: 0
        )
    )
    try page.validate(against: request)
    #expect(try JSONDecoder().decode(
        LocalAuditPageResponseV0.self,
        from: JSONEncoder().encode(page)
    ) == page)
    let wrong = try LocalAuditPageRequestV0(
        requestID: UUID(),
        beforeSequence: 10,
        limit: 2
    )
    #expect(throws: LocalAuditHistoryMessageErrorV0.invalidPage) {
        try page.validate(against: wrong)
    }
}

@Test func localAuditPageRejectsOrderingAndGlobalDetailLeaks() throws {
    #expect(throws: LocalAuditHistoryMessageErrorV0.invalidPage) {
        _ = try LocalAuditPageResponseV0(
            correlationID: UUID(),
            events: [
                try localAuditEvent(sequence: 1),
                try localAuditEvent(sequence: 2),
            ],
            nextBeforeSequence: nil,
            oldestVisibleSequence: 1,
            newestVisibleSequence: 2,
            gaps: try LocalAuditGapSummaryV0(
                prunedThroughSequence: nil,
                droppedEventCount: 0
            )
        )
    }
    #expect(throws: LocalAuditHistoryMessageErrorV0.invalidEvent) {
        _ = try LocalAuditEventV0(
            sequence: 1,
            eventID: UUID(),
            observedAtUnixMilliseconds: 1,
            actor: .system,
            visibility: .allPairedDevices,
            subjectDeviceID: localAuditDeviceID,
            code: .hostSecurityStateChanged,
            capabilityID: nil,
            routeClass: nil,
            surfaceKind: nil,
            outcome: nil
        )
    }
}
