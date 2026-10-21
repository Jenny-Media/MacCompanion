#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
#if os(iOS)
import UIKit
#endif
import SwiftTerm

struct TerminalModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let shift = Self(rawValue: 1)
    static let alt = Self(rawValue: 2)
    static let ctrl = Self(rawValue: 4)
    static let command = Self(rawValue: 8)
    var title: String { self == .ctrl ? "Ctrl" : self == .alt ? "Alt" : self == .command ? "Cmd" : "Shift" }
}
struct TerminalKeyboardState {
    var armed: TerminalModifiers = []
    var locked: TerminalModifiers = []
    var active: TerminalModifiers { armed.union(locked) }
    mutating func toggle(_ value: TerminalModifiers, lock: Bool = false) {
        if lock { if locked.contains(value) { locked.remove(value) } else { locked.insert(value); armed.remove(value) } }
        else if locked.contains(value) { locked.remove(value); armed.remove(value) }
        else if armed.contains(value) { armed.remove(value) } else { armed.insert(value) }
    }
    mutating func consume() -> TerminalModifiers { let value = active; armed = []; return value }
    mutating func reset() { armed = []; locked = [] }
    static func shifted(_ value: String) -> String {
        let plain = Array("1234567890-=[];',./`\\")
        let symbols = Array("!@#$%^&*()_+{}:\"<>?~|")
        let mapping = Dictionary(uniqueKeysWithValues: zip(plain, symbols))
        return value.map { mapping[$0].map(String.init) ?? String($0).uppercased() }.joined()
    }
    static func backspace(modifiers: TerminalModifiers, controlH: Bool = false, enhanced: Bool = false) -> [UInt8] {
        if enhanced { return Array("\u{1b}[127;\(modifiers.rawValue + 1)u".utf8) }
        return (modifiers.contains(.alt) ? [0x1b] : []) + [controlH || modifiers.contains(.ctrl) ? 0x08 : 0x7f]
    }
    static func text(_ value: String, modifiers: TerminalModifiers) -> [UInt8] {
        let text = modifiers.contains(.shift) ? shifted(value) : value
        var result = [UInt8]()
        if modifiers.contains(.alt) { result.append(0x1b) }
        for scalar in text.unicodeScalars {
            if modifiers.contains(.ctrl) {
                let ascii = scalar.value
                if (0x40...0x5f).contains(ascii) || (0x61...0x7a).contains(ascii) { result.append(UInt8(ascii & 0x1f)); continue }
                if ascii == 0x20 || ascii == 0x32 { result.append(0); continue }
                if ascii == 0x3f || ascii == 0x38 { result.append(0x7f); continue }
                if ascii == 0x2f { result.append(0x1f); continue }
                if ascii == 0x7e { result.append(0x1e); continue }
                if (0x33...0x37).contains(ascii) { result.append(UInt8(ascii - 0x33 + 0x1b)); continue }
            }
            result.append(contentsOf: String(scalar).utf8)
        }
        return result
    }
}

/// Explicit key actions, distinct from literal paste and native IME commits.
/// SwiftTerm's encoder is internal; use its public negotiated state without
/// changing the pinned frontend or fabricating physical keyboard metadata.
enum TerminalKeyInput {
    case text(String), accessory(TerminalAccessoryKey), enter, backspace
}

struct TerminalKeyEncoding {
    var flags: KittyKeyboardFlags = []
    var applicationCursor = false
    var backspaceSendsControlH = false
    var supportsCommand: Bool { flags.contains(.disambiguate) || flags.contains(.reportAllKeys) }

