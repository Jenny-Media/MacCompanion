#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import Security
import SwiftUI

struct DirectMacRecordV1: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var addresses: [String]
    var port: Int
    var sshPort: Int = 22
    var usesAutomaticName = false
    var detectedName: String?
    var modelIdentifier: String?
    var preferredConnection: DirectMacConnection = .desktop
    var swipeLeft: DirectMacSwipeAction = .terminal
    var swipeRight: DirectMacSwipeAction = .trackpad
    var family: DirectMacFamily { .detect(modelIdentifier) }
    var address: String { addresses.first ?? "" }
    private enum CodingKeys: String, CodingKey { case id, name, address, addresses, port, sshPort, usesAutomaticName, detectedName, modelIdentifier, preferredConnection, swipeLeft, swipeRight }
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
        swipeLeft = try c.decodeIfPresent(DirectMacSwipeAction.self, forKey: .swipeLeft) ?? .terminal
        swipeRight = try c.decodeIfPresent(DirectMacSwipeAction.self, forKey: .swipeRight) ?? .trackpad
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(addresses, forKey: .addresses); try c.encode(port, forKey: .port); try c.encode(sshPort, forKey: .sshPort)
        try c.encode(usesAutomaticName, forKey: .usesAutomaticName)
        try c.encodeIfPresent(detectedName, forKey: .detectedName); try c.encodeIfPresent(modelIdentifier, forKey: .modelIdentifier)
        try c.encode(preferredConnection, forKey: .preferredConnection)
        try c.encode(swipeLeft, forKey: .swipeLeft); try c.encode(swipeRight, forKey: .swipeRight)
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

enum DirectAddressGuidance {
    static func issue(_ addresses: [String]) -> String? {
        let hosts = addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if hosts.isEmpty || hosts.allSatisfy(\.isEmpty) { return "Add an address for this Mac." }
        if hosts.contains(where: \.isEmpty) { return "Enter an address or remove the empty row." }
        if Set(hosts).count != hosts.count { return "Each address must be unique." }
        if (try? DirectMacRecordV1.normalized(name: "Mac", addresses: hosts)) == nil { return "Use hostnames or IP addresses, without spaces or a URL scheme." }
        return nil
    }
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
        #if os(iOS)
        return try DirectMacAccessStore.load(id).login.map { .init(username: $0.username, password: $0.password) }
        #else
        return try readLegacyChecked(id)
        #endif
    }
    @MainActor static func readLegacyChecked(_ id: UUID) throws -> Login? {
        guard DirectAppLockV1.shared.canAccess else { throw StoreFailure.unavailable }
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreFailure.unavailable }
        return try JSONDecoder().decode(Login.self, from: data)
    }
    #if os(iOS)
    @MainActor
    #endif
    static func save(_ login: Login, hostID: UUID) throws {
        #if os(iOS)
        try DirectMacAccessStore.setMacLogin(.init(username: login.username, password: login.password), id: hostID)
        return
        #endif
        let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(login),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(hostID) as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(hostID).merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw StoreFailure.unavailable }
        } else if status != errSecSuccess { throw StoreFailure.unavailable }
    }
    #if os(iOS)
    @MainActor
    #endif
    static func remove(_ id: UUID) throws {
        #if os(iOS)
        try DirectMacAccessStore.setMacLogin(nil, id: id)
        #else
        try removeLegacy(id)
        #endif
    }
    static func removeLegacy(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreFailure.unavailable }
    }
    @MainActor static func removeForMacRemoval(_ id: UUID) throws {
        #if os(iOS)
        try DirectMacAccessStore.write(.init(), id: id)
        #else
        try removeLegacy(id)
        #endif
    }
    enum StoreFailure: Error { case unavailable }
}

