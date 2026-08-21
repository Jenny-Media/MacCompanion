import CompanionDomain
import CompanionObservation
import Testing

@Test func responseAgeAndFullRoundTripConservativelyReduceFreshnessWindow() throws {
    let freshness = try ObservationFreshness(
        observedAtUnixMilliseconds: 10_000,
        responseSentAtUnixMilliseconds: 10_100,
        requestStartedAtMonotonicMilliseconds: 1_000,
        receivedAtMonotonicMilliseconds: 1_200,
        validForMilliseconds: 1_000
    )
    #expect(freshness.estimatedAgeAtReceiptMilliseconds == 300)
    #expect(freshness.expiresAtMonotonicMilliseconds == 1_900)

    let live = try freshness.assess(
        reachability: .reachable,
        monotonicNowMilliseconds: 1_899
    )
    #expect(live.state == .live)
    #expect(live.estimatedAgeMilliseconds == 999)

    let stale = try freshness.assess(
        reachability: .reachable,
        monotonicNowMilliseconds: 1_900
    )
    #expect(stale.state == .stale)
    #expect(stale.estimatedAgeMilliseconds == 1_000)
}

@Test func disconnectAlwaysLabelsRetainedObservationUnreachable() throws {
    let freshness = try ObservationFreshness(
        observedAtUnixMilliseconds: 10_000,
        responseSentAtUnixMilliseconds: 10_000,
        requestStartedAtMonotonicMilliseconds: 1_000,
        receivedAtMonotonicMilliseconds: 1_010,
        validForMilliseconds: 5_000
    )
    let assessment = try freshness.assess(
        reachability: .unreachable,
        monotonicNowMilliseconds: 1_011
    )
    #expect(assessment.state == .unreachable)
    #expect(assessment.observedAtUnixMilliseconds == 10_000)
}

@Test func alreadyOldResponseIsStaleAtReceiptEvenOnConnectedSocket() throws {
    let freshness = try ObservationFreshness(
        observedAtUnixMilliseconds: 10_000,
        responseSentAtUnixMilliseconds: 11_500,
        requestStartedAtMonotonicMilliseconds: 1_000,
        receivedAtMonotonicMilliseconds: 1_200,
        validForMilliseconds: 1_000
    )
    #expect(freshness.expiresAtMonotonicMilliseconds == 1_200)
    #expect(try freshness.assess(
        reachability: .reachable,
        monotonicNowMilliseconds: 1_200
    ).state == .stale)
}

@Test func impossibleClockRelationshipsFailClosed() {
    #expect(throws: ObservationFreshnessError.invalidTime) {
        _ = try ObservationFreshness(
            observedAtUnixMilliseconds: 10_001,
            responseSentAtUnixMilliseconds: 10_000,
            requestStartedAtMonotonicMilliseconds: 1_000,
            receivedAtMonotonicMilliseconds: 1_200,
            validForMilliseconds: 1_000
        )
    }
    #expect(throws: ObservationFreshnessError.invalidTime) {
        _ = try ObservationFreshness(
            observedAtUnixMilliseconds: 10_000,
            responseSentAtUnixMilliseconds: 10_000,
            requestStartedAtMonotonicMilliseconds: 1_201,
            receivedAtMonotonicMilliseconds: 1_200,
            validForMilliseconds: 1_000
        )
    }
}