    func bytes(_ key: TerminalKeyInput, modifiers: TerminalModifiers = []) -> [UInt8] {
        guard !modifiers.contains(.command) || supportsCommand else { return [] }
        let all = flags.contains(.reportAllKeys)
        let disambiguate = all || flags.contains(.disambiguate)
        let events = flags.contains(.reportEvents)
        let parameter = modifiers.rawValue + 1
        func csi(_ code: String, suffix: String = "u", release: Bool = false, text: String? = nil) -> [UInt8] {
            var value = code
            if !modifiers.isEmpty || release { value += ";\(parameter)" + (release ? ":3" : "") }
            if let text, all, flags.contains(.reportText), !release,
               modifiers.intersection([.ctrl, .alt, .command]).isEmpty {
                value += modifiers.isEmpty ? ";;" : ";"
                value += text.unicodeScalars.map { String($0.value) }.joined(separator: ":")
            }
            return Array(("\u{1b}[" + value + suffix).utf8)
        }
        func unicode(_ code: String, legacy: [UInt8], releaseAllowed: Bool = true, text: String? = nil) -> [UInt8] {
            let encoded = disambiguate && (all || releaseAllowed || !modifiers.isEmpty)
            let press = encoded ? csi(code, text: text) : legacy
            return press + (events && releaseAllowed && disambiguate ? csi(code, release: true) : [])
        }
        switch key {
        case .text(let value):
            // Saved uppercase characters need an unshifted identity and Shift
            // under report-all, with their uppercase associated text retained.
            // Keep explicit Ctrl chords and the existing Alt inference intact.
            let lower = value.lowercased()
            let uppercaseSavedKey = all && modifiers.isEmpty && value == lower.uppercased()
            if !modifiers.intersection([.alt, .command]).isEmpty || uppercaseSavedKey,
               !modifiers.contains(.shift), value.unicodeScalars.count == 1,
               lower.unicodeScalars.count == 1, lower != value {
                return bytes(.text(lower), modifiers: modifiers.union(.shift))
            }
            if flags.isEmpty { return TerminalKeyboardState.text(value, modifiers: modifiers) }
            let legacy = !all && (!disambiguate || modifiers.intersection([.ctrl, .alt, .command]).isEmpty) &&
                (flags.isEmpty || !modifiers.contains([.ctrl, .shift]))
            return value.unicodeScalars.flatMap { scalar -> [UInt8] in
                let original = String(scalar)
                let base = modifiers.intersection([.ctrl, .shift, .command]).isEmpty ? scalar : (original.lowercased().unicodeScalars.first ?? scalar)
                var code = String(base.value)
                let text = modifiers.contains(.shift) ? TerminalKeyboardState.shifted(original) : original
                if flags.contains(.reportAlternates), modifiers.contains(.shift), text.unicodeScalars.count == 1, let shifted = text.unicodeScalars.first {
                    code += ":\(shifted.value)"
                }
                let press = legacy ? TerminalKeyboardState.text(original, modifiers: modifiers) : csi(code, text: text)
                let release = events && (!legacy || !modifiers.intersection([.ctrl, .alt, .command]).isEmpty) ? csi(code, release: true) : []
                return press + release
            }
        case .enter:
            return unicode("13", legacy: TerminalKeyboardState.text("\r", modifiers: modifiers), releaseAllowed: all || modifiers.contains(.command))
        case .backspace:
            return unicode("127", legacy: TerminalKeyboardState.backspace(modifiers: modifiers, controlH: backspaceSendsControlH), releaseAllowed: all || modifiers.contains(.command))
        case .accessory(let key):
            if flags.isEmpty {
                if key == .tab && modifiers.contains(.shift) {
                    return (modifiers.contains(.alt) ? [0x1b] : []) + Array("\u{1b}[Z".utf8)
                }
                return key.bytes(modifiers: modifiers, applicationCursor: applicationCursor)
            }
            if key == .escape { return unicode("27", legacy: key.bytes(modifiers: modifiers)) }
            if key == .tab {
                let legacy = modifiers.contains(.shift) ? (modifiers.contains(.alt) ? [UInt8(0x1b)] : []) + Array("\u{1b}[Z".utf8) : key.bytes(modifiers: modifiers)
                return unicode("9", legacy: legacy, releaseAllowed: all || modifiers.contains(.command))
            }
            let letter: String? = switch key {
            case .up: "A"; case .down: "B"; case .right: "C"; case .left: "D"; case .home: "H"; case .end: "F"
            case .f1: "P"; case .f2: "Q"; case .f4: "S"; default: nil
            }
            if let letter {
                let press = modifiers.isEmpty ? (disambiguate ? Array(("\u{1b}[" + letter).utf8) : key.bytes(applicationCursor: applicationCursor)) : csi("1", suffix: letter)
                return press + (events ? csi("1", suffix: letter, release: true) : [])
            }
            let code: Int = switch key {
            case .insert: 2; case .delete: 3; case .pageUp: 5; case .pageDown: 6; case .f3: 13; case .f5: 15; case .f6: 17
            case .f7: 18; case .f8: 19; case .f9: 20; case .f10: 21; case .f11: 23; case .f12: 24; default: 0
            }
            return csi(String(code), suffix: "~") + (events ? csi(String(code), suffix: "~", release: true) : [])
        }
    }
}

