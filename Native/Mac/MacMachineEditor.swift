#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacMachineEditor: View {
    let library: DirectMacLibraryV1
    let mac: DirectMacRecordV1?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var addresses: String
    @State private var desktopPort: String
    @State private var terminalPort: String
    @State private var automatic: Bool
    @State private var preferred: MacConnectionPreference
    @State private var sheet: Sheet?
    @State private var forgetting: Forget?
    private enum Sheet: String, Identifiable { case keys, install, pro; var id: String { rawValue } }
    private enum Forget { case desktop, terminal, serverKey, keySelection }
    init(library: DirectMacLibraryV1, mac: DirectMacRecordV1? = nil) {
        self.library = library; self.mac = mac
        _name = State(initialValue: mac?.name ?? "Mac")
        _addresses = State(initialValue: mac?.addresses.joined(separator: "\n") ?? "")
        _desktopPort = State(initialValue: String(mac?.port ?? 5900)); _terminalPort = State(initialValue: String(mac?.sshPort ?? 22))
        _automatic = State(initialValue: mac?.usesAutomaticName ?? true)
        _preferred = State(initialValue: MacConnectionPreference(mac?.preferredConnection ?? .desktop))
    }
    private var hosts: [String] { addresses.split(whereSeparator: \.isNewline).map(String.init) }
    private var valid: Bool {
        guard let vnc = Int(desktopPort), let ssh = Int(terminalPort) else { return false }
        return (try? DirectMacRecordV1.normalized(name: name, addresses: hosts, port: vnc, sshPort: ssh)) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("Name", text: $name).accessibilityIdentifier("mac-machine-name")
                    Toggle("Use detected Mac name", isOn: $automatic)
                        .accessibilityLabel("Use detected Mac name").accessibilityIdentifier("mac-machine-automatic-name")
                    Picker("Default connection", selection: $preferred.mode) { ForEach(MacConnectionMode.allCases) { Text($0.title).tag($0) } }
                        .accessibilityIdentifier("mac-machine-default-connection")
                }
                Section("Addresses, in connection order") {
                    TextEditor(text: $addresses).frame(height: 85).font(.body.monospaced()).accessibilityLabel("Local or private VPN addresses")
                        .accessibilityIdentifier("mac-machine-addresses")
                    Text("Enter one local hostname, local IP or private VPN address per line. Up to eight addresses.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(library.discovery.identities.enumerated()), id: \.offset) { _, identity in
                        Button("Use " + identity.name) { addresses = identity.host; if automatic { name = identity.name } }
                    }
                }
                Section("Service ports") {
                    TextField("Screen Sharing", text: $desktopPort).accessibilityIdentifier("mac-machine-vnc-port")
                    TextField("Remote Login", text: $terminalPort).accessibilityIdentifier("mac-machine-ssh-port")
                }
                if mac != nil {
                    Section("SSH Keys") {
                        Button("Choose or Manage Keys") { sheet = .keys }
                        Button("Install Key on This Mac") { sheet = .install }
                    }
                    Section("Saved Logins & Server Trust") {
                        Button("Forget Desktop Login", role: .destructive) { forgetting = .desktop }
                        Button("Forget Terminal Login", role: .destructive) { forgetting = .terminal }
                        Button("Forget SSH Key Selection", role: .destructive) { forgetting = .keySelection }
                        Button("Forget SSH Server Key", role: .destructive) { forgetting = .serverKey }
                    }
                }
                if let notice = library.recovery { DirectRecoveryCard(notice: notice) }
            }.formStyle(.grouped)
                .navigationTitle(mac == nil ? "Add Mac" : "Connection Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard DirectAppLockV1.shared.canAccess else { return }
                            let editsExistingMac = mac.map { edited in library.macs.contains { $0.id == edited.id } } ?? false
                            guard editsExistingMac || DirectProAccess.shared.canAddMac(count: library.macs.count) else {
                                sheet = .pro
                                return
                            }
                            if library.save(id: mac?.id, name: name, addresses: hosts, port: Int(desktopPort) ?? 5900,
                                sshPort: Int(terminalPort), usesAutomaticName: automatic, preferredConnection: preferred.shared) { dismiss() }
                        }.disabled(!valid).accessibilityIdentifier("mac-save-machine")
                    }
                }
                .sheet(item: $sheet) { item in
                    Group {
                        switch item {
                        case .keys: MacSSHKeyManager(mac: mac)
                        case .install: if let mac { TerminalKeyInstallView(mac: mac).frame(minWidth: 520, minHeight: 500) }
                        case .pro: DirectProView().frame(minWidth: 480, minHeight: 460)
                        }
                    }.modifier(MacSheetPrivacyCover())
                }
                .confirmationDialog("Forget this saved login or trust record on this Mac?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
                    Button("Forget", role: .destructive) { forget() }
                }
        }.frame(width: 550, height: 600)
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
                if !allowed { sheet = nil; forgetting = nil }
            }
    }
    private func forget() {
        guard DirectAppLockV1.shared.canAccess, let mac, let forgetting else { return }
        do {
            switch forgetting {
            case .desktop: try DesktopCredentialStoreV1.remove(mac.id)
            case .terminal: try TerminalSecretStore.forgetLogin(mac.id)
            case .serverKey: try TerminalSecretStore.forgetHostKey(mac.id)
            case .keySelection: try TerminalSecretStore.forgetKey(mac.id)
            }
        } catch { library.recovery = .make(.removeFailed) }
        self.forgetting = nil
    }
}
#endif
