#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers

struct TerminalControlsSettings: View {
    var store = TerminalControlsStore()
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TerminalControlsProfile.defaults
    @State private var readable = false
    @State private var issue: DirectRecoveryNotice?
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("One setup for every Mac you connect to on this device.").foregroundStyle(.secondary)
                    if !readable {
                        DirectRecoveryCard(notice: issue ?? .make(.controlsUnavailable), primary: .init(title: "Retry", perform: reload))
                    } else if let issue {
                        DirectRecoveryCard(notice: issue, primary: .init(title: "Reload Saved Controls", perform: reload))
                    }
                    TerminalControlsEditor(profile: $draft, editable: readable && pro.hasPro)
                    if !pro.hasPro { Button("Customize with Pro", systemImage: "sparkles") { paywall = true } }
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively).background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Terminal Controls").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("terminal-controls-cancel") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save)
                        .disabled(!readable || !pro.hasPro || !draft.valid).accessibilityIdentifier("terminal-controls-save") }
                }
        }.interactiveDismissDisabled().directAppearance()
            .onAppear(perform: reload)
            .sheet(isPresented: $paywall) { DirectProView() }
    }
    private func reload() {
        do { draft = try store.load(); readable = true; issue = nil }
        catch { readable = false; issue = .make(.controlsUnavailable, message: "Terminal controls couldn’t be read. Existing controls and snippets are kept. Retry when device storage is available.") }
    }
    private func save() {
        guard readable, pro.hasPro, DirectAppLockV1.shared.canAccess else { return }
        do { draft = try store.save(draft); changed(); dismiss() }
        catch TerminalControlsStore.Failure.staleDraft {
            issue = .make(.saveFailed, message: "Controls changed in another window. Reload the saved controls before editing again.")
        } catch { issue = .make(.saveFailed) }
    }
}

/// A value-type draft owns both placements. Neither preview has a session or
/// storage callback, so selecting, typing and reordering cannot execute input.
struct TerminalControlsEditor: View {
    @Binding var profile: TerminalControlsProfile
    var editable = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: UUID?
    private var selection: Binding<TerminalControlAction>? {
        guard let id = selected, let current = profile.actions.first(where: { $0.id == id }) else { return nil }
        return Binding(get: { profile.actions.first { $0.id == id } ?? current }, set: { value in
            guard editable, let index = profile.actions.firstIndex(where: { $0.id == id }) else { return }
            profile.actions[index] = value
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            previewCard("Custom Keyboard Row", symbol: "keyboard") {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(profile.actions.filter(\.inRow)) { item in actionButton(item) }
                        if !profile.actions.contains(where: \.inRow) { Text("Pin actions below to add a custom row.").foregroundStyle(.secondary).padding(8) }
                    }
                }
            }
            previewCard("Floating Menu", symbol: "ellipsis.circle") {
                TerminalMenuEditingPreview(actions: profile.actions.filter(\.inMenu), selected: selected, editable: editable,
                    select: { selected = $0 }, move: move)
                    .id(dynamicTypeSize)
                Text("Tap an action to edit. Drag to reorder. Preview sends no input.").font(.caption).foregroundStyle(.secondary)
            }
            if let selection {
                TerminalControlInspector(action: selection).id(selection.wrappedValue.id)
                    .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(!editable)
                HStack {
                    Button("Earlier", systemImage: "arrow.left") { moveSelected(-1) }
                        .disabled(profile.actions.first?.id == selected)
                    Button("Later", systemImage: "arrow.right") { moveSelected(1) }
                        .disabled(profile.actions.last?.id == selected)
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        profile.actions.removeAll { $0.id == selected }; selected = nil
                    }
                }.disabled(!editable)
            }
            HStack {
                Text("Action Library").font(.headline)
                Spacer()
                Menu("Add Action", systemImage: "plus") {
                    Button("Shortcut") { var item = TerminalControlAction(title: "Shortcut", kind: .shortcut); item.character = 0x63; item.modifiers = [0xffe3]; add(item) }
                    Button("Saved Text") { add(.init(title: "Saved Text", kind: .text)) }
                    Menu("Terminal Key") {
                        ForEach(TerminalAccessoryKey.allCases) { key in
                            Button(key.title) { add(.init(title: key.title, kind: .key, key: key)) }
                        }
                    }
                    Menu("Standard Action") {
                        ForEach(DirectQuickActionEditing.standards(.terminal)) { item in Button(item.title) { add(.init(item)) } }
                    }
                }.disabled(!editable || profile.actions.count >= 4096).accessibilityIdentifier("terminal-control-add")
            }
            // This is also where unpinned actions remain discoverable. Their
            // content has one owner even when both previews reference it.
            LazyVStack(spacing: 8) {
                ForEach(profile.actions) { item in
                    Button { selected = item.id } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.symbol).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if item.inRow { Image(systemName: "keyboard").accessibilityLabel("In keyboard row") }
                            if item.inMenu { Image(systemName: "ellipsis.circle").accessibilityLabel("In floating menu") }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected == item.id ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(!editable)
                        .accessibilityIdentifier("terminal-library-" + item.id.uuidString)
                }
            }
        }.privacySensitive()
    }
    private func previewCard<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: symbol).font(.headline); content() }
            .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func actionButton(_ item: TerminalControlAction) -> some View {
        Button(item.title) { selected = item.id }.buttonStyle(.bordered)
            .tint(selected == item.id ? .accentColor : .secondary).frame(minHeight: 44)
            .disabled(!editable).draggable(item.id.uuidString)
            .dropDestination(for: String.self) { values, _ in
                guard editable, let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                move(source, item.id); return true
            }.accessibilityIdentifier("terminal-row-preview-" + item.id.uuidString)
    }
    private func add(_ item: TerminalControlAction) { guard editable else { return }; profile.actions.append(item); selected = item.id }
    private func move(_ source: UUID, _ target: UUID) { guard editable else { return }; profile.move(source, to: target) }
    private func moveSelected(_ offset: Int) {
        guard let selected, let index = profile.actions.firstIndex(where: { $0.id == selected }),
              profile.actions.indices.contains(index + offset) else { return }
        move(selected, profile.actions[index + offset].id)
    }
}

