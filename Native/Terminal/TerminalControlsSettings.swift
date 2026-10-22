#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct TerminalControlsSettings: View {
    var store = TerminalControlsStore()
    var initialLibrary: TerminalSavedItemsSection?
    var contextImage: UIImage?
    let close: () -> Void
    @State private var profile = TerminalControlsProfile.defaults
    @State private var readable = false
    @State private var issue: DirectRecoveryNotice?
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    @State private var layout: LayoutRequest?
    private struct LayoutRequest: Identifiable {
        var id = UUID()
        let destination: TerminalControlsDestination
        var item: UUID?
    }
    var body: some View {
        NavigationStack {
            Group {
                if let initialLibrary { library(initialLibrary) }
                else {
                    List {
                        Section {
                            Button { layout = .init(destination: .keyboard) } label: {
                                entry("Keyboard Bar", summary: "\(profile.resolvedRows.count) customizable rows", symbol: "keyboard")
                            }.accessibilityIdentifier("terminal-edit-keyboard")
                            Button { layout = .init(destination: .menu) } label: {
                                entry("Floating Menu", summary: "\(profile.placed(.menu).count) favorites", symbol: "ellipsis.circle")
                            }.accessibilityIdentifier("terminal-edit-menu")
                        } header: { Text("Layout") }
                        Section {
                            ForEach([TerminalSavedItemsSection.shortcuts, .text], id: \.self) { section in
                                NavigationLink { library(section) } label: {
                                    entry(section.managementTitle, summary: "\(profile.savedItems(section).count) saved items", symbol: section == .shortcuts ? "keyboard" : "text.quote")
                                }.accessibilityIdentifier("terminal-edit-" + (section == .shortcuts ? "shortcuts" : "text"))
                            }
                        } footer: { Text("Applies to every Mac on this device.") }
                        recovery
                    }.navigationTitle("Terminal Controls").directInlineNavigationTitle()
                }
            }.toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close).buttonStyle(.borderedProminent).accessibilityIdentifier("terminal-controls-cancel")
            } }
        }.interactiveDismissDisabled().presentationSizing(.page).directAppearance()
            .onAppear(perform: reload)
            .fullScreenCover(item: $layout) { request in
                TerminalLayoutSheet(profile: profile, destination: request.destination, item: request.item,
                    editable: readable && pro.hasPro, contextImage: contextImage, apply: commit)
            }
            .sheet(isPresented: $paywall) { DirectProView() }
    }
    private func library(_ section: TerminalSavedItemsSection) -> some View {
        Group {
            if !readable {
                List { recovery }
            } else if !pro.hasPro {
                ContentUnavailableView {
                    Label("Customize with Pro", systemImage: "sparkles")
                } description: {
                    Text("Create and arrange shortcuts and saved text with Pro.")
                } actions: {
                    Button("View Pro Options") { paywall = true }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("terminal-library-pro")
                }
            } else {
                VStack(spacing: 0) {
                    if let issue {
                        DirectRecoveryCard(notice: issue, primary: .init(title: "Reload Saved Controls", perform: reload))
                            .padding(12).accessibilityIdentifier("terminal-controls-recovery")
                    }
                    TerminalSavedLibrary(profile: $profile, section: section, editable: true, persist: commit,
                        place: { id, destination in layout = .init(destination: destination, item: id) })
                }
            }
        }.navigationTitle(section.managementTitle).directInlineNavigationTitle()
    }
    @ViewBuilder private var recovery: some View {
        if !readable || issue != nil {
            Section { DirectRecoveryCard(notice: issue ?? .make(.controlsUnavailable), primary: .init(title: "Reload Saved Controls", perform: reload)) }
                .accessibilityIdentifier("terminal-controls-recovery")
        }
        if !pro.hasPro { Section { Button("Customize with Pro", systemImage: "sparkles") { paywall = true } } }
    }
    private func entry(_ title: String, summary: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) { Text(title); Text(summary).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.foregroundStyle(.primary).padding(.vertical, 5)
    }
    private func reload() {
        do {
            profile = try store.load()
            readable = true; issue = nil
        } catch TerminalControlsStore.Failure.newerFormat {
            readable = false; issue = .make(.controlsUnavailable, message: TerminalControlsStore.newerFormatMessage)
        } catch { readable = false; issue = .make(.controlsUnavailable) }
    }
    private func commit(_ draft: TerminalControlsProfile) -> Bool {
        guard readable, pro.hasPro, DirectAppLockV1.shared.canAccess else { return false }
        do { profile = try store.save(draft); issue = nil; return true }
        catch TerminalControlsStore.Failure.staleDraft {
            issue = .make(.saveFailed, message: "Controls changed in another window. Close this editor and reload before trying again.")
        } catch TerminalControlsStore.Failure.newerFormat {
            readable = false; issue = .make(.controlsUnavailable, message: TerminalControlsStore.newerFormatMessage)
        } catch { issue = .make(.saveFailed) }
        return false
    }
}

