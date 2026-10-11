#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Draft operations never touch storage or execute a session action.
enum DirectQuickActionEditing {
    static func standards(_ mode: DirectControlMode) -> [VNCQuickAction] {
        mode.builtIns.filter {
            #if os(macOS)
            $0.kind != .mode && $0.compatible(with: mode)
            #else
            $0.compatible(with: mode)
            #endif
        }
    }
    static func valid(_ actions: [VNCQuickAction], mode: DirectControlMode) -> Bool {
        actions.count <= VNCQuickAction.maximumCount && Set(actions.map(\.id)).count == actions.count
            && actions.filter(\.isCustom).count <= VNCQuickAction.maximumCustomCount
            && actions.allSatisfy { $0.valid && $0.compatible(with: mode) }
    }
    static func canSave(_ actions: [VNCQuickAction], mode: DirectControlMode, hasPro: Bool) -> Bool {
        // Terminal has no free preferences to save alongside its Pro-only actions.
        (mode != .terminal || hasPro) && valid(actions, mode: mode)
    }
    @discardableResult static func add(_ candidate: VNCQuickAction, to actions: inout [VNCQuickAction], mode: DirectControlMode) -> UUID? {
        guard !candidate.isCustom, candidate.compatible(with: mode) else { return nil }
        if let index = actions.firstIndex(where: { $0.kind == candidate.kind }) {
            actions[index].enabled = true; return actions[index].id
        }
        guard actions.count < VNCQuickAction.maximumCount else { return nil }
        actions.append(candidate); return candidate.id
    }
    static func move(_ id: UUID, to target: UUID, in actions: inout [VNCQuickAction]) {
        guard id != target, let source = actions.firstIndex(where: { $0.id == id }),
              let destination = actions.firstIndex(where: { $0.id == target }) else { return }
        let action = actions.remove(at: source); actions.insert(action, at: destination)
    }
}

extension VNCQuickAction {
    var shortcutTitle: String {
        guard kind == .shortcut else { return "" }
        let symbols: [(UInt32, String)] = [(0xffe3, "⌃"), (0xffe9, "⌥"), (0xffe1, "⇧"), (0xffeb, "⌘")]
        let special: [UInt32: String] = [0xff1b: "Esc", 0xff09: "Tab", 0xff0d: "↵", 0xff08: "⌫", 0xffff: "⌦", 0xff51: "←", 0xff52: "↑", 0xff53: "→", 0xff54: "↓"]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
            + (special[key] ?? (key == 0 ? "" : UnicodeScalar(key).map { String($0).uppercased() } ?? ""))
    }
}

/// Shared by the native Mac session menu and its editing preview.
struct DirectQuickActionLabel: View {
    let action: VNCQuickAction
    var body: some View {
        // Native menus extract the Label title and discard sibling Text views.
        Label(action.kind == .shortcut && action.displayTitle != action.shortcutTitle
            ? action.displayTitle + " · " + action.shortcutTitle : action.displayTitle,
            systemImage: action.symbol)
    }
}

#if os(macOS)
struct MacQuickActionsMenu: View {
    let actions: [VNCQuickAction]
    let perform: (VNCQuickAction) -> Void
    let customize: () -> Void
    var body: some View {
        ForEach(actions.filter(\.enabled)) { action in
            Button { perform(action) } label: { DirectQuickActionLabel(action: action) }
        }
        Divider()
        Button("Customize…", systemImage: "pencil", action: customize)
    }
}
#endif

