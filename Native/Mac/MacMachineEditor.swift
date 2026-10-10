#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacMachineEditor: View {
    let library: DirectMacLibraryV1
    let mac: DirectMacRecordV1?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var addresses: [MacAddressDraft]
    @State private var showNearby = false
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
        _addresses = State(initialValue: (mac?.addresses ?? [""]).map { MacAddressDraft(value: $0) })
        _showNearby = State(initialValue: mac == nil)
        _desktopPort = State(initialValue: String(mac?.port ?? 5900)); _terminalPort = State(initialValue: String(mac?.sshPort ?? 22))
        _automatic = State(initialValue: mac?.usesAutomaticName ?? true)
        _preferred = State(initialValue: MacConnectionPreference(mac?.preferredConnection ?? .desktop))
    }
    private var hosts: [String] { addresses.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
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
                Section {
                    VStack(spacing: 10) {
                        ForEach($addresses) { $address in
                            HStack(spacing: 8) {
                                Text("\((addresses.firstIndex { $0.id == address.id } ?? 0) + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 18)
                                TextField("Hostname or IP address", text: $address.value).font(.body.monospaced()).autocorrectionDisabled()
                                    .accessibilityLabel("Address \((addresses.firstIndex { $0.id == address.id } ?? 0) + 1)")
                                    .accessibilityIdentifier("mac-machine-address-\(addresses.firstIndex { $0.id == address.id } ?? 0)")
                                Menu { Button("Move Up") { move(address.id, offset: -1) }.disabled(addresses.first?.id == address.id)
                                    Button("Move Down") { move(address.id, offset: 1) }.disabled(addresses.last?.id == address.id)
                                } label: { Image(systemName: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).frame(width: 22).help("Change connection order")
                                Button("Remove Address", systemImage: "minus.circle") {
                                    addresses.removeAll { $0.id == address.id }; if addresses.isEmpty { addresses = [.init(value: "")] }
                                }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Remove this address")
                            }
                        }
                        HStack { Button("Add Address", systemImage: "plus") { addresses.append(.init(value: "")) }.disabled(addresses.count >= 8); Spacer() }
                    }
                } header: { Label("Addresses", systemImage: "network") }
                footer: { Text("Tried from top to bottom. Add up to eight local or private VPN addresses for this Mac.") }
                Section {
                    DisclosureGroup("Nearby Computers", isExpanded: $showNearby) {
                        MacNearbyGrid(discovery: library.discovery, choose: use)
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
        }.frame(width: 620, height: 680)
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
                if !allowed { sheet = nil; forgetting = nil }
            }
    }
    private func move(_ id: UUID, offset: Int) {
        guard let index = addresses.firstIndex(where: { $0.id == id }), addresses.indices.contains(index + offset) else { return }
        addresses.swapAt(index, index + offset)
    }
    private func use(_ item: DirectMacDiscoveryItem) {
        guard DirectAppLockV1.shared.canAccess else { return }
        let selection = MacDiscoverySelection(item)
        addresses = [.init(value: selection.address)]
        if automatic { name = selection.name }
        desktopPort = String(selection.desktopPort)
        terminalPort = String(selection.terminalPort)
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
private struct MacAddressDraft: Identifiable { let id = UUID(); var value: String }

/// One discovery choice describes one computer, never fallback routes to another.
struct MacDiscoverySelection {
    let name: String
    let address: String
    let desktopPort: Int
    let terminalPort: Int
    init(_ item: DirectMacDiscoveryItem) {
        name = item.name; address = item.host
        let desktop = Set(item.services.filter { $0.connection == .desktop }.map(\.port))
        let terminal = Set(item.services.filter { $0.connection == .terminal }.map(\.port))
        desktopPort = desktop.count == 1 ? desktop.first! : 5900
        terminalPort = terminal.count == 1 ? terminal.first! : 22
    }
}

struct MacNearbyGrid: View {
    let discovery: DirectMacDiscoveryV1
    let choose: (DirectMacDiscoveryItem) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select a computer, then add alternate addresses above.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Scan", systemImage: "arrow.clockwise") { discovery.start() }.disabled(discovery.scanning)
            }
            if discovery.scanning { ProgressView("Looking for computers…") }
            else if discovery.identities.isEmpty { Label(discovery.unavailable ? "Local discovery unavailable" : "No computers found", systemImage: "network").foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], spacing: 10) {
                ForEach(DirectMacDiscoveryItem.group(discovery.identities)) { item in
                    Button { choose(item) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.family.symbol).font(.title2).frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.headline).foregroundStyle(.primary)
                                Text(item.host).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    if item.services.contains(where: { $0.connection == .desktop }) { Label("Desktop", systemImage: "macwindow") }
                                    if item.services.contains(where: { $0.connection == .terminal }) { Label("Terminal", systemImage: "terminal") }
                                }.font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityLabel("Add \(item.name), \(item.host)")
                }
            }
        }.padding(.top, 8)
    }
}
#endif
