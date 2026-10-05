#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import Security
import SwiftUI

struct DirectMacRecordV1: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var addresses: [String]
    var port: Int
    var sshPort: Int = 22
    var address: String { addresses.first ?? "" }
    private enum CodingKeys: String, CodingKey { case id, name, address, addresses, port, sshPort }
    init(id: UUID, name: String, addresses: [String], port: Int = 5900, sshPort: Int = 22) {
        self.id = id; self.name = name; self.addresses = addresses; self.port = port; self.sshPort = sshPort
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        addresses = try c.decodeIfPresent([String].self, forKey: .addresses) ?? [c.decode(String.self, forKey: .address)]
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 5900
        sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(addresses, forKey: .addresses); try c.encode(port, forKey: .port); try c.encode(sshPort, forKey: .sshPort)
    }
    static func normalized(id: UUID = UUID(), name: String, address: String) throws -> Self {
        try normalized(id: id, name: name, addresses: [address])
    }
    static func port(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return 5900 }
        guard let port = Int(value), (1...65535).contains(port) else { return nil }
        return port
    }
    static func normalized(id: UUID = UUID(), name: String, addresses: [String], port: Int = 5900, sshPort: Int = 22) throws -> Self {
        let hosts = addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._:%")
        guard (1...8).contains(hosts.count), (1...65535).contains(port), (1...65535).contains(sshPort), Set(hosts).count == hosts.count,
              hosts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              !label.isEmpty, label.count <= 80,
              !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw LibraryFailure.invalid }
        return .init(id: id, name: label, addresses: hosts, port: port, sshPort: sshPort)
    }
    enum LibraryFailure: Error { case invalid }
}

enum DesktopCredentialStoreV1 {
    struct Login: Codable { let username: String; let password: String }
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "media.jenny.maccompanion.direct-screen-sharing-login.v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
    }
    @MainActor static func read(_ id: UUID) -> Login? {
        guard DirectAppLockV1.shared.canAccess else { return nil }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Login.self, from: data)
    }
    static func save(_ login: Login, hostID: UUID) throws {
        let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(login),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(hostID) as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(hostID).merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw StoreFailure.unavailable }
        } else if status != errSecSuccess { throw StoreFailure.unavailable }
    }
    static func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreFailure.unavailable }
    }
    enum StoreFailure: Error { case unavailable }
}

