#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

struct MacSSHKeyFileReference: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var bookmark: Data
    let fingerprint: String
    func resolve() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard url.isFileURL, !stale else { throw MacSSHKeyFileStore.Failure.reselect }
        return url
    }
    func read(passphrase: String) throws -> TerminalSSHKey {
        let key = try TerminalSSHKey.importOpenSSH(TerminalSSHKey.readOpenSSHFile(resolve()), passphrase: passphrase)
        guard key.fingerprint == fingerprint else { throw MacSSHKeyFileStore.Failure.changed }
        return key
    }
}

/// Device-only references. This store never serializes seeds or passphrases.
@MainActor enum MacSSHKeyFileStore {
    static let storageID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let kind = "key-file-references-v1"
    static let changed = Notification.Name("MacSSHKeyFileSelectionChanged")
    struct Library: Codable {
        var version = 1
        var files: [MacSSHKeyFileReference] = []
        var associations: [TerminalKeyAssociation] = []
        func validate() throws {
            guard version == 1, files.count <= 256, associations.count <= 512,
                  Set(files.map(\.id)).count == files.count,
                  Set(files.map(\.fingerprint)).count == files.count,
                  Set(associations.map(\.macID)).count == associations.count else { throw Failure.unavailable }
            for file in files {
                guard TerminalKeyLibraryStore.Library.validName(file.name), !file.bookmark.isEmpty,
                      file.bookmark.count <= 65536, file.fingerprint.hasPrefix("SHA256:"), file.fingerprint.utf8.count <= 128 else { throw Failure.unavailable }
            }
            for association in associations {
                guard files.contains(where: { $0.id == association.keyID }), association.username.utf8.count <= 255,
                      !association.username.contains("\0") else { throw Failure.unavailable }
            }
        }
    }
    enum Failure: LocalizedError {
        case unavailable, reselect, changed, requiresPro
        var errorDescription: String? {
            switch self {
            case .unavailable: "The selected key file is unavailable. Choose it again; existing selections are kept."
            case .reselect: "Access to this key file has expired. Choose the file again."
            case .changed: "This file now contains a different SSH key. Choose it again to confirm the new key."
            case .requiresPro: "Multiple SSH keys require Pro or an active trial."
            }
        }
    }
    static func load() throws -> Library {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        guard let data = try TerminalSecretStore.read(storageID, kind: kind) else { return .init() }
        guard data.count <= 2097152 else { throw Failure.unavailable }
        let value = try JSONDecoder().decode(Library.self, from: data); try value.validate(); return value
    }
    private static func save(_ library: Library) throws {
        _ = try load(); try library.validate()
        let data = try JSONEncoder().encode(library)
        guard data.count <= 2097152 else { throw Failure.unavailable }
        try TerminalSecretStore.write(data, id: storageID, kind: kind)
        NotificationCenter.default.post(name: changed, object: nil)
    }
    /// Count the same public key once even if it is both imported and referenced.
    static func identities(named: [TerminalNamedKey], files: [MacSSHKeyFileReference]) -> [(fingerprint: String, id: UUID)] {
        var result = named.map { (fingerprint: $0.key.fingerprint, id: $0.id) }
        for file in files where !result.contains(where: { $0.fingerprint == file.fingerprint }) { result.append((file.fingerprint, file.id)) }
        return result
    }
    static func canUse(_ file: MacSSHKeyFileReference, access: DirectProAccess = .shared) throws -> Bool {
        let files = try load().files
        guard files.contains(file) else { throw Failure.unavailable }
        let keys = identities(named: try TerminalKeyLibraryStore.load().keys, files: files)
        guard let id = keys.first(where: { $0.fingerprint == file.fingerprint })?.id else { throw Failure.unavailable }
        return access.ready && access.canUseKey(id, among: keys.map(\.id))
    }
    static func chooseFreeKey(_ fileID: UUID, access: DirectProAccess = .shared) throws {
        let files = try load().files
        guard let file = files.first(where: { $0.id == fileID }), access.ready else { throw Failure.unavailable }
        let keys = identities(named: try TerminalKeyLibraryStore.load().keys, files: files)
        guard let id = keys.first(where: { $0.fingerprint == file.fingerprint })?.id else { throw Failure.unavailable }
        access.chooseFreeKey(id)
        NotificationCenter.default.post(name: changed, object: nil)
    }
    @discardableResult static func add(url: URL, name: String, passphrase: String, access: DirectProAccess = .shared) throws -> UUID {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        let key = try TerminalSSHKey.importOpenSSH(TerminalSSHKey.readOpenSSHFile(url), passphrase: passphrase)
        return try register(url: url, name: name, key: key, access: access)
    }
    @discardableResult static func register(url: URL, name: String, key: TerminalSSHKey, access: DirectProAccess = .shared) throws -> UUID {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        try key.validate()
        var library = try load()
        let named = try TerminalKeyLibraryStore.load().keys
        let keys = identities(named: named, files: library.files)
        guard access.ready, keys.contains(where: { $0.fingerprint == key.fingerprint }) || access.canAddKey(count: keys.count) else { throw Failure.requiresPro }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let id = library.files.first(where: { $0.fingerprint == key.fingerprint })?.id
            ?? named.first(where: { $0.key.fingerprint == key.fingerprint })?.id ?? UUID()
        let file = MacSSHKeyFileReference(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), bookmark: bookmark, fingerprint: key.fingerprint)
        library.files.removeAll { $0.id == id }; library.files.append(file)
        try save(library); return id
    }
    static func selected(_ macID: UUID) throws -> (file: MacSSHKeyFileReference, username: String)? {
        let library = try load()
        guard let association = library.associations.first(where: { $0.macID == macID }), let file = library.files.first(where: { $0.id == association.keyID }) else { return nil }
        return (file, association.username)
    }
    static func associate(_ fileID: UUID, macID: UUID, username: String, access: DirectProAccess = .shared) throws {
        var library = try load()
        guard let file = library.files.first(where: { $0.id == fileID }), try canUse(file, access: access) else { throw Failure.requiresPro }
        library.associations.removeAll { $0.macID == macID }
        library.associations.append(.init(macID: macID, keyID: fileID, username: username)); try save(library)
        // File selection replaces the imported-key preference. Removing a file
        // later must never silently resurrect a previous authentication key.
        try TerminalKeyLibraryStore.forgetAssociation(macID)
    }
    static func forgetSelection(_ macID: UUID) throws {
        var library = try load(); library.associations.removeAll { $0.macID == macID }; try save(library)
    }
    static func remove(_ id: UUID) throws {
        var library = try load()
        for association in library.associations where association.keyID == id { try TerminalKeyLibraryStore.forgetAssociation(association.macID) }
        library.files.removeAll { $0.id == id }; library.associations.removeAll { $0.keyID == id }; try save(library)
    }
    static func rememberAccount(_ username: String, fileID: UUID, macID: UUID, fingerprint: String) throws {
        var library = try load()
        guard let index = library.associations.firstIndex(where: { $0.macID == macID && $0.keyID == fileID }),
              library.files.contains(where: { $0.id == fileID && $0.fingerprint == fingerprint }) else { throw Failure.unavailable }
        library.associations[index].username = username; try save(library)
    }
}
#endif
