#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class TerminalControlsRedesignTests: XCTestCase {
    func testRowAlignmentRoundTripsAndDraftCancellationRetainsOriginal() throws {
        let saved = TerminalControlsProfile.defaults
        for alignment in TerminalKeyboardRow.Alignment.allCases {
            var draft = saved, rows = saved.resolvedRows
            rows[0].alignment = alignment; draft.keyboardRows = rows
            XCTAssertTrue(draft.valid)
            let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(draft))
            XCTAssertEqual(decoded.resolvedRows[0].resolvedAlignment, alignment)
            XCTAssertEqual(saved.resolvedRows[0].resolvedAlignment, .fill)
            XCTAssertNil(saved.keyboardRows)
        }
    }
    func testTemplatesAddCompleteIndependentRowsAndLeaveExistingRowsIntact() throws {
        var profile = TerminalControlsProfile.defaults
        let source = try XCTUnwrap(profile.addRow(title: "Arrows"))
        profile.placeBarItem(.key("key-up"), in: source)
        let before = profile.resolvedRows.map { ($0.id, profile.barItems(in: $0)) }
        let id = try XCTUnwrap(profile.installEditorPreset(.navigation, before: profile.resolvedRows.first?.id))
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first { $0.id == id }!), TerminalRowPreset.navigation.items)
        for (id, items) in before { XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first { $0.id == id }!), items) }
        XCTAssertTrue(profile.valid)
    }
    func testNumbersTemplateAlwaysAddsAnotherCompleteRow() throws {
        var profile = TerminalControlsProfile.defaults
        let first = try XCTUnwrap(profile.resolvedRows.first?.id)
        let added = try XCTUnwrap(profile.installEditorPreset(.numbers, before: first))
        XCTAssertNotEqual(added, first)
        XCTAssertEqual(profile.resolvedRows.first?.id, added)
        XCTAssertEqual(profile.resolvedRows.filter { $0.preset == .numbers }.count, 2)
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows[0]), TerminalRowPreset.numbers.items)
        XCTAssertTrue(profile.valid)
    }
    func testCompleteTemplateKeepsExistingCustomAndPresetKeys() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.tmux.shortcuts[0]))
        profile.place(id, in: TerminalKeyboardRow.numbersID)
        let new = try XCTUnwrap(profile.installEditorPreset(.numbers, before: profile.resolvedRows.first?.id))
        let old = try XCTUnwrap(profile.resolvedRows.first { $0.id == TerminalKeyboardRow.numbersID })
        XCTAssertEqual(profile.barItems(in: old), TerminalRowPreset.numbers.items + [.saved(id)])
        XCTAssertEqual(profile.barItems(in: profile.resolvedRows.first { $0.id == new }!), TerminalRowPreset.numbers.items)
        XCTAssertTrue(profile.valid)
    }
    func testReplacingAnExactOccurrenceCanDuplicateAKeyAndPreservesItsIdentity() throws {
        var profile = TerminalControlsProfile.defaults
        let main = TerminalKeyboardRow.mainID
        let old = profile.barPlacements(in: profile.resolvedRows.first { $0.id == main }!)
        let tab = try XCTUnwrap(old.first { $0.item == .key("key-tab") })
        XCTAssertTrue(profile.replaceEditorItem(tab.item, in: main, with: .control(.ctrl), placementID: tab.id))
        let changed = profile.barPlacements(in: profile.resolvedRows.first { $0.id == main }!)
        XCTAssertEqual(changed.map(\.id), old.map(\.id))
        XCTAssertEqual(changed.filter { $0.item == .control(.ctrl) }.count, 2)
        XCTAssertTrue(profile.valid)
    }
    func testRepeatedKeypadPinsAddCopiesButReuseOneSavedDefinition() throws {
        var profile = TerminalControlsProfile.defaults
        let key = TerminalPaletteKey(.f8)
        let id = profile.pin(key, in: .keyboard)
        XCTAssertEqual(profile.pin(key, in: .keyboard), id)
        XCTAssertEqual(profile.pin(key, in: .menu), id)
        XCTAssertEqual(profile.pin(key, in: .menu), id)
        let row = try XCTUnwrap(profile.resolvedRows.first { $0.kind == .main })
        XCTAssertEqual(profile.barPlacements(in: row).filter { $0.item == .saved(id) }.count, 2)
        XCTAssertEqual(profile.resolvedMenuPlacements.filter { $0.actionID == id }.count, 2)
        XCTAssertEqual(profile.actions.filter { $0.id == id }.count, 1)
        XCTAssertTrue(profile.valid)
    }
    func testRepeatedPlacementsMoveRemoveAndUndoOnlyTheSelectedCopy() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.add(TerminalShortcutPack.herdr.shortcuts[1]))
        let main = TerminalKeyboardRow.mainID
        profile.place(id, in: main); profile.place(id, in: main)
        profile.pin(id, in: .menu, enabled: true); profile.pin(id, in: .menu, enabled: true)
        let row = try XCTUnwrap(profile.resolvedRows.first { $0.id == main })
        let copies = profile.barPlacements(in: row).filter { $0.item == .saved(id) }
        XCTAssertEqual(copies.count, 2); XCTAssertNotEqual(copies[0].id, copies[1].id)
        let saved = profile
        profile.moveBarPlacement(copies[1].id, from: main, to: TerminalKeyboardRow.numbersID)
        XCTAssertTrue(profile.barPlacements(in: profile.resolvedRows.first { $0.id == main }!).contains(copies[0]))
        profile.removeBarPlacement(copies[1].id, in: TerminalKeyboardRow.numbersID)
        XCTAssertTrue(profile.actions.first { $0.id == id }!.inRow)
        let favorites = profile.resolvedMenuPlacements.filter { $0.actionID == id }
        XCTAssertEqual(favorites.count, 2)
        profile.removeMenuPlacement(favorites[1].id)
        XCTAssertEqual(profile.resolvedMenuPlacements.filter { $0.actionID == id }.map(\.id), [favorites[0].id])
        XCTAssertTrue(profile.actions.first { $0.id == id }!.inMenu)
        profile.actions[profile.actions.firstIndex { $0.id == id }!].title = "Shared edit"
        XCTAssertEqual(profile.menuPreviewActions.first { $0.id == favorites[0].id }?.title, "Shared edit")
        var history = TerminalLayoutHistory(); history.changed(from: saved, to: profile)
        XCTAssertEqual(history.undo(), saved)
        XCTAssertTrue(profile.valid)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testLegacyPlacementIdentitiesPersistAcrossReorderingAndRejectCorruptIdentities() throws {
        var profile = TerminalControlsProfile.defaults
        let original = profile.resolvedRows[0]
        let ids = profile.barPlacements(in: original).map(\.id)
        profile.placeBarItem(.key("key-f8"), in: original.id)
        profile.moveRow(original.id, before: nil)
        XCTAssertEqual(profile.rowTitle(original.id), "Row 3")
        let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(Array(decoded.barPlacements(in: decoded.resolvedRows.last!).map(\.id).prefix(ids.count)), ids)
        XCTAssertTrue(decoded.valid)
        profile.keyboardRows![0].placementIDs![0] = profile.keyboardRows![0].placementIDs![1]
        XCTAssertFalse(profile.valid)
    }
    func testCompactLabelsPreserveExactCaseAndChordAndFullDetails() {
        let tmux = TerminalShortcutPack.tmux.shortcuts, herdr = TerminalShortcutPack.herdr.shortcuts
        XCTAssertEqual(tmux[0].action.keycapTitle, "⌃b")
        XCTAssertEqual(tmux[1].action.keycapTitle, "c")
        XCTAssertEqual(tmux[4].action.keycapTitle, "%")
        XCTAssertEqual(herdr[1].action.keycapTitle, "N")
        XCTAssertEqual(TerminalShortcutPack.zellij.shortcuts[0].action.keycapTitle, "⌃p")
        XCTAssertEqual(tmux[1].action.title, "Tmux New Window")
        XCTAssertEqual(tmux[1].action.usage, "After Tmux Prefix")
    }
    func testScrollStartPreferenceIsIndependentOfAlignmentAndRoundTrips() throws {
        for alignment in TerminalKeyboardRow.Alignment.allCases {
            for start in TerminalKeyboardRow.ScrollStart.allCases {
                var profile = TerminalControlsProfile.defaults, rows = profile.resolvedRows
                rows[0].alignment = alignment; rows[0].scrollStart = start; profile.keyboardRows = rows
                let decoded = try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile))
                XCTAssertEqual(decoded.resolvedRows[0].startsAtRight, start == .right || start == .automatic && alignment == .right)
                XCTAssertTrue(decoded.valid)
            }
        }
    }
    func testFavoriteReplacementPreservesPlacementAndLeavesKeyboardDefinitionUnchanged() throws {
        var profile = TerminalControlsProfile.defaults
        let id = profile.pin(TerminalPaletteKey(.home), in: .menu)
        profile.place(id, in: TerminalKeyboardRow.mainID)
        let favorite = try XCTUnwrap(profile.resolvedMenuPlacements.first { $0.actionID == id })
        XCTAssertTrue(profile.replaceEditorFavorite(favorite.id, with: TerminalPaletteKey(.f8)))
        let action = try XCTUnwrap(profile.actions.first { $0.id == id })
        XCTAssertEqual(action.kind, .key)
        XCTAssertEqual(action.key, .home)
        XCTAssertTrue(action.inRow); XCTAssertFalse(action.inMenu)
        let replaced = try XCTUnwrap(profile.resolvedMenuPlacements.first { $0.id == favorite.id })
        XCTAssertNotEqual(replaced.actionID, id)
        XCTAssertEqual(profile.actions.first { $0.id == replaced.actionID }?.key, .f8)
        XCTAssertEqual(profile.actions.filter { $0.id == id }.count, 1)
        XCTAssertTrue(profile.valid)
        XCTAssertEqual(try JSONDecoder().decode(TerminalControlsProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testReplacingSecondFavoriteReusesKeyDefinitionAndUndoRestoresOnlyThatDraft() throws {
        var saved = TerminalControlsProfile.defaults
        let home = saved.pin(TerminalPaletteKey(.home), in: .menu)
        saved.pin(home, in: .menu, enabled: true); saved.place(home, in: TerminalKeyboardRow.mainID)
        let f8 = saved.pin(TerminalPaletteKey(.f8), in: .menu)
        let originals = saved.resolvedMenuPlacements
        let second = try XCTUnwrap(originals.filter { $0.actionID == home }.last)
        var draft = saved
        XCTAssertTrue(draft.replaceEditorFavorite(second.id, with: TerminalPaletteKey(.f8)))
        XCTAssertEqual(draft.resolvedMenuPlacements.map(\.id), originals.map(\.id))
        XCTAssertEqual(draft.resolvedMenuPlacements.filter { $0.actionID == home }.count, 1)
        XCTAssertEqual(draft.resolvedMenuPlacements.filter { $0.actionID == f8 }.count, 2)
        XCTAssertEqual(draft.actions, saved.actions, "Existing definitions and pin flags need no changes when both keys remain placed")
        XCTAssertEqual(draft.keyboardRows, saved.keyboardRows)
        XCTAssertTrue(draft.valid)
        var history = TerminalLayoutHistory(); history.changed(from: saved, to: draft)
        XCTAssertEqual(history.undo(), saved)
        XCTAssertEqual(saved.resolvedMenuPlacements, originals, "Cancel leaves saved favorites unchanged")
        let before = draft
        XCTAssertFalse(draft.replaceEditorFavorite(UUID(), with: TerminalPaletteKey(.f9)))
        XCTAssertEqual(draft, before, "A stale occurrence must not replace another favorite or create a definition")
    }
    func testDeletingSavedItemsAfterRestoringAndEditingRowsPreservesPresetKeys() throws {
        for kind in [TerminalControlAction.Kind.text, .shortcut] {
            for setting in ["Alignment", "Scroll Start", "Order"] {
                var target = TerminalControlAction(title: "Unused", kind: kind, text: "synthetic", inMenu: false)
                if kind == .shortcut { target.character = 0x62; target.modifiers = [0xffe3] }
                let retained = TerminalControlAction(title: "Keep", kind: .text, text: "keep this", inMenu: false)
                var profile = TerminalControlsProfile.defaults
                profile.actions += [target, retained]; profile.freezeKeyboardLayout(); profile.restoreKeyboardBar()
                if setting == "Order" { profile.moveRow(TerminalKeyboardRow.numbersID, offset: 1) }
                else {
                    var rows = profile.resolvedRows
                    if setting == "Alignment" { rows[0].alignment = .right } else { rows[0].scrollStart = .right }
                    profile.keyboardRows = rows
                }
                var data = try JSONEncoder().encode(profile)
                let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] })
                var loaded = try store.load()
                XCTAssertEqual(loaded.rowsSchema, TerminalControlsProfile.currentRowsSchema)
                XCTAssertTrue(loaded.resolvedRows.allSatisfy { $0.items != nil })
                let rows = loaded.resolvedRows
                let keys = rows.map { loaded.barItems(in: $0) }
                loaded.delete(target.id)
                _ = try store.save(loaded)
                let reopened = try store.load()
                XCTAssertEqual(reopened.resolvedRows, rows, "Deleting unused \(kind) after \(setting) must retain rows and their settings")
                XCTAssertEqual(reopened.resolvedRows.map { reopened.barItems(in: $0) }, keys)
                XCTAssertFalse(reopened.actions.contains { $0.id == target.id })
                XCTAssertEqual(reopened.actions.first { $0.id == retained.id }, retained)
                XCTAssertTrue(reopened.valid)
            }
        }
    }
    func testLegacyFavoriteReplacementAndSharedDefinitionEditingRemainDistinct() throws {
        var legacy = TerminalControlsProfile.defaults
        let home = TerminalControlAction(title: "Home", kind: .key, key: .home)
        legacy.actions.append(home)
        XCTAssertNil(legacy.menuPlacements)
        XCTAssertTrue(legacy.replaceEditorFavorite(home.id, with: TerminalPaletteKey(.f8)))
        XCTAssertEqual(legacy.resolvedMenuPlacements.first { $0.id == home.id }.flatMap { p in legacy.actions.first { $0.id == p.actionID } }?.key, .f8)
        XCTAssertEqual(legacy.actions.first { $0.id == home.id }?.key, .home)
        XCTAssertTrue(legacy.valid)

        for kind in [TerminalControlAction.Kind.shortcut, .text] {
            var profile = TerminalControlsProfile.defaults
            var action = TerminalControlAction(title: "Shared", kind: kind, text: "before", inMenu: false)
            action.character = 0x61
            profile.actions.append(action)
            profile.pin(action.id, in: .menu, enabled: true); profile.pin(action.id, in: .menu, enabled: true)
            profile.place(action.id, in: TerminalKeyboardRow.mainID)
            let index = try XCTUnwrap(profile.actions.firstIndex { $0.id == action.id })
            profile.actions[index].title = "Edited"; profile.actions[index].text = "after"; profile.actions[index].character = 0x62
            let copies = profile.placed(.menu).filter { $0.id == action.id }
            XCTAssertEqual(copies.count, 2)
            XCTAssertTrue(copies.allSatisfy { $0.title == "Edited" && $0.text == "after" && $0.character == 0x62 })
            XCTAssertTrue(profile.barItems(in: profile.resolvedRows.first { $0.kind == .main }!).contains(.saved(action.id)))
            XCTAssertTrue(profile.valid)
        }
    }
    func testDeletingPlacedSavedItemKeepsImplicitKeysAndOtherSavedPlacements() throws {
        var profile = TerminalControlsProfile.defaults
        profile.freezeKeyboardLayout(); profile.restoreKeyboardBar()
        let removed = TerminalControlAction(title: "Remove", kind: .text, text: "remove", inRow: true, inMenu: false)
        let kept = TerminalControlAction(title: "Keep", kind: .text, text: "keep", inRow: true, inMenu: false)
        profile.actions += [removed, kept]
        var rows = profile.resolvedRows
        let main = try XCTUnwrap(rows.firstIndex { $0.kind == .main })
        // Exercise an implicit in-memory draft explicitly; Restore now freezes
        // persisted defaults instead of leaving their contents implicit.
        rows[main].items = nil; rows[main].placementIDs = nil
        rows[main].actionIDs = [removed.id, kept.id]; profile.keyboardRows = rows
        let before = profile.resolvedRows.map { profile.barItems(in: $0) }
        profile.delete(removed.id)
        XCTAssertEqual(profile.resolvedRows.map { profile.barItems(in: $0) }, before.map { $0.filter { $0.savedID != removed.id } })
        XCTAssertTrue(profile.actions.first { $0.id == kept.id }!.inRow)
        XCTAssertTrue(profile.valid)
    }
    func testRemovingMainRowPromotesAnotherAndLastRowRemainsEditable() throws {
        var profile = TerminalControlsProfile.defaults
        let id = try XCTUnwrap(profile.addRow(title: "My Keys"))
        profile.placeBarItem(.key("key-f12"), in: id)
        profile.removeEditorRow(TerminalKeyboardRow.mainID)
        let promoted = try XCTUnwrap(profile.resolvedRows.first { $0.kind == .main })
        XCTAssertEqual(promoted.visibility, .always)
        XCTAssertTrue(profile.barItems(in: profile.resolvedRows.first { $0.id == id }!).contains(.key("key-f12")))
        for row in profile.resolvedRows where row.id != promoted.id { profile.removeEditorRow(row.id) }
        profile.removeEditorRow(promoted.id)
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
