#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
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
    var usesAutomaticName = false
    var detectedName: String?
    var modelIdentifier: String?
    var preferredConnection: DirectMacConnection = .desktop
    var family: DirectMacFamily { .detect(modelIdentifier) }
    var address: String { addresses.first ?? "" }
    private enum CodingKeys: String, CodingKey { case id, name, address, addresses, port, sshPort, usesAutomaticName, detectedName, modelIdentifier, preferredConnection }
    init(id: UUID, name: String, addresses: [String], port: Int = 5900, sshPort: Int = 22) {
        self.id = id; self.name = name; self.addresses = addresses; self.port = port; self.sshPort = sshPort
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        addresses = try c.decodeIfPresent([String].self, forKey: .addresses) ?? [c.decode(String.self, forKey: .address)]
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 5900
        sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        usesAutomaticName = try c.decodeIfPresent(Bool.self, forKey: .usesAutomaticName) ?? false
        detectedName = try c.decodeIfPresent(String.self, forKey: .detectedName)
        modelIdentifier = try c.decodeIfPresent(String.self, forKey: .modelIdentifier)
        preferredConnection = try c.decodeIfPresent(DirectMacConnection.self, forKey: .preferredConnection) ?? .desktop
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(addresses, forKey: .addresses); try c.encode(port, forKey: .port); try c.encode(sshPort, forKey: .sshPort)
        try c.encode(usesAutomaticName, forKey: .usesAutomaticName)
        try c.encodeIfPresent(detectedName, forKey: .detectedName); try c.encodeIfPresent(modelIdentifier, forKey: .modelIdentifier)
        try c.encode(preferredConnection, forKey: .preferredConnection)
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
              // A bound method on this temporary CharacterSet misclassifies names under -O.
              !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LibraryFailure.invalid }
        return .init(id: id, name: label, addresses: hosts, port: port, sshPort: sshPort)
    }
    func validated() throws -> Self {
        let base = try Self.normalized(id: id, name: name, addresses: addresses, port: port, sshPort: sshPort)
        guard base.name == name, base.addresses == addresses,
              detectedName.map({ DirectMacDetectedIdentity.cleanName($0) == $0 }) ?? true,
              modelIdentifier.map({ DirectMacDetectedIdentity.cleanModel($0) == $0 }) ?? true else { throw LibraryFailure.invalid }
        return self
    }
    func applying(_ identity: DirectMacDetectedIdentity) -> Self {
        guard identity.matches(self), let detected = DirectMacDetectedIdentity.cleanName(identity.name) else { return self }
        var next = self
        next.detectedName = detected
        if usesAutomaticName { next.name = detected }
        if let model = identity.modelIdentifier.flatMap(DirectMacDetectedIdentity.cleanModel) { next.modelIdentifier = model }
        return next
    }
    enum LibraryFailure: Error { case invalid }
}

