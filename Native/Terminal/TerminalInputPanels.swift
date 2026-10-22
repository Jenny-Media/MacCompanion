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
    @State private var advancedExpanded = false
    @State private var query: String
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var keyWidth = 44.0
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: min(320, keyWidth)), spacing: 4)] }
    init(state: TerminalKeypadState, macName: String, numbersFirst: Bool = false, onClose: (() -> Void)? = nil) {
        self.state = state; self.macName = macName; self.onClose = onClose
        _query = State(initialValue: numbersFirst ? "Numbers" : "")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Find a key or group", text: $query)
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searching).submitLabel(.search).onSubmit { searching = false }
                        .accessibilityIdentifier("terminal-keypad-search")
                    if let notice = state.notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("terminal-keypad-notice") }
                    allKeys
                }.padding(8).disabled(!state.ready)
            }.scrollDismissesKeyboard(.interactively).navigationTitle("All Keys").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } } }
                .onChange(of: searching) { _, active in if active { state.beginSearch() } }
        }.privacySensitive().directAppearance().onDisappear { state.ready = false }
    }
    private var allKeys: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach([TerminalModifiers.ctrl, .alt, .shift], id: \.rawValue) { modifierButtons($0) }
            }
            Text("Tap for next key · Long-press to keep on").font(.caption2).foregroundStyle(.secondary)
            ForEach(TerminalKeyCatalog.groups) { group in
                let keys = TerminalKeyCatalog.matching(query, in: group)
                if !keys.isEmpty {
                    Text(group.title).font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 4) { ForEach(keys) { keyButton($0) } }
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
        Button { searching = false; state.send("paletteKey-" + key.id) } label: { Text(key.title).lineLimit(1).minimumScaleFactor(textSize.isAccessibilitySize ? 1 : 0.8).frame(maxWidth: .infinity, minHeight: 44) }
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
    private func modifierButtons(_ modifier: TerminalModifiers) -> some View {
        let locked = state.locked.contains(modifier), active = locked || state.armed.contains(modifier)
        let title = modifier.title
        return Image(systemName: modifier.symbol).font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? Color(uiColor: TerminalModifierAppearance.fill) : Color(uiColor: .secondarySystemFill), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.primary : .clear, lineWidth: 1.5) }
            .overlay(alignment: .bottom) {
                if locked { Capsule().fill(.white).frame(width: 14, height: 3).padding(.bottom, 4).accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.5).exclusively(before: TapGesture()).onEnded { value in
                switch value { case .first: state.toggle(modifier, true); case .second: state.toggle(modifier, false) }
            })
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel(title).accessibilityValue(locked ? "On" : active ? "Next Key" : "Off")
            .accessibilityHint("Tap for the next key. Long-press to keep on. Tap again to turn off.")
            .accessibilityIdentifier("terminal-keypad-" + title)
            .accessibilityAction { state.toggle(modifier, false) }
            .accessibilityAction(named: locked ? "Turn " + title + " Off" : "Keep " + title + " On") { state.toggle(modifier, true) }
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

/// Compact keycaps share the runtime bar's rectangular shape and neutral fill.
/// The visible cap stays compact while retaining a full touch target.
struct TerminalKeycapStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemFill), in: .rect(cornerRadius: 8))
            .contentShape(.rect).opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

enum TerminalSavedItemsSection: Hashable {
    case shortcuts, text
    var title: String { self == .shortcuts ? "Shortcuts" : "Text" }
    var managementTitle: String { self == .shortcuts ? "Shortcuts" : "Saved Text" }
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
                            .submitLabel(.search).onSubmit { searching = false }
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
                                    Text(item.title)
                                    if let usage = item.usage { Text(usage).font(.caption).foregroundStyle(.secondary) }
                                    Text(item.requiresCommand && !supportsCommand ? "Requires Command support from the remote app" : item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Text(item.kind == .text ? "Review" : "Send").font(.subheadline)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.disabled(item.requiresCommand && !supportsCommand).accessibilityIdentifier("terminal-saved-" + item.id.uuidString)
                    }
                    if filtered.isEmpty { Text(section == .shortcuts ? "No matching shortcuts." : "No matching saved text.").foregroundStyle(.secondary) }
                } header: { Text(macName) } footer: { Text(section == .shortcuts ? "Tap a shortcut to send it once." : "Choose saved text to review and edit. Nothing is sent until Send Text. No Return is added.") }
                Button("Manage Saved Items", systemImage: "slider.horizontal.3") { customize() }.accessibilityIdentifier("terminal-manage-saved")
            }
                .navigationTitle(section.title).directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Manage", action: customize).accessibilityIdentifier("terminal-saved-manage") }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }.privacySensitive().directAppearance()
    }
}
#endif
