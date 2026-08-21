import CompanionDiscovery
import CompanionObservation
import CompanionPresentation
import CompanionTransport
import Foundation
import Testing

private let retainedObservation = try! ObservationFreshness(
    observedAtUnixMilliseconds: 10_000,
    responseSentAtUnixMilliseconds: 10_100,
    requestStartedAtMonotonicMilliseconds: 1_000,
    receivedAtMonotonicMilliseconds: 1_200,
    validForMilliseconds: 1_000
)

@Test func connectedPresentationCanStillContainStaleObservation() throws {
    let live = try HostAvailabilityPresentation.make(
        reconnectPhase: .connected(try route()),
        retainedObservation: retainedObservation,
        monotonicNowMilliseconds: 1_899
    )
    #expect(live.connection == .connected)
    #expect(live.observation?.state == .live)

    let stale = try HostAvailabilityPresentation.make(
        reconnectPhase: .connected(try route()),
        retainedObservation: retainedObservation,
        monotonicNowMilliseconds: 1_900
    )
    #expect(stale.connection == .connected)
    #expect(stale.observation?.state == .stale)
}

@Test func reconnectCauseAndRetainedUnreachableObservationRemainSeparate() throws {
    let value = try HostAvailabilityPresentation.make(
        reconnectPhase: .backoff(untilMonotonicMilliseconds: 5_000),
        retainedObservation: retainedObservation,
        monotonicNowMilliseconds: 1_300
    )
    #expect(value.connection == .retryScheduled)
    #expect(value.retryAtMonotonicMilliseconds == 5_000)
    #expect(value.observation?.state == .unreachable)
    #expect(value.observation?.observedAtUnixMilliseconds == 10_000)
}

@Test func everyDisconnectedCauseMarksRetainedDataUnreachable() throws {
    let phases: [(ReconnectPhase, ConnectionPresentationState)] = [
        (.waitingForForeground, .background),
        (.waitingForNetwork, .noNetwork),
        (.ready, .connecting),
        (.dialing(UUID()), .connecting),
        (.requiresUserAction, .actionRequired),
        (.manuallyDisconnected, .disconnectedByUser),
    ]
    for (phase, expected) in phases {
        let value = try HostAvailabilityPresentation.make(
            reconnectPhase: phase,
            retainedObservation: retainedObservation,
            monotonicNowMilliseconds: 1_300
        )
        #expect(value.connection == expected)
        #expect(value.observation?.state == .unreachable)
    }
}

@Test func connectedWithoutObservationDoesNotInventEmptyOrLiveData() throws {
    let value = try HostAvailabilityPresentation.make(
        reconnectPhase: .connected(try route()),
        retainedObservation: nil,
        monotonicNowMilliseconds: 1_300
    )
    #expect(value.connection == .connected)
    #expect(value.observation == nil)
}

private func route() throws -> EndpointCandidate {
    try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.20",
        port: 47_474
    )
}
