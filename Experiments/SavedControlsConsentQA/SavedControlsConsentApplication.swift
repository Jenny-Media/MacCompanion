import SwiftUI

private final class NoCloudEffects: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; return Array(values.values) }
    func write(_ data: Data, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = data }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; values.removeAll() }
}

/// Private QA target. Injected identity bypasses shared cloud engines.
@main @MainActor struct SavedControlsConsentApplication: App {
    let cloud: DirectCloudSyncV1
    let library: DirectMacLibraryV1
    init() {
        let name = "dev.maccompanion.savedcontrolsqa.fixture"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        library = DirectMacLibraryV1(url: root.appending(path: "macs.json"))
        precondition(library.save(id: nil, name: "Synthetic Mac", addresses: ["synthetic.invalid"]))
        cloud = DirectCloudSyncV1(defaults: defaults, url: root.appending(path: "journal.json"),
            transport: NoCloudEffects(), writerID: UUID())
        cloud.attach(library)
    }
    var body: some Scene { WindowGroup { CopyAuditHome(cloud: cloud).directAppearance() } }
}

private struct CopyAuditHome: View {
    let cloud: DirectCloudSyncV1
    private enum Route: String, CaseIterable, Identifiable {
        case sync, gestures, setup, trust, identity, manual, keyImport, recovered, recoveryNotice, backup, backupPreview
        var id: String { rawValue }
    }
    @State private var route: Route?
    @State private var recovered = Self.makeRecoveryFixture()
    @State private var backup = Self.makeBackupFixture()
    private static func makeBackupFixture() -> DirectLocalBackupStore {
        let root = URL.temporaryDirectory.appending(path: "manual-backup-qa-" + UUID().uuidString)
        let library = DirectMacLibraryV1(url: root.appending(path: "macs.json"), removeLogin: { _ in })
        precondition(library.save(id: nil, name: "Current Mac", addresses: ["synthetic.invalid"]))
        var terminal = try! JSONEncoder().encode(TerminalControlsProfile.defaults)
        var remote = try! JSONEncoder().encode(TerminalControlsProfile.remoteDefaults)
        var terminalStore = TerminalControlsStore(), remoteStore = TerminalControlsStore.remoteMac()
        terminalStore.read = { terminal }; terminalStore.write = { terminal = $0 }
        remoteStore.read = { remote }; remoteStore.write = { remote = $0 }
        terminalStore.legacyIDs = { [] }; terminalStore.legacyActions = { [] }
        return DirectLocalBackupStore(library: library, stores: [.terminal: terminalStore, .remoteMac: remoteStore],
            directory: root.appending(path: "recovery"), canAccess: { true }, sessionsActive: { false },
            pauseSync: {}, applyPreferences: { _, _ in })
    }
    private func backupPreview() -> DirectLocalBackup {
        var file = try! backup.makeBackup()
        file.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        file.macs[0].name = "Restored Mac"
        file.terminal.actions.append(.init(title: "Sample Text", kind: .text, text: "Synthetic saved text.", inMenu: false))
        return file
    }
    private static func makeRecoveryFixture() -> DirectControlsRecoveryLibrary {
        var profile = TerminalControlsProfile.defaults
        profile.freezeKeyboardLayout()
        var layout = DirectCloudKeyboardLayout(profile); layout.rows[0].title = "Synthetic alternate layout"
        layout.rows[0].alignment = .right; layout.rows[0].scrollStart = .right
        let action = TerminalControlAction(title: "Synthetic trip notes", kind: .text, text: "Synthetic recovered notes. No personal data.", inMenu: false)
        let control = DirectCloudSavedControl(action: action, bar: [], menus: [], libraryIndex: 0)
        var state = profile.syncState
        state.recovered = [
            .init(id: "fixture-layout", family: .terminal, layout: layout),
            .init(id: "fixture-text", family: .terminal, control: control)
        ]
        profile.syncState = state
        var bytes = try! JSONEncoder().encode(profile), store = TerminalControlsStore()
        store.read = { bytes }; store.write = { bytes = $0 }; store.legacyIDs = { [] }; store.legacyActions = { [] }
        return DirectControlsRecoveryLibrary(stores: [.terminal: store])
    }
    private let mac = DirectMacRecordV1(id: UUID(uuidString: "4C18D75D-C154-4460-ACB9-830E5723AD31")!, name: "Synthetic Mac", addresses: ["synthetic.invalid"])
    var body: some View {
        NavigationStack {
            List {
            Text("Saved Macs: " + backup.library.macs.map(\.name).joined(separator: ", ")).accessibilityIdentifier("fixture-backup-macs")
            ForEach(Route.allCases) { choice in
                if choice == .gestures {
                    NavigationLink { DirectGestureGuide() } label: { Text(choice.rawValue) }
                        .accessibilityIdentifier("fixture-" + choice.rawValue)
                } else {
                    Button(choice.rawValue) { route = choice }.accessibilityIdentifier("fixture-" + choice.rawValue)
                }
            }
            }.navigationTitle("Copy QA")
        }.sheet(item: $route) { choice in
            Group {
            switch choice {
            case .backup, .backupPreview:
                NavigationStack {
                    DirectLocalBackupSettings(store: backup, preview: choice == .backupPreview ? backupPreview() : nil)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { route = nil } } }
                }
            case .sync:
                NavigationStack {
                    DirectSyncSecurityForm(cloud: cloud).navigationTitle("Sync & Security")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { route = nil } } }
                }
            case .recoveryNotice:
                NavigationStack {
                    DirectSyncSecurityForm(cloud: cloud, recovered: recovered).navigationTitle("Sync & Security")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { route = nil } } }
                }
            case .recovered:
                NavigationStack {
                    DirectRecoveredChangesForm(library: recovered)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { route = nil } } }
                }
            case .gestures:
                NavigationStack {
                    DirectGestureGuide().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { route = nil } } }
                }
            case .setup: DirectMacSetupGuide()
            case .trust:
                TerminalServerTrustView(macName: mac.name, fingerprint: "ED25519 SHA256:syntheticFingerprintForLayoutQAOnly", answer: { _ in route = nil })
            case .identity: TerminalIdentityGuide(macName: mac.name)
            case .manual: TerminalManualKeySetupView(mac: mac)
            case .keyImport: TerminalKeyComposer(importing: true, save: { _, _ in false })
            }
            }.presentationSizing(.form)
        }
    }
}
