#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacDesktopSettings: View {
    var macID: UUID? = nil
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var scrollSpeed = VNCSessionPreferences.scrollSpeed
    @State private var fullscreen = false
    @State private var actions: [VNCQuickAction] = []
    @State private var selection: UUID?
    @State private var editor: VNCQuickAction?
    @State private var issue: DirectRecoveryNotice?
    @State private var readable = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Pointer", value: "Direct control")
                    DirectGuidanceRow(title: "Zoom and pan", detail: "Pinch to zoom. Hold Option and scroll to pan. Use Fit to Window to see the whole desktop.", symbol: "arrow.up.left.and.arrow.down.right")
                    if macID != nil { Toggle("Open this desktop in full screen", isOn: $fullscreen) }
                } header: { Label("Display", systemImage: "display") }
                Section {
                    LabeledContent("Scroll speed") {
                        Slider(value: $scrollSpeed, in: VNCSessionPreferences.scrollSpeedRange, step: 0.25)
                            .frame(width: 200).accessibilityLabel("Scroll Speed").accessibilityIdentifier("scroll-speed-slider")
                        Text(scrollSpeed.formatted(.number.precision(.fractionLength(0...2))) + "×").monospacedDigit().frame(width: 36)
                    }
                    Button("Reset Scroll Speed") { scrollSpeed = 1 }
                } header: { Label("Scrolling", systemImage: "computermouse") }
                footer: { Text("Mouse-wheel and two-finger scrolling. Applies to all desktops on this device.") }
                Section {
                    Text("Your physical keyboard works directly. Add optional actions to the Send Key menu.").font(.caption).foregroundStyle(.secondary)
                    Table(actions, selection: $selection) {
                        TableColumn("Enabled") { action in
                            Toggle(action.title, isOn: Binding(get: { actions.first { $0.id == action.id }?.enabled ?? false }, set: { value in
                                if let index = actions.firstIndex(where: { $0.id == action.id }) { actions[index].enabled = value }
                            })).labelsHidden().accessibilityLabel("Enable " + action.title)
                        }.width(58)
                        TableColumn("Action") { action in Label(action.title, systemImage: action.symbol) }
                        TableColumn("Type") { action in Text(action.kind == .text ? "Saved text" : action.kind == .shortcut ? "Shortcut" : "Standard").foregroundStyle(.secondary) }.width(85)
                    }.frame(height: 170)
                    HStack {
                        Menu("Add Action", systemImage: "plus") {
                            ForEach(DirectControlMode.desktop.builtIns.filter { $0.kind != .mode && !actions.map(\.kind).contains($0.kind) }) { action in
                                Button(action.title, systemImage: action.symbol) { actions.append(action) }
                            }
                            Divider()
                            Button("Keyboard Shortcut…") { editor = .init(title: "", kind: .shortcut, key: 0x63, modifiers: [0xffeb]) }
                                .disabled(!VNCQuickAction.canAddCustom(to: actions))
                            Button("Saved Text…") { editor = .init(title: "", kind: .text) }
                                .disabled(!VNCQuickAction.canAddCustom(to: actions))
                        }.disabled(actions.count >= VNCQuickAction.maximumCount)
                        Button("Edit…") { editor = actions.first { $0.id == selection } }.disabled(!canEdit)
                        Menu("Arrange", systemImage: "arrow.up.arrow.down") {
                            Button("Move Up") { move(-1) }.disabled(selection == nil || selection == actions.first?.id)
                            Button("Move Down") { move(1) }.disabled(selection == nil || selection == actions.last?.id)
                        }.disabled(selection == nil)
                        Spacer()
                        Button("Remove", systemImage: "minus") { actions.removeAll { $0.id == selection }; selection = nil }.disabled(selection == nil)
                    }
                    Button("Restore Default Actions") { actions = DirectControlMode.desktop.defaults.filter { $0.kind != .mode } }
                } header: { Label("Shortcuts", systemImage: "keyboard") }
                footer: { Text("Optional shortcuts apply to all desktops. Saved text stays on this device.") }
                    .disabled(!readable || !DirectProAccess.shared.hasPro)
                if !DirectProAccess.shared.hasPro { Text("Custom shortcuts require Pro or an active trial.").font(.caption).foregroundStyle(.secondary) }
                if let issue {
                    DirectRecoveryCard(notice: issue,
                        primary: .init(title: readable ? "Retry Save" : "Retry", perform: { if readable { save() } else { reload() } }),
                        secondary: readable ? .init(title: "Keep Editing", perform: { self.issue = nil }) : nil)
                }
            }.formStyle(.grouped).navigationTitle("Desktop Controls")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!readable) }
                }
                .sheet(item: $editor) { action in
                    VNCActionEditor(action: action, mode: .desktop) { edited in
                        if let i = actions.firstIndex(where: { $0.id == edited.id }) { actions[i] = edited }
                        else if VNCQuickAction.canAddCustom(to: actions) { actions.append(edited) }
                    }.frame(width: 500, height: 520).modifier(MacSheetPrivacyCover())
                }
        }.frame(width: 580, height: 660).interactiveDismissDisabled().onAppear(perform: reload)
    }
    private var canEdit: Bool { actions.contains { $0.id == selection && [.shortcut, .text].contains($0.kind) } }
    private func move(_ offset: Int) {
        guard let i = actions.firstIndex(where: { $0.id == selection }), actions.indices.contains(i + offset) else { return }
        actions.swapAt(i, i + offset)
    }
    private func reload() {
        guard DirectAppLockV1.shared.canAccess else { return }
        do { actions = try VNCSessionPreferences.profileActions(.desktop, legacyMac: macID).filter { $0.kind != .mode }; readable = true; issue = nil }
        catch { readable = false; issue = .make(.controlsUnavailable) }
        fullscreen = macID.map(VNCSessionPreferences.fullscreen) ?? false
    }
    private func save() {
        guard DirectAppLockV1.shared.canAccess, readable else { return }
        do {
            if DirectProAccess.shared.hasPro { try VNCSessionPreferences.saveProfile(actions, mode: .desktop) }
            VNCSessionPreferences.setScrollSpeed(scrollSpeed)
            if let macID { VNCSessionPreferences.setFullscreen(fullscreen, mac: macID) }
            changed(); dismiss()
        } catch { issue = .make(.saveFailed) }
    }
}

