#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

private enum TerminalLayoutPanel: Identifiable {
    case rows, add(UUID?, TerminalBarItem?), item(TerminalBarItem, UUID?), placement(TerminalBarPlacement, UUID?), preview
    var id: String {
        switch self {
        case .rows: "rows"
        case .add(let row, let item): "add-\(row?.uuidString ?? "menu")-\(item?.id ?? "new")"
        case .item(let item, let row): "item-\(item.id)-\(row?.uuidString ?? "menu")"
        case .placement(let value, let row): "placement-\(value.id)-\(row?.uuidString ?? "menu")"
        case .preview: "preview"
        }
    }
}

/// Draft history is local to a destination. Removing a placement never deletes
/// its definition, and restoring/undoing never writes the shared store.
struct TerminalLayoutHistory {
    private(set) var values: [TerminalControlsProfile] = []
    private var restoring: TerminalControlsProfile?
    mutating func changed(from old: TerminalControlsProfile, to new: TerminalControlsProfile) {
        if restoring == new { restoring = nil; return }
        values.append(old)
        if values.count > 30 { values.removeFirst() }
    }
    mutating func undo() -> TerminalControlsProfile? {
        guard let value = values.popLast() else { return nil }
        restoring = value
        return value
    }
}

private struct TerminalLayoutUndoNotice: View {
    let title: String
    let undo: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 8)
            Button("Undo", action: undo).font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("terminal-editor-undo")
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 16).padding(.vertical, 8)
            .background(.regularMaterial, in: .rect(cornerRadius: 16)).padding(12)
    }
}

