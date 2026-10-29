#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Darwin
import CoreFoundation
import Foundation
import Observation

/// The pending file is the pre-restore state. Renaming it to the recovery copy
/// is the commit point; a crash before that point rolls back on next launch.
@MainActor @Observable final class DirectLocalBackupStore {
    static let changed = Notification.Name("DirectLocalBackupChangedV1")
    struct Change: Sendable { let libraryURL: URL; let ids: Set<UUID> }
    static private(set) var applying = false
    private static var operationInFlight = false
    static var recoveryDirectory: URL { DirectClientPlatformV1.dataURL("local-backup-recovery") }
    static var pendingRecovery: Bool { FileManager.default.fileExists(atPath: recoveryDirectory.appending(path: "pending.json").path) }
    private(set) var busy = false
    private(set) var hasRecoveryCopy = false
    private(set) var message: String?
    private(set) var problem: String?

    enum Failure: Error { case locked, busy, activeSessions, storage, recoveryRequired, cloudRemovalInProgress }
    struct FileStorage {
        var read: (URL, Int) throws -> Data? = { url, limit in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let data = try file.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw Failure.storage }; return data
        }
        var write: (Data, URL) throws -> Void = { data, url in
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var folder = directory; try folder.setResourceValues(values)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
        var remove: (URL) throws -> Void = { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        var commit: (URL, URL) throws -> Void = { source, target in
            let result = source.withUnsafeFileSystemRepresentation { from in
                target.withUnsafeFileSystemRepresentation { to in Darwin.rename(from, to) }
            }
            guard result == 0 else { throw Failure.storage }
        }
    }
    private struct Snapshot: Codable {
        var version = 2
        var createdAt = Date()
        var macs: Data?
        var terminal: Data
        var remoteMac: Data
        var preferences: [UUID: DirectLocalBackup.Mac]
        static let maximumBytes = 70 * 1024 * 1024
        func validate() throws {
            guard version == 2, macs.map({ $0.count <= 2 * 1024 * 1024 }) ?? true,
                  terminal.count <= 20 * 1024 * 1024, remoteMac.count <= 20 * 1024 * 1024 else { throw Failure.storage }
            let saved = try records
            guard preferences.count <= 64, Set(preferences.keys) == Set(saved.map(\.id)) else { throw Failure.storage }
            for record in saved {
                guard let value = preferences[record.id], try value.record(id: record.id) == record else { throw Failure.storage }
            }
            for (data, family) in [(terminal, TerminalControlsFamily.terminal), (remoteMac, .remoteMac)] {
                let profile = try JSONDecoder().decode(TerminalControlsProfile.self, from: data)
                guard profile.version == TerminalControlsProfile.currentVersion,
                      profile.rowsSchema == TerminalControlsProfile.currentRowsSchema,
                      (profile.family ?? .terminal) == family, profile.valid else { throw Failure.storage }
            }
        }
        func profile(_ family: TerminalControlsFamily) throws -> TerminalControlsProfile {
            try JSONDecoder().decode(TerminalControlsProfile.self, from: family == .terminal ? terminal : remoteMac)
        }
        var records: [DirectMacRecordV1] { get throws { try macs.map(DirectMacLibraryV1.decodeRecords) ?? [] } }
        var settings: [(DirectLocalBackup.Mac, UUID)] {
            get throws {
                try records.map { record in
                    guard let value = preferences[record.id] else { throw Failure.storage }
                    return (value, record.id)
                }
            }
        }
    }
    let library: DirectMacLibraryV1
    private let stores: [TerminalControlsFamily: TerminalControlsStore]
    private let directory: URL
    private let files: FileStorage
    private let canAccess: () -> Bool
    private let sessionsActive: () -> Bool
    private let pauseSync: () async throws -> Void
    private let applyPreferences: (DirectLocalBackup.Mac, UUID) -> Void
    private let readPreferences: (DirectMacRecordV1) -> DirectLocalBackup.Mac
    private let persistPreferences: () throws -> Void
    private let replaceMacs: ([DirectMacRecordV1]) throws -> Void
    private var pendingURL: URL { directory.appending(path: "pending.json") }
    private var recoveryURL: URL { directory.appending(path: "previous.json") }
    /// Backup's cross-store commit requires a checked persistence boundary;
    /// ordinary preference edits can keep using the system's asynchronous path.
    static func persistStandardPreferences() throws {
        guard CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication) else { throw Failure.storage }
    }
    private struct SyncReconciliation: Codable { var ids: Set<UUID> }
    private static func reconciliationURL(_ directory: URL) -> URL { directory.appending(path: "sync-reconciliation.json") }
    static func reconciliationIDs(in directory: URL, files: FileStorage = .init()) throws -> Set<UUID>? {
        guard let data = try files.read(reconciliationURL(directory), 512 * 1024) else { return nil }
        guard !FileManager.default.fileExists(atPath: directory.appending(path: "pending.json").path) else { throw Failure.recoveryRequired }
        let value = try JSONDecoder().decode(SyncReconciliation.self, from: data)
        guard value.ids.count <= 8192 else { throw Failure.storage }
        return value.ids
    }
    static func finishReconciliation(in directory: URL) throws {
        try FileStorage().remove(reconciliationURL(directory))
    }
    private func stageReconciliation(_ ids: Set<UUID>) throws {
        var combined = ids
        if let data = try files.read(Self.reconciliationURL(directory), 512 * 1024) {
            combined.formUnion(try JSONDecoder().decode(SyncReconciliation.self, from: data).ids)
        }
        guard combined.count <= 8192 else { throw Failure.storage }
        try files.write(JSONEncoder().encode(SyncReconciliation(ids: combined)), Self.reconciliationURL(directory))
    }

