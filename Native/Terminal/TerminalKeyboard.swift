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
private final class TerminalKeyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}

@MainActor final class TerminalKeyboardBar: UIView {
    weak var terminal: SessionTerminalView?
    lazy var keyFeedback = CompanionVNCInterfaceFeedback(view: self)
    private let row = UIStackView()
    private let keys = UIStackView()
    private let numbers = UIStackView()
    private let custom = UIStackView()
    private let navigation = UIStackView()
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    private var commandShortcuts: [UIButton] = []
    private var keyWidths: [ObjectIdentifier: NSLayoutConstraint] = [:]
    private var keySymbols: [ObjectIdentifier: String] = [:]
    private var rowHeight: NSLayoutConstraint!
    private var keyboardFocused: Bool?
    let keyboardButton = UIButton(type: .system)
    let numberButton = UIButton(type: .system)
    let keypadButton = UIButton(type: .system)
    let menuAnchor = UIView()
    let keyScroll: UIScrollView = TerminalKeyScrollView()
    var layoutChanged: (() -> Void)?
    var toggleKeyboard: (() -> Void)?
    var openKeypad: ((Bool) -> Void)?
    var showsNavigation = true { didSet { navigation.isHidden = !showsNavigation } }
    var showsNumberRow = true { didSet { updateNumbers() } }
    var height: CGFloat { 8 + (rowHeight?.constant ?? 52) }

