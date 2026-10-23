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
    var symbol: String { self == .ctrl ? "control" : self == .alt ? "option" : self == .command ? "command" : "shift" }
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
    var terminalShortcutValid: Bool {
        if valid { return true }
        var check = self; check.key = 0x61
        return kind == .shortcut && check.valid && TerminalAccessoryKey.allCases.contains { $0.shortcutCode == key }
    }
    func terminalBytes(applicationCursor: Bool = false) -> [UInt8] {
        terminalBytes(encoding: .init(applicationCursor: applicationCursor))
    }
    func terminalBytes(encoding: TerminalKeyEncoding) -> [UInt8] {
        guard kind == .shortcut, terminalShortcutValid, compatible(with: .terminal) else { return [] }
        var flags: TerminalModifiers = []
        if modifiers.contains(0xffe1) { flags.insert(.shift) }
        if modifiers.contains(0xffe3) { flags.insert(.ctrl) }
        if modifiers.contains(0xffe9) { flags.insert(.alt) }
        if modifiers.contains(0xffeb) { flags.insert(.command) }
        if key == 0xff08 { return encoding.bytes(.backspace, modifiers: flags) }
        if let special = TerminalAccessoryKey.allCases.first(where: { $0.shortcutCode == key }) { return encoding.bytes(.accessory(special), modifiers: flags) }
        if key == 0xff0d { return encoding.bytes(.enter, modifiers: flags) }
        guard let scalar = UnicodeScalar(key) else { return [] }
        return encoding.bytes(.text(String(scalar)), modifiers: flags)
    }
}

enum TerminalAccessoryKey: String, Codable, CaseIterable, Identifiable {
    case escape, tab, up, down, left, right, home, end, pageUp, pageDown, insert, delete, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    var id: String { rawValue }
    var shortcutCode: UInt32 {
        switch self {
        case .escape: return 0xff1b; case .tab: return 0xff09
        case .left: return 0xff51; case .up: return 0xff52; case .right: return 0xff53; case .down: return 0xff54
        case .home: return 0xff50; case .end: return 0xff57; case .pageUp: return 0xff55; case .pageDown: return 0xff56
        case .insert: return 0xff63; case .delete: return 0xffff
        default: return 0xffbe + UInt32(Self.allCases.filter { $0.rawValue.hasPrefix("f") }.firstIndex(of: self)!)
        }
    }
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
/// Use the same opaque selection color in the bar and All Keys. A gray button
/// configuration transforms its base color into a pale tint, obscuring state.
enum TerminalModifierAppearance {
    static let fill = UIColor { traits in
        if traits.accessibilityContrast == .high { return UIColor(red: 0, green: 0.27, blue: 0.68, alpha: 1) }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.39, blue: 0.88, alpha: 1)
            : UIColor(red: 0, green: 0.34, blue: 0.80, alpha: 1)
    }
}

private final class TerminalModifierKeyButton: UIButton {
    private let heldMark = UIView()
    private var active = false
    private var modifierHeld = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        heldMark.isUserInteractionEnabled = false
        heldMark.isAccessibilityElement = false
        heldMark.layer.cornerRadius = 1.5
        addSubview(heldMark)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showState(active: Bool, held: Bool) {
        self.active = active; modifierHeld = held
        isSelected = active
        setNeedsUpdateConfiguration()
    }
    override func updateConfiguration() {
        super.updateConfiguration()
        guard var value = configuration else { return }
        value.subtitle = nil; value.attributedSubtitle = nil
        value.automaticallyUpdateForSelection = false
        value.baseForegroundColor = active ? .white : .systemBlue
        value.imageColorTransformer = UIConfigurationColorTransformer { [active] _ in active ? .white : .systemBlue }
        value.background.backgroundColor = active ? TerminalModifierAppearance.fill : .secondarySystemBackground
        value.background.backgroundColorTransformer = UIConfigurationColorTransformer { $0 }
        value.background.strokeColor = active ? TerminalModifierAppearance.fill : .clear
        value.background.strokeWidth = active ? 1.5 : 0
        value.background.cornerRadius = 8; value.cornerStyle = .fixed
        configuration = value
        heldMark.backgroundColor = .white
        heldMark.isHidden = !modifierHeld
        bringSubviewToFront(heldMark)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        heldMark.frame = CGRect(x: (bounds.width - 14) / 2, y: bounds.height - 7, width: 14, height: 3)
        bringSubviewToFront(heldMark)
    }
}

struct TerminalRowScrollPosition {
    var offset: CGFloat
    var rightEdge: Bool
}

