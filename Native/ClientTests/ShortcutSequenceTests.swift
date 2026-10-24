#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class ShortcutSequenceTests: XCTestCase {
    func testProgressShowsCompletedStepsAndNeverPredictsWaitOrBatchCompletion() throws {
        let action = shortcut([.init(kind: .typeText, text: "t"), .init(character: 0xff0d),
                               .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .typeText, text: "1"), .init(character: 0xff0d)])
        let progress = TerminalSequenceProgress(action: action)
        XCTAssertEqual(progress.completedStepFraction, 0)
        progress.move(to: 2)
        XCTAssertEqual(try XCTUnwrap(progress.completedStepFraction), 0.4, accuracy: 0.0001)
        XCTAssertEqual(progress.symbol, "hourglass")
        XCTAssertTrue(progress.status(at: Date.now.addingTimeInterval(5)).contains("0 s"))
        XCTAssertEqual(progress.completedStepFraction, 0.4, "An elapsed wait does not acknowledge the following input steps")
        progress.move(to: 4)
        XCTAssertEqual(progress.completedStepFraction, 0.8, "The current write is still in progress")
        let batch = TerminalSequenceProgress(action: action, batching: true)
        XCTAssertNil(batch.completedStepFraction, "A single admitted batch cannot claim intermediate receipts")
        XCTAssertEqual(batch.symbol, "paperplane")
    }
    func testConfirmationDefaultsOffAndConnectionExceptionsMatchOnlyUnchangedShortcut() throws {
        var action = shortcut([.init(kind: .typeText, text: "t"), .init(character: 0xff0d)])
        var policy = TerminalShortcutConfirmations()
        XCTAssertFalse(policy.requiresReview(action, connectionID: "one"))
        action.confirmBeforeRunning = true
        XCTAssertTrue(policy.requiresReview(action, connectionID: "one"))
        XCTAssertTrue(policy.requiresReview(action, connectionID: "one"), "Merely opening or canceling review grants no exception")
        policy.skip(action, connectionID: "one")
        XCTAssertFalse(policy.requiresReview(action, connectionID: "one"))
        var other = action; other.id = UUID()
        XCTAssertTrue(policy.requiresReview(other, connectionID: "one"))
        var renamed = action; renamed.title = "Renamed"
        policy.definitionsChanged([renamed])
        XCTAssertFalse(policy.requiresReview(renamed, connectionID: "one"), "Presentation changes do not create a connection")
        var edited = action; edited.steps![0].text = "changed"
        policy.definitionsChanged([edited])
        XCTAssertTrue(policy.requiresReview(edited, connectionID: "one"))
        policy.skip(edited, connectionID: "one")
        XCTAssertTrue(policy.requiresReview(edited, connectionID: "two"))
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlAction.self, from: JSONEncoder().encode(edited)).confirmBeforeRunning, true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
        legacy.removeValue(forKey: "confirmBeforeRunning")
        let decoded = try JSONDecoder().decode(TerminalControlAction.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(policy.requiresReview(decoded, connectionID: "two"))
    }
    func testTimedScheduleValidatesDefinitionsWithoutForecastingFutureModes() throws {
        let action = shortcut([.init(character: 0x63, modifiers: [0xffe3]), .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .typeText, text: String(repeating: "a", count: 4000))])
        XCTAssertTrue(action.valid)
        XCTAssertThrowsError(try action.terminalPlan(encoding: .init(flags: .reportAllKeys), bracketedPaste: false))
        let plan = try action.terminalSchedule()
        XCTAssertEqual(plan.count, 3); XCTAssertEqual(plan[0].input, 0); XCTAssertEqual(plan[2].input, 2)
        if case .wait(let value) = plan[1] { XCTAssertEqual(value, 1000) } else { XCTFail("Wait must remain explicit") }
        var invalid = action; invalid.steps![2].text += String(repeating: "a", count: 97)
        XCTAssertThrowsError(try invalid.terminalSchedule())
        invalid = action; invalid.steps![1].waitMilliseconds = 30_001
        XCTAssertThrowsError(try invalid.terminalSchedule())
    }
    func testCurrentStepEncodingDoesNotRevalidateTheCompletedPrefix() throws {
        let action = shortcut([.init(kind: .typeText, text: String(repeating: "a", count: 4000)),
                               .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .typeText, text: "b")])
        XCTAssertEqual(try action.terminalPlan(encoding: .init(), bracketedPaste: false).compactMap(\.input).flatMap { $0 }.count, 4001)
        let current = TerminalKeyEncoding(flags: .reportAllKeys)
        XCTAssertThrowsError(try action.terminalPlan(encoding: current, bracketedPaste: false))
        let suffix = try action.resolvedSteps[2].terminalBytes(encoding: current, bracketedPaste: false)
        XCTAssertEqual(suffix, Array("\u{1b}[98u".utf8))
        XCTAssertEqual(4000 + suffix.count, 4005)
        XCTAssertThrowsError(try TerminalShortcutStep(character: 0x61, modifiers: [0xffeb]).terminalBytes(encoding: .init(), bracketedPaste: false))
    }
    func testQuickReturnAppendsOrdinaryDistinctKeysWithoutChangingCompactKeycaps() throws {
        var action = TerminalControlAction(title: "Return twice", kind: .shortcut)
        XCTAssertTrue(action.appendShortcutStep(.init(character: 0xff0d)))
        XCTAssertEqual(action.resolvedSteps.count, 1, "A new draft must not retain an empty phantom key")
        XCTAssertEqual(action.keycapTitle, "↵")
        XCTAssertEqual(action.sequencePreview, "↵ Return")
        XCTAssertTrue(action.appendShortcutStep(.init(character: 0xff0d)))
        XCTAssertNotEqual(action.resolvedSteps[0].id, action.resolvedSteps[1].id)
        XCTAssertTrue(action.resolvedSteps.allSatisfy { $0.kind == .key && $0.modifiers.isEmpty })
        XCTAssertEqual(action.keycapTitle, "↵ → ↵")
        XCTAssertEqual(try action.terminalSequence(encoding: .init(), bracketedPaste: true), [[13], [13]])
        let decoded = try JSONDecoder().decode(TerminalControlAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
        XCTAssertEqual(decoded.sequencePreview, "↵ Return → ↵ Return")
        let down = try action.remoteSequence().filter { $0["down"] as? Bool == true }
        XCTAssertEqual(down.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [0xff0d, 0xff0d])
    }
    func testAppendingReturnPreservesLegacyChordAndEnforcesStepLimit() throws {
        var action = TerminalControlAction(title: "Legacy prefix", kind: .shortcut)
        action.character = 0x62; action.modifiers = [0xffe3]
        XCTAssertTrue(action.appendShortcutStep(.init(character: 0xff0d)))
        XCTAssertEqual(try action.terminalSequence(encoding: .init(), bracketedPaste: false), [[2], [13]])
        for _ in 0..<30 { XCTAssertTrue(action.appendShortcutStep(.init(character: 0xff0d))) }
        let full = action
        XCTAssertFalse(action.appendShortcutStep(.init(character: 0xff0d)))
        XCTAssertEqual(action, full)
        var empty = TerminalControlAction(title: "Draft", kind: .shortcut)
        XCTAssertFalse(empty.appendShortcutStep(.init()))
        let step = TerminalShortcutStep(character: 0xff0d)
        XCTAssertTrue(empty.appendShortcutStep(step)); XCTAssertFalse(empty.appendShortcutStep(step))
        XCTAssertEqual(empty.resolvedSteps.count, 1)
    }
    func testReturnAndEnterSearchFindTheSameKeyWhileDisplayContextsRemainDistinct() throws {
        let group = try XCTUnwrap(TerminalKeyCatalog.groups.first { $0.title == "Essentials" })
        let key = try XCTUnwrap(group.keys.first { $0.shortcutCode == 0xff0d })
        for query in ["Return", "Enter", "ENTER", "  enter\n"] {
            XCTAssertEqual(TerminalKeyCatalog.matching(query, in: group).map(\.id), [key.id])
        }
        XCTAssertEqual(key.title, "↵")
        XCTAssertEqual(key.pickerTitle, "↵ Return")
        XCTAssertEqual(key.name, "Return")
        XCTAssertEqual(TerminalShortcutStep(character: 0xff0d, modifiers: [0xffe3]).label, "⌃↵ Return")
        XCTAssertEqual(TerminalShortcutStep(character: 0xff0d, modifiers: [0xffe3]).compactLabel, "⌃↵")
    }
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
        XCTAssertEqual(action.sequencePreview, "⌃b → c → c → B → ↵ Return")
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

    func testTypeTextIsOrdinaryInputWhileExistingTextKeepsPasteFormatting() throws {
        let typed = shortcut([.init(kind: .typeText, text: "12中😀")])
        let pasted = shortcut([.init(kind: .text, text: "12中😀")])
        XCTAssertEqual(try typed.terminalSequence(encoding: .init(), bracketedPaste: true), [Array("12中😀".utf8)])
        XCTAssertEqual(try pasted.terminalSequence(encoding: .init(), bracketedPaste: true), [Array("\u{1b}[200~12中😀\u{1b}[201~".utf8)])
        let enhanced = shortcut([.init(kind: .typeText, text: "ab")])
        XCTAssertEqual(try enhanced.terminalSequence(encoding: .init(flags: .reportAllKeys), bracketedPaste: true), [Array("\u{1b}[97u\u{1b}[98u".utf8)])
        XCTAssertTrue(typed.hasSequenceText)
        for separator in ["\n", "\r", "\r\n", "\t", "\u{2028}", "\u{2029}"] {
            XCTAssertFalse(shortcut([.init(kind: .typeText, text: "a" + separator + "b")]).valid)
        }
    }

    func testLegacyPasteStepDecodesWithoutNewWaitFieldAndNewTypesRoundTrip() throws {
        let old = TerminalShortcutStep(kind: .text, text: "preserve paste")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        value.removeValue(forKey: "waitMilliseconds")
        let decoded = try JSONDecoder().decode(TerminalShortcutStep.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(decoded, old)
        let action = shortcut([.init(kind: .typeText, text: "t"), .init(character: 0xff0d),
                               .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .text, text: "payload")])
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlAction.self, from: JSONEncoder().encode(action)), action)
    }

    func testUserLaunchAndNumericSelectionPlanWaitsBeforeTyping() async throws {
        let action = shortcut([.init(kind: .typeText, text: "t"), .init(character: 0xff0d),
            .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .typeText, text: "1"), .init(character: 0xff0d)])
        let plan = try action.terminalPlan(encoding: .init(), bracketedPaste: true)
        var now: UInt64 = 0, sent: [([UInt8], UInt64)] = []
        try await TerminalSequencePump.run(plan, current: { true }, pause: { now += $0 }) { _, bytes in sent.append((bytes, now)) }
        XCTAssertEqual(sent.map(\.0), [[116], [13], [49], [13]])
        XCTAssertEqual(sent.map(\.1), [0, 0, 1_000_000_000, 1_000_000_000])
        XCTAssertThrowsError(try action.terminalSequence(encoding: .init(), bracketedPaste: true), "An old byte-only caller must not discard a wait")
    }

    func testUserChordsThenTypedCommandKeepOrderAndNoPasteMarkers() async throws {
        for text in ["d", "done"] {
            let action = shortcut([.init(character: 0x67, modifiers: [0xffe3]),
                                   .init(character: 0x6f, modifiers: [0xffe3]), .init(kind: .typeText, text: text)])
            var sent: [[UInt8]] = []
            try await TerminalSequencePump.run(try action.terminalPlan(encoding: .init(), bracketedPaste: true), current: { true }) { _, bytes in sent.append(bytes) }
            XCTAssertEqual(sent, [[7], [15], Array(text.utf8)])
        }
    }

    func testCancellationDuringWaitNeverSendsOrReplaysTheSuffix() async throws {
        var current = true, slept: UInt64 = 0, sent: [[UInt8]] = []
        let plan: [TerminalSequenceOperation<[UInt8]>] = [.input([116, 13]), .wait(1000), .input([49, 13])]
        do {
            try await TerminalSequencePump.run(plan, current: { current }, pause: { duration in
                slept += duration; current = false
            }) { _, bytes in sent.append(bytes) }
            XCTFail("Retiring the owner during the wait must stop the shortcut")
        } catch is CancellationError {}
        XCTAssertEqual(slept, 50_000_000)
        current = true; await Task.yield()
        XCTAssertEqual(sent, [[116, 13]])
    }

    func testExplicitTaskCancellationInterruptsSleepRatherThanWaitingForDuration() async throws {
        let entered = expectation(description: "wait entered")
        var sent: [[UInt8]] = []
        let task = Task { @MainActor in
            try await TerminalSequencePump.run([TerminalSequenceOperation.input([116]), .wait(30_000), .input([49])], current: { true }, pause: { duration in
                entered.fulfill(); try await Task.sleep(nanoseconds: duration)
            }) { _, bytes in sent.append(bytes) }
        }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        do { try await task.value; XCTFail("Cancel must interrupt the wait") } catch is CancellationError {}
        XCTAssertEqual(sent, [[116]])
    }

    func testWaitValidationBudgetsAndRemotePlansKeepTheirBoundaries() throws {
        for duration in [-1, 0, 99, 30_001, Int.max] {
            XCTAssertFalse(shortcut([.init(character: 0x74), .init(kind: .wait, waitMilliseconds: duration)]).valid)
        }
        XCTAssertFalse(shortcut([.init(kind: .wait, waitMilliseconds: 1000)]).valid)
        XCTAssertFalse(shortcut([.init(character: 0x74)] + (0..<3).map { _ in .init(kind: .wait, waitMilliseconds: 30_000) }).valid)
        let action = shortcut([.init(character: 0x67, modifiers: [0xffe3]), .init(kind: .wait, waitMilliseconds: 1000), .init(kind: .typeText, text: "12")])
        let plan = try action.remotePlan()
        XCTAssertEqual(plan.count, 3)
        guard case .wait(1000) = plan[1] else { return XCTFail("Remote waits must retain their position") }
        let first = try XCTUnwrap(plan[0].input)
        XCTAssertEqual(first.filter { $0["down"] as? Bool == true }.count, 2)
        XCTAssertEqual(first.filter { $0["down"] as? Bool == false }.count, 2)
        let last = try XCTUnwrap(plan[2].input)
        XCTAssertEqual(last.filter { $0["down"] as? Bool == true }.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [49, 50])
        XCTAssertThrowsError(try action.remoteSequence())
    }

    func testRemoteReservationBlocksOtherInputAndCannotRetireANewerOwner() throws {
        let session = CompanionVNCSession()
        session.setValue(true, forKey: "inputOnly")
        for key in ["running", "inputReady", "established", "baselinePresented"] { session.setValue(true, forKey: key) }
        defer { session.setValue(false, forKey: "running"); session.stop() }
        XCTAssertTrue(session.composedTextReady)
        let old = try XCTUnwrap(session.beginControlSequence())
        XCTAssertTrue(session.connected, "A local input reservation must not make the transport look disconnected")
        let events: [[AnyHashable: Any]] = [["key": 49, "down": true], ["key": 49, "down": false]]
        XCTAssertFalse(session.tryKeyEvents(events))
        XCTAssertFalse(session.tryComposedTextEvents(events) { _ in })
        XCTAssertNil(session.beginControlSequence())
        session.cancelControlSequence(old)
        let replacement = try XCTUnwrap(session.beginControlSequence())
        session.endControlSequence(old)
        XCTAssertFalse(session.tryControlSequenceEvents(events, identifier: old) { _ in })
        XCTAssertTrue(session.tryControlSequenceEvents(events, identifier: replacement) { _ in })
        session.cancelControlSequence(replacement)
        XCTAssertTrue(session.tryKeyEvents(events))
    }
    func testControlCleanupDoesNotReduceRemoteEventBudgetOrLeaveRetiredGroupsQueued() throws {
        let session = CompanionVNCSession(); session.setValue(true, forKey: "inputOnly")
        for key in ["running", "inputReady", "established", "baselinePresented"] { session.setValue(true, forKey: key) }
        defer { session.setValue(false, forKey: "running"); session.stop() }
        let owner = try XCTUnwrap(session.beginControlSequence())
        let events: [[AnyHashable: Any]] = (0..<256).flatMap { _ in [["key": 97, "down": true], ["key": 97, "down": false]] }
        XCTAssertTrue(session.tryControlSequenceEvents(events, identifier: owner) { _ in })
        session.cancelControlSequence(owner)
        XCTAssertFalse(session.value(forKey: "overflow") as? Bool ?? true)
        let pending = try XCTUnwrap(session.value(forKey: "events") as? [[String: Any]])
        XCTAssertFalse(pending.contains { $0["composedTextID"] != nil })
        XCTAssertTrue(session.tryKeyEvents([["key": 98, "down": true], ["key": 98, "down": false]]))
    }
}
#endif