@MainActor @Observable final class DirectMacLibraryV1 {
    static var defaultURL: URL { DirectClientPlatformV1.dataURL("direct-macs-v1.json") }
    static let removed = Notification.Name("DirectMacLibraryRemovedV1")
    struct Removal: Sendable { let libraryURL: URL; let ids: Set<UUID> }
    private struct File: Codable, Sendable { var version = 5; var macs: [DirectMacRecordV1] }
    private(set) var macs: [DirectMacRecordV1] = []
    private(set) var readable = true
    private(set) var loading = false
    @ObservationIgnored private var initialRead: Task<[DirectMacRecordV1]?, Error>?
    @ObservationIgnored private var readGeneration = UUID()
    @ObservationIgnored private let readInitialRecords: @Sendable (URL) throws -> [DirectMacRecordV1]?
    var recovery: DirectRecoveryNotice?
    var failure: String? {
        get { recovery?.message }
        set { recovery = newValue.map { .make(.saveFailed, message: $0) } }
    }
    var localChange: ((UUID) -> Void)?
    let discovery = DirectMacDiscoveryV1()
    private let url: URL
    var storageURL: URL { url }
    private let removeLogin: @MainActor (UUID) throws -> Void
    init(url: URL? = nil, removeLogin: @escaping @MainActor (UUID) throws -> Void = DesktopCredentialStoreV1.removeForMacRemoval,
         loadInBackground: Bool = false,
         readInitialRecords: @escaping @Sendable (URL) throws -> [DirectMacRecordV1]? = { try DirectMacLibraryV1.readRecords(at: $0) }) {
        self.url = url ?? Self.defaultURL
        self.removeLogin = removeLogin; self.readInitialRecords = readInitialRecords
        if loadInBackground { loading = true; readable = false } else { reload() }
        discovery.updated = { [weak self] in
            guard let self else { return }
            self.updateDetectedMetadata(self.discovery.identities)
        }
    }
    nonisolated static func readRecords(at url: URL) throws -> [DirectMacRecordV1]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard (1...5).contains(file.version), file.macs.count <= 64,
              Set(file.macs.map(\.id)).count == file.macs.count else { throw DirectMacRecordV1.LibraryFailure.invalid }
        for mac in file.macs { _ = try mac.validated() }
        return file.version < 5 ? file.macs.sorted(by: Self.alphabetical) : file.macs
    }
    private func publishRead(_ records: [DirectMacRecordV1]?) {
        if let records { macs = records }
        readable = true; recovery = nil; loading = false
    }
    private func readFailed() {
        readable = false; loading = false
        recovery = .make(.savedDataUnavailable, message: "Saved Macs couldn’t be read. Existing data is kept. Retry when device storage is available; unreadable data won’t be replaced.")
    }
    func reload() {
        readGeneration = UUID(); initialRead?.cancel(); initialRead = nil
        do { publishRead(try Self.readRecords(at: url)) } catch { readFailed() }
    }
    /// Initial iOS metadata is prepared beneath the existing privacy cover.
    /// Mutations remain denied until the worker has produced a validated snapshot.
    func loadInitial(onLoad: () -> Void = {}) async {
        guard loading else { onLoad(); return }
        if initialRead == nil {
            let read = readInitialRecords, location = url
            initialRead = Task.detached(priority: .userInitiated) { try read(location) }
        }
        guard let task = initialRead else { return }
        let generation = readGeneration
        let result = await task.result
        guard generation == readGeneration, loading else { return }
        initialRead = nil
        switch result {
        case .success(let records): publishRead(records); onLoad()
        case .failure: readFailed()
        }
    }
    func reloadInBackground(onLoad: () -> Void = {}) async {
        if !loading { readGeneration = UUID(); loading = true; readable = false; recovery = nil }
        await loadInitial(onLoad: onLoad)
    }
    func save(id: UUID?, name: String, address: String) -> Bool { save(id: id, name: name, addresses: [address]) }
    func save(id: UUID?, name: String, addresses: [String], port: Int = 5900, sshPort: Int? = nil,
              usesAutomaticName: Bool? = nil, preferredConnection: DirectMacConnection? = nil,
              swipeLeft: DirectMacSwipeAction? = nil, swipeRight: DirectMacSwipeAction? = nil) -> Bool {
        do {
            guard readable else { return false }
            let old = macs.first { $0.id == id }
            var record = try DirectMacRecordV1.normalized(id: id ?? UUID(), name: name, addresses: addresses, port: port, sshPort: sshPort ?? old?.sshPort ?? 22)
            record.usesAutomaticName = usesAutomaticName ?? (old?.name == record.name ? old?.usesAutomaticName : false) ?? false
            record.preferredConnection = preferredConnection ?? old?.preferredConnection ?? .desktop
            record.swipeLeft = swipeLeft ?? old?.swipeLeft ?? .terminal
            record.swipeRight = swipeRight ?? old?.swipeRight ?? .trackpad
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
    #if os(iOS)
    func saveQuickConnection(_ mac: DirectMacRecordV1, connection: DirectMacConnection, pro: DirectProAccess) -> Bool {
        if macs.contains(where: { $0.id == mac.id }) { return true }
        // Login/trust may have waited while cloud sync or trial expiry changed
        // the admission checked when Quick Connect first opened.
        guard readable, pro.canAddMac(count: macs.count) else { return false }
        return save(id: mac.id, name: mac.name, addresses: mac.addresses, port: mac.port, sshPort: mac.sshPort,
            usesAutomaticName: mac.usesAutomaticName, preferredConnection: connection)
    }
    #endif
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
        #if os(iOS)
        guard !DirectMacConnections.shared.isActive(mac.id) else { recovery = .make(.removeFailed, message: "Disconnect this Mac before forgetting its login."); return }
        #endif
        do { try removeLogin(mac.id); failure = nil }
        catch { recovery = .make(.removeFailed, message: "The saved Screen Sharing login couldn’t be removed. Review it and retry.") }
    }
    func applyCloud(_ next: [DirectMacRecordV1]) throws {
        guard readable, next.count <= 64, Set(next.map(\.id)).count == next.count else { throw DirectCloudError.invalid }
        try next.forEach { _ = try $0.validated() }
        let records = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let existingIDs = Set(macs.map(\.id))
        let ordered = macs.compactMap { records[$0.id] } + next.filter { !existingIDs.contains($0.id) }.sorted(by: Self.alphabetical)
        if ordered != macs { try write(ordered) }
    }
    nonisolated private static func alphabetical(_ lhs: DirectMacRecordV1, _ rhs: DirectMacRecordV1) -> Bool {
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
        let removedIDs = Set(macs.map(\.id)).subtracting(next.map(\.id))
        macs = next; failure = nil
        if !removedIDs.isEmpty {
            NotificationCenter.default.post(name: Self.removed, object: Removal(libraryURL: url.standardizedFileURL, ids: removedIDs))
        }
    }
}

