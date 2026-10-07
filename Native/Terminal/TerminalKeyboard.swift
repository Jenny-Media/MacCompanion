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

@MainActor final class TerminalKeyboardAccessory: UIInputView {
    weak var terminal: SessionTerminalView?
    var customize: (() -> Void)?
    private let rows = UIStackView()
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    private var height: CGFloat = 100
    init(terminal: SessionTerminalView, preferences: TerminalKeyboardPreferences) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 100), inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.distribution = .fillEqually; rows.spacing = 4; rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: topAnchor, constant: 4), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
        let numbers = row(); for number in ["1","2","3","4","5","6","7","8","9","0"] { numbers.addArrangedSubview(button(number) { [weak terminal] in terminal?.insertText(number) }) }
        let controls = row()
        controls.addArrangedSubview(button("Esc") { [weak self] in self?.send(.escape) })
        controls.addArrangedSubview(button("Tab") { [weak self] in self?.send(.tab) })
        for (title, modifier) in [("Ctrl", TerminalModifiers.ctrl), ("Alt", .alt)] {
            let value = button(title) { [weak self] in self?.toggle(modifier) }; modifierButtons.append((value, modifier))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))); value.addGestureRecognizer(hold)
            controls.addArrangedSubview(value)
        }
        for key in [TerminalAccessoryKey.left, .down, .up, .right] { controls.addArrangedSubview(button(key.title) { [weak self] in self?.send(key) }) }
        let more = button("Fn") {}; more.showsMenuAsPrimaryAction = true
        more.accessibilityLabel = "Extra Terminal Keys"
        var menu = [UIMenu(title: "Navigation & Function Keys", children: TerminalAccessoryKey.allCases.filter { ![.escape, .tab, .left, .right, .up, .down].contains($0) }.map { key in UIAction(title: key.title) { [weak self] _ in self?.send(key) } }),
            UIMenu(title: "Shortcuts", children: [("Interrupt · Ctrl-C", "c"), ("End Input · Ctrl-D", "d"), ("Suspend · Ctrl-Z", "z")].map { title, text in UIAction(title: title) { [weak terminal] _ in terminal?.resetModifiers(); terminal?.send(data: TerminalKeyboardState.text(text, modifiers: .ctrl)[...]) } }),
            UIMenu(title: "Keyboard", children: [UIAction(title: "Shift for Next Key") { [weak self] _ in self?.toggle(.shift) }, UIAction(title: "Lock/Unlock Shift") { [weak self] _ in self?.terminal?.keyboardState.toggle(.shift, lock: true); self?.refresh() }, UIAction(title: "Copy Selection") { [weak terminal] _ in terminal?.copy(nil) }, UIAction(title: "Paste") { [weak terminal] _ in terminal?.resetModifiers(); terminal?.paste(nil) }, UIAction(title: "Customize Keys & Snippets") { [weak self] _ in self?.customize?() }, UIAction(title: "Hide Keyboard", image: UIImage(systemName: "keyboard.chevron.compact.down")) { [weak terminal] _ in _ = terminal?.resignFirstResponder() }])]
        if DirectProAccess.shared.hasPro, !preferences.snippets.isEmpty {
            menu.insert(UIMenu(title: "Saved Snippets", children: preferences.snippets.map { snippet in UIAction(title: snippet.name) { [weak terminal] _ in
                guard DirectProAccess.shared.hasPro, let terminal else { return }; terminal.resetModifiers()
                let text = terminal.getTerminal().bracketedPasteMode ? "\u{1b}[200~" + snippet.text + "\u{1b}[201~" : snippet.text
                terminal.send(data: Array(text.utf8)[...])
            } }), at: 1)
        }
        more.menu = UIMenu(children: menu); controls.addArrangedSubview(more)
        if DirectProAccess.shared.hasPro, !preferences.keys.isEmpty {
            let custom = row(); height = 148; frame.size.height = height
            for key in preferences.keys { custom.addArrangedSubview(button(key.title) { [weak self] in guard DirectProAccess.shared.hasPro else { return }; self?.send(key) }) }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    private func row() -> UIStackView { let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 3; rows.addArrangedSubview(row); return row }
    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray(); configuration.title = title; configuration.cornerStyle = .medium
        configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { value in var value = value; value.font = UIFont.systemFont(ofSize: 13, weight: .medium); return value }
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
