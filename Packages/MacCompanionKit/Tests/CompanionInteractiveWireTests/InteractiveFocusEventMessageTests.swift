import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func focusEventFixture(_ path: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent(path)
    )
}

@Test func authoritativeFocusEventIsCanonicalAndPrivacyClosed() throws {
    let source = try focusEventFixture(
        "valid/interactive-surface-focus-changed.json"
    )
    let event = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceFocusChangedBodyV0>.self,
        from: source
    )
    #expect(event.channel == .events)
    #expect(event.correlationID == nil)
    #expect(event.body.eventSequence == 1)
    #expect(event.body.recommendedTargetKind == .focusedRegion)
    #expect(event.body.focus?.category == .text)
    #expect(try event.body.clientExpiry(
        receivedAtMonotonicMilliseconds: 500
    ) == 1_500)
    #expect(try WireCodec.encode(event) == Data(source.dropLast()))

    let metadata = try WireCodec.routingMetadata(from: source)
    #expect(metadata.channel == .events)
    #expect(metadata.kind == .interactiveSurfaceFocusChanged)
    #expect(metadata.correlationID == nil)

    let leaking = try focusEventFixture(
        "invalid/interactive-focus-event-leaks-label.json"
    )
    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceFocusChangedBodyV0>.self,
            from: leaking
        )
    }
}

@Test func focusEventCandidateAndDesktopShapesAreClosed() throws {
    let sessionID = WireUUID(UUID())
    let surfaceID = WireUUID(UUID())
    let token = WireUUID(UUID())
    let focus = InteractiveSurfaceWireFocusV0(try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 2),
        category: .button,
        bounds: NormalizedSurfaceRect(
            x: 1,
            y: 2,
            width: 3,
            height: 4
        ),
        editable: false,
        secure: false
    ))
    _ = try InteractiveSurfaceFocusChangedBodyV0(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        currentSurfaceID: surfaceID,
        currentSurfaceRevision: .init(rawValue: 1),
        currentCoordinateSpaceRevision: .init(rawValue: 1),
        recommendedTargetKind: .focusedRegion,
        targetToken: token,
        focus: focus,
        inputPaused: false,
        reason: .verifiedFocus,
        validForMilliseconds: 1_000,
        eventSequence: 1
    )
    _ = try InteractiveSurfaceFocusChangedBodyV0(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        currentSurfaceID: surfaceID,
        currentSurfaceRevision: .init(rawValue: 1),
        currentCoordinateSpaceRevision: .init(rawValue: 1),
        recommendedTargetKind: .desktop,
        targetToken: nil,
        focus: nil,
        inputPaused: true,
        reason: .targetDisappeared,
        validForMilliseconds: 1_000,
        eventSequence: 2
    )

    #expect(throws: InteractiveFocusEventWireErrorV0.invalidEvent) {
        try InteractiveSurfaceFocusChangedBodyV0(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            currentSurfaceID: surfaceID,
            currentSurfaceRevision: .init(rawValue: 1),
            currentCoordinateSpaceRevision: .init(rawValue: 1),
            recommendedTargetKind: .focusedRegion,
            targetToken: nil,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000,
            eventSequence: 1
        )
    }
    #expect(throws: InteractiveFocusEventWireErrorV0.invalidEvent) {
        try InteractiveSurfaceFocusChangedBodyV0(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            currentSurfaceID: surfaceID,
            currentSurfaceRevision: .init(rawValue: 1),
            currentCoordinateSpaceRevision: .init(rawValue: 1),
            recommendedTargetKind: .application,
            targetToken: token,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000,
            eventSequence: 1
        )
    }
}

@Test func focusEventIsAcceptedOnlyOnTheUncorrelatedEventLane() throws {
    let body = try InteractiveSurfaceFocusChangedBodyV0(
        interactiveSessionID: WireUUID(UUID()),
        authorizationEpoch: .init(rawValue: 1),
        currentSurfaceID: WireUUID(UUID()),
        currentSurfaceRevision: .init(rawValue: 1),
        currentCoordinateSpaceRevision: .init(rawValue: 1),
        recommendedTargetKind: .desktop,
        targetToken: nil,
        focus: nil,
        inputPaused: false,
        reason: .noVerifiedFocus,
        validForMilliseconds: 500,
        eventSequence: 1
    )
    _ = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        channel: .events,
        sentAtUnixMilliseconds: 1,
        body: body
    )
    #expect(throws: (any Error).self) {
        try WireEnvelope(
            messageID: WireUUID(UUID()),
            correlationID: nil,
            channel: .command,
            sentAtUnixMilliseconds: 1,
            body: body
        )
    }
    #expect(throws: (any Error).self) {
        try WireEnvelope(
            messageID: WireUUID(UUID()),
            correlationID: WireUUID(UUID()),
            channel: .events,
            sentAtUnixMilliseconds: 1,
            body: body
        )
    }
    #expect(throws: InteractiveFocusEventWireErrorV0.invalidTime) {
        try body.clientExpiry(
            receivedAtMonotonicMilliseconds:
                WireLimits.maximumSafeInteger
        )
    }
}
