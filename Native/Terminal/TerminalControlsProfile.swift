#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Local terminal operations, independent of key and shortcut definitions.
enum TerminalAppAction: String, Codable, CaseIterable, Identifiable {
    case composeText, paste, copySelection, keyboard, expandRows
    var id: String { rawValue }
    var title: String {
        switch self {
        case .composeText: "Compose Text"
        case .paste: "Paste"
        case .copySelection: "Copy Selection"
        case .keyboard: "Show/Hide Keyboard"
        case .expandRows: "Expand/Collapse Rows"
        }
    }
    var symbol: String {
        switch self {
        case .composeText: "square.and.pencil"
        case .paste: "document.on.clipboard"
        case .copySelection: "doc.on.doc"
        case .keyboard: "keyboard"
        case .expandRows: "rectangle.expand.vertical"
        }
    }
    var detail: String {
        switch self {
        case .composeText: "Open a draft before sending text"
        case .paste: "Paste clipboard text into the terminal"
        case .copySelection: "Copy selected terminal text"
        case .keyboard: "Show or hide the native keyboard"
        case .expandRows: "Show or hide rows set to When Expanded"
        }
    }
    var definition: TerminalControlAction {
        var action = TerminalControlAction(title: title, kind: .builtIn, inMenu: false)
        action.operation = self
        return action
    }
}

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
    var operation: TerminalAppAction? = nil
    var inRow = false
    var inMenu = true
    var presetID: String?
    var usage: String?

    init(_ saved: VNCQuickAction) {
        id = saved.id; title = saved.title; character = saved.key
        modifiers = saved.modifiers; text = saved.text; inMenu = saved.enabled
        kind = saved.kind == .shortcut ? .shortcut : saved.kind == .text ? .text : .builtIn
        builtIn = kind == .builtIn ? saved.kind : nil
        normalizeLegacyDefinition()
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
        guard operation == nil || kind == .builtIn else { return false }
        switch kind {
        case .key: return key != nil
        case .shortcut: return shortcut.terminalShortcutValid && shortcut.compatible(with: .terminal)
        case .text: return !text.isEmpty && text.utf8.count <= 4096 && !text.contains("\0") && !text.contains("\u{1b}")
        case .builtIn:
            if operation != nil { return builtIn == nil }
            return builtIn.map { kind in DirectQuickActionEditing.standards(.terminal).contains { $0.kind == kind } } ?? false
        }
    }
    var symbol: String {
        switch kind {
        case .key: key.flatMap { TerminalBarItem.key("key-" + $0.rawValue).symbol } ?? "keyboard"
        case .shortcut: "keyboard"
        case .text: "text.quote"
        case .builtIn: operation?.symbol ?? VNCQuickAction(title: title, kind: builtIn ?? .escape).symbol
        }
    }
    var detail: String {
        switch kind {
        case .key: return key?.title ?? "Choose a key"
        case .shortcut:
            let names: [(UInt32, String)] = [(0xffe3, "Ctrl"), (0xffe9, "Option"), (0xffe1, "Shift"), (0xffeb, "Command")]
            let title = TerminalAccessoryKey.allCases.first { $0.shortcutCode == character }?.title
                ?? (character == 0xff08 ? "Backspace" : character == 0xff0d ? "Return" : UnicodeScalar(character).map(String.init) ?? "Choose Key")
            return (names.filter { modifiers.contains($0.0) }.map(\.1) + [title]).joined(separator: " + ")
        case .text: return text
        case .builtIn: return operation?.detail ?? "Standard action"
        }
    }
    var native: [String: Any] {
        ["id": id.uuidString, "kind": "terminalAction", "title": title, "symbol": symbol, "enabled": true,
         "requiresCommand": requiresCommand,
         "inputAction": kind != .builtIn || (operation.map { $0 == .paste } ?? (builtIn != .composeText)),
         "defersInterfaceFeedback": operation == .copySelection || operation == .keyboard || operation == .expandRows]
    }
    /// Retain identity, title and placements while removing legacy aliases from
    /// the app-action category. In particular, Ctrl-C remains a saved shortcut.
    mutating func normalizeLegacyDefinition() {
        guard kind == .builtIn, operation == nil, let builtIn else { return }
        switch builtIn {
        case .composeText: operation = .composeText
        case .paste: operation = .paste
        case .escape: kind = .key; key = .escape
        case .tab: kind = .key; key = .tab
        case .returnKey: kind = .shortcut; character = 0xff0d; modifiers = []
        case .interrupt: kind = .shortcut; character = 0x63; modifiers = [0xffe3]
        default: return
        }
        self.builtIn = nil
    }
    func sameDefinition(as other: TerminalControlAction) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .builtIn: return operation != nil ? operation == other.operation : builtIn != nil && builtIn == other.builtIn
        case .key: return key == other.key
        case .shortcut: return character == other.character && Set(modifiers) == Set(other.modifiers)
        case .text: return id == other.id
        }
    }
    func placements(in profile: TerminalControlsProfile) -> [String] {
        var result = profile.resolvedRows.filter { profile.barItems(in: $0).contains(.saved(id)) }.map { "Keyboard Bar · " + $0.title }
        if inMenu { result.append("Floating Menu") }
        return result
    }
}

