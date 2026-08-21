import CompanionDomain
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func auditFixture(_ relativePath: String) throws -> Data {
    try Data(contentsOf: FixturePaths.authoritativeFixtures()
        .appendingPathComponent(relativePath))
}

@Test func authoritativeAuditRequestAndResponseRoundTripCanonically() throws {
    let requestData = try auditFixture("valid/audit-list-request.json")
    let request = try WireCodec.decode(
        WireEnvelope<AuditListRequestBodyV1>.self,
        from: requestData
    )
    #expect(request.body.beforeSequence == nil)
    #expect(request.body.limit == 20)
    #expect(try CanonicalJSON.canonicalize(WireCodec.encode(request))
        == CanonicalJSON.canonicalize(requestData))

    let responseData = try auditFixture("valid/audit-list-response.json")
    let response = try WireCodec.decode(
        WireEnvelope<AuditListResponseBodyV1>.self,
        from: responseData
    )
    #expect(response.body.events.map(\.sequence) == [9, 8])
    #expect(response.body.events.map(\.scope) == [.selfDevice, .host])
    #expect(response.body.nextBeforeSequence == 8)
    #expect(response.body.gaps.prunedThroughSequence == 3)
    #expect(response.body.gaps.droppedEventCount == 1)
    #expect(try CanonicalJSON.canonicalize(WireCodec.encode(response))
        == CanonicalJSON.canonicalize(responseData))
}

@Test func authoritativeAuditHostLeakFixtureFailsClosed() throws {
    #expect(throws: (any Error).self) {
        _ = try WireCodec.decode(
            WireEnvelope<AuditListResponseBodyV1>.self,
            from: auditFixture(
                "invalid/audit-list-host-leaks-device-field.json"
            )
        )
    }
}

@Test func auditRequestAndPageBoundsAreClosed() throws {
    #expect(throws: (any Error).self) {
        _ = try AuditListRequestBodyV1(beforeSequence: 0, limit: 1)
    }
    #expect(throws: (any Error).self) {
        _ = try AuditListRequestBodyV1(beforeSequence: nil, limit: 0)
    }
    #expect(throws: (any Error).self) {
        _ = try AuditListResponseBodyV1(
            events: [],
            nextBeforeSequence: 1,
            oldestVisibleSequence: nil,
            newestVisibleSequence: nil,
            gaps: AuditGapWireV1(
                prunedThroughSequence: nil,
                droppedEventCount: 0
            )
        )
    }
}

@Test func auditResponseRejectsOrderingAndHostScopedDetail() throws {
    let event = try AuditSelfEventWireV1(
        sequence: 2,
        eventID: WireUUID(UUID()),
        observedAtUnixMilliseconds: 1,
        scope: .selfDevice,
        actor: .pairedDevice,
        code: .operationRequested,
        capabilityID: "maccompanion.status.read"
    )
    #expect(throws: (any Error).self) {
        _ = try AuditListResponseBodyV1(
            events: [event, event],
            nextBeforeSequence: nil,
            oldestVisibleSequence: 1,
            newestVisibleSequence: 2,
            gaps: AuditGapWireV1(
                prunedThroughSequence: nil,
                droppedEventCount: 0
            )
        )
    }
    #expect(throws: (any Error).self) {
        _ = try AuditSelfEventWireV1(
            sequence: 1,
            eventID: WireUUID(UUID()),
            observedAtUnixMilliseconds: 1,
            scope: .host,
            actor: .system,
            code: .hostAvailabilityChanged,
            operationID: WireUUID(UUID())
        )
    }
}

@Test func sessionDescriptionRegistersAuditWithoutGrantingIt() throws {
    let description = try SessionDescriptionBody(
        hostID: WireUUID(UUID()),
        deviceID: WireUUID(UUID()),
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 2),
        policyRevision: .init(rawValue: 3),
        hostState: .userSessionActive,
        features: [
            "audit.readSelf",
            "interactive.control.v0.1",
            "status.snapshot",
        ],
        serverTimeUnixMilliseconds: 1
    )
    #expect(description.features.first == "audit.readSelf")
}
