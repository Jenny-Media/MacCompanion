#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct TerminalSavedControlEditor: View {
    @State var action: TerminalControlAction
    let profile: TerminalControlsProfile
    var localDraft = false
    var creating = false
    // A successful apply closes the owner's item binding in the same update
    // that accepts the value. A later environment dismissal can be lost when
    // an iPad sheet is reconfigured by that value change.
    let apply: (TerminalControlAction) -> Bool
    var delete: (() -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var failed = false
    @State private var validation = false
    @State private var newStep: TerminalShortcutStep?
    @State private var editingExistingStep = false
    @FocusState private var editingName: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $action.title).accessibilityIdentifier("terminal-control-name")
                        .textInputAutocapitalization(.words).autocorrectionDisabled().focused($editingName).submitLabel(.done).onSubmit { editingName = false }
                }
                if action.kind == .shortcut {
                    if action.steps == nil {
                        Section("Key Combination") { TerminalShortcutCombination(action: $action, allowsCommand: profile.family == .remoteMac) }
                        Section {
                            Button("Add Step", systemImage: "plus") { newStep = .init() }
                                .accessibilityIdentifier("shortcut-add-step")
                        }
                    } else { TerminalSequenceEditor(action: $action, edit: { step in
                        editingExistingStep = true; newStep = step
                    }, add: { editingExistingStep = false; newStep = .init() }) }
                } else if action.kind == .text {
                    Section {
                        TextEditor(text: $action.text).font(.body.monospaced()).frame(minHeight: 150, maxHeight: 210)
                            .autocorrectionDisabled().directNoAutocapitalization().privacySensitive()
                            .accessibilityLabel("Text to Insert").accessibilityIdentifier("quick-action-text")
                    } header: { Text("Text to Insert") }
                    footer: { Text("Inserts text without pressing Return. Line breaks require confirmation before sending.") }
                } else if action.kind == .key {
                    Section("Key") { Picker("Key", selection: $action.key) { ForEach(TerminalAccessoryKey.allCases) { Text($0.title).tag(Optional($0)) } } }
                }
                if let usage = action.usage { Section { Text(usage).foregroundStyle(.secondary) } }
                let placements = action.placements(in: profile)
                if !placements.isEmpty {
                    Section { Text(localDraft ? "Updates this saved item everywhere when you tap Done in the layout editor." : "Saving updates this item everywhere it is used.").font(.caption).foregroundStyle(.secondary) }
                }
                if validation && !action.valid { Section { Text("Enter a name up to 40 characters and valid content. Text supports up to 4096 UTF-8 bytes.").font(.caption).foregroundStyle(.red).accessibilityIdentifier("terminal-item-validation") } }
            }.environment(\.editMode, .constant(action.kind == .shortcut && action.steps != nil ? .active : .inactive))
                .navigationTitle((creating ? "New " : "Edit ") + (action.kind == .text ? "Saved Text" : "Shortcut"))
                .directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("terminal-item-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(creating && localDraft ? "Add" : "Save") {
                            guard action.valid else { validation = true; return }
                            if !apply(action) { failed = true }
                        }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("terminal-item-save")
                    }
                    if delete != nil { ToolbarItem(placement: .topBarTrailing) {
                        Menu { Button("Delete Saved Item…", systemImage: "trash", role: .destructive) { confirmingDelete = true } }
                        label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More Item Actions")
                    } }
                }
                .confirmationDialog("Delete this saved item and all its placements?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete Saved Item", role: .destructive) { if delete?() != true { failed = true } }
                }
                .alert("Couldn’t Save", isPresented: $failed) { Button("Keep Editing", role: .cancel) {} }
                message: { Text("Your changes are still open. If controls changed in another window, cancel and reopen this editor before trying again.") }
        }.privacySensitive().directAppearance().interactiveDismissDisabled().presentationSizing(.page)
            .sheet(item: $newStep) { step in
                TerminalSequenceStepEditor(step: step, allowsCommand: profile.family == .remoteMac, creating: !editingExistingStep) { result in
                    if editingExistingStep, let index = action.steps?.firstIndex(where: { $0.id == result.id }) { action.steps?[index] = result }
                    else { action.steps = action.resolvedSteps + [result] }
                    newStep = nil
                }
            }
    }
}

struct TerminalShortcutCombination: View {
    @Binding var action: TerminalControlAction
    var allowsCommand = false
    @State private var choosingKey = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var keyTitle: String {
        guard action.character != 0 else { return "Choose Key" }
        return TerminalKeyCatalog.all.first { $0.shortcutCode == action.character && $0.modifiers.isEmpty }?.name
            ?? UnicodeScalar(action.character).map(String.init) ?? "Choose Key"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 118))], spacing: 8) {
                modifier("Ctrl", symbol: "control", code: 0xffe3)
                modifier("Option", symbol: "option", code: 0xffe9)
                modifier("Shift", symbol: "shift", code: 0xffe1)
                if allowsCommand { modifier("Command", symbol: "command", code: 0xffeb) }
                Button { choosingKey = true } label: { HStack { Text(keyTitle); Image(systemName: "chevron.down").font(.caption) }.frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).accessibilityIdentifier("terminal-choose-key")
            }
            Text("Sends " + action.detail + ".").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("terminal-shortcut-preview")
            if action.requiresCommand && !allowsCommand {
                Toggle("Command", isOn: Binding(get: { action.requiresCommand }, set: { enabled in if !enabled { action.modifiers.removeAll { $0 == 0xffeb } } }))
                Text("Requires support from the remote terminal application.").font(.caption).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $choosingKey) {
            TerminalShortcutKeyPicker(character: action.character) { code in action.character = code; choosingKey = false }
        }
    }
    private func modifier(_ title: String, symbol: String, code: UInt32) -> some View {
        let active = action.modifiers.contains(code)
        return Button {
            if active { action.modifiers.removeAll { $0 == code } } else { action.modifiers.append(code) }
        } label: { Label(title, systemImage: active ? "checkmark" : symbol).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered).tint(active ? .accentColor : .secondary)
            .accessibilityValue(active ? "Selected" : "Off").accessibilityIdentifier("terminal-shortcut-modifier-" + title)
    }
}

private struct TerminalShortcutKeyPicker: View {
    @State var character: UInt32
    let select: (UInt32) -> Void
    @State private var query = ""
    @State private var typed = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Character") {
                    TextField("Type one letter or symbol", text: $typed).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("terminal-key-character")
                    Button("Use Character") { if let value = typed.unicodeScalars.first { select(value.value) } }
                        .disabled(typed.unicodeScalars.count != 1).accessibilityIdentifier("terminal-use-character")
                }
                ForEach(TerminalKeyCatalog.groups.filter { $0.title != "Common Shortcuts" }) { group in
                    Section(group.title) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                            ForEach(TerminalKeyCatalog.matching(query, in: group).filter { $0.modifiers.isEmpty }) { key in
                                Button { select(key.shortcutCode) } label: { Text(key.title) }
                                    .buttonStyle(TerminalKeycapStyle()).accessibilityLabel(key.name).accessibilityIdentifier("terminal-choose-" + key.id)
                            }
                        }
                    }
                }
            }.searchable(text: $query, prompt: "Find a key").navigationTitle("Choose Key").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { if character >= 0x20 && character < 0xff00 { typed = UnicodeScalar(character).map(String.init) ?? "" } }
        }.presentationSizing(.page)
    }
}

extension TerminalPaletteKey {
    var shortcutCode: UInt32 {
        guard let accessory else { return character }
        return accessory.shortcutCode
    }
}
#endif