enum TerminalControlsDestination: String, CaseIterable, Identifiable, Hashable {
    case keyboard, menu
    var id: String { rawValue }
    var title: String { self == .keyboard ? "Keyboard Bar" : "Floating Menu" }
    var symbol: String { self == .keyboard ? "keyboard" : "ellipsis.circle" }
}

/// A bar placement is independent from a saved definition. Built-in keys are
/// editable without creating duplicate shortcuts in the shared library.
enum TerminalBarItem: Codable, Hashable, Identifiable {
    case control(Control), key(String), saved(UUID)
    enum Control: String, Codable, CaseIterable { case keyboard, ctrl, alt, shift, command, keypad, expand
        // Decode-only compatibility for pre-row-preset profiles. Removed on load.
        case retiredNumbers = "numbers"
        static var allCases: [Self] { [.keyboard, .ctrl, .alt, .shift, .command, .keypad, .expand] }
    }
    var id: String {
        switch self { case .control(let value): "control-" + value.rawValue; case .key(let value): "palette-" + value; case .saved(let value): "saved-" + value.uuidString }
    }
    var savedID: UUID? { if case .saved(let id) = self { id } else { nil } }
    var control: Control? { if case .control(let value) = self { value } else { nil } }
    var palette: TerminalPaletteKey? { if case .key(let id) = self { TerminalKeyCatalog.key(id) } else { nil } }
    var modifier: TerminalModifiers? {
        switch control { case .ctrl: .ctrl; case .alt: .alt; case .shift: .shift; case .command: .command; default: nil }
    }
    func title(in profile: TerminalControlsProfile) -> String {
        if let id = savedID { return profile.actions.first { $0.id == id }?.title ?? "Saved Item" }
        if let palette { return palette.name }
        switch control {
        case .keyboard: return "Keyboard"; case .ctrl: return "Ctrl"; case .alt: return "Alt"
        case .shift: return "Shift"; case .command: return "Command"; case .retiredNumbers: return "Retired Control"
        case .keypad: return "Keypad"; case .expand: return "Expand Rows"; case nil: return "Key"
        }
    }
    var symbol: String? {
        if let key = palette?.accessory {
            return switch key { case .escape: "escape"; case .tab: "arrow.right.to.line"; case .up: "arrow.up"; case .down: "arrow.down"; case .left: "arrow.left"; case .right: "arrow.right"; default: nil }
        }
        return switch control {
        case .keyboard: "keyboard"; case .ctrl: "control"; case .alt: "option"; case .shift: "shift"; case .command: "command"
        case .retiredNumbers: nil; case .keypad: "rectangle.grid.3x2"; case .expand: "rectangle.expand.vertical"; case nil: nil
        }
    }
}

