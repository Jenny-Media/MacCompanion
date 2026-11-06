#if os(iOS)
import XCTest
@testable import Mac_Companion

private final class ComposerBatchSession: CompanionVNCSession {
    var owner: String?
    var groups: [[[AnyHashable: Any]]] = []
    var pending: ((Bool) -> Void)?
    var rejectBatch: Int?
    var cancelled = false
    override func beginControlSequence() -> String? {
        guard owner == nil else { return nil }
        let value = UUID().uuidString; owner = value; return value
    }
    override func ownsControlSequence(_ identifier: String) -> Bool { owner == identifier }
    override func tryControlSequenceEvents(_ events: [[AnyHashable: Any]], identifier: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard owner == identifier, pending == nil, rejectBatch != groups.count else { return false }
        groups.append(events); pending = completion; return true
    }
    override func endControlSequence(_ identifier: String) { if owner == identifier { owner = nil } }
    override func cancelControlSequence(_ identifier: String) {
        if owner == identifier { cancelled = true; owner = nil }
    }
    func complete(_ written: Bool) { let reply = pending; pending = nil; reply?(written) }
}

@MainActor final class ComposerDeliveryTests: XCTestCase {
    func testLongUnicodeTextWaitsForEachBalancedBatchAndCompletesOnce() throws {
        let session = ComposerBatchSession()
        let text = String(repeating: "中😀", count: 2000)
        var results: [Bool] = []
        XCTAssertTrue(DirectTextComposer.sendDesktopText(text, session: session, current: { true }) { results.append($0) })
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertNotNil(session.owner); XCTAssertTrue(results.isEmpty)
        while session.pending != nil {
            XCTAssertTrue(session.groups.allSatisfy { $0.count <= 256 && $0.count.isMultiple(of: 2) })
            session.complete(true)
        }
        let actual = session.groups.flatMap { $0 }.map { NSDictionary(dictionary: $0) }
        let expected = try DirectComposedText(text, mode: .desktop).desktopEvents.map { NSDictionary(dictionary: $0) }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(results, [true]); XCTAssertNil(session.owner); XCTAssertFalse(session.cancelled)
    }
    func testBusyFirstBatchSendsNothingAndKeepsCompletionForTheCaller() {
        let session = ComposerBatchSession(); session.rejectBatch = 0
        var results: [Bool] = []
        XCTAssertFalse(DirectTextComposer.sendDesktopText(String(repeating: "x", count: 600), session: session, current: { true }) { results.append($0) })
        XCTAssertTrue(session.groups.isEmpty); XCTAssertTrue(results.isEmpty); XCTAssertNil(session.owner)
    }
    func testBusyLaterBatchOrFailedWriteStopsTheRemainder() {
        for failedWrite in [false, true] {
            let session = ComposerBatchSession(); session.rejectBatch = failedWrite ? nil : 1
            var results: [Bool] = []
            XCTAssertTrue(DirectTextComposer.sendDesktopText(String(repeating: "x", count: 600), session: session, current: { true }) { results.append($0) })
            session.complete(!failedWrite)
            XCTAssertEqual(session.groups.count, 1); XCTAssertEqual(results, [false])
            XCTAssertTrue(session.cancelled); XCTAssertNil(session.owner); XCTAssertNil(session.pending)
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
                    let warning = "This draft exceeds the 16 KB limit. Use a smaller selection. Your previous text was kept."
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
}
#endif