struct TerminalKeyboardEditingPreview: View {
    @Binding var profile: TerminalControlsProfile
    let selected: UUID?
    @Binding var selectedRow: UUID
    let select: (UUID?) -> Void
    var contextImage: UIImage?
    var insertion: UUID?
    @State private var panel: TerminalLayoutPanel?
    @State private var history = TerminalLayoutHistory()
    @State private var previewing = false
    @State private var restoring = false
    @State private var barHeight: CGFloat = 180
    @State private var editorHeight: CGFloat = 600
    @State private var pending: UUID?
    @State private var started = false
    @State private var removing: UUID?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                if !compact {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your keyboard").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("Tap a key to edit. Drag a handle to move a row.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Menu {
                    if !history.values.isEmpty { Button("Undo Last Change", systemImage: "arrow.uturn.backward", action: undo) }
                    Button("Preview with Keyboard", systemImage: "keyboard") { previewing = true }
                        .accessibilityIdentifier("terminal-preview-keyboard")
                    Button("Restore Keyboard Bar…", systemImage: "arrow.counterclockwise") { restoring = true }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Keyboard Options").accessibilityIdentifier("terminal-row-options")
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 20).padding(.vertical, compact ? 0 : 20)
            if let pending, let action = profile.actions.first(where: { $0.id == pending }) {
                Label("Choose a row’s Add Key action to place " + action.title, systemImage: "plus.circle").font(.subheadline).padding(.horizontal, 20)
            }
            Spacer(minLength: compact ? 0 : 12)
            ScrollView(.vertical) {
                TerminalKeyboardBarPreview(profile: profile, allRows: true, handles: true,
                    select: { item, row in
                        selectedRow = row
                        if placePending(in: row) { return }
                        if let item { show(.item(item, row)) }
                    }, move: { item, source, target, before in
                        profile.placeBarItem(item, in: target, from: source, before: before)
                    }, remove: { item, row in profile.removeBarItem(item, in: row) },
                    moveRow: { source, target in profile.moveRow(source, before: target) },
                    addPreset: { preset, target in _ = profile.installEditorPreset(preset, before: target) },
                    addItem: { item, target, before in profile.placeBarItem(item, in: target, before: before) },
                    addToRow: { row in
                        selectedRow = row
                        if !placePending(in: row) { show(.add(row, nil)) }
                    }, rowAction: rowAction,
                    placementSelect: { placement, row in
                        selectedRow = row
                        if !placePending(in: row) { show(.placement(placement, row)) }
                    }, placementMove: { id, source, target, before in profile.moveBarPlacement(id, from: source, to: target, before: before) },
                    placementRemove: { id, row in profile.removeBarPlacement(id, in: row) },
                    placementAdd: { item, row, before in profile.addBarPlacement(item, to: row, before: before) })
                    .accessibilityIdentifier("terminal-live-bar-preview")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { barHeight = $0 } }
            }.scrollBounceBehavior(.basedOnSize)
                .frame(height: min(barHeight, max(60, editorHeight - (compact ? 126 : 226))))
                .background(Color(uiColor: .secondarySystemBackground))
            HStack {
                Button("Add Row", systemImage: "plus") { show(.rows) }.buttonStyle(.bordered)
                    .accessibilityIdentifier("terminal-add-row")
                Spacer()
                Text("\(profile.resolvedRows.count) rows").font(.caption).foregroundStyle(.secondary)
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 20).padding(.vertical, 16)
            if !compact {
                Text("Applies to every Mac on this device.").font(.caption).foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.bottom, 12)
            }
        }.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editorHeight = $0 }
            .onAppear {
                guard !started else { return }; started = true
                pending = insertion
            }
            .onChange(of: profile) { old, new in history.changed(from: old, to: new) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !history.values.isEmpty { TerminalLayoutUndoNotice(title: "Keyboard bar updated", undo: undo) }
            }
            .sheet(item: $panel) { panel in
                switch panel {
                case .rows: TerminalEditorRowPicker(profile: $profile) { self.panel = nil }
                case .add(let row, let item): TerminalEditorItemPicker(profile: $profile, destination: .keyboard, rowID: row, replacing: item) { self.panel = nil }
                case .item(let item, let row): TerminalEditorItemActions(profile: $profile, item: item, rowID: row) { self.panel = nil }
                case .placement(let value, let row): TerminalEditorItemActions(profile: $profile, item: value.item, rowID: row, placementID: value.id) { self.panel = nil }
                case .preview: EmptyView()
                }
            }
            .fullScreenCover(isPresented: $previewing) { TerminalDockedKeyboardPreview(profile: profile) }
            .confirmationDialog("Restore the default keyboard bar?", isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore Layout") { profile.restoreKeyboardBar() }
            } message: { Text("Saved shortcuts, text and menu favorites stay available. You can undo this change.") }
            .confirmationDialog(profile.resolvedRows.count == 1 ? "Clear this row?" : "Remove this row?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { id in
                Button(profile.resolvedRows.count == 1 ? "Clear Row" : "Remove Row", role: .destructive) {
                    profile.removeEditorRow(id); removing = nil
                }.accessibilityIdentifier("terminal-remove-row")
            } message: { _ in Text("Saved shortcuts and text stay available. You can undo this change.") }
    }
    private func rowAction(_ id: UUID, _ action: TerminalKeyboardRow.MenuAction) {
        guard let row = profile.resolvedRows.first(where: { $0.id == id }) else { return }
        selectedRow = id
        switch action {
        case .visibility(let visibility):
            guard row.kind != .main else { return }
            editRow(id) { $0.visibility = visibility }
        case .alignment(let alignment): editRow(id) { $0.alignment = alignment }
        case .scrollStart(let value): editRow(id) { $0.scrollStart = value }
        case .remove: removing = id
        }
    }
    private func editRow(_ id: UUID, _ change: (inout TerminalKeyboardRow) -> Void) {
        var rows = profile.resolvedRows
        if let index = rows.firstIndex(where: { $0.id == id }) { change(&rows[index]); profile.keyboardRows = rows }
    }
    private func show(_ panel: TerminalLayoutPanel) { self.panel = panel }
    private func placePending(in row: UUID) -> Bool {
        guard let pending else { return false }
        profile.place(pending, in: row); self.pending = nil; return true
    }
    private func undo() { if let value = history.undo() { profile = value } }
}

