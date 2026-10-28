#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import Security
#if os(iOS)
import UIKit
#endif

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
            guard mac.id == id, try mac.validated() == mac,
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
    func remove(account: String) throws
}
extension DirectCloudTransport {
    func remove(account: String) throws { throw DirectCloudError.storage }
}

/// No new Apple container or access group. This separate service never reads local secrets.
struct DirectCloudKeychain: DirectCloudTransport {
    static let service = "media.jenny.maccompanion.cloud-library.v1"
    private let serviceName: String
    init(service: String = Self.service) { serviceName = service }
    private func query() throws -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrSynchronizable as String: true]
        #if os(macOS) || os(visionOS)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MacCompanionSharedKeychainGroup") as? String,
              group.hasSuffix(".media.jenny.maccompanion.ios"), !group.contains("$"),
              group.count > "media.jenny.maccompanion.ios".count + 1 else { throw DirectCloudError.storage }
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        query[kSecAttrAccessGroup as String] = group
        #endif
        return query
    }
    func read() throws -> [Data] {
        var q = try query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let values = result as? [Data], values.count <= 512, values.allSatisfy({ $0.count <= 4096 }) else { throw DirectCloudError.storage }
        return values
    }
    func write(_ data: Data, account: String) throws {
        guard data.count <= 4096 else { throw DirectCloudError.invalid }
        var q = try query(); q[kSecAttrAccount as String] = account
        let fields: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
        let status = SecItemUpdate(q as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw DirectCloudError.storage }
        } else if status != errSecSuccess { throw DirectCloudError.storage }
    }
    func remove(account: String) throws {
        var q = try query(); q[kSecAttrAccount as String] = account
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DirectCloudError.storage }
    }
    func removeAll() throws {
        let status = SecItemDelete(try query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DirectCloudError.storage }
    }
}

enum DirectCloudSyncIssue: Equatable { case storage, capacity }

