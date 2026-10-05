#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import Security
import UIKit

struct DirectCloudPreferences: Codable, Equatable {
    var speed: Double
    var display: UInt32?
    var fullscreen: Bool
    var trackpad: Bool
    var followCursor: Bool
    @MainActor init(mac: UUID) {
        speed = VNCSessionPreferences.speed(mac); display = VNCSessionPreferences.display(mac)?.uint32Value
        fullscreen = VNCSessionPreferences.fullscreen(mac); trackpad = VNCSessionPreferences.trackpad(mac); followCursor = VNCSessionPreferences.followCursor(mac)
    }
    @MainActor func apply(mac: UUID) {
        VNCSessionPreferences.setSpeed(speed, mac: mac); VNCSessionPreferences.setDisplay(display.map(NSNumber.init(value:)), mac: mac)
        VNCSessionPreferences.setFullscreen(fullscreen, mac: mac); VNCSessionPreferences.setTrackpad(trackpad, mac: mac); VNCSessionPreferences.setFollowCursor(followCursor, mac: mac)
    }
}

/// A deletion is data, not a missing item, so an offline device cannot resurrect it.
struct DirectCloudVersion: Codable, Equatable {
    var schema = 1
    var id: UUID
    var writer: UUID
    var revision: Int64
    var mac: DirectMacRecordV1?
    var preferences: DirectCloudPreferences?
    var account: String { writer.uuidString.lowercased() + "." + id.uuidString.lowercased() }
    func validate() throws {
        guard schema == 1, (1...1_000_000_000).contains(revision), (mac == nil) == (preferences == nil) else { throw DirectCloudError.invalid }
        if let mac, let preferences {
            guard mac.id == id, try DirectMacRecordV1.normalized(id: id, name: mac.name, addresses: mac.addresses, port: mac.port, sshPort: mac.sshPort) == mac,
                  preferences.speed.isFinite, (0.5...3).contains(preferences.speed) else { throw DirectCloudError.invalid }
        }
    }
    func newer(than other: Self) -> Bool { revision == other.revision ? writer.uuidString > other.writer.uuidString : revision > other.revision }
    static func merge(_ local: [Self], _ remote: [Self]) throws -> [Self] {
        guard local.count <= 512, remote.count <= 512 else { throw DirectCloudError.invalid }
        for batch in [local, remote] {
            guard Set(batch.map(\.account)).count == batch.count else { throw DirectCloudError.invalid }
            try batch.forEach { try $0.validate() }
        }
        var result = Dictionary(uniqueKeysWithValues: local.map { ($0.account, $0) })
        for value in remote {
            if let old = result[value.account], old.revision >= value.revision { continue }
            result[value.account] = value
        }
        guard result.count <= 512 else { throw DirectCloudError.invalid }
        return result.values.sorted { $0.account < $1.account }
    }
    static func winners(_ versions: [Self]) -> [UUID: Self] {
        versions.reduce(into: [:]) { result, value in
            if let old = result[value.id], !value.newer(than: old) { return }; result[value.id] = value
        }
    }
}
enum DirectCloudError: Error { case invalid, storage, locked }

protocol DirectCloudTransport: Sendable {
    func read() throws -> [Data]
    func write(_ data: Data, account: String) throws
    func removeAll() throws
}

/// No new Apple container or access group. This separate service never reads local secrets.
struct DirectCloudKeychain: DirectCloudTransport {
    static let service = "media.jenny.maccompanion.cloud-library.v1"
    private let serviceName: String
    init(service: String = Self.service) { serviceName = service }
    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrSynchronizable as String: true]
    }
    func read() throws -> [Data] {
        var q = query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let values = result as? [Data], values.count <= 512, values.allSatisfy({ $0.count <= 4096 }) else { throw DirectCloudError.storage }
        return values
    }
    func write(_ data: Data, account: String) throws {
        guard data.count <= 4096 else { throw DirectCloudError.invalid }
        var q = query(); q[kSecAttrAccount as String] = account
        let fields: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
        let status = SecItemUpdate(q as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw DirectCloudError.storage }
        } else if status != errSecSuccess { throw DirectCloudError.storage }
    }
    func removeAll() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DirectCloudError.storage }
    }
}

