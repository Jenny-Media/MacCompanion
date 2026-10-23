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
        var menus = Dictionary(uniqueKeysWithValues: [DirectControlMode.desktop, .trackpad].map { ($0.rawValue, $0.defaults) })
        func store(_ mode: DirectControlMode = .desktop) -> TerminalControlsStore {
            .init(read: { self.data }, write: { self.data = $0; self.writes += 1 }, legacyIDs: { [] }, legacyActions: { [] },
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
