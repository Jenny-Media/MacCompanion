#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct TerminalSequenceEditor: View {
    @Binding var action: TerminalControlAction
    let edit: (TerminalShortcutStep) -> Void
    let add: () -> Void
    var body: some View {
        Section {
            ForEach(action.steps ?? []) { step in
                HStack {
                    Button { edit(step) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: step.kind == .text ? "text.quote" : "keyboard")
                            Text(step.label).foregroundStyle(.primary).lineLimit(2)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("shortcut-step-" + step.id.uuidString)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            guard let index = action.steps?.firstIndex(where: { $0.id == step.id }), (action.steps?.count ?? 0) < 32 else { return }
                            var copy = step; copy.id = UUID(); action.steps?.insert(copy, at: index + 1)
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) { action.steps?.removeAll { $0.id == step.id } }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Options for " + step.label)
                }
            }.onMove { source, destination in action.steps?.move(fromOffsets: source, toOffset: destination) }
            Button("Add Step", systemImage: "plus", action: add)
                .frame(minHeight: 44).disabled((action.steps?.count ?? 0) >= 32).accessibilityIdentifier("shortcut-add-step")
        } header: { Text("Steps · \(action.steps?.count ?? 0) of 32") }
        footer: { Text("Drag to reorder. Text is reviewed before the whole shortcut runs. Add Return explicitly when needed.") }
        Section("Preview") { TerminalSequencePreview(action: action) }
    }
}

struct TerminalSequenceStepEditor: View {
    @State var step: TerminalShortcutStep
    var allowsCommand: Bool
    var creating: Bool
    let apply: (TerminalShortcutStep) -> Void
    @Environment(\.dismiss) private var dismiss
    private var chord: Binding<TerminalControlAction> {
        Binding(get: {
            var value = TerminalControlAction(title: "Step", kind: .shortcut)
            value.character = step.character; value.modifiers = step.modifiers; return value
        }, set: { step.character = $0.character; step.modifiers = $0.modifiers })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Step Type", selection: Binding(get: { step.kind }, set: { kind in
                        if step.kind != kind { step = .init(id: step.id, kind: kind) }
                    })) { Text("Key or Shortcut").tag(TerminalShortcutStep.Kind.key); Text("Text").tag(TerminalShortcutStep.Kind.text) }
                        .pickerStyle(.segmented).accessibilityIdentifier("shortcut-step-type")
                }
                if step.kind == .key { Section("Key Combination") { TerminalShortcutCombination(action: chord, allowsCommand: allowsCommand) } }
                else { Section {
                    TextEditor(text: $step.text).frame(minHeight: 150).font(.body.monospaced()).autocorrectionDisabled().directNoAutocapitalization()
                        .accessibilityIdentifier("shortcut-step-text")
                } header: { Text("Text to Insert") } footer: { Text("No Return is added. Review the full sequence before sending.") } }
            }.navigationTitle(creating ? "Add Step" : "Edit Step").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(creating ? "Add" : "Done") { apply(step) }
                        .buttonStyle(.borderedProminent).disabled(!step.valid).accessibilityIdentifier("shortcut-step-save") }
                }
        }.privacySensitive().presentationSizing(.page)
    }
}

struct TerminalSequencePreview: View {
    let action: TerminalControlAction
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(action.resolvedSteps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary) }
                    Text(step.kind == .text ? "Text" : step.label).font(.body.monospaced().weight(.medium)).foregroundStyle(.tint)
                        .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 8))
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(action.sequencePreview).accessibilityIdentifier("shortcut-sequence-preview")
    }
}

struct TerminalSequenceReview: View {
    let action: TerminalControlAction
    let send: () -> Void
    let cancel: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section { Text(action.title).font(.headline); Text("Review every step before sending. Text and line breaks can run commands. Return is sent only where shown.") }
                ForEach(Array(action.resolvedSteps.enumerated()), id: \.offset) { index, step in
                    Section("Step \(index + 1)") {
                        Text(step.kind == .text ? ((try? DirectComposedText(step.text, mode: .terminal))?.text ?? step.text) : step.label).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
            }.navigationTitle("Review Shortcut").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Send", action: send).buttonStyle(.borderedProminent).accessibilityLabel("Send Sequence").accessibilityIdentifier("shortcut-sequence-send") }
                }
        }.privacySensitive().interactiveDismissDisabled().directAppearance()
    }
}
#endif