@MainActor @Observable final class DirectMacLibraryV1 {
    private struct File: Codable { var version = 3; var macs: [DirectMacRecordV1] }
    private(set) var macs: [DirectMacRecordV1] = []
    private(set) var readable = true
    var failure: String?
    var localChange: ((UUID) -> Void)?
    private let url: URL
    private let removeLogin: (UUID) throws -> Void
    init(url: URL? = nil, removeLogin: @escaping (UUID) throws -> Void = DesktopCredentialStoreV1.remove) {
        self.url = url ?? URL.applicationSupportDirectory.appending(path: "direct-macs-v1.json")
        self.removeLogin = removeLogin
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: self.url))
                guard (1...3).contains(file.version), file.macs.count <= 64,
                      Set(file.macs.map(\.id)).count == file.macs.count else { throw DirectMacRecordV1.LibraryFailure.invalid }
                for mac in file.macs {
                    guard try DirectMacRecordV1.normalized(id: mac.id, name: mac.name, addresses: mac.addresses, port: mac.port, sshPort: mac.sshPort) == mac else { throw DirectMacRecordV1.LibraryFailure.invalid }
                }
                macs = file.macs
            }
        } catch { readable = false; failure = "Saved Macs could not be read. Your existing file has been preserved." }
    }
    func save(id: UUID?, name: String, address: String) -> Bool { save(id: id, name: name, addresses: [address]) }
    func save(id: UUID?, name: String, addresses: [String], port: Int = 5900, sshPort: Int? = nil) -> Bool {
        do {
            guard readable else { return false }
            let record = try DirectMacRecordV1.normalized(id: id ?? UUID(), name: name, addresses: addresses, port: port, sshPort: sshPort ?? macs.first(where: { $0.id == id })?.sshPort ?? 22)
            var next = macs
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else { guard next.count < 64 else { failure = "You can save up to 64 Macs."; return false }; next.append(record) }
            try write(next); localChange?(record.id); return true
        } catch { failure = "Could not save this Mac. Use a name, unique local/VPN addresses and a port from 1 to 65535."; return false }
    }
    func sharingEndpoint(addresses: [String], port: Int, excluding id: UUID?) -> [DirectMacRecordV1] {
        let routes = Set(addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return macs.filter { $0.id != id && $0.port == port && !routes.isDisjoint(with: $0.addresses) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func remove(_ mac: DirectMacRecordV1) {
        do {
            guard readable else { return }
            try removeLogin(mac.id)
            try TerminalSecretStore.remove(mac.id)
            try write(macs.filter { $0.id != mac.id }); localChange?(mac.id); VNCSessionPreferences.clear(mac.id)
        } catch { failure = "Could not remove this Mac and its saved login. Please retry." }
    }
    func forgetLogin(_ mac: DirectMacRecordV1) {
        do { try removeLogin(mac.id); failure = nil }
        catch { failure = "Could not forget this Mac’s saved login. Please retry." }
    }
    func applyCloud(_ next: [DirectMacRecordV1]) throws {
        guard readable, next.count <= 64, Set(next.map(\.id)).count == next.count else { throw DirectCloudError.invalid }
        if next != macs { try write(next) }
    }
    private func write(_ next: [DirectMacRecordV1]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(File(macs: next)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        macs = next; failure = nil
    }
}

struct DirectMacLibraryRootV1: View {
    @State private var library = DirectMacLibraryV1()
    @State private var selected: DirectMacRecordV1?
    @State private var inputOnly = false
    @State private var terminal: DirectMacRecordV1?
    @State private var appLock = DirectAppLockV1.shared
    private struct EditorSelection: Identifiable { let id = UUID(); let mac: DirectMacRecordV1? }
    @State private var editor: EditorSelection?
    @State private var removing: DirectMacRecordV1?
    @State private var setup = false
    @State private var settings = false
    @State private var search = ""
    private var visibleMacs: [DirectMacRecordV1] {
        library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.addresses.contains { $0.localizedCaseInsensitiveContains(search) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if library.macs.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "desktopcomputer").font(.system(size: 48)).foregroundStyle(.blue)
                            Text("Your Macs, within reach").font(.title3.bold())
                            Text("Enable Screen Sharing or Remote Login on your Mac, then add its local or Tailscale address.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Add your first Mac", systemImage: "plus") { edit(nil) }
                                .buttonStyle(.borderedProminent).disabled(!library.readable)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                } else {
                    Section {
                        ForEach(visibleMacs) { mac in
                            HStack(spacing: 12) {
                                Button { inputOnly = false; selected = mac } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.blue)
                                            .frame(width: 44, height: 44).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(mac.name).font(.headline).foregroundStyle(.primary)
                                            Text(mac.addresses.count > 1 ? "\(mac.address) · \(mac.addresses.count) addresses" : mac.address).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Connect to " + mac.name)
                                Menu {
                                    Section("Connect") {
                                        Button("Desktop", systemImage: "desktopcomputer") { inputOnly = false; selected = mac }
                                        Button("Trackpad & Keyboard", systemImage: "rectangle.and.hand.point.up.left") { inputOnly = true; selected = mac }
                                        Button("Terminal", systemImage: "terminal") { terminal = mac }
                                    }
                                    Section("Manage Mac") {
                                        Button("Edit Mac", systemImage: "pencil") { edit(mac) }
                                        Button("Remove Mac", systemImage: "trash", role: .destructive) { removing = mac }
                                    }
                                } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
                                    .accessibilityLabel("Manage " + mac.name)
                            }.padding(.vertical, 4)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { removing = mac }
                                    Button("Edit") { edit(mac) }.tint(.blue)
                                }
                        }
                        if visibleMacs.isEmpty { Text("No matching Macs").foregroundStyle(.secondary) }
                    } footer: { Text("Tap a Mac for Desktop. Its menu also offers Terminal, Trackpad & Keyboard, and Mac settings.") }
                }
                Section {
                    Button("App Settings", systemImage: "gearshape") { settings = true }
                    Button("Set Up Your Mac", systemImage: "questionmark.circle") { setup = true }
                } footer: {
                    Text("Use a trusted local network or private VPN. Desktop and input traffic are not encrypted by this development app.")
                }
            }
            .navigationTitle("My Macs")
            .searchable(text: $search, prompt: "Find a Mac")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mac", systemImage: "plus") { edit(nil) }.disabled(!library.readable)
                }
            }
            .sheet(item: $editor) { selection in DirectMacEditorV1(mac: selection.mac, library: library) }
            .sheet(isPresented: $setup) { DirectMacSetupV1() }
            .sheet(isPresented: $settings) { DirectSessionSettingsV1() }
            .alert("Saved Macs", isPresented: Binding(get: { library.failure != nil && editor == nil }, set: { if !$0 { library.failure = nil } })) {
                Button("OK") { library.failure = nil }
            } message: { Text(library.failure ?? "") }
            .confirmationDialog("Remove this Mac and its saved login?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove Mac", role: .destructive) { if let removing { library.remove(removing) }; removing = nil }
            }
            .onOpenURL { url in
                guard let id = RemoteSessionActivityAttributes.resumeMacID(from: url),
                      let mac = library.macs.first(where: { $0.id == id }), selected == nil else { return }
                selected = mac
            }
            .fullScreenCover(item: $terminal) { mac in
                DirectTerminalView(mac: mac, exit: { terminal = nil })
            }
            .fullScreenCover(item: $selected) { mac in
                VNCRemoteDesktopView(mac: mac, inputOnly: inputOnly, showMacs: { selected = nil })
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .opacity(appLock.canAccess ? 1 : 0)
        .allowsHitTesting(appLock.canAccess)
        .accessibilityHidden(!appLock.canAccess)
        .onAppear { appLock.install(); DirectCloudSyncV1.shared.attach(library) }
    }
    private func edit(_ mac: DirectMacRecordV1?) { editor = EditorSelection(mac: mac) }
}