struct DirectQuickActionsEditor: View {
    @Binding var actions: [VNCQuickAction]
    let mode: DirectControlMode
    var readable = true
    var macID: UUID? = nil
    var selectionChanged: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selected: UUID?
    @State private var pro = DirectProAccess.shared
    @State private var reset = false
    @State private var paywall = false
    @State private var catalogueShown = false
    @State private var automaticNames: Set<UUID> = []
    private var canEdit: Bool { readable && pro.hasPro && DirectAppLockV1.shared.canAccess }
    private var visible: [VNCQuickAction] { actions.filter(\.enabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Quick Actions", systemImage: "keyboard").font(.headline)
                Spacer()
                Text("On this device").font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            HStack(alignment: .top, spacing: 20) {
                preview.frame(width: 240)
                VStack(alignment: .leading, spacing: 18) { inspector }.frame(maxWidth: .infinity)
            }
            #else
            preview
            inspector
            #endif
            if !pro.hasPro {
                Button { paywall = true } label: { Label("Customize with Pro", systemImage: "sparkles") }
            }
            HStack {
                Button("Add Action", systemImage: "plus") { catalogueShown = true }
                    .disabled(!canEdit).accessibilityIdentifier("quick-action-add")
                Spacer()
                Menu("More", systemImage: "ellipsis") {
                    Button("Restore Defaults") { reset = true }.disabled(!canEdit)
                }.accessibilityLabel("Quick Action Options")
            }
            Text("\(visible.count) of \(VNCQuickAction.maximumCount) actions").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $catalogueShown, onDismiss: {
            if selected != nil { selectionChanged() }
        }) {
            NavigationStack {
                ScrollView { library.padding(16) }
                    .navigationTitle("Add Action").directInlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { catalogueShown = false } } }
            }.directAppearance()
                #if os(macOS)
                .frame(width: 480, height: 500).modifier(MacSheetPrivacyCover())
                #endif
        }
        .onChange(of: canEdit) { _, value in if !value { catalogueShown = false } }
        .onChange(of: selected) { _, value in if value != nil && !catalogueShown { selectionChanged() } }
        .confirmationDialog("Restore default quick actions?", isPresented: $reset, titleVisibility: .visible) {
            Button("Restore Defaults") {
                guard canEdit else { return }
                actions = mode.defaults.filter { candidate in
                    #if os(macOS)
                    candidate.kind != .mode
                    #else
                    true
                    #endif
                }; selected = nil; automaticNames.removeAll()
            }
        } message: { Text("Your draft shortcuts and saved text will be removed when you save.") }
        .sheet(isPresented: $paywall) {
            #if os(macOS)
            DirectProView().directAppearance().modifier(MacSheetPrivacyCover())
            #else
            DirectProView().directAppearance()
            #endif
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(iOS)
            DirectQuickActionsNativePreview(actions: visible, mode: mode, selected: selected,
                trackpad: macID.map(VNCSessionPreferences.trackpad) ?? false,
                editable: canEdit, select: { if canEdit { selected = $0 } }, move: move)
                .frame(maxWidth: .infinity).accessibilityIdentifier("quick-actions-preview")
            #else
            VStack(spacing: 4) {
                ForEach(visible) { action in
                    Button { if canEdit { selected = action.id } } label: {
                        DirectQuickActionLabel(action: action).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected == action.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).allowsHitTesting(canEdit)
                        .accessibilityIdentifier("preview-action-" + action.id.uuidString)
                        .accessibilityHint(canEdit ? "Select to edit. No input is sent to your Mac." : "Quick action in your session")
                        .accessibilityRemoveTraits(canEdit ? [] : .isButton)
                        .draggable(canEdit ? action.id.uuidString : "")
                        .dropDestination(for: String.self) { ids, _ in
                            guard canEdit, let value = ids.first, let id = UUID(uuidString: value), visible.contains(where: { $0.id == id }) else { return false }
                            move(id, action.id); return true
                        }
                        .accessibilityAction(named: "Move Earlier") { moveSelected(action.id, offset: -1) }
                        .accessibilityAction(named: "Move Later") { moveSelected(action.id, offset: 1) }
                }
            }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("quick-actions-preview")
            #endif
            if visible.isEmpty { Text("No quick actions. Add one below.").font(.subheadline).foregroundStyle(.secondary) }
            else { Text(canEdit ? "Drag to reorder · select to edit" : "Your session layout").font(.caption).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var inspector: some View {
        if let selected, let index = actions.firstIndex(where: { $0.id == selected }) {
            let current = actions[index]
            VStack(alignment: .leading, spacing: 12) {
                DirectQuickActionInspector(action: Binding(get: {
                    actions.first { $0.id == selected } ?? current
                }, set: { edited in
                    guard canEdit, let i = actions.firstIndex(where: { $0.id == selected }) else { return }
                    actions[i] = edited
                }), mode: mode, automaticallyNamed: Binding(get: {
                    automaticNames.contains(selected)
                }, set: { value in
                    if value { automaticNames.insert(selected) } else { automaticNames.remove(selected) }
                })).id(selected)
                HStack {
                    Menu("Move", systemImage: "arrow.up.arrow.down") {
                        Button("Earlier") { moveSelected(selected, offset: -1) }.disabled(visible.first?.id == selected)
                        Button("Later") { moveSelected(selected, offset: 1) }.disabled(visible.last?.id == selected)
                    }.disabled(!actions[index].enabled)
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        guard canEdit else { return }
                        actions.removeAll { $0.id == selected }; automaticNames.remove(selected); self.selected = nil
                    }.accessibilityLabel("Remove from Quick Actions")
                }
            }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12)).disabled(!canEdit)
                .accessibilityElement(children: .contain).accessibilityIdentifier("quick-action-inspector").id("quick-action-inspector")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            let catalogue = DirectQuickActionEditing.standards(mode).filter { candidate in !actions.contains { $0.kind == candidate.kind && $0.enabled } } + [
                VNCQuickAction(title: "Shortcut", kind: .shortcut), VNCQuickAction(title: "Saved Text", kind: .text)]
            let columns = textSize.isAccessibilitySize ? 1 : 2
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: catalogue.count, by: columns)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(catalogue[start..<min(start + columns, catalogue.count)]), id: \.kind) { candidate in
                            libraryButton(candidate)
                        }
                        if columns == 2 && start + 1 == catalogue.count { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
            if actions.count >= VNCQuickAction.maximumCount { Text("Remove an action to add another.").font(.caption).foregroundStyle(.secondary) }
            else if actions.filter(\.isCustom).count >= VNCQuickAction.maximumCustomCount {
                Text("12 custom actions. Remove one to add another shortcut or text.").font(.caption).foregroundStyle(.secondary)
            }
            if actions.contains(where: { !$0.enabled && $0.isCustom }) {
                Text("Hidden actions").font(.subheadline.bold())
                ForEach(actions.filter { !$0.enabled && $0.isCustom }) { action in
                    Button {
                        guard canEdit, let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
                        actions[i].enabled = true; selected = action.id; catalogueShown = false
                    } label: { Label(action.displayTitle, systemImage: "plus") }.disabled(!canEdit)
                }
            }
        }
    }
    private func libraryButton(_ candidate: VNCQuickAction) -> some View {
        let existing = candidate.isCustom ? nil : actions.first { $0.kind == candidate.kind }
        let added = existing?.enabled == true
        let title = candidate.kind == .mode ? "Input Mode" : candidate.displayTitle
        let full = candidate.isCustom ? !VNCQuickAction.canAddCustom(to: actions)
            : existing == nil && actions.count >= VNCQuickAction.maximumCount
        return Button {
            guard canEdit else { return }
            if candidate.isCustom { addCustom(candidate.kind) }
            else { selected = DirectQuickActionEditing.add(candidate, to: &actions, mode: mode) }
            catalogueShown = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: candidate.symbol).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if added { Text("Added").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 2)
                Image(systemName: added ? "checkmark" : "plus").font(.caption.weight(.semibold))
                    .foregroundStyle(added ? Color.secondary : Color.accentColor)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .foregroundStyle(added ? Color.secondary : Color.primary)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!canEdit || added || full)
            .accessibilityLabel(title + (added ? ", Added" : ", Add action"))
            .accessibilityIdentifier("add-action-" + candidate.kind.rawValue)
    }
    private func addCustom(_ kind: VNCQuickAction.Kind) {
        guard canEdit, VNCQuickAction.canAddCustom(to: actions) else { return }
        var action = VNCQuickAction(title: kind == .text ? "Saved Text" : "Shortcut", kind: kind,
            key: kind == .shortcut ? 0x63 : 0, modifiers: kind == .shortcut ? [mode == .terminal ? 0xffe3 : 0xffeb] : [])
        if kind == .shortcut { action.title = action.shortcutTitle; automaticNames.insert(action.id) }
        actions.append(action); selected = action.id
    }
    private func move(_ id: UUID, _ target: UUID) {
        guard canEdit else { return }
        DirectQuickActionEditing.move(id, to: target, in: &actions)
    }
    private func moveSelected(_ id: UUID, offset: Int) {
        guard let index = visible.firstIndex(where: { $0.id == id }), visible.indices.contains(index + offset) else { return }
        move(id, visible[index + offset].id)
    }
}

