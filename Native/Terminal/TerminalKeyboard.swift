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
            case .delete: 3; case .pageUp: 5; case .pageDown: 6; case .f3: 13; case .f5: 15; case .f6: 17
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
    case escape, tab, up, down, left, right, home, end, pageUp, pageDown, delete, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    var id: String { rawValue }
    var title: String {
        switch self {
        case .escape: "Esc"; case .tab: "Tab"; case .up: "↑"; case .down: "↓"; case .left: "←"; case .right: "→"
        case .home: "Home"; case .end: "End"; case .pageUp: "PgUp"; case .pageDown: "PgDn"; case .delete: "Del"
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
            let code: Int = switch self { case .pageUp: 5; case .pageDown: 6; case .delete: 3; case .f5: 15; case .f6: 17; case .f7: 18; case .f8: 19; case .f9: 20; case .f10: 21; case .f11: 23; case .f12: 24; default: 0 }
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
@MainActor final class TerminalKeyboardBar: UIView {
    weak var terminal: SessionTerminalView?
    // Shared preference policy; this surface owns its reusable feedback generators.
    lazy var keyFeedback = CompanionVNCInterfaceFeedback(view: self)
    private let rows = UIStackView()
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    private var commandShortcuts: [UIButton] = []
    let keyboardButton = UIButton(type: .system)
    let menuAnchor = UIView()
    let keyScroll = UIScrollView()
    private let numbers = UIStackView()
    private let custom = UIStackView()
    private let navigation = UIStackView()
    private let navigationScroll = UIScrollView()
    let numberButton = UIButton(type: .system)
    let expandButton = UIButton(type: .system)
    var layoutChanged: (() -> Void)?
    var openKeypad: ((Bool) -> Void)?
    var compactLayout = false { didSet { if oldValue != compactLayout { updateRows() } } }
    private var expandedRowsVisible: Bool { expanded && !compactLayout }
    var expanded = true { didSet { if oldValue != expanded { updateRows() } } }
    var showsNavigation = true { didSet { if oldValue != showsNavigation { updateRows() } } }
    private let numberScroll = UIScrollView()
    private let customScroll = UIScrollView()
    private let modifierKeys = UIStackView()
    private let modifierRow = UIStackView()
    private var navigationKeys: [UIButton] = []
    private var keyRows: [(UIStackView, NSLayoutConstraint, NSLayoutConstraint)] = []
    private var naturalHeights: [ObjectIdentifier: CGFloat] = [:]
    private var modifierHeight: NSLayoutConstraint!
    var toggleKeyboard: (() -> Void)?
    private var softwareKeyboardVisible = false
    private var composerVisible = false
    private var hasCustomKeys = false
    var showsNumberRow = true {
        didSet { if oldValue != showsNumberRow { updateRows() } }
    }
    var expandedHeight: CGFloat {
        8 + (modifierHeight?.constant ?? 52) + (showsNumberRow ? naturalHeight(numbers) + 4 : 0)
            + (hasCustomKeys ? naturalHeight(custom) + 4 : 0) + naturalHeight(navigation) + 4
    }
    var height: CGFloat {
        !composerVisible && expandedRowsVisible ? expandedHeight : 8 + (modifierHeight?.constant ?? 52)
    }
    init(terminal: SessionTerminalView, preferences: TerminalKeyboardPreferences) {
        self.terminal = terminal
        super.init(frame: .zero)
        accessibilityIdentifier = "terminal-keyboard-bar"
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.spacing = 0; rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: topAnchor, constant: 4), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
        for number in ["1","2","3","4","5","6","7","8","9","0"] { numbers.addArrangedSubview(button(number) { [weak self] in self?.sendNumber(number) }) }
        for (row, scroll) in [(numbers, numberScroll), (custom, customScroll), (navigation, navigationScroll)] {
            row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 3
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.showsHorizontalScrollIndicator = false; scroll.addSubview(row); rows.addArrangedSubview(scroll)
            let height = scroll.heightAnchor.constraint(equalToConstant: 0)
            naturalHeights[ObjectIdentifier(row)] = 44
            let minimum = row.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
            let fill = row.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor); fill.priority = .init(750)
            NSLayoutConstraint.activate([height, minimum, fill,
                row.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor),
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
            keyRows.append((row, height, minimum)); scroll.clipsToBounds = true
        }
        numbers.accessibilityIdentifier = "terminal-number-row"
        navigation.accessibilityIdentifier = "terminal-navigation-row"
        for key in [TerminalAccessoryKey.left, .down, .up, .right] {
            let value = button(key.title) { [weak self] in self?.send(key) }
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            navigationKeys.append(value); navigation.addArrangedSubview(value)
        }
        for (value, title, id) in [(numberButton, "123", "terminal-number-toggle"), (expandButton, "", "terminal-expand-toggle")] {
            var configuration = UIButton.Configuration.gray(); configuration.title = title; configuration.cornerStyle = .medium
            configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
            if value === numberButton { configuration.title = nil; configuration.image = UIImage(systemName: "textformat.123") }
            value.configuration = configuration; value.accessibilityIdentifier = id
            let width = value.widthAnchor.constraint(equalToConstant: 44); width.priority = .defaultHigh; width.isActive = true
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        numberButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }; if compactLayout { openKeypad?(true); return }; if !expanded { showsNumberRow = true; expanded = true } else { showsNumberRow.toggle() }; layoutChanged?()
        }, for: .touchUpInside)
        expandButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }; if compactLayout { openKeypad?(false); return }; expanded.toggle(); layoutChanged?()
        }, for: .touchUpInside)
        var keyboardConfiguration = UIButton.Configuration.gray()
        keyboardConfiguration.image = UIImage(systemName: "keyboard")
        keyboardConfiguration.cornerStyle = .medium
        keyboardButton.configuration = keyboardConfiguration
        let keyboardWidth = keyboardButton.widthAnchor.constraint(equalToConstant: 44)
        keyboardWidth.priority = .defaultHigh; keyboardWidth.isActive = true
        keyboardButton.accessibilityIdentifier = "terminal-keyboard-toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in
            guard let self, let terminal = self.terminal else { return }
            let wasVisible = terminal.isFirstResponder
            self.toggleKeyboard?()
            if wasVisible != terminal.isFirstResponder { self.keyFeedback.feedback("selection") }
        }, for: .touchUpInside)
        keyScroll.showsHorizontalScrollIndicator = true
        keyScroll.accessibilityIdentifier = "terminal-modifier-keys"
        keyScroll.translatesAutoresizingMaskIntoConstraints = false
        let controls = modifierKeys; controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 3
        controls.translatesAutoresizingMaskIntoConstraints = false; keyScroll.addSubview(controls)
        menuAnchor.isUserInteractionEnabled = false
        let bar = modifierRow
        for item in [keyboardButton, keyScroll, numberButton, expandButton, menuAnchor] { bar.addArrangedSubview(item) }
        bar.spacing = 4
        rows.addArrangedSubview(bar)
        let fill = controls.widthAnchor.constraint(equalTo: keyScroll.frameLayoutGuide.widthAnchor); fill.priority = .init(750)
        modifierHeight = bar.heightAnchor.constraint(equalToConstant: 52)
        let modifierWidth = controls.widthAnchor.constraint(greaterThanOrEqualToConstant: 4 * 44 + 3 * 3)
        keyRows.append((controls, modifierHeight, modifierWidth))
        NSLayoutConstraint.activate([
            fill,
            modifierHeight,
            keyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44), menuAnchor.widthAnchor.constraint(equalToConstant: 52),
            controls.leadingAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.trailingAnchor),
            controls.topAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.topAnchor),
            controls.bottomAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.bottomAnchor),
            controls.heightAnchor.constraint(equalTo: keyScroll.frameLayoutGuide.heightAnchor),
            controls.widthAnchor.constraint(greaterThanOrEqualTo: keyScroll.frameLayoutGuide.widthAnchor),
            modifierWidth
        ])
        controls.addArrangedSubview(button("Esc") { [weak self] in self?.send(.escape) })
        controls.addArrangedSubview(button("Tab") { [weak self] in self?.send(.tab) })
        for modifier in [TerminalModifiers.ctrl, .alt, .shift, .command] {
            let title = modifier.title
            let value = button(title) { [weak self] in self?.toggle(modifier) }; modifierButtons.append((value, modifier))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))); value.addGestureRecognizer(hold)
            controls.addArrangedSubview(value)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: TerminalKeyboardBar, _: UITraitCollection) in
            bar.updateKeyMetrics(refreshFonts: true)
        }
        configure(preferences)
        refresh()
    }
    func configure(_ preferences: TerminalKeyboardPreferences) {
        for key in custom.arrangedSubviews { custom.removeArrangedSubview(key); key.removeFromSuperview() }
        hasCustomKeys = DirectProAccess.shared.hasPro && !preferences.keys.isEmpty
        if hasCustomKeys {
            for key in preferences.keys { custom.addArrangedSubview(button(key.title) { [weak self] in guard DirectProAccess.shared.hasPro else { return }; self?.send(key) }) }
        }
        updateRows()
        updateKeyMetrics(refreshFonts: true)
    }
    func configure(_ profile: TerminalControlsProfile, perform: @escaping (UUID) -> Void) {
        commandShortcuts = []
        for key in custom.arrangedSubviews { custom.removeArrangedSubview(key); key.removeFromSuperview() }
        let actions = DirectProAccess.shared.hasPro ? profile.placed(.keyboard) : []
        expanded = profile.expandedBar ?? true; showsNavigation = profile.navigationRow ?? true
        hasCustomKeys = !actions.isEmpty
        for item in actions {
            let key = button(item.title) { [weak self] in
                guard self?.terminal?.customInputEpoch() != nil else { return }
                perform(item.id)
            }
            if item.requiresCommand {
                commandShortcuts.append(key)
                key.accessibilityHint = "Requires Command support from the remote terminal application."
            }
            custom.addArrangedSubview(key)
        }
        updateRows(); updateKeyMetrics(refreshFonts: true); refresh()
    }
    func setSoftwareKeyboardVisible(_ visible: Bool) {
        guard softwareKeyboardVisible != visible else { return }
        softwareKeyboardVisible = visible; updateRows()
    }
    func setKeyboardFocused(_ focused: Bool) {
        keyboardButton.accessibilityLabel = focused ? "Hide Keyboard" : "Show Keyboard"
        keyboardButton.configuration?.image = UIImage(systemName: focused ? "keyboard.chevron.compact.down" : "keyboard")
    }
    func setComposerVisible(_ visible: Bool) {
        guard composerVisible != visible else { return }
        composerVisible = visible; updateRows()
    }
    private func updateRows() {
        let expanded = !composerVisible && expandedRowsVisible
        let utilityRow = expanded ? navigation : modifierRow
        if keyboardButton.superview !== utilityRow {
            for item in [keyboardButton, numberButton, expandButton] {
                (item.superview as? UIStackView)?.removeArrangedSubview(item); item.removeFromSuperview()
            }
            utilityRow.insertArrangedSubview(keyboardButton, at: 0)
            if expanded {
                utilityRow.insertArrangedSubview(numberButton, at: 1); utilityRow.addArrangedSubview(expandButton)
            } else {
                utilityRow.insertArrangedSubview(numberButton, at: 2); utilityRow.insertArrangedSubview(expandButton, at: 3)
            }
        }
        for key in navigationKeys { key.isHidden = !showsNavigation }
        let usesKeypad = compactLayout
        numberButton.accessibilityLabel = usesKeypad ? "Open Number Keypad" : showsNumberRow && expanded ? "Hide Number Row" : "Show Number Row"
        numberButton.accessibilityValue = usesKeypad ? nil : (showsNumberRow && expandedRowsVisible ? "On" : "Off")
        numberButton.isSelected = showsNumberRow && expandedRowsVisible
        expandButton.configuration?.image = UIImage(systemName: usesKeypad ? "rectangle.grid.3x2" : expanded ? "chevron.down" : "chevron.up")
        expandButton.accessibilityLabel = usesKeypad ? "Open Keypad" : expanded ? "Collapse Keyboard Bar" : "Expand Keyboard Bar"
        for (index, shown) in [expanded && showsNumberRow, expanded && hasCustomKeys, expanded].enumerated() {
            let (row, height, _) = keyRows[index]
            let scroll = [numberScroll, customScroll, navigationScroll][index]
            // Keep arranged views attached. Explicit zero heights avoid UIKit's
            // animated hidden-state constraints retaining overlapping row frames.
            height.constant = shown ? naturalHeight(row) : 0
            scroll.alpha = shown ? 1 : 0; scroll.isUserInteractionEnabled = shown
            scroll.accessibilityElementsHidden = !shown
            rows.setCustomSpacing(shown ? 4 : 0, after: scroll)
        }
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    private func naturalHeight(_ row: UIStackView) -> CGFloat { naturalHeights[ObjectIdentifier(row)] ?? 44 }

    override func didMoveToWindow() { super.didMoveToWindow(); updateKeyMetrics(refreshFonts: true) }
    private var keyFont: UIFont {
        UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), compatibleWith: traitCollection)
    }
    private func updateKeyMetrics(refreshFonts: Bool) {
        var changed = false
        let font = keyFont
        for (row, height, width) in keyRows {
            let buttons = row.arrangedSubviews.compactMap { $0 as? UIButton }.filter { !$0.isHidden }
            if refreshFonts { for button in buttons { button.setNeedsUpdateConfiguration(); button.updateConfiguration() } }
            // Trait callbacks can precede UILabel's configuration update. Measure
            // the new font directly so growing captions cannot retain old bounds.
            let sizes = buttons.map { button in
                let text = (button.configuration?.title ?? "") as NSString
                let insets = button.configuration?.contentInsets ?? .zero
                return CGSize(width: text.size(withAttributes: [.font: font]).width + insets.leading + insets.trailing,
                    height: font.lineHeight + insets.top + insets.bottom)
            }
            let rowHeight = max(row === modifierKeys ? 52 : 44, ceil(sizes.map(\.height).max() ?? 0))
            let keyWidth = max(row === modifierKeys ? 44 : 28, ceil(sizes.map(\.width).max() ?? 0) + 12)
            let rowWidth = CGFloat(buttons.count) * keyWidth + CGFloat(max(0, buttons.count - 1)) * row.spacing
            if naturalHeights[ObjectIdentifier(row)] != rowHeight {
                naturalHeights[ObjectIdentifier(row)] = rowHeight
                if row === modifierKeys { height.constant = rowHeight }
                changed = true
            }
            if width.constant != rowWidth { width.constant = rowWidth; changed = true }
        }
        if changed { updateRows() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray(); configuration.title = title; configuration.cornerStyle = .medium
        configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] value in
            var value = value
            value.font = self?.keyFont ?? UIFont.systemFont(ofSize: 13, weight: .medium)
            return value
        }
        button.configuration = configuration; button.accessibilityLabel = title; button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in if self?.terminal?.customInputEpoch() != nil { self?.keyFeedback.prepareKeyFeedback() } }, for: .touchDown)
        return button
    }
    private func sendNumber(_ number: String) {
        guard let terminal else { return }
        terminal.performCustomInput { terminal.insertText(number) }
    }
    func toggle(_ modifier: TerminalModifiers, lock: Bool = false) {
        guard let terminal, terminal.customInputEpoch() != nil else { return }
        guard modifier != .command || terminal.keyEncoding.supportsCommand else { return }
        terminal.keyboardState.toggle(modifier, lock: lock); keyFeedback.feedback("selection"); refresh()
    }
    @objc private func lockModifier(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton,
              let modifier = modifierButtons.first(where: { $0.0 === button })?.1 else { return }
        toggle(modifier, lock: true)
    }
    func refresh() {
        guard let terminal else { return }
        let ready = terminal.customInputEpoch() != nil
        if !terminal.keyEncoding.supportsCommand {
            terminal.keyboardState.armed.remove(.command); terminal.keyboardState.locked.remove(.command)
        }
        if !ready { terminal.keyboardState.reset(); terminal.controlModifier = false; terminal.metaModifier = false }
        for (row, _, _) in keyRows {
            for case let key as UIButton in row.arrangedSubviews { key.isEnabled = ready; key.alpha = ready ? 1 : 0.4 }
        }
        for (button, modifier) in modifierButtons {
            button.isEnabled = ready && (modifier != .command || terminal.keyEncoding.supportsCommand)
            button.alpha = button.isEnabled ? 1 : 0.4
            button.accessibilityHint = modifier == .command ? "Requires Command support from the remote terminal application." : modifier == .alt ? "Option on Mac. Tap for the next key; hold to lock." : "Tap for the next key; hold to lock."
            button.isSelected = terminal.keyboardState.active.contains(modifier)
            button.configuration?.baseBackgroundColor = button.isSelected ? .systemBlue : .secondarySystemFill
            button.configuration?.baseForegroundColor = button.isSelected ? .white : .label
            let name = modifier.title
            button.configuration?.title = name + (terminal.keyboardState.locked.contains(modifier) ? " 🔒" : button.isSelected ? " •" : "")
            button.accessibilityValue = modifier == .command && !terminal.keyEncoding.supportsCommand ? "Unavailable in this application" : terminal.keyboardState.locked.contains(modifier) ? "Locked" : (button.isSelected ? "Next key" : "Off")
        }
        for button in commandShortcuts {
            button.isEnabled = ready && terminal.keyEncoding.supportsCommand
            button.alpha = button.isEnabled ? 1 : 0.4
            button.accessibilityValue = terminal.keyEncoding.supportsCommand ? nil : "Unavailable in this application"
        }
        // These change local presentation even while remote input is suspended.
        for button in [keyboardButton, numberButton, expandButton] { button.isEnabled = true; button.alpha = 1 }
        updateKeyMetrics(refreshFonts: false)
    }
    private func send(_ key: TerminalAccessoryKey) {
        guard let terminal else { return }
        terminal.performCustomInput {
            terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume())
        }
        refresh()
    }
}
#endif

#endif