    init(terminal: SessionTerminalView, preferences: TerminalKeyboardPreferences) {
        self.terminal = terminal
        super.init(frame: .zero)
        accessibilityIdentifier = "terminal-keyboard-bar"
        translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal; row.spacing = 4; row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        for item in [keyboardButton, keyScroll, menuAnchor] { row.addArrangedSubview(item) }
        rowHeight = row.heightAnchor.constraint(equalToConstant: 52)
        let keyboardWidth = keyboardButton.widthAnchor.constraint(equalToConstant: 44)
        keyWidths[ObjectIdentifier(keyboardButton)] = keyboardWidth
        menuAnchor.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), rowHeight,
            keyboardWidth,
            menuAnchor.widthAnchor.constraint(equalToConstant: 52)
        ])
        configureButton(keyboardButton, title: "Show Keyboard", symbol: "keyboard")
        keyboardButton.accessibilityIdentifier = "terminal-keyboard-toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in
            guard let self, let terminal = self.terminal else { return }
            let wasVisible = terminal.isFirstResponder
            self.toggleKeyboard?()
            if wasVisible != terminal.isFirstResponder { self.keyFeedback.feedback("selection") }
        }, for: .touchUpInside)
        keyScroll.showsHorizontalScrollIndicator = true
        keyScroll.alwaysBounceHorizontal = true
        keyScroll.accessibilityIdentifier = "terminal-modifier-keys"
        keyScroll.accessibilityLabel = "Terminal keys"
        keys.axis = .horizontal; keys.spacing = 3; keys.translatesAutoresizingMaskIntoConstraints = false
        keyScroll.addSubview(keys)
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.topAnchor),
            keys.bottomAnchor.constraint(equalTo: keyScroll.contentLayoutGuide.bottomAnchor),
            keys.heightAnchor.constraint(equalTo: keyScroll.frameLayoutGuide.heightAnchor)
        ])
        keys.addArrangedSubview(button("Esc", symbol: "escape") { [weak self] in self?.send(.escape) })
        keys.addArrangedSubview(button("Tab", symbol: "arrow.right.to.line") { [weak self] in self?.send(.tab) })
        for (modifier, symbol) in [(TerminalModifiers.ctrl, "control"), (.alt, "option"), (.shift, "shift"), (.command, "command")] {
            let value = button(modifier.title, symbol: symbol) { [weak self] in self?.toggle(modifier) }
            value.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))))
            modifierButtons.append((value, modifier)); keys.addArrangedSubview(value)
        }
        for (group, identifier) in [(navigation, "terminal-navigation-row"), (custom, "terminal-custom-keys"), (numbers, "terminal-number-row")] {
            group.axis = .horizontal; group.spacing = 3; group.accessibilityIdentifier = identifier
        }
        for (key, symbol) in [(TerminalAccessoryKey.left, "arrow.left"), (.down, "arrow.down"), (.up, "arrow.up"), (.right, "arrow.right")] {
            navigation.addArrangedSubview(button(key.title, symbol: symbol) { [weak self] in self?.send(key) })
        }
        keys.addArrangedSubview(navigation)
        configureButton(numberButton, title: "Hide Numbers", symbol: "textformat.123")
        numberButton.accessibilityIdentifier = "terminal-number-toggle"
        numberButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }; showsNumberRow.toggle(); layoutChanged?()
            if showsNumberRow { layoutIfNeeded(); keyScroll.scrollRectToVisible(numbers.convert(numbers.bounds, to: keys), animated: true) }
        }, for: .touchUpInside)
        configureButton(keypadButton, title: "Open Keypad", symbol: "rectangle.grid.3x2")
        keypadButton.accessibilityIdentifier = "terminal-keypad-toggle"
        keypadButton.addAction(UIAction { [weak self] _ in self?.openKeypad?(false) }, for: .touchUpInside)
        for item in [numberButton, keypadButton, custom, numbers] { keys.addArrangedSubview(item) }
        for number in ["1","2","3","4","5","6","7","8","9","0"] {
            numbers.addArrangedSubview(button(number) { [weak self] in self?.sendNumber(number) })
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: TerminalKeyboardBar, _: UITraitCollection) in bar.updateKeyMetrics() }
        configure(preferences); refresh()
    }
    func configure(_ preferences: TerminalKeyboardPreferences) {
        clearCustomKeys()
        if DirectProAccess.shared.hasPro {
            for key in preferences.keys { custom.addArrangedSubview(button(key.title) { [weak self] in
                guard DirectProAccess.shared.hasPro else { return }; self?.send(key)
            }) }
        }
        custom.isHidden = custom.arrangedSubviews.isEmpty
        updateNumbers(); updateKeyMetrics()
    }
    func configure(_ profile: TerminalControlsProfile, perform: @escaping (UUID) -> Void) {
        clearCustomKeys(); showsNavigation = profile.navigationRow ?? true
        for item in DirectProAccess.shared.hasPro ? profile.placed(.keyboard) : [] {
            let key = button(item.title) { [weak self] in
                guard self?.terminal?.customInputEpoch() != nil else { return }; perform(item.id)
            }
            if item.requiresCommand { commandShortcuts.append(key) }
            custom.addArrangedSubview(key)
        }
        custom.isHidden = custom.arrangedSubviews.isEmpty
        updateNumbers(); updateKeyMetrics(); refresh()
    }
    private func clearCustomKeys() {
        commandShortcuts = []
        for key in custom.arrangedSubviews {
            keyWidths.removeValue(forKey: ObjectIdentifier(key))
            custom.removeArrangedSubview(key); key.removeFromSuperview()
        }
    }
    func setKeyboardFocused(_ focused: Bool) {
        guard keyboardFocused != focused else { return }
        keyboardFocused = focused
        keyboardButton.accessibilityLabel = focused ? "Hide Keyboard" : "Show Keyboard"
        keySymbols[ObjectIdentifier(keyboardButton)] = focused ? "keyboard.chevron.compact.down" : "keyboard"
        updateKeyMetrics()
    }
    private func updateNumbers() {
        numbers.isHidden = !showsNumberRow
        numberButton.accessibilityLabel = showsNumberRow ? "Hide Numbers" : "Show Numbers"
        numberButton.accessibilityValue = showsNumberRow ? "On" : "Off"
        numberButton.isSelected = showsNumberRow
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updateKeyMetrics() }
    private var keyFont: UIFont { UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), compatibleWith: traitCollection) }
    private var allKeys: [UIButton] {
        keys.arrangedSubviews.flatMap { item in (item as? UIStackView)?.arrangedSubviews.compactMap { $0 as? UIButton } ?? [item as? UIButton].compactMap { $0 } }
    }
    private func updateKeyMetrics() {
        let font = keyFont
        let symbolFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        for button in allKeys + [keyboardButton] {
            if let symbol = keySymbols[ObjectIdentifier(button)] {
                button.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: symbolFont))
            }
            button.setNeedsUpdateConfiguration(); button.updateConfiguration()
            let text = (button.configuration?.title ?? "") as NSString
            let contentWidth = max(text.size(withAttributes: [.font: font]).width, button.configuration?.image?.size.width ?? 0)
            keyWidths[ObjectIdentifier(button)]?.constant = max(44, ceil(contentWidth) + 12)
        }
        rowHeight.constant = max(52, ceil(max(font.lineHeight, symbolFont.lineHeight)) + 8)
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    private func configureButton(_ button: UIButton, title: String, symbol: String? = nil) {
        var configuration = UIButton.Configuration.gray(); configuration.cornerStyle = .medium
        configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
        if let symbol { keySymbols[ObjectIdentifier(button)] = symbol; configuration.image = UIImage(systemName: symbol) } else { configuration.title = title }
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] value in
            var value = value; value.font = self?.keyFont ?? .systemFont(ofSize: 13, weight: .medium); return value
        }
        button.configuration = configuration; button.accessibilityLabel = title
        if button !== keyboardButton {
            let width = button.widthAnchor.constraint(equalToConstant: 44); width.isActive = true
            keyWidths[ObjectIdentifier(button)] = width
        }
    }
    private func button(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system); configureButton(button, title: title, symbol: symbol)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in if self?.terminal?.customInputEpoch() != nil { self?.keyFeedback.prepareKeyFeedback() } }, for: .touchDown)
        return button
    }
    private func sendNumber(_ number: String) {
        guard let terminal else { return }; terminal.performCustomInput { terminal.insertText(number) }
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
        if !terminal.keyEncoding.supportsCommand { terminal.keyboardState.armed.remove(.command); terminal.keyboardState.locked.remove(.command) }
        if !ready { terminal.keyboardState.reset(); terminal.controlModifier = false; terminal.metaModifier = false }
        for key in allKeys { key.isEnabled = ready; key.alpha = ready ? 1 : 0.4 }
        for (button, modifier) in modifierButtons {
            button.isEnabled = ready && (modifier != .command || terminal.keyEncoding.supportsCommand)
            button.alpha = button.isEnabled ? 1 : 0.4
            button.accessibilityHint = modifier == .command ? "Requires Command support from the remote terminal application. Tap for the next key; hold to lock." : modifier == .alt ? "Option on Mac. Tap for the next key; hold to lock." : "Tap for the next key; hold to lock."
            button.isSelected = terminal.keyboardState.active.contains(modifier)
            button.configuration?.baseBackgroundColor = button.isSelected ? .systemBlue : .secondarySystemFill
            button.configuration?.baseForegroundColor = button.isSelected ? .white : .label
            button.layer.borderWidth = terminal.keyboardState.locked.contains(modifier) ? 2 : 0
            button.layer.borderColor = UIColor.label.cgColor
            button.layer.cornerRadius = 10
            button.accessibilityValue = modifier == .command && !terminal.keyEncoding.supportsCommand ? "Unavailable in this application" : terminal.keyboardState.locked.contains(modifier) ? "Locked" : (button.isSelected ? "Next key" : "Off")
        }
        for button in commandShortcuts {
            button.isEnabled = ready && terminal.keyEncoding.supportsCommand; button.alpha = button.isEnabled ? 1 : 0.4
            button.accessibilityValue = terminal.keyEncoding.supportsCommand ? nil : "Unavailable in this application"
        }
        for button in [keyboardButton, numberButton, keypadButton] { button.isEnabled = true; button.alpha = 1 }
    }
    private func send(_ key: TerminalAccessoryKey) {
        guard let terminal else { return }
        terminal.performCustomInput { terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume()) }; refresh()
    }
}
#endif

#endif
