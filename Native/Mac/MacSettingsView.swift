#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacSettingsView: View {
    @State private var appearance = DirectAppearanceV1.shared
    @State private var lock = DirectAppLockV1.shared
    @State private var selection: Category? = .general
    private var category: Category { selection ?? .general }
    @State private var sheet: Sheet?
    private enum Category: String, CaseIterable, Identifiable {
        case general, controls, keys, sync
        var id: String { rawValue }
        var title: String { switch self { case .general: "General"; case .controls: "Connections & Input"; case .keys: "SSH Keys"; case .sync: "Sync & Security" } }
        var symbol: String { switch self { case .general: "gearshape"; case .controls: "slider.horizontal.3"; case .keys: "key"; case .sync: "lock.shield" } }
    }
    private enum Sheet: String, Identifiable {
        case keys, pro, desktop, terminal
        var id: String { rawValue }
    }
    var body: some View {
        HStack(spacing: 0) {
            List(Category.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).lineLimit(2).tag(item)
            }.listStyle(.sidebar).frame(width: 230)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(category.title).font(.title2.bold()).padding(.horizontal, 24).padding(.top, 22)
                Form {
                    switch category {
                    case .general:
                        Section("Appearance") {
                            Picker("App Appearance", selection: $appearance.app) { ForEach(DirectAppAppearance.allCases) { Text($0.title).tag($0) } }
                            Picker("Terminal Colors", selection: $appearance.terminal) { ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) } }
                        }
                        Section("Pro") { destination(DirectProAccess.shared.accessTitle, symbol: "sparkles", sheet: .pro) }
                    case .controls:
                        Section("Quick Actions") {
                            destination("Desktop", symbol: "display", sheet: .desktop)
                            destination("Terminal", symbol: "terminal", sheet: .terminal)
                        }
                        Section {} footer: { Text("Each editor shows whether a preference applies to one Mac or all connections on this device.") }
                    case .keys:
                        Section { destination("Manage SSH Keys", symbol: "key", sheet: .keys) }
                        Section {} footer: { Text("Use an existing key file, import a copy into Keychain, or create a new key.") }
                    case .sync:
                        DirectCloudSettingsSection()
                        Section {
                            Toggle("Require Mac Authentication", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                                .accessibilityIdentifier("app-lock-toggle")
                            if lock.message.contains("before enabling") { Text(lock.message) }
                        } header: { Text("App Unlock") } footer: { Text("Lock on screen sleep or user-session lock. Unlock with Touch ID or your Mac password.") }
                    }
                }.formStyle(.grouped)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 780, height: 540)
            .sheet(item: $sheet) { item in
                Group {
                    switch item {
                    case .keys: MacSSHKeyManager()
                    case .pro: DirectProView()
                    case .desktop: MacDesktopSettings()
                    case .terminal: MacDesktopSettings(mode: .terminal)
                    }
                }.directAppearance().modifier(MacSheetPrivacyCover())
            }
            .directAppearance().modifier(MacPrivacyCover())
            .onChange(of: lock.canAccess) { _, allowed in if !allowed { sheet = nil } }
    }
    private func destination(_ title: String, symbol: String, sheet: Sheet) -> some View {
        Button { self.sheet = sheet } label: { DirectSettingsRow(title: title, symbol: symbol) }
            .buttonStyle(.plain).padding(.vertical, 4)
    }
}
#endif