struct TerminalFloatingMenuEditor: View {
    @Binding var profile: TerminalControlsProfile
    var contextImage: UIImage?
    var insertion: UUID?
    @State private var panel: TerminalLayoutPanel?
    @State private var history = TerminalLayoutHistory()
    @State private var restoring = false
    @State private var started = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your favorites").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("Tap to edit. Drag a favorite to change its position.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        if !history.values.isEmpty { Button("Undo Last Change", systemImage: "arrow.uturn.backward", action: undo) }
                        Button("Restore Menu Favorites…", systemImage: "arrow.counterclockwise") { restoring = true }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Menu Options").accessibilityIdentifier("terminal-menu-options")
                }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                TerminalMenuEditingPreview(actions: profile.menuPreviewActions, selected: nil, editable: true,
                    select: { id in
                        if let value = profile.resolvedMenuPlacements.first(where: { $0.id == id }) { panel = .placement(.init(id: id.uuidString, item: .saved(value.actionID)), nil) }
                    }, move: { profile.moveMenuPlacement($0, to: $1) },
                    add: { panel = .add(nil, nil) })
                    .accessibilityIdentifier("terminal-menu-preview")
                Button("Preview Full Menu", systemImage: "arrow.up.right") { panel = .preview }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("terminal-full-menu-preview")
                Text("Applies to every Mac on this device.").font(.caption).foregroundStyle(.secondary).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.padding(20)
        }.onAppear {
            guard !started else { return }; started = true
            if let insertion { profile.pin(insertion, in: .menu, enabled: true) }
        }
            .onChange(of: profile) { old, new in history.changed(from: old, to: new) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !history.values.isEmpty { TerminalLayoutUndoNotice(title: "Menu favorites updated", undo: undo) }
            }
            .sheet(item: $panel) { panel in
                switch panel {
                case .add: TerminalEditorItemPicker(profile: $profile, destination: .menu) { self.panel = nil }
                case .item(let item, _): TerminalEditorItemActions(profile: $profile, item: item) { self.panel = nil }
                case .placement(let value, _): TerminalEditorItemActions(profile: $profile, item: value.item, placementID: value.id) { self.panel = nil }
                case .preview: TerminalFullMenuPreview(profile: profile)
                default: EmptyView()
                }
            }
            .confirmationDialog("Restore the default menu favorites?", isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore Favorites") { profile.restoreMenuFavorites() }
            } message: { Text("Your keyboard bar and saved items stay available. You can undo this change.") }
    }
    private func undo() { if let value = history.undo() { profile = value } }
}

private struct TerminalFullMenuPreview: View {
    let profile: TerminalControlsProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                TerminalMenuEditingPreview(actions: profile.menuPreviewActions, selected: nil, editable: false,
                    select: { _ in }, move: { _, _ in }, fullMenu: true)
                    .padding(.vertical, 20).frame(maxWidth: .infinity)
            }.navigationTitle("Menu Preview").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

private struct TerminalEditorRowPicker: View {
    @Binding var profile: TerminalControlsProfile
    let finished: () -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("terminal-add-error") }
                    ForEach(TerminalRowPreset.allCases) { preset in
                        Button {
                            install(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(preset == .blank ? "Empty Row" : preset.rawValue).font(.headline); Spacer(); Image(systemName: "plus") }
                                ScrollView(.horizontal) {
                                    HStack(spacing: 4) {
                                        ForEach(preset.items) { item in
                                            Group { if let symbol = item.symbol { Image(systemName: symbol) } else { Text(item.palette?.title ?? item.title(in: profile)) } }
                                                .frame(minWidth: 35, minHeight: 40).padding(.horizontal, 5)
                                                .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 7))
                                        }
                                        if preset == .blank { Text("Choose every key yourself").font(.subheadline).foregroundStyle(.secondary) }
                                    }
                                }.scrollIndicators(.hidden)
                            }.padding(12).background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 14))
                        }.buttonStyle(.plain).dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityIdentifier("terminal-row-template-" + preset.id)
                    }
                }.padding(20)
            }.navigationTitle("Add Row").directInlineNavigationTitle().toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: finished) }
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)

    }
    private func install(_ preset: TerminalRowPreset) {
        if profile.installEditorPreset(preset, before: profile.resolvedRows.first?.id) != nil { finished() }
        else { error = "Six rows are configured. Remove a row before adding another." }
    }
}

