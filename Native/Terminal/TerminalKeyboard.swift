#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import UIKit
import SwiftTerm

struct TerminalModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let shift = Self(rawValue: 1)
    static let alt = Self(rawValue: 2)
    static let ctrl = Self(rawValue: 4)
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
                if (0x33...0x37).contains(ascii) { result.append(UInt8(ascii - 0x33 + 0x1b)); continue }
            }
            result.append(contentsOf: String(scalar).utf8)
        }
        return result
    }
}

extension VNCQuickAction {
    func terminalBytes(applicationCursor: Bool = false) -> [UInt8] {
        guard kind == .shortcut, valid, compatible(with: .terminal) else { return [] }
        var flags: TerminalModifiers = []
        if modifiers.contains(0xffe1) { flags.insert(.shift) }
        if modifiers.contains(0xffe3) { flags.insert(.ctrl) }
        if modifiers.contains(0xffe9) { flags.insert(.alt) }
        let special: [UInt32: TerminalAccessoryKey] = [0xff1b: .escape, 0xff09: .tab, 0xffff: .delete, 0xff51: .left, 0xff52: .up, 0xff53: .right, 0xff54: .down]
        if key == 0xff08 { return TerminalKeyboardState.backspace(modifiers: flags) }
        if let special = special[key] { return special.bytes(modifiers: flags, applicationCursor: applicationCursor) }
        if key == 0xff0d { return TerminalKeyboardState.text("\r", modifiers: flags) }
        guard let scalar = UnicodeScalar(key) else { return [] }
        return TerminalKeyboardState.text(String(scalar), modifiers: flags)
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

@MainActor final class TerminalKeyboardBar: UIView {
    weak var terminal: SessionTerminalView?
    var customize: (() -> Void)?
    private let rows = UIStackView()
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    let keyboardButton = UIButton(type: .system)
    let menuAnchor = UIView()
    let keyScroll = UIScrollView()
    private let numbers = UIStackView()
    private let custom = UIStackView()
    private let numberScroll = UIScrollView()
    private let customScroll = UIScrollView()
    private let modifierKeys = UIStackView()
    private var keyRows: [(UIStackView, NSLayoutConstraint, NSLayoutConstraint)] = []
    private var modifierHeight: NSLayoutConstraint!
    private var more = UIButton(type: .system)
    var toggleKeyboard: (() -> Void)?
    private var softwareKeyboardVisible = false
    private var hasCustomKeys = false
    var showsNumberRow = true {
        didSet { if oldValue != showsNumberRow { updateRows() } }
    }
    var height: CGFloat {
        8 + (modifierHeight?.constant ?? 52) + (softwareKeyboardVisible ?
            (showsNumberRow ? keyRows[0].1.constant + 4 : 0) + (hasCustomKeys ? keyRows[1].1.constant + 4 : 0) : 0)
    }
    init(terminal: SessionTerminalView, preferences: TerminalKeyboardPreferences) {
        self.terminal = terminal
        super.init(frame: .zero)
        accessibilityIdentifier = "terminal-keyboard-bar"
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.spacing = 4; rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: topAnchor, constant: 4), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
        for number in ["1","2","3","4","5","6","7","8","9","0"] { numbers.addArrangedSubview(button(number) { [weak terminal] in terminal?.insertText(number) }) }
        for (row, scroll) in [(numbers, numberScroll), (custom, customScroll)] {
            row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 3
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.showsHorizontalScrollIndicator = false; scroll.addSubview(row); rows.addArrangedSubview(scroll)
            let height = scroll.heightAnchor.constraint(equalToConstant: 44)
            let minimum = row.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
            let fill = row.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor); fill.priority = .init(750)
            NSLayoutConstraint.activate([height, minimum, fill,
                row.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor),
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
            keyRows.append((row, height, minimum)); scroll.isHidden = true
        }
        numbers.accessibilityIdentifier = "terminal-number-row"
        var keyboardConfiguration = UIButton.Configuration.gray()
        keyboardConfiguration.image = UIImage(systemName: "keyboard")
        keyboardConfiguration.cornerStyle = .medium
        keyboardButton.configuration = keyboardConfiguration
        keyboardButton.accessibilityIdentifier = "terminal-keyboard-toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in self?.toggleKeyboard?() }, for: .touchUpInside)
        keyScroll.showsHorizontalScrollIndicator = false
        keyScroll.accessibilityIdentifier = "terminal-modifier-keys"
        keyScroll.translatesAutoresizingMaskIntoConstraints = false
        let controls = modifierKeys; controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 3
        controls.translatesAutoresizingMaskIntoConstraints = false; keyScroll.addSubview(controls)
        menuAnchor.isUserInteractionEnabled = false
        let bar = UIStackView(arrangedSubviews: [keyboardButton, keyScroll, menuAnchor]); bar.spacing = 4
        rows.addArrangedSubview(bar)
        let fill = controls.widthAnchor.constraint(equalTo: keyScroll.frameLayoutGuide.widthAnchor); fill.priority = .init(750)
        modifierHeight = bar.heightAnchor.constraint(equalToConstant: 52)
        let modifierWidth = controls.widthAnchor.constraint(greaterThanOrEqualToConstant: 9 * 44 + 8 * 3)
        keyRows.append((controls, modifierHeight, modifierWidth))
        NSLayoutConstraint.activate([
            fill,
            modifierHeight,
            keyboardButton.widthAnchor.constraint(equalToConstant: 48), menuAnchor.widthAnchor.constraint(equalToConstant: 52),
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
        for (title, modifier) in [("Ctrl", TerminalModifiers.ctrl), ("Alt", .alt)] {
            let value = button(title) { [weak self] in self?.toggle(modifier) }; modifierButtons.append((value, modifier))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))); value.addGestureRecognizer(hold)
            controls.addArrangedSubview(value)
        }
        for key in [TerminalAccessoryKey.left, .down, .up, .right] { controls.addArrangedSubview(button(key.title) { [weak self] in self?.send(key) }) }
        more = button("Fn", action: {})
        more.showsMenuAsPrimaryAction = true
        controls.addArrangedSubview(more)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: TerminalKeyboardBar, _: UITraitCollection) in
            bar.updateKeyMetrics(refreshFonts: true)
        }
        configure(preferences)
        refresh()
    }
    func configure(_ preferences: TerminalKeyboardPreferences) {
        more.accessibilityLabel = "Extra Terminal Keys"
        var menu = [UIMenu(title: "Navigation & Function Keys", children: TerminalAccessoryKey.allCases.filter { ![.escape, .tab, .left, .right, .up, .down].contains($0) }.map { key in UIAction(title: key.title) { [weak self] _ in self?.send(key) } }),
            UIMenu(title: "Shortcuts", children: [("Interrupt · Ctrl-C", "c"), ("End Input · Ctrl-D", "d"), ("Suspend · Ctrl-Z", "z")].map { title, text in UIAction(title: title) { [weak terminal] _ in terminal?.resetModifiers(); terminal?.send(data: TerminalKeyboardState.text(text, modifiers: .ctrl)[...]) } }),
            UIMenu(title: "Keyboard", children: [UIAction(title: "Shift for Next Key") { [weak self] _ in self?.toggle(.shift) }, UIAction(title: "Lock/Unlock Shift") { [weak self] _ in self?.terminal?.keyboardState.toggle(.shift, lock: true); self?.refresh() }, UIAction(title: "Copy Selection") { [weak terminal] _ in terminal?.copy(nil) }, UIAction(title: "Paste") { [weak terminal] _ in terminal?.resetModifiers(); terminal?.paste(nil) }, UIAction(title: "Customize Keys & Snippets") { [weak self] _ in self?.customize?() }])]
        if DirectProAccess.shared.hasPro, !preferences.snippets.isEmpty {
            menu.insert(UIMenu(title: "Saved Snippets", children: preferences.snippets.map { snippet in UIAction(title: snippet.name) { [weak terminal] _ in
                guard DirectProAccess.shared.hasPro, let terminal else { return }; terminal.resetModifiers()
                let text = terminal.getTerminal().bracketedPasteMode ? "\u{1b}[200~" + snippet.text + "\u{1b}[201~" : snippet.text
                terminal.send(data: Array(text.utf8)[...])
            } }), at: 1)
        }
        more.menu = UIMenu(children: menu)
        for key in custom.arrangedSubviews { custom.removeArrangedSubview(key); key.removeFromSuperview() }
        hasCustomKeys = DirectProAccess.shared.hasPro && !preferences.keys.isEmpty
        if hasCustomKeys {
            for key in preferences.keys { custom.addArrangedSubview(button(key.title) { [weak self] in guard DirectProAccess.shared.hasPro else { return }; self?.send(key) }) }
        }
        updateRows()
        updateKeyMetrics(refreshFonts: true)
    }
    func setSoftwareKeyboardVisible(_ visible: Bool) {
        guard softwareKeyboardVisible != visible else { return }
        softwareKeyboardVisible = visible; updateRows()
    }
    func setKeyboardFocused(_ focused: Bool) {
        keyboardButton.accessibilityLabel = focused ? "Hide Keyboard" : "Show Keyboard"
        keyboardButton.configuration?.image = UIImage(systemName: focused ? "keyboard.chevron.compact.down" : "keyboard")
    }
    private func updateRows() {
        numbers.isHidden = !softwareKeyboardVisible || !showsNumberRow
        custom.isHidden = !softwareKeyboardVisible || !hasCustomKeys
        numberScroll.isHidden = numbers.isHidden; customScroll.isHidden = custom.isHidden
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updateKeyMetrics(refreshFonts: true) }
    private var keyFont: UIFont {
        UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), compatibleWith: traitCollection)
    }
    private func updateKeyMetrics(refreshFonts: Bool) {
        var changed = false
        let font = keyFont
        for (row, height, width) in keyRows {
            let buttons = row.arrangedSubviews.compactMap { $0 as? UIButton }
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
            if height.constant != rowHeight { height.constant = rowHeight; changed = true }
            if width.constant != rowWidth { width.constant = rowWidth; changed = true }
        }
        if changed { invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout() }
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
        return button
    }
    private func toggle(_ modifier: TerminalModifiers) { terminal?.keyboardState.toggle(modifier); refresh() }
    @objc private func lockModifier(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton,
              let modifier = modifierButtons.first(where: { $0.0 === button })?.1 else { return }
        terminal?.keyboardState.toggle(modifier, lock: true); UIImpactFeedbackGenerator(style: .light).impactOccurred(); refresh()
    }
    func refresh() {
        guard let terminal else { return }
        for (button, modifier) in modifierButtons {
            button.isSelected = terminal.keyboardState.active.contains(modifier)
            button.configuration?.baseBackgroundColor = button.isSelected ? .systemBlue : .secondarySystemFill
            button.configuration?.baseForegroundColor = button.isSelected ? .white : .label
            button.accessibilityValue = terminal.keyboardState.locked.contains(modifier) ? "Locked" : (button.isSelected ? "Next key" : "Off")
        }
    }
    private func send(_ key: TerminalAccessoryKey) {
        guard let terminal else { return }
        terminal.send(data: key.bytes(modifiers: terminal.keyboardState.consume(), applicationCursor: terminal.getTerminal().applicationCursor)[...]); refresh()
    }
}
#endif
