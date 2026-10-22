#if os(iOS)
import XCTest
import Security
@testable import Mac_Companion

@MainActor final class TerminalControlsProfileTests: XCTestCase {
    @MainActor private final class Memory {
        var data: Data?
        var keyboards: [UUID: TerminalKeyboardPreferences] = [:]
        var quick = DirectControlMode.terminal.defaults
        var writes = 0
        var failWrite = false
        var unreadableSource: UUID?
        var store: TerminalControlsStore {
            .init(read: { self.data }, write: {
                if self.failWrite { throw TerminalControlsStore.Failure.unreadable }
                self.data = $0; self.writes += 1
            }, legacyIDs: { self.keyboards.keys.sorted { $0.uuidString < $1.uuidString } }, legacyKeyboard: {
                if self.unreadableSource == $0 { throw TerminalControlsStore.Failure.unreadable }
                return self.keyboards[$0]!
            }, legacyActions: { self.quick })
        }
    }
    func testImportsAllMacsWithoutLosingSameNameLongUnicodeOrCollidingIDs() throws {
        let memory = Memory(), first = UUID(), second = UUID(), collision = UUID()
        let long = String(repeating: "😀", count: 1023) + "\n"
        let hidden = VNCQuickAction(id: collision, title: "Same", kind: .shortcut, enabled: false, key: 0x42)
        memory.quick.append(hidden)
        memory.keyboards[first] = .init(keys: [.home, .f1], snippets: [.init(id: collision, name: "Same", text: long)])
        memory.keyboards[second] = .init(keys: [.f1, .end], snippets: [.init(id: collision, name: "Same", text: "  different\n\t中文\n")])
        let profile = try memory.store.load()
        XCTAssertTrue(profile.valid)
        XCTAssertEqual(profile.importedMacs, [first, second])
        let snippets = profile.actions.filter { $0.kind == .text }
        XCTAssertEqual(snippets.count, 2)
        XCTAssertEqual(Set(snippets.map(\.text)), [long, "  different\n\t中文\n"])
        XCTAssertEqual(snippets.map(\.title), ["Same", "Same"])
        XCTAssertTrue(snippets.allSatisfy { !$0.inMenu && !$0.inRow }, "Imported snippets remain available under Saved Text without pinning every Mac’s collection")
        XCTAssertEqual(Set(profile.actions.map(\.id)).count, profile.actions.count)
        let imported = try XCTUnwrap(profile.actions.first { $0.id == hidden.id })
        XCTAssertFalse(imported.inMenu); XCTAssertEqual(imported.character, 0x42)
        XCTAssertEqual(Set(profile.actions.compactMap(\.key)), [.home, .end, .f1])
        XCTAssertEqual(memory.keyboards[first]?.snippets.first?.text, long, "Migration leaves legacy sources intact")
        XCTAssertEqual(try memory.store.load(), profile); XCTAssertEqual(memory.writes, 1)
    }
    func testRemovedImportedSnippetDoesNotResurrectAndLaterMacStillImports() throws {
        let memory = Memory(), first = UUID(), next = UUID()
        let snippet = TerminalSnippet(name: "Remove me", text: "synthetic")
        memory.keyboards[first] = .init(snippets: [snippet])
        var draft = try memory.store.load()
        draft.actions.removeAll { $0.id == snippet.id }
        _ = try memory.store.save(draft)
        XCTAssertFalse(try memory.store.load().actions.contains { $0.id == snippet.id })
        memory.keyboards[next] = .init(snippets: [.init(name: "New Mac", text: "next")])
        let refreshed = try memory.store.load()
        XCTAssertFalse(refreshed.actions.contains { $0.id == snippet.id })
        XCTAssertEqual(refreshed.actions.filter { $0.kind == .text }.map(\.text), ["next"])
        XCTAssertEqual(refreshed.importedMacs, [first, next])
    }
    func testFailedAtomicWriteRetriesWithoutPartialImportOrDuplicateActions() throws {
        let memory = Memory(), mac = UUID()
        memory.keyboards[mac] = .init(snippets: [.init(name: "Kept", text: "\t  kept\n")])
        memory.failWrite = true
        XCTAssertThrowsError(try memory.store.load()); XCTAssertNil(memory.data)
        XCTAssertEqual(memory.writes, 0)
        memory.failWrite = false
        let profile = try memory.store.load()
        XCTAssertEqual(profile.actions.filter { $0.kind == .text }.count, 1)
        XCTAssertEqual(profile.importedMacs, [mac])
        XCTAssertEqual(try memory.store.load(), profile); XCTAssertEqual(memory.writes, 1)
    }
    func testTemporaryIdentityDiscardJournalHasNoMigrationAuthority() throws {
        let memory = Memory(), temporary = UUID(), saved = UUID()
        memory.keyboards[temporary] = .init(snippets: [.init(name: "Temporary", text: "discard")])
        memory.keyboards[saved] = .init(snippets: [.init(name: "Saved", text: "keep")])
        var store = memory.store; store.excludedIDs = { [temporary] }
        let profile = try store.load()
        XCTAssertEqual(profile.actions.filter { $0.kind == .text }.map(\.text), ["keep"])
        XCTAssertEqual(profile.importedMacs, [saved])
        XCTAssertEqual(memory.keyboards[temporary]?.snippets.first?.text, "discard", "The existing cleanup owner retains authority over its source")
    }
    func testUnreadableDestinationAndSourceNeverGetReplacedWithDefaults() throws {
        let memory = Memory()
        memory.data = Data("corrupt synthetic record".utf8)
        let corrupt = memory.data
        XCTAssertThrowsError(try memory.store.load())
        XCTAssertEqual(memory.data, corrupt); XCTAssertEqual(memory.writes, 0)
        memory.data = nil
        _ = try memory.store.load()
        let saved = memory.data, writes = memory.writes, bad = UUID()
        memory.keyboards[bad] = .init(snippets: [.init(name: "Unreadable source", text: "preserved")])
        memory.unreadableSource = bad
        XCTAssertThrowsError(try memory.store.load())
        XCTAssertEqual(memory.data, saved); XCTAssertEqual(memory.writes, writes)
    }
    func testStaleEditorCannotOverwriteAnotherWindowOrANewImport() throws {
        let memory = Memory()
        var first = try memory.store.load(), second = first
        first.actions[0].title = "First window"
        let saved = try memory.store.save(first)
        second.actions[0].title = "Stale window"
        XCTAssertThrowsError(try memory.store.save(second))
        XCTAssertEqual(try memory.store.load(), saved)
        memory.keyboards[UUID()] = .init(snippets: [.init(name: "Later import", text: "new")])
        XCTAssertThrowsError(try memory.store.save(saved))
        XCTAssertEqual(try memory.store.load().actions.last?.text, "new")
    }
    func testEditingPlacementsAndOrderPreservesOnePayloadAndStableIdentity() throws {
        let memory = Memory()
        var profile = try memory.store.load()
        let item = TerminalControlAction(title: "Both", kind: .text, text: "  exact\n", inRow: true)
        profile.actions.append(item)
        profile.move(item.id, to: profile.actions[0].id)
        profile.actions[0].title = "Renamed"
        profile.actions[0].inMenu = false
        let saved = try memory.store.save(profile)
        XCTAssertEqual(saved.actions[0].id, item.id)
        XCTAssertEqual(saved.actions[0].text, item.text)
        XCTAssertTrue(saved.actions[0].inRow); XCTAssertFalse(saved.actions[0].inMenu)
        XCTAssertEqual(saved.actions.filter { $0.id == item.id }.count, 1)
    }
    func testSharedRecordIncludesAllMacImportsAndPreservesDisabledQuickActions() throws {
        let memory = Memory()
        let original = VNCQuickAction(title: "Hidden text", kind: .text, enabled: false, text: "hidden\n")
        memory.quick = [original]
        let first = try memory.store.load()
        XCTAssertEqual(first.actions.map(\.id), [original.id]); XCTAssertFalse(first.actions[0].inMenu)
        memory.keyboards[UUID()] = .init(snippets: [.init(name: "Another Mac", text: "other")])
        let second = try memory.store.load()
        XCTAssertEqual(second.actions.first?.id, first.actions.first?.id)
        XCTAssertEqual(second.actions.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: XCTUnwrap(memory.data)), second)
    }
    func testTerminalTextRetainsFourKiBByteLimitAndRejectsControlInjection() {
        var item = TerminalControlAction(title: "Text", kind: .text, text: String(repeating: "😀", count: 1024))
        XCTAssertTrue(item.valid)
        item.text += "a"; XCTAssertFalse(item.valid)
        for text in ["", "x\0y", "x\u{1b}[31my"] { item.text = text; XCTAssertFalse(item.valid) }
        item.text = "\t中文\n"; item.inMenu = false; item.inRow = false; XCTAssertTrue(item.valid, "Unpinned content stays in the library")
        item.kind = .key; XCTAssertFalse(item.valid)
        item.key = .f12; XCTAssertTrue(item.valid)
        item.kind = .shortcut; item.character = 0x42; XCTAssertTrue(item.valid)
        item.modifiers = [0xffeb]; XCTAssertTrue(item.valid, "Command chords are saved intact and admitted only with negotiated support")
        XCTAssertTrue(item.shortcut.terminalBytes().isEmpty)
        XCTAssertEqual(item.shortcut.terminalBytes(encoding: .init(flags: [.disambiguate])), Array("\u{1b}[98;10u".utf8))
    }
    func testInvalidLegacyPayloadStopsMigrationWithoutTruncation() throws {
        let memory = Memory(), mac = UUID()
        memory.keyboards[mac] = .init(snippets: [.init(name: "Long", text: String(repeating: "x", count: 4097))])
        XCTAssertThrowsError(try memory.store.load()); XCTAssertNil(memory.data); XCTAssertEqual(memory.writes, 0)
        memory.keyboards[mac]?.snippets[0].text = String(repeating: "x", count: 4096)
        XCTAssertEqual(try memory.store.load().actions.last?.text.utf8.count, 4096)
    }
    func testLegacyKeychainDiscoveryFindsEveryMacWithoutChangingItsSource() throws {
        let ids = [UUID(), UUID()]
        let service = "media.jenny.maccompanion.ssh-terminal-keyboard-v1.v1"
        defer { for id in ids { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString.lowercased()] as CFDictionary) } }
        for (index, id) in ids.enumerated() {
            try TerminalKeyboardPreferences(snippets: [.init(name: "Synthetic \(index)", text: "preserved \(index)\n")]).save(id)
        }
        let found = try TerminalSecretStore.accounts(kind: "terminal-keyboard-v1")
        XCTAssertTrue(Set(ids).isSubset(of: Set(found)))
        for (index, id) in ids.enumerated() { XCTAssertEqual(try TerminalKeyboardPreferences.load(id).snippets.first?.text, "preserved \(index)\n") }
    }
    func testIndependentPlacementOrderAndUnpinPreserveSharedContent() throws {
        let first = TerminalControlAction(title: "First", kind: .text, text: "中文😀\n", inRow: true)
        let second = TerminalControlAction(title: "Second", kind: .text, text: "path with spaces", inRow: true)
        var profile = TerminalControlsProfile(actions: [first, second])
        profile.move(second.id, to: first.id, in: .keyboard)
        XCTAssertEqual(profile.placed(.keyboard).map(\.id), [second.id, first.id])
        XCTAssertEqual(profile.placed(.menu).map(\.id), [first.id, second.id])
        profile.pin(first.id, in: .keyboard, enabled: false)
        XCTAssertEqual(profile.actions.first?.text, first.text)
        XCTAssertEqual(profile.placed(.menu).map(\.id), [first.id, second.id])
        profile.pin(first.id, in: .keyboard, enabled: true)
        XCTAssertEqual(profile.placed(.keyboard).map(\.id), [second.id, first.id])
        XCTAssertEqual(profile.actions.count, 2)
        profile.delete(first.id)
        XCTAssertEqual(profile.actions.count, 1); XCTAssertTrue(profile.valid)
        XCTAssertEqual(profile.rowOrder, [second.id]); XCTAssertEqual(profile.placed(.menu).map(\.id), [second.id])
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testV1RecordWithoutLayoutFieldsDecodesAndKeepsPayloads() throws {
        let original = TerminalControlsProfile(actions: [.init(title: "Old text", kind: .text, text: "  old\n", inRow: true)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["rowOrder", "menuOrder", "numberRow", "expandedBar", "navigationRow"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.valid); XCTAssertEqual(decoded.actions, original.actions)
        XCTAssertNil(decoded.navigationRow); XCTAssertNil(decoded.expandedBar)
    }
    func testLayoutAndIndependentOrdersShareOptimisticSaveAndRejectInvalidIDs() throws {
        let memory = Memory(); var profile = try memory.store.load()
        profile.numberRow = false; profile.expandedBar = false; profile.navigationRow = true
        let saved = try memory.store.save(profile)
        XCTAssertFalse(try XCTUnwrap(try memory.store.load().numberRow))
        XCTAssertFalse(try XCTUnwrap(try memory.store.load().expandedBar))
        XCTAssertThrowsError(try memory.store.save(profile))
        var bad = saved; bad.rowOrder = [UUID()]; XCTAssertFalse(bad.valid)
        bad = saved; bad.menuOrder = [saved.actions[0].id, saved.actions[0].id]; XCTAssertFalse(bad.valid)
    }

    func testRowsUpgradeFlatPlacementsAndKeepNumbersIndependent() throws {
        let snippet = TerminalControlAction(title: "Deploy", kind: .text, text: "  exact 中文😀\n", inRow: true)
        var profile = TerminalControlsProfile(actions: [snippet])
        XCTAssertEqual(profile.resolvedRows.map(\.kind), [.numbers, .navigation, .main])
        XCTAssertEqual(profile.resolvedRows.last?.actionIDs, [snippet.id])
        XCTAssertNil(profile.rowsExpanded); XCTAssertNil(profile.commandInBar)
        let custom = try XCTUnwrap(profile.addRow(title: "Shortcuts"))
        profile.place(snippet.id, in: custom)
        XCTAssertEqual(profile.resolvedRows.filter { $0.actionIDs.contains(snippet.id) }.map(\.id), [custom])
        profile.moveRow(TerminalKeyboardRow.numbersID, offset: 1)
        profile.numberRow = false
        let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile); XCTAssertTrue(decoded.valid)
        profile.removeRow(custom)
        XCTAssertEqual(profile.actions, [.init(id: snippet.id, title: snippet.title, kind: .text, text: snippet.text, inRow: false)])
        XCTAssertTrue(profile.valid); XCTAssertFalse(profile.resolvedRows.flatMap(\.actionIDs).contains(snippet.id))
    }
    func testCatalogPinReusesDefinitionAcrossSurfacesAndPreservesEdits() throws {
        let key = try XCTUnwrap(TerminalKeyCatalog.all.first { $0.accessory == .f8 })
        var profile = TerminalControlsProfile.defaults
        let id = profile.pin(key, in: .keyboard)
        let index = try XCTUnwrap(profile.actions.firstIndex { $0.id == id })
        profile.actions[index].title = "Debugger"
        XCTAssertEqual(profile.pin(key, in: .menu), id)
        XCTAssertEqual(profile.actions.filter { key.matches($0) }.count, 1)
        XCTAssertEqual(profile.actions[index].title, "Debugger")
        profile.pin(id, in: .keyboard, enabled: false)
        XCTAssertTrue(profile.actions[index].inMenu); XCTAssertEqual(profile.pin(key, in: .keyboard), id)
        XCTAssertTrue(profile.valid)
        XCTAssertEqual(Set(TerminalKeyCatalog.all.map(\.id)).count, TerminalKeyCatalog.all.count)
        XCTAssertTrue(TerminalKeyCatalog.all.allSatisfy { $0.definition.valid })
    }
    func testRowValidationRejectsDuplicatePlacementAndPreservesSavedCommand() throws {
        var item = TerminalControlAction(title: "Command B", kind: .shortcut, inRow: true)
        item.character = 0x42; item.modifiers = [0xffeb]
        var profile = TerminalControlsProfile(actions: [item]); profile.keyboardRows = profile.resolvedRows
        XCTAssertTrue(profile.valid)
        profile.commandInBar = false
        XCTAssertEqual(profile.actions[0], item)
        let extra = try XCTUnwrap(profile.addRow())
        while profile.resolvedRows.count < TerminalControlsProfile.maximumKeyboardRows { XCTAssertNotNil(profile.addRow()) }
        XCTAssertNil(profile.addRow(), "Six total rows, including Numbers")
        profile.place(item.id, in: extra)
        profile.keyboardRows![0].actionIDs = [item.id]
        XCTAssertFalse(profile.valid)
    }

    func testEditableBuiltinsSurviveRoundTripWithoutCreatingSavedDefinitions() throws {
        var profile = TerminalControlsProfile.defaults
        let original = profile.actions, main = TerminalKeyboardRow.mainID
        profile.placeBarItem(.control(.keyboard), in: main, before: .control(.shift))
        profile.removeBarItem(.key("key-escape"), in: main)
        let row = try XCTUnwrap(profile.resolvedRows.first { $0.id == main })
        XCTAssertFalse(profile.barItems(in: row).contains(.key("key-escape")))
        XCTAssertTrue(profile.valid); XCTAssertEqual(profile.actions, original)
        profile.removeRow(TerminalKeyboardRow.numbersID)
        let numbers = try XCTUnwrap(profile.addPreset(.numbers))
        XCTAssertEqual(profile.resolvedRows.first { $0.id == numbers }?.kind, .numbers)
        XCTAssertTrue(profile.valid)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testMovingOneBuiltinPlacementPreservesItsCopyInAnotherRow() throws {
        var profile = TerminalControlsProfile.defaults
        let main = TerminalKeyboardRow.mainID, nav = TerminalKeyboardRow.navigationID
        profile.placeBarItem(.key("key-up"), in: main) // An intentional legacy duplicate.
        let custom = try XCTUnwrap(profile.addPreset(.blank))
        profile.placeBarItem(.key("key-up"), in: custom, from: main)
        XCTAssertTrue(profile.valid)
        XCTAssertFalse(profile.barItems(in: profile.resolvedRows.first { $0.id == main }!).contains(.key("key-up")))
        XCTAssertTrue(profile.barItems(in: profile.resolvedRows.first { $0.id == nav }!).contains(.key("key-up")))
        profile.removeBarItem(.key("key-up"), in: custom)
        XCTAssertTrue(profile.barItems(in: profile.resolvedRows.first { $0.id == nav }!).contains(.key("key-up")))
    }
    func testRestoreLayoutKeepsLibraryMenuAndImportJournalAndSavedBytes() throws {
        let saved = TerminalControlAction(title: "Keep", kind: .text, text: "  中文😀\n", inRow: true)
        var profile = TerminalControlsProfile(actions: [saved]); profile.importedMacs = [UUID()]
        let journal = profile.importedMacs, menu = profile.placed(.menu)
        let custom = try XCTUnwrap(profile.addPreset(.functions)); profile.place(saved.id, in: custom)
        XCTAssertTrue(profile.valid)
        profile.restoreRow(custom)
        XCTAssertTrue(profile.valid); XCTAssertEqual(profile.actions.first?.text, saved.text)
        XCTAssertFalse(profile.actions[0].inRow); XCTAssertEqual(profile.placed(.menu).map(\.id), menu.map(\.id))
        profile.restoreKeyboardBar()
        XCTAssertTrue(profile.valid); XCTAssertEqual(profile.importedMacs, journal)
        XCTAssertEqual(profile.actions[0].id, saved.id); XCTAssertEqual(profile.actions[0].text, saved.text)
        XCTAssertTrue(profile.actions[0].inMenu); XCTAssertFalse(profile.actions[0].inRow)
        XCTAssertNil(profile.keyboardRows); XCTAssertEqual(profile.numberRow, true)
    }
    func testEachPresetIsEditableAndDoesNotPolluteSavedCollection() throws {
        for preset in TerminalRowPreset.allCases {
            var profile = TerminalControlsProfile.defaults
            profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", items: [])]
            let actions = profile.actions
            let id = try XCTUnwrap(profile.addPreset(preset))
            XCTAssertTrue(profile.valid, preset.rawValue); XCTAssertEqual(profile.actions, actions)
            let row = try XCTUnwrap(profile.resolvedRows.first { $0.id == id })
            XCTAssertEqual(profile.barItems(in: row), preset.items)
            if let first = preset.items.first { profile.removeBarItem(first, in: id) }
            profile.restoreRow(id)
            XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first { $0.id == id }!), preset.items)
            XCTAssertTrue(profile.valid)
        }
    }
    func testEditableRowsRejectUnknownKeysDuplicateControlsAndMissingSavedItems() throws {
        var profile = TerminalControlsProfile.defaults
        profile.placeBarItem(.key("not-in-catalog"), in: TerminalKeyboardRow.mainID)
        XCTAssertFalse(profile.valid)
        profile.restoreKeyboardBar(); profile.placeBarItem(.control(.ctrl), in: TerminalKeyboardRow.mainID)
        profile.keyboardRows![0].items!.append(.control(.ctrl)); XCTAssertFalse(profile.valid)
        profile.restoreKeyboardBar(); profile.placeBarItem(.saved(UUID()), in: TerminalKeyboardRow.mainID)
        XCTAssertFalse(profile.valid)
    }

    func testDefaultRowsHaveOneHomeForEachBuiltinAndExplicitLegacyCopiesSurvive() throws {
        var profile = TerminalControlsProfile.defaults
        let items = profile.resolvedRows.flatMap { profile.barItems(in: $0) }
        XCTAssertEqual(items.count, Set(items).count)
        XCTAssertFalse(profile.barItems(in: profile.resolvedRows.first { $0.kind == .main }!).contains(.key("key-up")))
        profile.placeBarItem(.key("key-up"), in: TerminalKeyboardRow.mainID)
        let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile); XCTAssertTrue(decoded.valid)
        XCTAssertEqual(decoded.resolvedRows.flatMap { decoded.barItems(in: $0) }.filter { $0 == .key("key-up") }.count, 2)
    }

    func testAddingPresetShowsExactMissingKeysAndDoesNotStealOrDuplicatePlacements() throws {
        var profile = TerminalControlsProfile.defaults
        let before = profile.resolvedRows
        XCTAssertTrue(profile.availableItems(for: .navigation).isEmpty)
        XCTAssertNil(profile.addPreset(.navigation))
        profile.placeBarItem(.key("key-f1"), in: TerminalKeyboardRow.mainID)
        let additions = profile.availableItems(for: .functions)
        XCTAssertFalse(additions.contains(.key("key-f1")))
        let id = try XCTUnwrap(profile.addPreset(.functions, before: TerminalKeyboardRow.numbersID))
        XCTAssertEqual(profile.resolvedRows.first?.id, id)
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first!), additions)
        XCTAssertTrue(profile.barItems(in: profile.resolvedRows.first { $0.kind == .main }!).contains(.key("key-f1")))
        for row in before where row.kind != .main {
            let current = try XCTUnwrap(profile.resolvedRows.first { $0.id == row.id })
            XCTAssertEqual(profile.barItems(in: current), TerminalControlsProfile.defaults.barItems(in: row))
            XCTAssertEqual(current.actionIDs, row.actionIDs); XCTAssertEqual(current.title, row.title)
        }
        profile.restoreRow(id)
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first!), additions)
        XCTAssertTrue(profile.valid)
    }

    func testSixRowsReorderAtBothEndsAndRoundTripWithoutChangingSavedPayloads() throws {
        let text = TerminalControlAction(title: "Preserve", kind: .text, text: "  中文😀\n", inRow: true)
        var profile = TerminalControlsProfile(actions: [text], importedMacs: [UUID()])
        let originalActions = profile.actions, journal = profile.importedMacs
        for _ in 0..<3 { XCTAssertNotNil(profile.addPreset(.blank)) }
        XCTAssertEqual(profile.resolvedRows.count, 6); XCTAssertTrue(profile.valid)
        XCTAssertNil(profile.addPreset(.blank))
        let last = profile.resolvedRows.last!.id, first = profile.resolvedRows.first!.id
        profile.moveRow(last, before: first); XCTAssertEqual(profile.resolvedRows.first?.id, last)
        profile.moveRow(last, before: nil); XCTAssertEqual(profile.resolvedRows.last?.id, last)
        let snapshot = profile
        profile.moveRow(first, before: UUID()); XCTAssertEqual(profile, snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile)), profile)
        XCTAssertEqual(profile.actions, originalActions); XCTAssertEqual(profile.importedMacs, journal)
        profile.keyboardRows!.append(.init(kind: .custom, title: "Seventh")); XCTAssertFalse(profile.valid)
    }
    func testPresetRecognizesAnAlreadyPlacedLegacySavedKeyWithoutChangingItsDefinition() throws {
        let saved = TerminalControlAction(title: "My F1", kind: .key, key: .f1, inRow: true)
        var profile = TerminalControlsProfile(actions: [saved])
        XCTAssertFalse(profile.availableItems(for: .functions).contains(.key("key-f1")))
        let row = try XCTUnwrap(profile.addPreset(.functions))
        XCTAssertFalse(profile.barItems(in: profile.resolvedRows.first { $0.id == row }!).contains(.key("key-f1")))
        XCTAssertEqual(profile.actions, [saved]); XCTAssertTrue(profile.valid)
    }

}
#endif
