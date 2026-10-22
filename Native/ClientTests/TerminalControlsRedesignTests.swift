#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class TerminalControlsRedesignTests: XCTestCase {
    func testFocusedTemplateMovesTheWholeRowWithoutDuplicatingKeysOrSavedDefinitions() throws {
        var profile = TerminalControlsProfile.defaults
        let source = try XCTUnwrap(profile.addRow(title: "Arrows"))
        profile.placeBarItem(.key("key-up"), in: source)
        let id = try XCTUnwrap(profile.installEditorPreset(.navigation, before: profile.resolvedRows.first?.id))
        let installed = try XCTUnwrap(profile.resolvedRows.first { $0.id == id })
        XCTAssertEqual(profile.barItems(in: installed), TerminalRowPreset.navigation.items)
        for item in TerminalRowPreset.navigation.items {
            XCTAssertEqual(profile.resolvedRows.flatMap { profile.barItems(in: $0) }.filter { $0 == item }.count, 1)
        }
        XCTAssertFalse(profile.resolvedRows.contains { $0.id == source })
        XCTAssertTrue(profile.valid)
    }
    func testNumbersTemplateReusesExistingRowAndKeepsItOnTop() throws {
        var profile = TerminalControlsProfile.defaults
        let first = try XCTUnwrap(profile.resolvedRows.first?.id)
        XCTAssertEqual(profile.installEditorPreset(.numbers, before: first), first)
        XCTAssertEqual(profile.resolvedRows.first?.id, first)
        XCTAssertEqual(profile.resolvedRows.filter { $0.kind == .numbers }.count, 1)
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows[0]), TerminalRowPreset.numbers.items)
        XCTAssertTrue(profile.valid)
    }
    func testCompleteTemplateDoesNotDiscardExtraCustomPlacements() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.tmux.shortcuts[0]))
        profile.place(id, in: TerminalKeyboardRow.numbersID)
        let new = try XCTUnwrap(profile.installEditorPreset(.numbers, before: profile.resolvedRows.first?.id))
        XCTAssertNotEqual(new, TerminalKeyboardRow.numbersID)
        let old = try XCTUnwrap(profile.resolvedRows.first { $0.id == TerminalKeyboardRow.numbersID })
        XCTAssertEqual(profile.barItems(in: old), [.saved(id)])
        XCTAssertTrue(profile.actions.first { $0.id == id }!.inRow)
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first { $0.id == new }!), TerminalRowPreset.numbers.items)
        XCTAssertTrue(profile.valid)
    }
    func testReplacingAKeyIsAtomicAndPreservesItsPosition() throws {
        var profile = TerminalControlsProfile.defaults
        let main = TerminalKeyboardRow.mainID
        let before = profile
        XCTAssertFalse(profile.replaceEditorItem(.key("key-tab"), in: main, with: .control(.ctrl)))
        XCTAssertEqual(profile, before)
        let old = profile.barItems(in: profile.resolvedRows.first { $0.id == main }!)
        XCTAssertTrue(profile.replaceEditorItem(.key("key-tab"), in: main, with: .key("key-f12")))
        let changed = profile.barItems(in: profile.resolvedRows.first { $0.id == main }!)
        XCTAssertEqual(changed.firstIndex(of: .key("key-f12")), old.firstIndex(of: .key("key-tab")))
        XCTAssertTrue(profile.valid)
    }
    func testFavoriteReplacementKeepsOneIdentityAndItsKeyEditingBehavior() throws {
        var profile = TerminalControlsProfile.defaults
        let id = profile.pin(TerminalPaletteKey(.home), in: .menu)
        profile.place(id, in: TerminalKeyboardRow.mainID)
        XCTAssertTrue(profile.replaceEditorFavorite(id, with: TerminalPaletteKey(.f8)))
        let action = try XCTUnwrap(profile.actions.first { $0.id == id })
        XCTAssertEqual(action.kind, .key)
        XCTAssertEqual(action.key, .f8)
        XCTAssertEqual(action.placements(in: profile).count, 2)
        XCTAssertEqual(profile.actions.filter { $0.id == id }.count, 1)
        XCTAssertTrue(profile.valid)
    }
    func testRemovingMainRowPromotesAnotherAndLastRowRemainsEditable() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.addRow(title: "My Keys"))
        profile.placeBarItem(.key("key-f12"), in: id)
        profile.removeEditorRow(TerminalKeyboardRow.mainID)
        XCTAssertEqual(profile.resolvedRows.first { $0.kind == .main }?.id, id)
        for row in profile.resolvedRows where row.id != id { profile.removeEditorRow(row.id) }
        profile.removeEditorRow(id)
        XCTAssertEqual(profile.resolvedRows.count, 1)
        XCTAssertTrue(profile.barItems(in: profile.resolvedRows[0]).isEmpty)
        XCTAssertTrue(profile.valid)
    }
    func testMenuRestoreAndUndoKeepKeyboardAndSharedPayloads() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.tmux.shortcuts[0]))
        profile.place(id, in: TerminalKeyboardRow.mainID); profile.pin(id, in: .menu, enabled: true)
        let before = profile
        var history = TerminalLayoutHistory()
        profile.restoreMenuFavorites(); history.changed(from: before, to: profile)
        XCTAssertEqual(profile.actions.first { $0.id == id }?.character, 0x62)
        XCTAssertTrue(profile.actions.first { $0.id == id }!.inRow)
        XCTAssertFalse(profile.actions.first { $0.id == id }!.inMenu)
        let restored = try XCTUnwrap(history.undo())
        history.changed(from: profile, to: restored)
        XCTAssertTrue(history.values.isEmpty)
        XCTAssertEqual(restored, before)
        XCTAssertTrue(profile.valid)
    }
    func testAllPresetKeysAreValidSingleChordsAndRepeatedAdditionReusesDefinition() throws {
        var profile = TerminalControlsProfile.defaults
        let presets = TerminalShortcutPack.allCases.flatMap(\.shortcuts)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        for preset in presets {
            XCTAssertTrue(preset.action.valid, preset.id)
            XCTAssertEqual(preset.action.kind, .shortcut)
            XCTAssertTrue(preset.action.text.isEmpty, "Presets cannot inject command text or implicit Return")
            let id = try XCTUnwrap(profile.add(preset))
            profile.place(id, in: TerminalKeyboardRow.mainID)
            profile.pin(id, in: .menu, enabled: true)
            let again = try XCTUnwrap(TerminalShortcutPack.allCases.flatMap(\.shortcuts).first { $0.id == preset.id })
            XCTAssertEqual(profile.add(again), id)
            XCTAssertEqual(profile.actions.filter { $0.presetID == preset.id }.count, 1)
        }
        XCTAssertTrue(profile.valid)
        let restored = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored, profile)
    }
    func testToolPrefixesAndModePrerequisitesRemainExplicit() throws {
        let tmux = TerminalShortcutPack.tmux.shortcuts
        XCTAssertEqual(tmux.first?.action.character, 0x62)
        XCTAssertEqual(tmux.first?.action.modifiers, [0xffe3])
        XCTAssertTrue(tmux.dropFirst().allSatisfy { $0.action.modifiers.isEmpty && $0.action.usage == "After Tmux Prefix" })
        let herdr = TerminalShortcutPack.herdr.shortcuts
        let rename = try XCTUnwrap(herdr.first { $0.id == "herdr.rename" })
        XCTAssertEqual(rename.action.character, 0x57)
        XCTAssertEqual(herdr.first { $0.id == "herdr.workspace" }?.action.character, 0x4e)
        XCTAssertEqual(herdr.first { $0.id == "herdr.zoom" }?.action.character, 0x7a)
        XCTAssertTrue(rename.action.modifiers.isEmpty)
        XCTAssertEqual(TerminalKeyEncoding().bytes(.text("N")), [0x4e])
        XCTAssertEqual(TerminalShortcutPack.zellij.shortcuts.first?.action.modifiers, [0xffe3])
        XCTAssertTrue(TerminalShortcutPack.zellijUnlock.shortcuts.dropFirst().allSatisfy { $0.action.usage == "After Zellij Unlock" && $0.action.modifiers.isEmpty })
    }
    func testRenameUpdatesBothPlacementsAndRemovalKeepsOneDefinition() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.tmux.shortcuts[0]))
        profile.place(id, in: TerminalKeyboardRow.mainID); profile.pin(id, in: .menu, enabled: true)
        let index = try XCTUnwrap(profile.actions.firstIndex { $0.id == id })
        profile.actions[index].title = "Tmux"
        XCTAssertEqual(profile.placed(.menu).first { $0.id == id }?.title, "Tmux")
        XCTAssertEqual(profile.placed(in: profile.resolvedRows.first { $0.kind == .main }!).first { $0.id == id }?.title, "Tmux")
        profile.removeBarItem(.saved(id), in: TerminalKeyboardRow.mainID)
        let item = try XCTUnwrap(profile.actions.first { $0.id == id })
        XCTAssertEqual(item.placements(in: profile), ["Floating Menu"])
        XCTAssertEqual(item.character, 0x62); XCTAssertEqual(item.modifiers, [0xffe3])
        XCTAssertFalse(item.inRow); XCTAssertTrue(item.inMenu)
        profile.place(id, in: TerminalKeyboardRow.mainID)
        XCTAssertEqual(profile.actions.filter { $0.id == id }.count, 1)
        XCTAssertTrue(profile.valid)
    }
    func testCancelledLayoutDraftRetainsOriginalDefinitionAndPlacements() throws {
        var saved = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(saved.add(TerminalShortcutPack.tmux.shortcuts[0]))
        saved.place(id, in: TerminalKeyboardRow.mainID); saved.pin(id, in: .menu, enabled: true)
        let before = try JSONEncoder().encode(saved)
        var draft = saved
        draft.actions[draft.actions.firstIndex { $0.id == id }!].title = "Cancelled"
        draft.removeBarItem(.saved(id)); draft.pin(id, in: .menu, enabled: false)
        draft.addPreset(.functions)
        XCTAssertNotEqual(draft, saved)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: before), saved)
        XCTAssertEqual(saved.actions.first { $0.id == id }?.placements(in: saved).count, 2)
    }
    func testSharedNavigationAndSpecialKeyPickerMatchSupportedCatalog() {
        XCTAssertEqual(TerminalControlNavigation.items.compactMap { $0["kind"] as? String }, ["moreKeys", "savedShortcuts", "savedText", "customize", "appearance", "session"])
        for key in TerminalKeyCatalog.all where key.modifiers.isEmpty {
            var item = TerminalControlAction(title: key.name, kind: .shortcut, inMenu: false)
            item.character = key.shortcutCode
            XCTAssertTrue(item.valid, key.name)
        }
        XCTAssertEqual(TerminalPaletteKey(.f12).shortcutCode, 0xffc9)
        XCTAssertEqual(TerminalPaletteKey(.home).shortcutCode, 0xff50)
        for key in TerminalAccessoryKey.allCases {
            var item = TerminalControlAction(title: key.title, kind: .shortcut, inMenu: false)
            item.character = key.shortcutCode
            XCTAssertEqual(item.shortcut.terminalBytes(), key.bytes(), key.rawValue)
        }
    }
}
#endif