struct MacDesktopFullScreenControls: View {
    let session: MacVNCSession
    let window: MacWindowHandle
    let actions: [VNCQuickAction]
    let settings: () -> Void
    @State private var revealed = false
    var body: some View {
        ZStack(alignment: .top) {
        Color.clear.frame(height: 8).contentShape(Rectangle()).onHover { if $0 { revealed = true } }
        HStack(spacing: 16) {
            Text(session.mac.name).font(.headline)
            Divider().frame(height: 18)
            Menu("Displays", systemImage: "display.2") {
                Button("All Displays") { session.selectDisplay(nil) }
                ForEach(session.displays) { display in Button("Display \(display.id)") { session.selectDisplay(display.id) } }
            }
            Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") { session.fit() }
            Menu("Send Key", systemImage: "keyboard") {
                ForEach(actions.filter(\.enabled)) { action in Button(action.title, systemImage: action.symbol) { if window.acceptsActions { session.quickAction(action) } } }
            }
            Button("Controls", systemImage: "slider.horizontal.3", action: settings)
            Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left") { window.toggleFullScreen() }
            Button("Disconnect", systemImage: "power") { session.disconnect() }
        }.labelStyle(.iconOnly).buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule()).padding(8)
            .opacity(revealed ? 1 : 0).allowsHitTesting(revealed)
            .frame(maxWidth: .infinity, alignment: .top)
            .onHover { revealed = $0 }
            .accessibilityHidden(!revealed)
        }.frame(height: 62, alignment: .top)
    }
}
#endif