private final class TerminalKeyScrollView: UIScrollView {
    private let canvas = UIView()
    private var positioning: [NSLayoutConstraint] = []
    private weak var keyStack: UIStackView?
    private var pending: TerminalRowScrollPosition?
    private var resizingPosition: TerminalRowScrollPosition?
    private var lastWidth: CGFloat = 0
    private var lastMaximum: CGFloat = 0
    private var pinnedRight = false
    private var alignment = TerminalKeyboardRow.Alignment.left
    private var fillKeys: [ObjectIdentifier] = []
    private var fillConstraints: [NSLayoutConstraint] = []
    var position: TerminalRowScrollPosition {
        pending ?? resizingPosition ?? .init(offset: contentOffset.x, rightEdge: lastMaximum > 0 ? abs(contentOffset.x - lastMaximum) < 1 : pinnedRight)
    }
    // UIScrollView can clamp its offset before layoutSubviews runs. Snapshot
    // the visible edge before either manual frames or Auto Layout resize it.
    override var frame: CGRect {
        willSet { if abs(newValue.width - frame.width) > 0.5 { prepareResize() } }
    }
    override var bounds: CGRect {
        willSet { if abs(newValue.width - bounds.width) > 0.5 { prepareResize() } }
    }
    private func prepareResize() {
        guard lastWidth > 0, pending == nil, resizingPosition == nil, !isDragging, !isDecelerating else { return }
        resizingPosition = position
    }
    func install(_ stack: UIStackView) {
        keyStack = stack
        showsHorizontalScrollIndicator = true; alwaysBounceHorizontal = true
        canvas.translatesAutoresizingMaskIntoConstraints = false; addSubview(canvas)
        stack.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(stack)
        let fit = canvas.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor); fit.priority = .defaultHigh
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor), canvas.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            canvas.widthAnchor.constraint(greaterThanOrEqualTo: frameLayoutGuide.widthAnchor), fit,
            canvas.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            stack.topAnchor.constraint(equalTo: canvas.topAnchor), stack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor), stack.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor)])
        align(.left)
    }
    func align(_ alignment: TerminalKeyboardRow.Alignment, startsAtRight: Bool = false, restoring: TerminalRowScrollPosition? = nil) {
        guard let stack = keyStack else { return }
        NSLayoutConstraint.deactivate(positioning)
        self.alignment = alignment
        NSLayoutConstraint.deactivate(fillConstraints); fillConstraints = []; fillKeys = []
        stack.distribution = .fill
        switch alignment {
        case .left: positioning = [stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor)]
        case .center: positioning = [stack.centerXAnchor.constraint(equalTo: canvas.centerXAnchor)]
        case .right: positioning = [stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)]
        case .fill: positioning = [stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)]
        }
        NSLayoutConstraint.activate(positioning)
        pending = restoring ?? .init(offset: 0, rightEdge: startsAtRight)
        pinnedRight = pending!.rightEdge
        setNeedsLayout()
    }
    func updateFill() {
        guard let stack = keyStack else { return }
        let visible = alignment == .fill ? stack.arrangedSubviews.filter { !$0.isHidden } : []
        let identifiers = visible.map(ObjectIdentifier.init)
        guard identifiers != fillKeys else { return }
        NSLayoutConstraint.deactivate(fillConstraints); fillConstraints = []; fillKeys = identifiers
        guard let first = visible.first else { return }
        // Prefer equal widths while the row fits. The viewport's stronger fit
        // constraint wins on overflow, leaving each key at its natural minimum.
        fillConstraints = visible.dropFirst().map { key in
            let constraint = key.widthAnchor.constraint(equalTo: first.widthAnchor)
            constraint.priority = .init(1); return constraint
        }
        NSLayoutConstraint.activate(fillConstraints)
    }
    override func layoutSubviews() {
        let wasRight = lastMaximum > 0 ? abs(contentOffset.x - lastMaximum) < 1 : pinnedRight
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let maximum = max(0, contentSize.width - bounds.width)
        let restore = pending ?? resizingPosition
        let resized = abs(lastWidth - bounds.width) > 0.5 || abs(lastMaximum - maximum) > 0.5
        lastWidth = bounds.width; lastMaximum = maximum; pending = nil; resizingPosition = nil
        if let restore {
            pinnedRight = restore.rightEdge
            setContentOffset(.init(x: restore.rightEdge ? maximum : min(maximum, max(0, restore.offset)), y: 0), animated: false)
        } else if resized && !isDragging && !isDecelerating {
            pinnedRight = wasRight
            setContentOffset(.init(x: wasRight ? maximum : min(maximum, max(0, contentOffset.x)), y: 0), animated: false)
        }
    }
    override func touchesShouldCancel(in view: UIView) -> Bool { view is UIButton || super.touchesShouldCancel(in: view) }
}

