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
        case sync, gestures, setup, trust, identity, manual, keyImport
        var id: String { rawValue }
    }
    @State private var route: Route?
    private let mac = DirectMacRecordV1(id: UUID(uuidString: "4C18D75D-C154-4460-ACB9-830E5723AD31")!, name: "Synthetic Mac", addresses: ["synthetic.invalid"])
    var body: some View {
        NavigationStack {
            List(Route.allCases) { choice in
                if choice == .gestures {
                    NavigationLink { DirectGestureGuide() } label: { Text(choice.rawValue) }
                        .accessibilityIdentifier("fixture-" + choice.rawValue)
                } else {
                    Button(choice.rawValue) { route = choice }.accessibilityIdentifier("fixture-" + choice.rawValue)
                }
            }.navigationTitle("Copy QA")
        }.sheet(item: $route) { choice in
            Group {
            switch choice {
            case .sync:
                NavigationStack {
                    DirectSyncSecurityForm(cloud: cloud).navigationTitle("Sync & Security")
                        .navigationBarTitleDisplayMode(.inline)
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