private struct TerminalLayoutSheet: View {
    @State var profile: TerminalControlsProfile
    let destination: TerminalControlsDestination
    var item: UUID?
    let editable: Bool
    var contextImage: UIImage?
    let apply: (TerminalControlsProfile) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var initial: TerminalControlsProfile?
    @State private var discarding = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if failed { Text("Couldn’t save. Your draft is still open. Close and reload if controls changed in another window.").font(.caption).foregroundStyle(.red).padding(12) }
                if editable {
                    TerminalControlsEditor(profile: $profile, destination: destination, contextImage: contextImage, insertion: item)
                } else {
                    ContentUnavailableView("Customization Unavailable", systemImage: "slider.horizontal.3", description: Text("Close this editor to check Pro access or reload your saved controls."))
                }
            }.navigationTitle(destination == .keyboard ? "Keyboard Bar" : "Menu Favorites").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
                        if let initial, initial != profile { discarding = true } else { dismiss() }
                    }.accessibilityIdentifier("terminal-layout-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { if !editable || apply(profile) { dismiss() } else { failed = true } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("terminal-controls-save")
                    }
                }
        }.interactiveDismissDisabled().directAppearance().onAppear { if initial == nil { initial = profile } }
            .confirmationDialog("Discard changes?", isPresented: $discarding, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: { Text("Your layout changes have not been saved.") }
    }
}

/// A destination editor owns only a value draft, never a terminal input owner.
struct TerminalControlsEditor: View {
    @Binding var profile: TerminalControlsProfile
    var editable = true
    var destination: TerminalControlsDestination = .menu
    var libraryOnly = false
    var contextImage: UIImage?
    var insertion: UUID?
    @State private var selectedRow = TerminalKeyboardRow.mainID
    var body: some View {
        Group {
            if libraryOnly {
                TerminalSavedLibrary(profile: $profile, section: .shortcuts, editable: editable, persist: { profile = $0; return true }, place: { _, _ in })
            } else if destination == .keyboard {
                TerminalKeyboardEditingPreview(profile: $profile, selected: nil, selectedRow: $selectedRow, select: { _ in }, contextImage: contextImage, insertion: insertion)
            } else {
                TerminalFloatingMenuEditor(profile: $profile, contextImage: contextImage, insertion: insertion)
            }
        }.disabled(!editable).privacySensitive()
    }
}