/// Owner-scoped cancellation, delivered synchronously after library persistence.
/// Hidden sheets and pending handshakes are retired before they can save a login.
final class DirectMacRemovalObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    @MainActor init(macID: UUID, libraryURL: URL, removed: @escaping @MainActor () -> Void) {
        let url = libraryURL.standardizedFileURL
        token = NotificationCenter.default.addObserver(forName: DirectMacLibraryV1.removed, object: nil, queue: .main) { notification in
            guard let event = notification.object as? DirectMacLibraryV1.Removal,
                  event.libraryURL == url, event.ids.contains(macID) else { return }
            MainActor.assumeIsolated { removed() }
        }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Carry the chosen mode with the Mac into the presentation. Separate state for
/// the mode can be captured at its initial value on the first full-screen cover.
struct DirectMacSessionSelection: Identifiable {
    let id = UUID()
    let mac: DirectMacRecordV1
    let connection: DirectMacConnection
    var autoConnect = true
    var saveAfterConnect = false
    var temporary = false
}

#if os(iOS)
struct DirectMacLibraryRootV1: View {
    @State private var library: DirectMacLibraryV1
    init(library: DirectMacLibraryV1 = DirectMacLibraryV1(loadInBackground: true), appLock: DirectAppLockV1 = .shared,
         pro: DirectProAccess = .shared, accessTimeout: Duration = .seconds(5)) {
        _library = State(initialValue: library); _appLock = State(initialValue: appLock)
        _pro = State(initialValue: pro); self.accessTimeout = accessTimeout
    }
    private let accessTimeout: Duration
    private enum LibraryAction {
        case edit(DirectMacRecordV1?)
        case open(DirectMacRecordV1, DirectMacConnection, Bool)
        case connect(DirectQuickConnectRequest)
    }
    private struct PendingAccess { let id = UUID(); let action: LibraryAction }
    @State private var pendingAccess: PendingAccess?
    @State private var deferredRoute: LibraryAction?
    @State private var loadingRoute: URL?
    @State private var servicesAttached = false
    @State private var accessTimedOut = false
    @State private var accessDeadline: Task<Void, Never>?