private struct TerminalControlInspector: View {
    @Binding var action: TerminalControlAction
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if action.kind == .shortcut {
                DirectQuickActionInspector(action: Binding(get: { action.shortcut }, set: {
                    action.title = $0.title; action.character = $0.key; action.modifiers = $0.modifiers
                }), mode: .terminal)
            } else {
                Label(action.kind == .text ? "Saved Text" : action.kind == .builtIn ? "Standard Action" : "Terminal Key", systemImage: action.symbol).font(.headline)
                TextField("Name", text: $action.title).textFieldStyle(.roundedBorder).accessibilityIdentifier("terminal-control-name")
                if action.kind == .text { DirectSavedTextEditor(text: $action.text, mode: .terminal, maximumBytes: 4096) }
                if action.kind == .key {
                    Picker("Key", selection: $action.key) {
                        ForEach(TerminalAccessoryKey.allCases) { key in Text(key.title).tag(Optional(key)) }
                    }
                }
            }
            Toggle("Show in Keyboard Row", isOn: $action.inRow).accessibilityIdentifier("terminal-placement-row")
            Toggle("Show in Floating Menu", isOn: $action.inMenu).accessibilityIdentifier("terminal-placement-menu")
            if !action.valid { Text("Enter a name up to 40 characters and valid action content. Saved text supports up to 4096 UTF-8 bytes.").font(.caption).foregroundStyle(.red) }
        }.privacySensitive()
    }
}

/// The production floating-menu renderer supplies layout, selection, drag and
/// accessible move actions. It never receives an input execution handler here.
struct TerminalMenuEditingPreview: UIViewRepresentable {
    let actions: [TerminalControlAction]
    let selected: UUID?
    var editable: Bool
    let select: (UUID) -> Void
    let move: (UUID, UUID) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var category: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall; case .small: .small; case .medium: .medium; case .large: .large
        case .xLarge: .extraLarge; case .xxLarge: .extraExtraLarge; case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium; case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge; case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
    func makeUIView(context: Context) -> CompanionVNCControls {
        let view = CompanionVNCControls(); view.editingPreview = true; view.bottomInset = 0; return view
    }
    func updateUIView(_ view: CompanionVNCControls, context: Context) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.macName = "Terminal"; view.categoryActions = []; view.quickActions = actions.map(\.native)
        view.selectedPreviewID = selected?.uuidString
        view.previewSelectionHandler = editable ? { if let id = UUID(uuidString: $0) { select(id) } } : nil
        view.previewMoveHandler = editable ? { if let source = UUID(uuidString: $0), let target = UUID(uuidString: $1) { move(source, target) } } : nil
        view.refreshEditingPreview()
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CompanionVNCControls, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? 360, height: .greatestFiniteMagnitude))
    }
}
#endif