@MainActor final class TerminalKeyboardBar: UIView, UIDragInteractionDelegate, UIDropInteractionDelegate {
    weak var terminal: SessionTerminalView?
    var remoteInput: TerminalRemoteInput?
    lazy var keyFeedback = CompanionVNCInterfaceFeedback(view: self)
    private let rows = UIStackView()
    private let row = UIStackView()
    private let keys = UIStackView()
    private var extraViews: [UIView] = []
    private var generated: [UIButton] = []
    private var modifierButtons: [(UIButton, TerminalModifiers)] = []
    var renderedModifiers: [UIButton] { modifierButtons.map { $0.0 } }
    private var commandShortcuts: [UIButton] = []
    private var keyWidths: [ObjectIdentifier: NSLayoutConstraint] = [:]
    private var keySymbols: [ObjectIdentifier: String] = [:]
    private var heights: [NSLayoutConstraint] = []
    private var viewportConstraints: [NSLayoutConstraint] = []
    private var keyHeight: CGFloat = 44
    private var keyboardFocused: Bool?
    let keyboardButton = UIButton(type: .system)
    let keypadButton = UIButton(type: .system)
    let expandButton = UIButton(type: .system)
    let menuAnchor = UIView()
    private var menuAnchorWidth: NSLayoutConstraint?
    private let keyViewport = TerminalKeyScrollView()
    var keyScroll: UIScrollView { keyViewport }
    var editingPreview = false {
        didSet {
            guard oldValue != editingPreview else { return }
            // The runtime bar participates in its controller's Auto Layout.
            // A SwiftUI preview receives measured bounds instead; don't let a
            // template's intrinsic width expand that viewport during sizing.
            if editingPreview { NSLayoutConstraint.deactivate(viewportConstraints) }
            rows.translatesAutoresizingMaskIntoConstraints = editingPreview
            if !editingPreview { NSLayoutConstraint.activate(viewportConstraints) }
            setNeedsLayout()
        }
    }
    var selectedPreviewItem: TerminalBarItem?
    var selectedPreviewRow: UUID?
    var previewPlacementSelect: ((TerminalBarPlacement, UUID) -> Void)?
    var previewPlacementMove: ((String, UUID, UUID, String?) -> Void)?
    var previewPlacementRemove: ((String, UUID) -> Void)?
    var previewPlacementAdd: ((TerminalBarItem, UUID, String?) -> Void)?
    var previewSelect: ((TerminalBarItem?, UUID) -> Void)?
    var previewMove: ((TerminalBarItem, UUID, UUID, TerminalBarItem?) -> Void)?
    var previewRemove: ((TerminalBarItem, UUID) -> Void)?
    var previewSelectRow: ((UUID) -> Void)?
    var previewAddToRow: ((UUID) -> Void)?
    var previewRowAction: ((UUID, TerminalKeyboardRow.MenuAction) -> Void)?
    var previewMoveRow: ((UUID, UUID?) -> Void)?
    var previewAddPreset: ((TerminalRowPreset, UUID?) -> Void)?
    var previewAddItem: ((TerminalBarItem, UUID, TerminalBarItem?) -> Void)?
    var previewCatalogDragBegan: (() -> Void)?
    var previewShowsAllRows = false
    var previewShowsRowHandles = false
    /// Docked preview shares live geometry, but cannot edit or send input.
    var presentationPreview = false
    var previewPreset: TerminalRowPreset?
    var previewUnavailableItems: Set<TerminalBarItem> = []
    var previewCanAddPreset = true
    private enum DragContent { case item(TerminalBarPlacement, UUID), row(UUID), preset(TerminalRowPreset), catalogItem(TerminalBarItem) }
    private var previewItems: [ObjectIdentifier: TerminalBarItem] = [:]
    private var previewPlacements: [ObjectIdentifier: TerminalBarPlacement] = [:]
    private var rowScrollViews: [UUID: TerminalKeyScrollView] = [:]
    private var keyboardToggles: [UIButton] = []
    private var keypadToggles: [UIButton] = []
    private var expandToggles: [UIButton] = []
    private var previewRows: [ObjectIdentifier: UUID] = [:]
    private var previewHandles: Set<ObjectIdentifier> = []
    private var rowContainers: [UUID: UIView] = [:]
    private let dropIndicator = UIView()
    private struct DropPosition: Equatable {
        let row: UUID?
        let before: String?
    }
    private var feedbackPosition: DropPosition?
    private struct RowReorder {
        let source: UUID
        let lifted: UIView
        let touchOffset: CGFloat
        var before: UUID?
    }
    private var rowReorder: RowReorder?
    private var rowPans: [UIPanGestureRecognizer] = []
    private weak var activeRowPan: UIPanGestureRecognizer?
    private var rowScrollLink: CADisplayLink?
    private var profileRows: [TerminalKeyboardRow] = []
    private var layoutGeneration = UUID()
    private var revealedPreviewSelection: String?
    private var revealPreviewSelection = false
    var layoutChanged: (() -> Void)?
    var toggleKeyboard: (() -> Void)?
    var openKeypad: ((Bool) -> Void)?
    var showsNavigation = true
    var showsExtraRows = false { didSet { updateVisibility() } }
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
        viewportConstraints = [
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 4), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)]
        NSLayoutConstraint.activate(viewportConstraints)
        row.axis = .horizontal; row.spacing = 4
        for item in [keyScroll, menuAnchor] { row.addArrangedSubview(item) }
        menuAnchor.isUserInteractionEnabled = false
        menuAnchorWidth = menuAnchor.widthAnchor.constraint(equalToConstant: 52)
        menuAnchorWidth?.isActive = true
        configureButton(keyboardButton, title: "Show Keyboard", symbol: "keyboard")
        keyboardButton.accessibilityIdentifier = "terminal-keyboard-toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in
            self?.performKeyboardToggle()
        }, for: .touchUpInside)
        configureButton(expandButton, title: "Expand Rows", symbol: "rectangle.expand.vertical")
        expandButton.accessibilityIdentifier = "terminal-row-expand"
        expandButton.addAction(UIAction { [weak self] _ in
            self?.performExpandToggle()
        }, for: .touchUpInside)
        configureButton(keypadButton, title: "Open Keypad", symbol: "rectangle.grid.3x2")
        keypadButton.accessibilityIdentifier = "terminal-keypad-toggle"
        keypadButton.addAction(UIAction { [weak self] _ in self?.openKeypad?(false) }, for: .touchUpInside)
        keys.axis = .horizontal; keys.spacing = 3
        keyViewport.install(keys)
        keyScroll.accessibilityIdentifier = "terminal-modifier-keys"; keyScroll.accessibilityLabel = "Terminal keys"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: TerminalKeyboardBar, _: UITraitCollection) in bar.updateKeyMetrics() }
        configure(preferences)
    }
    func configure(_ preferences: TerminalKeyboardPreferences) {
        var profile = TerminalControlsProfile.defaults
        profile.actions += preferences.keys.map { .init(title: $0.title, kind: .key, key: $0, inRow: true, inMenu: false) }
        configure(profile) { _ in }
    }
    func configure(_ profile: TerminalControlsProfile, perform: @escaping (UUID) -> Void) {
        let positions = rowScrollViews.mapValues(\.position)
        let previousRows = profileRows
        rowScrollViews = [:]; keyboardToggles = []; keypadToggles = []; expandToggles = []
        var usedIdentifiers = Set<String>()
        let selection = editingPreview ? selectedPreviewItem.map { (selectedPreviewRow?.uuidString ?? "") + $0.id + $0.title(in: profile) } : nil
        revealPreviewSelection = selection != nil && selection != revealedPreviewSelection
        revealedPreviewSelection = selection
        layoutGeneration = UUID()
        for key in generated { keyWidths.removeValue(forKey: ObjectIdentifier(key)); keySymbols.removeValue(forKey: ObjectIdentifier(key)) }
        generated = []; modifierButtons = []; commandShortcuts = []
        for view in row.arrangedSubviews where view !== keyScroll && view !== menuAnchor { row.removeArrangedSubview(view); view.removeFromSuperview() }
        previewItems = [:]; previewPlacements = [:]; previewRows = [:]; previewHandles = []; rowContainers = [:]; profileRows = profile.resolvedRows.map { source in var row = source; row.items = profile.barItems(in: source); row.title = profile.rowTitle(row.id); return row }
        finishRowReorder(commit: false)
        rowPans = []
        dropIndicator.removeFromSuperview()
        for stack in [keys] { for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() } }
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        heights.forEach { $0.isActive = false }; heights = []; extraViews = []
        for definition in profileRows {
            let stack: UIStackView, scroll: TerminalKeyScrollView, container: UIView
            if definition.kind == .main { stack = keys; scroll = keyViewport; container = row }
            else {
                scroll = TerminalKeyScrollView(); stack = UIStackView()
                stack.axis = .horizontal; stack.spacing = 3
                scroll.install(stack)
                scroll.accessibilityIdentifier = "terminal-extra-row-" + definition.id.uuidString
                if definition.kind == .navigation { stack.accessibilityIdentifier = "terminal-navigation-row" }
                container = scroll
            }
            let previous = previousRows.first { $0.id == definition.id }
            let retained = previous?.resolvedAlignment == definition.resolvedAlignment && previous?.scrollStart == definition.scrollStart ? positions[definition.id] : nil
            scroll.align(definition.resolvedAlignment, startsAtRight: definition.startsAtRight, restoring: retained)
            rowScrollViews[definition.id] = scroll
            if definition.extra { extraViews.append(container) }
            if editingPreview && !presentationPreview {
                scroll.accessibilityIdentifier = definition.kind == .main ? "terminal-row-preview-scroll" : "terminal-row-preview-scroll-" + definition.id.uuidString
                previewRows[ObjectIdentifier(scroll)] = definition.id
                if scroll.interactions.allSatisfy({ !($0 is UIDropInteraction) }) { scroll.addInteraction(UIDropInteraction(delegate: self)) }
                scroll.layer.borderWidth = 0
                scroll.layer.borderColor = UIColor.tintColor.cgColor; scroll.layer.cornerRadius = 8
            }
            for placement in profile.barPlacements(in: definition) {
                let item = placement.item
                if item.savedID != nil, !editingPreview && !DirectProAccess.shared.hasPro { continue }
                let title = item.title(in: profile)
                let savedAction = item.savedID.flatMap { id in profile.actions.first { $0.id == id } }
                let key: UIButton
                if !editingPreview, let control = item.control {
                    switch control {
                    case .keyboard:
                        if keyboardToggles.isEmpty { key = keyboardButton }
                        else { key = button(title, symbol: "keyboard") { [weak self] in self?.performKeyboardToggle() } }
                        keyboardToggles.append(key)
                    case .retiredNumbers: continue
                    case .keypad:
                        key = button(title, symbol: item.symbol) { [weak self] in self?.openKeypad?(false) }; keypadToggles.append(key)
                    case .expand:
                        if expandToggles.isEmpty { key = expandButton }
                        else { key = button(title, symbol: item.symbol) { [weak self] in self?.performExpandToggle() } }
                        expandToggles.append(key)
                    default: key = button(title, symbol: item.symbol, modifier: item.modifier != nil) { [weak self] in if let modifier = item.modifier { self?.toggle(modifier) } }
                    }
                } else {
                    key = button(savedAction?.keycapTitle ?? item.palette?.title ?? title, symbol: item.symbol ?? (savedAction?.isLocalKeyboardControl == true ? savedAction?.symbol : nil), modifier: item.modifier != nil) { [weak self] in
                        guard let self else { return }
                        if editingPreview {
                            if let previewPlacementSelect { previewPlacementSelect(placement, definition.id) }
                            else { previewSelect?(item, definition.id) }
                        }
                        else if let id = item.savedID { guard inputReady || savedAction?.isLocalKeyboardControl == true, DirectProAccess.shared.hasPro else { return }; perform(id) }
                        else if let palette = item.palette { send(palette) }
                    }
                }
                if !editingPreview, savedAction?.isLocalKeyboardControl == true {
                    if savedAction?.operation == .keyboard { keyboardToggles.append(key) }
                    else { expandToggles.append(key) }
                }
                if editingPreview, item.control == .expand { expandToggles.append(key) }
                key.accessibilityLabel = title
                key.tag = Int(item.palette?.shortcutCode ?? (item.modifier == .ctrl ? 0xffe3 : item.modifier == .alt ? 0xffe9 : item.modifier == .shift ? 0xffe1 : item.modifier == .command ? 0xffeb : 0))
                if let action = item.savedID.flatMap({ id in profile.actions.first { $0.id == id } }) { key.accessibilityHint = ([action.detail] + [action.usage].compactMap { $0 }).joined(separator: ". ") }
                if let modifier = item.modifier {
                    modifierButtons.append((key, modifier))
                    if !editingPreview {
                        key.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(lockModifier(_:))))
                        key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Keep " + title + " On", actionHandler: { [weak self] _ in self?.toggle(modifier, lock: true); return true })]
                    }
                }
                if let id = item.savedID {
                    key.accessibilityIdentifier = (editingPreview ? "terminal-row-preview-" : "terminal-row-action-") + id.uuidString
                    if profile.actions.first(where: { $0.id == id })?.requiresCommand == true { commandShortcuts.append(key) }
                }
                if editingPreview && !presentationPreview {
                    if item.savedID == nil { key.accessibilityIdentifier = previewPreset.map { "terminal-template-item-" + $0.id + "-" + item.id } ?? "terminal-preview-item-" + item.id }
                    key.accessibilityValue = previewUnavailableItems.contains(item) ? "Already placed" : selectedPreviewItem == item && selectedPreviewRow == definition.id ? "Selected" : nil
                    key.alpha = previewUnavailableItems.contains(item) ? 0.3 : 1
                    key.configuration?.background.backgroundColor = .secondarySystemBackground
                    key.layer.borderWidth = selectedPreviewItem == item && selectedPreviewRow == definition.id ? 1.5 : 0
                    key.layer.borderColor = UIColor.systemBlue.cgColor; key.layer.cornerRadius = 8
                    previewItems[ObjectIdentifier(key)] = item; previewPlacements[ObjectIdentifier(key)] = placement; previewRows[ObjectIdentifier(key)] = definition.id
                    let drag = UIDragInteraction(delegate: self); drag.isEnabled = true
                    key.addInteraction(drag); key.addInteraction(UIDropInteraction(delegate: self))
                    let items = profile.barPlacements(in: definition)
                    key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Remove from Keyboard Bar", actionHandler: { [weak self] _ in if let callback = self?.previewPlacementRemove { callback(placement.id, definition.id) } else { self?.previewRemove?(item, definition.id) }; return true })] + [-1, 1].map { offset in
                        UIAccessibilityCustomAction(name: offset < 0 ? "Move Earlier" : "Move Later", actionHandler: { [weak self] _ in
                            guard let index = items.firstIndex(where: { $0.id == placement.id }), items.indices.contains(index + offset) else { return false }
                            let before = offset < 0 ? items[index - 1] : (items.indices.contains(index + 2) ? items[index + 2] : nil)
                            if let callback = self?.previewPlacementMove { callback(placement.id, definition.id, definition.id, before?.id) } else { self?.previewMove?(item, definition.id, definition.id, before?.item) }; return true
                        })
                    } + profileRows.map { target in
                        UIAccessibilityCustomAction(name: "Move to " + target.title, actionHandler: { [weak self] _ in if let callback = self?.previewPlacementMove { callback(placement.id, definition.id, target.id, nil) } else { self?.previewMove?(item, definition.id, target.id, nil) }; return true })
                    }
                    if previewPreset != nil {
                        key.accessibilityCustomActions = nil
                        key.accessibilityHint = previewUnavailableItems.contains(item) ? "This key is already in your keyboard bar." : "Drag into a keyboard row, or use Add to Keyboard Bar to place this key."
                    }
                }
                if let identifier = key.accessibilityIdentifier, !usedIdentifiers.insert(identifier).inserted { key.accessibilityIdentifier = identifier + "-" + placement.id }
                stack.addArrangedSubview(key)
            }
            if stack.arrangedSubviews.isEmpty && editingPreview && !presentationPreview {
                let label = UILabel(); label.text = editingPreview ? "Empty row · use Add" : definition.title
                label.font = .preferredFont(forTextStyle: .caption1); stack.addArrangedSubview(label)
            }
            let displayed: UIView
            if editingPreview && previewShowsRowHandles {
                let handle = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.title = nil
                configuration.subtitle = nil
                configuration.image = UIImage(systemName: previewPreset == nil ? "line.3.horizontal" : "plus.circle")
                configuration.baseForegroundColor = previewPreset == nil ? .secondaryLabel : .systemBlue
                configuration.preferredSymbolConfigurationForImage = .init(pointSize: 14, weight: .medium)
                configuration.imagePadding = 3; configuration.contentInsets = .init(top: 0, leading: 2, bottom: 0, trailing: 2)
                configuration.titleTextAttributesTransformer = .init { attributes in var result = attributes; result.font = .preferredFont(forTextStyle: .caption2); return result }
                configuration.subtitleTextAttributesTransformer = .init { attributes in var result = attributes; result.font = .preferredFont(forTextStyle: .caption2); result.foregroundColor = .secondaryLabel; return result }
                handle.configuration = configuration
                handle.accessibilityIdentifier = previewPreset.map { "terminal-preset-add-" + $0.id } ?? "terminal-row-handle-" + definition.id.uuidString
                handle.accessibilityLabel = previewPreset.map { "Add " + $0.rawValue + " Row" } ?? "Reorder " + definition.title
                handle.accessibilityHint = previewPreset == nil ? "Drag to reorder the whole row, or use the Move Row accessibility actions." : "Drag this row into your keyboard, or tap to add."
                handle.accessibilityValue = selectedPreviewItem == nil && selectedPreviewRow == definition.id ? "Selected" : nil
                handle.widthAnchor.constraint(equalToConstant: previewAddToRow == nil ? 44 : 32).isActive = true
                let generation = layoutGeneration
                if previewPreset != nil {
                    handle.addAction(UIAction { [weak self] _ in
                        guard let self, self.layoutGeneration == generation, let preset = self.previewPreset, self.previewCanAddPreset else { return }
                        self.previewAddPreset?(preset, nil)
                    }, for: .touchUpInside)
                } else { handle.accessibilityTraits = [] }
                handle.isEnabled = previewPreset == nil || previewCanAddPreset
                previewRows[ObjectIdentifier(handle)] = definition.id; previewHandles.insert(ObjectIdentifier(handle))
                if previewPreset != nil {
                    let drag = UIDragInteraction(delegate: self); drag.isEnabled = true; handle.addInteraction(drag)
                } else {
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(reorderRow(_:)))
                    pan.maximumNumberOfTouches = 1; handle.addGestureRecognizer(pan); rowPans.append(pan)
                }
                handle.addInteraction(UIDropInteraction(delegate: self))
                handle.accessibilityCustomActions = [-1, 1].map { offset in
                    UIAccessibilityCustomAction(name: offset < 0 ? "Move Row Up" : "Move Row Down", actionHandler: { [weak self] _ in
                        guard let self, let index = self.profileRows.firstIndex(where: { $0.id == definition.id }), self.profileRows.indices.contains(index + offset) else { return false }
                        let target = offset < 0 ? self.profileRows[index - 1].id : (self.profileRows.indices.contains(index + 2) ? self.profileRows[index + 2].id : nil)
                        self.previewMoveRow?(definition.id, target); return true
                    })
                }
                let wrapper = UIStackView(arrangedSubviews: [handle, container]); wrapper.axis = .horizontal; wrapper.spacing = 3
                if previewPreset == nil, previewAddToRow != nil {
                    let add = UIButton(type: .system)
                    let hasMenu = previewRowAction != nil
                    var configuration = UIButton.Configuration.plain(); configuration.image = UIImage(systemName: hasMenu ? "ellipsis" : "plus")
                    configuration.preferredSymbolConfigurationForImage = .init(pointSize: 20, weight: .regular)
                    add.configuration = configuration; add.widthAnchor.constraint(equalToConstant: 32).isActive = true
                    add.accessibilityLabel = hasMenu ? "Row Options for " + definition.title : "Add to " + definition.title + " Row"
                    add.accessibilityIdentifier = (hasMenu ? "terminal-row-menu-" : "terminal-add-to-row-") + definition.id.uuidString
                    if hasMenu {
                        add.menu = editorRowMenu(definition)
                        add.showsMenuAsPrimaryAction = true
                    } else {
                        add.addAction(UIAction { [weak self] _ in
                            guard let self, self.layoutGeneration == generation else { return }
                            self.previewAddToRow?(definition.id)
                        }, for: .touchUpInside)
                    }
                    if definition.kind == .main { row.insertArrangedSubview(add, at: 1) }
                    else { wrapper.addArrangedSubview(add) }
                }
                wrapper.layer.cornerRadius = 8
                wrapper.layer.borderColor = UIColor.systemBlue.cgColor
                wrapper.layer.borderWidth = selectedPreviewItem == nil && selectedPreviewRow == definition.id ? 1.5 : 0
                displayed = wrapper
            } else { displayed = container }
            rowContainers[definition.id] = displayed
            rows.addArrangedSubview(displayed)
            let constraint = displayed.heightAnchor.constraint(equalToConstant: keyHeight); constraint.priority = UILayoutPriority(999); constraint.isActive = true; heights.append(constraint)
        }
        showsExtraRows = profile.rowsExpanded ?? false
        updateVisibility(); setKeyboardFocused(keyboardFocused ?? false); refresh()
        prioritizeRowPans()
    }
    private func editorRowMenu(_ definition: TerminalKeyboardRow) -> UIMenu {
        let generation = layoutGeneration
        let add = UIAction(title: "Add Key", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self, self.layoutGeneration == generation else { return }
            self.previewAddToRow?(definition.id)
        }
        var settings: [UIMenuElement] = []
        let alignmentChoices = TerminalKeyboardRow.Alignment.allCases.map { alignment in
            UIAction(title: alignment.rawValue, image: UIImage(systemName: alignment.symbol), state: definition.resolvedAlignment == alignment ? .on : .off) { [weak self] _ in
                guard let self, self.layoutGeneration == generation else { return }
                self.previewRowAction?(definition.id, .alignment(alignment))
            }
        }
        let starts = TerminalKeyboardRow.ScrollStart.allCases.map { start in
            UIAction(title: start.rawValue, state: (definition.scrollStart ?? .automatic) == start ? .on : .off) { [weak self] _ in
                guard let self, self.layoutGeneration == generation else { return }; self.previewRowAction?(definition.id, .scrollStart(start))
            }
        }
        settings.append(UIMenu(title: "Scroll Start", image: UIImage(systemName: "arrow.left.and.right"), options: .singleSelection, children: starts))
        settings.append(UIMenu(title: "Alignment", image: UIImage(systemName: definition.resolvedAlignment.symbol), options: .singleSelection, children: alignmentChoices))
        if definition.kind != .main {
            let choices = TerminalKeyboardRow.Visibility.allCases.map { visibility in
                UIAction(title: visibility.rawValue, state: definition.visibility == visibility ? .on : .off) { [weak self] _ in
                    guard let self, self.layoutGeneration == generation else { return }
                    self.previewRowAction?(definition.id, .visibility(visibility))
                }
            }
            settings.append(UIMenu(title: "Visibility", image: UIImage(systemName: "eye"), options: .singleSelection, children: choices))
        }
        let remove = UIAction(title: profileRows.count == 1 ? "Clear Row" : "Remove Row", image: UIImage(systemName: "minus.circle"), attributes: .destructive) { [weak self] _ in
            guard let self, self.layoutGeneration == generation else { return }
            self.previewRowAction?(definition.id, .remove)
        }
        let sections = [
            UIMenu(options: .displayInline, children: [add]),
            UIMenu(options: .displayInline, children: settings),
            UIMenu(options: .displayInline, children: [remove])].filter { !$0.children.isEmpty }
        return UIMenu(title: definition.title, children: sections)
    }
    private func prioritizeRowPans() {
        // The dedicated handle owns vertical reordering; scrolling still starts
        // normally everywhere else in the keyboard or catalog.
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView { for pan in rowPans { scroll.panGestureRecognizer.require(toFail: pan) } }
            ancestor = view.superview
        }
    }
    @objc private func reorderRow(_ pan: UIPanGestureRecognizer) {
        guard editingPreview, previewPreset == nil, let handle = pan.view,
              let source = previewRows[ObjectIdentifier(handle)], let container = rowContainers[source] else { return }
        switch pan.state {
        case .began:
            guard let lifted = container.snapshotView(afterScreenUpdates: false) else { return }
            lifted.frame = container.convert(container.bounds, to: self)
            lifted.layer.shadowOpacity = 0.18; lifted.layer.shadowRadius = 8; lifted.layer.cornerRadius = 8
            lifted.isUserInteractionEnabled = false; addSubview(lifted); container.alpha = 0.25
            rowReorder = .init(source: source, lifted: lifted, touchOffset: pan.location(in: self).y - lifted.center.y,
                before: profileRows.drop(while: { $0.id != source }).dropFirst().first?.id)
            activeRowPan = pan
            let link = CADisplayLink(target: self, selector: #selector(scrollReorderingRow(_:)))
            link.add(to: .main, forMode: .common); rowScrollLink = link
            keyFeedback.feedback("selection")
            fallthrough
        case .changed:
            guard var reorder = rowReorder else { return }
            reorder.lifted.center.y = pan.location(in: self).y - reorder.touchOffset
            let remaining = profileRows.filter { $0.id != source }
            let before = remaining.first { row in
                guard let view = rowContainers[row.id] else { return false }
                return reorder.lifted.center.y < view.convert(view.bounds, to: self).midY
            }?.id
            if before != reorder.before { keyFeedback.feedback("selection") }
            reorder.before = before; rowReorder = reorder
            let target = before.flatMap { rowContainers[$0] }
            let y = target.map { $0.convert($0.bounds, to: self).minY } ?? rows.frame.maxY
            dropIndicator.backgroundColor = .systemBlue; dropIndicator.isUserInteractionEnabled = false
            dropIndicator.frame = .init(x: 0, y: y - 2, width: bounds.width, height: 3)
            addSubview(dropIndicator); bringSubviewToFront(reorder.lifted)
        case .ended: finishRowReorder(commit: true)
        case .cancelled, .failed: finishRowReorder(commit: false)
        default: break
        }
    }
    private func finishRowReorder(commit: Bool) {
        rowScrollLink?.invalidate(); rowScrollLink = nil; activeRowPan = nil
        guard let reorder = rowReorder else { return }
        rowReorder = nil; reorder.lifted.removeFromSuperview(); rowContainers[reorder.source]?.alpha = 1
        dropIndicator.removeFromSuperview()
        let originalNext = profileRows.drop(while: { $0.id != reorder.source }).dropFirst().first?.id
        if commit, reorder.before != reorder.source, reorder.before != originalNext, let previewMoveRow {
            previewMoveRow(reorder.source, reorder.before); keyFeedback.feedback("commit")
        }
    }
    @objc private func scrollReorderingRow(_ link: CADisplayLink) {
        guard let pan = activeRowPan, pan.state == .changed else { return }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                let point = pan.location(in: scroll)
                let edge: CGFloat = 30
                let delta: CGFloat = point.y < scroll.bounds.minY + edge ? -4 : point.y > scroll.bounds.maxY - edge ? 4 : 0
                let minimum = -scroll.adjustedContentInset.top
                let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let y = min(maximum, max(minimum, scroll.contentOffset.y + delta))
                if y != scroll.contentOffset.y { scroll.setContentOffset(.init(x: scroll.contentOffset.x, y: y), animated: false); reorderRow(pan) }
                return
            }
            ancestor = view.superview
        }
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard editingPreview, let view = interaction.view, let row = previewRows[ObjectIdentifier(view)] else { return [] }
        let content: DragContent
        if previewHandles.contains(ObjectIdentifier(view)) {
            if let preset = previewPreset { guard previewCanAddPreset else { return [] }; content = .preset(preset) }
            else { content = .row(row) }
        } else if let item = previewPlacements[ObjectIdentifier(view)] {
            guard !previewUnavailableItems.contains(item.item) else { return [] }
            content = previewPreset == nil ? .item(item, row) : .catalogItem(item.item)
        } else { return [] }
        let drag = UIDragItem(itemProvider: NSItemProvider(object: "Terminal keyboard layout" as NSString)); drag.localObject = content; return [drag]
    }
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        switch item.localObject as? DragContent {
        case .row(let row): return rowContainers[row].map { UITargetedDragPreview(view: $0) }
        case .preset: return rowContainers.values.first.map { UITargetedDragPreview(view: $0) }
        default: return nil
        }
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        feedbackPosition = nil
        keyFeedback.feedback("selection")
        // The catalog lives in a popover. Once UIKit owns the lifted preview,
        // dismiss that presentation so its modal hit testing cannot cover the
        // real keyboard rows. The local drag item carries its value with it.
        if previewPreset != nil { previewCatalogDragBegan?() }
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionDidEnd session: UIDragSession, with operation: UIDropOperation) {
        feedbackPosition = nil
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        guard editingPreview, previewPreset == nil, let content = session.items.first?.localObject as? DragContent else { return false }
        if case .preset = content { return profileRows.count < TerminalControlsProfile.maximumKeyboardRows }
        return true
    }
    private func dropTarget(_ interaction: UIDropInteraction, session: UIDropSession) -> (UUID, TerminalBarPlacement?, Bool)? {
        guard let view = interaction.view, let row = previewRows[ObjectIdentifier(view)], let container = rowContainers[row] else { return nil }
        let point = session.location(in: self), frame = container.convert(container.bounds, to: self)
        if case .row = session.items.first?.localObject as? DragContent { return (row, nil, point.y > frame.midY) }
        if case .preset = session.items.first?.localObject as? DragContent { return (row, nil, point.y > frame.midY) }
        if let item = previewPlacements[ObjectIdentifier(view)] {
            let after = session.location(in: view).x > view.bounds.midX
            return (row, item, after)
        }
        // Dropping into the visible whitespace appends to this row.
        return (row, nil, false)
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        guard dropInteraction(interaction, canHandle: session), let (row, item, after) = dropTarget(interaction, session: session), let container = rowContainers[row], let view = interaction.view,
              let index = profileRows.firstIndex(where: { $0.id == row }) else { return UIDropProposal(operation: .forbidden) }
        dropIndicator.backgroundColor = .systemBlue; dropIndicator.layer.cornerRadius = 2; dropIndicator.isUserInteractionEnabled = false
        addSubview(dropIndicator)
        let frame = container.convert(container.bounds, to: self)
        switch session.items.first?.localObject as? DragContent {
        case .row, .preset: dropIndicator.frame = CGRect(x: 0, y: (after ? frame.maxY : frame.minY) - 2, width: bounds.width, height: 4)
        default:
            let cell = view.convert(view.bounds, to: self)
            dropIndicator.frame = CGRect(x: (after ? cell.maxX : cell.minX) - 2, y: frame.minY, width: 4, height: frame.height)
        }
        let position: DropPosition
        switch session.items.first?.localObject as? DragContent {
        case .row, .preset:
            position = .init(row: after ? (profileRows.indices.contains(index + 1) ? profileRows[index + 1].id : nil) : row, before: nil)
        default:
            position = .init(row: row, before: insertionItem(in: profileRows[index], item: item, after: after)?.id)
        }
        if position != feedbackPosition { keyFeedback.feedback("selection"); feedbackPosition = position }
        switch session.items.first?.localObject as? DragContent {
        case .preset, .catalogItem: return UIDropProposal(operation: .copy)
        default: return UIDropProposal(operation: .move)
        }
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { dropIndicator.removeFromSuperview() }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { dropIndicator.removeFromSuperview(); feedbackPosition = nil }
    private func insertionItem(in row: TerminalKeyboardRow, item: TerminalBarPlacement?, after: Bool) -> TerminalBarPlacement? {
        guard after, let item, let index = row.placements.firstIndex(of: item) else { return item }
        return row.placements.indices.contains(index + 1) ? row.placements[index + 1] : nil
    }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        defer { dropIndicator.removeFromSuperview(); feedbackPosition = nil }
        guard dropInteraction(interaction, canHandle: session), let content = session.items.first?.localObject as? DragContent,
              let (row, item, after) = dropTarget(interaction, session: session), let index = profileRows.firstIndex(where: { $0.id == row }) else { return }
        let targetRow = after ? (profileRows.indices.contains(index + 1) ? profileRows[index + 1].id : nil) : row
        let targetItem = insertionItem(in: profileRows[index], item: item, after: after)
        switch content {
        case .row(let source):
            guard let sourceIndex = profileRows.firstIndex(where: { $0.id == source }), let previewMoveRow else { return }
            let next = profileRows.indices.contains(sourceIndex + 1) ? profileRows[sourceIndex + 1].id : nil
            guard targetRow != source, targetRow != next else { return }
            previewMoveRow(source, targetRow)
        case .preset(let preset):
            guard let previewAddPreset else { return }; previewAddPreset(preset, targetRow)
        case .item(let source, let sourceRow):
            guard let sourceItems = profileRows.first(where: { $0.id == sourceRow })?.placements,
                  let sourceIndex = sourceItems.firstIndex(where: { $0.id == source.id }) else { return }
            if sourceRow == row {
                let next = sourceItems.indices.contains(sourceIndex + 1) ? sourceItems[sourceIndex + 1].id : nil
                guard targetItem?.id != source.id, targetItem?.id != next else { return }
            }
            if let previewPlacementMove { previewPlacementMove(source.id, sourceRow, row, targetItem?.id) }
            else if let previewMove { previewMove(source.item, sourceRow, row, targetItem?.item) }
            else { return }
        case .catalogItem(let source):
            if let previewPlacementAdd { previewPlacementAdd(source, row, targetItem?.id) }
            else if let previewAddItem { previewAddItem(source, row, targetItem?.item) }
            else { return }
        }
        keyFeedback.feedback("commit")
    }
    private func send(_ key: TerminalPaletteKey) {
        if let remoteInput { if remoteInput.ready() { remoteInput.send(key) }; refresh(); return }
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
        keyboardFocused = focused
        for key in keyboardToggles {
            key.accessibilityLabel = focused ? "Hide Keyboard" : "Show Keyboard"
            keySymbols[ObjectIdentifier(key)] = focused ? "keyboard.chevron.compact.down" : "keyboard"
        }
        updateKeyMetrics()
    }
    private func updateVisibility() {
        let all = editingPreview && previewShowsAllRows
        for definition in profileRows {
            let hidden = !all && (definition.hidden == true || definition.extra && !showsExtraRows)
            if let container = rowContainers[definition.id], container.isHidden != hidden { container.isHidden = hidden }
        }
        for key in expandToggles {
            key.accessibilityLabel = showsExtraRows ? "Collapse Rows" : "Expand Rows"
            key.accessibilityValue = showsExtraRows ? "Expanded" : "Collapsed"
            key.isHidden = !profileRows.contains { $0.extra && $0.hidden != true }
            keyWidths[ObjectIdentifier(key)]?.isActive = !key.isHidden
        }
        for scroll in rowScrollViews.values { scroll.updateFill() }
        // The session button belongs to the live overlay. Editors have their own
        // trailing row menu and must not show a second, non-interactive button.
        menuAnchorWidth?.isActive = !editingPreview || presentationPreview
        menuAnchor.isHidden = editingPreview && !presentationPreview
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    // The menu lives in a sibling overlay. Finish both nested stacks before
    // that overlay converts its anchor frame after a row-count change.
    func layoutRows() {
        if editingPreview {
            let frame = CGRect(x: 4, y: 4, width: max(0, bounds.width - 8), height: max(0, bounds.height - 8))
            if rows.frame != frame { rows.frame = frame }
        }
        rows.setNeedsLayout(); rows.layoutIfNeeded()
        row.setNeedsLayout(); row.layoutIfNeeded()
        keyScroll.layoutIfNeeded()
        if revealPreviewSelection, let selectedPreviewItem, let selectedPreviewRow,
           let key = generated.first(where: { previewItems[ObjectIdentifier($0)] == selectedPreviewItem && previewRows[ObjectIdentifier($0)] == selectedPreviewRow }),
           let scroll = key.superview?.superview?.superview as? UIScrollView, scroll.bounds.width > 0 {
            revealPreviewSelection = false
            scroll.scrollRectToVisible(key.convert(key.bounds, to: scroll), animated: false)
        }
    }
    override func layoutSubviews() { super.layoutSubviews(); layoutRows() }
    override func didMoveToWindow() { super.didMoveToWindow(); updateKeyMetrics(); prioritizeRowPans(); if window == nil { finishRowReorder(commit: false) } }
    private var keyFont: UIFont { UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .medium), compatibleWith: traitCollection) }
    private var allKeys: [UIButton] { generated + [keyboardButton, keypadButton, expandButton] }
    private func updateKeyMetrics() {
        let font = keyFont
        for key in allKeys {
            if let symbol = keySymbols[ObjectIdentifier(key)] { key.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font)) }
            key.setNeedsUpdateConfiguration(); key.updateConfiguration(); key.titleLabel?.numberOfLines = 1
            let text = (key.configuration?.title ?? "") as NSString
            let width = max(text.size(withAttributes: [.font: font]).width, key.configuration?.image?.size.width ?? 0)
            keyWidths[ObjectIdentifier(key)]?.constant = max(44, ceil(width) + 12)
        }
        keyHeight = max(44, ceil(font.lineHeight) + 8)
        heights.forEach { $0.constant = keyHeight }
        invalidateIntrinsicContentSize(); setNeedsLayout(); superview?.setNeedsLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    private func configureButton(_ key: UIButton, title: String, symbol: String? = nil) {
        var configuration = UIButton.Configuration.plain(); configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 8; configuration.background.backgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .systemBlue
        configuration.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
        configuration.titleLineBreakMode = .byClipping
        if let symbol { keySymbols[ObjectIdentifier(key)] = symbol; configuration.image = UIImage(systemName: symbol) } else { configuration.title = title }
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] value in
            var value = value; value.font = self?.keyFont ?? .systemFont(ofSize: 17, weight: .medium); return value
        }
        key.configuration = configuration; key.titleLabel?.numberOfLines = 1; key.accessibilityLabel = title
        let width = key.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        width.isActive = true; keyWidths[ObjectIdentifier(key)] = width
    }
    private func button(_ title: String, symbol: String? = nil, modifier: Bool = false, action: @escaping () -> Void) -> UIButton {
        let key: UIButton = modifier ? TerminalModifierKeyButton(type: .system) : UIButton(type: .system)
        configureButton(key, title: title, symbol: symbol); generated.append(key)
        let generation = layoutGeneration
        key.addAction(UIAction { [weak self] _ in guard self?.layoutGeneration == generation else { return }; action() }, for: .touchUpInside)
        key.addAction(UIAction { [weak self] _ in if self?.terminal?.customInputEpoch() != nil { self?.keyFeedback.prepareKeyFeedback() } }, for: .touchDown)
        return key
    }
    private func performKeyboardToggle() {
        if let remoteInput { remoteInput.toggleKeyboard(); return }
        guard let terminal else { return }
        let before = terminal.isFirstResponder; toggleKeyboard?()
        if before != terminal.isFirstResponder { keyFeedback.feedback("selection") }
    }
    private func performExpandToggle() {
        showsExtraRows.toggle(); keyFeedback.feedback("selection"); layoutChanged?()
    }
    func toggle(_ modifier: TerminalModifiers, lock: Bool = false) {
        if let remoteInput { guard remoteInput.ready() else { return }; remoteInput.toggle(modifier, lock); keyFeedback.feedback("selection"); refresh(); return }
        guard let terminal, terminal.customInputEpoch() != nil, modifier != .command || terminal.keyEncoding.supportsCommand else { return }
        terminal.keyboardState.toggle(modifier, lock: lock); keyFeedback.feedback("selection"); refresh()
    }
    @objc private func lockModifier(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let key = gesture.view as? UIButton, let modifier = modifierButtons.first(where: { $0.0 === key })?.1 else { return }
        toggle(modifier, lock: true)
    }
    private var inputReady: Bool { remoteInput?.ready() ?? (terminal?.customInputEpoch() != nil) }
    func refresh() {
        guard !editingPreview else { return }
        if let remoteInput {
            let ready = remoteInput.ready(), state = remoteInput.state()
            for key in allKeys { key.isEnabled = ready; key.alpha = ready ? 1 : 0.4 }
            for (key, modifier) in modifierButtons {
                let locked = state.locked.contains(modifier)
                (key as? TerminalModifierKeyButton)?.showState(active: state.active.contains(modifier), held: locked)
                key.accessibilityValue = locked ? "On" : state.active.contains(modifier) ? "Next key" : "Off"
                key.accessibilityHint = "Tap for the next key; long-press to keep on. Tap again to turn off."
            }
            for key in keyboardToggles + expandToggles + keypadToggles + [keypadButton] { key.isEnabled = true; key.alpha = 1 }
            return
        }
        guard let terminal else { return }
        let ready = terminal.customInputEpoch() != nil
        if !terminal.keyEncoding.supportsCommand { terminal.keyboardState.armed.remove(.command); terminal.keyboardState.locked.remove(.command) }
        if !ready { terminal.keyboardState.reset(); terminal.controlModifier = false; terminal.metaModifier = false }
        for key in allKeys { key.isEnabled = ready; key.alpha = ready ? 1 : 0.4 }
        for (key, modifier) in modifierButtons {
            key.isEnabled = ready && (modifier != .command || terminal.keyEncoding.supportsCommand); key.alpha = key.isEnabled ? 1 : 0.4
            let locked = terminal.keyboardState.locked.contains(modifier)
            key.accessibilityHint = "Tap for the next key; long-press to keep on. Tap again to turn off."
            key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: locked ? "Turn " + modifier.title + " Off" : "Keep " + modifier.title + " On", actionHandler: { [weak self] _ in self?.toggle(modifier, lock: true); return true })]
            (key as? TerminalModifierKeyButton)?.showState(active: terminal.keyboardState.active.contains(modifier), held: locked)
            key.accessibilityValue = modifier == .command && !terminal.keyEncoding.supportsCommand ? "Unavailable in this application" : locked ? "On" : key.isSelected ? "Next key" : "Off"
        }
        for key in commandShortcuts { key.isEnabled = ready && terminal.keyEncoding.supportsCommand; key.alpha = key.isEnabled ? 1 : 0.4; key.accessibilityValue = terminal.keyEncoding.supportsCommand ? nil : "Unavailable in this application" }
        for key in keyboardToggles + expandToggles + keypadToggles + [keypadButton] { key.isEnabled = true; key.alpha = 1 }
    }
    private func send(_ key: TerminalAccessoryKey) {
        guard let terminal else { return }; terminal.performCustomInput { terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume()) }; refresh()
    }
}
#endif

#endif