enum DirectQuickActionName {
    static let symbols = [("Command", "⌘"), ("Option", "⌥"), ("Control", "⌃"), ("Shift", "⇧"),
        ("Escape", "⎋"), ("Tab", "⇥"), ("Return", "↵"), ("Delete", "⌫")]
    static func inserting(_ symbol: String, into name: String, selection: NSRange?) -> (name: String, cursor: Int)? {
        let range = selection.flatMap { Range($0, in: name) } ?? name.endIndex..<name.endIndex
        var result = name
        let prefixCount = name[..<range.lowerBound].utf16.count
        result.replaceSubrange(range, with: symbol)
        guard result.count <= 40 else { return nil }
        return (result, prefixCount + symbol.utf16.count)
    }
}

struct DirectQuickActionInspector: View {
    @Binding var action: VNCQuickAction
    let mode: DirectControlMode
    var automaticallyNamed: Binding<Bool> = .constant(false)
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var recording = false
    @State private var nameSelection: TextSelection?
    @State private var lastNameRange: NSRange?
    @State private var lastNameSource = ""
    @FocusState private var nameFocused: Bool
    private let modifiers: [(name: String, label: String, key: UInt32)] = [
        ("Control", "⌃ Ctrl", 0xffe3), ("Option", "⌥ Option", 0xffe9),
        ("Shift", "⇧ Shift", 0xffe1), ("Command", "⌘ Cmd", 0xffeb)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if action.isCustom {
                Label(action.kind == .text ? "Saved Text" : "Shortcut", systemImage: action.symbol).font(.subheadline.bold())
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu("Insert Symbol", systemImage: "character.cursor.ibeam") {
                            ForEach(DirectQuickActionName.symbols, id: \.0) { name, symbol in
                                Button(symbol + " " + name) { insertNameSymbol(symbol) }
                            }
                        }.font(.caption).accessibilityIdentifier("quick-action-insert-symbol")
                    }
                    TextField("Name", text: Binding(get: { action.title }, set: {
                        automaticallyNamed.wrappedValue = false; action.title = $0
                    }), selection: $nameSelection).focused($nameFocused)
                        .accessibilityIdentifier("quick-action-name")
                }
                if action.kind == .text {
                    DirectSavedTextEditor(text: $action.text, mode: mode)
                } else {
                    HStack {
                        Text(action.shortcutTitle.isEmpty ? "Choose a key" : action.shortcutTitle)
                            .font(.body.monospaced().weight(.medium)).accessibilityIdentifier("quick-action-shortcut")
                        Spacer()
                        #if os(macOS)
                        Button(recording ? "Cancel Recording" : "Record Shortcut") { recording.toggle() }
                        #endif
                    }
                    #if os(macOS)
                    if recording {
                        Text("Press a shortcut. Escape cancels.").font(.caption).foregroundStyle(.secondary)
                        DirectShortcutRecorder(mode: mode) { key, flags in
                            if let key { action.key = key; action.modifiers = flags }
                            recording = false
                        }.frame(height: 1).id(action.id)
                    }
                    #endif
                    if textSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { modifierButtons }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { modifierButtons }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108))], alignment: .leading, spacing: 8) { modifierButtons }
                        }
                    }
                    TextField("Letter or symbol", text: Binding(get: {
                        action.key > 0 && action.key < 0xff00 ? UnicodeScalar(action.key).map(String.init) ?? "" : ""
                    }, set: { value in
                        action.key = value.unicodeScalars.count == 1 ? value.unicodeScalars.first!.value : 0
                    })).autocorrectionDisabled().directNoAutocapitalization().accessibilityIdentifier("quick-action-key")
                    Picker("Special Key", selection: Binding(get: { action.key < 0xff00 ? 0 : action.key }, set: { action.key = $0 })) {
                        Text("Character").tag(UInt32(0))
                        ForEach([("Escape", UInt32(0xff1b)), ("Tab", 0xff09), ("Return", 0xff0d), ("Backspace", 0xff08), ("Delete", 0xffff), ("Left", 0xff51), ("Up", 0xff52), ("Right", 0xff53), ("Down", 0xff54)], id: \.1) { Text($0.0).tag($0.1) }
                    }
                }
                if !action.valid || !action.compatible(with: mode) {
                    Text(action.kind == .text ? "Enter text up to 256 characters and a name up to 40 characters." : "Choose a valid key and a name up to 40 characters.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else { Label(action.displayTitle, systemImage: action.symbol).font(.subheadline.bold()) }
        }.textFieldStyle(.roundedBorder)
            .onChange(of: action.shortcutTitle) { _, value in
                if automaticallyNamed.wrappedValue, !value.isEmpty { action.title = value; nameSelection = nil }
            }
            .onChange(of: nameSelection) { _, selection in
                if case let .selection(range) = selection?.indices {
                    lastNameRange = NSRange(range, in: action.title); lastNameSource = action.title
                }
            }
    }
    private func insertNameSymbol(_ symbol: String) {
        let range = lastNameSource == action.title ? lastNameRange : nil
        guard let result = DirectQuickActionName.inserting(symbol, into: action.title, selection: range) else { return }
        automaticallyNamed.wrappedValue = false; action.title = result.name
        nameSelection = TextSelection(insertionPoint: String.Index(utf16Offset: result.cursor, in: result.name))
        lastNameRange = NSRange(location: result.cursor, length: 0); lastNameSource = result.name
        nameFocused = true
    }
    private var modifierButtons: some View {
        ForEach(modifiers.filter { mode != .terminal || $0.key != 0xffeb }, id: \.key) { modifier in
            Button {
                if action.modifiers.contains(modifier.key) { action.modifiers.removeAll { $0 == modifier.key } }
                else { action.modifiers.append(modifier.key) }
            } label: { Text(modifier.label).fixedSize(horizontal: true, vertical: true) }
                .font(.subheadline).buttonStyle(.bordered).controlSize(.small)
                .tint(action.modifiers.contains(modifier.key) ? .accentColor : .secondary)
                .accessibilityLabel(modifier.name).help(modifier.name)
                .accessibilityValue(action.modifiers.contains(modifier.key) ? "Selected" : "Off")
        }
    }
}

