#if os(iOS)
import SwiftUI
import XCTest
import StoreKit
import StoreKitTest
@testable import Mac_Companion

@MainActor final class UnifiedControlsMenuTests: XCTestCase {
    @MainActor private final class Memory {
        var data: Data?
        var writes = 0
        var library: [VNCQuickAction] = []
        var menus = Dictionary(uniqueKeysWithValues: [DirectControlMode.desktop, .trackpad].map { ($0.rawValue, $0.defaults) })
        func store(_ mode: DirectControlMode = .desktop) -> TerminalControlsStore {
            .init(read: { self.data }, write: { self.data = $0; self.writes += 1 }, legacyIDs: { [] }, legacyActions: { self.library },
                family: .remoteMac, remoteMode: mode, legacyRemoteMenus: { self.menus })
        }
    }
    func testNavigationUsesTheSameSlotsAndContextualDisplayEntryInEveryMode() {
        for mode in DirectControlMode.allCases {
            let items = TerminalControlNavigation.items(for: mode == .terminal ? .terminal : .remoteMac)
            XCTAssertEqual(items.compactMap { $0["title"] as? String }, ["Keypad", "Shortcuts", "Text", "Customize Controls", mode == .terminal ? "Appearance" : "Display", "Session"])
            XCTAssertFalse(items.contains { $0["kind"] as? String == "inputMenu" })
        }
        XCTAssertEqual(RemoteMacControls.navigationItems.compactMap { $0["kind"] as? String }, ["moreKeys", "savedShortcuts", "savedText", "customize", "viewMenu", "session"])
    }
    func testRemoteFavoritesImportOnceWithoutChangingKeyboardOrOtherMode() throws {
        let memory = Memory()
        let sharedID = UUID()
        let desktop = VNCQuickAction(id: sharedID, title: "Desktop Text", kind: .text, text: "desktop")
        let trackpad = VNCQuickAction(id: sharedID, title: "Trackpad Text", kind: .text, text: "trackpad")
        memory.menus["desktop"] = [VNCQuickAction.composeText, desktop, .init(title: "Hidden", kind: .shortcut, enabled: false, key: 0x63, modifiers: [0xffe3])]
        memory.menus["trackpad"] = [.init(title: "Right Click", kind: .rightClick), trackpad]
        var previous = TerminalControlsProfile.remoteDefaults
        previous.addBarPlacement(.key("key-f12"), to: TerminalKeyboardRow.mainID)
        let rows = previous.keyboardRows
        memory.data = try JSONEncoder().encode(previous)
        var draft = try memory.store().load()
        XCTAssertEqual(draft.keyboardRows, rows)
        XCTAssertEqual(draft.placed(.menu).map(\.title), ["Compose Text", "Desktop Text"])
        XCTAssertEqual(Set(draft.savedItems(.text).map(\.text)), ["desktop", "trackpad"])
        XCTAssertEqual(Set(draft.actions.map(\.id)).count, draft.actions.count)
        XCTAssertTrue(draft.actions.contains { $0.title == "Hidden" && !$0.inMenu })
        XCTAssertEqual(try memory.store().load(), draft)
        let writes = memory.writes
        let trackpadBefore = try memory.store(.trackpad).load().resolvedMenuPlacements
        XCTAssertEqual(memory.writes, writes, "Selecting a mode must not rewrite the shared record")
        draft.removeMenuPlacement(try XCTUnwrap(draft.resolvedMenuPlacements.last).id)
        let saved = try memory.store().save(draft)
        XCTAssertEqual(try memory.store().load(), saved)
        XCTAssertEqual(try memory.store(.trackpad).load().resolvedMenuPlacements, trackpadBefore)
        XCTAssertEqual(try memory.store(.trackpad).load().keyboardRows, rows)
    }
    func testSavedDefinitionsAreSharedButFavoritePlacementsAndRestoreAreModeSpecific() throws {
        let memory = Memory()
        var desktop = try memory.store().load()
        var action = TerminalControlAction(title: "Two Steps", kind: .shortcut, inMenu: false)
        action.steps = [.init(character: 0x62, modifiers: [0xffe3]), .init(character: 0x63)]
        desktop.actions.append(action)
        desktop.pin(action.id, in: .menu, enabled: true)
        desktop.place(action.id, in: TerminalKeyboardRow.mainID)
        _ = try memory.store().save(desktop)
        var trackpad = try memory.store(.trackpad).load()
        XCTAssertTrue(trackpad.actions.contains { $0.id == action.id })
        XCTAssertFalse(trackpad.placed(.menu).contains { $0.id == action.id })
        trackpad.pin(action.id, in: .menu, enabled: true)
        _ = try memory.store(.trackpad).save(trackpad)
        let shared = try memory.store().load()
        let uses = try XCTUnwrap(shared.actions.first { $0.id == action.id }).placements(in: shared)
        XCTAssertTrue(uses.contains("Floating Menu · Screen Sharing"))
        XCTAssertTrue(uses.contains("Floating Menu · Trackpad & Keyboard"), "Deletion details must identify placements in the other remote mode too")
        let originalDesktop = try memory.store().load().resolvedMenuPlacements
        trackpad = try memory.store(.trackpad).load()
        trackpad.restoreMenuFavorites()
        _ = try memory.store(.trackpad).save(trackpad)
        XCTAssertEqual(try memory.store().load().resolvedMenuPlacements, originalDesktop)
        XCTAssertEqual(try memory.store(.trackpad).load().placed(.menu).map(\.title), DirectControlMode.trackpad.defaults.map(\.title))
        var deleting = try memory.store(.trackpad).load()
        deleting.delete(action.id)
        _ = try memory.store(.trackpad).save(deleting)
        for mode in [DirectControlMode.desktop, .trackpad] {
            let loaded = try memory.store(mode).load()
            XCTAssertTrue(loaded.valid)
            XCTAssertFalse(loaded.actions.contains { $0.id == action.id })
            XCTAssertFalse(loaded.placed(.menu).contains { $0.id == action.id })
            XCTAssertFalse(loaded.resolvedRows.flatMap { loaded.barItems(in: $0) }.contains(.saved(action.id)))
        }
    }
    func testRestoreDesktopFavoritesUsesDefaultOrderAfterReorderedImport() throws {
        try assertRestoresRemoteDefaultOrder(.desktop)
    }
    func testRestoreTrackpadFavoritesDoesNotInheritDesktopDefinitionOrder() throws {
        try assertRestoresRemoteDefaultOrder(.trackpad)
    }
    private func assertRestoresRemoteDefaultOrder(_ mode: DirectControlMode) throws {
        let memory = Memory()
        let text = VNCQuickAction(title: "Saved Text", kind: .text, text: "synthetic")
        memory.menus["desktop"] = [.init(title: "Right Click", kind: .rightClick),
            VNCQuickAction.composeText, .init(title: "Copy Text", kind: .copyText), text]
        let store = memory.store(mode)
        var draft = try store.load()
        let textID = try XCTUnwrap(draft.actions.first { $0.kind == .text }).id
        draft.place(textID, in: TerminalKeyboardRow.mainID)
        draft.pin(textID, in: .menu, enabled: true)
        _ = try store.save(draft)
        draft = try store.load()
        let rows = draft.keyboardRows
        let otherMode: DirectControlMode = mode == .desktop ? .trackpad : .desktop
        let otherFavorites = try memory.store(otherMode).load().resolvedMenuPlacements
        func definitions(_ profile: TerminalControlsProfile) -> [TerminalControlAction] {
            profile.actions.map { action in var action = action; action.inMenu = false; return action }
        }
        let originalDefinitions = definitions(draft)
        draft.restoreMenuFavorites()
        XCTAssertEqual(draft.placed(.menu).map(\.title), mode.defaults.map(\.title))
        _ = try store.save(draft)
        let reloaded = try store.load()
        XCTAssertTrue(reloaded.valid)
        XCTAssertEqual(reloaded.placed(.menu).map(\.title), mode.defaults.map(\.title))
        XCTAssertEqual(definitions(reloaded), originalDefinitions, "Restoring placements must preserve shared definition identities and content")
        XCTAssertEqual(reloaded.keyboardRows, rows)
        XCTAssertEqual(try memory.store(otherMode).load().resolvedMenuPlacements, otherFavorites)
    }
    func testRestoreTerminalFavoritesUsesDefaultOrderWithReversedDefinitions() throws {
        var data = try JSONEncoder().encode(TerminalControlsProfile.defaults)
        let store = TerminalControlsStore(read: { data }, write: { data = $0 },
            legacyIDs: { [] }, legacyActions: { [] })
        var draft = try store.load()
        draft.actions.reverse()
        let ids = Set(draft.actions.map(\.id))
        draft.restoreMenuFavorites()
        _ = try store.save(draft)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.placed(.menu).map(\.title), DirectControlMode.terminal.defaults.map(\.title))
        XCTAssertEqual(Set(reloaded.actions.map(\.id)), ids)
    }
    func testConcurrentRemoteModeEditsAreRejectedAndUnreadableLegacyFavoritesArePreserved() throws {
        let memory = Memory()
        let first = try memory.store().load()
        let second = try memory.store(.trackpad).load()
        _ = try memory.store().save(first)
        XCTAssertThrowsError(try memory.store(.trackpad).save(second)) { XCTAssertEqual($0 as? TerminalControlsStore.Failure, .staleDraft) }
        let original = try JSONEncoder().encode(TerminalControlsProfile.remoteDefaults)
        memory.data = original
        var store = memory.store()
        store.legacyRemoteMenus = { throw TerminalControlsStore.Failure.unreadable }
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(memory.data, original)
    }
    func testImportedShortcutNamesRemainDistinctEvenWhenTheirKeysMatch() throws {
        let memory = Memory()
        memory.menus["desktop"] = [.init(title: "Desktop Search", kind: .shortcut, key: 0x72, modifiers: [0xffe3])]
        memory.menus["trackpad"] = [.init(title: "Trackpad History", kind: .shortcut, key: 0x72, modifiers: [0xffe3])]
        let desktop = try memory.store().load(), trackpad = try memory.store(.trackpad).load()
        XCTAssertEqual(desktop.placed(.menu).map(\.title), ["Desktop Search"])
        XCTAssertEqual(trackpad.placed(.menu).map(\.title), ["Trackpad History"])
        XCTAssertNotEqual(desktop.placed(.menu).first?.id, trackpad.placed(.menu).first?.id)
    }
    func testImportedIdenticalShortcutsKeepDistinctIDsThroughEditingDeletionAndReload() throws {
        let memory = Memory()
        let first = VNCQuickAction(title: "Jump", kind: .shortcut, key: 0x62, modifiers: [0xffe3])
        let second = VNCQuickAction(title: "Jump", kind: .shortcut, key: 0x62, modifiers: [0xffe3])
        // Also cover a profile whose definitions were already imported before its menus.
        memory.library = [first, second].map { var item = $0; item.enabled = false; return item }
        memory.menus = ["desktop": [first], "trackpad": [second]]
        var desktop = try memory.store().load()
        XCTAssertEqual(desktop.placed(.menu).map(\.id), [first.id])
        XCTAssertEqual(try memory.store(.trackpad).load().placed(.menu).map(\.id), [second.id])
        XCTAssertEqual(desktop.savedItems(.shortcuts).count, 2)
        let index = try XCTUnwrap(desktop.actions.firstIndex { $0.id == second.id })
        desktop.actions[index].character = 0x78
        _ = try memory.store().save(desktop)
        XCTAssertEqual(try memory.store(.trackpad).load().placed(.menu).first?.character, 0x78)
        XCTAssertEqual(try memory.store().load().placed(.menu).first?.character, 0x62)
        var trackpad = try memory.store(.trackpad).load()
        trackpad.delete(second.id); _ = try memory.store(.trackpad).save(trackpad)
        XCTAssertTrue(try memory.store(.trackpad).load().placed(.menu).isEmpty)
        XCTAssertEqual(try memory.store().load().placed(.menu).map(\.id), [first.id])
    }
    func testSameIDAndDefinitionStaySharedWhileEnabledPlacementsRemainIndependent() throws {
        let memory = Memory()
        let shared = VNCQuickAction(title: "Shared", kind: .shortcut, key: 0x62, modifiers: [0xffe3])
        var hidden = shared; hidden.enabled = false
        memory.menus = ["desktop": [shared], "trackpad": [hidden]]
        let desktop = try memory.store().load(), trackpad = try memory.store(.trackpad).load()
        XCTAssertEqual(desktop.savedItems(.shortcuts).map(\.id), [shared.id])
        XCTAssertEqual(trackpad.savedItems(.shortcuts).map(\.id), [shared.id])
        XCTAssertEqual(desktop.placed(.menu).map(\.id), [shared.id]); XCTAssertTrue(trackpad.placed(.menu).isEmpty)
        XCTAssertEqual(try memory.store().load(), desktop)
    }
    func testConflictingIDIsRemappedOnceAndBothMenusReferenceItsMatchingDefinition() throws {
        let memory = Memory()
        let original = VNCQuickAction(title: "Jump", kind: .shortcut, key: 0x62, modifiers: [0xffe3])
        var conflicting = original; conflicting.key = 0x78
        var retained = original; retained.enabled = false
        memory.library = [retained]
        memory.menus = ["desktop": [conflicting], "trackpad": [conflicting]]
        let desktop = try memory.store().load(), trackpad = try memory.store(.trackpad).load()
        let imported = try XCTUnwrap(desktop.placed(.menu).first)
        XCTAssertNotEqual(imported.id, original.id); XCTAssertEqual(imported.character, 0x78)
        XCTAssertEqual(trackpad.placed(.menu).map(\.id), [imported.id])
        XCTAssertEqual(desktop.actions.first { $0.id == original.id }?.character, 0x62)
        XCTAssertEqual(desktop.savedItems(.shortcuts).count, 2, "Do not create an unreferenced extra copy for the second menu")
        XCTAssertEqual(try memory.store().load(), desktop)
        XCTAssertEqual(try memory.store(.trackpad).load(), trackpad)
    }
    func testFreshImportSplitsConflictingIDsAndRetainsDisabledTextWithoutPreloading() throws {
        let memory = Memory()
        let first = VNCQuickAction(title: "Jump", kind: .shortcut, key: 0x62, modifiers: [0xffe3])
        var second = first; second.key = 0x78
        let hidden = VNCQuickAction(title: "Hidden Text", kind: .text, enabled: false, text: "synthetic")
        memory.menus = ["desktop": [first, hidden], "trackpad": [second]]
        let desktop = try memory.store().load(), trackpad = try memory.store(.trackpad).load()
        XCTAssertEqual(desktop.placed(.menu).map(\.id), [first.id])
        XCTAssertEqual(trackpad.placed(.menu).first?.character, 0x78)
        XCTAssertNotEqual(trackpad.placed(.menu).first?.id, first.id)
        XCTAssertEqual(desktop.savedItems(.shortcuts).count, 2)
        XCTAssertEqual(desktop.savedItems(.text).map(\.id), [hidden.id])
        XCTAssertEqual(try memory.store().load(), desktop)
        XCTAssertEqual(try memory.store(.trackpad).load(), trackpad)
    }
    func testOpeningPointerSettingsDoesNotWritePreferencesOrNotifyTheSession() async throws {
        let id = UUID()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let prefix = "direct-session-" + id.uuidString.lowercased() + "-"
        let before = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
        var notifications = 0
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            VNCPointerSettings(macID: id, mode: .desktop, changed: { notifications += 1 })
        })
        window.makeKeyAndVisible(); window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) } as NSDictionary, before as NSDictionary)
    }
    func testRemoteActionsRemainContextualAndDoNotAppearInTerminal() throws {
        let memory = Memory()
        let desktop = try memory.store().load(), trackpad = try memory.store(.trackpad).load()
        XCTAssertTrue(desktop.availableActions.contains(.rightClick))
        XCTAssertTrue(desktop.availableActions.contains(.copyScreenText))
        XCTAssertTrue(trackpad.availableActions.contains(.rightClick))
        XCTAssertFalse(trackpad.availableActions.contains(.copyScreenText))
        XCTAssertFalse(trackpad.availableActions.contains(.fitToWindow))
        XCTAssertTrue(TerminalControlsProfile.defaults.availableActions.allSatisfy { !$0.remoteOnly })
        var invalid = TerminalControlsProfile.defaults
        invalid.actions.append(TerminalAppAction.rightClick.definition)
        XCTAssertFalse(invalid.valid)
    }
}
#endif
