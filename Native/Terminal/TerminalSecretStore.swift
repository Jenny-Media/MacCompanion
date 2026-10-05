#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Security
import CryptoKit

enum TerminalSecretStore {
    struct Login: Codable { var username: String; var password: String }
    private static func query(_ id: UUID, _ kind: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.ssh-\(kind).v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
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
        return try read(id, kind: "login").map { try JSONDecoder().decode(Login.self, from: $0) }
    }
    static func save(_ login: Login, id: UUID) throws { try write(JSONEncoder().encode(login), id: id, kind: "login") }
    static func hostKey(_ id: UUID) throws -> String? {
        guard let data = try read(id, kind: "host-key") else { return nil }
        guard let key = String(data: data, encoding: .utf8), fingerprint(key) != nil else { throw Failure.storage }
        return key
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
    static func forgetLogin(_ id: UUID) throws { try remove(id, kind: "login") }
    static func forgetHostKey(_ id: UUID) throws { try remove(id, kind: "host-key") }
    @MainActor static func sshKey(_ id: UUID) throws -> TerminalSSHKey? {
        guard DirectAppLockV1.shared.canAccess else { throw Failure.locked }
        guard let data = try read(id, kind: "private-key") else { return nil }
        let key = try JSONDecoder().decode(TerminalSSHKey.self, from: data); try key.validate(); return key
    }
    @MainActor static func saveKey(_ key: TerminalSSHKey, id: UUID) throws {
        guard DirectAppLockV1.shared.canAccess else { throw Failure.locked }
        try key.validate(); _ = try sshKey(id); try write(JSONEncoder().encode(key), id: id, kind: "private-key")
    }
    static func forgetKey(_ id: UUID) throws { try remove(id, kind: "private-key") }
    static func remove(_ id: UUID) throws { try forgetLogin(id); try forgetHostKey(id); try forgetKey(id) }
    enum Failure: Error { case storage, locked, changedKey, rejectedKey, network }
}
#endif
