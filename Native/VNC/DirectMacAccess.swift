#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
@preconcurrency import Citadel

struct DirectMacAccessProfile: Codable, Equatable {
    struct Password: Codable, Equatable {
        var username: String
        var password: String
        var valid: Bool { !username.isEmpty && !password.isEmpty && username.utf8.count <= 255 && password.utf8.count <= 4096 && !username.contains("\0") && !password.contains("\0") }
    }
    enum SSHMethod: String, Codable, CaseIterable { case inherit, password, key }
    var version = 1
    var login: Password?
    var sshMethod = SSHMethod.inherit
    var sshPassword: Password?
    var keyID: UUID?
    var keyUsername = ""
    var passwordLogin: Password? { sshMethod == .password ? sshPassword : login }
    static func migrated(desktop: Password?, ssh: Password?, key: TerminalNamedKey?) -> Self {
        var result = Self(login: desktop ?? ssh)
        if let ssh, ssh != result.login { result.sshPassword = ssh; result.sshMethod = .password }
        if let key { result.keyID = key.id; result.keyUsername = key.key.username; result.sshMethod = .key }
        return result
    }
}

/// One device-only authority. Legacy items are migration inputs, never a fallback
/// after a canonical record (including an intentionally empty one) exists.
@MainActor enum DirectMacAccessStore {
    enum Failure: Error { case busy, invalid, changed, storage }
    static let changed = Notification.Name("DirectMacAccessChangedV1")
    static let forgotten = Notification.Name("DirectMacAccessForgottenV1")
    static let kind = "mac-access-v1"
    struct Repository {
        var read: () throws -> Data?
        var write: (Data) throws -> Void
        var legacy: () throws -> DirectMacAccessProfile
        var clean: () throws -> Void
        func load() throws -> DirectMacAccessProfile {
            if let data = try read() {
                let value = try JSONDecoder().decode(DirectMacAccessProfile.self, from: data)
                guard value.version == 1 else { throw Failure.storage }
                return value
            }
            let value = try legacy()
            let bytes = try JSONEncoder().encode(value)
            try write(bytes)
            guard try read() == bytes else { throw Failure.storage }
            // A failed cleanup cannot make stale legacy data authoritative again.
            try? clean()
            return value
        }
    }
    static func repository(_ id: UUID) -> Repository {
        .init(read: { try TerminalSecretStore.read(id, kind: kind) },
              write: { try TerminalSecretStore.write($0, id: id, kind: kind) },
              legacy: {
                  let desktop = try DesktopCredentialStoreV1.readLegacyChecked(id).map { DirectMacAccessProfile.Password(username: $0.username, password: $0.password) }
                  let ssh = try TerminalSecretStore.read(id, kind: "login").map { try JSONDecoder().decode(DirectMacAccessProfile.Password.self, from: $0) }
                  let key = try TerminalKeyLibraryStore.selectedLegacy(id)
                  return .migrated(desktop: desktop, ssh: ssh, key: key)
              }, clean: {
                  try DesktopCredentialStoreV1.removeLegacy(id)
                  try TerminalSecretStore.removeLegacyLogin(id)
              })
    }
    static func load(_ id: UUID) throws -> DirectMacAccessProfile {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        return try repository(id).load()
    }
    static func write(_ value: DirectMacAccessProfile, id: UUID) throws {
        guard DirectAppLockV1.shared.canAccess, value.version == 1 else { throw Failure.storage }
        try TerminalSecretStore.write(JSONEncoder().encode(value), id: id, kind: kind)
        NotificationCenter.default.post(name: changed, object: id)
    }
    static func save(_ value: DirectMacAccessProfile, id: UUID, replacing expected: DirectMacAccessProfile) throws {
        guard !DirectMacConnections.shared.isActive(id) else { throw Failure.busy }
        guard try load(id) == expected else { throw Failure.changed }
        guard value.login == nil || value.login?.valid == true,
              value.sshPassword == nil || value.sshPassword?.valid == true,
              value.sshMethod != .key || (value.keyID != nil && value.keyUsername.utf8.count <= 255 && !value.keyUsername.contains("\0")) else { throw Failure.invalid }
        if value.sshMethod == .key, value.keyID != expected.keyID || expected.sshMethod != .key {
            guard let keyID = value.keyID, try TerminalKeyLibraryStore.load().keys.contains(where: { $0.id == keyID }) else { throw Failure.invalid }
        }
        try write(value, id: id)
    }
    static func setMacLogin(_ login: DirectMacAccessProfile.Password?, id: UUID) throws {
        let current = try load(id); var value = current; value.login = login
        if value == current { return }
        try save(value, id: id, replacing: current)
    }
    static func setSSHPassword(_ login: DirectMacAccessProfile.Password?, id: UUID) throws {
        let current = try load(id); var value = current
        if login == nil {
            if value.sshMethod == .password { value.sshPassword = nil }
            else { value.login = nil }
        }
        else if value.login == nil { value.login = login; value.sshMethod = .inherit }
        else if login == value.login { value.sshMethod = .inherit; value.sshPassword = nil }
        else { value.sshMethod = .password; value.sshPassword = login }
        if value == current { return }
        try save(value, id: id, replacing: current)
    }
    static func selectKey(_ keyID: UUID?, account: String = "", macID: UUID) throws {
        let current = try load(macID); var value = current
        value.keyID = keyID; value.keyUsername = keyID == nil ? "" : account
        value.sshMethod = keyID == nil ? .inherit : .key
        try save(value, id: macID, replacing: current)
    }
    static func checkConnection(macID: UUID, username: String, password: String, key: TerminalSSHKey?, ssh: Bool, ownerID: UUID? = nil) throws {
        guard DirectMacConnections.shared.isActive(macID, excludingOwner: ownerID) else { return }
        guard !DirectMacConnections.shared.hasPendingAccessChange(macID, excludingOwner: ownerID) else { throw Failure.busy }
        let profile = try load(macID)
        if ssh, let key {
            guard let selected = try TerminalKeyLibraryStore.selected(macID), selected.key.seed == key.seed,
                  profile.keyUsername == username else { throw Failure.busy }
        } else {
            let expected = ssh ? profile.passwordLogin : profile.login
            guard expected == .init(username: username, password: password) else { throw Failure.busy }
        }
    }
    static func willRetainChange(macID: UUID, username: String, password: String, key: TerminalSSHKey?, ssh: Bool, remember: Bool) -> Bool {
        guard let profile = try? load(macID) else { return remember || key != nil }
        if key != nil { return profile.keyUsername != username }
        guard remember else { return false }
        return (ssh ? profile.passwordLogin : profile.login) != .init(username: username, password: password)
    }
    static func retain(_ login: DirectMacAccessProfile.Password, macID: UUID, ssh: Bool, owner: UUID) throws {
        guard DirectMacConnections.shared.owns(owner, macID: macID) else { throw Failure.changed }
        var value = try load(macID)
        if ssh && value.sshMethod == .password { value.sshPassword = login }
        else if !ssh || value.sshMethod == .inherit { value.login = login }
        else { return }
        try write(value, id: macID)
        DirectMacConnections.shared.retained(owner)
    }
    static func retainKeyAccount(_ account: String, macID: UUID, keyID: UUID?, owner: UUID) throws {
        guard let keyID, DirectMacConnections.shared.owns(owner, macID: macID) else { return }
        var profile = try load(macID)
        guard profile.sshMethod == .key, profile.keyID == keyID, profile.keyUsername != account else { return }
        profile.keyUsername = account; try write(profile, id: macID)
        DirectMacConnections.shared.retained(owner)
    }
    static func forget(_ id: UUID, replacing expected: DirectMacAccessProfile? = nil) throws {
        guard !DirectMacConnections.shared.isActive(id) else { throw Failure.busy }
        let current = try load(id)
        let empty = DirectMacAccessProfile()
        guard expected == nil || current == expected || current == empty else { throw Failure.changed }
        if current != empty { try save(empty, id: id, replacing: current) }
        guard try load(id) == empty else { throw Failure.storage }
        // Commit the empty authority before revoking all staged credentials.
        // An idempotent retry must also clear a retained form's old copy.
        NotificationCenter.default.post(name: forgotten, object: id)
    }
}

