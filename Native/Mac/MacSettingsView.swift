#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacSettingsView: View {
    @State private var appearance = DirectAppearanceV1.shared
    @State private var lock = DirectAppLockV1.shared
    @State private var selection: Category? = .general
    private var category: Category { selection ?? .general }
    @State private var sheet: Sheet?
    private enum Category: String, CaseIterable, Identifiable {
        case general, controls, keys, sync, help
        var id: String { rawValue }
        var title: String { switch self { case .general: "Appearance"; case .controls: "Controls"; case .keys: "SSH Keys"; case .sync: "Sync & Security"; case .help: "Help" } }
        var symbol: String { switch self { case .general: "circle.lefthalf.filled"; case .controls: "slider.horizontal.3"; case .keys: "key"; case .sync: "lock.shield"; case .help: "questionmark.circle" } }
    }
    private enum Sheet: String, Identifiable {
        case keys, pro, desktop, terminal, help
        var id: String { rawValue }
    }
    var body: some View {
        HStack(spacing: 0) {
            List(Category.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).lineLimit(2).tag(item)
                    .accessibilityIdentifier("mac-settings-category-" + item.rawValue)
            }.listStyle(.sidebar).frame(width: 230)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(category.title).font(.title2.bold()).padding(.horizontal, 24).padding(.top, 22)
                if category == .sync {
                    DirectSyncSecurityForm()
                } else {
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
                                destination("Screen Sharing", symbol: "display", sheet: .desktop)
                                destination("Terminal", symbol: "terminal", sheet: .terminal)
                            }
                            Section {} footer: { Text("Each editor shows whether a preference applies to one Mac or all connections on this device.") }
                        case .keys:
                            Section { destination("Manage SSH Keys", symbol: "key", sheet: .keys) }
                            Section {} footer: { Text("Use an existing key file, import a copy into Keychain, or create a new key.") }
                        case .sync:
                            EmptyView()
                        case .help:
                            Section { destination("Set Up Your Mac", symbol: "questionmark.circle", sheet: .help) }
                        }
                    }.formStyle(.grouped)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 780, height: 540)
            .sheet(item: $sheet) { item in
                Group {
                    switch item {
                    case .keys: MacSSHKeyManager()
                    case .pro: DirectProView()
                    case .desktop: MacDesktopSettings()
                    case .terminal: MacDesktopSettings(mode: .terminal)
                    case .help: DirectMacSetupGuide().frame(width: 560, height: 600)
                    }
                }.directAppearance().modifier(MacSheetPrivacyCover())
            }
            .directAppearance().modifier(MacPrivacyCover())
            .onChange(of: lock.canAccess) { _, allowed in if !allowed { sheet = nil } }
    }
    private func destination(_ title: String, symbol: String, sheet: Sheet) -> some View {
        Button { self.sheet = sheet } label: { DirectSettingsRow(title: title, symbol: symbol) }
            .buttonStyle(.plain).padding(.vertical, 4)
            .accessibilityIdentifier("mac-settings-destination-" + sheet.rawValue)
    }
}
#endif
