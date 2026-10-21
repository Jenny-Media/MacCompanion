#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// One definition can be placed in either surface without copying its payload.
struct TerminalControlAction: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case key, shortcut, text, builtIn }
    var id = UUID()
    var title: String
    var kind: Kind
    var key: TerminalAccessoryKey? = nil
    var character: UInt32 = 0
    var modifiers: [UInt32] = []
    var text = ""
    var builtIn: VNCQuickAction.Kind? = nil
    var inRow = false
    var inMenu = true

    init(_ saved: VNCQuickAction) {
        id = saved.id; title = saved.title; character = saved.key
        modifiers = saved.modifiers; text = saved.text; inMenu = saved.enabled
        kind = saved.kind == .shortcut ? .shortcut : saved.kind == .text ? .text : .builtIn
        builtIn = kind == .builtIn ? saved.kind : nil
    }
    init(id: UUID = UUID(), title: String, kind: Kind, key: TerminalAccessoryKey? = nil,
         text: String = "", inRow: Bool = false, inMenu: Bool = true) {
        self.id = id; self.title = title; self.kind = kind; self.key = key
        self.text = text; self.inRow = inRow; self.inMenu = inMenu
    }
    var shortcut: VNCQuickAction {
        .init(id: id, title: title, kind: .shortcut, key: character, modifiers: modifiers)
    }
    var requiresCommand: Bool { kind == .shortcut && modifiers.contains(0xffeb) }
    var valid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 40 else { return false }
        switch kind {
        case .key: return key != nil
        case .shortcut: return shortcut.valid && shortcut.compatible(with: .terminal)
        case .text: return !text.isEmpty && text.utf8.count <= 4096 && !text.contains("\0") && !text.contains("\u{1b}")
        case .builtIn: return builtIn.map { kind in DirectQuickActionEditing.standards(.terminal).contains { $0.kind == kind } } ?? false
        }
    }
    var symbol: String {
        switch kind { case .key, .shortcut: "keyboard"; case .text: "text.quote"; case .builtIn: VNCQuickAction(title: title, kind: builtIn ?? .escape).symbol }
    }
    var detail: String {
        switch kind { case .key: key?.title ?? "Choose a key"; case .shortcut: shortcut.shortcutTitle; case .text: text; case .builtIn: "Standard action" }
    }
    var native: [String: Any] {
        ["id": id.uuidString, "kind": "terminalAction", "title": title, "symbol": symbol, "enabled": true,
         "requiresCommand": requiresCommand,
         "inputAction": kind != .builtIn || builtIn != .composeText]
    }
}

enum TerminalControlsDestination: String, CaseIterable, Identifiable, Hashable {
    case keyboard, menu
    var id: String { rawValue }
    var title: String { self == .keyboard ? "Keyboard Bar" : "Floating Menu" }
    var symbol: String { self == .keyboard ? "keyboard" : "ellipsis.circle" }
}