private struct DirectMacEditorV1: View {
    @Environment(\.dismiss) private var dismiss
    let mac: DirectMacRecordV1?
    @Bindable var library: DirectMacLibraryV1
    private struct Draft: Identifiable { let id = UUID(); var address: String }
    @State private var name: String
    @State private var credentialAction: CredentialAction?
    private enum CredentialAction: String, Identifiable {
        case desktop, terminal, serverKey
        var id: String { rawValue }
        var title: String { switch self { case .desktop: "Forget Desktop Login"; case .terminal: "Forget Terminal Login"; case .serverKey: "Forget SSH Server Key" } }
        var detail: String { self == .serverKey ? "You will need to verify the server fingerprint the next time you use Terminal." : "You will need to enter this Mac’s login the next time you connect. The other login is kept." }
    }
    @State private var addresses: [Draft]
    @State private var port: String
    @State private var sshPort: String
    @State private var advanced = false
    @State private var keySettings = false
    @State private var addressEditMode: EditMode = .inactive
    init(mac: DirectMacRecordV1?, library: DirectMacLibraryV1) {
        self.mac = mac; self.library = library
        _name = State(initialValue: mac?.name ?? "My Mac")
        _addresses = State(initialValue: (mac?.addresses ?? [""]).map { Draft(address: $0) })
        _sshPort = State(initialValue: mac.map { $0.sshPort == 22 ? "" : String($0.sshPort) } ?? "")
        _port = State(initialValue: mac.map { $0.port == 5900 ? "" : String($0.port) } ?? "")
    }
    private var resolvedPort: Int? { DirectMacRecordV1.port(from: port) }
    private var resolvedSSHPort: Int? { sshPort.trimmingCharacters(in: .whitespaces).isEmpty ? 22 : DirectMacRecordV1.port(from: sshPort) }
    private var valid: Bool {
        guard let resolvedSSHPort, let resolvedPort else { return false }
        return (try? DirectMacRecordV1.normalized(name: name, addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort)) != nil
    }
    private var sharedNames: String? {
        guard let resolvedPort else { return nil }
        let shared = library.sharingEndpoint(addresses: addresses.map(\.address), port: resolvedPort, excluding: mac?.id)
        guard !shared.isEmpty else { return nil }
        let names = shared.prefix(3).map(\.name).joined(separator: ", ")
        return shared.count > 3 ? "\(names) and \(shared.count - 3) more" : names
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") { TextField("Name", text: $name) }
                Section {
                    ForEach($addresses) { $draft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(addresses.first?.id == draft.id ? "Preferred address" : "Fallback address").font(.caption).foregroundStyle(.secondary)
                            TextField("IP address or hostname", text: $draft.address)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        }
                    }.onDelete { addresses.remove(atOffsets: $0) }.onMove { addresses.move(fromOffsets: $0, toOffset: $1) }
                    if addresses.count < 8 { Button("Add Address", systemImage: "plus") { addresses.append(Draft(address: "")) } }
                } header: {
                    HStack {
                        Text("Connection Addresses")
                        Spacer()
                        if addresses.count > 1 {
                            Button(addressEditMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { addressEditMode = addressEditMode.isEditing ? .inactive : .active }
                            }
                            .textCase(nil)
                            .accessibilityLabel(addressEditMode.isEditing ? "Finish Reordering Addresses" : "Reorder Addresses")
                            .accessibilityIdentifier("mac-reorder-addresses")
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add local and Tailscale addresses for this same Mac. Addresses are tried in order until one responds. Use Reorder to change priority.")
                        if let sharedNames { Label("Also used by \(sharedNames). Each saved Mac keeps its own login.", systemImage: "info.circle") }
                    }
                }
                Section {
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        TextField("5900 (default)", text: $port).keyboardType(.numberPad)
                            .accessibilityLabel("Port").accessibilityIdentifier("mac-port")
                        Text("Leave blank to use Screen Sharing port 5900.").font(.footnote).foregroundStyle(.secondary)
                        TextField("22 (default)", text: $sshPort).keyboardType(.numberPad).accessibilityLabel("SSH Port")
                        Text("Leave SSH Port blank to use 22. Terminal requires Remote Login on your Mac.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let mac {
                    Section {
                        Button("SSH Key", systemImage: "key") { keySettings = true }
                        Button("Forget Desktop Login", systemImage: "key.slash", role: .destructive) { credentialAction = .desktop }
                        Button("Forget Terminal Login", systemImage: "terminal", role: .destructive) { credentialAction = .terminal }
                        Button("Forget SSH Server Key", systemImage: "checkmark.shield", role: .destructive) { credentialAction = .serverKey }
                    } header: { Text("Saved Logins & Server Trust") }
                    footer: { Text("Address and port edits keep saved logins. Desktop and Terminal use separate logins for \(mac.name).") }
                }
            }
            .sheet(isPresented: $keySettings) { if let mac { TerminalKeySettings(mac: mac) } }
            .environment(\.editMode, $addressEditMode)
            .onChange(of: addresses.count) { _, count in
                if count < 2 { addressEditMode = .inactive }
            }
            .navigationTitle(mac == nil ? "Add Mac" : "Edit Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let resolvedPort, library.save(id: mac?.id, name: name, addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort) { dismiss() }
                    }.disabled(!valid)
                }
            }
            .alert("Saved Macs", isPresented: Binding(get: { library.failure != nil }, set: { if !$0 { library.failure = nil } })) {
                Button("OK") { library.failure = nil }
            } message: { Text(library.failure ?? "") }
            .confirmationDialog(credentialAction?.title ?? "Saved Login", isPresented: Binding(get: { credentialAction != nil }, set: { if !$0 { credentialAction = nil } }), titleVisibility: .visible, presenting: credentialAction) { action in
                Button(action.title, role: .destructive) {
                    guard let mac else { return }
                    do {
                        switch action {
                        case .desktop: library.forgetLogin(mac)
                        case .terminal: try TerminalSecretStore.forgetLogin(mac.id)
                        case .serverKey: try TerminalSecretStore.forgetHostKey(mac.id)
                        }
                    } catch { library.failure = "Could not remove the saved entry. It has been preserved. Unlock your iPhone and try again." }
                    credentialAction = nil
                }
            } message: { action in Text(action.detail) }
        }
    }
}

