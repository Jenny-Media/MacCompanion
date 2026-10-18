#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Visible form and bounded active-session recovery have different lifetimes.
/// Never use a hidden UITextField as the credential store for reconnecting.
@MainActor @objc final class DirectDesktopLoginState: NSObject {
    private var draft = DirectFilesLoginDraft()
    private var attempt: DirectFilesLoginDraft.AuthenticationAttempt?
    private var pending: TerminalSecretStore.Login?
    private var recovery: TerminalSecretStore.Login?
    private var established = false
    var readSaved: () throws -> TerminalSecretStore.Login?
    @objc init(macID: String?, username: String, password: String) {
        readSaved = {
            guard let id = macID.flatMap(UUID.init(uuidString:)) else { return nil }
            return try DesktopCredentialStoreV1.readChecked(id).map { .init(username: $0.username, password: $0.password) }
        }
        super.init()
        draft.initialize(saved: password.isEmpty ? nil : .init(username: username, password: password))
        if password.isEmpty { draft.username = username }
    }
    @objc var accessAllowed: Bool { DirectAppLockV1.shared.canAccess }
    @objc var username: String { draft.username }
    @objc var password: String { draft.password }
    @objc var remember: Bool { draft.remember }
    @objc func edit(username: String, password: String, remember: Bool) {
        draft.username = username; draft.password = password; draft.remember = remember
    }
    @objc func discardSessionRecovery() {
        pending = nil; recovery = nil; attempt = nil; established = false
    }
    @objc func replace(username: String, password: String) {
        pending = nil; recovery = nil; established = false; attempt = nil
        draft = DirectFilesLoginDraft()
        draft.initialize(saved: password.isEmpty ? nil : .init(username: username, password: password))
        if password.isEmpty { draft.username = username }
    }
    @objc func beginLogin() -> [String: String] {
        pending = .init(username: draft.username, password: draft.password)
        attempt = draft.authenticationAttempt(account: draft.username, password: draft.password, remember: draft.remember)
        return ["username": draft.username, "password": draft.password]
    }
    @objc func loginForResume() -> [String: String]? {
        guard let login = recovery ?? pending else { return nil }
        return ["username": login.username, "password": login.password]
    }
    @objc func authenticated() {
        guard let pending else { return }
        recovery = pending; self.pending = nil; established = true
        let stored = draft.remember ? try? readSaved() : nil
        let retained = draft.remember && stored?.username == pending.username && stored?.password == pending.password
        draft.authenticationSucceeded(attempt, retention: retained ? .saved : .failed)
        attempt = nil
    }
    @objc func suspend() { draft.suspend() }
    @objc func suspendForModeRetry() {
        draft.suspend()
        if !draft.remember { draft.username = "" }
    }
    @objc func resume(active: Bool, allowed: Bool) {
        draft.resume()
        // A live owner needs no visible secret and must not reread storage.
        guard !established else { return }
        try? draft.restorePassword(active: active, allowed: allowed, signIn: true, read: readSaved)
    }
    @objc func ended(active: Bool, allowed: Bool) {
        pending = nil; recovery = nil; attempt = nil
        if established { draft.passwordSessionEnded() }
        established = false
        if active && allowed { resume(active: active, allowed: allowed) }
    }
    @objc func invalidate() {
        pending = nil; recovery = nil; attempt = nil; established = false; draft.invalidate()
    }
}
#endif