enum DesktopCredentialStoreV1 {
    struct Login: Codable { let username: String; let password: String }
    private static func query(_ id: UUID) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "media.jenny.maccompanion.direct-screen-sharing-login.v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
    @MainActor static func read(_ id: UUID) -> Login? { try? readChecked(id) }
    @MainActor static func readChecked(_ id: UUID) throws -> Login? {
        guard DirectAppLockV1.shared.canAccess else { throw StoreFailure.unavailable }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreFailure.unavailable }
        return try JSONDecoder().decode(Login.self, from: data)
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
    private struct File: Codable { var version = 5; var macs: [DirectMacRecordV1] }
    private(set) var macs: [DirectMacRecordV1] = []
    private(set) var readable = true
    var recovery: DirectRecoveryNotice?
    var failure: String? {
        get { recovery?.message }
        set { recovery = newValue.map { .make(.saveFailed, message: $0) } }
    }
    var localChange: ((UUID) -> Void)?
    let discovery = DirectMacDiscoveryV1()
    private let url: URL
    private let removeLogin: (UUID) throws -> Void
    init(url: URL? = nil, removeLogin: @escaping (UUID) throws -> Void = DesktopCredentialStoreV1.remove) {
        self.url = url ?? DirectClientPlatformV1.dataURL("direct-macs-v1.json")
        self.removeLogin = removeLogin
        reload()
        discovery.updated = { [weak self] in
            guard let self else { return }
            self.updateDetectedMetadata(self.discovery.identities)
        }
    }
    func reload() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
                guard (1...5).contains(file.version), file.macs.count <= 64,
                      Set(file.macs.map(\.id)).count == file.macs.count else { throw DirectMacRecordV1.LibraryFailure.invalid }
                for mac in file.macs {
                    _ = try mac.validated()
                }
                macs = file.version < 5 ? file.macs.sorted(by: Self.alphabetical) : file.macs
            }
            readable = true; recovery = nil
        } catch { readable = false; recovery = .make(.savedDataUnavailable, message: "Saved Macs couldn’t be read. Existing data is kept. Retry when device storage is available; unreadable data won’t be replaced.") }
    }
    func save(id: UUID?, name: String, address: String) -> Bool { save(id: id, name: name, addresses: [address]) }
    func save(id: UUID?, name: String, addresses: [String], port: Int = 5900, sshPort: Int? = nil,
              usesAutomaticName: Bool? = nil, preferredConnection: DirectMacConnection? = nil) -> Bool {
        do {
            guard readable else { return false }
            let old = macs.first { $0.id == id }
            var record = try DirectMacRecordV1.normalized(id: id ?? UUID(), name: name, addresses: addresses, port: port, sshPort: sshPort ?? old?.sshPort ?? 22)
            record.usesAutomaticName = usesAutomaticName ?? (old?.name == record.name ? old?.usesAutomaticName : false) ?? false
            record.preferredConnection = preferredConnection ?? old?.preferredConnection ?? .desktop
            if let old, Set(old.addresses) == Set(record.addresses), old.port == record.port, old.sshPort == record.sshPort {
                record.detectedName = old.detectedName; record.modelIdentifier = old.modelIdentifier
            }
            if record.usesAutomaticName, let detected = record.detectedName { record.name = detected }
            if let identity = DirectMacDetectedIdentity.match(record, in: discovery.identities) { record = record.applying(identity) }
            _ = try record.validated()
            var next = macs
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else { guard next.count < 64 else { failure = "You can save up to 64 Macs."; return false }; next.append(record) }
            try write(next); localChange?(record.id); return true
        } catch { failure = "Could not save this Mac. Use a name, unique local/VPN addresses and a port from 1 to 65535."; return false }
    }
    func updateDetectedMetadata(_ identities: [DirectMacDetectedIdentity]) {
        guard readable else { return }
        let next = macs.map { mac in
            DirectMacDetectedIdentity.match(mac, in: identities).map { mac.applying($0) } ?? mac
        }
        guard next != macs else { return }
        do {
            let changed = zip(macs, next).filter { $0 != $1 }.map { $1.id }
            try write(next); changed.forEach { localChange?($0) }
        } catch { failure = "Detected Mac details couldn’t be saved. Your saved Macs are kept." }
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
        } catch { recovery = .make(.removeFailed) }
    }
    func forgetLogin(_ mac: DirectMacRecordV1) {
        do { try removeLogin(mac.id); failure = nil }
        catch { recovery = .make(.removeFailed, message: "The saved Desktop login couldn’t be removed. Review it and retry.") }
    }
    func applyCloud(_ next: [DirectMacRecordV1]) throws {
        guard readable, next.count <= 64, Set(next.map(\.id)).count == next.count else { throw DirectCloudError.invalid }
        try next.forEach { _ = try $0.validated() }
        let records = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let existingIDs = Set(macs.map(\.id))
        let ordered = macs.compactMap { records[$0.id] } + next.filter { !existingIDs.contains($0.id) }.sorted(by: Self.alphabetical)
        if ordered != macs { try write(ordered) }
    }
    private static func alphabetical(_ lhs: DirectMacRecordV1, _ rhs: DirectMacRecordV1) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
    }
    @discardableResult func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
        guard readable, !offsets.isEmpty, offsets.allSatisfy({ macs.indices.contains($0) }),
              (0...macs.count).contains(destination) else { return false }
        let moving = offsets.map { macs[$0] }
        var next = macs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        next.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        do { try write(next); return true }
        catch { failure = "The new order couldn’t be saved. Your previous order is kept."; return false }
    }
    private func write(_ next: [DirectMacRecordV1]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DirectClientPlatformV1.write(JSONEncoder().encode(File(macs: next)), to: url)
        macs = next; failure = nil
    }
}