private struct TerminalEditorItemPicker: View {
    @Binding var profile: TerminalControlsProfile
    let destination: TerminalControlsDestination
    var rowID: UUID?
    var replacing: TerminalBarItem?
    var placementID: String?
    let finished: () -> Void
    @State private var page = "Keys"
    @State private var query = ""
    @State private var creation: TerminalControlAction?
    @State private var presetPack: TerminalShortcutPack?
    @State private var completed = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var title: String { replacing != nil ? "Replace Key" : destination == .menu ? "Add Favorite" : "Add to Row" }
    private var searchPrompt: String {
        switch page { case "Actions": "Find an action"; case "Keys": "Find a key"; case "Shortcuts": "Find a shortcut"; default: "Find saved text" }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if replacing == nil {
                        Picker("Add", selection: $page) { ForEach(destination == .menu ? ["Actions", "Keys", "Shortcuts", "Text"] : ["Keys", "Shortcuts", "Text"], id: \.self) { Text($0) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("terminal-add-page")
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("terminal-add-error") }
                    if page == "Actions" && replacing == nil { actions }
                    else if page == "Keys" || replacing != nil { keys }
                    else { saved }
                }.padding(20)
            }.navigationTitle(title).directInlineNavigationTitle()
                .searchable(text: $query, prompt: searchPrompt)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: finished) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .onAppear { if destination == .menu && replacing == nil { page = "Actions" } }
            .sheet(item: $creation, onDismiss: { if completed { finished() } }) { item in
                TerminalSavedControlEditor(action: item, profile: profile, localDraft: true, creating: true, apply: { value in
                    guard value.valid, profile.actions.count < 4096 else { return false }
                    profile.actions.append(value)
                    if destination == .keyboard, let rowID { profile.place(value.id, in: rowID) }
                    else { profile.pin(value.id, in: .menu, enabled: true) }
                    completed = true; creation = nil; return true
                })
            }
            .sheet(item: $presetPack, onDismiss: { if completed { finished() } }) { pack in
                TerminalShortcutPresetPicker(profile: profile, initialPack: pack, placement: true) { choices in
                    var draft = profile
                    for preset in choices {
                        guard let id = draft.add(preset) else { return false }
                        if destination == .keyboard, let rowID { draft.place(id, in: rowID) }
                        else { draft.pin(id, in: .menu, enabled: true) }
                    }
                    profile = draft; completed = true; presetPack = nil; return true
                }
            }

    }
    @ViewBuilder private var keys: some View {
        let controls = TerminalBarItem.Control.allCases.filter {
            let item = TerminalBarItem.control($0)
            return $0 != .command && (query.isEmpty || (item.title(in: profile) + " " + $0.rawValue + " " + (item.symbol ?? "")).localizedCaseInsensitiveContains(query))
        }
        if destination == .keyboard && !controls.isEmpty {
            Text("Controls & Modifiers").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 64))], spacing: 8) {
                ForEach(controls, id: \.self) { control in
                    let item = TerminalBarItem.control(control)
                    Button { place(item) } label: { Image(systemName: item.symbol ?? "keyboard").font(.body) }
                        .buttonStyle(TerminalKeycapStyle()).accessibilityLabel(item.title(in: profile))
                        .accessibilityHint("Add to the selected keyboard row")
                        .accessibilityIdentifier("terminal-add-control-" + control.rawValue)
                }
            }
        }
        ForEach(TerminalKeyCatalog.groups.filter { $0.title != "Common Shortcuts" }) { group in
            let keys = TerminalKeyCatalog.matching(query, in: group)
            if !keys.isEmpty {
                Text(group.title).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 64))], spacing: 8) {
                    ForEach(keys) { key in
                        Button { place(.key(key.id)) } label: { Text(key.title) }
                            .buttonStyle(TerminalKeycapStyle()).accessibilityLabel(key.name).accessibilityIdentifier("terminal-add-" + key.id)
                    }
                }
            }
        }
    }
    private var actions: some View {
        VStack(spacing: 8) {
            ForEach(TerminalAppAction.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }) { standard in
                Button {
                    if let existing = profile.actions.first(where: { $0.operation == standard }) {
                        profile.pin(existing.id, in: .menu, enabled: true)
                    } else {
                        guard profile.actions.count < 4096 else { error = "The saved control limit has been reached."; return }
                        var action = standard.definition; action.inMenu = false
                        profile.actions.append(action); profile.pin(action.id, in: .menu, enabled: true)
                    }
                    finished()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: standard.symbol).frame(width: 24)
                        Text(standard.title).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus")
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("terminal-add-action-" + standard.rawValue)
            }
        }
    }
    private var saved: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(page == "Text" ? "Create Saved Text" : "Create Shortcut", systemImage: "plus") {
                creation = .init(title: "", kind: page == "Text" ? .text : .shortcut, inMenu: false)
            }.accessibilityIdentifier("terminal-create-inline")
            if page == "Shortcuts" {
                Text("Tool Shortcuts").font(.headline).padding(.top, 8)
                TerminalPresetEntries { presetPack = $0 }
                if let group = TerminalKeyCatalog.groups.first(where: { $0.title == "Common Shortcuts" }) {
                    let keys = TerminalKeyCatalog.matching(query, in: group)
                    if !keys.isEmpty {
                        Text("Common Shortcuts").font(.headline).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 64))], spacing: 8) {
                            ForEach(keys) { key in
                                Button { place(.key(key.id)) } label: { Text(key.title) }
                                    .buttonStyle(TerminalKeycapStyle()).accessibilityLabel(key.name)
                                    .accessibilityIdentifier("terminal-add-" + key.id)
                            }
                        }
                    }
                }
            }
            Text(page == "Text" ? "Saved Text" : "Your Shortcuts").font(.headline).padding(.top, 8)
            ForEach(profile.savedItems(page == "Text" ? .text : .shortcuts).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }) { item in
                Button { place(.saved(item.id)) } label: {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(item.title); Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: "plus") }
                        .frame(minHeight: 48)
                }.accessibilityIdentifier("terminal-reuse-" + item.id.uuidString)
            }
        }
    }
    private func place(_ item: TerminalBarItem) {
        if destination == .keyboard, let rowID {
            if let replacing {
                guard profile.replaceEditorItem(replacing, in: rowID, with: item, placementID: placementID) else { error = "This placement is no longer available."; return }
            } else {
                profile.placeBarItem(item, in: rowID)
            }
        } else if let replacing, let id = replacing.savedID, let key = item.palette {
            guard profile.replaceEditorFavorite(id, with: key) else { return }
        } else if let id = item.savedID { profile.pin(id, in: .menu, enabled: true) }
        else if let key = item.palette { profile.pin(key, in: .menu) }
        finished()
    }
}

