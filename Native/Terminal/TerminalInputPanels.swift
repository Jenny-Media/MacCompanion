#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import Observation

@MainActor @Observable final class TerminalKeypadState {
    var armed: TerminalModifiers = []
    var locked: TerminalModifiers = []
    var ready = true
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
    @ScaledMetric(relativeTo: .body) private var keyWidth = 72.0
    @Environment(\.dynamicTypeSize) private var textSize
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: min(320, keyWidth)), spacing: 8)] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(macName).font(.subheadline).foregroundStyle(.secondary)
                    if !numbersFirst { Text("Tap a key to send it once. The keypad stays open.").font(.subheadline) }
                    if numbersFirst { numbers }
                    VStack(spacing: 8) {
                        ForEach(["Ctrl", "Alt", "Shift"], id: \.self) { title in
                            let modifier: TerminalModifiers = title == "Ctrl" ? .ctrl : title == "Alt" ? .alt : .shift
                            let locked = state.locked.contains(modifier)
                            let active = locked || state.armed.contains(modifier)
                            if textSize.isAccessibilitySize {
                                VStack { modifierButtons(title, modifier: modifier, locked: locked, active: active) }
                            } else {
                                HStack { modifierButtons(title, modifier: modifier, locked: locked, active: active) }
                            }
                        }
                    }
                    keyGroup("Navigation", keys: [.escape, .tab, .left, .down, .up, .right, .home, .end, .pageUp, .pageDown, .delete])
                    keyGroup("Function Keys", keys: [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12])
                    if !numbersFirst { numbers }
                    Text("Clipboard").font(.headline)
                    if textSize.isAccessibilitySize { VStack { clipboardButtons } }
                    else { HStack { clipboardButtons } }
                    Text("Process Controls").font(.headline)
                    ForEach([("interrupt", "Interrupt · Ctrl-C"), ("endInput", "End Input · Ctrl-D"), ("suspendProcess", "Suspend · Ctrl-Z")], id: \.0) { kind, title in
                        Button { state.send(kind) } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered).accessibilityIdentifier("terminal-keypad-" + kind)
                    }
                }.padding(16).disabled(!state.ready)
            }.navigationTitle(numbersFirst ? "Number Keypad" : "Keypad").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } } }
        }.directAppearance().onDisappear { state.ready = false }
    }
    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Numbers").font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { number in
                    Button { state.send("terminalNumber-" + number) } label: { Text(number).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("terminal-keypad-number-" + number)
                }
            }
        }
    }
    @ViewBuilder private var clipboardButtons: some View {
        Button { state.send("copySelection") } label: { Text("Copy Selection").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
        Button { state.send("paste") } label: { Text("Paste").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
    }
    @ViewBuilder private func modifierButtons(_ title: String, modifier: TerminalModifiers, locked: Bool, active: Bool) -> some View {
        Button { state.toggle(modifier, false) } label: {
            Text(title + " · " + (locked ? "Locked" : active ? "Next Key" : "Off")).frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).tint(active ? .accentColor : .primary).accessibilityIdentifier("terminal-keypad-" + title)
        Button { state.toggle(modifier, true) } label: { Label(locked ? "Unlock" : "Lock", systemImage: locked ? "lock.open" : "lock").frame(minHeight: 44) }
            .buttonStyle(.bordered).accessibilityLabel((locked ? "Unlock " : "Lock ") + title)
    }
    private func keyGroup(_ title: String, keys: [TerminalAccessoryKey]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(keys) { key in Button { state.send("terminalKey-" + key.rawValue) } label: { Text(key.title).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).accessibilityIdentifier("terminal-keypad-" + key.rawValue) }
            }
        }
    }
}

struct TerminalSavedItems: View {
    let items: [TerminalControlAction]
    let macName: String
    let select: (UUID) -> Void
    let customize: () -> Void
    @State private var search = ""
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    private var filtered: [TerminalControlAction] {
        items.filter { ($0.kind == .shortcut || $0.kind == .text) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search shortcuts and text", text: $search).focused($searching)
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
                                    Text(item.title); Text(item.kind == .text ? "Paste text · no added Return" : item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: item.kind == .text ? "doc.on.clipboard" : "arrow.up.forward")
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.accessibilityIdentifier("terminal-saved-" + item.id.uuidString)
                    }
                    if filtered.isEmpty { Text("No matching saved items.").foregroundStyle(.secondary) }
                } header: { Text(macName) } footer: { Text("Tap a shortcut to send it, or text to paste it. Multiline text asks for confirmation.") }
                Button("Manage Shortcuts & Text", systemImage: "pencil") { customize() }.accessibilityIdentifier("terminal-manage-saved")
            }
                .navigationTitle("Shortcuts & Text").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.privacySensitive().directAppearance()
    }
}
#endif