extension VNCQuickAction {
    func terminalBytes(applicationCursor: Bool = false) -> [UInt8] {
        terminalBytes(encoding: .init(applicationCursor: applicationCursor))
    }
    func terminalBytes(encoding: TerminalKeyEncoding) -> [UInt8] {
        guard kind == .shortcut, valid, compatible(with: .terminal) else { return [] }
        var flags: TerminalModifiers = []
        if modifiers.contains(0xffe1) { flags.insert(.shift) }
        if modifiers.contains(0xffe3) { flags.insert(.ctrl) }
        if modifiers.contains(0xffe9) { flags.insert(.alt) }
        if modifiers.contains(0xffeb) { flags.insert(.command) }
        let special: [UInt32: TerminalAccessoryKey] = [0xff1b: .escape, 0xff09: .tab, 0xffff: .delete, 0xff51: .left, 0xff52: .up, 0xff53: .right, 0xff54: .down]
        if key == 0xff08 { return encoding.bytes(.backspace, modifiers: flags) }
        if let special = special[key] { return encoding.bytes(.accessory(special), modifiers: flags) }
        if key == 0xff0d { return encoding.bytes(.enter, modifiers: flags) }
        guard let scalar = UnicodeScalar(key) else { return [] }
        return encoding.bytes(.text(String(scalar)), modifiers: flags)
    }
}

enum TerminalAccessoryKey: String, Codable, CaseIterable, Identifiable {
    case escape, tab, up, down, left, right, home, end, pageUp, pageDown, insert, delete, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    var id: String { rawValue }
    var title: String {
        switch self {
        case .escape: "Esc"; case .tab: "Tab"; case .up: "↑"; case .down: "↓"; case .left: "←"; case .right: "→"
        case .home: "Home"; case .end: "End"; case .pageUp: "PgUp"; case .pageDown: "PgDn"; case .insert: "Ins"; case .delete: "Del"
        default: rawValue.uppercased()
        }
    }
    func bytes(modifiers: TerminalModifiers = [], applicationCursor: Bool = false) -> [UInt8] {
        let parameter = modifiers.rawValue + 1
        let arrow: String? = switch self { case .up: "A"; case .down: "B"; case .right: "C"; case .left: "D"; case .home: "H"; case .end: "F"; default: nil }
        if let arrow { return Array((modifiers.isEmpty ? "\u{1b}" + (applicationCursor ? "O" : "[") + arrow : "\u{1b}[1;\(parameter)" + arrow).utf8) }
        switch self {
        case .escape: return TerminalKeyboardState.text("\u{1b}", modifiers: modifiers)
        case .tab: return modifiers.contains(.shift) ? Array("\u{1b}[Z".utf8) : TerminalKeyboardState.text("\t", modifiers: modifiers)
        default:
            let code: Int = switch self { case .insert: 2; case .pageUp: 5; case .pageDown: 6; case .delete: 3; case .f5: 15; case .f6: 17; case .f7: 18; case .f8: 19; case .f9: 20; case .f10: 21; case .f11: 23; case .f12: 24; default: 0 }
            if code > 0 { return Array(("\u{1b}[\(code)" + (modifiers.isEmpty ? "" : ";\(parameter)") + "~").utf8) }
            let suffix: String = switch self { case .f1: "P"; case .f2: "Q"; case .f3: "R"; case .f4: "S"; default: "" }
            return Array((modifiers.isEmpty ? "\u{1b}O" + suffix : "\u{1b}[1;\(parameter)" + suffix).utf8)
        }
    }
}