/// Credential owners can outlive their visible form, so revocation is observed
/// by the owner and scoped to the Mac. No credential data enters notifications.
final class DirectMacAccessForgetObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    @MainActor init(macID: UUID, forgotten: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(forName: DirectMacAccessStore.forgotten, object: nil, queue: .main) { notification in
            guard notification.object as? UUID == macID else { return }
            MainActor.assumeIsolated { forgotten() }
        }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Records network ownership, including teardown. UI visibility is not activity.
@MainActor @Observable final class DirectMacConnections {
    static let shared = DirectMacConnections()
    static let changed = Notification.Name("DirectMacConnectionOwnershipChangedV1")
    struct Entry {
        let macID: UUID
        let ownerID: UUID
        let keyID: UUID?
        let kind: String
        var pendingAccessChange: Bool
        let disconnect: @MainActor () -> Void
        let transferActive: @MainActor () -> Bool
    }
    private(set) var entries: [UUID: Entry] = [:]
    func begin(macID: UUID, kind: String, keyID: UUID? = nil, ownerID: UUID = UUID(), pendingAccessChange: Bool = false,
               transferActive: @escaping @MainActor () -> Bool = { false },
               disconnect: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID(); entries[token] = .init(macID: macID, ownerID: ownerID, keyID: keyID, kind: kind, pendingAccessChange: pendingAccessChange, disconnect: disconnect, transferActive: transferActive)
        NotificationCenter.default.post(name: Self.changed, object: macID)
        return token
    }
    func end(_ token: UUID?) {
        if let token, let entry = entries.removeValue(forKey: token) { NotificationCenter.default.post(name: Self.changed, object: entry.macID) }
    }
    func isActive(_ id: UUID, excludingOwner: UUID? = nil) -> Bool { entries.values.contains { $0.macID == id && (excludingOwner == nil || $0.ownerID != excludingOwner) } }
    func hasPendingAccessChange(_ id: UUID, excludingOwner: UUID?) -> Bool {
        entries.values.contains { $0.macID == id && $0.pendingAccessChange && (excludingOwner == nil || $0.ownerID != excludingOwner) }
    }
    func retained(_ token: UUID) { entries[token]?.pendingAccessChange = false }
    func keyInUse(_ id: UUID) -> Bool { entries.values.contains { $0.keyID == id } }
    func owns(_ token: UUID, macID: UUID) -> Bool { entries[token]?.macID == macID }
    func hasTransfers(_ id: UUID) -> Bool { entries.values.contains { $0.macID == id && $0.transferActive() } }
    func disconnect(_ id: UUID) async -> Bool {
        let owners = entries.values.filter { $0.macID == id }
        owners.forEach { $0.disconnect() }
        for _ in 0..<200 {
            if !isActive(id) { return true }
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return false }
        }
        return !isActive(id)
    }
}