    @State private var connectionPanel = DirectConnectionPanelHost()
    @State private var quickConnect = false
    @State private var files: DirectMacRecordV1?
    @State private var session: DirectMacSessionSelection?
    @State private var appLock = DirectAppLockV1.shared
    private struct EditorSelection: Identifiable { let id = UUID(); let mac: DirectMacRecordV1? }
    @State private var editor: EditorSelection?
    @State private var removing: DirectMacRecordV1?
    @State private var setup = false
    @State private var settings = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var editMode: EditMode = .inactive
    @State private var pro = DirectProAccess.shared
    @State private var paywall = false
    @Environment(\.scenePhase) private var scenePhase
    private var visibleMacs: [DirectMacRecordV1] {
        library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.addresses.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        ZStack {
        NavigationStack {
            DirectMacDiscoveryList(refresh: refreshNearbyMacs) {
                let downloads = DirectFilesWorkspace.recoverableDownloads(libraryURL: library.storageURL)
                if !downloads.isEmpty {
                    Section("Downloads from Other Macs") {
                        ForEach(downloads, id: \.mac.id) { owner in
                            Button("Save Downloads from " + owner.mac.name, systemImage: "folder.badge.questionmark") { files = owner.mac }
                                .accessibilityIdentifier("recover-downloads-" + owner.mac.id.uuidString)
                        }
                    }
                }

                if let pendingAccess, !quickConnect {
                    Section {
                        if accessTimedOut {
                            Text("Purchases couldn’t be checked. Try again when the App Store is available.")
                                .accessibilityIdentifier("mac-access-timeout")
                            Button("Retry") {
                                request(pendingAccess.action)
                                if !pro.ready { Task { await pro.refresh() } }
                            }.accessibilityIdentifier("mac-access-retry")
                        } else {
                            HStack { ProgressView(); Text("Checking purchases…") }
                                .accessibilityIdentifier("mac-access-progress")
                        }
                        Button("Cancel") { cancelAccess() }.accessibilityIdentifier("mac-access-cancel")
                    }
                }
                if let notice = library.recovery {
                    Section { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry", perform: { Task { await library.reloadInBackground(onLoad: { attachLoadedServices() }) } }), secondary: .init(title: "Help", perform: { setup = true })) }
                }
                if library.loading {
                    Section { HStack { ProgressView(); Text("Loading saved Macs…") }.accessibilityIdentifier("mac-library-loading") }
                } else if !library.readable {
                    Section { Text("Saved Macs are unavailable. Adding and editing are paused to protect the existing file.").foregroundStyle(.secondary) }
                } else if library.macs.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "desktopcomputer").font(.system(size: 48)).foregroundStyle(.blue)
                            Text("Your Macs, within reach").font(.title3.bold())
                            Text("Add a Mac on your local network or private VPN. The setup guide shows which services to enable.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Add your first Mac", systemImage: "plus") { beginQuickConnect() }
                                .buttonStyle(.borderedProminent).disabled(!library.readable)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                } else {
                    Section {
                        ForEach(visibleMacs) { mac in
                            DirectMacLibraryRow(mac: mac, reordering: editMode.isEditing,
                                canChooseFreeMac: !pro.hasPro,
                                open: { open(mac, connection: $0) }, browseFiles: { files = mac },
                                edit: { edit(mac) }, remove: { removing = mac },
                                chooseFreeMac: { pro.chooseFreeMac(mac.id) })
                        }.onMove { offsets, destination in
                            guard search.isEmpty else { return }
                            if let first = library.macs.first { _ = pro.canUseMac(first.id, among: library.macs.map(\.id)) }
                            library.move(fromOffsets: offsets, toOffset: destination)
                        }.moveDisabled(!search.isEmpty)
                        if visibleMacs.isEmpty { Text("No matching Macs").foregroundStyle(.secondary) }
                    } footer: { if editMode.isEditing { Text("Drag to reorder your Macs.") } }
                }
            }
            .navigationTitle("My Macs")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a Mac", text: $search).focused($searchFocused)
                            .submitLabel(.search).onSubmit { searchFocused = false }.accessibilityIdentifier("macs-search")
                        if !search.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }.labelStyle(.iconOnly) }
                    }.padding(14).glassEffect(in: .capsule)
                    if searchFocused {
                        Button("Done") { searchFocused = false }
                            .font(.body.weight(.semibold)).padding(.horizontal, 16).frame(minWidth: 52, minHeight: 52)
                            .glassEffect(.regular.interactive(), in: .capsule).accessibilityIdentifier("macs-search-done")
                    } else {
                        Button("Add Mac", systemImage: "plus") { beginQuickConnect() }.labelStyle(.iconOnly)
                            .font(.title2).frame(width: 52, height: 52).glassEffect(.regular.interactive(), in: .circle)
                            .disabled(!library.readable).accessibilityIdentifier("macs-add")
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            .onChange(of: search) { _, value in if !value.isEmpty { editMode = .inactive } }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.readable && library.macs.count > 1 {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }.disabled(!search.isEmpty).accessibilityIdentifier("macs-edit-order")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { settings = true }
                        .accessibilityIdentifier("open-app-settings")
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $files) { mac in DirectFilesView(mac: mac, session: DirectFilesWorkspace.session(mac, libraryURL: library.storageURL), retainWhenDismissed: true) }
            .sheet(item: $editor) { selection in DirectMacEditorV1(mac: selection.mac, library: library) }
            .sheet(isPresented: $setup) { DirectMacSetupV1() }
            .sheet(isPresented: $settings) { DirectSessionSettingsV1() }
            .sheet(isPresented: $paywall) { DirectProView() }
            .task {
                pro.start()
                appLock.unlockTimings.libraryWaitStarted()
                await library.loadInitial(onLoad: {
                    // Bind cloud change tracking in this same actor turn, before
                    // the newly loaded list can accept a user edit or deletion.
                    attachLoadedServices()
                })
                appLock.unlockTimings.libraryWaitFinished(readable: library.readable)
                guard !Task.isCancelled else { return }
                attachLoadedServices()
            }
            .onChange(of: library.loading) { _, loading in
                updateTemporaryCleanup()
                if !loading, library.readable {
                    attachLoadedServices()
                    if let route = loadingRoute { loadingRoute = nil; openRoute(route) }
                }
            }
            .onChange(of: appLock.canAccess) { _, unlocked in
                if !unlocked { library.discovery.stop(); cancelAccess(); deferredRoute = nil; loadingRoute = nil }
                else { updateTemporaryCleanup() }
            }
            .onChange(of: appLock.canInteract) { _, admitted in
                if !admitted { cancelAccess() }
            }
            .onChange(of: appLock.canResumeRemoteSession) { _, ready in
                if ready, let route = deferredRoute { deferredRoute = nil; request(route) }
            }
            .onChange(of: pro.ready) { _, ready in if ready { completePendingAccess() } }
            .onChange(of: library.macs.map(\.id)) { _, ids in
                updateTemporaryCleanup()
                guard let pending = pendingAccess else { return }
                if case .open(let mac, _, _) = pending.action, !ids.contains(mac.id) { cancelAccess() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    updateTemporaryCleanup()
                    if pro.ready { Task { await pro.refresh() } } else { pro.start() }
                } else {
                    library.discovery.stop(); cancelAccess()
                    if phase == .background { deferredRoute = nil; loadingRoute = nil }
                }
            }
            .onDisappear { library.discovery.stop(); cancelAccess(); deferredRoute = nil; loadingRoute = nil }
            .confirmationDialog("Remove this Mac and its saved login?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove Mac", role: .destructive) { if let removing { library.remove(removing) }; removing = nil }
            } message: {
                Text("Related sessions will close and transfers will stop. Unsaved downloads stay available until you save or discard them.")
            }

        }
            .accessibilityHidden(session != nil || !appLock.canInteract)
            .allowsHitTesting(session == nil && appLock.canInteract)
            .background(DirectConnectionPanelAnchor(host: connectionPanel).frame(width: 0, height: 0))
            Group {
                if quickConnect && session == nil {
                    DirectConnectionPanelContent(host: connectionPanel, cancel: cancelQuickConnect) {
                        DirectQuickConnectView(library: library, panel: connectionPanel,
                            checkingPurchases: pendingAccess != nil, timedOut: accessTimedOut,
                            retry: { if let pendingAccess { request(pendingAccess.action); if !pro.ready { Task { await pro.refresh() } } } },
                            cancel: cancelQuickConnect, connect: { request(.connect($0)) })
                    }
                }
                if let selection = session {
                    switch selection.connection {
                    case .terminal:
                        DirectTerminalView(mac: selection.mac, macLibrary: library, autoConnect: selection.autoConnect,
                            connectionPanel: connectionPanel, loginRetentionAllowed: !selection.temporary || selection.saveAfterConnect,
                            connectionEstablished: { saveConnectedMac(selection) }, exit: { endSession(selection) })
                    case .desktop, .trackpad:
                        DirectDesktopSessionView(mac: selection.mac, inputOnly: selection.connection.inputOnly,
                            connectionMacNames: library.macs.map(\.name), libraryURL: library.storageURL,
                            connectionPanel: connectionPanel, loginRetentionAllowed: !selection.temporary || selection.saveAfterConnect,
                            connectionEstablished: { saveConnectedMac(selection) }, showMacs: { endSession(selection) })
                            .ignoresSafeArea(.container, edges: .bottom)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!appLock.canInteract)
        }
        #if DEBUG
        .background(DirectUnlockFrameProbe(lock: appLock, token: appLock.unlockTimingToken, phase: .libraryDisplayTick,
            enabled: session == nil && !settings && editor == nil && files == nil && !setup && !paywall))
        #endif
        .opacity(appLock.contentVisible ? 1 : 0)
        .allowsHitTesting(appLock.canInteract)
        .onAppear { appLock.install(); updateTemporaryCleanup() }
        .onOpenURL { openRoute($0) }
        .onReceive(NotificationCenter.default.publisher(for: DirectMacConnections.changed)) { _ in
            DirectTemporaryMacCleanup.shared.retry()
        }
    }
    private func beginQuickConnect() { searchFocused = false; quickConnect = true }
    private func cancelQuickConnect() { quickConnect = false; library.discovery.stop(); cancelAccess(); deferredRoute = nil }
    private func saveConnectedMac(_ selection: DirectMacSessionSelection) -> Bool {
        guard session?.id == selection.id else { return false }
        if library.macs.contains(where: { $0.id == selection.mac.id }) { return true }
        guard selection.saveAfterConnect, library.readable else { return false }
        return library.saveQuickConnection(selection.mac, connection: selection.connection, pro: pro)
    }
    private func endSession(_ selection: DirectMacSessionSelection) {
        guard session?.id == selection.id else { return }
        connectionPanel.close(); session = nil; quickConnect = false
        guard selection.temporary, !library.macs.contains(where: { $0.id == selection.mac.id }) else { return }
        DirectFilesWorkspace.endTemporarySession(selection.mac.id, libraryURL: library.storageURL)
        DirectTemporaryMacCleanup.shared.end(selection.mac.id)
    }
    private func refreshNearbyMacs() async {
        guard library.readable else { return }
        library.discovery.start()
        while library.discovery.scanning && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
    }
    private func updateTemporaryCleanup() {
        DirectTemporaryMacCleanup.shared.updateSavedMacs(library.readable && !library.loading ? Set(library.macs.map(\.id)) : nil)
    }
    private func attachLoadedServices() {
        updateTemporaryCleanup()
        guard library.readable, !library.loading, !servicesAttached else { return }
        servicesAttached = true
        let keys = TerminalKeyLibrary(); keys.reload(macs: library.macs)
        DirectCloudSyncV1.shared.attach(library)
    }
    private func openRoute(_ url: URL) {
        guard let route = RemoteSessionActivityAttributes.resumeRoute(from: url) else { return }
        if library.loading { loadingRoute = url; return }
        guard let mac = library.macs.first(where: { $0.id == route.macID }), session == nil else { return }
        request(.open(mac, route.kind == .terminal ? .terminal : .desktop, route.automaticallyConnect), deferUntilActive: true)
    }
    private func edit(_ mac: DirectMacRecordV1?) { request(.edit(mac)) }
    private func open(_ mac: DirectMacRecordV1, connection: DirectMacConnection, autoConnect: Bool = true) {
        request(.open(mac, connection, autoConnect))
    }
    private func cancelAccess() {
        accessDeadline?.cancel(); accessDeadline = nil; pendingAccess = nil; accessTimedOut = false
    }
    private func admits(_ action: LibraryAction) -> Bool {
        switch action {
        case .edit: appLock.canInteract
        case .open, .connect: appLock.canResumeRemoteSession
        }
    }
    private func request(_ action: LibraryAction, deferUntilActive: Bool = false) {
        cancelAccess(); deferredRoute = nil; searchFocused = false
        guard appLock.canInteract else { if deferUntilActive { deferredRoute = action }; return }
        // Accept a local tap during the successful-authentication handoff, but
        // start its remote session only after the real activation event.
        guard admits(action) else { deferredRoute = action; return }
        if performIfResolved(action) { return }
        let pending = PendingAccess(action: action); pendingAccess = pending; pro.start()
        accessDeadline = Task { @MainActor in
            do { try await Task.sleep(for: accessTimeout) } catch { return }
            guard !Task.isCancelled, pendingAccess?.id == pending.id, admits(pending.action) else { return }
            if pro.ready { completePendingAccess() } else { accessTimedOut = true }
        }
    }
    private func completePendingAccess() {
        guard let pending = pendingAccess, !accessTimedOut, admits(pending.action) else { return }
        if performIfResolved(pending.action) { cancelAccess() }
    }
    // Free actions are safe before purchase readiness. A paid denial is safe only
    // after the current verified lookup has published its result.
    private func performIfResolved(_ action: LibraryAction) -> Bool {
        guard admits(action) else { return false }
        guard session == nil else { return true }
        switch action {
        case .edit(let mac):
            guard library.readable else { return true }
            if let mac {
                guard let current = library.macs.first(where: { $0.id == mac.id }) else { return true }
                editor = EditorSelection(mac: current); return true
            }
            if pro.canAddMac(count: library.macs.count) { editor = EditorSelection(mac: nil); return true }
            guard pro.ready else { return false }
            paywall = true
        case .connect(let proposal):
            guard library.readable, session == nil else { return true }
            if let current = library.macs.first(where: { $0.id == proposal.mac.id }) {
                return performIfResolved(.open(current, proposal.connection, true))
            }
            if pro.canAddMac(count: library.macs.count) {
                library.discovery.stop(); quickConnect = false
                CompanionVNCPlayInterfaceFeedback("open")
                DirectTemporaryMacCleanup.shared.begin(proposal.mac.id)
                session = DirectMacSessionSelection(mac: proposal.mac, connection: proposal.connection,
                    saveAfterConnect: proposal.saveMac, temporary: true)
                return true
            }
            guard pro.ready else { return false }
            connectionPanel.presentSecondary(UIHostingController(rootView: DirectProView().directAppearance()))
        case .open(let mac, let connection, let autoConnect):
            guard let current = library.macs.first(where: { $0.id == mac.id }) else { return true }
            if pro.canUseMac(mac.id, among: library.macs.map(\.id)) {
                CompanionVNCPlayInterfaceFeedback("open")
                quickConnect = false; library.discovery.stop()
                session = DirectMacSessionSelection(mac: current, connection: connection, autoConnect: autoConnect); return true
            }
            guard pro.ready else { return false }
            if quickConnect { connectionPanel.presentSecondary(UIHostingController(rootView: DirectProView().directAppearance())) }
            else { paywall = true }
        }
        return true
    }

}