@MainActor @Observable final class DirectCloudSyncV1 {
    static let shared = DirectCloudSyncV1()
    static let enabledKey = "direct-cloud-library-enabled-v1"
    static let preferenceChanged = Notification.Name("DirectCloudLocalPreferencesChangedV1")
    static let disclosure = "Across your devices: Mac names and models, addresses, ports, My Macs tap and swipe shortcuts, and desktop preferences. On iPhone and iPad, keyboard row layouts and built-in key choices also sync. These details describe your Macs and network.\n\nPasswords, private keys, trusted Mac identities, session quick actions and saved text don’t sync.\n\nUses iCloud Keychain with your Apple Account and trusted devices; there is no separate cloud password. Enable iCloud Keychain on each device.\n\nTurning sync off keeps existing iCloud data. Use Delete Mac Data from iCloud to remove it."
    #if os(iOS)
    private var keyboardCloud: DirectKeyboardCloudSync?
    private var savedControlsCloud: DirectSavedControlsCloudSync?
    private let keyboardTransport: any DirectCloudTransport
    private let savedControlsTransport: any DirectCloudTransport
    var savedControlsSyncStatus: String? { savedControlsCloud?.status }
    var keyboardSyncStatus: String? { keyboardCloud?.status }
    var syncNeedsAttention: Bool {
        recovery != nil || enabled && [keyboardCloud?.issue, savedControlsCloud?.issue].contains { $0 != nil }
    }
    var syncInProgress: Bool { busy || keyboardCloud?.busy == true || savedControlsCloud?.busy == true }
    var summary: String {
        if recovery != nil { return "iCloud needs attention. Local data is kept." }
        guard enabled else { return "Sync is off. iCloud data is kept." }
        if syncNeedsAttention { return "Sync needs attention. Local data is kept." }
        return syncInProgress ? "Syncing with iCloud…" : "Sync is on. Changes may take a moment."
    }
    #endif
    private struct Journal: Codable { var schema = 1; var versions: [DirectCloudVersion] }
    private let defaults: UserDefaults
    private let url: URL
    private let transport: any DirectCloudTransport
    private let applyPreferences: @MainActor (DirectCloudPreferences, UUID) -> Void
    private var writer: UUID
    private var syncIdentityReadable = true
    private let injectedWriter: UUID?
    var recovery: DirectRecoveryNotice?
    private var versions: [DirectCloudVersion] = []
    private var readable = true
    private weak var library: DirectMacLibraryV1?
    private var applying = false
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private(set) var enabled: Bool
    private(set) var busy = false
    private(set) var status = "Sync is off on this device."
    init(defaults: UserDefaults = .standard, url: URL? = nil, transport: any DirectCloudTransport = DirectCloudKeychain(), writerID: UUID? = nil,
         keyboardTransport: (any DirectCloudTransport)? = nil,
         savedControlsTransport: (any DirectCloudTransport)? = nil,
         applyPreferences: @escaping @MainActor (DirectCloudPreferences, UUID) -> Void = { $0.apply(mac: $1) }) {
        self.defaults = defaults; self.url = url ?? DirectClientPlatformV1.dataURL("direct-cloud-journal-v1.json"); self.transport = transport
        self.applyPreferences = applyPreferences
        #if os(iOS)
        if let keyboardTransport { self.keyboardTransport = keyboardTransport }
        else if writerID != nil { self.keyboardTransport = transport }
        else { self.keyboardTransport = DirectCloudKeychain(service: DirectKeyboardCloudSync.service) }
        if let savedControlsTransport { self.savedControlsTransport = savedControlsTransport }
        else if writerID != nil { self.savedControlsTransport = transport }
        else { self.savedControlsTransport = DirectSavedControlsTransport() }
        #endif
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
        injectedWriter = writerID; writer = resolvedWriter; syncIdentityReadable = identityReadable
        enabled = defaults.bool(forKey: Self.enabledKey)
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let file = try FileHandle(forReadingFrom: self.url); defer { try? file.close() }
                let data = try file.read(upToCount: 2_097_153) ?? Data(); guard data.count <= 2_097_152 else { throw DirectCloudError.invalid }
                let journal = try JSONDecoder().decode(Journal.self, from: data)
                guard journal.schema == 1 else { throw DirectCloudError.invalid }
                versions = try DirectCloudVersion.merge([], journal.versions)
            }
        } catch { readable = false; recovery = .make(.cloudUnavailable, message: "Sync history couldn’t be read. Existing history and local Macs are kept. Retry when device storage is available.") }
        if !identityReadable { readable = false; recovery = .make(.cloudUnavailable, message: "This device’s sync identity couldn’t be read. Existing data is kept. Retry when device storage is available.") }
        #if os(iOS)
        if writerID == nil && readable {
            keyboardCloud = DirectKeyboardCloudSync(writer: writer, transport: self.keyboardTransport)
            savedControlsCloud = DirectSavedControlsCloudSync(writer: writer, transport: self.savedControlsTransport)
        }
        #endif
    }
    func retry() {
        guard !busy, DirectAppLockV1.shared.canAccess else { return }
        #if os(iOS)
        keyboardCloud?.retry()
        savedControlsCloud?.retry()
        #endif
        if !readable {
            do {
                let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
                var resolved = writer
                if let injectedWriter { resolved = injectedWriter }
                else if let bytes = try TerminalSecretStore.read(identity, kind: "sync-writer") {
                    guard let text = String(data: bytes, encoding: .utf8), let id = UUID(uuidString: text) else { throw DirectCloudError.storage }; resolved = id
                } else { try TerminalSecretStore.write(Data(resolved.uuidString.utf8), id: identity, kind: "sync-writer") }
                var restored: [DirectCloudVersion] = []
                if FileManager.default.fileExists(atPath: url.path) {
                    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                    let data = try file.read(upToCount: 2_097_153) ?? Data(); guard data.count <= 2_097_152 else { throw DirectCloudError.invalid }
                    let journal = try JSONDecoder().decode(Journal.self, from: data)
                    guard journal.schema == 1 else { throw DirectCloudError.invalid }
                    restored = try DirectCloudVersion.merge([], journal.versions)
                }
                writer = resolved; versions = restored; readable = true; syncIdentityReadable = true
                if let library { for mac in library.macs where !versions.contains(where: { $0.id == mac.id && $0.writer == writer }) { localChange(mac.id) } }
            } catch { recovery = .make(.cloudUnavailable, message: "Sync data is still unavailable. Local Macs and the existing history are kept."); return }
        }
        #if os(iOS)
        if keyboardCloud == nil && injectedWriter == nil {
            keyboardCloud = DirectKeyboardCloudSync(writer: writer, transport: keyboardTransport)
            keyboardCloud?.setEnabled(enabled)
        }
        if savedControlsCloud == nil && injectedWriter == nil {
            savedControlsCloud = DirectSavedControlsCloudSync(writer: writer, transport: self.savedControlsTransport)
            savedControlsCloud?.setEnabled(enabled)
        }
        #endif
        recovery = nil; refresh()
    }
    func attach(_ library: DirectMacLibraryV1) {
        let firstAttachment = self.library == nil
        self.library = library
        #if os(iOS)
        keyboardCloud?.setEnabled(enabled)
        savedControlsCloud?.setEnabled(enabled)
        #endif
        library.localChange = { [weak self] id in self?.localChange(id) }
        if observers.isEmpty {
            for name in [DirectClientPlatformV1.didBecomeActive, DirectAppLockV1.unlocked] {
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
        #if os(iOS)
        keyboardCloud?.setEnabled(value)
        savedControlsCloud?.setEnabled(value)
        #endif
        if value {
            if let library { for mac in library.macs where !versions.contains(where: { $0.id == mac.id }) { localChange(mac.id) } }
            refresh()
        } else { status = "Sync is off on this device. Existing iCloud data is kept." }
    }
    private func persist(_ values: [DirectCloudVersion]) throws {
        guard readable else { throw DirectCloudError.storage }
        let checked = try DirectCloudVersion.merge([], values)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DirectClientPlatformV1.write(JSONEncoder().encode(Journal(versions: checked)), to: url)
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
        } catch { recovery = .make(.cloudUnavailable, message: "The sync change couldn’t be saved. Local Macs are kept. Retry after checking device storage.") }
    }
    func refresh() {
        #if os(iOS)
        if enabled { keyboardCloud?.refresh(); savedControlsCloud?.refresh() }
        #endif
        guard enabled, !busy, readable, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable, let library, library.readable else { return }
        busy = true; generation = UUID(); let id = generation, transport = self.transport
        refreshTask = Task {
            defer { if generation == id { busy = false; refreshTask = nil } }
            do {
                let data = try await Task.detached { try transport.read() }.value
                guard enabled, generation == id, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
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
                for value in winners.values { if let preferences = value.preferences { applyPreferences(preferences, value.id) } }
                try persist(merged)
                }
                for value in merged where value.writer == writer {
                    guard enabled, generation == id, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable, !Task.isCancelled else { return }
                    let bytes = try JSONEncoder().encode(value), account = value.account
                    try await Task.detached { try transport.write(bytes, account: account) }.value
                }
                if enabled, generation == id {
                    recovery = nil; status = "Changes may take a moment to appear on other devices."
                    if versions != merged { busy = false; refresh() }
                }
            } catch { if generation == id { recovery = .make(.cloudUnavailable) } }
        }
    }
    func removeCloudCopies() {
        guard !busy, DirectAppLockV1.shared.canAccess else { return }
        setEnabled(false)
        busy = true; let transport = self.transport
        Task {
            defer { busy = false }
            // Independent cloud services must remain removable when another
            // service or its local journal is unavailable. Report partial failure
            // only after every removal and local-history cleanup was attempted.
            var failed = false, removedMacs = false
            do { try await Task.detached { try transport.removeAll() }.value; removedMacs = true }
            catch { failed = true }
            #if os(iOS)
            do {
                if let keyboardCloud { try await keyboardCloud.removeCloudCopies() }
                else {
                    guard syncIdentityReadable else { throw DirectCloudError.storage }
                    try DirectKeyboardCloudSync.prepareForCloudRemoval(writer: writer)
                    let layoutTransport = keyboardTransport
                    try await Task.detached { try layoutTransport.removeAll() }.value
                }
            } catch { failed = true }
            do {
                if let savedControlsCloud { try await savedControlsCloud.removeCloudCopies() }
                else {
                    guard syncIdentityReadable else { throw DirectCloudError.storage }
                    try DirectSavedControlsCloudSync.prepareForCloudRemoval(writer: writer)
                    let contentTransport = savedControlsTransport
                    try await Task.detached { try contentTransport.removeAll() }.value
                }
            } catch { failed = true }
            #endif
            // Keep the Mac clocks/tombstones if that service could not be
            // removed. Losing them would let a later refresh revive old records.
            if removedMacs { do { try persist([]) } catch { failed = true } }
            if failed { recovery = .make(.cloudRemoval) }
            else {
                recovery = nil; status = "Deletion requested. Sync is off; your local Macs are kept. Other devices may take a moment to update."
            }
        }
    }
}
#endif