struct DirectSavedTextEditor: View {
    @Binding var text: String
    let mode: DirectControlMode
    private var editorBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text to Send").font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "\n\n\n" : text + "\n")
                .font(.body.monospaced()).padding(8).opacity(0).accessibilityHidden(true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 112, maxHeight: 240).fixedSize(horizontal: false, vertical: true).clipped()
                .overlay(alignment: .topLeading) {
                TextEditor(text: $text).font(.body.monospaced()).scrollContentBackground(.hidden)
                    .padding(4).autocorrectionDisabled().directNoAutocapitalization().privacySensitive()
                    .accessibilityLabel("Text to Send").accessibilityIdentifier("quick-action-text")
                if text.isEmpty {
                    Text("Text to send when you tap this action").font(.body).foregroundStyle(.secondary)
                        .padding(12).allowsHitTesting(false).accessibilityHidden(true)
                }
            }.background(editorBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35), lineWidth: 1) }
            HStack {
                Text("Stored only on this device")
                Spacer()
                Text("\(text.unicodeScalars.count)/256").monospacedDigit()
                    .foregroundStyle(text.unicodeScalars.count > 256 ? Color.red : Color.secondary)
            }.font(.caption).foregroundStyle(.secondary)
            Text(mode == .terminal ? "A trailing newline can run a command." : "Sent to the focused field on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }.privacySensitive()
    }
}