#if os(iOS)
struct DirectMacLibraryRootV1: View {
    @State private var library: DirectMacLibraryV1
    init(library: DirectMacLibraryV1 = DirectMacLibraryV1()) { _library = State(initialValue: library) }
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
    @State private var editMode: EditMode = .inactive
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    @ScaledMetric(relativeTo: .title2) private var menuIconSize = 22
    @Environment(\.scenePhase) private var scenePhase
    private var visibleMacs: [DirectMacRecordV1] {
        library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.addresses.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        NavigationStack {
            List {
                if let notice = library.recovery {
                    Section { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry", perform: { library.reload() }), secondary: .init(title: "Help", perform: { setup = true })) }
                }
                if !library.readable {
                    Section { Text("Saved Macs are unavailable. Adding and editing are paused to protect the existing file.").foregroundStyle(.secondary) }
                } else if library.macs.isEmpty {
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
                                Button { open(mac, input: mac.preferredConnection.inputOnly, terminalMode: mac.preferredConnection.terminalMode) } label: {
                                    DirectMacListRowLabel(mac: mac)
                                }.buttonStyle(.plain).disabled(editMode.isEditing)
                                    .accessibilityLabel("Connect to " + mac.name + " using " + mac.preferredConnection.title)
                                    .accessibilityHint(mac.family.title)
                                if !editMode.isEditing {
                                    Menu {
                                        Section("Connect") {
                                            Button("Desktop", systemImage: DirectMacConnection.desktop.symbol) { open(mac, input: false, terminalMode: false) }
                                            Button("Trackpad & Keyboard", systemImage: "rectangle.and.hand.point.up.left") { open(mac, input: true, terminalMode: false) }
                                            Button("Terminal", systemImage: "terminal") { open(mac, input: false, terminalMode: true) }
                                        }
                                        Section("Manage Mac") {
                                            Button("Mac Settings", systemImage: "gearshape") { edit(mac) }
                                            if !pro.hasPro { Button("Use as My Free Mac") { pro.chooseFreeMac(mac.id) } }
                                            Button("Remove Mac", systemImage: "trash", role: .destructive) { removing = mac }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: min(menuIconSize, 32))).frame(width: 44, height: 44) }
                                        .accessibilityLabel("Manage " + mac.name)
                                }
                            }.padding(.vertical, 4)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { removing = mac }
                                    Button("Edit") { edit(mac) }.tint(.blue)
                                }
                        }.onMove { offsets, destination in
                            guard search.isEmpty else { return }
                            if let first = library.macs.first { _ = pro.canUseMac(first.id, among: library.macs.map(\.id)) }
                            library.move(fromOffsets: offsets, toOffset: destination)
                        }.moveDisabled(!search.isEmpty)
                        if visibleMacs.isEmpty { Text("No matching Macs").foregroundStyle(.secondary) }
                    } footer: { Text(editMode.isEditing ? "Drag the handles to reorder your Macs." : "Tap a Mac to open its preferred connection. Change Open on Tap in Mac Settings, or choose a mode from its menu.") }
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
            .onChange(of: search) { _, value in if !value.isEmpty { editMode = .inactive } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.readable && library.macs.count > 1 {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }.disabled(!search.isEmpty).accessibilityIdentifier("macs-edit-order")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mac", systemImage: "plus") { edit(nil) }.disabled(!library.readable)
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $editor) { selection in DirectMacEditorV1(mac: selection.mac, library: library) }
            .sheet(isPresented: $setup) { DirectMacSetupV1() }
            .sheet(isPresented: $settings) { DirectSessionSettingsV1() }
            .sheet(isPresented: $paywall) { DirectProView() }
            .task { pro.start(); let keys = TerminalKeyLibrary(); keys.reload(macs: library.macs) }
            .refreshable {
                library.discovery.start()
                while library.discovery.scanning && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            }
            .onChange(of: appLock.canAccess) { _, unlocked in
                if !unlocked { library.discovery.stop() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await pro.refresh() } }
                else { library.discovery.stop() }
            }
            .onDisappear { library.discovery.stop() }
            .confirmationDialog("Remove this Mac and its saved login?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove Mac", role: .destructive) { if let removing { library.remove(removing) }; removing = nil }
            }
            .onOpenURL { url in
                guard let route = RemoteSessionActivityAttributes.resumeRoute(from: url),
                      let mac = library.macs.first(where: { $0.id == route.macID }), selected == nil, terminal == nil else { return }
                open(mac, input: false, terminalMode: route.kind == .terminal)
            }
            .fullScreenCover(item: $terminal) { mac in
                DirectTerminalView(mac: mac, macLibrary: library, exit: { terminal = nil })
            }
            .fullScreenCover(item: $selected) { mac in
                DirectDesktopSessionView(mac: mac, inputOnly: inputOnly, connectionMacNames: library.macs.map(\.name), showMacs: { selected = nil })
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .opacity(appLock.canAccess ? 1 : 0)
        .allowsHitTesting(appLock.canAccess)
        .accessibilityHidden(!appLock.canAccess)
        .onAppear { appLock.install(); DirectCloudSyncV1.shared.attach(library) }
    }
    private func edit(_ mac: DirectMacRecordV1?) {
        Task {
            if !pro.ready { await pro.refresh() }
            guard mac != nil || pro.canAddMac(count: library.macs.count) else { paywall = true; return }
            editor = EditorSelection(mac: mac)
        }
    }
    private func open(_ mac: DirectMacRecordV1, input: Bool, terminalMode: Bool) {
        Task {
            if !pro.ready { await pro.refresh() }
            guard pro.canUseMac(mac.id, among: library.macs.map(\.id)) else { paywall = true; return }
            if terminalMode { terminal = mac } else { inputOnly = input; selected = mac }
        }
    }
}

