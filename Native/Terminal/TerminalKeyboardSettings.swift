#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct TerminalKeyboardSettings: View {
    let macID: UUID
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TerminalKeyboardPreferences()
    @State private var readable = false
    @State private var issue: DirectRecoveryNotice?
    @State private var snippet: TerminalSnippet?
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    @State private var editMode: EditMode = .inactive
    private func reload() {
        do { draft = try .load(macID); readable = true; issue = nil }
        catch { readable = false; issue = .make(.controlsUnavailable, message: "Terminal keyboard settings couldn’t be read. Existing settings are kept; editing is paused to protect them.") }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Standard keys are free. Pro adds a custom row and saved snippets.").foregroundStyle(.secondary)
                    if !pro.hasPro { Button("Unlock Lifetime Pro") { paywall = true } }
                }
                Section("Custom Row · Up to 8 Keys") {
                    ForEach(draft.keys) { key in Text(key.title) }.onMove { draft.keys.move(fromOffsets: $0, toOffset: $1) }.onDelete { draft.keys.remove(atOffsets: $0) }
                    if !draft.keys.isEmpty { Button(editMode.isEditing ? "Done Reordering" : "Reorder") { editMode = editMode.isEditing ? .inactive : .active } }
                    Menu("Add Key") {
                        ForEach(TerminalAccessoryKey.allCases.filter { !draft.keys.contains($0) }) { key in Button(key.title) { if draft.keys.count < 8 { draft.keys.append(key) } } }
                    }.disabled(draft.keys.count >= 8)
                }.disabled(!pro.hasPro || !readable)
                Section {
                    ForEach(draft.snippets) { value in Button(value.name) { snippet = value } }.onDelete { draft.snippets.remove(atOffsets: $0) }
                    if draft.snippets.count < 32 { Button("Add Snippet") { snippet = .init(name: "", text: "") } }
                } header: { Text("Saved Snippets") } footer: { Text("Snippets stay in this iPhone’s Keychain. Selecting one sends its text to the active shell; a trailing newline can run a command.") }
                    .disabled(!pro.hasPro || !readable)
                if let issue { Section { DirectRecoveryCard(notice: issue, primary: .init(title: readable ? "Keep Editing" : "Retry", perform: { if readable { self.issue = nil } else { reload() } })) } }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Terminal Keyboard").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard pro.hasPro, readable else { paywall = true; return }
                    do { try draft.save(macID); changed(); dismiss() }
                    catch { issue = .make(.saveFailed) }
                }.disabled(!pro.hasPro || !readable) }
            }
            .sheet(item: $snippet) { value in TerminalSnippetEditor(value: value) { value in
                if let index = draft.snippets.firstIndex(where: { $0.id == value.id }) { draft.snippets[index] = value } else { draft.snippets.append(value) }
            } }
            .sheet(isPresented: $paywall) { DirectProView() }
            .onAppear { reload() }
        }
    }
}
private struct TerminalSnippetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: TerminalSnippet
    let save: @MainActor (TerminalSnippet) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $value.name)
                TextEditor(text: $value.text).font(.body.monospaced()).frame(minHeight: 160).autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                if !value.valid { Text("Enter a name from 1 to 32 characters and text from 1 byte to 4 KiB.").font(.footnote).foregroundStyle(.secondary) }
                Text("Up to 4 KiB. Text is sent exactly as entered. Include a newline only if you want the shell to execute it.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Terminal Snippet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(value); dismiss() }.disabled(!value.valid) }
            }
        }
    }
}
#endif
