#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation

struct TerminalNamedKey: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var key: TerminalSSHKey
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.key.seed == rhs.key.seed }
}
struct TerminalKeyAssociation: Codable {
    var macID: UUID
    var keyID: UUID
    var username: String
}

@MainActor enum TerminalKeyLibraryStore {
    private static let storageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    struct Library: Codable {
        var version = 2
        var keys: [TerminalNamedKey] = []
        var associations: [TerminalKeyAssociation] = []
        var migratedMacs: [UUID] = []
        func validate() throws {
            guard version == 2, keys.count <= 256, associations.count <= 512, migratedMacs.count <= 512,
                  Set(keys.map(\.id)).count == keys.count,
                  Set(associations.map(\.macID)).count == associations.count,
                  Set(migratedMacs).count == migratedMacs.count else { throw TerminalSecretStore.Failure.storage }
            for value in keys {
                try value.key.validate()
                guard Self.validName(value.name) else { throw TerminalSecretStore.Failure.storage }
            }
            let ids = Set(keys.map(\.id))
            for association in associations {
                guard ids.contains(association.keyID), association.username.utf8.count <= 255,
                      !association.username.contains("\0") else { throw TerminalSecretStore.Failure.storage }
            }
        }
        static func validName(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 80 &&
                !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
    }
    static func load() throws -> Library {
        guard DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.locked }
        guard let data = try TerminalSecretStore.read(storageID, kind: "key-library-v2") else { return .init() }
        guard data.count <= 524288 else { throw TerminalSecretStore.Failure.storage }
        let library = try JSONDecoder().decode(Library.self, from: data); try library.validate(); return library
    }
    private static func save(_ library: Library) throws {
        _ = try load(); try library.validate()
        try TerminalSecretStore.write(JSONEncoder().encode(library), id: storageID, kind: "key-library-v2")
    }
    static func migrate(_ macID: UUID, name: String = "SSH Key") throws {
        var library = try load()
        guard !library.migratedMacs.contains(macID) else { return }
        guard let data = try TerminalSecretStore.read(macID, kind: "private-key") else { return }
        let key = try JSONDecoder().decode(TerminalSSHKey.self, from: data); try key.validate()
        let id: UUID
        if let match = library.keys.first(where: { $0.key.seed == key.seed }) { id = match.id }
        else {
            id = macID
            library.keys.append(.init(id: id, name: name, key: .init(seed: key.seed)))
        }
        if !library.associations.contains(where: { $0.macID == macID }) {
            library.associations.append(.init(macID: macID, keyID: id, username: key.username))
        }
        library.migratedMacs.append(macID)
        try save(library)
        // A failed cleanup does not invalidate the already committed migration.
        try? TerminalSecretStore.removeLegacyKey(macID)
    }
    static func selected(_ macID: UUID) throws -> TerminalNamedKey? {
        try migrate(macID)
        let library = try load()
        guard let association = library.associations.first(where: { $0.macID == macID }),
              var entry = library.keys.first(where: { $0.id == association.keyID }) else { return nil }
        entry.key.username = association.username; return entry
    }
    @discardableResult static func add(_ key: TerminalSSHKey, name: String) throws -> UUID {
        var library = try load(); try key.validate()
        if let existing = library.keys.first(where: { $0.key.seed == key.seed }) { return existing.id }
        guard library.keys.count < 256, Library.validName(name) else { throw TerminalSecretStore.Failure.storage }
        let id = UUID(); library.keys.append(.init(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), key: .init(seed: key.seed)))
        try save(library); return id
    }
    static func rename(_ id: UUID, name: String) throws {
        var library = try load()
        guard Library.validName(name), let index = library.keys.firstIndex(where: { $0.id == id }) else { throw TerminalSecretStore.Failure.storage }
        library.keys[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines); try save(library)
    }
    static func associate(_ keyID: UUID, macID: UUID, username: String) throws {
        var library = try load()
        guard library.keys.contains(where: { $0.id == keyID }) else { throw TerminalSecretStore.Failure.storage }
        library.associations.removeAll { $0.macID == macID }
        library.associations.append(.init(macID: macID, keyID: keyID, username: username))
        if !library.migratedMacs.contains(macID) { library.migratedMacs.append(macID) }
        try save(library)
    }
    static func forgetAssociation(_ macID: UUID) throws {
        // Migrate first so removing a Mac never loses its only local copy of a key.
        try migrate(macID)
        var library = try load(); library.associations.removeAll { $0.macID == macID }; try save(library)
        try TerminalSecretStore.removeLegacyKey(macID)
    }
    static func delete(_ id: UUID) throws {
        var library = try load()
        library.keys.removeAll { $0.id == id }; library.associations.removeAll { $0.keyID == id }
        try save(library)
    }
    static func saveCompatible(_ key: TerminalSSHKey, macID: UUID) throws {
        try migrate(macID)
        let id = try add(key, name: "SSH Key")
        try associate(id, macID: macID, username: key.username)
    }
}

@MainActor @Observable final class TerminalKeyLibrary {
    private(set) var keys: [TerminalNamedKey] = []
    private(set) var associations: [TerminalKeyAssociation] = []
    private(set) var readable = true
    var recovery: DirectRecoveryNotice?
    var error: String? {
        get { recovery?.message }
        set { recovery = newValue.map { .make(.savedDataUnavailable, message: $0) } }
    }
    func reload(macs: [DirectMacRecordV1] = []) {
        do {
            for mac in macs { try TerminalKeyLibraryStore.migrate(mac.id, name: String(mac.name.prefix(70)) + " SSH Key") }
            let value = try TerminalKeyLibraryStore.load(); keys = value.keys; associations = value.associations; readable = true; error = nil
        } catch { readable = false; recovery = .make(.savedDataUnavailable, message: "Saved SSH keys couldn’t be read. Existing keys are kept. Retry when device storage is available; unreadable data won’t be replaced.") }
    }
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        guard readable else { return false }
        do { try action(); reload(); return readable }
        catch { recovery = .make(.saveFailed, message: "The key library change couldn’t be completed. Review the current keys and retry; no unreadable data will be replaced."); return false }
    }
}
#endif