enum TerminalRowPreset: String, Codable, CaseIterable, Identifiable {
    case numbers = "Numbers", essentials = "Essentials", navigation = "Navigation", functions = "Function Keys", symbols = "Symbols", shell = "Shell Shortcuts", blank = "Blank"
    var id: String { rawValue }
    var items: [TerminalBarItem] {
        if self == .blank { return [] }
        if self == .essentials { return [.control(.keyboard), .key("key-escape"), .key("key-tab"), .control(.ctrl), .control(.alt), .control(.shift), .control(.keypad), .control(.expand)] }
        let group = self == .shell ? "Common Shortcuts" : rawValue
        return (TerminalKeyCatalog.groups.first { $0.title == group }?.keys ?? []).map { .key($0.id) }
    }
}

struct TerminalKeyboardRow: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case main, numbers, navigation, custom }
    var id = UUID()
    var kind: Kind
    var title: String
    var actionIDs: [UUID] = []
    var items: [TerminalBarItem]?
    var preset: TerminalRowPreset?
    var expandedOnly: Bool?
    var hidden: Bool?
    enum Alignment: String, Codable, CaseIterable {
        case left = "Left", center = "Center", right = "Right", fill = "Fill"
        var symbol: String {
            switch self {
            case .left: "align.horizontal.left"
            case .center: "align.horizontal.center"
            case .right: "align.horizontal.right"
            case .fill: "arrow.left.and.right"
            }
        }
    }
    var alignment: Alignment?
    var resolvedAlignment: Alignment { alignment ?? (preset == .numbers || kind == .numbers ? .fill : .left) }
    enum Visibility: String, CaseIterable { case always = "Always", expanded = "When Expanded", hidden = "Hidden" }
    enum MenuAction { case visibility(Visibility), alignment(Alignment), remove }
    var visibility: Visibility {
        get { hidden == true ? .hidden : extra ? .expanded : .always }
        set { hidden = newValue == .hidden; expandedOnly = newValue == .expanded }
    }
    static let mainID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let numbersID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let navigationID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    var extra: Bool { expandedOnly ?? (kind == .navigation || kind == .custom) }
}