struct TerminalSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
    var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40 && !text.isEmpty && text.utf8.count <= 4096 && !text.contains("\0") && !text.contains("\u{1b}") }
}
struct TerminalKeyboardPreferences: Codable {
    var keys: [TerminalAccessoryKey] = []
    var snippets: [TerminalSnippet] = []
    @MainActor static func load(_ macID: UUID) throws -> Self {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        guard let data = try TerminalSecretStore.read(macID, kind: "terminal-keyboard-v1") else { return .init() }
        guard data.count <= 147456 else { throw TerminalSecretStore.Failure.storage }
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
    func validate() throws {
        guard keys.count <= 8, Set(keys).count == keys.count, snippets.count <= 32,
              Set(snippets.map(\.id)).count == snippets.count, snippets.allSatisfy(\.valid) else { throw TerminalSecretStore.Failure.storage }
    }
    @MainActor func save(_ macID: UUID) throws {
        _ = try Self.load(macID); try validate()
        try TerminalSecretStore.write(JSONEncoder().encode(self), id: macID, kind: "terminal-keyboard-v1")
    }
}

#if os(iOS)
private final class TerminalKeyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}

@MainActor final class TerminalKeyboardBar: UIView, UIDragInteractionDelegate, UIDropInteractionDelegate {
    weak var terminal: SessionTerminalView?
    lazy var keyFeedback = CompanionVNCInterfaceFeedback(view: self)
    private let rows = UIStackView()
    private let row = UIStackView()
    private let keys = UIStackView()
    private let numbers = UIStackView()
    private let numberScroll: UIScrollView = TerminalKeyScrollView()
    private var extraViews: [UIView] = []
    private var generated: [UIButton] = []
    private var numeric: [UIButton] = []
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    private var commandShortcuts: [UIButton] = []
    private var keyWidths: [ObjectIdentifier: NSLayoutConstraint] = [:]
    private var keySymbols: [ObjectIdentifier: String] = [:]
    private var heights: [NSLayoutConstraint] = []
    private var keyHeight: CGFloat = 52
    private var keyboardFocused: Bool?
    let keyboardButton = UIButton(type: .system)
    let numberButton = UIButton(type: .system)
    let keypadButton = UIButton(type: .system)
    let expandButton = UIButton(type: .system)
    let menuAnchor = UIView()
    let keyScroll: UIScrollView = TerminalKeyScrollView()
    var editingPreview = false
    var selectedPreviewItem: TerminalBarItem?
    var selectedPreviewRow: UUID?
    var previewSelect: ((TerminalBarItem?, UUID) -> Void)?
    var previewMove: ((TerminalBarItem, UUID, UUID, TerminalBarItem?) -> Void)?
    var previewRemove: ((TerminalBarItem, UUID) -> Void)?
    private struct DragPlacement { let item: TerminalBarItem; let row: UUID }
    private var previewItems: [ObjectIdentifier: TerminalBarItem] = [:]
    private var previewRows: [ObjectIdentifier: UUID] = [:]
    private var profileRows: [TerminalKeyboardRow] = []
    private var layoutGeneration = UUID()
    var layoutChanged: (() -> Void)?
    var toggleKeyboard: (() -> Void)?
    var openKeypad: ((Bool) -> Void)?
    var showsNavigation = true
    var showsExtraRows = false { didSet { updateVisibility() } }
    var showsNumberRow = true { didSet { updateVisibility() } }
    var height: CGFloat {
        let count = max(1, rows.arrangedSubviews.filter { !$0.isHidden }.count)
        return 8 + CGFloat(count) * keyHeight + CGFloat(count - 1) * 3
    }