struct DirectMacEditorV1: View {
    @Environment(\.dismiss) private var dismiss
    let mac: DirectMacRecordV1?
    @Bindable var library: DirectMacLibraryV1
    private struct Draft: Identifiable { let id = UUID(); var address: String }
    @State private var name: String
    @State private var usesAutomaticName: Bool
    @State private var preferredConnection: DirectMacConnection
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
    private enum SSHSheet: Identifiable {
        case keys(DirectMacRecordV1), install(DirectMacRecordV1), manual(DirectMacRecordV1), login(DirectSavedLoginService), pro
        var id: String { switch self { case .keys: "keys"; case .install: "install"; case .manual: "manual"; case .login(let service): "login-" + service.rawValue; case .pro: "pro" } }
    }
    @State private var sshSheet: SSHSheet?
    @State private var selectedKeyName = "No SSH key selected"
    @State private var selectedAccount = ""
    private func refreshSelectedKey() {
        guard let mac else { return }; let keys = TerminalKeyLibrary(); keys.reload(macs: library.macs)
        do { let key = try TerminalKeyLibraryStore.selected(mac.id); selectedKeyName = key?.name ?? "No SSH key selected"; if let key { selectedAccount = key.key.username } else { selectedAccount = try TerminalSecretStore.login(mac.id)?.username ?? "" } } catch { selectedKeyName = "Saved key unavailable" }
    }
    private var draftMac: DirectMacRecordV1? {
        guard let mac, let resolvedPort, let resolvedSSHPort else { return nil }
        return try? .normalized(id: mac.id, name: name, addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort)
    }
    @State private var addressEditMode: EditMode = .inactive
    @State private var lastAutomaticDiscoveryKey: String?
    init(mac: DirectMacRecordV1?, library: DirectMacLibraryV1) {
        self.mac = mac; self.library = library
        _name = State(initialValue: mac?.name ?? "My Mac")
        _usesAutomaticName = State(initialValue: mac?.usesAutomaticName ?? true)
        _preferredConnection = State(initialValue: mac?.preferredConnection ?? .desktop)
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
    private var detectedIdentity: DirectMacDetectedIdentity? {
        guard let resolvedPort, let resolvedSSHPort,
              let record = try? DirectMacRecordV1.normalized(name: "Mac", addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort) else { return nil }
        return DirectMacDetectedIdentity.match(record, in: library.discovery.identities)
    }
    private var sameSavedEndpoints: Bool {
        guard let mac else { return false }
        return Set(addresses.map { $0.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) == Set(mac.addresses)
            && resolvedPort == mac.port && resolvedSSHPort == mac.sshPort
    }
    private var discoveryKey: String? {
        guard let resolvedPort, let resolvedSSHPort,
              let record = try? DirectMacRecordV1.normalized(name: "Mac", addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort) else { return nil }
        return record.addresses.sorted().joined(separator: "|") + "|\(record.port)|\(record.sshPort)"
    }
    private var automaticDiscoveryKey: String? { sameSavedEndpoints ? nil : discoveryKey }
    private func startAutomaticDiscovery() {
        guard let key = automaticDiscoveryKey, key != lastAutomaticDiscoveryKey else { return }
        if library.discovery.scanning || library.discovery.start() { lastAutomaticDiscoveryKey = key }
    }
    private var detectedName: String? { detectedIdentity?.name ?? (sameSavedEndpoints ? mac?.detectedName : nil) }
    private var detectedModel: String? { detectedIdentity?.modelIdentifier ?? (sameSavedEndpoints ? mac?.modelIdentifier : nil) }
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
                if let notice = library.recovery { Section { DirectRecoveryCard(notice: notice, primary: .init(title: "Keep Editing", perform: { library.recovery = nil })) } }
                Section("Mac") {
                    TextField("Name", text: Binding(get: { name }, set: { name = $0; usesAutomaticName = false }))
                        .accessibilityIdentifier("mac-name")
                    Toggle("Use Detected Name", isOn: $usesAutomaticName)
                        .accessibilityIdentifier("mac-use-detected-name")
                    if let detectedName { LabeledContent("Detected Name", value: detectedName) }
                    LabeledContent("Mac Type") {
                        Label(detectedModel == nil ? "Not detected" : DirectMacFamily.detect(detectedModel).title,
                              systemImage: DirectMacFamily.detect(detectedModel).symbol)
                            .labelStyle(.titleAndIcon)
                    }
                    if library.discovery.scanning {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular)
                            Text("Detecting Mac details…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh Mac Details", systemImage: "arrow.clockwise") {
                        if library.discovery.start() { lastAutomaticDiscoveryKey = automaticDiscoveryKey }
                    }.disabled(discoveryKey == nil || library.discovery.scanning)
                        .accessibilityIdentifier("mac-refresh-details")
                    Text(library.discovery.unavailable
                        ? "Local discovery is unavailable. Allow Local Network access in Settings to refresh."
                        : "Details are saved. Refresh to check for changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { Text("Use a name from 1 to 80 characters, without control characters.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Picker("Open on Tap", selection: $preferredConnection) {
                        ForEach(DirectMacConnection.allCases) { connection in
                            Label(connection.title, systemImage: connection.symbol).tag(connection)
                        }
                    }.accessibilityIdentifier("mac-open-on-tap")
                } footer: {
                    Text("Choose what opens when you tap this Mac in My Macs. You can always choose another mode from its menu.")
                }
                Section {
                    ForEach($addresses) { $draft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(addresses.first?.id == draft.id ? "Preferred address" : "Fallback address").font(.caption).foregroundStyle(.secondary)
                            TextField("IP address or hostname", text: $draft.address)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        }
                    }.onDelete { addresses.remove(atOffsets: $0) }.onMove { addresses.move(fromOffsets: $0, toOffset: $1) }
                    if !valid { Text("Enter unique addresses for this Mac, a name, and valid ports before saving. An IP address or hostname goes here; enter the port under Advanced.").font(.footnote).foregroundStyle(.secondary) }
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
                        if resolvedPort == nil { Text("Use a port from 1 to 65535, or leave it blank for 5900.").font(.footnote).foregroundStyle(.secondary) }
                        Text("Leave blank to use Screen Sharing port 5900.").font(.footnote).foregroundStyle(.secondary)
                        TextField("22 (default)", text: $sshPort).keyboardType(.numberPad).accessibilityLabel("SSH Port")
                        if resolvedSSHPort == nil { Text("Use an SSH port from 1 to 65535, or leave it blank for 22.").font(.footnote).foregroundStyle(.secondary) }
                        Text("Leave SSH Port blank to use 22. Terminal requires Remote Login on your Mac.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let mac {
                    Section {
                        Label(selectedKeyName, systemImage: "key").font(.headline)
                        LabeledContent("Account", value: selectedAccount.isEmpty ? "Choose during setup" : selectedAccount)
                        Button("Choose SSH Key", systemImage: "key") { sshSheet = .keys(mac) }
                        Button {
                            guard DirectProAccess.shared.hasPro else { sshSheet = .pro; return }
                            if let draft = draftMac { sshSheet = .install(draft) }
                        } label: {
                            HStack { Label("Set Up Key on This Mac", systemImage: "key.horizontal"); Spacer(); DirectProBadge() }
                        }.disabled(!valid).accessibilityIdentifier("mac-install-ssh-key")
                        Button("Manual Key Setup", systemImage: "doc.text") { sshSheet = .manual(draftMac ?? mac) }
                    } header: { Text("Terminal Access") } footer: {
                        Text("Selecting a key doesn’t add it to the Mac. Automatic setup requires Pro or an active trial; manual setup is free. Save address changes to keep them for future connections.")
                    }
                    Section {
                        Button("Desktop Login", systemImage: "desktopcomputer") { sshSheet = .login(.desktop) }.accessibilityIdentifier("mac-edit-desktop-login")
                        Button("Terminal Password Login", systemImage: "terminal") { sshSheet = .login(.terminal) }.accessibilityIdentifier("mac-edit-terminal-login")
                    } header: { Text("Saved Logins") } footer: {
                        Text("Edit the saved account and password for each service. Changes apply to your next connection; SSH key selection is kept.")
                    }
                    Section {
                        Button("Forget Desktop Login", systemImage: "key.slash", role: .destructive) { credentialAction = .desktop }
                        Button("Forget Terminal Login", systemImage: "terminal", role: .destructive) { credentialAction = .terminal }
                        Button("Forget SSH Server Key", systemImage: "checkmark.shield", role: .destructive) { credentialAction = .serverKey }
                    } header: { Text("Reset Login & Trust") }
                    footer: { Text("Address and port edits keep saved logins. Desktop and Terminal use separate logins for \(mac.name).") }
                }
            }
            .sheet(item: $sshSheet, onDismiss: { refreshSelectedKey() }) { selection in
                switch selection {
                case .keys(let mac): TerminalKeySettings(mac: mac)
                case .install(let mac): TerminalKeyInstallView(mac: mac, changed: { refreshSelectedKey() })
                case .manual(let mac): TerminalManualKeySetupView(mac: mac)
                case .login(let service): if let mac { DirectSavedLoginEditor(mac: mac, service: service) }
                case .pro: DirectProView()
                }
            }
            .task { refreshSelectedKey() }
            .task(id: automaticDiscoveryKey) {
                guard automaticDiscoveryKey != nil else { return }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard !Task.isCancelled else { return }
                startAutomaticDiscovery()
            }
            .onChange(of: detectedName) { _, detected in if usesAutomaticName, let detected { name = detected } }
            .onChange(of: usesAutomaticName) { _, automatic in if automatic, let detectedName { name = detectedName } }
            .environment(\.editMode, $addressEditMode)
            .onChange(of: addresses.count) { _, count in
                if count < 2 { addressEditMode = .inactive }
            }
            .navigationTitle(mac == nil ? "Add Mac" : "Edit Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if mac == nil && !DirectProAccess.shared.canAddMac(count: library.macs.count) { sshSheet = .pro; return }
                        if let resolvedPort, library.save(id: mac?.id, name: name, addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort, usesAutomaticName: usesAutomaticName, preferredConnection: preferredConnection) { startAutomaticDiscovery(); dismiss() }
                    }.disabled(!valid)
                }
            }
            .confirmationDialog(credentialAction?.title ?? "Saved Login", isPresented: Binding(get: { credentialAction != nil }, set: { if !$0 { credentialAction = nil } }), titleVisibility: .visible, presenting: credentialAction) { action in
                Button(action.title, role: .destructive) {
                    guard let mac else { return }
                    do {
                        switch action {
                        case .desktop: library.forgetLogin(mac)
                        case .terminal: try TerminalSecretStore.forgetLogin(mac.id)
                        case .serverKey: try TerminalSecretStore.forgetHostKey(mac.id)
                        }
                    } catch { library.recovery = .make(.removeFailed, message: "The saved entry couldn’t be removed. Review the entry and retry; other logins are kept.") }
                    credentialAction = nil
                }
            } message: { action in Text(action.detail) }
        }
    }
}

