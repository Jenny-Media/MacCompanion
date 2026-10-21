#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers

struct TerminalControlsSettings: View {
    private enum Page: Hashable {
        case destination(TerminalControlsDestination), library
        var title: String { switch self { case .destination(let place): place.title; case .library: "Shortcuts & Text" } }
    }
    var store = TerminalControlsStore()
    let close: () -> Void
    @State private var draft = TerminalControlsProfile.defaults
    @State private var readable = false
    @State private var issue: DirectRecoveryNotice?
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    @State private var path: [Page] = []
    var body: some View {
        NavigationStack(path: $path) {
            scrollContent {
                ForEach(TerminalControlsDestination.allCases) { place in
                    Button { path.append(.destination(place)) } label: {
                        editorEntry(place.title, detail: place == .keyboard ? "Keys above the native keyboard" : "Favorites in the floating button", symbol: place.symbol)
                    }.buttonStyle(.plain).accessibilityIdentifier("terminal-edit-" + place.rawValue)
                }
                Button { path.append(.library) } label: {
                    editorEntry("Shortcuts & Text", detail: "Create and edit reusable saved items", symbol: "text.quote")
                }.buttonStyle(.plain).accessibilityIdentifier("terminal-edit-library")
            }.navigationTitle("Terminal Controls").directInlineNavigationTitle()
                .toolbar { if path.isEmpty { editorToolbar(overview: true) } }
                .navigationDestination(for: Page.self) { page in
                    scrollContent {
                        switch page {
                        case .destination(let place): TerminalControlsEditor(profile: $draft, editable: readable && pro.hasPro, destination: place)
                        case .library: TerminalControlsEditor(profile: $draft, editable: readable && pro.hasPro, libraryOnly: true)
                        }
                    }.navigationTitle(page.title).directInlineNavigationTitle()
                        .toolbar { editorToolbar(overview: false) }
                }
        }.interactiveDismissDisabled().presentationSizing(.page).directAppearance()
            .onAppear { path = []; reload() }
            .sheet(isPresented: $paywall) { DirectProView() }
    }
    private func scrollContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Applies to every Mac on this device.").font(.subheadline).foregroundStyle(.secondary)
                if !readable || issue != nil {
                    DirectRecoveryCard(notice: issue ?? .make(.controlsUnavailable), primary: .init(title: "Reload Saved Controls", perform: reload))
                }
                content()
                if !pro.hasPro { Button("Customize with Pro", systemImage: "sparkles") { paywall = true } }
            }.padding(16)
        }.scrollDismissesKeyboard(.interactively).background(Color(uiColor: .systemGroupedBackground))
    }
    @ToolbarContentBuilder private func editorToolbar(overview: Bool) -> some ToolbarContent {
        ToolbarItem(placement: overview ? .cancellationAction : .topBarTrailing) {
            Button("Cancel", action: close).accessibilityIdentifier("terminal-controls-cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save).disabled(!readable || !pro.hasPro || !draft.valid).accessibilityIdentifier("terminal-controls-save")
        }
    }
    private func editorEntry(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func reload() {
        do {
            draft = try store.load()
            if draft.numberRow == nil {
                let defaults = UserDefaults.standard
                draft.numberRow = defaults.object(forKey: TerminalController.numberRowPreference) == nil || defaults.bool(forKey: TerminalController.numberRowPreference)
            }
            readable = true; issue = nil
        }
        catch { readable = false; issue = .make(.controlsUnavailable, message: "Terminal controls couldn’t be read. Existing controls and snippets are kept. Retry when device storage is available.") }
    }
    private func save() {
        guard readable, pro.hasPro, DirectAppLockV1.shared.canAccess else { return }
        do { draft = try store.save(draft); close() }
        catch TerminalControlsStore.Failure.staleDraft {
            issue = .make(.saveFailed, message: "Controls changed in another window. Reload the saved controls before editing again.")
        } catch { issue = .make(.saveFailed) }
    }
}

/// Editors own value drafts. Preview selection never acquires session input.
struct TerminalControlsEditor: View {
    @Binding var profile: TerminalControlsProfile
    var editable = true
    var destination: TerminalControlsDestination = .menu
    var libraryOnly = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: UUID?
    @State private var selectedRow = TerminalKeyboardRow.mainID
    @State private var adding = false
    @State private var search = ""
    @State private var confirmingDelete = false
    private var placed: [TerminalControlAction] {
        if destination == .keyboard, let selected, let row = profile.resolvedRows.first(where: { $0.actionIDs.contains(selected) }) { return profile.placed(in: row) }
        return profile.placed(destination)
    }
    private var saved: [TerminalControlAction] {
        profile.actions.filter { ($0.kind == .text || $0.kind == .shortcut) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    private var selection: Binding<TerminalControlAction>? {
        guard let id = selected, let current = profile.actions.first(where: { $0.id == id }) else { return nil }
        return Binding(get: { profile.actions.first { $0.id == id } ?? current }, set: { value in
            guard editable, let index = profile.actions.firstIndex(where: { $0.id == id }) else { return }
            profile.actions[index] = value
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !libraryOnly {
                VStack(alignment: .leading, spacing: 12) {
                    Label(destination.title + " Preview", systemImage: destination.symbol).font(.headline)
                    if destination == .keyboard {
                        TerminalKeyboardEditingPreview(profile: $profile, selected: selected, selectedRow: $selectedRow, select: { selected = $0 })
                    } else {
                        TerminalMenuEditingPreview(actions: placed, selected: selected, editable: editable, select: { selected = $0 }, move: move).id(dynamicTypeSize)
                    }
                    Text(destination == .keyboard ? "Select a row to add keys. Tap a custom item to edit. Preview sends nothing." : "Tap an action to edit. This preview sends nothing.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
                if destination == .keyboard {
                    Toggle("Numbers", isOn: Binding(get: { profile.numberRow ?? true }, set: { profile.numberRow = $0 })).accessibilityIdentifier("terminal-setting-numbers")
                    Toggle("Quick Up / Down", isOn: Binding(get: { profile.navigationRow ?? true }, set: { profile.navigationRow = $0 })).accessibilityIdentifier("terminal-setting-arrows")
                    Toggle("Expanded Rows", isOn: Binding(get: { profile.rowsExpanded ?? false }, set: { profile.rowsExpanded = $0 })).accessibilityIdentifier("terminal-setting-expanded")
                    Toggle("Command in Main Row", isOn: Binding(get: { profile.commandInBar ?? false }, set: { profile.commandInBar = $0 })).accessibilityIdentifier("terminal-setting-command")
                    Text("Numbers have a dedicated row. Extra rows appear only when expanded. The same layout stays above the keyboard and at the bottom when it is hidden. Command requires support from the remote app.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let selection {
                TerminalControlInspector(action: selection).id(selection.wrappedValue.id)
                    .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16)).disabled(!editable)
                Text("Content edits apply everywhere this item is used.").font(.caption).foregroundStyle(.secondary)
                if !libraryOnly {
                    HStack {
                        Button("Earlier", systemImage: "arrow.left") { moveSelected(-1) }.disabled(placed.first?.id == selected)
                        Button("Later", systemImage: "arrow.right") { moveSelected(1) }.disabled(placed.last?.id == selected)
                    }
                    if destination == .keyboard, let selected {
                        Picker("Place in Row", selection: Binding(get: { profile.resolvedRows.first(where: { $0.actionIDs.contains(selected) })?.id ?? TerminalKeyboardRow.mainID }, set: { profile.place(selected, in: $0); selectedRow = $0 })) {
                            ForEach(profile.resolvedRows.filter { $0.kind != .numbers }) { Text($0.title).tag($0.id) }
                        }.accessibilityIdentifier("terminal-item-row")
                    }
                    Button("Remove from " + destination.title, systemImage: "minus.circle") {
                        if let selected { profile.pin(selected, in: destination, enabled: false) }; selected = nil
                    }.accessibilityIdentifier("terminal-remove-placement")
                    Text("Saved shortcuts and text remain in Shortcuts & Text.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if selection != nil {
                Button("Delete Saved Item…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("terminal-delete-item")
            }
            if libraryOnly {
                TextField("Search shortcuts and text", text: $search).textFieldStyle(.roundedBorder)
                ForEach(saved) { item in
                    Button { selected = item.id } label: {
                        HStack { Image(systemName: item.symbol); VStack(alignment: .leading) { Text(item.title); Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: "pencil") }.padding(12)
                    }.buttonStyle(.bordered).accessibilityIdentifier("terminal-library-" + item.id.uuidString)
                }
                if saved.isEmpty { Text("No matching saved items. Create a shortcut or text below.").foregroundStyle(.secondary) }
            }
            Button(libraryOnly ? "Create Shortcut or Text" : "Add to " + destination.title, systemImage: "plus") { adding = true }
                .buttonStyle(.borderedProminent).disabled(!editable || profile.actions.count >= 4096).accessibilityIdentifier("terminal-control-add")
        }.disabled(!editable).privacySensitive()
            .sheet(isPresented: $adding) { addPicker }
            .confirmationDialog("Delete this item from the keyboard bar, floating menu and saved collection?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Item", role: .destructive) { if let selected { profile.delete(selected) }; selected = nil }
            }
    }
    private func previewSymbol(_ symbol: String, title: String) -> some View {
        Image(systemName: symbol).frame(minWidth: 44, minHeight: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(title)
    }
    private var addPicker: some View {
        NavigationStack {
            List {
                Section("Create New") {
                    Button("Shortcut") { var item = TerminalControlAction(title: "Shortcut", kind: .shortcut); item.character = 0x63; item.modifiers = [0xffe3]; add(item) }
                    Button("Saved Text") { add(.init(title: "Saved Text", kind: .text)) }
                }
                if !libraryOnly {
                    Section("Reuse Saved Item") {
                        TextField("Search", text: $search)
                        ForEach(saved) { item in
                            Button { profile.pin(item.id, in: destination, enabled: true); if destination == .keyboard { profile.place(item.id, in: selectedRow) }; selected = item.id; adding = false } label: {
                                VStack(alignment: .leading, spacing: 4) { Text(item.title); Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }.accessibilityLabel(item.title).accessibilityValue(item.detail)
                        }
                    }
                    ForEach(TerminalKeyCatalog.groups) { group in
                        Section(group.title) { ForEach(TerminalKeyCatalog.matching(search, in: group)) { key in
                            Button(key.name) {
                                let id = profile.pin(key, in: destination)
                                if destination == .keyboard { profile.place(id, in: selectedRow) }
                                selected = id; adding = false
                            }
                        } }
                    }
                    Section("Session Actions") { ForEach(DirectQuickActionEditing.standards(.terminal)) { item in Button(item.title) { add(.init(item)) } } }
                }
            }.navigationTitle(libraryOnly ? "Create Saved Item" : "Add to " + destination.title).directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { adding = false } } }
        }
    }
    private func actionButton(_ item: TerminalControlAction) -> some View {
        Button(item.title) { selected = item.id }.buttonStyle(.bordered)
            .tint(selected == item.id ? .accentColor : .secondary).frame(minHeight: 44)
            .draggable(item.id.uuidString).dropDestination(for: String.self) { values, _ in
                guard editable, let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }; move(source, item.id); return true
            }.accessibilityIdentifier("terminal-row-preview-" + item.id.uuidString)
    }
    private func add(_ source: TerminalControlAction) {
        guard editable else { return }
        var item = source; item.inRow = !libraryOnly && destination == .keyboard; item.inMenu = !libraryOnly && destination == .menu
        profile.actions.append(item); if item.inRow { profile.place(item.id, in: selectedRow) }; selected = item.id; adding = false
    }
    private func move(_ source: UUID, _ target: UUID) { guard editable else { return }; profile.move(source, to: target, in: destination) }
    private func moveSelected(_ offset: Int) {
        guard let selected, let index = placed.firstIndex(where: { $0.id == selected }), placed.indices.contains(index + offset) else { return }
        move(selected, placed[index + offset].id)
    }
}

/// A value-only layout editor; it has no terminal or input callbacks.
private struct TerminalKeyboardEditingPreview: View {
    @Binding var profile: TerminalControlsProfile
    let selected: UUID?
    @Binding var selectedRow: UUID
    let select: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(profile.resolvedRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button { selectedRow = row.id } label: {
                            Label(row.title, systemImage: row.id == selectedRow ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain).disabled(row.kind == .numbers).accessibilityIdentifier("terminal-select-row-" + row.id.uuidString)
                        Spacer()
                        Button { profile.moveRow(row.id, offset: -1) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Move " + row.title + " Up").disabled(profile.resolvedRows.first?.id == row.id)
                        Button { profile.moveRow(row.id, offset: 1) } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44) }.accessibilityLabel("Move " + row.title + " Down").disabled(profile.resolvedRows.last?.id == row.id)
                        if row.extra {
                            Button { profile.removeRow(row.id); if selectedRow == row.id { selectedRow = TerminalKeyboardRow.mainID } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                                .accessibilityLabel("Remove " + row.title + " Row")
                        }
                    }.font(.subheadline).buttonStyle(.borderless).frame(minHeight: 44)
                    if row.kind == .custom {
                        TextField("Row Name", text: Binding(get: { profile.resolvedRows.first { $0.id == row.id }?.title ?? row.title }, set: { name in
                            var rows = profile.resolvedRows
                            if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].title = name; profile.keyboardRows = rows }
                        })).textFieldStyle(.roundedBorder).accessibilityIdentifier("terminal-row-name-" + row.id.uuidString)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            if row.kind == .main {
                                symbol("keyboard", name: "Keyboard")
                                ForEach(["escape", "arrow.right.to.line", "control", "option", "shift"], id: \.self) { symbol($0, name: $0) }
                                if profile.commandInBar ?? false { symbol("command", name: "Command") }
                                if profile.navigationRow ?? true { symbol("arrow.up", name: "Up"); symbol("arrow.down", name: "Down") }
                            }
                            if row.kind == .numbers { ForEach(Array("1234567890"), id: \.self) { Text(String($0)).frame(minWidth: 32, minHeight: 44).background(.quaternary, in: .rect(cornerRadius: 8)) } }
                            if row.kind == .navigation { ForEach(["←", "↓", "↑", "→", "Home", "End", "PgUp", "PgDn"], id: \.self) { Text($0).frame(minWidth: 44, minHeight: 44).background(.quaternary, in: .rect(cornerRadius: 8)) } }
                            ForEach(profile.placed(in: row)) { item in
                                Button(item.title) { selectedRow = row.id; select(item.id) }.buttonStyle(.bordered)
                                    .tint(selected == item.id ? .accentColor : .secondary).frame(minHeight: 44)
                                    .draggable(item.id.uuidString).dropDestination(for: String.self) { values, _ in
                                        guard let id = values.first.flatMap(UUID.init(uuidString:)), profile.actions.contains(where: { $0.id == id }) else { return false }
                                        profile.place(id, in: row.id); profile.move(id, to: item.id, in: .keyboard); return true
                                    }.accessibilityIdentifier("terminal-row-preview-" + item.id.uuidString)
                            }
                            if row.kind == .custom && profile.placed(in: row).isEmpty { Text("Select this row, then Add to Keyboard Bar").font(.caption).foregroundStyle(.secondary) }
                            if row.kind == .main { symbol("chevron.up.chevron.down", name: "Expand Rows"); symbol("ellipsis", name: "Floating Menu") }
                        }
                    }.accessibilityIdentifier(row.kind == .main ? "terminal-row-preview-scroll" : "terminal-row-preview-scroll-" + row.id.uuidString)
                    if row.kind == .numbers && !(profile.numberRow ?? true) { Text("Hidden · turn on Numbers below").font(.caption).foregroundStyle(.secondary) }
                    if row.extra { Text((profile.rowsExpanded ?? false) ? "Visible when expanded" : "Hidden until you expand the bar").font(.caption).foregroundStyle(.secondary) }
                }.padding(8).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
            }
            Menu("Add Row", systemImage: "plus") {
                if !profile.resolvedRows.contains(where: { $0.kind == .navigation }) { Button("Navigation") { if let id = profile.addRow(title: "Navigation", navigation: true) { selectedRow = id } } }
                Button("Shortcuts") { if let id = profile.addRow(title: "Shortcuts") { selectedRow = id } }
                Button("Custom Row") { if let id = profile.addRow() { selectedRow = id } }
            }.disabled(profile.resolvedRows.count >= 4).accessibilityIdentifier("terminal-add-row")
            Text("Add up to two extra rows. Move entire rows up or down. Removing a row keeps its saved items.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func symbol(_ name: String, name title: String) -> some View {
        Image(systemName: name).frame(minWidth: 44, minHeight: 44).background(.quaternary, in: .rect(cornerRadius: 8)).accessibilityLabel(title)
    }
}

private struct TerminalControlInspector: View {
    @Binding var action: TerminalControlAction
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if action.kind == .shortcut {
                DirectQuickActionInspector(action: Binding(get: { action.shortcut }, set: { action.title = $0.title; action.character = $0.key; action.modifiers = $0.modifiers }), mode: .terminal)
                Label(action.shortcut.shortcutTitle, systemImage: "keyboard").font(.headline).accessibilityIdentifier("terminal-shortcut-preview")
            } else {
                Label(action.kind == .text ? "Saved Text" : action.kind == .builtIn ? "Session Action" : "Terminal Key", systemImage: action.symbol).font(.headline)
                TextField("Name", text: $action.title).textFieldStyle(.roundedBorder).accessibilityIdentifier("terminal-control-name")
                if action.kind == .text { DirectSavedTextEditor(text: $action.text, mode: .terminal, maximumBytes: 4096) }
                if action.kind == .key { Picker("Key", selection: $action.key) { ForEach(TerminalAccessoryKey.allCases) { key in Text(key.title).tag(Optional(key)) } } }
            }
            if !action.valid { Text("Enter a name up to 40 characters and valid content. Text supports up to 4096 UTF-8 bytes.").font(.caption).foregroundStyle(.red) }
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