struct DirectSessionSettingsV1: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VNCSessionActivityController.preferenceKey) private var showSession = true
    @State private var lock = DirectAppLockV1.shared
    @State private var cloud = DirectCloudSyncV1.shared
    @State private var enableCloud = false
    @State private var removeCloud = false
    @Environment(DirectAppearanceV1.self) private var appearance
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("App Appearance", selection: Binding(get: { appearance.app }, set: { appearance.app = $0 })) {
                        ForEach(DirectAppAppearance.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("app-appearance")
                    Picker("Terminal Colors", selection: Binding(get: { appearance.terminal }, set: { appearance.terminal = $0 })) {
                        ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("terminal-appearance")
                }
                Section {
                    Toggle("Sync Saved Macs with iCloud", isOn: Binding(get: { cloud.enabled }, set: { if $0 { enableCloud = true } else { cloud.setEnabled(false) } }))
                        .disabled(cloud.busy).accessibilityIdentifier("icloud-library-toggle")
                    Text(cloud.status).font(.footnote).foregroundStyle(.secondary)
                    if cloud.enabled {
                        Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { cloud.refresh() }.disabled(cloud.busy)
                        if cloud.busy { ProgressView("Refreshing Keychain…") }
                    }
                    Button("Remove iCloud Copies", systemImage: "icloud.slash", role: .destructive) { removeCloud = true }.disabled(cloud.busy)
                } header: { Text("iCloud Sync · Optional") } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                    Text("Off by default. Sync uses iCloud Keychain and depends on your Apple Account and trusted devices for privacy. Saved Macs, addresses, ports and display/input settings sync. Passwords, SSH private keys, server trust and saved text stay on this device.")
                    Link("Apple’s iCloud security overview", destination: URL(string: "https://support.apple.com/en-us/102651")!)
                    }
                }
                Section {
                    Toggle("Require Face ID or Passcode", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                        .accessibilityIdentifier("app-lock-toggle")
                } header: { Text("Security") } footer: {
                    Text("Optional app unlock protects saved Macs and sessions when you return. Your Mac login remains separate.")
                    if lock.message.contains("before enabling") { Text(lock.message) }
                }
                Section {
                    Toggle("Show session in Dynamic Island", isOn: $showSession)
                        .accessibilityIdentifier("session-live-activity")
                } header: { Text("Session") } footer: {
                    Text("Show session status on Dynamic Island and the Lock Screen, with a quick way back to your Mac. Connection recovery works with this setting on or off.")
                }
            }
            .alert("Enable iCloud Sync?", isPresented: $enableCloud) {
                Button("Enable Sync") { cloud.setEnabled(true) }; Button("Cancel", role: .cancel) {}
            } message: { Text(DirectCloudSyncV1.disclosure) }
            .confirmationDialog("Remove saved Mac copies from iCloud?", isPresented: $removeCloud, titleVisibility: .visible) {
                Button("Turn Off Sync & Remove Cloud Copies", role: .destructive) { cloud.removeCloudCopies() }
            } message: { Text("Local Macs and logins stay on this device. Turn off sync on your other devices first; otherwise they may upload the saved Macs again. Apple manages when removal reaches other devices.") }
            .navigationTitle("App Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct DirectMacSetupV1: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("1. Enable Screen Sharing or Remote Login") {
                    Text("On your Mac, open System Settings → General → Sharing. Turn on Screen Sharing for Desktop, or Remote Login for Terminal, and allow your Mac account.")
                }
                Section("2. Add the Mac") {
                    Text("Use the local address shown in Screen Sharing settings, or a Tailscale address with Tailscale connected on both devices.")
                }
                Section("3. Sign in") {
                    Text("Enter that Mac account’s username and password in the app. Save the login on this iPhone if you want to reconnect without typing it again.")
                }
                Section { Text("No Mac Companion installation is needed on your Mac.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Set Up Your Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
