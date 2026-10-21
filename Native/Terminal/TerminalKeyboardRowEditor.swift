#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

/// This editor has no terminal/input owner. Both its canvas and row library use
/// the production bar renderer, including real key metrics and scrolling.
struct TerminalKeyboardEditingPreview: View {
    @Binding var profile: TerminalControlsProfile
    let selected: UUID?
    @Binding var selectedRow: UUID
    let select: (UUID?) -> Void
    private enum Mode: String, CaseIterable { case arrange = "Arrange", collapsed = "Collapsed", expanded = "Expanded" }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var keyboardVisible = false
    @State private var mode = Mode.arrange
    @State private var selectedItem: TerminalBarItem?
    @State private var inspectedRow: TerminalKeyboardRow?
    @State private var restoring = false
    @State private var deleting = false
    private var currentRow: TerminalKeyboardRow? { profile.resolvedRows.first { $0.id == selectedRow } }
    private var previewProfile: TerminalControlsProfile {
        var result = profile
        if mode != .arrange { result.rowsExpanded = mode == .expanded }
        return result
    }
    private var visibleRows: Int {
        previewProfile.resolvedRows.filter { mode == .arrange || ($0.kind == .numbers ? profile.numberRow != false : !$0.extra || previewProfile.rowsExpanded == true) }.count
    }
    private var savedSelection: Binding<TerminalControlAction>? {
        guard let selected, let action = profile.actions.first(where: { $0.id == selected }) else { return nil }
        return Binding(get: { profile.actions.first { $0.id == selected } ?? action }, set: { value in
            if let index = profile.actions.firstIndex(where: { $0.id == selected }) { profile.actions[index] = value }
        })
    }
    private var hideCanvasForTyping: Bool { keyboardVisible && selected != nil && !dynamicTypeSize.isAccessibilitySize }
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text needs a single scroll surface so the canvas never
                // pushes the selected key or its text fields offscreen.
                ScrollViewReader { proxy in
                    ScrollView { VStack(alignment: .leading, spacing: 14) { canvas; details } }
                        .scrollDismissesKeyboard(.interactively).accessibilityIdentifier("terminal-row-library")
                        .onChange(of: selected) { _, value in if value != nil { proxy.scrollTo("selected-control", anchor: .top) } }
                        .onChange(of: selectedItem) { _, value in if value != nil { proxy.scrollTo("selected-control", anchor: .top) } }
                }
            } else {
                VStack(alignment: .leading, spacing: hideCanvasForTyping ? 0 : 14) {
                    canvas.frame(height: hideCanvasForTyping ? 0 : nil).clipped()
                        .accessibilityHidden(hideCanvasForTyping).allowsHitTesting(!hideCanvasForTyping)
                    ScrollViewReader { proxy in
                        ScrollView { details }.scrollIndicators(.visible).accessibilityIdentifier("terminal-row-library")
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: selected) { _, value in if value != nil { proxy.scrollTo("selected-control", anchor: .top) } }
                            .onChange(of: selectedItem) { _, value in if value != nil { proxy.scrollTo("selected-control", anchor: .top) } }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .sheet(item: $inspectedRow) { row in TerminalKeyboardRowOptions(profile: $profile, rowID: row.id) }
        .onChange(of: profile.resolvedRows.map(\.id)) { _, ids in if !ids.contains(selectedRow) { selectedRow = TerminalKeyboardRow.mainID } }
        .confirmationDialog("Delete this item from the keyboard bar, floating menu and saved collection?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) { if let selected { profile.delete(selected) }; selectedItem = nil; select(nil) }
        }
        .confirmationDialog("Restore the default keyboard bar?", isPresented: $restoring, titleVisibility: .visible) {
            Button("Restore Layout") { profile.restoreKeyboardBar(); selectedItem = nil; selectedRow = TerminalKeyboardRow.mainID; select(nil) }
        } message: { Text("Saved shortcuts, text and floating-menu favorites are kept. You can Undo before saving.") }
    }
    private var canvas: some View {
        VStack(alignment: .leading, spacing: 14) {
        Picker("Keyboard preview", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("terminal-preview-mode")
        VStack(alignment: .leading, spacing: 0) {
            if mode != .arrange {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approximate terminal space").font(.caption).foregroundStyle(.secondary)
                    Text("$ ssh mac.local\n▏").font(.system(.caption, design: .monospaced))
                    Spacer(minLength: 0)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(62, 210 - CGFloat(visibleRows) * 24))
            }
            TerminalKeyboardBarPreview(profile: previewProfile, selected: selectedItem, row: selectedRow,
                allRows: mode == .arrange, handles: mode == .arrange,
                select: { item, row in selectedItem = item; selectedRow = row; select(item?.savedID) },
                move: move, remove: remove,
                selectRow: { row in selectedItem = nil; select(nil); inspectedRow = profile.resolvedRows.first { $0.id == row }; selectedRow = row },
                moveRow: { row, target in withAnimation(.snappy) { profile.moveRow(row, before: target) } },
                addPreset: addPreset, addItem: { item, row, target in
                    guard !profile.resolvedRows.contains(where: { profile.barItems(in: $0).contains(item) }) else { return }
                    profile.placeBarItem(item, in: row, before: target)
                })
                .disabled(mode != .arrange)
                .allowsHitTesting(mode == .arrange)
                .accessibilityIdentifier("terminal-live-bar-preview")
        }.background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        if mode != .arrange {
            Text("Appearance preview. Choose Arrange to edit every row, including hidden rows.").font(.caption).foregroundStyle(.secondary)
        }
        if profile.resolvedRows.count > 4 {
            Label("Extra rows reduce terminal space.", systemImage: "rectangle.compress.vertical")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("terminal-row-space-warning")
        }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 0).id("selected-control")
            if let selectedItem, let row = currentRow, mode == .arrange {
                HStack {
                    Text(selectedItem.title(in: profile)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Menu("Move Key", systemImage: "arrow.left.arrow.right") {
                        Button("Earlier") { moveSelected(-1) }
                        Button("Later") { moveSelected(1) }
                        ForEach(profile.resolvedRows) { target in
                            Button("To " + target.title) { move(selectedItem, row.id, target.id, nil) }
                        }
                    }.accessibilityIdentifier("terminal-item-row")
                    Button { remove(selectedItem, row.id) } label: { Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Remove from Keyboard Bar").accessibilityIdentifier("terminal-remove-placement")
                }
            }
            if let savedSelection, mode == .arrange {
                TerminalControlInspector(action: savedSelection).id(savedSelection.wrappedValue.id)
                Text("Content edits apply everywhere this item is used.").font(.caption).foregroundStyle(.secondary)
                Button("Delete Saved Item…", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("terminal-delete-item")
            }
            Text("Available Rows").font(.headline)
            Text("Drag a row into the bar, or tap Add. Dimmed keys are already placed and stay where they are. You can also drag individual available keys.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(TerminalRowPreset.allCases) { preset in
                TerminalRowTemplate(profile: profile, preset: preset, arranging: mode == .arrange, add: { addPreset(preset, TerminalKeyboardRow.mainID) })
            }
            if profile.resolvedRows.count >= TerminalControlsProfile.maximumKeyboardRows {
                Text("Six rows are configured. Remove a row to add another; keys can still move between rows.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Restore Keyboard Bar…", systemImage: "arrow.counterclockwise") { restoring = true }.accessibilityIdentifier("terminal-restore-bar")
        }
    }
    private func move(_ item: TerminalBarItem, _ source: UUID, _ row: UUID, _ target: TerminalBarItem?) {
        guard let existing = profile.resolvedRows.first(where: { $0.id == source }), profile.barItems(in: existing).contains(item) else { return }
        withAnimation(.snappy) { profile.placeBarItem(item, in: row, from: source, before: target) }
        selectedRow = row; selectedItem = item; select(item.savedID)
    }
    private func remove(_ item: TerminalBarItem, _ row: UUID) {
        profile.removeBarItem(item, in: row); selectedItem = nil; select(nil)
    }
    private func moveSelected(_ offset: Int) {
        guard let selectedItem, let row = currentRow else { return }
        let items = profile.barItems(in: row)
        guard let index = items.firstIndex(of: selectedItem), items.indices.contains(index + offset) else { return }
        let target = offset < 0 ? items[index - 1] : (items.indices.contains(index + 2) ? items[index + 2] : nil)
        move(selectedItem, row.id, row.id, target)
    }
    private func addPreset(_ preset: TerminalRowPreset, _ target: UUID?) {
        withAnimation(.snappy) {
            if let id = profile.addPreset(preset, before: target) { selectedRow = id; selectedItem = nil; select(nil) }
        }
    }
}

private struct TerminalRowTemplate: View {
    let profile: TerminalControlsProfile
    let preset: TerminalRowPreset
    let arranging: Bool
    let add: () -> Void
    private var available: [TerminalBarItem] { profile.availableItems(for: preset) }
    private var canAdd: Bool { profile.resolvedRows.count < TerminalControlsProfile.maximumKeyboardRows && (preset == .blank || !available.isEmpty) }
    private var template: TerminalControlsProfile {
        var result = TerminalControlsProfile()
        // A template is a render value, not a newly saved profile on each pass.
        result.revision = TerminalKeyboardRow.mainID
        result.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .custom, title: preset.rawValue, items: preset.items, expandedOnly: false)]
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(preset.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                Text(preset == .blank ? "Start empty" : available.isEmpty ? "All keys placed" : "\(available.count) new keys")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TerminalKeyboardBarPreview(profile: template, allRows: true, handles: true, preset: preset,
                unavailable: Set(preset.items).subtracting(available), canAddPreset: canAdd,
                addPreset: { _, _ in add() })
                .accessibilityIdentifier("terminal-row-template-" + preset.id)
                .disabled(!arranging)
                .allowsHitTesting(arranging)
        }.padding(.vertical, 4)
    }
}

/// Row controls belong to the row's own handle; they are also tap alternatives
/// to every row drag. Changes remain in the parent draft until Save.
private struct TerminalKeyboardRowOptions: View {
    @Binding var profile: TerminalControlsProfile
    let rowID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var restoring = false
    private var row: TerminalKeyboardRow? { profile.resolvedRows.first { $0.id == rowID } }
    private func edit(_ change: (inout TerminalKeyboardRow) -> Void) {
        var rows = profile.resolvedRows
        if let index = rows.firstIndex(where: { $0.id == rowID }) { change(&rows[index]); profile.keyboardRows = rows }
    }
    var body: some View {
        NavigationStack {
            Form {
                if let row {
                    Section {
                        TextField("Row Name", text: Binding(get: { self.row?.title ?? row.title }, set: { name in edit { $0.title = name } }))
                            .accessibilityIdentifier("terminal-row-name-" + rowID.uuidString)
                        if row.kind == .numbers {
                            Toggle("Show Numbers", isOn: Binding(get: { profile.numberRow ?? true }, set: { profile.numberRow = $0 })).accessibilityIdentifier("terminal-setting-numbers")
                        } else if row.kind != .main {
                            Toggle("Always Visible", isOn: Binding(get: { self.row?.extra == false }, set: { visible in edit { $0.expandedOnly = !visible } }))
                        } else { Text("This row is always visible.").foregroundStyle(.secondary) }
                    }
                    Section("Position") {
                        Button("Move Row Up", systemImage: "arrow.up") { profile.moveRow(rowID, offset: -1) }
                            .disabled(profile.resolvedRows.first?.id == rowID)
                        Button("Move Row Down", systemImage: "arrow.down") { profile.moveRow(rowID, offset: 1) }
                            .disabled(profile.resolvedRows.last?.id == rowID)
                    }
                    Section {
                        Button("Restore This Row", systemImage: "arrow.counterclockwise") { restoring = true }.accessibilityIdentifier("terminal-restore-row")
                        if row.kind != .main {
                            Button("Remove Row", systemImage: "minus.circle", role: .destructive) { profile.removeRow(rowID); dismiss() }
                        }
                    } footer: { Text("Removing a row keeps its saved shortcuts, text and floating-menu favorites.") }
                }
            }.navigationTitle("Row Settings").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
            .confirmationDialog("Restore this row’s starting layout?", isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore Layout") { profile.restoreRow(rowID) }
            } message: { Text("Keys already placed in other rows stay there. Saved items are kept.") }
    }
}

private struct TerminalKeyboardBarPreview: UIViewRepresentable {
    struct Configuration: Equatable {
        let profile: TerminalControlsProfile
        let selected: TerminalBarItem?
        let row: UUID
        let allRows: Bool
        let handles: Bool
        let preset: TerminalRowPreset?
        let unavailable: Set<TerminalBarItem>
        let canAdd: Bool
        let enabled: Bool
        let textSize: DynamicTypeSize
    }
    final class Coordinator { var configuration: Configuration? }
    let profile: TerminalControlsProfile
    var selected: TerminalBarItem? = nil
    var row: UUID = TerminalKeyboardRow.mainID
    var allRows = false
    var handles = false
    var preset: TerminalRowPreset? = nil
    var unavailable: Set<TerminalBarItem> = []
    var canAddPreset = true
    var select: ((TerminalBarItem?, UUID) -> Void)? = nil
    var move: ((TerminalBarItem, UUID, UUID, TerminalBarItem?) -> Void)? = nil
    var remove: ((TerminalBarItem, UUID) -> Void)? = nil
    var selectRow: ((UUID) -> Void)? = nil
    var moveRow: ((UUID, UUID?) -> Void)? = nil
    var addPreset: ((TerminalRowPreset, UUID?) -> Void)? = nil
    var addItem: ((TerminalBarItem, UUID, TerminalBarItem?) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> TerminalKeyboardBar {
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true; return bar
    }
    func updateUIView(_ bar: TerminalKeyboardBar, context: Context) {
        let enabled = context.environment.isEnabled
        bar.isUserInteractionEnabled = enabled
        bar.selectedPreviewItem = selected; bar.selectedPreviewRow = row
        bar.previewShowsAllRows = allRows; bar.previewShowsRowHandles = handles; bar.previewPreset = preset
        bar.previewUnavailableItems = unavailable; bar.previewCanAddPreset = canAddPreset
        bar.previewSelect = enabled ? select : nil; bar.previewMove = enabled ? move : nil; bar.previewRemove = enabled ? remove : nil
        bar.previewSelectRow = enabled ? selectRow : nil; bar.previewMoveRow = enabled ? moveRow : nil
        bar.previewAddPreset = enabled ? addPreset : nil; bar.previewAddItem = enabled ? addItem : nil
        let configuration = Configuration(profile: profile, selected: selected, row: row, allRows: allRows, handles: handles,
            preset: preset, unavailable: unavailable, canAdd: canAddPreset, enabled: enabled, textSize: context.environment.dynamicTypeSize)
        guard context.coordinator.configuration != configuration else { return }
        // UIKit invalidates intrinsic size during configuration. Rebuilding on
        // every SwiftUI layout pass creates a feedback loop and also destroys
        // the source/drop views during an active drag.
        context.coordinator.configuration = configuration
        bar.configure(profile) { _ in }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TerminalKeyboardBar, context: Context) -> CGSize? {
        .init(width: proposal.width ?? 360, height: uiView.height)
    }
}
#endif
