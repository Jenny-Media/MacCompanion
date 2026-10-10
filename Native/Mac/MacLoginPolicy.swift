#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

@MainActor enum MacLoginPolicy {
    /// Match the iPhone's ARD field bounds before modifying local login data.
    static func prepareVNC(username: String, password: String, remember: Bool, macID: UUID,
                           remove: (UUID) throws -> Void = DesktopCredentialStoreV1.remove) throws {
        let account = Array(username.utf8), secret = Array(password.utf8)
        guard (1...63).contains(account.count), (1...63).contains(secret.count),
              !account.contains(0), !secret.contains(0) else { throw Failure.invalidLogin }
        if !remember { try remove(macID) }
    }

    /// Check the window's displayed key, which may differ from a selection
    /// changed in another window. Removed or unreadable keys cannot be dialed.
    static func canUseSSHKey(_ key: TerminalSSHKey, access: DirectProAccess = .shared,
                             keys: () throws -> [TerminalNamedKey] = { try TerminalKeyLibraryStore.load().keys }) throws -> Bool {
        let library = try keys()
        guard let entry = library.first(where: { $0.key.seed == key.seed }) else { throw Failure.keyUnavailable }
        let identities = MacSSHKeyFileStore.identities(named: library, files: try MacSSHKeyFileStore.load().files)
        return access.canUseKey(entry.id, among: identities.map(\.id))
    }
    enum Failure: Error { case invalidLogin, keyUnavailable }
}
#endif