#if os(iOS)
private struct DirectQuickActionsNativePreview: UIViewRepresentable {
    let actions: [VNCQuickAction]
    let mode: DirectControlMode
    let selected: UUID?
    let trackpad: Bool
    let editable: Bool
    let select: (UUID) -> Void
    let move: (UUID, UUID) -> Void
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CompanionVNCControls, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? 360, height: .greatestFiniteMagnitude))
    }
    func makeUIView(context: Context) -> CompanionVNCControls { let view = CompanionVNCControls(); view.editingPreview = true; view.bottomInset = 0; return view }
    func updateUIView(_ view: CompanionVNCControls, context: Context) {
        view.macName = mode.title; view.inputOnly = mode == .trackpad; view.trackpad = trackpad
        view.categoryActions = []
        view.quickActions = actions.map(\.native); view.selectedPreviewID = selected?.uuidString
        view.previewSelectionHandler = editable ? { if let id = UUID(uuidString: $0) { select(id) } } : nil
        view.previewMoveHandler = editable ? { if let id = UUID(uuidString: $0), let target = UUID(uuidString: $1) { move(id, target) } } : nil
        view.refreshEditingPreview()
    }
}
#else
struct DirectShortcutRecorder: NSViewRepresentable {
    let mode: DirectControlMode
    let recorded: (UInt32?, [UInt32]) -> Void
    final class Capture: NSView {
        var mode = DirectControlMode.desktop
        var recorded: ((UInt32?, [UInt32]) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { recorded?(nil, []); return }
            if mode == .terminal && event.modifierFlags.contains(.command) { NSSound.beep(); return }
            let special: [UInt16: UInt32] = [48: 0xff09, 36: 0xff0d, 76: 0xff0d, 51: 0xff08, 117: 0xffff, 123: 0xff51, 126: 0xff52, 124: 0xff53, 125: 0xff54]
            guard let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first?.value else { return }
            let flags: [(NSEvent.ModifierFlags, UInt32)] = [(.control, 0xffe3), (.option, 0xffe9), (.shift, 0xffe1), (.command, 0xffeb)]
            let keys = flags.filter { event.modifierFlags.contains($0.0) }.map(\.1)
            let candidate = VNCQuickAction(title: "Recorded", kind: .shortcut, key: key, modifiers: keys)
            if candidate.valid && candidate.compatible(with: mode) { recorded?(key, keys) }
        }
    }
    func makeNSView(context: Context) -> Capture { let view = Capture(); view.mode = mode; view.recorded = recorded; return view }
    func updateNSView(_ view: Capture, context: Context) { view.mode = mode; view.recorded = recorded }
    static func dismantleNSView(_ view: Capture, coordinator: ()) { if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }; view.recorded = nil }
}
#endif
#endif
