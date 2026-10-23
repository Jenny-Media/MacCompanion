#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class ShortcutSequenceTests: XCTestCase {
    private func shortcut(_ steps: [TerminalShortcutStep]) -> TerminalControlAction {
        var action = TerminalControlAction(title: "Synthetic Shortcut", kind: .shortcut, inMenu: false)
        action.steps = steps; return action
    }
    func testRetirementAfterFirstWriteStopsRemainderAndNeverRestarts() async throws {
        var current = true, sent: [[UInt8]] = []
        do {
            try await TerminalSequencePump.write([[2], [99], [13]], current: { current }) { packet in sent.append(packet); current = false }
            XCTFail("Retirement must cancel the remaining packets")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(sent, [[2]])
        current = true
        await Task.yield()
        XCTAssertEqual(sent, [[2]], "Returning to foreground cannot revive the retired execution")
    }
    func testCapabilityLossAfterFirstWriteStopsTheRemainingChord() async throws {
        let action = shortcut([.init(character: 0x61), .init(character: 0x63, modifiers: [0xffeb])])
        var encoding = TerminalKeyEncoding(flags: .disambiguate)
        let packets = try action.terminalSequence(encoding: encoding, bracketedPaste: false)
        var sent: [[UInt8]] = []
        do {
            try await TerminalSequencePump.write(packets, current: { (try? action.terminalSequence(encoding: encoding, bracketedPaste: false)) == packets }) { bytes in
                sent.append(bytes); encoding.flags = []
            }
            XCTFail("Loss of negotiated Command support must stop the sequence")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(sent, [packets[0]])
    }
    func testUnavailableOwnerSendsNoPrefixAndWriteFailureStopsRemainder() async {
        var sent: [[UInt8]] = []
        do { try await TerminalSequencePump.write([[2], [99]], current: { false }) { sent.append($0) }; XCTFail() } catch {}
        XCTAssertTrue(sent.isEmpty)
        do { try await TerminalSequencePump.write([[2], [99]], current: { true }) { sent.append($0); throw TerminalSequenceFailure.unsupported }; XCTFail() } catch {}
        XCTAssertEqual(sent, [[2]])
    }
    func testLiteralPaletteKeyNeverReusesASequenceWithTheSameFinalKey() throws {
        let split = try XCTUnwrap(TerminalShortcutPack.tmux.shortcuts.first { $0.id == "tmux.split-right.complete" })
        var profile = TerminalControlsProfile(actions: [split.action])
        let literal = TerminalPaletteKey("%", character: 0x25)
        let id = profile.pin(literal, in: .menu)
        XCTAssertNotEqual(id, split.action.id)
        let action = try XCTUnwrap(profile.actions.first { $0.id == id })
        XCTAssertEqual(try action.terminalSequence(encoding: .init(), bracketedPaste: false), [[0x25]])
        XCTAssertEqual(try split.action.terminalSequence(encoding: .init(), bracketedPaste: false), [[2], [0x25]])
    }
    func testExactOrderRepeatedKeysCaseAndExplicitReturn() throws {
        let action = shortcut([.init(character: 0x62, modifiers: [0xffe3]), .init(character: 0x63),
            .init(character: 0x63), .init(character: 0x42), .init(character: 0xff0d)])
        XCTAssertEqual(try action.terminalSequence(encoding: .init(), bracketedPaste: false), [[2], [99], [99], [66], [13]])
        XCTAssertEqual(action.sequencePreview, "⌃b → c → c → B → ↵")
        let decoded = try JSONDecoder().decode(TerminalControlAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
    }
    func testTextIsReviewedAndFramedWithoutAnImplicitReturn() throws {
        let action = shortcut([.init(character: 0x61), .init(kind: .text, text: "  中文\n😀 "), .init(character: 0xff1b)])
        XCTAssertTrue(action.hasSequenceText)
        let packets = try action.terminalSequence(encoding: .init(), bracketedPaste: true)
        XCTAssertEqual(packets[1], Array("\u{1b}[200~  中文\n😀 \u{1b}[201~".utf8))
        XCTAssertEqual(packets[2], [27])
        XCTAssertEqual(packets.count, 3)
    }
    func testUnsupportedLaterCommandRejectsEntireTerminalSequence() {
        let action = shortcut([.init(character: 0x61), .init(character: 0x63, modifiers: [0xffeb])])
        XCTAssertThrowsError(try action.terminalSequence(encoding: .init(), bracketedPaste: false))
        XCTAssertNoThrow(try action.remoteSequence())
    }
    func testRemoteGroupsReleaseEveryModifierAndNeverIncludeLiveState() throws {
        let action = shortcut([.init(character: 0x42, modifiers: [0xffe3, 0xffe1]), .init(character: 0x63), .init(kind: .text, text: "😀")])
        let events = try action.remoteSequence()
        var held = Set<UInt32>()
        for event in events {
            let code = try XCTUnwrap((event["key"] as? NSNumber)?.uint32Value)
            if event["down"] as? Bool == true { XCTAssertTrue(held.insert(code).inserted) }
            else { XCTAssertNotNil(held.remove(code)) }
        }
        XCTAssertTrue(held.isEmpty)
        XCTAssertEqual(events.filter { ($0["key"] as? NSNumber)?.uint32Value == 99 }.count, 2)
    }
    func testTextStepsReusePlainTextNormalizationAndRemoteTabMapping() throws {
        let action = shortcut([.init(kind: .text, text: "a\r\n\t中\u{2028}b")])
        XCTAssertEqual(try action.terminalSequence(encoding: .init(), bracketedPaste: false), [Array("a\n\t中\nb".utf8)])
        let down = try action.remoteSequence().filter { $0["down"] as? Bool == true }.compactMap { ($0["key"] as? NSNumber)?.uint32Value }
        XCTAssertEqual(down, [0x61, 0xff0d, 0xff09, 0x01004e2d, 0xff0d, 0x62])
        XCTAssertFalse(shortcut([.init(kind: .text, text: "x\u{03}")]).valid)
        XCTAssertFalse(shortcut([.init(kind: .text, text: "x\u{7f}")]).valid)
        let oversized = shortcut([.init(character: 0x61), .init(kind: .text, text: String(repeating: "x", count: 257)), .init(character: 0xff0d)])
        XCTAssertThrowsError(try oversized.remoteSequence(), "An unsupported text step must reject the entire sequence, never disappear between its other keys")
    }
    func testWholeRemoteBudgetRejectsAnOversizedLaterTextStep() {
        let action = shortcut([.init(character: 0x62, modifiers: [0xffe3]), .init(kind: .text, text: String(repeating: "x", count: 256))])
        XCTAssertTrue(action.valid)
        XCTAssertThrowsError(try action.remoteSequence())
    }
    func testInvalidAndOversizedStepListsCannotSave() {
        XCTAssertFalse(shortcut([]).valid)
        XCTAssertFalse(shortcut((0..<33).map { _ in .init(character: 0x61) }).valid)
        XCTAssertFalse(shortcut([.init(kind: .text, text: "unsafe\u{1b}")]).valid)
        XCTAssertFalse(shortcut([.init(character: 0x61, modifiers: [0xffe3, 0xffe3])]).valid)
        let repeated = TerminalShortcutStep(character: 0x61)
        XCTAssertFalse(shortcut([repeated, repeated]).valid, "Step identities must be unique even when the keys repeat")
    }
    func testLegacySingleChordAndDuplicatePlacementsSurviveVersionUpgrade() throws {
        var action = TerminalControlAction(title: "Uppercase", kind: .shortcut, inRow: true)
        action.character = 0x42
        var old = TerminalControlsProfile(actions: [action]); old.freezeKeyboardLayout()
        old.place(action.id, in: TerminalKeyboardRow.mainID); old.version = 1
        var data = try JSONEncoder().encode(old)
        let originalPlacements = old.resolvedRows.flatMap { old.barPlacements(in: $0) }
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] })
        let loaded = try store.load()
        XCTAssertEqual(loaded.actions, old.actions)
        XCTAssertEqual(loaded.resolvedRows.flatMap { loaded.barPlacements(in: $0) }, originalPlacements)
        XCTAssertEqual(try loaded.actions[0].terminalSequence(encoding: .init(), bracketedPaste: false), [[66]])
        let saved = try store.save(loaded)
        XCTAssertEqual(saved.version, TerminalControlsProfile.currentVersion)
    }
    func testRemoteProfileIsIndependentAndRestoresCommandControls() throws {
        var data: Data?
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] }, legacyActions: { [] }, family: .remoteMac)
        var remote = try store.load()
        XCTAssertEqual(remote.family, .remoteMac)
        XCTAssertTrue(remote.resolvedRows.flatMap { remote.barItems(in: $0) }.contains(.control(.command)))
        remote.placeBarItem(.key("key-f12"), in: TerminalKeyboardRow.mainID)
        let saved = try store.save(remote)
        XCTAssertEqual(try store.load(), saved)
        XCTAssertFalse(TerminalControlsProfile.defaults.resolvedRows.flatMap { TerminalControlsProfile.defaults.barItems(in: $0) }.contains(.key("key-f12")))
        XCTAssertTrue(remote.availableActions.contains(.commandAlone))
        XCTAssertFalse(TerminalControlsProfile.defaults.availableActions.contains(.commandAlone))
    }
    func testCompletePresetsRetainIndividualPrefixAndIndependentSteps() throws {
        for pack in TerminalShortcutPack.allCases {
            XCTAssertTrue(pack.shortcuts.contains { $0.action.steps == nil })
            let complete = pack.shortcuts.filter { $0.action.steps != nil }
            XCTAssertFalse(complete.isEmpty)
            for preset in complete { XCTAssertTrue(preset.action.valid); XCTAssertNoThrow(try preset.action.terminalSequence(encoding: .init(), bracketedPaste: false)) }
        }
        let tmux = try XCTUnwrap(TerminalShortcutPack.tmux.shortcuts.first { $0.id == "tmux.window.complete" })
        XCTAssertEqual(try tmux.action.terminalSequence(encoding: .init(), bracketedPaste: false), [[2], [99]])
        let zellij = try XCTUnwrap(TerminalShortcutPack.zellijUnlock.shortcuts.first { $0.id == "zellijUnlock.new-pane.complete" })
        XCTAssertEqual(try zellij.action.terminalSequence(encoding: .init(), bracketedPaste: false), [[7], [112], [110]])
    }
}
#endif