struct TerminalSavedLibrary: View {
    @Binding var profile: TerminalControlsProfile
    let section: TerminalSavedItemsSection
    var editable: Bool
    let persist: (TerminalControlsProfile) -> Bool
    let place: (UUID, TerminalControlsDestination) -> Void
    @State private var query = ""
    @State private var editing: TerminalControlAction?
    @State private var presetPack: TerminalShortcutPack?
    @State private var deleting: TerminalControlAction?
    @State private var editMode = EditMode.inactive
    private var items: [TerminalControlAction] {
        profile.savedItems(section).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button { editing = item } label: { itemLabel(item) }.buttonStyle(.plain)
                            .accessibilityIdentifier("terminal-library-" + item.id.uuidString)
                        if editMode != .active {
                            Menu {
                                Button("Edit", systemImage: "pencil") { editing = item }
                                ForEach(TerminalControlsDestination.allCases) { destination in
                                    Button("Add to " + destination.title, systemImage: destination.symbol) { place(item.id, destination) }
                                }
                                Button("Delete…", systemImage: "trash", role: .destructive) { deleting = item }
                            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Actions for " + item.title)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Edit", systemImage: "pencil") { editing = item }.tint(.accentColor)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
                    }
                }.onMove { source, destination in
                    var order = profile.savedItems(section).map(\.id)
                    order.move(fromOffsets: source, toOffset: destination)
                    var draft = profile; draft.reorderLibrary(section, ids: order); _ = commit(draft)
                }.moveDisabled(!query.isEmpty)
                if items.isEmpty {
                    ContentUnavailableView(section == .shortcuts ? "No Shortcuts" : "No Saved Text", systemImage: section == .shortcuts ? "keyboard" : "text.quote", description: Text(query.isEmpty ? "Tap + to create your first item." : "Try another search."))
                }
            } footer: { Text("Shared by every Mac on this device. Tap or swipe right to edit; swipe left to delete.") }
            if section == .shortcuts && editMode != .active {
                Section("Tool Shortcuts") { TerminalPresetEntries { presetPack = $0 } }
            }
        }.searchable(text: $query, prompt: section == .shortcuts ? "Search shortcuts" : "Search saved text")
            .environment(\.editMode, $editMode)
            .onChange(of: query) { _, query in if !query.isEmpty { editMode = .inactive } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if profile.savedItems(section).count > 1 && query.isEmpty {
                        Button(editMode == .active ? "Finish Reordering" : "Reorder", systemImage: editMode == .active ? "checkmark" : "arrow.up.arrow.down") {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        }.accessibilityIdentifier("terminal-library-reorder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(section == .shortcuts ? "New Shortcut" : "New Saved Text", systemImage: "plus") {
                        editing = .init(title: "", kind: section.kind, inMenu: false)
                    }.accessibilityIdentifier("terminal-library-create").disabled(!editable)
                }
            }
            .sheet(item: $editing) { item in
                TerminalSavedControlEditor(action: item, profile: profile, creating: !profile.actions.contains { $0.id == item.id }, apply: { action in
                    var draft = profile
                    if let index = draft.actions.firstIndex(where: { $0.id == action.id }) { draft.actions[index] = action }
                    else { draft.actions.append(action) }
                    let saved = commit(draft); if saved { editing = nil }; return saved
                }, delete: profile.actions.contains { $0.id == item.id } ? {
                    var draft = profile; draft.delete(item.id)
                    let saved = commit(draft); if saved { editing = nil }; return saved
                } : nil)
            }
            .sheet(item: $presetPack) { pack in
                TerminalShortcutPresetPicker(profile: profile, initialPack: pack) { chosen in
                    var draft = profile
                    for preset in chosen { guard draft.add(preset) != nil else { return false } }
                    return commit(draft)
                }
            }
            .confirmationDialog("Delete this saved item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Saved Item", role: .destructive) {
                    if let deleting { var draft = profile; draft.delete(deleting.id); _ = commit(draft) }; deleting = nil
                }
            } message: {
                if let deleting {
                    let placements = deleting.placements(in: profile)
                    Text(placements.isEmpty ? "This item has no placements." : "Also removes it from: " + placements.joined(separator: ", ") + ".")
                }
            }.disabled(!editable)
    }
    private func itemLabel(_ item: TerminalControlAction) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).foregroundStyle(.primary)
            Text(item.detail).font(item.kind == .text ? .system(.caption, design: .monospaced) : .caption).foregroundStyle(.secondary).lineLimit(2)
            if let usage = item.usage { Text(usage).font(.caption).foregroundStyle(.secondary) }
            let placements = item.placements(in: profile)
            Text(placements.isEmpty ? "Not placed yet" : placements.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    private func commit(_ draft: TerminalControlsProfile) -> Bool {
        guard editable else { return false }
        return persist(draft)
    }
}

/// The same named entry points are used by libraries and direct placement.
struct TerminalPresetEntries: View {
    let select: (TerminalShortcutPack) -> Void
    var body: some View {
        ForEach([TerminalShortcutPack.tmux, .zellij, .herdr]) { pack in
            Button(pack == .zellij ? "Zellij" : pack.title, systemImage: "square.stack.3d.up") { select(pack) }
                .accessibilityIdentifier("terminal-tool-presets-" + pack.id)
        }
    }
}

