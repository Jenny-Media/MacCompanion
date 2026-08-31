@testable import CompanionClient
import Foundation
import Testing

@Test func shortBackgroundGraceConsumesOnlyItsCurrentDeadline() {
    let first = UUID()
    let second = UUID()
    var grace = ClientApplicationBackgroundGraceV1()

    let beganFirst = grace.begin(token: first)
    let rejectedSecond = grace.begin(token: second)
    let consumedFirst = grace.consume(token: first)
    #expect(beganFirst)
    #expect(!rejectedSecond)
    #expect(consumedFirst)
    #expect(grace.pendingToken == nil)

    let beganSecond = grace.begin(token: second)
    let rejectedStale = grace.consume(token: first)
    let consumedSecond = grace.consume(token: second)
    #expect(beganSecond)
    #expect(!rejectedStale)
    #expect(consumedSecond)
}

@Test func foregroundReturnFencesTheOldBackgroundDeadline() {
    let token = UUID()
    var grace = ClientApplicationBackgroundGraceV1()

    let began = grace.begin(token: token)
    let cancelled = grace.cancel()
    let consumedStale = grace.consume(token: token)
    let cancelledAgain = grace.cancel()
    #expect(began)
    #expect(cancelled)
    #expect(!consumedStale)
    #expect(!cancelledAgain)
}
