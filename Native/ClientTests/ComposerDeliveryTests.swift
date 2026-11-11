#if os(iOS)
import XCTest
@testable import Mac_Companion

private final class ComposerBatchSession: CompanionVNCSession {
    var owner: String?
    var groups: [[[AnyHashable: Any]]] = []
    var pending: ((Bool) -> Void)?
    var rejectBatch: Int?
    var cancelled = false
    var admitted: (() -> Void)?
    override func beginControlSequence() -> String? {
        guard owner == nil else { return nil }
        let value = UUID().uuidString; owner = value; return value
    }
    override func ownsControlSequence(_ identifier: String) -> Bool { owner == identifier }
    override func tryControlSequenceEvents(_ events: [[AnyHashable: Any]], identifier: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard owner == identifier, pending == nil, rejectBatch != groups.count else { return false }
        groups.append(events); pending = completion; admitted?(); return true
    }
    override func endControlSequence(_ identifier: String) { if owner == identifier { owner = nil } }
    override func cancelControlSequence(_ identifier: String) {
        if owner == identifier { cancelled = true; owner = nil }
    }
    func complete(_ written: Bool) { let reply = pending; pending = nil; reply?(written) }
}

@MainActor private final class ComposerDeliveryClock {
    var pending: (@MainActor () -> Void)?
    var delays: [TimeInterval] = []
    func schedule(_ delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        XCTAssertNil(pending)
        delays.append(delay)
        pending = action
    }
    func advance() { let action = pending; pending = nil; action?() }
}

