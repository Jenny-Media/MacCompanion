#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacDesktopSettings: View {
    var macID: UUID? = nil
    var mode: DirectControlMode = .desktop
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var scrollSpeed = VNCSessionPreferences.scrollSpeed
    @State private var fullscreen = false
    @State private var actions: [VNCQuickAction] = []
    @State private var issue: DirectRecoveryNotice?
    @State private var readable = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DirectQuickActionsEditor(actions: $actions, mode: mode, readable: readable, macID: macID)
                }
                if mode == .desktop {
                    Section {
                        if macID != nil { Toggle("Open this desktop in full screen", isOn: $fullscreen) }
                        DisclosureGroup("Pointer, zoom & pan") {
                            LabeledContent("Pointer", value: "Direct control")
                            Text("Pinch to zoom. Hold Option and scroll to pan. Use Fit to Window to see the whole desktop.").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Label("Display", systemImage: "display") }
                    Section {
                        LabeledContent("Scroll speed") {
                            Slider(value: $scrollSpeed, in: VNCSessionPreferences.scrollSpeedRange, step: 0.25)
                                .frame(width: 180).accessibilityLabel("Scroll Speed").accessibilityIdentifier("scroll-speed-slider")
                            Text(scrollSpeed.formatted(.number.precision(.fractionLength(0...2))) + "×").monospacedDigit().frame(width: 36)
                        }
                        Button("Reset to Default") { scrollSpeed = 1 }
                    } header: { Label("Scrolling", systemImage: "computermouse") } footer: { Text("Applies to all Mac connections on this Mac.") }
                }

                if let issue {
                    DirectRecoveryCard(notice: issue,
                        primary: .init(title: readable ? "Retry Save" : "Retry", perform: { if readable { save() } else { reload() } }),
                        secondary: readable ? .init(title: "Keep Editing", perform: { self.issue = nil }) : nil)
                }
            }.formStyle(.grouped).navigationTitle(mode.title + " Controls")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!readable || !DirectQuickActionEditing.valid(actions, mode: mode)) }
                }
        }.frame(width: 820, height: 680).interactiveDismissDisabled().directAppearance().onAppear(perform: reload)
    }

    private func reload() {
        guard DirectAppLockV1.shared.canAccess else { return }
        do { actions = try VNCSessionPreferences.profileActions(mode, legacyMac: macID).filter { $0.kind != .mode }; readable = true; issue = nil }
        catch { readable = false; issue = .make(.controlsUnavailable) }
        fullscreen = macID.map(VNCSessionPreferences.fullscreen) ?? false
    }
    private func save() {
        guard DirectAppLockV1.shared.canAccess, readable, DirectQuickActionEditing.valid(actions, mode: mode) else { return }
        do {
            if DirectProAccess.shared.hasPro { try VNCSessionPreferences.saveProfile(actions, mode: mode) }
            if mode == .desktop {
                VNCSessionPreferences.setScrollSpeed(scrollSpeed)
                if let macID { VNCSessionPreferences.setFullscreen(fullscreen, mac: macID) }
            }
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
            Button("Fit to Window", systemImage: "arrow.down.right.and.arrow.up.left") { session.fit() }
            Menu("Quick Actions", systemImage: "keyboard") {
                MacQuickActionsMenu(actions: actions, perform: { if window.acceptsActions { session.quickAction($0) } }, customize: settings)
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
