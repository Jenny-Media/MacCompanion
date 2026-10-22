#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Presets contain one chord each. Prefix/mode steps remain separate user taps.
/// Default bindings are configurable in each tool; never infer remote state.
enum TerminalShortcutPack: String, CaseIterable, Identifiable {
    case tmux, zellij, zellijUnlock, herdr
    var id: String { rawValue }
    var title: String {
        switch self { case .tmux: "tmux"; case .zellij: "Zellij · Default"; case .zellijUnlock: "Zellij · Unlock First"; case .herdr: "Herdr" }
    }
    var guidance: String {
        switch self {
        case .tmux: "Tap Prefix, then a command key. These use tmux’s default Ctrl+b prefix."
        case .zellij: "Mode shortcuts use Zellij’s Default keybindings. Alt+n opens a pane directly."
        case .zellijUnlock: "Tap Unlock, then a mode key. These use Zellij’s Unlock First keybindings."
        case .herdr: "Tap Navigate, then a command key. These use Herdr’s default Ctrl+b prefix."
        }
    }
    var source: URL {
        let address = switch self {
        case .tmux: "https://github.com/tmux/tmux/wiki/Getting-Started"
        case .zellij, .zellijUnlock: "https://zellij.dev/documentation/keybinding-presets"
        case .herdr: "https://github.com/herdrdev/herdr/blob/master/docs/next/website/src/content/docs/keyboard.mdx"
        }
        return URL(string: address)!
    }
    var shortcuts: [TerminalShortcutPreset] {
        switch self {
        case .tmux:
            return [preset("prefix", "Tmux Prefix", "b", ctrl: true),
                preset("window", "Tmux New Window", "c", after: "After Tmux Prefix"),
                preset("next", "Tmux Next Window", "n", after: "After Tmux Prefix"),
                preset("previous", "Tmux Previous Window", "p", after: "After Tmux Prefix"),
                preset("split-right", "Tmux Split Right", "%", after: "After Tmux Prefix"),
                preset("split-down", "Tmux Split Down", "\"", after: "After Tmux Prefix"),
                preset("copy", "Tmux Copy Mode", "[", after: "After Tmux Prefix"),
                preset("zoom", "Tmux Zoom Pane", "z", after: "After Tmux Prefix"),
                preset("detach", "Tmux Detach", "d", after: "After Tmux Prefix")]
        case .zellij:
            return [preset("pane", "Zellij Pane Mode", "p", ctrl: true), preset("tab", "Zellij Tab Mode", "t", ctrl: true),
                preset("resize", "Zellij Resize Mode", "n", ctrl: true), preset("scroll", "Zellij Scroll Mode", "s", ctrl: true),
                preset("session", "Zellij Session Mode", "o", ctrl: true), preset("lock", "Zellij Lock", "g", ctrl: true),
                preset("new-pane", "Zellij New Pane", "n", alt: true)]
        case .zellijUnlock:
            return [preset("unlock", "Zellij Unlock", "g", ctrl: true),
                preset("pane", "Zellij Pane Mode", "p", after: "After Zellij Unlock"),
                preset("tab", "Zellij Tab Mode", "t", after: "After Zellij Unlock")]
        case .herdr:
            return [preset("prefix", "Herdr Navigate", "b", ctrl: true),
                preset("workspace", "Herdr New Workspace", "N", after: "After Herdr Navigate"),
                preset("rename", "Herdr Rename Workspace", "W", after: "After Herdr Navigate"),
                preset("tab", "Herdr New Tab", "c", after: "After Herdr Navigate"),
                preset("split", "Herdr Split Pane", "v", after: "After Herdr Navigate"),
                preset("sidebar", "Herdr Toggle Sidebar", "b", after: "After Herdr Navigate"),
                preset("zoom", "Herdr Zoom Pane", "z", after: "After Herdr Navigate"),
                preset("resize", "Herdr Resize Mode", "r", after: "After Herdr Navigate"),
                preset("detach", "Herdr Detach", "q", after: "After Herdr Navigate")]
        }
    }
    private func preset(_ key: String, _ name: String, _ character: Character, ctrl: Bool = false, alt: Bool = false, after: String? = nil) -> TerminalShortcutPreset {
        var action = TerminalControlAction(title: name, kind: .shortcut, inMenu: false)
        action.character = character.unicodeScalars.first!.value
        action.modifiers = ctrl ? [0xffe3] : alt ? [0xffe9] : []
        action.presetID = rawValue + "." + key; action.usage = after
        return .init(id: action.presetID!, action: action)
    }
}
struct TerminalShortcutPreset: Identifiable {
    let id: String
    let action: TerminalControlAction
}
extension TerminalControlsProfile {
    @discardableResult mutating func add(_ preset: TerminalShortcutPreset) -> UUID? {
        if let item = actions.first(where: { $0.presetID == preset.id }) { return item.id }
        guard actions.count < 4096, preset.action.valid else { return nil }
        actions.append(preset.action); return preset.action.id
    }
}
#endif