struct TerminalControlsProfile: Codable, Equatable {
    static let maximumKeyboardRows = 6
    var version = 1
    var revision = UUID()
    var actions: [TerminalControlAction] = []
    var importedMacs: Set<UUID> = []
    // Optional fields decode existing v1 records without rewriting their content.
    var rowOrder: [UUID]?
    var menuOrder: [UUID]?
    var numberRow: Bool? // Decode-only legacy preference; cleared by normalizeLegacyRows().
    var expandedBar: Bool? // Legacy setting; new explicit expansion uses rowsExpanded.
    var navigationRow: Bool?
    var keyboardRows: [TerminalKeyboardRow]?
    var rowsExpanded: Bool?
    var commandInBar: Bool?
    var shortcutOrder: [UUID]?
    var textOrder: [UUID]?
    var rowsSchema: Int?
    /// Old flat placements remain on the main row. New rows reference the same
    /// saved definitions, and never copy or discard their content.
    var resolvedRows: [TerminalKeyboardRow] {
        var rows = keyboardRows ?? [
            .init(id: TerminalKeyboardRow.numbersID, kind: .custom, title: "Numbers", preset: .numbers, expandedOnly: false),
            .init(id: TerminalKeyboardRow.navigationID, kind: .navigation, title: "Navigation"),
            .init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main Row")]
        let assigned = Set(rows.flatMap(\.actionIDs))
        if let main = rows.firstIndex(where: { $0.kind == .main }) {
            let missing = placed(.keyboard).map(\.id).filter { !assigned.contains($0) }
            rows[main].actionIDs += missing
            if rows[main].items != nil { rows[main].items! += missing.map { .saved($0) } }
        }
        return rows
    }
    func barItems(in row: TerminalKeyboardRow) -> [TerminalBarItem] {
        if let items = row.items { return items }
        var items: [TerminalBarItem] = switch row.kind {
        case .main: TerminalRowPreset.essentials.items
        case .numbers: TerminalRowPreset.numbers.items
        case .navigation: TerminalRowPreset.navigation.items
        case .custom: row.preset?.items ?? []
        }
        if row.kind == .main {
            if commandInBar == true { items.insert(.control(.command), at: 6) }
            if navigationRow == false { items.removeAll { $0 == .key("key-up") || $0 == .key("key-down") } }
        }
        return items + row.actionIDs.map { .saved($0) }
    }
    private mutating func editRows(_ edit: (inout [TerminalKeyboardRow]) -> Void) {
        var rows = resolvedRows
        for index in rows.indices { rows[index].items = barItems(in: rows[index]) }
        edit(&rows)
        for index in rows.indices { rows[index].actionIDs = (rows[index].items ?? []).compactMap(\.savedID) }
        let placed = Set(rows.flatMap(\.actionIDs))
        for index in actions.indices { actions[index].inRow = placed.contains(actions[index].id) }
        keyboardRows = rows
    }
    mutating func placeBarItem(_ item: TerminalBarItem, in rowID: UUID, from sourceRowID: UUID? = nil, before target: TerminalBarItem? = nil) {
        guard resolvedRows.contains(where: { $0.id == rowID }) else { return }
        editRows { rows in
            for index in rows.indices where item.control != nil || item.savedID != nil || rows[index].id == sourceRowID || rows[index].id == rowID { rows[index].items?.removeAll { $0 == item } }
            let index = rows.firstIndex { $0.id == rowID }!
            let position = target.flatMap { rows[index].items?.firstIndex(of: $0) } ?? rows[index].items!.endIndex
            rows[index].items!.insert(item, at: position)
        }
    }
    mutating func removeBarItem(_ item: TerminalBarItem, in rowID: UUID? = nil) {
        editRows { rows in for index in rows.indices where rowID == nil || rows[index].id == rowID { rows[index].items?.removeAll { $0 == item } } }
    }
    mutating func restoreRow(_ id: UUID) {
        guard let row = resolvedRows.first(where: { $0.id == id }) else { return }
        let preset = row.preset ?? (row.kind == .main ? .essentials : row.kind == .numbers ? .numbers : row.kind == .navigation ? .navigation : .blank)
        let startingItems = availableItems(for: preset, excluding: id)
        for item in barItems(in: row) { removeBarItem(item, in: id) }
        for item in startingItems { placeBarItem(item, in: id) }
    }
    mutating func restoreKeyboardBar() {
        for index in actions.indices { actions[index].inRow = false }
        rowOrder = nil; keyboardRows = nil; numberRow = nil; navigationRow = true; rowsExpanded = false; commandInBar = false
    }
    /// The focused editor transfers a complete template only after explaining
    /// existing placements. Legacy addPreset retains its non-moving semantics.
    @discardableResult mutating func installEditorPreset(_ preset: TerminalRowPreset, before target: UUID?) -> UUID? {
        var draft = self
        let primary = preset == .essentials ? resolvedRows.first { $0.kind == .main }
            : preset == .numbers ? resolvedRows.first { $0.preset == .numbers || $0.kind == .numbers } : nil
        let existing = primary.flatMap { row -> UUID? in
            let extras = barItems(in: row).filter { item in
                !preset.items.contains(item) && !(item.savedID.flatMap { id in actions.first { $0.id == id } }.map { action in preset.items.contains { $0.palette?.matches(action) == true } } ?? false)
            }
            return extras.isEmpty ? row.id : nil
        }
        guard let id = existing ?? draft.addRow(title: preset == .blank ? "Custom Row" : preset.rawValue) else { return nil }
        let originallyEmpty = Set(draft.resolvedRows.filter { draft.barItems(in: $0).isEmpty }.map(\.id))
        let transferred = Set(preset.items)
        let equivalent = Set(draft.actions.filter { action in preset.items.contains { $0.palette?.matches(action) == true } }.map(\.id))
        draft.editRows { rows in
            for index in rows.indices {
                rows[index].items?.removeAll { transferred.contains($0) || $0.savedID.map(equivalent.contains) == true }
            }
            if let index = rows.firstIndex(where: { $0.id == id }) {
                if preset != .blank { rows[index].title = preset.rawValue }
                rows[index].items = preset.items; rows[index].preset = preset; rows[index].expandedOnly = false
                rows[index].hidden = false
            }
            rows.removeAll { $0.id != id && $0.kind != .main && $0.items?.isEmpty == true && !originallyEmpty.contains($0.id) }
        }
        if target != id { draft.moveRow(id, before: target) }
        guard draft.valid else { return nil }
        self = draft; return id
    }
    @discardableResult mutating func replaceEditorItem(_ item: TerminalBarItem, in rowID: UUID, with replacement: TerminalBarItem) -> Bool {
        guard let row = resolvedRows.first(where: { $0.id == rowID }), let index = barItems(in: row).firstIndex(of: item) else { return false }
        if item == replacement { return true }
        guard !resolvedRows.contains(where: { barItems(in: $0).contains(replacement) }) else { return false }
        let values = barItems(in: row)
        var draft = self
        draft.removeBarItem(item, in: rowID)
        draft.placeBarItem(replacement, in: rowID, before: index + 1 < values.count ? values[index + 1] : nil)
        guard draft.valid else { return false }
        self = draft; return true
    }
    @discardableResult mutating func replaceEditorFavorite(_ id: UUID, with key: TerminalPaletteKey) -> Bool {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return false }
        var replacement = key.definition
        replacement.id = id; replacement.inRow = actions[index].inRow; replacement.inMenu = actions[index].inMenu
        replacement.presetID = actions[index].presetID
        guard replacement.valid else { return false }
        actions[index] = replacement
        return true
    }
    mutating func removeEditorRow(_ id: UUID) {
        guard let row = resolvedRows.first(where: { $0.id == id }) else { return }
        if resolvedRows.count == 1 {
            for item in barItems(in: row) { removeBarItem(item, in: id) }
        } else {
            editRows { rows in
                rows.removeAll { $0.id == id }
                if row.kind == .main, let index = rows.firstIndex(where: { $0.kind == .custom }) ?? rows.indices.last {
                    rows[index].kind = .main; rows[index].expandedOnly = false; rows[index].hidden = false
                }
            }
        }
    }
    mutating func restoreMenuFavorites() {
        for index in actions.indices { actions[index].inMenu = false }
        for action in Self.defaults.actions {
            if let existing = actions.firstIndex(where: { $0.sameDefinition(as: action) }) { actions[existing].inMenu = true }
            else { actions.append(action) }
        }
        menuOrder = nil
    }
    /// The row library shows these exact additions. Existing placements, including
    /// deliberately duplicated legacy keys, are never stolen by a preset.
    func availableItems(for preset: TerminalRowPreset, excluding rowID: UUID? = nil) -> [TerminalBarItem] {
        let used = Set(resolvedRows.filter { $0.id != rowID }.flatMap { barItems(in: $0) })
        let savedIDs = Set(used.compactMap(\.savedID))
        let saved = actions.filter { savedIDs.contains($0.id) }
        return preset.items.filter { item in
            !used.contains(item) && !(item.palette.map { palette in saved.contains(where: palette.matches) } ?? false)
        }
    }
    @discardableResult mutating func addPreset(_ preset: TerminalRowPreset, before target: UUID? = TerminalKeyboardRow.mainID) -> UUID? {
        let additions = availableItems(for: preset)
        guard preset == .blank || !additions.isEmpty else { return nil }
        guard let id = addRow(title: preset == .blank ? "Custom Row" : preset.rawValue) else { return nil }
        editRows { rows in
            let index = rows.firstIndex { $0.id == id }!
            rows[index].preset = preset
            rows[index].expandedOnly = false
        }
        for item in additions { placeBarItem(item, in: id) }
        moveRow(id, before: target)
        return id
    }
    func placed(in row: TerminalKeyboardRow) -> [TerminalControlAction] {
        row.actionIDs.compactMap { id in actions.first { $0.id == id && $0.inRow } }
    }
    mutating func place(_ id: UUID, in rowID: UUID) {
        guard actions.contains(where: { $0.id == id }) else { return }
        placeBarItem(.saved(id), in: rowID)
    }
    mutating func moveRow(_ id: UUID, offset: Int) {
        var rows = resolvedRows
        guard let index = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(index + offset) else { return }
        rows.swapAt(index, index + offset); keyboardRows = rows
    }
    mutating func moveRow(_ id: UUID, before target: UUID?) {
        var rows = resolvedRows
        guard id != target, let source = rows.firstIndex(where: { $0.id == id }),
              target == nil || rows.contains(where: { $0.id == target }) else { return }
        let row = rows.remove(at: source)
        rows.insert(row, at: target.flatMap { id in rows.firstIndex { $0.id == id } } ?? rows.endIndex)
        keyboardRows = rows
    }
    mutating func removeRow(_ id: UUID) {
        let rows = resolvedRows
        guard rows.contains(where: { $0.id == id && $0.kind != .main }) else { return }
        editRows { $0.removeAll { $0.id == id } }
    }
    @discardableResult mutating func addRow(title: String = "Custom Row", navigation: Bool = false) -> UUID? {
        var rows = resolvedRows
        guard rows.count < Self.maximumKeyboardRows, !navigation || !rows.contains(where: { $0.kind == .navigation }) else { return nil }
        var resolvedTitle = title
        if title == "Custom Row" {
            var number = 1
            while rows.contains(where: { $0.title == "Custom Row \(number)" }) { number += 1 }
            resolvedTitle = "Custom Row \(number)"
        }
        let row = TerminalKeyboardRow(kind: navigation ? .navigation : .custom, title: resolvedTitle)
        rows.insert(row, at: rows.firstIndex(where: { $0.kind == .main }) ?? rows.endIndex)
        keyboardRows = rows; rowsExpanded = true; return row.id
    }
    func placed(_ destination: TerminalControlsDestination) -> [TerminalControlAction] {
        let items = actions.filter { destination == .keyboard ? $0.inRow : $0.inMenu }
        let order = destination == .keyboard ? rowOrder : menuOrder
        let ranks = Dictionary(uniqueKeysWithValues: (order ?? []).enumerated().map { ($1, $0) })
        return items.enumerated().sorted {
            (ranks[$0.element.id] ?? (actions.count + $0.offset)) < (ranks[$1.element.id] ?? (actions.count + $1.offset))
        }.map(\.element)
    }
    mutating func move(_ id: UUID, to target: UUID, in destination: TerminalControlsDestination) {
        if destination == .keyboard, let rows = keyboardRows,
           let row = rows.first(where: { $0.items != nil && $0.actionIDs.contains(id) && $0.actionIDs.contains(target) }) {
            placeBarItem(.saved(id), in: row.id, before: .saved(target)); return
        }
        if destination == .keyboard, var rows = keyboardRows,
           let row = rows.firstIndex(where: { $0.actionIDs.contains(id) && $0.actionIDs.contains(target) }),
           let from = rows[row].actionIDs.firstIndex(of: id), let to = rows[row].actionIDs.firstIndex(of: target), from != to {
            rows[row].actionIDs.insert(rows[row].actionIDs.remove(at: from), at: to); keyboardRows = rows; return
        }
        var order = placed(destination).map(\.id)
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: target), from != to else { return }
        order.insert(order.remove(at: from), at: to)
        if destination == .keyboard { rowOrder = order } else { menuOrder = order }
    }
    mutating func delete(_ id: UUID) {
        actions.removeAll { $0.id == id }; rowOrder?.removeAll { $0 == id }; menuOrder?.removeAll { $0 == id }; shortcutOrder?.removeAll { $0 == id }; textOrder?.removeAll { $0 == id }
        if keyboardRows != nil { for index in keyboardRows!.indices { keyboardRows![index].actionIDs.removeAll { $0 == id }; keyboardRows![index].items?.removeAll { $0.savedID == id } } }
    }
    mutating func pin(_ id: UUID, in destination: TerminalControlsDestination, enabled: Bool) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        if destination == .keyboard { actions[index].inRow = enabled } else { actions[index].inMenu = enabled }
        if destination == .keyboard, !enabled, keyboardRows != nil {
            for row in keyboardRows!.indices { keyboardRows![row].actionIDs.removeAll { $0 == id }; keyboardRows![row].items?.removeAll { $0.savedID == id } }
        }
    }
    var valid: Bool {
        version == 1 && actions.count <= 4096 && importedMacs.count <= 4096
            && Set(actions.map(\.id)).count == actions.count && actions.allSatisfy(\.valid)
            && [rowOrder, menuOrder, shortcutOrder, textOrder].allSatisfy { order in
                guard let order else { return true }
                return order.count <= 4096 && Set(order).count == order.count && Set(order).isSubset(of: Set(actions.map(\.id)))
            }
            && validRows
    }
    private var validRows: Bool {
        guard let rows = keyboardRows else { return true }
        let ids = rows.flatMap(\.actionIDs)
        return (1...Self.maximumKeyboardRows).contains(rows.count) && Set(rows.map(\.id)).count == rows.count
            && rows.filter { $0.kind == .main }.count == 1 && rows.filter { $0.kind == .numbers }.count <= 1
            && rows.filter { $0.kind == .navigation }.count <= 1
            && rows.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 40 && ($0.kind != .numbers || $0.items != nil || $0.actionIDs.isEmpty) }
            && ids.count <= 4096 && Set(ids).count == ids.count && Set(ids).isSubset(of: Set(actions.map(\.id)))
            && validBarItems(rows)
    }
    private func validBarItems(_ rows: [TerminalKeyboardRow]) -> Bool {
        let items = rows.flatMap { $0.items ?? [] }
        let singular = items.filter { $0.control != nil || $0.savedID != nil }
        return items.count <= 4096 && Set(singular).count == singular.count && rows.allSatisfy { row in
            guard row.items == nil || Set(row.items!).count == row.items!.count else { return false }
            return row.items == nil || row.actionIDs == row.items!.compactMap(\.savedID)
        } && items.allSatisfy { item in
            switch item {
            case .control: true
            case .key(let id): TerminalKeyCatalog.key(id) != nil
            case .saved(let id): actions.contains { $0.id == id && $0.inRow }
            }
        }
    }
    func savedItems(_ section: TerminalSavedItemsSection) -> [TerminalControlAction] {
        let items = actions.filter { $0.kind == section.kind }
        let order = section == .shortcuts ? shortcutOrder : textOrder
        let ranks = Dictionary(uniqueKeysWithValues: (order ?? []).enumerated().map { ($1, $0) })
        return items.enumerated().sorted {
            (ranks[$0.element.id] ?? (actions.count + $0.offset)) < (ranks[$1.element.id] ?? (actions.count + $1.offset))
        }.map(\.element)
    }
    mutating func reorderLibrary(_ section: TerminalSavedItemsSection, ids: [UUID]) {
        if section == .shortcuts { shortcutOrder = ids } else { textOrder = ids }
    }
    /// Convert only retired Numbers behavior; leave all other placements alone.
    mutating func normalizeLegacyRows(legacyNumbersVisible: Bool = true) {
        guard rowsSchema != 2 else { return }
        var rows = resolvedRows
        for index in rows.indices {
            var items = barItems(in: rows[index])
            items.removeAll { $0.control == .retiredNumbers }
            rows[index].items = items
            rows[index].actionIDs = items.compactMap(\.savedID)
            if rows[index].kind == .numbers || rows[index].id == TerminalKeyboardRow.numbersID {
                rows[index].kind = .custom; rows[index].preset = .numbers
                rows[index].expandedOnly = false
                rows[index].hidden = !(numberRow ?? legacyNumbersVisible)
            }
        }
        keyboardRows = rows; numberRow = nil; rowsSchema = 2
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
        } else {
            let actions = try legacyActions()
            guard DirectQuickActionEditing.valid(actions, mode: .terminal) else { throw Failure.unreadable }
            profile = .init(actions: actions.map(TerminalControlAction.init))
        }
        // Resolution builds ordering dictionaries. Reject malformed storage
        // before migration can resolve rows; never rewrite a corrupt record.
        guard profile.valid else { throw Failure.unreadable }
        let before = profile
        let legacyPreference = "direct-terminal-number-row"
        let legacyVisible = UserDefaults.standard.object(forKey: legacyPreference) == nil || UserDefaults.standard.bool(forKey: legacyPreference)
        profile.normalizeLegacyRows(legacyNumbersVisible: legacyVisible)
        for index in profile.actions.indices { profile.actions[index].normalizeLegacyDefinition() }
        guard profile.valid else { throw Failure.unreadable }
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