struct TerminalShortcutPresetPicker: View {
    let profile: TerminalControlsProfile
    var initialPack: TerminalShortcutPack = .tmux
    var placement = false
    let add: ([TerminalShortcutPreset]) -> Bool
    @State private var pack = TerminalShortcutPack.tmux
    @State private var selected: Set<String> = []
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    private var all: [TerminalShortcutPreset] { TerminalShortcutPack.allCases.flatMap(\.shortcuts) }
    var body: some View {
        NavigationStack {
            List {
                if initialPack == .zellij || initialPack == .zellijUnlock {
                    Section { Picker("Keybindings", selection: $pack) {
                        Text("Default").tag(TerminalShortcutPack.zellij)
                        Text("Unlock First").tag(TerminalShortcutPack.zellijUnlock)
                    }.pickerStyle(.segmented).accessibilityIdentifier("terminal-preset-tool") }
                }
                Section {
                    Text(pack.guidance)
                    Text("Each button sends one key or chord. Custom tool bindings may differ.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach([false, true], id: \.self) { afterPrefix in
                    Section(afterPrefix ? "After Prefix" : "Direct Shortcuts") {
                    ForEach(pack.shortcuts.filter { ($0.action.usage != nil) == afterPrefix }) { preset in
                        let added = profile.actions.contains { $0.presetID == preset.id }
                        Button {
                            if selected.contains(preset.id) { selected.remove(preset.id) } else { selected.insert(preset.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.action.title)
                                    Text(preset.action.detail).font(.caption).foregroundStyle(.secondary)
                                    if let usage = preset.action.usage { Text(usage).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(); Image(systemName: (!placement && added) || selected.contains(preset.id) ? "checkmark.circle.fill" : "circle")
                            }.foregroundStyle(.primary).frame(minHeight: 44)
                        }.disabled(added && !placement).accessibilityValue(added && !placement ? "Already added" : selected.contains(preset.id) ? "Selected" : "Not selected")
                            .accessibilityIdentifier("terminal-preset-" + preset.id)
                    }
                    }
                }
                Section { Link("Default bindings reference", destination: pack.source) }
                if failed { Text("Couldn’t add presets. Your selection is kept.").foregroundStyle(.red) }
            }.navigationTitle(initialPack == .zellij || initialPack == .zellijUnlock ? "Zellij Shortcuts" : initialPack.title + " Shortcuts").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add \(selected.count)") {
                        if add(all.filter { selected.contains($0.id) }) { dismiss() } else { failed = true }
                    }.buttonStyle(.borderedProminent).disabled(selected.isEmpty).accessibilityIdentifier("terminal-presets-add") }
                }
        }.directAppearance().onAppear { pack = initialPack }
    }
}
/// The production floating-menu renderer supplies layout, selection, drag and
/// accessible move actions. It never receives an input execution handler here.
struct TerminalMenuEditingPreview: UIViewRepresentable {
    struct Configuration: Equatable {
        let actions: [TerminalControlAction]
        let selected: UUID?
        let enabled: Bool
        let adding: Bool
        let category: UIContentSizeCategory
        let fullMenu: Bool
    }
    final class Coordinator { var configuration: Configuration? }
    let actions: [TerminalControlAction]
    let selected: UUID?
    var editable: Bool
    let select: (UUID) -> Void
    let move: (UUID, UUID) -> Void
    var add: (() -> Void)? = nil
    var fullMenu = false
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
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIView(_ view: CompanionVNCControls, context: Context) {
        let allowed = editable && context.environment.isEnabled
        view.isUserInteractionEnabled = allowed || fullMenu
        view.fullMenuPreview = fullMenu
        let addIdentifier = "terminal-editor-add-favorite"
        view.previewSelectionHandler = allowed ? { value in
            if value == addIdentifier { add?() }
            else if let id = UUID(uuidString: value) { select(id) }
        } : nil
        view.previewMoveHandler = allowed ? { source, target in
            let destination = target == addIdentifier ? actions.last?.id : UUID(uuidString: target)
            if let source = UUID(uuidString: source), let destination { move(source, destination) }
        } : nil
        let configuration = Configuration(actions: actions, selected: selected, enabled: allowed, adding: add != nil, category: category, fullMenu: fullMenu)
        guard context.coordinator.configuration != configuration else { return }
        // Layout can re-enter updateUIView. Recreating the material panel on
        // every pass prevents the event loop from settling and replaces hit
        // targets while a selection or drag is still being delivered.
        context.coordinator.configuration = configuration
        view.traitOverrides.preferredContentSizeCategory = category
        view.macName = "Terminal"; view.categoryActions = fullMenu ? TerminalControlNavigation.items : []; view.quickActions = actions.map(\.native)
        if add != nil { view.quickActions.append(["id": addIdentifier, "kind": "previewAdd", "title": "Add Favorite", "symbol": "plus", "enabled": true, "inputAction": false]) }
        view.selectedPreviewID = selected?.uuidString
        view.refreshEditingPreview()
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CompanionVNCControls, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? 360, height: .greatestFiniteMagnitude))
    }
}
#endif