struct TerminalControlsProfile: Codable, Equatable {
    var version = 1
    var revision = UUID()
    var actions: [TerminalControlAction] = []
    var importedMacs: Set<UUID> = []
    // Optional fields decode existing v1 records without rewriting their content.
    var rowOrder: [UUID]?
    var menuOrder: [UUID]?
    var numberRow: Bool?
    var expandedBar: Bool? // Retained for compatibility; the bar now always uses one row.
    var navigationRow: Bool?
    func placed(_ destination: TerminalControlsDestination) -> [TerminalControlAction] {
        let items = actions.filter { destination == .keyboard ? $0.inRow : $0.inMenu }
        let order = destination == .keyboard ? rowOrder : menuOrder
        let ranks = Dictionary(uniqueKeysWithValues: (order ?? []).enumerated().map { ($1, $0) })
        return items.enumerated().sorted {
            (ranks[$0.element.id] ?? (actions.count + $0.offset)) < (ranks[$1.element.id] ?? (actions.count + $1.offset))
        }.map(\.element)
    }
    mutating func move(_ id: UUID, to target: UUID, in destination: TerminalControlsDestination) {
        var order = placed(destination).map(\.id)
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: target), from != to else { return }
        order.insert(order.remove(at: from), at: to)
        if destination == .keyboard { rowOrder = order } else { menuOrder = order }
    }
    mutating func delete(_ id: UUID) {
        actions.removeAll { $0.id == id }; rowOrder?.removeAll { $0 == id }; menuOrder?.removeAll { $0 == id }
    }
    mutating func pin(_ id: UUID, in destination: TerminalControlsDestination, enabled: Bool) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        if destination == .keyboard { actions[index].inRow = enabled } else { actions[index].inMenu = enabled }
    }
    var valid: Bool {
        version == 1 && actions.count <= 4096 && importedMacs.count <= 4096
            && Set(actions.map(\.id)).count == actions.count && actions.allSatisfy(\.valid)
            && [rowOrder, menuOrder].allSatisfy { order in
                guard let order else { return true }
                return order.count <= 4096 && Set(order).count == order.count && Set(order).isSubset(of: Set(actions.map(\.id)))
            }
    }
    static var defaults: Self { .init(actions: DirectControlMode.terminal.defaults.map(TerminalControlAction.init)) }
    mutating func importKeyboard(_ preferences: TerminalKeyboardPreferences, macID: UUID) {
        guard !importedMacs.contains(macID) else { return }
        for key in preferences.keys where !actions.contains(where: { $0.kind == .key && $0.key == key }) {
            actions.append(.init(title: key.title, kind: .key, key: key, inRow: true, inMenu: false))
        }
        for snippet in preferences.snippets {
            // Source UUIDs can coincide across Macs or with quick actions. Keep
            // both records; the completed-Mac journal makes a retry idempotent.
            let id = actions.contains { $0.id == snippet.id } ? UUID() : snippet.id
            // Legacy snippets lived in a submenu, not among pinned quick
            // actions. Keep them in Saved Text without flooding the main menu.
            actions.append(.init(id: id, title: snippet.name, kind: .text, text: snippet.text, inMenu: false))
        }
        importedMacs.insert(macID)
    }
    mutating func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = actions.firstIndex(where: { $0.id == id }),
              let to = actions.firstIndex(where: { $0.id == target }) else { return }
        let item = actions.remove(at: from); actions.insert(item, at: to)
    }
}

/// Injectable persistence lets regression tests exercise failed reads/writes
/// without touching a person's actual snippets or Keychain records.
@MainActor struct TerminalControlsStore {
    static let account = DirectControlMode.terminal.profileID
    static let kind = "terminal-controls-v2"
    static let changed = Notification.Name("TerminalControlsChangedV2")
    enum Failure: Error { case unreadable, staleDraft }
    var read: () throws -> Data? = { try TerminalSecretStore.read(account, kind: kind) }
    var write: (Data) throws -> Void = { try TerminalSecretStore.write($0, id: account, kind: kind) }
    var legacyIDs: () throws -> [UUID] = { try TerminalSecretStore.accounts(kind: "terminal-keyboard-v1") }
    var legacyKeyboard: (UUID) throws -> TerminalKeyboardPreferences = { try .load($0) }
    var legacyActions: () throws -> [VNCQuickAction] = { try VNCSessionPreferences.profileActions(.terminal) }
    var excludedIDs: () -> Set<UUID> = { DirectTemporaryMacCleanup.shared.pending }

    func load() throws -> TerminalControlsProfile {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        let stored = try read()
        var profile: TerminalControlsProfile
        if let stored {
            guard stored.count <= 20 * 1024 * 1024 else { throw Failure.unreadable }
            profile = try JSONDecoder().decode(TerminalControlsProfile.self, from: stored)
            guard profile.valid else { throw Failure.unreadable }
        } else {
            let actions = try legacyActions()
            guard DirectQuickActionEditing.valid(actions, mode: .terminal) else { throw Failure.unreadable }
            profile = .init(actions: actions.map(TerminalControlAction.init))
        }
        let before = profile
        let excluded = excludedIDs()
        for id in try legacyIDs() where !profile.importedMacs.contains(id) && !excluded.contains(id) {
            let preferences = try legacyKeyboard(id)
            try preferences.validate()
            profile.importKeyboard(preferences, macID: id)
        }
        guard profile.valid else { throw Failure.unreadable }
        if stored == nil || profile != before {
            profile.revision = UUID()
            try persist(profile)
        }
        return profile
    }
    func save(_ draft: TerminalControlsProfile) throws -> TerminalControlsProfile {
        let current = try load()
        guard current.revision == draft.revision else { throw Failure.staleDraft }
        guard draft.valid, draft.importedMacs == current.importedMacs else { throw Failure.unreadable }
        var result = draft; result.revision = UUID()
        try persist(result)
        NotificationCenter.default.post(name: Self.changed, object: nil)
        return result
    }
    private func persist(_ profile: TerminalControlsProfile) throws {
        let data = try JSONEncoder().encode(profile)
        guard data.count <= 20 * 1024 * 1024 else { throw Failure.unreadable }
        try write(data)
    }
}
#endif
