#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import Observation

@MainActor @Observable final class TerminalKeypadState {
    var armed: TerminalModifiers = []
    var locked: TerminalModifiers = []
    var ready = true
    var supportsCommand = false
    var profileRevision = UUID()
    var canPin = false
    var items: [TerminalControlAction] = []
    var notice: String?
    var toggle: (TerminalModifiers, Bool) -> Void = { _, _ in }
    var send: (String) -> Void = { _ in }
    var pin: (String, TerminalControlsDestination) -> Void = { _, _ in }
    var useSaved: (UUID) -> Void = { _ in }
    var compose: () -> Void = {}
    var beginSearch: () -> Void = {}
}

/// Runtime keys send once; context-menu placement and editor previews never send.
struct TerminalKeypad: View {
    let state: TerminalKeypadState
    let macName: String
    var onClose: (() -> Void)?
    private enum Page: String, CaseIterable, Identifiable {
        case keys = "All Keys", shortcuts = "Shortcuts", text = "Text"
        var id: String { rawValue }
    }
    @State private var page = Page.keys
    @State private var advancedExpanded = false
    @State private var query: String
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var keyWidth = 48.0
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: min(320, keyWidth)), spacing: 6)] }
    init(state: TerminalKeypadState, macName: String, numbersFirst: Bool = false, onClose: (() -> Void)? = nil) {
        self.state = state; self.macName = macName; self.onClose = onClose
        _query = State(initialValue: numbersFirst ? "Numbers" : "")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if textSize.isAccessibilitySize {
                        pagePicker.pickerStyle(.menu)
                    } else { pagePicker.pickerStyle(.segmented) }
                    TextField(page == .keys ? "Find a key or group" : "Search saved items", text: $query)
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searching).submitLabel(.search).onSubmit { searching = false }
                        .accessibilityIdentifier("terminal-keypad-search")
                    if let notice = state.notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("terminal-keypad-notice") }
                    if page == .keys { allKeys } else { savedItems }
                }.padding(12).disabled(!state.ready)
            }.scrollDismissesKeyboard(.interactively).navigationTitle("Keypad").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } } }
                .onChange(of: page) { _, _ in query = "" }
                .onChange(of: searching) { _, active in if active { state.beginSearch() } }
        }.privacySensitive().directAppearance().onDisappear { state.ready = false }
    }
    private var pagePicker: some View {
        Picker("Keys", selection: $page) { ForEach(Page.allCases) { Text($0.rawValue).tag($0) } }
            .accessibilityIdentifier("terminal-keypad-page")
    }
    private var allKeys: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap to send once. Hold a key to pin it. Modifiers apply to the next key; lock for repeated keys.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 260 : 90), spacing: 6)], spacing: 6) {
                ForEach([TerminalModifiers.ctrl, .alt, .shift], id: \.rawValue) { modifierButtons($0) }
            }
            ForEach(TerminalKeyCatalog.groups) { group in
                let keys = TerminalKeyCatalog.matching(query, in: group)
                if !keys.isEmpty {
                    Text(group.title).font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 6) { ForEach(keys) { keyButton($0) } }
                }
            }
            if query.isEmpty {
                HStack {
                    Button("Copy Selection") { state.send("copySelection") }
                    Button("Paste") { state.send("paste") }
                }.buttonStyle(.bordered).frame(minHeight: 44)
                Button {
                    advancedExpanded.toggle()
                } label: {
                    Label("Advanced · Command", systemImage: advancedExpanded ? "chevron.down" : "chevron.right").frame(minHeight: 44)
                }.accessibilityIdentifier("terminal-keypad-advanced").accessibilityValue(advancedExpanded ? "Expanded" : "Collapsed")
                if advancedExpanded {
                    modifierButtons(.command)
                    Text("Command works only when the remote application negotiates support. Ctrl and Option work in ordinary terminal sessions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !state.canPin { Text("All keys are available here. Pinning favorites requires Pro.").font(.caption).foregroundStyle(.secondary) }
            }
            if !TerminalKeyCatalog.groups.contains(where: { !TerminalKeyCatalog.matching(query, in: $0).isEmpty }) {
                Text("No matching keys. Try Home, F8, Symbols or Numbers.").foregroundStyle(.secondary)
            }
        }
    }
    private func keyButton(_ key: TerminalPaletteKey) -> some View {
        Button { searching = false; state.send("paletteKey-" + key.id) } label: { Text(key.title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(TerminalKeypadButtonStyle()).accessibilityLabel(key.name)
            .accessibilityIdentifier("terminal-keypad-" + (key.accessory?.rawValue ?? key.id))
            .contextMenu {
                ForEach(TerminalControlsDestination.allCases) { destination in
                    let pinned = state.items.contains { key.matches($0) && (destination == .keyboard ? $0.inRow : $0.inMenu) }
                    Button(pinned ? "Pinned to " + destination.title : "Pin to " + destination.title, systemImage: pinned ? "checkmark" : destination.symbol) {
                        state.pin(key.id, destination)
                    }.disabled(!state.canPin || pinned)
                }
            }
            .accessibilityAction(named: "Pin to Keyboard Bar") { if state.canPin { state.pin(key.id, .keyboard) } }
            .accessibilityAction(named: "Pin to Floating Menu") { if state.canPin { state.pin(key.id, .menu) } }
    }
    private var savedItems: some View {
        VStack(alignment: .leading, spacing: 10) {
            if page == .text {
                Button("Compose Text", systemImage: "square.and.pencil", action: state.compose).buttonStyle(.bordered)
                Text("Choose text to review and edit. Nothing is sent until Send Text.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Tap a shortcut to send once.").font(.caption).foregroundStyle(.secondary) }
            let items = state.items.filter { $0.kind == (page == .text ? .text : .shortcut) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)) }
            ForEach(items) { item in
                Button { searching = false; state.useSaved(item.id) } label: {
                    HStack {
                        Image(systemName: item.symbol)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.requiresCommand && !state.supportsCommand ? "Requires remote Command support" : item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(); Image(systemName: item.kind == .text ? "square.and.pencil" : "arrow.up.forward")
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.bordered).disabled(item.requiresCommand && !state.supportsCommand).accessibilityIdentifier("terminal-keypad-saved-" + item.id.uuidString)
            }
            if items.isEmpty { Text("No matching saved items. Create them in Customize Controls → Shortcuts & Text.").foregroundStyle(.secondary) }
        }
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
}

private struct TerminalKeypadButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.tint)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
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
                                    Text(item.title); Text(item.requiresCommand && !supportsCommand ? "Requires Command support from the remote app" : item.kind == .text ? "Review text before sending" : item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: item.kind == .text ? "square.and.pencil" : "arrow.up.forward")
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.disabled(item.requiresCommand && !supportsCommand).accessibilityIdentifier("terminal-saved-" + item.id.uuidString)
                    }
                    if filtered.isEmpty { Text(section == .shortcuts ? "No matching shortcuts." : "No matching saved text.").foregroundStyle(.secondary) }
                } header: { Text(macName) } footer: { Text(section == .shortcuts ? "Tap a shortcut to send it once." : "Choose saved text to review and edit. Nothing is sent until Send Text. No Return is added.") }
                Button("Customize Controls", systemImage: "slider.horizontal.3") { customize() }.accessibilityIdentifier("terminal-manage-saved")
            }
                .navigationTitle(section.title).directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.privacySensitive().directAppearance()
    }
}
#endif
