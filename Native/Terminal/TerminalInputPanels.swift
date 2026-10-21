#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import Observation

@MainActor @Observable final class TerminalKeypadState {
    var armed: TerminalModifiers = []
    var locked: TerminalModifiers = []
    var ready = true
    var supportsCommand = false
    var toggle: (TerminalModifiers, Bool) -> Void = { _, _ in }
    var send: (String) -> Void = { _ in }
}

/// Runtime controls always send; editor previews only select. Keep those paths separate.
struct TerminalKeypad: View {
    let state: TerminalKeypadState
    let macName: String
    var numbersFirst = false
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    private enum Page: String, CaseIterable, Identifiable {
        case navigation = "Navigation", function = "F1–F12", numbers = "Numbers", actions = "Actions"
        var id: String { rawValue }
    }
    @State private var page: Page
    @ScaledMetric(relativeTo: .body) private var keyWidth = 48.0
    @Environment(\.dynamicTypeSize) private var textSize
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: min(320, keyWidth)), spacing: 6)] }
    init(state: TerminalKeypadState, macName: String, numbersFirst: Bool = false, onClose: (() -> Void)? = nil) {
        self.state = state; self.macName = macName; self.numbersFirst = numbersFirst; self.onClose = onClose
        _page = State(initialValue: numbersFirst ? .numbers : .navigation)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap a key to send once. Tap a modifier for the next key; use its lock for repeated keys.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 260 : 140), spacing: 6)], spacing: 6) {
                        ForEach([TerminalModifiers.ctrl, .alt, .shift, .command], id: \.rawValue) { modifier in
                            modifierButtons(modifier)
                        }
                    }
                    if !state.supportsCommand { Text("Command becomes available when the remote app supports it.").font(.caption).foregroundStyle(.secondary) }
                    if textSize.isAccessibilitySize {
                        Picker("Keys", selection: $page) { ForEach(Page.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.menu).accessibilityIdentifier("terminal-keypad-page")
                    } else {
                        Picker("Keys", selection: $page) { ForEach(Page.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("terminal-keypad-page")
                    }
                    switch page {
                    case .navigation: keyGroup(keys: [.escape, .tab, .left, .down, .up, .right, .home, .end, .pageUp, .pageDown, .delete])
                    case .function: keyGroup(keys: [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12])
                    case .numbers:
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { number in
                                Button { state.send("terminalNumber-" + number) } label: { Text(number).frame(maxWidth: .infinity, minHeight: 44) }
                                    .buttonStyle(TerminalKeypadButtonStyle()).accessibilityIdentifier("terminal-keypad-number-" + number)
                            }
                        }
                    case .actions:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
                            ForEach([("copySelection", "Copy Selection"), ("paste", "Paste"), ("interrupt", "Interrupt · Ctrl-C"), ("endInput", "End Input · Ctrl-D"), ("suspendProcess", "Suspend · Ctrl-Z")], id: \.0) { kind, title in
                                Button { state.send(kind) } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
                                    .buttonStyle(TerminalKeypadButtonStyle()).accessibilityIdentifier("terminal-keypad-" + kind)
                            }
                        }
                    }
                }.padding(12).disabled(!state.ready)
            }.navigationTitle(numbersFirst ? "Number Keypad" : "Keypad").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } } }
        }.directAppearance().onDisappear { state.ready = false }
    }
    private func modifierButtons(_ modifier: TerminalModifiers) -> some View {
        let locked = state.locked.contains(modifier), active = locked || state.armed.contains(modifier)
        let title = modifier.title
        return HStack(spacing: 0) {
            Button { state.toggle(modifier, false) } label: {
                VStack(spacing: 0) { Text(title); Text(locked ? "Locked" : active ? "Next Key" : "Off").font(.caption2) }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("terminal-keypad-" + title)
            Button { state.toggle(modifier, true) } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel((locked ? "Unlock " : "Lock ") + title)
        }.buttonStyle(TerminalKeypadButtonStyle()).tint(active ? .accentColor : .primary)
            .disabled(modifier == .command && !state.supportsCommand)
    }
    private func keyGroup(keys: [TerminalAccessoryKey]) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(keys) { key in Button { state.send("terminalKey-" + key.rawValue) } label: { Text(key.title).frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(TerminalKeypadButtonStyle()).accessibilityIdentifier("terminal-keypad-" + key.rawValue) }
        }
    }
}

private struct TerminalKeypadButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.tint)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

enum TerminalSavedItemsSection {
    case shortcuts, text
    var title: String { self == .shortcuts ? "Shortcuts" : "Text" }
    var kind: TerminalControlAction.Kind { self == .shortcuts ? .shortcut : .text }
}

struct TerminalSavedItems: View {
    let section: TerminalSavedItemsSection
    let items: [TerminalControlAction]
    let macName: String
    var supportsCommand = false
    let select: (UUID) -> Void
    let customize: () -> Void
    var compose: () -> Void = {}
    @State private var search = ""
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    private var filtered: [TerminalControlAction] {
        items.filter { $0.kind == section.kind && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                if section == .text {
                    Button("Compose Text", systemImage: "square.and.pencil", action: compose)
                        .accessibilityIdentifier("terminal-compose-text")
                }
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(section == .shortcuts ? "Search shortcuts" : "Search saved text", text: $search).focused($searching)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("terminal-saved-search")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Clear Search")
                        }
                    }
                }
                Section {
                    ForEach(filtered) { item in
                        Button { searching = false; select(item.id) } label: {
                            HStack {
                                Image(systemName: item.symbol)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title); Text(item.requiresCommand && !supportsCommand ? "Requires Command support from the remote app" : item.kind == .text ? "Paste text · no added Return" : item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: item.kind == .text ? "doc.on.clipboard" : "arrow.up.forward")
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.disabled(item.requiresCommand && !supportsCommand).accessibilityIdentifier("terminal-saved-" + item.id.uuidString)
                    }
                    if filtered.isEmpty { Text(section == .shortcuts ? "No matching shortcuts." : "No matching saved text.").foregroundStyle(.secondary) }
                } header: { Text(macName) } footer: { Text(section == .shortcuts ? "Tap a shortcut to send it once." : "Tap saved text to paste it without adding Return. Multiline text asks for confirmation.") }
                Button("Customize Controls", systemImage: "slider.horizontal.3") { customize() }.accessibilityIdentifier("terminal-manage-saved")
            }
                .navigationTitle(section.title).directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.privacySensitive().directAppearance()
    }
}
#endif