struct DirectSessionSettingsV1: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VNCSessionActivityController.preferenceKey) private var showSession = true
    @AppStorage(CompanionVNCControlsHapticsPreference) private var controlsHaptics = true
    @State private var lock = DirectAppLockV1.shared
    @State private var cloud = DirectCloudSyncV1.shared
    @State private var enableCloud = false
    @State private var removeCloud = false
    private enum SettingsSheet: String, Identifiable { case keys, pro, desktop, terminal, trackpad; var id: String { rawValue } }
    @State private var settingsSheet: SettingsSheet?
    @Environment(DirectAppearanceV1.self) private var appearance
    var body: some View {
        NavigationStack {
            Form {
                Section("SSH & Pro") {
                    Button("SSH Keys", systemImage: "key") { settingsSheet = .keys }.accessibilityIdentifier("settings-ssh-keys")
                    Button(DirectProAccess.shared.accessTitle, systemImage: "sparkles") { settingsSheet = .pro }
                }
                Section("Controls") {
                    Button("Desktop", systemImage: "desktopcomputer") { settingsSheet = .desktop }
                    Button("Terminal", systemImage: "terminal") { settingsSheet = .terminal }
                    Button("Trackpad & Keyboard", systemImage: "rectangle.and.hand.point.up.left") { settingsSheet = .trackpad }
                }
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
                    if let notice = cloud.recovery {
                        DirectRecoveryCard(notice: notice, primary: .init(title: notice.reason == .cloudRemoval ? "Retry Removal" : "Retry", perform: { if notice.reason == .cloudRemoval { cloud.removeCloudCopies() } else { cloud.retry() } }))
                    } else { Text(cloud.status).font(.footnote).foregroundStyle(.secondary) }
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
                    Toggle("Controls Haptics", isOn: $controlsHaptics).accessibilityIdentifier("controls-haptics")
                } header: { Text("Session") } footer: {
                    Text("Dynamic Island shows Desktop or Terminal status with Resume and End actions. Terminal keeps the same shell during brief app switches; iOS may suspend networking while you’re away. Controls Haptics confirms a local menu selection.")
                }
            }
            .sheet(item: $settingsSheet) { selection in
                switch selection {
                case .keys: TerminalKeySettings(); case .pro: DirectProView()
                case .desktop: VNCInputSettings(mode: .desktop)
                case .terminal: VNCInputSettings(mode: .terminal)
                case .trackpad: VNCInputSettings(mode: .trackpad)
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

struct DirectMacListRowLabel: View {
    let mac: DirectMacRecordV1
    @ScaledMetric(relativeTo: .title2) private var hardwareIconSize = 22
    @ScaledMetric(relativeTo: .title2) private var badgeSize = 44

    private var hardwareIcon: some View {
        Image(systemName: mac.family.symbol).font(.system(size: min(hardwareIconSize, 32))).foregroundStyle(.blue)
            .frame(width: min(badgeSize, 60), height: min(badgeSize, 60))
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
    private var name: some View { Text(mac.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
    private var action: some View {
        Text(mac.preferredConnection.actionTitle).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var address: some View {
        Text(mac.addresses.count > 1 ? "\(mac.address) · \(mac.addresses.count) addresses" : mac.address)
            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        HStack(spacing: 14) {
            hardwareIcon
            VStack(alignment: .leading, spacing: 4) { name; action; address }
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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

#endif