@MainActor @Observable final class DirectCloudSyncV1 {
    static let shared = DirectCloudSyncV1()
    static let enabledKey = "direct-cloud-library-enabled-v1"
    static let preferenceChanged = Notification.Name("DirectCloudLocalPreferencesChangedV1")
    static let disclosure = "Sync sends saved Mac names, local and VPN addresses, ports, and display/input settings to iCloud Keychain on devices using your Apple Account. These details can reveal your machines and network. Privacy relies on Apple’s iCloud Keychain security, your Apple Account and trusted devices. Mac Companion adds no separate cloud password. Passwords, SSH private keys, trusted server keys, saved text and custom actions are excluded. Enable Passwords & Keychain in iCloud settings on each device. Turning this off stops app sync but does not delete existing cloud copies."
    private struct Journal: Codable { var schema = 1; var versions: [DirectCloudVersion] }
    private let defaults: UserDefaults
    private let url: URL
    private let transport: any DirectCloudTransport
    private let writer: UUID
    private var versions: [DirectCloudVersion] = []
    private var readable = true
    private weak var library: DirectMacLibraryV1?
    private var applying = false
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var status = "Off. Saved Macs stay on this device."
    init(defaults: UserDefaults = .standard, url: URL? = nil, transport: any DirectCloudTransport = DirectCloudKeychain(), writerID: UUID? = nil) {
        self.defaults = defaults; self.url = url ?? URL.applicationSupportDirectory.appending(path: "direct-cloud-journal-v1.json"); self.transport = transport
        // A restored backup must get a new writer, or two phones could overwrite one another.
        let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        var identityReadable = true
        var resolvedWriter = writerID ?? UUID()
        if writerID == nil {
            do {
                if let bytes = try TerminalSecretStore.read(identity, kind: "sync-writer") {
                    guard let text = String(data: bytes, encoding: .utf8), let id = UUID(uuidString: text) else { throw DirectCloudError.storage }
                    resolvedWriter = id
                } else { try TerminalSecretStore.write(Data(resolvedWriter.uuidString.utf8), id: identity, kind: "sync-writer") }
            } catch { identityReadable = false }
        }
        writer = resolvedWriter
        enabled = defaults.bool(forKey: Self.enabledKey)
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let file = try FileHandle(forReadingFrom: self.url); defer { try? file.close() }
                let data = try file.read(upToCount: 2_097_153) ?? Data(); guard data.count <= 2_097_152 else { throw DirectCloudError.invalid }
                let journal = try JSONDecoder().decode(Journal.self, from: data)
                guard journal.schema == 1 else { throw DirectCloudError.invalid }
                versions = try DirectCloudVersion.merge([], journal.versions)
            }
        } catch { readable = false; status = "Sync history could not be read. Existing data was preserved." }
        if !identityReadable { readable = false; status = "This device’s sync identity is unavailable. Unlock and reopen the app; existing data was preserved." }
    }
    func attach(_ library: DirectMacLibraryV1) {
        let firstAttachment = self.library == nil
        self.library = library
        library.localChange = { [weak self] id in self?.localChange(id) }
        if observers.isEmpty {
            for name in [UIApplication.didBecomeActiveNotification, DirectAppLockV1.unlocked] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
            }
            observers.append(NotificationCenter.default.addObserver(forName: Self.preferenceChanged, object: nil, queue: .main) { [weak self] note in
                let id = note.object as? UUID
                MainActor.assumeIsolated { if let id { self?.localChange(id) } }
            })
        }
        // Migrate only records that have no journal version. No cloud access while off.
        if firstAttachment { for mac in library.macs where !versions.contains(where: { $0.id == mac.id && $0.writer == writer }) { localChange(mac.id) } }
        refresh()
    }
    func setEnabled(_ value: Bool) {
        guard DirectAppLockV1.shared.canAccess else { return }
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil; busy = false
        enabled = value; defaults.set(value, forKey: Self.enabledKey)
        if value {
            if let library { for mac in library.macs where !versions.contains(where: { $0.id == mac.id }) { localChange(mac.id) } }
            refresh()
        } else { status = "Off. Local Macs and existing iCloud copies are kept." }
    }
    private func persist(_ values: [DirectCloudVersion]) throws {
        guard readable else { throw DirectCloudError.storage }
        let checked = try DirectCloudVersion.merge([], values)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Journal(versions: checked)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        versions = checked
    }
    func localChange(_ id: UUID) {
        guard !applying, readable, let library, library.readable else { return }
        do {
            let mac = library.macs.first { $0.id == id }
            guard mac != nil || versions.contains(where: { $0.id == id }) else { return }
            let value = DirectCloudVersion(id: id, writer: writer, revision: (versions.map(\.revision).max() ?? 0) + 1, mac: mac, preferences: mac.map { DirectCloudPreferences(mac: $0.id) })
            try persist(DirectCloudVersion.merge(versions.filter { $0.account != value.account }, [value]))
            refresh()
        } catch { status = "Could not record a sync change. Local Macs are kept." }
    }
    func refresh() {
        guard enabled, !busy, readable, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active, let library, library.readable else { return }
        busy = true; generation = UUID(); let id = generation, transport = self.transport
        refreshTask = Task {
            defer { if generation == id { busy = false; refreshTask = nil } }
            do {
                let data = try await Task.detached { try transport.read() }.value
                guard enabled, generation == id, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { return }
                guard data.count <= 512, data.allSatisfy({ $0.count <= 4096 }) else { throw DirectCloudError.invalid }
                let remote = try data.map { try JSONDecoder().decode(DirectCloudVersion.self, from: $0) }
                let merged = try DirectCloudVersion.merge(versions, remote)
                let winners = DirectCloudVersion.winners(merged)
                var next = library.macs.filter { winners[$0.id] == nil }
                next += winners.values.compactMap(\.mac)
                guard next.count <= 64 else { throw DirectCloudError.invalid }
                applying = true
                do {
                defer { applying = false }
                try library.applyCloud(next.sorted { $0.id.uuidString < $1.id.uuidString })
                for value in winners.values { value.preferences?.apply(mac: value.id) }
                try persist(merged)
                }
                for value in merged where value.writer == writer {
                    guard enabled, generation == id, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active, !Task.isCancelled else { return }
                    let bytes = try JSONEncoder().encode(value), account = value.account
                    try await Task.detached { try transport.write(bytes, account: account) }.value
                }
                if enabled, generation == id {
                    status = "Saved to the syncing Keychain. Apple manages delivery; cross-device completion is not confirmed here."
                    if versions != merged { busy = false; refresh() }
                }
            } catch { if generation == id { status = "Could not refresh iCloud Keychain. Local Macs are kept. Unlock this device and check iCloud Passwords & Keychain settings, then retry." } }
        }
    }
    func removeCloudCopies() {
        guard !busy, DirectAppLockV1.shared.canAccess else { return }
        setEnabled(false); busy = true; let transport = self.transport
        Task {
            defer { busy = false }
            do {
                try await Task.detached { try transport.removeAll() }.value
                try persist([])
                status = "Cloud copy removal requested. Sync is off; local Macs are kept. Apple manages propagation to other devices."
            } catch { status = "Could not remove iCloud copies. Sync is off; local data is kept. Retry when Keychain is available." }
        }
    }
}
#endif