    init(library: DirectMacLibraryV1? = nil,
         stores: [TerminalControlsFamily: TerminalControlsStore] = [.terminal: .init(), .remoteMac: .remoteMac()],
         directory: URL? = nil, files: FileStorage = .init(),
         canAccess: @escaping () -> Bool = { DirectAppLockV1.shared.canAccess },
         sessionsActive: @escaping () -> Bool = { !DirectMacConnections.shared.entries.isEmpty },
         pauseSync: @escaping () async throws -> Void = { try await DirectCloudSyncV1.shared.pauseForLocalRestore() },
         applyPreferences: @escaping (DirectLocalBackup.Mac, UUID) -> Void = { $0.applyPreferences(to: $1) },
         readPreferences: @escaping (DirectMacRecordV1) -> DirectLocalBackup.Mac = { DirectLocalBackup.Mac($0) },
         persistPreferences: @escaping () throws -> Void = { try DirectLocalBackupStore.persistStandardPreferences() },
         replaceMacs: (([DirectMacRecordV1]) throws -> Void)? = nil) {
        let source = library ?? DirectMacLibraryV1()
        self.library = source; self.stores = stores; self.directory = directory ?? Self.recoveryDirectory
        self.files = files; self.canAccess = canAccess; self.sessionsActive = sessionsActive
        self.pauseSync = pauseSync; self.applyPreferences = applyPreferences
        self.readPreferences = readPreferences
        self.persistPreferences = persistPreferences
        self.replaceMacs = replaceMacs ?? { try source.replaceFromBackup($0) }
        refreshRecoveryCopy()
    }
    func refreshRecoveryCopy() {
        hasRecoveryCopy = canAccess() && FileManager.default.fileExists(atPath: recoveryURL.path)
    }
    func makeBackup() throws -> DirectLocalBackup {
        guard canAccess(), !busy, !Self.operationInFlight else { throw Failure.locked }
        try recoverPending()
        library.reload(); guard library.readable else { throw Failure.storage }
        guard let terminal = stores[.terminal], let remote = stores[.remoteMac] else { throw Failure.storage }
        var backup = try DirectLocalBackup(macs: library.macs, terminal: terminal.load(), remoteMac: remote.load())
        backup.macs = library.macs.map(readPreferences)
        try backup.validate()
        return backup
    }
    func recoveryPreview() throws -> DirectLocalBackup {
        guard canAccess() else { throw Failure.locked }
        let old = try readSnapshot(recoveryURL)
        var backup = try DirectLocalBackup(macs: old.records, terminal: old.profile(.terminal), remoteMac: old.profile(.remoteMac), createdAt: old.createdAt)
        backup.macs = try old.settings.map { $0.0 }
        try backup.validate()
        return backup
    }
    func restore(_ backup: DirectLocalBackup) async {
        do {
            try backup.validate()
            let records = try backup.macs.map { try $0.record() }
            try await perform(records: records, terminal: backup.terminal, remote: backup.remoteMac,
                recovered: [.terminal: backup.terminalRecovered, .remoteMac: backup.remoteRecovered], settings: Array(zip(backup.macs, records.map(\.id))))
            problem = nil; message = "Backup restored. Previous data is available below."
        } catch { record(error) }
    }
    func restorePrevious() async {
        do {
            guard canAccess() else { throw Failure.locked }
            let old = try readSnapshot(recoveryURL)
            let terminal = try old.profile(.terminal), remote = try old.profile(.remoteMac)
            try await perform(records: old.records, terminal: terminal, remote: remote,
                recovered: [.terminal: terminal.syncState.recovered, .remoteMac: remote.syncState.recovered], settings: old.settings)
            problem = nil; message = "Previous data restored."
        } catch { record(error) }
    }
    private func perform(records: [DirectMacRecordV1], terminal: TerminalControlsProfile,
                         remote: TerminalControlsProfile, recovered: [TerminalControlsFamily: [DirectControlsRecoveredChange]],
                         settings: [(DirectLocalBackup.Mac, UUID)]) async throws {
        guard !Self.operationInFlight else { throw Failure.busy }
        guard canAccess() else { throw Failure.locked }
        guard !sessionsActive() else { throw Failure.activeSessions }
        Self.operationInFlight = true; busy = true; problem = nil; message = nil
        defer { Self.operationInFlight = false; busy = false; refreshRecoveryCopy() }
        try await pauseSync()
        guard !Task.isCancelled, canAccess() else { throw Failure.locked }
        guard !sessionsActive() else { throw Failure.activeSessions }
        // Persist sync-off and the original preferences before their recovery
        // snapshot can become authoritative across an interrupted restore.
        try persistPreferences()
        try recoverPending()
        library.reload(); guard library.readable else { throw Failure.storage }
        // Finish normal local-profile preparation before capturing the rollback.
        for family in [TerminalControlsFamily.terminal, .remoteMac] { _ = try stores[family]?.load() }
        let before = try capture()
        let oldIDs = Set(library.macs.map(\.id))
        // This intent survives both sides of the commit point. Startup may
        // recover before cloud tracking attaches, so notifications alone are
        // insufficient to reconcile removed or rolled-back Mac identities.
        try stageReconciliation(oldIDs.union(records.map(\.id)))
        try writeSnapshot(before, to: pendingURL)
        let priorApplying = Self.applying; Self.applying = true
        defer { Self.applying = priorApplying }
        do {
            guard canAccess() else { throw Failure.locked }
            // Capture both old baselines before writing either new profile.
            for family in [TerminalControlsFamily.terminal, .remoteMac] {
                NotificationCenter.default.post(name: TerminalControlsStore.willChange, object: family.rawValue, userInfo: ["cloudImport": false])
            }
            try save(terminal, family: .terminal, recovered: recovered[.terminal] ?? [])
            try save(remote, family: .remoteMac, recovered: recovered[.remoteMac] ?? [])
            guard canAccess(), !sessionsActive() else { throw Failure.locked }
            try replaceMacs(records)
            guard try DirectMacLibraryV1.readRecords(at: library.storageURL) == records else { throw Failure.storage }
            for (preferences, id) in settings { applyPreferences(preferences, id) }
            try persistPreferences()
            // All stores have succeeded before the atomic commit point.
            try files.commit(pendingURL, recoveryURL)
        } catch {
            do { try applyRaw(before); try files.remove(pendingURL) }
            catch {
                library.backupRecoveryUnavailable()
                throw Failure.recoveryRequired
            }
            publish(ids: oldIDs.union(records.map(\.id)))
            throw error
        }
        publish(ids: oldIDs.union(records.map(\.id)))
    }
    private func save(_ imported: TerminalControlsProfile, family: TerminalControlsFamily, recovered: [DirectControlsRecoveredChange]) throws {
        guard canAccess(), let store = stores[family] else { throw Failure.locked }
        let current = try store.load()
        var value = imported
        value.revision = current.revision; value.importedMacs = current.importedMacs
        var state = current.syncState
        // Manual restore is an explicit placement choice. A prior cloud
        // normalization receipt must not substitute its old intended positions.
        state.savedPositions = nil
        state.recovered = recovered.map { entry in var copy = entry; copy.id = "backup-" + UUID().uuidString.lowercased(); return copy }
        value.syncState = state
        let saved = try store.save(value, notifyChanges: false)
        guard let bytes = try store.read(),
              try JSONDecoder().decode(TerminalControlsProfile.self, from: bytes) == saved else { throw Failure.storage }
    }
    private func capture() throws -> Snapshot {
        guard canAccess(), let terminal = try stores[.terminal]?.read(), let remote = try stores[.remoteMac]?.read() else { throw Failure.storage }
        let value = Snapshot(macs: try files.read(library.storageURL, 2 * 1024 * 1024), terminal: terminal, remoteMac: remote,
            preferences: Dictionary(uniqueKeysWithValues: library.macs.map { ($0.id, readPreferences($0)) }))
        try value.validate(); return value
    }
    private func writeSnapshot(_ value: Snapshot, to url: URL) throws {
        try value.validate()
        let data = try JSONEncoder().encode(value)
        guard data.count <= Snapshot.maximumBytes else { throw Failure.storage }
        try files.write(data, url)
    }
    private func readSnapshot(_ url: URL) throws -> Snapshot {
        guard let data = try files.read(url, Snapshot.maximumBytes) else { throw Failure.storage }
        let value = try JSONDecoder().decode(Snapshot.self, from: data)
        try value.validate(); return value
    }
    private func applyRaw(_ value: Snapshot) throws {
        guard canAccess(), let terminal = stores[.terminal], let remote = stores[.remoteMac] else { throw Failure.locked }
        try value.validate()
        try terminal.write(value.terminal); try remote.write(value.remoteMac)
        if let macs = value.macs { try DirectClientPlatformV1.write(macs, to: library.storageURL) }
        else { try files.remove(library.storageURL) }
        for (preferences, id) in try value.settings { applyPreferences(preferences, id) }
        try persistPreferences()
    }
    func recoverPending() throws {
        guard FileManager.default.fileExists(atPath: pendingURL.path) else { return }
        guard canAccess() else { throw Failure.locked }
        let before = try readSnapshot(pendingURL)
        let wasApplying = Self.applying; Self.applying = true
        defer { Self.applying = wasApplying }
        let oldIDs = Set(library.macs.map(\.id))
        try applyRaw(before); try files.remove(pendingURL)
        publish(ids: oldIDs.union(try before.records.map(\.id)))
    }
    static func recoverDefaultIfNeeded() throws {
        guard pendingRecovery, !applying else { return }
        guard DirectAppLockV1.shared.canAccess else { throw Failure.locked }
        applying = true; defer { applying = false }
        try DirectLocalBackupStore().recoverPending()
    }
    private func publish(ids: Set<UUID>) {
        library.reload()
        for family in [TerminalControlsFamily.terminal, .remoteMac] {
            NotificationCenter.default.post(name: TerminalControlsStore.changed, object: family.rawValue, userInfo: ["cloudImport": false])
        }
        NotificationCenter.default.post(name: Self.changed, object: Change(libraryURL: library.storageURL.standardizedFileURL, ids: ids))
    }
    private func record(_ error: Error) {
        message = nil
        switch error {
        case Failure.locked: problem = "Unlock Mac Companion, then try again."
        case Failure.busy: problem = "Another restore is running. Try again when it finishes."
        case Failure.cloudRemovalInProgress: problem = "Wait for iCloud deletion to finish, then restore the backup."
        case Failure.activeSessions: problem = "Disconnect your sessions before restoring a backup."
        case Failure.recoveryRequired: problem = "Restore couldn’t finish. Your recovery copy is kept. Retry when storage is available."
        default: problem = "Couldn’t restore the backup. Your previous data is kept. Try again."
        }
    }
}
#endif
