import CompanionInteractiveClient
import Dispatch
import Testing

@Test func latestResultMailboxKeepsOneNewestPendingValue() {
    let mailbox = ClientLatestResultMailboxV0<Int>()
    #expect(mailbox.offer(
        1,
        order: .init(generation: 1, sequence: 1)
    ) == .accepted(
        scheduleDrain: true,
        replacedPending: false
    ))
    #expect(mailbox.offer(
        2,
        order: .init(generation: 1, sequence: 2)
    ) == .accepted(
        scheduleDrain: false,
        replacedPending: true
    ))
    #expect(mailbox.offer(
        0,
        order: .init(generation: 1, sequence: 1)
    ) == .discardedNotNewer)
    #expect(mailbox.takePendingForScheduledDrain() == 2)
    #expect(mailbox.completeDrain() == false)
}

@Test func arrivalDuringDrainOwnsExactlyOneSuccessorTurn() {
    let mailbox = ClientLatestResultMailboxV0<Int>()
    _ = mailbox.offer(1)
    #expect(mailbox.takePendingForScheduledDrain() == 1)
    #expect(mailbox.offer(2) == .accepted(
        scheduleDrain: false,
        replacedPending: false
    ))
    #expect(mailbox.completeDrain() == true)
    #expect(mailbox.takePendingForScheduledDrain() == 2)
    #expect(mailbox.completeDrain() == false)
}

@Test func terminalResultCannotBeReplacedByLaterCallback() {
    let mailbox = ClientLatestResultMailboxV0<Int>()
    _ = mailbox.offer(
        1,
        order: .init(generation: 2, sequence: 1)
    )
    #expect(mailbox.offer(
        8,
        order: .init(generation: 1, sequence: 9),
        terminal: true
    ) == .discardedNotNewer)
    #expect(mailbox.offer(
        9,
        order: .init(generation: 2, sequence: 1),
        terminal: true
    ) == .acceptedTerminal(
        scheduleDrain: false,
        replacedPending: true
    ))
    #expect(mailbox.offer(10) == .rejectedTerminalPending)
    #expect(mailbox.takePendingForScheduledDrain() == 9)
    #expect(mailbox.completeDrain() == false)
    #expect(mailbox.offer(10) == .accepted(
        scheduleDrain: true,
        replacedPending: false
    ))
}

@Test func closeDiscardsPendingAndRejectsFutureCallbacks() {
    let mailbox = ClientLatestResultMailboxV0<Int>()
    _ = mailbox.offer(7)
    #expect(mailbox.close() == 7)
    #expect(mailbox.takePendingForScheduledDrain() == nil)
    #expect(mailbox.offer(8) == .rejectedClosed)
}

@Test func concurrentOutOfOrderOffersConvergeOnHighestSequence() {
    let mailbox = ClientLatestResultMailboxV0<Int>()
    DispatchQueue.concurrentPerform(iterations: 1_000) { value in
        _ = mailbox.offer(
            value,
            order: .init(
                generation: 3,
                sequence: UInt64(value + 1)
            )
        )
    }
    #expect(mailbox.takePendingForScheduledDrain() == 999)
    #expect(mailbox.completeDrain() == false)
}
