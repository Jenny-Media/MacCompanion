import CompanionHostSession
import CompanionWire
import Foundation
import Testing

private func routeObservationBodyV1(
    connection: ClosedRange<UInt8> = 0x00...0x0f,
    route: ClosedRange<UInt8> = 0x50...0x5f,
    routeClass: ConfiguredRouteClassV1 = .privateDNS,
    sequence: Int64
) throws -> RouteObservationBodyV1 {
    try RouteObservationBodyV1(
        connectionID: WireBytes16(Data(connection)),
        configuredRouteID: WireBytes16(Data(route)),
        routeClass: routeClass,
        observationSequence: sequence
    )
}

@Test func routeObservationBindsConnectionRouteAndStrictSequence() async throws {
    let authority = try AuthenticatedRouteObservationSessionV1(
        connectionID: Data(0x00...0x0f)
    )
    var value = try await authority.admit(
        routeObservationBodyV1(sequence: 1),
        hostMonotonicMilliseconds: 100
    )
    #expect(value.routeClass == .privateDNS)
    #expect(value.lastObservationSequence == 1)
    #expect(value.freshThroughMonotonicMilliseconds == 30_100)

    value = try await authority.admit(
        routeObservationBodyV1(sequence: 2),
        hostMonotonicMilliseconds: 15_000
    )
    #expect(value.freshThroughMonotonicMilliseconds == 45_000)
    await #expect(
        throws: AuthenticatedRouteObservationSessionErrorV1.sequenceReplay
    ) {
        try await authority.admit(
            routeObservationBodyV1(sequence: 2),
            hostMonotonicMilliseconds: 15_001
        )
    }
    await #expect(
        throws: AuthenticatedRouteObservationSessionErrorV1.sequenceGap
    ) {
        try await authority.admit(
            routeObservationBodyV1(sequence: 4),
            hostMonotonicMilliseconds: 15_001
        )
    }
}

@Test func routeObservationRejectsConnectionAndProvenanceReplacement() async throws {
    let authority = try AuthenticatedRouteObservationSessionV1(
        connectionID: Data(0x00...0x0f)
    )
    _ = try await authority.admit(
        routeObservationBodyV1(sequence: 1),
        hostMonotonicMilliseconds: 100
    )
    await #expect(
        throws: AuthenticatedRouteObservationSessionErrorV1.connectionMismatch
    ) {
        try await authority.admit(
            routeObservationBodyV1(
                connection: 0x10...0x1f,
                sequence: 2
            ),
            hostMonotonicMilliseconds: 101
        )
    }
    await #expect(
        throws: AuthenticatedRouteObservationSessionErrorV1.routeChanged
    ) {
        try await authority.admit(
            routeObservationBodyV1(
                route: 0x60...0x6f,
                routeClass: .privateNetwork,
                sequence: 2
            ),
            hostMonotonicMilliseconds: 101
        )
    }
}

@Test func routeObservationExpiresAfterInclusiveDeadlineAndCanRecover() async throws {
    let authority = try AuthenticatedRouteObservationSessionV1(
        connectionID: Data(0x00...0x0f)
    )
    _ = try await authority.admit(
        routeObservationBodyV1(sequence: 1),
        hostMonotonicMilliseconds: 100
    )
    #expect(
        try await authority.snapshot(
            hostMonotonicMilliseconds: 30_100
        ).routeClass == .privateDNS
    )
    #expect(
        try await authority.snapshot(
            hostMonotonicMilliseconds: 30_101
        ).routeClass == nil
    )
    let recovered = try await authority.admit(
        routeObservationBodyV1(sequence: 2),
        hostMonotonicMilliseconds: 30_102
    )
    #expect(recovered.routeClass == .privateDNS)
    #expect(recovered.freshThroughMonotonicMilliseconds == 60_102)
}

@Test func routeObservationCloseWithdrawsAndRejectsDelayedTraffic() async throws {
    let authority = try AuthenticatedRouteObservationSessionV1(
        connectionID: Data(0x00...0x0f)
    )
    _ = try await authority.admit(
        routeObservationBodyV1(sequence: 1),
        hostMonotonicMilliseconds: 100
    )
    let closed = await authority.close()
    #expect(closed.closed)
    #expect(closed.routeClass == nil)
    await #expect(throws: AuthenticatedRouteObservationSessionErrorV1.closed) {
        try await authority.admit(
            routeObservationBodyV1(sequence: 2),
            hostMonotonicMilliseconds: 101
        )
    }
}

@Test func routeObservationBuildsExactCorrelatedAcknowledgement() async throws {
    let authority = try AuthenticatedRouteObservationSessionV1(
        connectionID: Data(0x00...0x0f)
    )
    let body = try routeObservationBodyV1(sequence: 1)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID(
            uuidString: "018f0000-0000-7000-8000-000000001100"
        )!),
        correlationID: nil,
        sentAtUnixMilliseconds: 100,
        body: body
    )
    _ = try await authority.admit(
        body,
        hostMonotonicMilliseconds: 100
    )
    let responseID = WireUUID(UUID(
        uuidString: "018f0000-0000-7000-8000-000000001103"
    )!)
    let acknowledgement = try await authority.acknowledgement(
        for: request,
        responseMessageID: responseID,
        sentAtUnixMilliseconds: 103
    )

    #expect(acknowledgement.correlationID == request.messageID)
    #expect(acknowledgement.body.connectionID == body.connectionID)
    #expect(acknowledgement.body.configuredRouteID == body.configuredRouteID)
    #expect(acknowledgement.body.routeClass == body.routeClass)
    #expect(acknowledgement.body.observationSequence == 1)
    #expect(acknowledgement.body.validForMilliseconds == 30_000)
}