    init(terminal: SessionTerminalView?, preferences: TerminalKeyboardPreferences) {
        self.terminal = terminal
        super.init(frame: .zero)
        accessibilityIdentifier = "terminal-keyboard-bar"
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.spacing = 3; rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 4), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
        row.axis = .horizontal; row.spacing = 4
        for item in [keyScroll, menuAnchor] { row.addArrangedSubview(item) }
        menuAnchor.isUserInteractionEnabled = false
        menuAnchor.widthAnchor.constraint(equalToConstant: 52).isActive = true
        configureButton(keyboardButton, title: "Show Keyboard", symbol: "keyboard")
        keyboardButton.accessibilityIdentifier = "terminal-keyboard-toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in
            guard let self, let terminal = self.terminal else { return }
            let before = terminal.isFirstResponder; toggleKeyboard?()
            if before != terminal.isFirstResponder { keyFeedback.feedback("selection") }
        }, for: .touchUpInside)
        configureButton(expandButton, title: "Expand Rows", symbol: "rectangle.expand.vertical")
        expandButton.accessibilityIdentifier = "terminal-row-expand"
        expandButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }; showsExtraRows.toggle(); keyFeedback.feedback("selection"); layoutChanged?()
        }, for: .touchUpInside)
        configureButton(numberButton, title: "Hide Numbers", symbol: "textformat.123")
        numberButton.accessibilityIdentifier = "terminal-number-toggle"
        numberButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }; showsNumberRow.toggle(); keyFeedback.feedback("selection"); layoutChanged?()
        }, for: .touchUpInside)
        configureButton(keypadButton, title: "Open Keypad", symbol: "rectangle.grid.3x2")
        keypadButton.accessibilityIdentifier = "terminal-keypad-toggle"
        keypadButton.addAction(UIAction { [weak self] _ in self?.openKeypad?(false) }, for: .touchUpInside)
        keys.axis = .horizontal; keys.spacing = 3
        install(keys, in: keyScroll)
        keyScroll.accessibilityIdentifier = "terminal-modifier-keys"; keyScroll.accessibilityLabel = "Terminal keys"
        numbers.axis = .horizontal; numbers.spacing = 3; numbers.distribution = .fillEqually
        numbers.accessibilityIdentifier = "terminal-number-row"
        install(numbers, in: numberScroll, fitting: true)
        numberScroll.accessibilityIdentifier = "terminal-number-scroll"
        for value in ["1","2","3","4","5","6","7","8","9","0"] {
            let key = UIButton(type: .system); configureButton(key, title: value, number: true)
            key.addAction(UIAction { [weak self] _ in self?.sendNumber(value) }, for: .touchUpInside)
            numeric.append(key); numbers.addArrangedSubview(key)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: TerminalKeyboardBar, _: UITraitCollection) in bar.updateKeyMetrics() }
        configure(preferences)
    }
    private func install(_ stack: UIStackView, in scroll: UIScrollView, fitting: Bool = false) {
        scroll.showsHorizontalScrollIndicator = true; scroll.alwaysBounceHorizontal = true
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        if fitting {
            let width = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor); width.priority = .defaultHigh; width.isActive = true
        }
    }
    func configure(_ preferences: TerminalKeyboardPreferences) {
        var profile = TerminalControlsProfile.defaults
        profile.actions += preferences.keys.map { .init(title: $0.title, kind: .key, key: $0, inRow: true, inMenu: false) }
        configure(profile) { _ in }
    }
    func configure(_ profile: TerminalControlsProfile, perform: @escaping (UUID) -> Void) {
        layoutGeneration = UUID()
        for key in generated { keyWidths.removeValue(forKey: ObjectIdentifier(key)); keySymbols.removeValue(forKey: ObjectIdentifier(key)) }
        generated = []; numeric = []; modifierButtons = []; commandShortcuts = []
        previewItems = [:]; previewRows = [:]; profileRows = profile.resolvedRows
        for stack in [keys, numbers] { for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() } }
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        heights.forEach { $0.isActive = false }; heights = []; extraViews = []
        for definition in profileRows {
            let stack: UIStackView, scroll: UIScrollView, container: UIView
            if definition.kind == .main { stack = keys; scroll = keyScroll; container = row }
            else if definition.kind == .numbers { stack = numbers; scroll = numberScroll; container = scroll }
            else {
                scroll = TerminalKeyScrollView(); stack = UIStackView()
                stack.axis = .horizontal; stack.spacing = 3; install(stack, in: scroll)
                scroll.accessibilityIdentifier = "terminal-extra-row-" + definition.id.uuidString
                if definition.kind == .navigation { stack.accessibilityIdentifier = "terminal-navigation-row" }
                container = scroll
            }
            if definition.extra { extraViews.append(container) }
            if editingPreview {
                scroll.accessibilityIdentifier = definition.kind == .main ? "terminal-row-preview-scroll" : "terminal-row-preview-scroll-" + definition.id.uuidString
                previewRows[ObjectIdentifier(scroll)] = definition.id
                if scroll.interactions.allSatisfy({ !($0 is UIDropInteraction) }) { scroll.addInteraction(UIDropInteraction(delegate: self)) }
                scroll.layer.borderWidth = selectedPreviewRow == definition.id ? 1 : 0
                scroll.layer.borderColor = UIColor.tintColor.cgColor; scroll.layer.cornerRadius = 8
            }
            for item in profile.barItems(in: definition) {
                if item.savedID != nil, !editingPreview && !DirectProAccess.shared.hasPro { continue }
                let title = item.title(in: profile)
                let key: UIButton
                if !editingPreview, let control = item.control {
                    switch control {
                    case .keyboard: key = keyboardButton
                    case .numbers: key = numberButton
                    case .keypad: key = keypadButton
                    case .expand: key = expandButton
                    default: key = button(title, symbol: item.symbol) { [weak self] in if let modifier = item.modifier { self?.toggle(modifier) } }
                    }
                } else {
                    key = button(item.palette?.title ?? title, symbol: item.symbol, number: (48...57).contains(item.palette?.character ?? 0)) { [weak self] in
                        guard let self else { return }
                        if editingPreview { previewSelect?(item, definition.id) }
                        else if let id = item.savedID { guard terminal?.customInputEpoch() != nil, DirectProAccess.shared.hasPro else { return }; perform(id) }
                        else if let palette = item.palette { send(palette) }
                    }
                }
                if let modifier = item.modifier {
                    modifierButtons.append((key, modifier))
                    if !editingPreview {
                        key.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))))
                        key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Keep " + title + " On", actionHandler: { [weak self] _ in self?.toggle(modifier, lock: true); return true })]
                    }
                }
                if case .key(let id) = item, id.hasPrefix("character-"), let value = item.palette?.character, (48...57).contains(value) { numeric.append(key) }
                if let id = item.savedID {
                    key.accessibilityIdentifier = (editingPreview ? "terminal-row-preview-" : "terminal-row-action-") + id.uuidString
                    if profile.actions.first(where: { $0.id == id })?.requiresCommand == true { commandShortcuts.append(key) }
                }
                if editingPreview {
                    if item.savedID == nil { key.accessibilityIdentifier = "terminal-preview-item-" + item.id }
                    key.accessibilityValue = selectedPreviewItem == item && selectedPreviewRow == definition.id ? "Selected" : nil
                    key.configuration?.baseBackgroundColor = selectedPreviewItem == item && selectedPreviewRow == definition.id ? .systemBlue : .secondarySystemFill
                    if selectedPreviewItem == item && selectedPreviewRow == definition.id { key.configuration?.baseForegroundColor = .white }
                    previewItems[ObjectIdentifier(key)] = item; previewRows[ObjectIdentifier(key)] = definition.id
                    key.addInteraction(UIDragInteraction(delegate: self)); key.addInteraction(UIDropInteraction(delegate: self))
                    key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Remove from Keyboard Bar", actionHandler: { [weak self] _ in self?.previewRemove?(item, definition.id); return true })] + profileRows.map { target in
                        UIAccessibilityCustomAction(name: "Move to " + target.title, actionHandler: { [weak self] _ in self?.previewMove?(item, definition.id, target.id, nil); return true })
                    }
                }
                stack.addArrangedSubview(key)
            }
            if stack.arrangedSubviews.isEmpty && editingPreview {
                let label = UILabel(); label.text = editingPreview ? "Empty row · add keys below" : definition.title
                label.font = .preferredFont(forTextStyle: .caption1); stack.addArrangedSubview(label)
            }
            rows.addArrangedSubview(container)
            let constraint = container.heightAnchor.constraint(equalToConstant: keyHeight); constraint.priority = UILayoutPriority(999); constraint.isActive = true; heights.append(constraint)
        }
        showsNumberRow = profile.numberRow ?? true; showsExtraRows = profile.rowsExpanded ?? false
        updateVisibility(); updateKeyMetrics(); refresh()
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard editingPreview, let view = interaction.view, let item = previewItems[ObjectIdentifier(view)] else { return [] }
        let drag = UIDragItem(itemProvider: NSItemProvider(object: item.id as NSString)); drag.localObject = DragPlacement(item: item, row: previewRows[ObjectIdentifier(view)]!); return [drag]
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        editingPreview && session.items.first?.localObject is DragPlacement
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .move) }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard editingPreview, let source = session.items.first?.localObject as? DragPlacement, let view = interaction.view,
              let row = previewRows[ObjectIdentifier(view)] else { return }
        let target = previewItems[ObjectIdentifier(view)]
        if source.item != target || source.row != row { previewMove?(source.item, source.row, row, target) }
    }
    private func send(_ key: TerminalPaletteKey) {
        guard let terminal else { return }
        terminal.performCustomInput {
            var modifiers = terminal.keyboardState.consume()
            for value in key.modifiers {
                if value == 0xffe3 { modifiers.insert(.ctrl) }; if value == 0xffe9 { modifiers.insert(.alt) }; if value == 0xffe1 { modifiers.insert(.shift) }
            }
            let input: TerminalKeyInput
            if let accessory = key.accessory { input = .accessory(accessory) }
            else if key.character == 0xff08 { input = .backspace }
            else if key.character == 0xff0d { input = .enter }
            else if key.character == 0xff09 { input = .accessory(.tab) }
            else if let scalar = UnicodeScalar(key.character) { input = .text(String(scalar)) }
            else { return }
            terminal.sendKey(input, modifiers: modifiers)
        }; refresh()
    }
    func setKeyboardFocused(_ focused: Bool) {
        guard keyboardFocused != focused else { return }; keyboardFocused = focused
        keyboardButton.accessibilityLabel = focused ? "Hide Keyboard" : "Show Keyboard"
        keySymbols[ObjectIdentifier(keyboardButton)] = focused ? "keyboard.chevron.compact.down" : "keyboard"
        updateKeyMetrics()
    }
    private func updateVisibility() {
        numberScroll.isHidden = !showsNumberRow
        extraViews.forEach { $0.isHidden = !showsExtraRows }
        numberButton.accessibilityLabel = showsNumberRow ? "Hide Numbers" : "Show Numbers"
        numberButton.accessibilityValue = showsNumberRow ? "On" : "Off"; numberButton.isSelected = showsNumberRow
        expandButton.accessibilityLabel = showsExtraRows ? "Collapse Rows" : "Expand Rows"
        expandButton.accessibilityValue = showsExtraRows ? "Expanded" : "Collapsed"
        expandButton.isHidden = extraViews.isEmpty
        if editingPreview { menuAnchor.backgroundColor = .secondarySystemFill; menuAnchor.layer.cornerRadius = 24
            if menuAnchor.subviews.isEmpty { let icon = UIImageView(image: UIImage(systemName: "ellipsis")); icon.tintColor = .label; icon.contentMode = .center; icon.frame = CGRect(x: 0, y: 0, width: 52, height: 52); menuAnchor.addSubview(icon) }
        }
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    // The menu lives in a sibling overlay. Finish both nested stacks before
    // that overlay converts its anchor frame after a row-count change.
    func layoutRows() {
        rows.setNeedsLayout(); rows.layoutIfNeeded()
        row.setNeedsLayout(); row.layoutIfNeeded()
        keyScroll.layoutIfNeeded()
    }
    override func layoutSubviews() { super.layoutSubviews(); layoutRows() }
    override func didMoveToWindow() { super.didMoveToWindow(); updateKeyMetrics() }
    private var keyFont: UIFont { UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), compatibleWith: traitCollection) }
    private var allKeys: [UIButton] { generated + numeric + [keyboardButton, numberButton, keypadButton, expandButton] }
    private func updateKeyMetrics() {
        let font = keyFont, symbolFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let numericIDs = Set(numeric.map(ObjectIdentifier.init))
        for key in allKeys {
            if let symbol = keySymbols[ObjectIdentifier(key)] { key.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: symbolFont)) }
            key.setNeedsUpdateConfiguration(); key.updateConfiguration()
            let text = (key.configuration?.title ?? "") as NSString
            let width = max(text.size(withAttributes: [.font: font]).width, key.configuration?.image?.size.width ?? 0)
            keyWidths[ObjectIdentifier(key)]?.constant = max(numericIDs.contains(ObjectIdentifier(key)) ? 32 : 44, ceil(width) + 12)
        }
        keyHeight = max(52, ceil(max(font.lineHeight, symbolFont.lineHeight)) + 8)
        heights.forEach { $0.constant = keyHeight }
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    private func configureButton(_ key: UIButton, title: String, symbol: String? = nil, number: Bool = false) {
        var configuration = UIButton.Configuration.gray(); configuration.cornerStyle = .medium
        configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
        if let symbol { keySymbols[ObjectIdentifier(key)] = symbol; configuration.image = UIImage(systemName: symbol) } else { configuration.title = title }
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] value in
            var value = value; value.font = self?.keyFont ?? .systemFont(ofSize: 13, weight: .medium); return value
        }
        key.configuration = configuration; key.accessibilityLabel = title
        let width = number ? key.widthAnchor.constraint(greaterThanOrEqualToConstant: 32) : key.widthAnchor.constraint(equalToConstant: 44)
        width.isActive = true; keyWidths[ObjectIdentifier(key)] = width
    }
    private func button(_ title: String, symbol: String? = nil, number: Bool = false, action: @escaping () -> Void) -> UIButton {
        let key = UIButton(type: .system); configureButton(key, title: title, symbol: symbol, number: number); generated.append(key)
        let generation = layoutGeneration
        key.addAction(UIAction { [weak self] _ in guard self?.layoutGeneration == generation else { return }; action() }, for: .touchUpInside)
        key.addAction(UIAction { [weak self] _ in if self?.terminal?.customInputEpoch() != nil { self?.keyFeedback.prepareKeyFeedback() } }, for: .touchDown)
        return key
    }
    private func sendNumber(_ value: String) {
        guard let terminal else { return }; terminal.performCustomInput { terminal.insertText(value) }; refresh()
    }
    func toggle(_ modifier: TerminalModifiers, lock: Bool = false) {
        guard let terminal, terminal.customInputEpoch() != nil, modifier != .command || terminal.keyEncoding.supportsCommand else { return }
        terminal.keyboardState.toggle(modifier, lock: lock); keyFeedback.feedback("selection"); refresh()
    }
    @objc private func lockModifier(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let key = gesture.view as? UIButton, let modifier = modifierButtons.first(where: { $0.0 === key })?.1 else { return }
        toggle(modifier, lock: true)
    }
    func refresh() {
        guard !editingPreview, let terminal else { return }
        let ready = terminal.customInputEpoch() != nil
        if !terminal.keyEncoding.supportsCommand { terminal.keyboardState.armed.remove(.command); terminal.keyboardState.locked.remove(.command) }
        if !ready { terminal.keyboardState.reset(); terminal.controlModifier = false; terminal.metaModifier = false }
        for key in allKeys { key.isEnabled = ready; key.alpha = ready ? 1 : 0.4 }
        for (key, modifier) in modifierButtons {
            key.isEnabled = ready && (modifier != .command || terminal.keyEncoding.supportsCommand); key.alpha = key.isEnabled ? 1 : 0.4
            let locked = terminal.keyboardState.locked.contains(modifier)
            key.accessibilityHint = "Tap for the next key; long-press to keep on. Tap again to turn off."
            key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: locked ? "Turn " + modifier.title + " Off" : "Keep " + modifier.title + " On", actionHandler: { [weak self] _ in self?.toggle(modifier, lock: true); return true })]
            key.isSelected = terminal.keyboardState.active.contains(modifier)
            key.configuration?.baseBackgroundColor = key.isSelected ? .systemBlue : .secondarySystemFill
            key.configuration?.baseForegroundColor = key.isSelected ? .white : .label
            key.configuration?.subtitle = locked ? "On" : key.isSelected ? "Next" : nil
            key.configuration?.titleAlignment = .center
            key.layer.borderWidth = locked ? 2 : 0; key.layer.borderColor = UIColor.label.cgColor; key.layer.cornerRadius = 10
            key.accessibilityValue = modifier == .command && !terminal.keyEncoding.supportsCommand ? "Unavailable in this application" : locked ? "On" : key.isSelected ? "Next key" : "Off"
        }
        for key in commandShortcuts { key.isEnabled = ready && terminal.keyEncoding.supportsCommand; key.alpha = key.isEnabled ? 1 : 0.4; key.accessibilityValue = terminal.keyEncoding.supportsCommand ? nil : "Unavailable in this application" }
        for key in [keyboardButton, numberButton, keypadButton, expandButton] { key.isEnabled = true; key.alpha = 1 }
    }
    private func send(_ key: TerminalAccessoryKey) {
        guard let terminal else { return }; terminal.performCustomInput { terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume()) }; refresh()
    }
}
#endif

#endif
