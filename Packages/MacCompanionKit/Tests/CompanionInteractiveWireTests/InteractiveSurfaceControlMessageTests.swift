import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func surfaceFixture(_ path: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent(path)
    )
}

@Test func authoritativeSurfaceSelectionAndAcknowledgementAreCanonical() throws {
    let selectedSource = try surfaceFixture(
        "valid/interactive-surface-selected.json"
    )
    let selected = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
        from: selectedSource
    )
    let selectedCanonical = selectedSource.last == 0x0a
        ? Data(selectedSource.dropLast()) : selectedSource
    #expect(try WireCodec.encode(selected) == selectedCanonical)
    #expect(selected.body.mediaSequenceBeforeTransition == 4)

    let descriptor = try selected.body.descriptor.materialize(
        clientMonotonicNowMilliseconds: 500
    )
    #expect(descriptor.createdAtMonotonicMilliseconds == 500)
    #expect(descriptor.expiresAtMonotonicMilliseconds == 10_500)
    #expect(descriptor.kind == .application)
    #expect(descriptor.surfaceRevision.rawValue == 2)

    let acknowledgementSource = try surfaceFixture(
        "valid/interactive-surface-ack.json"
    )
    let acknowledgement = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self,
        from: acknowledgementSource
    )
    let acknowledgementCanonical = acknowledgementSource.last == 0x0a
        ? Data(acknowledgementSource.dropLast()) : acknowledgementSource
    #expect(try WireCodec.encode(acknowledgement) == acknowledgementCanonical)
    #expect(acknowledgement.body.transitionID == selected.body.transitionID)
    #expect(acknowledgement.body.surfaceID == selected.body.descriptor.surfaceID)
    #expect(acknowledgement.body.readyMediaSequence == 7)
}

@Test func surfaceSelectionTargetAndSequencesAreClosed() throws {
    let sessionID = WireUUID(UUID())
    let surfaceID = WireUUID(UUID())

    _ = try InteractiveSurfaceSelectBodyV0(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        currentSurfaceID: surfaceID,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        targetKind: .desktop,
        targetToken: nil,
        sequence: 1
    )
    #expect(throws: InteractiveSurfaceWireErrorV0.invalidSelection) {
        try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            currentSurfaceID: surfaceID,
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .window,
            targetToken: nil,
            sequence: 1
        )
    }
    #expect(throws: InteractiveSurfaceWireErrorV0.invalidSelection) {
        try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            currentSurfaceID: surfaceID,
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .desktop,
            targetToken: nil,
            sequence: 0
        )
    }
}

@Test func wireDescriptorRejectsHostMonotonicAndNestedUnknownFields() throws {
    let source = try surfaceFixture("valid/interactive-surface-selected.json")
    var object = try #require(
        JSONSerialization.jsonObject(with: source) as? [String: Any]
    )
    var body = try #require(object["body"] as? [String: Any])
    var descriptor = try #require(body["descriptor"] as? [String: Any])
    descriptor["createdAtMonotonicMilliseconds"] = 1_000
    body["descriptor"] = descriptor
    object["body"] = body
    let injected = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
            from: injected
        )
    }

    descriptor.removeValue(forKey: "createdAtMonotonicMilliseconds")
    descriptor["validForMilliseconds"] = 10_001
    body["descriptor"] = descriptor
    object["body"] = body
    let oversized = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: InteractiveSurfaceWireErrorV0.invalidDescriptor) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
            from: oversized
        )
    }
}