private struct TerminalEditorItemActions: View {
    @Binding var profile: TerminalControlsProfile
    let item: TerminalBarItem
    var rowID: UUID?
    var placementID: String?
    let finished: () -> Void
    @State private var editing: TerminalControlAction?
    @State private var replacing = false
    @State private var completed = false
    private var action: TerminalControlAction? { profile.actions.first { $0.id == item.savedID } }
    private var items: [TerminalBarPlacement] {
        if let row = profile.resolvedRows.first(where: { $0.id == rowID }) { return profile.barPlacements(in: row) }
        return profile.resolvedMenuPlacements.map { .init(id: $0.id.uuidString, item: .saved($0.actionID)) }
    }
    private var position: Int { items.firstIndex { placementID == nil ? $0.item == item : $0.id == placementID } ?? 0 }
    private var selectedPlacement: TerminalBarPlacement? { items.indices.contains(position) ? items[position] : nil }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(item.title(in: profile), systemImage: action?.symbol ?? item.symbol ?? "keyboard").font(.headline)
                    if let action { Text(action.detail).font(.subheadline).foregroundStyle(.secondary) }
                }
                Section {
                    if let action, action.kind == .shortcut || action.kind == .text {
                        Button(action.kind == .text ? "Edit Text" : "Edit Shortcut", systemImage: "pencil") { editing = action }.accessibilityIdentifier("terminal-edit-selected")
                    } else if action?.kind != .builtIn {
                        Button("Replace Key", systemImage: "pencil") { replacing = true }.accessibilityIdentifier("terminal-replace-key")
                    }
                    if position > 0 { Button("Move Earlier", systemImage: "arrow.left") { move(-1) }.accessibilityIdentifier("terminal-move-earlier") }
                    if position + 1 < items.count { Button("Move Later", systemImage: "arrow.right") { move(1) }.accessibilityIdentifier("terminal-move-later") }
                    if let rowID {
                        NavigationLink("Move to Another Row") {
                            List { ForEach(profile.resolvedRows.filter { $0.id != rowID }) { target in
                                Button(profile.rowTitle(target.id)) { if let selectedPlacement { profile.moveBarPlacement(selectedPlacement.id, from: rowID, to: target.id) }; finished() }
                                    .accessibilityIdentifier("terminal-move-to-" + target.id.uuidString)
                            } }.navigationTitle("Move Key").directInlineNavigationTitle()
                        }.accessibilityIdentifier("terminal-item-row")
                    }
                    Button(rowID == nil ? "Remove from Favorites" : "Remove from Row", systemImage: "minus.circle", role: .destructive) {
                        if let id = selectedPlacement?.id {
                            if let rowID { profile.removeBarPlacement(id, in: rowID) }
                            else if let uuid = UUID(uuidString: id) { profile.removeMenuPlacement(uuid) }
                        }
                        finished()
                    }.accessibilityIdentifier("terminal-remove-placement")
                } footer: { if action != nil { Text("Removing this placement keeps the saved item available.") } }
            }.navigationTitle(item.title(in: profile)).directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close", action: finished) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .sheet(item: $editing, onDismiss: { if completed { finished() } }) { action in
                TerminalSavedControlEditor(action: action, profile: profile, localDraft: true, apply: { value in
                    guard let index = profile.actions.firstIndex(where: { $0.id == value.id }) else { return false }
                    profile.actions[index] = value; completed = true; editing = nil; return true
                })
            }
            .sheet(isPresented: $replacing) {
                TerminalEditorItemPicker(profile: $profile, destination: rowID == nil ? .menu : .keyboard, rowID: rowID, replacing: item, placementID: placementID) {
                    completed = true; replacing = false
                }
            }.onChange(of: replacing) { _, value in if !value && completed { finished() } }
    }
    private func move(_ offset: Int) {
        if let rowID {
            let before = offset < 0 ? items[position - 1] : (position + 2 < items.count ? items[position + 2] : nil)
            if let selectedPlacement { profile.moveBarPlacement(selectedPlacement.id, from: rowID, to: rowID, before: before?.id) }
        } else if let id = selectedPlacement.flatMap({ UUID(uuidString: $0.id) }), let target = UUID(uuidString: items[position + offset].id) { profile.moveMenuPlacement(id, to: target) }
        finished()
    }
}

#endif