@MainActor enum DirectFilesWorkspace {
    private struct Key: Hashable { let macID: UUID; let library: URL }
    @MainActor @Observable fileprivate final class Signals { var revision = 0 }
    private static let signals = Signals()
    private static var owners: [Key: DirectFilesSession] = [:]
    static func recoverableDownloads(libraryURL: URL) -> [DirectFilesSession] {
        _ = signals.revision
        return owners.values.filter {
            $0.libraryURL.standardizedFileURL == libraryURL.standardizedFileURL && $0.macRemoved && $0.hasUnsavedDownloads
        }.sorted { $0.mac.name == $1.mac.name ? $0.mac.id.uuidString < $1.mac.id.uuidString : $0.mac.name < $1.mac.name }
    }
    static func session(_ mac: DirectMacRecordV1, libraryURL: URL = DirectMacLibraryV1.defaultURL) -> DirectFilesSession {
        let key = Key(macID: mac.id, library: libraryURL.standardizedFileURL)
        if let existing = owners[key], !existing.isClosed {
            if existing.mac == mac || existing.transferActive || existing.hasPendingResults { return existing }
            existing.close()
        }
        owners = owners.filter { !$0.value.isClosed }
        let owner = DirectFilesSession(mac: mac, libraryURL: libraryURL); owners[key] = owner
        // Creation can occur in a presentation initializer. Publish afterward.
        Task { signals.revision &+= 1 }
        return owner
    }
}
#endif