@Test func focusedAcknowledgementAndResponseRequireTheExactFullFence() throws {
    let focusToken = WireUUID(UUID())
    let request = try InteractiveSurfaceAcknowledgementBodyV0(
        interactiveSessionID: WireUUID(UUID()),
        authorizationEpoch: .init(rawValue: 2),
        transitionID: WireUUID(UUID()),
        surfaceID: WireUUID(UUID()),
        surfaceRevision: .init(rawValue: 3),
        coordinateSpaceRevision: .init(rawValue: 4),
        focusToken: focusToken,
        focusRevision: .init(rawValue: 5),
        readyMediaSequence: 9,
        sequence: 2
    )
    let response = try InteractiveSurfaceAcknowledgedBodyV0(
        acknowledgement: request,
        inputResumed: true,
        sequence: 3
    )
    try response.validate(against: request)
    #expect(request.fence().focusToken == focusToken.rawValue)

    #expect(throws: InteractiveSurfaceWireErrorV0.invalidAcknowledgement) {
        try InteractiveSurfaceAcknowledgementBodyV0(
            interactiveSessionID: request.interactiveSessionID,
            authorizationEpoch: request.authorizationEpoch,
            transitionID: request.transitionID,
            surfaceID: request.surfaceID,
            surfaceRevision: request.surfaceRevision,
            coordinateSpaceRevision: request.coordinateSpaceRevision,
            focusToken: focusToken,
            focusRevision: nil,
            readyMediaSequence: 9,
            sequence: 2
        )
    }
    #expect(throws: InteractiveSurfaceWireErrorV0.bindingMismatch) {
        let changed = try InteractiveSurfaceAcknowledgementBodyV0(
            interactiveSessionID: request.interactiveSessionID,
            authorizationEpoch: request.authorizationEpoch,
            transitionID: request.transitionID,
            surfaceID: request.surfaceID,
            surfaceRevision: request.surfaceRevision,
            coordinateSpaceRevision: request.coordinateSpaceRevision,
            focusToken: focusToken,
            focusRevision: .init(rawValue: 5),
            readyMediaSequence: 10,
            sequence: 2
        )
        try response.validate(against: changed)
    }
}

@Test func authoritativeInitialSurfaceDescriptorAndAckAreCanonical() throws {
    let descriptorSource = try surfaceFixture(
        "valid/interactive-initial-surface-descriptor.json"
    )
    let response = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceDescriptorBodyV0>.self,
        from: descriptorSource
    )
    #expect(try WireCodec.encode(response) == Data(descriptorSource.dropLast()))
    #expect(response.body.mediaSequenceBeforeActivation == 0)
    let descriptor = try response.body.descriptor.materialize(
        clientMonotonicNowMilliseconds: 200
    )
    #expect(descriptor.kind == .desktop)
    #expect(descriptor.surfaceRevision.rawValue == 1)
    #expect(descriptor.coordinateSpaceRevision.rawValue == 1)

    let ackSource = try surfaceFixture(
        "valid/interactive-initial-surface-ack.json"
    )
    let ack = try WireCodec.decode(
        WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self,
        from: ackSource
    )
    #expect(try WireCodec.encode(ack) == Data(ackSource.dropLast()))
    #expect(ack.body.activationID == response.body.activationID)
    #expect(ack.body.readyMediaSequence == 2)

    let acknowledged = try InteractiveInitialSurfaceAcknowledgedBodyV0(
        acknowledgement: ack.body,
        inputResumed: true,
        sequence: 2
    )
    try acknowledged.validate(against: ack.body)
}

@Test func initialSurfaceMessagesRejectReplacementOrUnreadyShapes() throws {
    let source = try surfaceFixture(
        "valid/interactive-initial-surface-descriptor.json"
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: source) as? [String: Any]
    )
    var body = try #require(object["body"] as? [String: Any])
    var descriptor = try #require(body["descriptor"] as? [String: Any])
    descriptor["surfaceRevision"] = 2
    body["descriptor"] = descriptor
    object["body"] = body
    let changed = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: InteractiveInitialSurfaceMessageErrorV0.invalidInitialDescriptor) {
        try WireCodec.decode(
            WireEnvelope<InteractiveInitialSurfaceDescriptorBodyV0>.self,
            from: changed
        )
    }

    #expect(throws: InteractiveInitialSurfaceMessageErrorV0.bindingMismatch) {
        try InteractiveInitialSurfaceAcknowledgementBodyV0(
            interactiveSessionID: WireUUID(UUID()),
            authorizationEpoch: .init(rawValue: 1),
            activationID: WireUUID(UUID()),
            surfaceID: WireUUID(UUID()),
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            readyMediaSequence: 0,
            sequence: 2
        )
    }
}
