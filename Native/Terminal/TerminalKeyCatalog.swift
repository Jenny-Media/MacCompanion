#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Runtime catalog and pin/editor picker use identical definitions. Literal
/// characters are shortcut keys, never saved-text pastes or implicit Return.
struct TerminalPaletteKey: Identifiable, Equatable {
    let id: String
    let title: String
    let name: String
    let accessory: TerminalAccessoryKey?
    let character: UInt32
    let modifiers: [UInt32]
    var pickerTitle: String { shortcutCode == 0xff0d ? "↵ Return" : title }
    var searchAliases: [String] { shortcutCode == 0xff0d ? ["Enter"] : [] }
    init(_ key: TerminalAccessoryKey, name: String? = nil) {
        id = "key-" + key.rawValue; title = key.title; self.name = name ?? key.title
        accessory = key; character = 0; modifiers = []
    }
    init(_ title: String, name: String? = nil, character: UInt32, modifiers: [UInt32] = []) {
        id = "character-\(character)-" + modifiers.map(String.init).joined(separator: "-")
        self.title = title; self.name = name ?? title; accessory = nil; self.character = character; self.modifiers = modifiers
    }
    var definition: TerminalControlAction {
        if let accessory { return .init(title: name, kind: .key, key: accessory, inMenu: false) }
        var item = TerminalControlAction(title: name, kind: .shortcut, inMenu: false)
        item.character = character; item.modifiers = modifiers; return item
    }
    func matches(_ item: TerminalControlAction) -> Bool {
        if let accessory { return item.kind == .key && item.key == accessory }
        return item.kind == .shortcut && item.resolvedSteps.count == 1 && item.resolvedSteps[0].kind == .key && item.resolvedSteps[0].character == character && item.resolvedSteps[0].modifiers == modifiers
    }
}

enum TerminalKeyCatalog {
    struct Group: Identifiable { let title: String; let keys: [TerminalPaletteKey]; var id: String { title } }
    static let groups: [Group] = [
        .init(title: "Essentials", keys: [.init(.escape, name: "Escape"), .init(.tab),
            .init("⇤", name: "Shift+Tab", character: 0xff09, modifiers: [0xffe1]),
            .init("⌫", name: "Backspace", character: 0xff08), .init(.delete, name: "Delete"), .init(.insert, name: "Insert"),
            .init("↵", name: "Return", character: 0xff0d), .init("Space", character: 0x20)]),
        .init(title: "Navigation", keys: [.init(.left, name: "Left"), .init(.down, name: "Down"), .init(.up, name: "Up"), .init(.right, name: "Right"),
            .init(.home), .init(.end), .init(.pageUp, name: "Page Up"), .init(.pageDown, name: "Page Down")]),
        .init(title: "Function Keys", keys: [TerminalAccessoryKey.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12].map { TerminalPaletteKey($0) }),
        .init(title: "Common Shortcuts", keys: ["c", "d", "z", "r", "a", "e", "k", "l"].map {
            .init("⌃" + $0.uppercased(), name: "Ctrl+" + $0.uppercased(), character: $0.unicodeScalars.first!.value, modifiers: [0xffe3])
        }),
        .init(title: "Symbols", keys: Array("/\\|~-_`$&*(){}[]<>=+:;'\"!?%^@#").map {
            .init(String($0), character: $0.unicodeScalars.first!.value)
        }),
        .init(title: "Numbers", keys: Array("1234567890").map { .init(String($0), character: $0.unicodeScalars.first!.value) })
    ]
    static var all: [TerminalPaletteKey] { groups.flatMap(\.keys) }
    static func key(_ id: String) -> TerminalPaletteKey? { all.first { $0.id == id } }
    static func matching(_ query: String, in group: Group) -> [TerminalPaletteKey] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return group.keys.filter { key in
            query.isEmpty || key.title.localizedCaseInsensitiveContains(query) || key.name.localizedCaseInsensitiveContains(query)
                || group.title.localizedCaseInsensitiveContains(query) || key.searchAliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

extension TerminalControlsProfile {
    @discardableResult mutating func pin(_ key: TerminalPaletteKey, in destination: TerminalControlsDestination) -> UUID {
        let id: UUID
        if let existing = actions.first(where: { key.matches($0) }) { id = existing.id }
        else { let item = key.definition; actions.append(item); id = item.id }
        pin(id, in: destination, enabled: true)
        return id
    }
}
#endif