@MainActor final class ComposerDeliveryTests: XCTestCase {
    func testLongUnicodeTextWaitsForEachBalancedBatchAndCompletesOnce() throws {
        let session = ComposerBatchSession()
        let clock = ComposerDeliveryClock()
        let text = String(repeating: "中😀", count: 2000)
        var results: [Bool] = []
        let delivery = DirectDesktopTextDelivery(events: DirectTextComposer.desktopEvents(text), session: session,
            current: { true }, schedule: clock.schedule) { results.append($0) }
        XCTAssertTrue(delivery.start())
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertNotNil(session.owner); XCTAssertTrue(results.isEmpty)
        while session.pending != nil {
            XCTAssertEqual(session.groups.last?.count, 2)
            let count = session.groups.count
            session.complete(true)
            XCTAssertEqual(session.groups.count, count)
            XCTAssertNil(session.pending)
            clock.advance()
        }
        let actual = session.groups.flatMap { $0 }.map { NSDictionary(dictionary: $0) }
        let expected = try DirectComposedText(text, mode: .desktop).desktopEvents.map { NSDictionary(dictionary: $0) }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(clock.delays, Array(repeating: 0.01, count: 3999))
        XCTAssertNil(clock.pending)
        XCTAssertEqual(results, [true]); XCTAssertNil(session.owner); XCTAssertFalse(session.cancelled)
    }
    func testLongEnglishTextKeepsEveryAdjacentLetterInOrderAcrossDelays() throws {
        let session = ComposerBatchSession(), clock = ComposerDeliveryClock()
        let text = String(repeating: "abcdefghijklmnopqrstuvwxyz 0123456789. ", count: 60)
        var results: [Bool] = []
        let delivery = DirectDesktopTextDelivery(events: DirectTextComposer.desktopEvents(text), session: session,
            current: { true }, schedule: clock.schedule) { results.append($0) }
        XCTAssertTrue(delivery.start())
        while session.pending != nil {
            XCTAssertEqual(session.groups.last?.count, 2)
            session.complete(true)
            XCTAssertNil(session.pending)
            clock.advance()
        }
        let actual = session.groups.flatMap { $0 }.map { NSDictionary(dictionary: $0) }
        let expected = try DirectComposedText(text, mode: .desktop).desktopEvents.map { NSDictionary(dictionary: $0) }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(results, [true])
    }
    func testSingleCharacterUsesOwnedDeliveryAndCompletesOnce() {
        let session = ComposerBatchSession()
        var results: [Bool] = []
        XCTAssertTrue(DirectTextComposer.sendDesktopText("a", session: session,
            current: { true }) { results.append($0) })
        XCTAssertNotNil(session.owner)
        let reply = session.pending
        session.complete(true)
        reply?(true)
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertEqual(results, [true])
        XCTAssertNil(session.owner)
    }
    func testProductionShortAndLongSendsWaitAfterThePreviousCharacterWrite() async {
        for count in [2, 255, 256, 257] {
            let session = ComposerBatchSession()
            var results: [Bool] = []
            XCTAssertTrue(DirectTextComposer.sendDesktopText(String(repeating: "a", count: count), session: session,
                current: { true }) { results.append($0) })
            XCTAssertEqual(session.groups.first?.count, 2)
            let next = expectation(description: "Next character after pacing delay for \(count) scalars")
            let writtenAt = ProcessInfo.processInfo.systemUptime
            session.admitted = {
                XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - writtenAt, 0.01)
                next.fulfill()
            }
            session.complete(true)
            XCTAssertEqual(session.groups.count, 1)
            await fulfillment(of: [next], timeout: 1)
            XCTAssertEqual(session.groups.count, 2)
            session.complete(false)
            XCTAssertEqual(results, [false])
            XCTAssertNil(session.owner)
        }
    }
    func testBusyFirstBatchSendsNothingAndKeepsCompletionForTheCaller() {
        for count in [1, 2, 256, 600] {
            let session = ComposerBatchSession(); session.rejectBatch = 0
            var results: [Bool] = []
            XCTAssertFalse(DirectTextComposer.sendDesktopText(String(repeating: "x", count: count), session: session, current: { true }) { results.append($0) })
            XCTAssertTrue(session.groups.isEmpty); XCTAssertTrue(results.isEmpty); XCTAssertNil(session.owner)
        }
    }
    func testBusyLaterBatchOrFailedWriteStopsTheRemainder() {
        for failedWrite in [false, true] {
            let session = ComposerBatchSession(); session.rejectBatch = failedWrite ? nil : 1
            let clock = ComposerDeliveryClock()
            var results: [Bool] = []
            let delivery = DirectDesktopTextDelivery(events: DirectTextComposer.desktopEvents(String(repeating: "x", count: 600)),
                session: session, current: { true }, schedule: clock.schedule) { results.append($0) }
            XCTAssertTrue(delivery.start())
            session.complete(!failedWrite)
            clock.advance()
            XCTAssertEqual(session.groups.count, 1); XCTAssertEqual(results, [false])
            XCTAssertTrue(session.cancelled); XCTAssertNil(session.owner); XCTAssertNil(session.pending)
            XCTAssertNil(clock.pending)
        }
    }
    func testChangedSessionBetweenBatchesNeverContinuesOrReplays() {
        let session = ComposerBatchSession()
        var current = true, results: [Bool] = []
        XCTAssertTrue(DirectTextComposer.sendDesktopText(String(repeating: "x", count: 600), session: session, current: { current }) { results.append($0) })
        let staleReply = session.pending
        current = false; session.complete(true)
        XCTAssertEqual(session.groups.count, 1); XCTAssertEqual(results, [false]); XCTAssertNil(session.owner)
        current = true; staleReply?(true)
        XCTAssertEqual(session.groups.count, 1); XCTAssertEqual(results, [false]); XCTAssertNil(session.owner)
    }
    func testLostReservationDuringDelayDoesNotContinueOrCancelAnotherOwner() {
        let session = ComposerBatchSession(), clock = ComposerDeliveryClock()
        var results: [Bool] = []
        let delivery = DirectDesktopTextDelivery(events: DirectTextComposer.desktopEvents(String(repeating: "x", count: 600)),
            session: session, current: { true }, schedule: clock.schedule) { results.append($0) }
        XCTAssertTrue(delivery.start())
        let staleReply = session.pending
        session.complete(true)
        XCTAssertNotNil(clock.pending)
        let replacement = UUID().uuidString
        session.owner = replacement
        clock.advance()
        staleReply?(true)
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertEqual(results, [false])
        XCTAssertEqual(session.owner, replacement)
        XCTAssertFalse(session.cancelled)
        XCTAssertNil(clock.pending)
    }
    func testCountsStayHiddenUntilNearTheActualPerModeLimit() {
        for mode in DirectControlMode.allCases {
            let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: mode)
            draft.configure(available: { true }, send: { _, _ in })
            draft.edit(String(repeating: "x", count: 600))
            XCTAssertTrue(draft.canSend); XCTAssertNil(draft.sizeSummary)
            let limit = mode == .terminal ? DirectComposedText.terminalMaximumBytes : DirectComposedText.desktopMaximumScalars
            draft.edit(String(repeating: "x", count: limit * 4 / 5))
            XCTAssertNil(draft.sizeSummary)
            draft.edit(String(repeating: "x", count: limit * 4 / 5 + 1))
            XCTAssertNotNil(draft.sizeSummary); XCTAssertTrue(draft.canSend)
            if mode != .terminal {
                draft.edit(String(repeating: "x", count: limit + 1))
                XCTAssertFalse(draft.canSend)
                XCTAssertTrue(draft.issueMessage?.contains("4,097") == true)
                XCTAssertTrue(draft.issueMessage?.contains("4,096") == true)
            }
        }
    }
    func testRejectedPasteDetailsKeepTheWarningAndRetainedDraftCount() {
        for mode in DirectControlMode.allCases {
            for counterInDetails in [false, true] {
                for retained in ["short draft", String(repeating: "😀", count: 3277)] {
                    let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: mode)
                    draft.configure(available: { true }, send: { _, _ in XCTFail("Editing must not send text") })
                    draft.edit(retained); draft.counterInDetails = counterInDetails
                    let nearLimit = draft.sizeSummary != nil
                    XCTAssertEqual(draft.detailsMessage, counterInDetails ? draft.sizeSummary : nil)
                    draft.edit(String(repeating: "x", count: DirectComposedText.draftMaximumBytes + 1))
                    XCTAssertEqual(draft.text, retained); XCTAssertTrue(draft.canSend)
                    let warning = "Drafts can contain up to 16 KB. Your previous text was kept."
                    XCTAssertEqual(draft.issueMessage, warning)
                    let count = mode == .terminal ? retained.utf8.count : retained.unicodeScalars.count
                    let limit = mode == .terminal ? DirectComposedText.terminalMaximumBytes : DirectComposedText.desktopMaximumScalars
                    let units = mode == .terminal ? "UTF-8 bytes" : "characters"
                    XCTAssertTrue(draft.detailsMessage?.contains(warning) == true)
                    XCTAssertTrue(draft.detailsMessage?.contains("Current draft: \(count.formatted()) / \(limit.formatted()) \(units)") == true)
                    XCTAssertEqual(draft.sizeSummary != nil, nearLimit)
                    draft.edit(retained)
                    XCTAssertNil(draft.issueMessage); XCTAssertTrue(draft.canSend)
                    XCTAssertEqual(draft.detailsMessage, counterInDetails ? draft.sizeSummary : nil)
                }
            }
        }
    }
    func testRejectedPasteTakesPriorityOverCompactDeliveryWarning() throws {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .desktop)
        let delivery = "Text may have been partially sent. Check your Mac before sending it again."
        draft.configure(available: { true }, send: { _, complete in complete(delivery) })
        draft.edit("retained draft")
        draft.requestSend()
        draft.deliveryIssueInDetails = true
        draft.edit(String(repeating: "x", count: DirectComposedText.draftMaximumBytes + 1))

        let details = try XCTUnwrap(draft.detailsMessage)
        XCTAssertTrue(details.hasPrefix("Drafts can contain up to 16 KB. Your previous text was kept."))
        XCTAssertTrue(details.contains(delivery))
        XCTAssertEqual(draft.text, "retained draft")
        XCTAssertTrue(draft.canSend)
    }
    func testDraftLimitAppliesToExistingTextPlusPaste() {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .terminal)
        draft.configure(available: { true }, send: { _, _ in XCTFail("Editing must not send text") })
        let retained = String(repeating: "a", count: 12 * 1024)
        draft.edit(retained)
        draft.edit(retained + String(repeating: "b", count: 8 * 1024))
        XCTAssertEqual(draft.text, retained)
        XCTAssertEqual(draft.issueMessage, "Drafts can contain up to 16 KB. Your previous text was kept.")
    }
}
#endif