struct DirectMacEditorV1: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let mac: DirectMacRecordV1?
    @Bindable var library: DirectMacLibraryV1
    private struct Draft: Identifiable { let id = UUID(); var address: String }
    @State private var name: String
    @State private var usesAutomaticName: Bool
    @State private var preferredConnection: DirectMacConnection
    @State private var swipeLeft: DirectMacSwipeAction
    @State private var swipeRight: DirectMacSwipeAction
    @State private var desktopSize: Int
    @State private var credentialAction: CredentialAction?
    private enum CredentialAction: String, Identifiable {
        case desktop, terminal, serverKey
        var id: String { rawValue }
        var title: String { switch self { case .desktop: "Forget Screen Sharing Login"; case .terminal: "Forget Terminal Login"; case .serverKey: "Forget SSH Server Key" } }
        var detail: String { self == .serverKey ? "You will need to verify the server fingerprint the next time you connect in any mode." : "You will need to enter this Mac’s login the next time you connect. The other login is kept." }
    }
    @State private var addresses: [Draft]
    @State private var port: String
    @State private var sshPort: String
    @State private var advanced = false
    private enum SSHSheet: Identifiable {
        case keys(DirectMacRecordV1), install(DirectMacRecordV1), manual(DirectMacRecordV1), login(DirectSavedLoginService), pro, shortcuts
        var id: String { switch self { case .keys: "keys"; case .install: "install"; case .manual: "manual"; case .login(let service): "login-" + service.rawValue; case .pro: "pro"; case .shortcuts: "shortcuts" } }
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
    @State private var addressEdited = false
    private var addressIssue: String? { DirectAddressGuidance.issue(addresses.map(\.address)) }
    @State private var lastAutomaticDiscoveryKey: String?
    init(mac: DirectMacRecordV1?, library: DirectMacLibraryV1) {
        self.mac = mac; self.library = library
        _name = State(initialValue: mac?.name ?? "My Mac")
        _usesAutomaticName = State(initialValue: mac?.usesAutomaticName ?? true)
        _preferredConnection = State(initialValue: mac?.preferredConnection ?? .desktop)
        _swipeLeft = State(initialValue: mac?.swipeLeft ?? .terminal)
        _swipeRight = State(initialValue: mac?.swipeRight ?? .trackpad)
        _desktopSize = State(initialValue: mac.map { VNCSessionPreferences.desktopSize($0.id) } ?? 2)
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
                Section {
                    ForEach($addresses) { $draft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(addresses.first?.id == draft.id ? "Preferred address" : "Fallback address").font(.caption).foregroundStyle(.secondary)
                            TextField("IP address or hostname", text: $draft.address)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        }
                    }.onDelete { addresses.remove(atOffsets: $0) }.onMove { addresses.move(fromOffsets: $0, toOffset: $1) }
                    if addressEdited, let issue = addressIssue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
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
                        Text("Tried from top to bottom. Use local or private VPN addresses for the same Mac.")
                        if let sharedNames { Label("Also used by \(sharedNames). Each saved Mac keeps its own login.", systemImage: "info.circle") }
                    }
                }
                Section("Mac") {
                    TextField("Name", text: Binding(get: { name }, set: { name = $0; usesAutomaticName = false }))
                        .accessibilityIdentifier("mac-name")
                    Toggle("Use Detected Name", isOn: $usesAutomaticName).accessibilityIdentifier("mac-use-detected-name")
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                        Text("Use a name from 1 to 80 characters, without control characters.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                DirectMacShortcutsSection { sshSheet = .shortcuts }
                DirectDesktopDisplaySection(selection: $desktopSize)
                if discoveryKey != nil {
                    Section {
                        DisclosureGroup("Mac Details") {
                            DirectMacDetailsContent(name: detectedName, model: detectedModel,
                                scanning: library.discovery.scanning, unavailable: library.discovery.unavailable) {
                                if library.discovery.start() { lastAutomaticDiscoveryKey = automaticDiscoveryKey }
                            }
                        }
                    }
                }
                Section {
                    DisclosureGroup("Service Ports", isExpanded: $advanced) {
                        DirectServicePortField(title: "Screen Sharing", defaultPort: "5900", value: $port, identifier: "mac-port")
                        if resolvedPort == nil { Text("Use a port from 1 to 65535, or leave it blank for 5900.").font(.footnote).foregroundStyle(.secondary) }
                        DirectServicePortField(title: "Remote Login (SSH)", defaultPort: "22", value: $sshPort, identifier: "mac-ssh-port")
                        if resolvedSSHPort == nil { Text("Use an SSH port from 1 to 65535, or leave it blank for 22.").font(.footnote).foregroundStyle(.secondary) }
                        Text("Default ports: Screen Sharing 5900 · SSH 22.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let mac {
                    Section {
                        Label(selectedKeyName, systemImage: "key").font(.headline)
                        LabeledContent("Account", value: selectedAccount.isEmpty ? "Choose during setup" : selectedAccount)
                        Button("Saved Login", systemImage: "person.badge.key") { sshSheet = .login(.desktop) }
                        Button {
                            guard DirectProAccess.shared.hasPro else { sshSheet = .pro; return }
                            if let draft = draftMac { sshSheet = .install(draft) }
                        } label: {
                            HStack { Label("Set Up Key on This Mac", systemImage: "key.horizontal"); Spacer(); DirectProBadge() }
                        }.disabled(!valid).accessibilityIdentifier("mac-install-ssh-key")
                        Button("Manual Key Setup", systemImage: "doc.text") { sshSheet = .manual(draftMac ?? mac) }
                    } header: { Text("Saved Login") } footer: {
                        Text("Choose how to sign in to this Mac, or set up an SSH key for Terminal.")
                    }
                    Section {
                        Button("Forget SSH Server Key", systemImage: "checkmark.shield", role: .destructive) { credentialAction = .serverKey }.disabled(DirectMacConnections.shared.isActive(mac.id))
                    } header: { Text("Reset Login & Trust") }
                    footer: { Text("Login and trust changes require disconnecting this Mac. Address and port edits keep its saved login.") }
                }
            }
            .accessibilityIdentifier("mac-editor-form")
            .sheet(item: $sshSheet, onDismiss: { refreshSelectedKey() }) { selection in
                switch selection {
                case .shortcuts:
                    DirectMacShortcutsSheet(macName: name, family: mac?.family ?? .unknown,
                                            tap: $preferredConnection, swipeLeft: $swipeLeft, swipeRight: $swipeRight)
                        .dynamicTypeSize(dynamicTypeSize)
                case .keys(let mac): TerminalKeySettings(mac: mac)
                case .install(let mac): TerminalKeyInstallView(mac: mac, changed: { refreshSelectedKey() })
                case .manual(let mac): TerminalManualKeySetupView(mac: mac)
                case .login: if let mac { DirectMacAccessView(mac: mac) }
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
            .onChange(of: addresses.map(\.address)) { _, _ in addressEdited = true }
            .onChange(of: addresses.count) { _, count in
                if count < 2 { addressEditMode = .inactive }
            }
            .navigationTitle(mac == nil ? "Add Mac" : "Edit Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if mac == nil && !DirectProAccess.shared.canAddMac(count: library.macs.count) { sshSheet = .pro; return }
                        if let resolvedPort, library.save(id: mac?.id, name: name, addresses: addresses.map(\.address), port: resolvedPort, sshPort: resolvedSSHPort, usesAutomaticName: usesAutomaticName, preferredConnection: preferredConnection, swipeLeft: swipeLeft, swipeRight: swipeRight) {
                            if let id = mac?.id ?? library.macs.last?.id { VNCSessionPreferences.setDesktopSize(desktopSize, mac: id) }
                            CompanionVNCPlayInterfaceFeedback("success"); startAutomaticDiscovery(); dismiss()
                        }
                        else { CompanionVNCPlayInterfaceFeedback("error") }
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
    private enum SettingsSheet: String, Identifiable { case pro, desktop, terminal, trackpad, help; var id: String { rawValue } }
    @State private var settingsSheet: SettingsSheet?
    @Environment(DirectAppearanceV1.self) private var appearance
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { general.navigationTitle("Appearance") } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                        .accessibilityIdentifier("settings-appearance")
                    NavigationLink { controls.navigationTitle("Controls") } label: { Label("Controls", systemImage: "slider.horizontal.3") }
                    NavigationLink { TerminalKeySettings(embedded: true) } label: { Label("SSH Keys", systemImage: "key") }.accessibilityIdentifier("settings-ssh-keys")
                    NavigationLink { sync.navigationTitle("Sync & Security") } label: { Label("Sync & Security", systemImage: "lock.shield") }
                        .accessibilityIdentifier("settings-sync")
                }
                Section("Pro") {
                    Button { settingsSheet = .pro } label: { DirectSettingsRow(title: DirectProAccess.shared.accessTitle, symbol: "sparkles") }
                        .accessibilityIdentifier("settings-pro")
                }
                Section("Help") {
                    Button { settingsSheet = .help } label: { DirectSettingsRow(title: "Set Up Your Mac", symbol: "questionmark.circle") }
                    #if os(iOS)
                    NavigationLink { DirectGestureGuide() } label: { Label("Gesture Guide", systemImage: "hand.draw") }
                        .accessibilityIdentifier("settings-gesture-guide")
                    #endif
                }
            }
            .sheet(item: $settingsSheet) { selection in
                Group {
                    switch selection {
                    case .pro: DirectProView()
                    case .desktop: VNCInputSettings(mode: .desktop)
                    case .terminal: VNCInputSettings(mode: .terminal)
                    case .trackpad: VNCInputSettings(mode: .trackpad)
                    case .help: DirectMacSetupGuide()
                    }
                }.directAppearance()
            }
            .navigationTitle("App Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.directAppearance()
    }
    private var general: some View {
        Form {
            Section("Appearance") {
                Picker("App Appearance", selection: Binding(get: { appearance.app }, set: { appearance.app = $0 })) {
                    ForEach(DirectAppAppearance.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("app-appearance")
                Picker("Terminal Colors", selection: Binding(get: { appearance.terminal }, set: { appearance.terminal = $0 })) {
                    ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("terminal-appearance")
            }
        }.navigationBarTitleDisplayMode(.inline)
    }
    private var controls: some View {
        Form {
            Section("Controls") {
                control("Screen Sharing", symbol: "desktopcomputer", sheet: .desktop)
                control("Terminal", symbol: "terminal", sheet: .terminal)
                control("Trackpad & Keyboard", symbol: "rectangle.and.hand.point.up.left", sheet: .trackpad)
            }
            Section {
                Toggle("Show session in Dynamic Island", isOn: $showSession).accessibilityIdentifier("session-live-activity")
                Toggle("Interface Haptics", isOn: $controlsHaptics).accessibilityIdentifier("controls-haptics")
            } header: { Text("This Device") } footer: { Text("Dynamic Island shows session status with Resume and End actions. Interface haptics confirm gestures, opening modes and explicit session actions. Trackpad haptics are controlled separately.") }
        }.navigationBarTitleDisplayMode(.inline)
    }
    private var sync: some View {
        DirectSyncSecurityForm().navigationBarTitleDisplayMode(.inline)
    }
    private func control(_ title: String, symbol: String, sheet: SettingsSheet) -> some View {
        Button { settingsSheet = sheet } label: { DirectSettingsRow(title: title, symbol: symbol) }
    }
}

struct DirectMacListRowLabel: View {
    let mac: DirectMacRecordV1
    let connectionSummary: String
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
        Label {
            Text(connectionSummary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: mac.preferredConnection == .desktop ? "display" : mac.preferredConnection.symbol)
                .accessibilityHidden(true)
        }.labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
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
    var body: some View { DirectMacSetupGuide() }
}
#endif

#endif
