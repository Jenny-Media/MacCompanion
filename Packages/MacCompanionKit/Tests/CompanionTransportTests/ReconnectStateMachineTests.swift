import CompanionDiscovery
import CompanionTransport
import Foundation
import Testing

private let routeA = try! EndpointCandidate(
    kind: .bonjour,
    value: "mac-018f._maccompanion._tcp.local.",
    port: 47_474
)
private let routeB = try! EndpointCandidate(
    kind: .ipv4,
    value: "192.168.1.20",
    port: 47_474
)
private let routeC = try! EndpointCandidate(
    kind: .dns,
    value: "mac.tail123.ts.net",
    port: 47_474
)
private let pinnedFingerprint = Data(0x80...0x9f)

private func reconnect(
    foreground: Bool = true,
    networkReachable: Bool = true
) throws -> ReconnectStateMachine {
    try ReconnectStateMachine(
        candidates: [routeA, routeB, routeC],
        requiredHostFingerprint: pinnedFingerprint,
        foreground: foreground,
        networkReachable: networkReachable
    )
}

@Test func foregroundRoundStaggersAllBoundedRoutesAndCarriesRequiredPin() throws {
    var state = try reconnect()
    let roundID = UUID()
    let effects = try state.apply(.tick(monotonicNowMilliseconds: 100, roundID: roundID))
    guard case let .startDialRound(round) = effects.first else {
        Issue.record("missing dial round")
        return
    }
    #expect(round.roundID == roundID)
    #expect(round.requiredHostFingerprint == pinnedFingerprint)
    #expect(round.attempts.map(\.endpoint) == [routeA, routeB, routeC])
    #expect(round.attempts.map(\.startAfterMilliseconds) == [0, 250, 500])
    #expect(round.attempts.allSatisfy {
        $0.connectTimeoutMilliseconds == 10_000
            && $0.authenticationTimeoutMilliseconds == 10_000
    })
}

@Test func firstAuthenticatedPinnedRouteWinsAndCancelsOtherDials() throws {
    var state = try reconnect()
    let roundID = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 100, roundID: roundID))
    #expect(try state.apply(.authenticated(roundID, routeB)) == [.cancelPendingDials])
    #expect(state.phase == .connected(routeB))
    #expect(state.failedRounds == 0)
}

@Test func exhaustedRoundsUseBoundedExponentialBackoffWithInjectedJitter() throws {
    var state = try reconnect()
    var now: Int64 = 1_000
    for (index, expectedBase) in ReconnectStateMachine.backoffMilliseconds.enumerated() {
        let roundID = UUID()
        _ = try state.apply(.tick(monotonicNowMilliseconds: now, roundID: roundID))
        let effects = try state.apply(.roundExhausted(
            roundID,
            monotonicNowMilliseconds: now,
            jitterBasisPoints: 10_000
        ))
        #expect(effects == [.scheduleRetry(atMonotonicMilliseconds: now + expectedBase)])
        #expect(state.failedRounds == index + 1)
        now += expectedBase
    }

    let cappedRound = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: now, roundID: cappedRound))
    #expect(try state.apply(.roundExhausted(
        cappedRound,
        monotonicNowMilliseconds: now,
        jitterBasisPoints: 12_000
    )) == [.scheduleRetry(atMonotonicMilliseconds: now + 36_000)])
}

@Test func backgroundAndNetworkLossCancelWorkWithoutInventingReachability() throws {
    var state = try reconnect()
    let firstRound = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 100, roundID: firstRound))
    #expect(try state.apply(.setForeground(false, monotonicNowMilliseconds: 101)) == [
        .cancelPendingDials,
    ])
    #expect(state.phase == .waitingForForeground)
    #expect(try state.apply(.tick(monotonicNowMilliseconds: 102, roundID: UUID())).isEmpty)

    _ = try state.apply(.setForeground(true, monotonicNowMilliseconds: 103))
    let secondRound = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 104, roundID: secondRound))
    _ = try state.apply(.authenticated(secondRound, routeA))
    #expect(try state.apply(.setNetworkReachable(false, monotonicNowMilliseconds: 105)) == [
        .closeConnection,
    ])
    #expect(state.phase == .waitingForNetwork)
}

@Test func manualDisconnectAndAuthorizationDenialNeverAutoRetry() throws {
    var state = try reconnect()
    let firstRound = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 100, roundID: firstRound))
    #expect(try state.apply(.manualDisconnect) == [.cancelPendingDials])
    #expect(state.phase == .manuallyDisconnected)
    _ = try state.apply(.setForeground(false, monotonicNowMilliseconds: 101))
    _ = try state.apply(.setForeground(true, monotonicNowMilliseconds: 102))
    #expect(state.phase == .manuallyDisconnected)
    _ = try state.apply(.resumeManualConnection)

    let secondRound = UUID()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 103, roundID: secondRound))
    #expect(try state.apply(.authenticationDenied(secondRound)) == [.cancelPendingDials])
    #expect(state.phase == .requiresUserAction)
    #expect(try state.apply(.tick(monotonicNowMilliseconds: 104, roundID: UUID())).isEmpty)
    _ = try state.apply(.resumeAfterUserAction)
    #expect(state.phase == .ready)
}

@Test func candidateReplacementCancelsOldRoundAndPreservesManualIntent() throws {
    var state = try reconnect()
    _ = try state.apply(.tick(monotonicNowMilliseconds: 100, roundID: UUID()))
    #expect(try state.apply(.replaceCandidates(
        [routeC, routeA],
        monotonicNowMilliseconds: 101
    )) == [.cancelPendingDials])
    #expect(state.candidates == [routeC, routeA])
    #expect(state.phase == .ready)

    _ = try state.apply(.manualDisconnect)
    #expect(try state.apply(.replaceCandidates(
        [routeB],
        monotonicNowMilliseconds: 102
    )).isEmpty)
    #expect(state.phase == .manuallyDisconnected)
}
