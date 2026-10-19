#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Security
import CryptoKit

enum TerminalSecretStore {
    struct Login: Codable { var username: String; var password: String }
    private static func query(_ id: UUID, _ kind: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.ssh-\(kind).v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
    static func read(_ id: UUID, kind: String) throws -> Data? {
        var q = query(id, kind); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.storage }
        return data
    }
    static func write(_ data: Data, id: UUID, kind: String) throws {
        _ = try read(id, kind: kind)
        let fields: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(id, kind) as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(id, kind).merging(fields) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw Failure.storage }
        } else if status != errSecSuccess { throw Failure.storage }
    }
    @MainActor static func login(_ id: UUID) throws -> Login? {
        guard DirectAppLockV1.shared.canAccess else { throw Failure.locked }
        #if os(iOS)
        return try DirectMacAccessStore.load(id).passwordLogin.map { .init(username: $0.username, password: $0.password) }
        #else
        return try read(id, kind: "login").map { try JSONDecoder().decode(Login.self, from: $0) }
        #endif
    }
    @MainActor static func save(_ login: Login, id: UUID) throws {
        #if os(iOS)
        try DirectMacAccessStore.setSSHPassword(.init(username: login.username, password: login.password), id: id)
        #else
        try write(JSONEncoder().encode(login), id: id, kind: "login")
        #endif
    }
    static func hostKey(_ id: UUID) throws -> String? {
        guard let data = try read(id, kind: "host-key") else { return nil }
        guard let key = String(data: data, encoding: .utf8), fingerprint(key) != nil else { throw Failure.storage }
        return key
    }
    /// Approval may have waited while another session established shared trust.
    /// Add atomically: never update a pin belonging to another approval.
    static func approveHostKey(_ key: String, id: UUID) throws {
        guard fingerprint(key) != nil else { throw Failure.rejectedKey }
        if let saved = try hostKey(id) {
            guard saved == key else { throw Failure.changedKey }; return
        }
        let fields: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemAdd(query(id, "host-key").merging(fields) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard try hostKey(id) == key else { throw Failure.changedKey }
        } else if status != errSecSuccess { throw Failure.storage }
    }
    static func fingerprint(_ key: String) -> String? {
        let fields = key.split(separator: " ")
        guard fields.count >= 2, let data = Data(base64Encoded: String(fields[1])) else { return nil }
        return "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    private static func remove(_ id: UUID, kind: String) throws {
        let result = SecItemDelete(query(id, kind) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw Failure.storage }
    }
    @MainActor static func forgetLogin(_ id: UUID) throws {
        #if os(iOS)
        try DirectMacAccessStore.setSSHPassword(nil, id: id)
        #else
        try remove(id, kind: "login")
        #endif
    }
    static func removeLegacyLogin(_ id: UUID) throws { try remove(id, kind: "login") }
    @MainActor static func forgetHostKey(_ id: UUID) throws {
        #if os(iOS)
        guard !DirectMacConnections.shared.isActive(id) else { throw DirectMacAccessStore.Failure.busy }
        #endif
        try remove(id, kind: "host-key")
    }
    @MainActor static func sshKey(_ id: UUID) throws -> TerminalSSHKey? {
        try TerminalKeyLibraryStore.selected(id)?.key
    }
    @MainActor static func saveKey(_ key: TerminalSSHKey, id: UUID) throws {
        guard DirectAppLockV1.shared.canAccess else { throw Failure.locked }
        try TerminalKeyLibraryStore.saveCompatible(key, macID: id)
    }
    static func removeLegacyKey(_ id: UUID) throws { try remove(id, kind: "private-key") }
    @MainActor static func forgetKey(_ id: UUID) throws {
        try TerminalKeyLibraryStore.forgetAssociation(id)
        #if os(macOS)
        try MacSSHKeyFileStore.forgetSelection(id)
        #endif
    }
    #if os(iOS)
    /// A never-saved identity has no migration authority to preserve. Delete its
    /// legacy inputs first, then the canonical profile; retries are idempotent.
    /// The caller journals the ID and waits for all scoped connection owners.
    @MainActor static func removeTemporaryIdentity(_ id: UUID) throws {
        guard !DirectMacConnections.shared.isActive(id) else { throw DirectMacAccessStore.Failure.busy }
        try DesktopCredentialStoreV1.removeLegacy(id)
        try removeLegacyLogin(id)
        try removeLegacyKey(id)
        try remove(id, kind: "host-key")
        try remove(id, kind: "terminal-keyboard-v1")
        try remove(id, kind: DirectMacAccessStore.kind)
    }
    #endif
    @MainActor static func remove(_ id: UUID) throws {
        #if os(iOS)
        // Mac removal has its own persisted-library invalidation; it is not an
        // editable login change. Preserve shared private keys.
        try DirectMacAccessStore.write(.init(), id: id)
        try remove(id, kind: "host-key"); try removeLegacyLogin(id); try removeLegacyKey(id)
        #else
        try forgetLogin(id); try forgetHostKey(id); try forgetKey(id)
        #endif
    }
    enum Failure: Error { case storage, locked, changedKey, rejectedKey, network }
}
#endif
