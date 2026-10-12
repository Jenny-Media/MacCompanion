#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Value state owned by one Files session, surviving its sheet presentations.
/// Storage and other windows never replace its user choices implicitly.
@MainActor struct DirectFilesLoginDraft {
    private enum Initialization { case pending, complete }
    private enum Visibility { case active, suspended }
    private enum Password {
        case empty
        case saved(account: String, value: String)
        case edited(String)
        // Keep an account, never a secret, across privacy cleanup.
        case clearedSaved(account: String)
        var value: String {
            switch self {
            case .saved(_, let value), .edited(let value): value
            case .empty, .clearedSaved: ""
            }
        }
    }
    struct NamedKeyIdentity: Equatable {
        let id: UUID
        let fingerprint: String
    }
    /// No secret is retained in an attempt across suspension or authentication.
    struct AuthenticationAttempt {
        fileprivate enum Source { case savedPassword, editedPassword, key }
        fileprivate let revision: UUID
        fileprivate let account: String
        fileprivate let source: Source
    }
    enum PasswordRetention { case notRequested, saved, failed }
    private enum KeySnapshot: Equatable {
        case unknown, none, named(NamedKeyIdentity), file
    }
    private var initialization = Initialization.pending
    private var visibility = Visibility.active
    private var selection = TerminalLoginSelection()
    private var secret = Password.empty
    private var savesLogin = false
    private var keySnapshot = KeySnapshot.unknown
    private var revision = UUID()
    #if os(macOS)
    private var keyFileReference: MacSSHKeyFileReference?
    #endif
    var passphrase = ""

    var username: String {
        get { selection.username }
        set {
            guard newValue != selection.username else { return }
            initialization = .complete
            revision = UUID()
            if selection.method == .password { invalidateRestoration() }
            selection.username = newValue
        }
    }
    var method: TerminalLoginMethod { selection.method }
    var password: String {
        get { secret.value }
        set {
            guard newValue != secret.value else { return }
            initialization = .complete
            revision = UUID()
            secret = newValue.isEmpty ? .empty : .edited(newValue)
        }
    }
    var remember: Bool {
        get { savesLogin }
        set {
            guard newValue != savesLogin else { return }
            initialization = .complete
            revision = UUID()
            savesLogin = newValue
            if !newValue { invalidateRestoration() }
        }
    }
    var isSuspended: Bool { visibility == .suspended }
    var hasKeySnapshot: Bool { keySnapshot != .unknown }
    func needsInitialLoad(active: Bool, allowed: Bool, signIn: Bool) -> Bool {
        initialization == .pending && visibility == .active && active && allowed && signIn
    }
    mutating func initialize(saved: TerminalSecretStore.Login?) {
        guard initialization == .pending, visibility == .active else { return }
        if let saved {
            selection.loadPasswordAccount(saved.username)
            secret = .saved(account: saved.username, value: saved.password)
            savesLogin = true
        }
        initialization = .complete
    }
    mutating func selectMethod(_ method: TerminalLoginMethod) {
        initialization = .complete
        revision = UUID()
        selection.select(method)
    }
    mutating func loadKeyAccount(_ account: String?, preferSelected: Bool) {
        let previousAccount = selection.username, previousMethod = selection.method
        selection.loadKeyAccount(account, preferSelected: preferSelected)
        if previousAccount != selection.username || previousMethod != selection.method { revision = UUID() }
    }
    mutating func updateNamedKey(_ identity: NamedKeyIdentity?) -> Bool {
        let snapshot = identity.map { KeySnapshot.named($0) } ?? .none
        let changed = keySnapshot != snapshot
        keySnapshot = snapshot
        return changed
    }
    mutating func keyFileChanged() { passphrase = ""; keySnapshot = .file }
    #if os(macOS)
    mutating func updateKeyFile(_ reference: MacSSHKeyFileReference?) -> Bool {
        guard keyFileReference != reference else { return false }
        keyFileReference = reference
        keyFileChanged()
        return true
    }
    #endif
    func authenticationAttempt(account: String, password: String?, remember: Bool) -> AuthenticationAttempt? {
        guard selection.username == account else { return nil }
        guard let password else {
            return selection.method == .sshKey ? .init(revision: revision, account: account, source: .key) : nil
        }
        guard selection.method == .password, !password.isEmpty,
              secret.value == password, savesLogin == remember else { return nil }
        let source: AuthenticationAttempt.Source
        if case .saved(let savedAccount, _) = secret, savedAccount == account { source = .savedPassword }
        else { source = .editedPassword }
        return .init(revision: revision, account: account, source: source)
    }

    mutating func suspend() {
        visibility = .suspended
        let account: String?
        switch secret {
        case .saved(let savedAccount, _), .clearedSaved(let savedAccount): account = savesLogin ? savedAccount : nil
        case .empty, .edited: account = nil
        }
        clearSecrets(restoring: account)
    }
    mutating func resume() { visibility = .active }
    mutating func authenticationSucceeded(_ attempt: AuthenticationAttempt?, retention: PasswordRetention) {
        guard let attempt, attempt.revision == revision, attempt.account == selection.username else { return }
        // Successful authentication does not prove a write succeeded. A failed
        // redundant write preserves the provenance of an already saved login;
        // an edited secret requires successful retention by this exact attempt.
        let restorable = attempt.source != .key && savesLogin && selection.method == .password &&
            (retention == .saved || (retention == .failed && attempt.source == .savedPassword))
        clearSecrets(restoring: restorable ? attempt.account : nil)
    }
    mutating func invalidate() {
        self = Self()
        initialization = .complete
        visibility = .suspended
    }
    mutating func restorePassword(active: Bool, allowed: Bool, signIn: Bool,
                                  read: () throws -> TerminalSecretStore.Login?) rethrows {
        guard visibility == .active, active, allowed, signIn,
              case .clearedSaved(let account) = secret,
              savesLogin, selection.method == .password, selection.username == account else { return }
        if let saved = try read(), saved.username == account {
            secret = .saved(account: account, value: saved.password)
        } else { secret = .empty }
    }
    private mutating func clearSecrets(restoring account: String?) {
        secret = account.map { .clearedSaved(account: $0) } ?? .empty
        passphrase = ""
    }
    private mutating func invalidateRestoration() {
        secret = secret.value.isEmpty ? .empty : .edited(secret.value)
    }
}
#endif
