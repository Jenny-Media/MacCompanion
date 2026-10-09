#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacSettingsView: View {
    @State private var appearance = DirectAppearanceV1.shared
    @State private var cloud = DirectCloudSyncV1.shared
    @State private var lock = DirectAppLockV1.shared
    @State private var enableCloud = false
    @State private var removeCloud = false
    @State private var sheet: Sheet?
    private enum Sheet: String, Identifiable {
        case keys, pro, desktop, terminal, trackpad
        var id: String { rawValue }
    }
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("App Appearance", selection: $appearance.app) {
                    ForEach(DirectAppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Picker("Terminal Colors", selection: $appearance.terminal) {
                    ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Connections") {
                Button("SSH Keys", systemImage: "key") { sheet = .keys }
                Button(DirectProAccess.shared.accessTitle, systemImage: "sparkles") { sheet = .pro }
                Button("Desktop Controls") { sheet = .desktop }
                Button("Terminal Controls") { sheet = .terminal }
                Button("Trackpad & Keyboard Controls") { sheet = .trackpad }
            }
            Section {
                Toggle("Sync Saved Macs with iCloud", isOn: Binding(get: { cloud.enabled }, set: {
                    if $0 { enableCloud = true } else { cloud.setEnabled(false) }
                })).disabled(cloud.busy).accessibilityIdentifier("icloud-library-toggle")
                if let notice = cloud.recovery {
                    DirectRecoveryCard(notice: notice, primary: .init(title: "Retry", perform: {
                        if notice.reason == .cloudRemoval { cloud.removeCloudCopies() } else { cloud.retry() }
                    }))
                } else { Text(cloud.status).foregroundStyle(.secondary) }
                if cloud.enabled {
                    Button("Refresh iCloud") { cloud.refresh() }.disabled(cloud.busy)
                    if cloud.busy { ProgressView("Refreshing Keychain…") }
                }
                Button("Remove iCloud Copies", role: .destructive) { removeCloud = true }.disabled(cloud.busy)
            } header: { Text("iCloud Sync · Optional") } footer: {
                Text("Off by default. Saved Macs, addresses, ports and display/input preferences sync through iCloud Keychain. Passwords, SSH private keys, server trust and saved text stay on this device.")
            }
            Section {
                Toggle("Require Mac Authentication", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                    .accessibilityIdentifier("app-lock-toggle")
                if lock.message.contains("before enabling") { Text(lock.message) }
            } header: { Text("Security") } footer: {
                Text("Lock Mac Companion when the screen sleeps or your Mac user session locks. Unlock with Touch ID or your Mac login password.")
            }
        }.formStyle(.grouped).frame(width: 580, height: 660)
            .sheet(item: $sheet) { item in
                Group {
                    switch item {
                    case .keys: MacSSHKeyManager()
                    case .pro: DirectProView()
                    case .desktop: VNCInputSettings(mode: .desktop)
                    case .terminal: VNCInputSettings(mode: .terminal)
                    case .trackpad: VNCInputSettings(mode: .trackpad)
                    }
                }.frame(minWidth: 520, minHeight: 520).directAppearance().modifier(MacSheetPrivacyCover())
            }
            .alert("Enable iCloud Sync?", isPresented: $enableCloud) {
                Button("Enable Sync") { if lock.canAccess { cloud.setEnabled(true) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(DirectCloudSyncV1.disclosure) }
            .confirmationDialog("Remove saved Mac copies from iCloud?", isPresented: $removeCloud, titleVisibility: .visible) {
                Button("Turn Off Sync & Remove Cloud Copies", role: .destructive) { if lock.canAccess { cloud.removeCloudCopies() } }
            } message: {
                Text("Local Macs and logins stay on this device. Turn off sync on your other devices first; otherwise they may upload the saved Macs again. Apple manages when removal reaches other devices.")
            }
            .directAppearance().modifier(MacPrivacyCover())
            .onChange(of: lock.canAccess) { _, allowed in
                if !allowed { sheet = nil; enableCloud = false; removeCloud = false }
            }
    }
}
#endif
