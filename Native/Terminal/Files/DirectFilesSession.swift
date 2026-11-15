#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import Crypto
@preconcurrency import Citadel
@preconcurrency import NIO
@preconcurrency import NIOSSH
import Logging

private final class DirectFilesBackgroundObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    @MainActor init(_ handler: @escaping @Sendable (Notification) -> Void) {
        token = NotificationCenter.default.addObserver(forName: DirectClientPlatformV1.didEnterBackground, object: nil, queue: .main, using: handler)
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor @Observable final class DirectFilesSession {
    enum Phase: String { case signIn = "Sign In Required", connecting = "Connecting", ready = "Ready", interrupted = "Disconnected" }
    struct ConnectionRecovery {
        enum Reason { case missingLogin, rejectedLogin, identityChanged }
        let reason: Reason
        let message: String
        let presentedIdentity: TerminalSecretStore.HostIdentity?
    }
    enum ConflictChoice { case keepBoth, replace, cancel }
    struct Trust: Identifiable { let id = UUID(); let fingerprint: String }
    struct Conflict: Identifiable {
        let id = UUID()
        let name: String
        let replaceAllowed: Bool
    }
    private struct PendingConflict {
        let prompt: Conflict
        let job: UUID
        let item: UUID
        let destination: String
        let reply: CheckedContinuation<ConflictChoice, Never>
    }
    private struct TransferBatch {
        enum Phase {
            case idle
            case running(UUID)
            case awaitingDecision(PendingConflict)
            case settled
        }
        var account = ""
        var items: [ResultItem] = []
        var phase = Phase.idle
    }
    struct ResultItem: Identifiable {
        enum Outcome { case waiting, transferring, completed, interrupted }
        let id = UUID()
        let source: URL?
        let remotePath: String?
        let folder: String
        let name: String
        var destinationName: String?
        var outcome: Outcome = .waiting
        var message = "Waiting"
        var bytes: UInt64 = 0
        var total: UInt64?
        var localDownload: URL?
        var saved = false
        var needsAttention: Bool { outcome != .completed || (localDownload != nil && !saved) }
    }
    let mac: DirectMacRecordV1
    let libraryURL: URL
    var loginDraft = DirectFilesLoginDraft()
    private struct ParentConnection {
        let ownerID: UUID
        let generation: UUID
        let isCurrent: @MainActor () -> Bool
    }
    private enum CredentialSource {
        case macPassword
        case sshPassword
        case sshKey(UUID?)
    }
    private struct Connection {
        enum Authority {
            case borrowed(ParentConnection)
            case independent(CredentialSource)
        }
        let account: String
        let authority: Authority

        var parent: ParentConnection? {
            if case .borrowed(let parent) = authority { return parent }
            return nil
        }
    }
    private enum ConnectionState {
        case signIn
        case opening(Connection)
        case ready(Connection)
        case interrupted(account: String)
        case closed
    }
    private var connectionState = ConnectionState.signIn
    private var connection: Connection? {
        switch connectionState {
        case .opening(let connection), .ready(let connection): connection
        case .signIn, .interrupted, .closed: nil
        }
    }
    var account: String {
        if case .interrupted(let previousAccount) = connectionState { return previousAccount }
        return connection?.account ?? ""
    }
    var phase: Phase {
        switch connectionState {
        case .signIn: .signIn
        case .opening: .connecting
        case .ready: .ready
        case .interrupted, .closed: .interrupted
        }
    }
    private var connectionIsCurrent: Bool { connection?.parent?.isCurrent() != false }
    @ObservationIgnored var activityChanged: (@MainActor (String) -> Void)?
    private(set) var status = "Sign In Required" { didSet { activityChanged?(activityTitle) } }
    private(set) var directory: DirectFilesDirectory?
    private(set) var home = ""
    private var batch = TransferBatch() { didSet { activityChanged?(activityTitle) } }
    var results: [ResultItem] { batch.items }
    var resultsAccount: String { batch.account }
    private(set) var preparedUploads: [URL] = []
    private(set) var busy = false
    private var statusMessage: String?
    var message: String? {
        get { statusMessage ?? connectionRecovery?.message }
        set { statusMessage = newValue }
    }
    private(set) var connectionRecovery: ConnectionRecovery?
    var trust: Trust?
    var conflict: Conflict? {
        if case .awaitingDecision(let decision) = batch.phase { return decision.prompt }
        return nil
    }
    #if os(iOS)
    private let accessOwnerID = UUID()
    private var connectionLease: UUID?
    #endif
    var isBorrowed: Bool { connection?.parent != nil }
    func reportConnectionRecovery(_ reason: ConnectionRecovery.Reason, message: String, presentedIdentity: TerminalSecretStore.HostIdentity? = nil) {
        statusMessage = nil
        connectionRecovery = .init(reason: reason, message: message, presentedIdentity: presentedIdentity)
    }
    func clearConnectionRecovery() {
        connectionRecovery = nil
    }
    #if os(iOS)
    enum SavedLogin: Equatable {
        case password(DirectMacAccessProfile.Password)
        case key(id: UUID, account: String)
        case missing(String)

        init(profile: DirectMacAccessProfile, useSSH: Bool) {
            if useSSH && profile.sshMethod == .key {
                guard let id = profile.keyID else { self = .missing("Choose an available SSH key in Saved Login."); return }
                let account = profile.keyUsername
                guard !account.isEmpty, account.utf8.count <= 255, !account.contains("\0") else {
                    self = .missing("Add the Terminal account for this SSH key in Saved Login.")
                    return
                }
                self = .key(id: id, account: account)
            } else if let login = useSSH ? profile.passwordLogin : profile.login, login.valid {
                self = .password(login)
            } else {
                self = .missing("Add the login you use for this Mac to open Files.")
            }
        }
    }
    func updateSavedLoginRecovery(previous: SavedLogin, current: SavedLogin) {
        guard let reason = connectionRecovery?.reason, reason == .missingLogin || reason == .rejectedLogin else { return }
        if case .missing(let message) = current { reportConnectionRecovery(.missingLogin, message: message) }
        else if reason == .missingLogin || previous != current { clearConnectionRecovery() }
    }
    #endif
    func disconnectBorrowed(_ owner: UUID) {
        if connection?.parent?.generation == owner { disconnect(message: "The parent session ended. Completed downloads are kept; reconnect before retrying interrupted transfers.") }
    }
    private var generation = UUID()
    private var operation = UUID()
    private var work: Task<Void, Never>?
    private var stageWork: Task<[URL], Error>?
    private var deadline: Task<Void, Never>?
    private var socket: TerminalSocketOwner?
    private var channel: Channel?
    private var ssh: SSHClient?
    private var store: (any DirectFilesRemoteStore)?
    private var trustReply: CheckedContinuation<Bool, Never>?
    private var temporaryRoot: URL?
    @ObservationIgnored private var backgroundObserver: DirectFilesBackgroundObservation?
    private var closed: Bool { if case .closed = connectionState { true } else { false } }
    var isClosed: Bool { closed }
    private(set) var macRemoved = false
    var shouldCloseAfterRemoval: Bool { macRemoved && !hasUnsavedDownloads }
    @ObservationIgnored private var removalObserver: DirectMacRemovalObservation?
    #if os(iOS)
    @ObservationIgnored private var forgetObserver: DirectMacAccessForgetObservation?
    #endif
    private let canAccess: @MainActor () -> Bool
    private let saveLogin: @MainActor (TerminalSecretStore.Login, UUID) throws -> Void
    private let idleTimeout: Duration
    init(mac: DirectMacRecordV1, canAccess: @escaping @MainActor () -> Bool = { DirectAppLockV1.shared.canAccess }, idleTimeout: Duration = .seconds(30),
         libraryURL: URL = DirectMacLibraryV1.defaultURL,
         saveLogin: @escaping @MainActor (TerminalSecretStore.Login, UUID) throws -> Void = TerminalSecretStore.save) {
        precondition(idleTimeout > .zero)
        self.mac = mac; self.canAccess = canAccess; self.idleTimeout = idleTimeout
        self.libraryURL = libraryURL
        self.saveLogin = saveLogin
        #if os(iOS)
        forgetObserver = DirectMacAccessForgetObservation(macID: mac.id) { [weak self] in self?.loginDraft = .init() }
        #endif
        removalObserver = DirectMacRemovalObservation(macID: mac.id, libraryURL: libraryURL) { [weak self] in self?.removedFromLibrary() }
    }
    private func observeLifecycle() {
        guard backgroundObserver == nil else { return }
        observeAccess()
        backgroundObserver = DirectFilesBackgroundObservation { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.closed, !self.macRemoved else { return }
                self.loginDraft.suspend()
                self.pauseConnection(message: "Files paused. Reconnect, then Retry any interrupted transfer.")
            }
        }
    }
    private func observeAccess() {
        // iOS's enabled preference lives in UserDefaults. Track allowed even
        // while unlock is disabled, so enabling it also retires a hidden owner.
        withObservationTracking { _ = DirectAppLockV1.shared.allowed; _ = canAccess() } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.closed, !self.macRemoved else { return }
                if !self.canAccess() {
                    self.loginDraft.suspend()
                    self.pauseConnection(message: "Files stopped when the app locked. Reconnect after unlocking.")
                }
                self.observeAccess()
            }
        }
    }
    var transferActive: Bool {
        switch batch.phase {
        case .running, .awaitingDecision: true
        case .idle, .settled: false
        }
    }
    var hasPendingResults: Bool { results.contains { $0.needsAttention } }
    var hasUnsavedDownloads: Bool { results.contains { $0.localDownload != nil && !$0.saved } }
    var activityTitle: String {
        if let current = results.first(where: { $0.outcome == .transferring }) {
            if let total = current.total, total > 0 { return "Transferring · \(min(100, Int(Double(current.bytes) / Double(total) * 100)))%" }
            return "Transferring"
        }
        return status
    }
    private func check(_ token: UUID, _ job: UUID? = nil) throws {
        guard !closed, !macRemoved, generation == token, job == nil || operation == job, canAccess(), connectionIsCurrent, !Task.isCancelled else { throw CancellationError() }
    }
    private func armDeadline(after delay: Duration? = nil) {
        deadline?.cancel(); let token = generation, job = operation
        let delay = delay ?? idleTimeout
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            // Cancellation can arrive after sleep completes, while this callback is queued.
            guard !Task.isCancelled, let self, self.generation == token, self.operation == job else { return }
            self.disconnect(message: DirectFilesFailure.timedOut.localizedDescription)
        }
    }
    private func receivedResponse(_ token: UUID) {
        guard generation == token, !closed, busy, canAccess(), conflict == nil else { return }
        armDeadline()
    }
    func connectBorrowed(_ context: DirectFilesConnectionContext) {
        guard context.macID == mac.id, context.isCurrent(), !closed, !macRemoved, canAccess(), DirectClientPlatformV1.sessionAvailable, !busy else { return }
        if phase == .ready, let parent = connection?.parent, parent.ownerID == context.ownerID,
           parent.generation == context.generation, account == context.account { return }
        clearConnectionRecovery()
        guard !transferActive else { message = "A transfer is still running for " + account + ". Finish or cancel it first."; return }
        guard !hasPendingResults || resultsAccount.isEmpty || resultsAccount == context.account else {
            message = "Save or discard the files for " + resultsAccount + " before opening another account."; return
        }
        let previousPath = account == context.account ? directory?.path : nil
        observeLifecycle(); retire(); let token = generation
        let parent = ParentConnection(ownerID: context.ownerID, generation: context.generation, isCurrent: context.isCurrent)
        let attempt = Connection(account: context.account, authority: .borrowed(parent))
        connectionState = .opening(attempt)
        #if os(iOS)
        connectionLease = DirectMacConnections.shared.begin(macID: mac.id, kind: "files", keyID: context.keyID, ownerID: context.ownerID,
            transferActive: { [weak self] in self?.transferActive == true }, disconnect: { [weak self] in self?.disconnect() })
        #endif
        busy = true; message = nil; status = "Opening Files…"; armDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let logger = Logger(label: "Files", factory: { _ in SwiftLogNoOpLogHandler() })
                let client = try await context.client.openSFTP(logger: logger)
                do { try check(token) } catch { try? await client.close(); throw error }
                let store = DirectFilesSFTPStore(client: client); self.store = store
                client.closeFuture.whenComplete { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.disconnect(message: "Files connection ended. Reopen Files after reconnecting the session. Transfers will not restart automatically.")
                    }
                }
                client.setResponseActivityHandler { [weak self] in await self?.receivedResponse(token) }
                let previous = previousPath
                let homePath = try await store.directory("."); try check(token)
                let directory: DirectFilesDirectory
                if let previous, previous != homePath.path { directory = (try? await store.directory(previous)) ?? homePath }
                else { directory = homePath }
                try check(token)
                self.directory = directory; home = homePath.path
                deadline?.cancel(); busy = false; connectionState = .ready(attempt); status = "Ready"
            } catch {
                guard generation == token else { return }
                disconnect(message: "Files could not open on this connection. Check the session and retry. Nothing was transferred automatically.")
            }
        }
    }
    func connect(username: String, password: String, key: TerminalSSHKey?, remember: Bool, keyFileID: UUID? = nil, useMacLogin: Bool = false) {
        guard !closed, !macRemoved, canAccess(), !busy, phase != .ready else { return }
        clearConnectionRecovery()
        guard !username.isEmpty, username.utf8.count <= 255, !username.contains("\0"),
              (key != nil || !password.isEmpty), password.utf8.count <= 4096, !password.contains("\0") else {
            message = "Enter a Mac account and password, or choose its SSH key."; return
        }
        #if os(iOS)
        do { try DirectMacAccessStore.checkConnection(macID: mac.id, username: username, password: password, key: key, ssh: !useMacLogin, ownerID: accessOwnerID) }
        catch { message = "Disconnect this Mac before changing its login."; return }
        guard !hasPendingResults || resultsAccount.isEmpty || resultsAccount == username else { message = "Save or discard files for " + resultsAccount + " before changing accounts."; return }
        #endif
        let authentication: @Sendable () -> SSHAuthenticationMethod
        let namedSelection: TerminalNamedKey?
        #if os(macOS)
        let keyFileSelection: MacSSHKeyFileStore.LoginSelection?
        #endif
        do {
            if let key {
                try key.validate()
                #if os(macOS)
                keyFileSelection = try keyFileID.flatMap {
                    try MacSSHKeyFileStore.loginSelection(fileID: $0, macID: mac.id, fingerprint: key.fingerprint)
                }
                #endif
                let selected = keyFileID == nil ? try TerminalKeyLibraryStore.selected(mac.id) : nil
                namedSelection = selected?.key.seed == key.seed ? selected : nil
                let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)
                authentication = { .ed25519(username: username, privateKey: parsed) }
            } else {
                namedSelection = nil
                #if os(macOS)
                keyFileSelection = nil
                #endif
                authentication = { .passwordBased(username: username, password: password) }
            }
        } catch { message = "The SSH key could not be read."; return }
        let attempt = loginDraft.authenticationAttempt(account: username, password: key == nil ? password : nil, remember: remember)
        #if os(iOS)
        do { if key == nil && !remember {
            if useMacLogin { try DesktopCredentialStoreV1.remove(mac.id) }
            else { try TerminalSecretStore.forgetLogin(mac.id) }
        } }
        catch { message = "Disconnect this Mac before changing its saved login."; return }
        #endif
        observeLifecycle()
        retire(); let token = generation, owner = TerminalSocketOwner(); socket = owner
        #if os(iOS)
        connectionLease = DirectMacConnections.shared.begin(macID: mac.id, kind: "files", keyID: key == nil ? nil : (try? DirectMacAccessStore.load(mac.id).keyID), ownerID: accessOwnerID,
            pendingAccessChange: DirectMacAccessStore.willRetainChange(macID: mac.id, username: username, password: password, key: key, ssh: !useMacLogin, remember: remember),
            transferActive: { [weak self] in self?.transferActive == true }, disconnect: { [weak self] in self?.disconnect() })
        #endif
        let credential: CredentialSource
        if key != nil { credential = .sshKey(keyFileID ?? namedSelection?.id) }
        else { credential = useMacLogin ? .macPassword : .sshPassword }
        let connectionAttempt = Connection(account: username, authority: .independent(credential))
        connectionState = .opening(connectionAttempt)
        busy = true; message = nil; status = "Contacting Remote Login…"; armDeadline(after: .seconds(60))
        let addresses = mac.addresses, port = mac.sshPort
        work = Task {
            do {
                do {
                    #if !os(iOS)
                    if key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) }
                    #endif
                }
                catch {
                    retire(); status = "Sign In Required"
                    message = "The saved SSH login could not be removed. Files did not connect."
                    return
                }
                let (fd, failure) = await Task.detached(priority: .userInitiated) {
                    var failure = 0
                    let fd = CompanionVNCConnectAddresses(addresses, port, { owner.isCancelled }, { owner.register($0) }, nil, &failure)
                    return (fd, failure)
                }.value
                guard fd >= 0 else { throw failure == 10 ? TerminalConnectionFailure.lookup : TerminalConnectionFailure.socket }
                do { try check(token) } catch { Darwin.close(fd); throw error }
                let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                    .channelOption(ChannelOptions.autoRead, value: false).withConnectedSocket(fd).get()
                do { try check(token) } catch { try? await channel.close(); throw error }
                self.channel = channel
                let validator = TerminalHostValidator { [weak self] publicKey in
                    guard let self else { throw CancellationError() }; try self.check(token)
                    if try TerminalSecretStore.matchesTrustedHostKey(publicKey, id: self.mac.id) { return }
                    guard let fingerprint = TerminalSecretStore.fingerprint(publicKey) else { throw TerminalSecretStore.Failure.rejectedKey }
                    self.status = "Verify this Mac’s identity"; self.trust = .init(fingerprint: fingerprint)
                    let accepted = await withCheckedContinuation { self.trustReply = $0 }
                    try self.check(token)
                    guard accepted else { throw TerminalSecretStore.Failure.rejectedKey }
                    do { try TerminalSecretStore.approveHostKey(publicKey, id: self.mac.id) }
                    catch TerminalSecretStore.Failure.changedKey { throw TerminalSecretStore.HostKeyMismatch(key: publicKey) }
                }
                var settings = SSHClientSettings(host: addresses.first ?? "", port: port,
                    authenticationMethod: authentication, hostKeyValidator: .custom(validator))
                settings.connectTimeout = .seconds(60)
                let ssh = try await SSHClient.connect(on: channel, settings: settings)
                do { try check(token) } catch { try? await ssh.close(); throw error }; self.ssh = ssh
                self.status = "Opening Files…"; self.armDeadline()
                let logger = Logger(label: "Files", factory: { _ in SwiftLogNoOpLogHandler() })
                let client = try await ssh.openSFTP(logger: logger)
                do { try check(token) } catch { try? await client.close(); throw error }
                client.closeFuture.whenComplete { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.closed, self.generation == token else { return }
                        self.disconnect(message: "Files connection lost. Reconnect to continue; transfers will not restart automatically.")
                    }
                }
                armDeadline()
                client.setResponseActivityHandler { [weak self] in await self?.receivedResponse(token) }
                let store = DirectFilesSFTPStore(client: client); self.store = store
                let directory = try await store.directory("."); try check(token)
                // Reuse existing Terminal retention. No Desktop credentials are read.
                var retention = DirectFilesLoginDraft.PasswordRetention.notRequested
                do { if keyFileID != nil {
                    #if os(macOS)
                    if let keyFileSelection { try MacSSHKeyFileStore.rememberAccount(username, selection: keyFileSelection) }
                    #endif
                } else if let namedSelection {
                    try TerminalKeyLibraryStore.rememberAccount(username, macID: mac.id, selection: namedSelection)
                } else if remember && key == nil {
                    let login = TerminalSecretStore.Login(username: username, password: password)
                    do {
                        #if os(iOS)
                        if let owner = connectionLease { try DirectMacAccessStore.retain(.init(username: username, password: password), macID: mac.id, ssh: !useMacLogin, owner: owner) }
                        #else
                        try saveLogin(login, mac.id)
                        #endif
                        retention = .saved
                    }
                    catch { retention = .failed; throw error }
                }
                } catch { self.message = "Connected. The SSH login could not be saved on this device." }
                loginDraft.authenticationSucceeded(attempt, retention: retention)
                self.directory = directory; self.home = directory.path
                deadline?.cancel(); busy = false; connectionState = .ready(connectionAttempt); status = "Ready"
                channel.closeFuture.whenComplete { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.disconnect(message: "Files connection lost. Reconnect to continue; transfers will not restart automatically.")
                    }
                }
            } catch {
                guard generation == token else { return }
                let openingFiles = ssh != nil
                retire()
                if let mismatch = error as? TerminalSecretStore.HostKeyMismatch {
                    reportConnectionRecovery(.identityChanged, message: "The Mac’s SSH identity changed. Verify it before reconnecting. Existing trust is kept.",
                        presentedIdentity: mismatch.presented)
                } else if let failure = error as? TerminalSecretStore.Failure, failure == .rejectedKey {
                    message = "Server identity was not approved. No file connection was opened."
                } else if DirectTerminalSession.reason(for: error, keyLogin: key != nil) == .loginRejected || DirectTerminalSession.reason(for: error, keyLogin: key != nil) == .keyRejected {
                    reportConnectionRecovery(.rejectedLogin, message: "Your Mac didn’t accept this login. Check the saved account or SSH key and the users allowed in Remote Login.")
                } else if openingFiles { message = "SSH connected, but Files could not open. Check SFTP availability and this account’s folder permissions." }
                else { message = "Couldn’t connect to Remote Login. Check the network, saved SSH port and Remote Login settings on your Mac." }
                status = "Sign In Required"
            }
        }
    }
    func answerTrust(_ accepted: Bool, requestID: UUID? = nil) {
        if let requestID, trust?.id != requestID { return }
        let reply = trustReply; trustReply = nil; trust = nil
        reply?.resume(returning: accepted && canAccess())
    }
    func answerConflict(_ choice: ConflictChoice, requestID: UUID? = nil) {
        guard case .awaitingDecision(let decision) = batch.phase,
              requestID == nil || requestID == decision.prompt.id else { return }
        let current = operation == decision.job && connectionIsCurrent && canAccess() &&
            batch.items.contains { $0.id == decision.item && $0.outcome == .transferring &&
                (try? DirectFilesPolicy.child($0.name, of: $0.folder)) == decision.destination }
        batch.phase = .running(decision.job)
        decision.reply.resume(returning: current ? choice : .cancel)
    }
    func browse(_ path: String) {
        guard phase == .ready, connectionIsCurrent, !busy, let store, canAccess() else { return }
        let token = generation; operation = UUID(); let job = operation
        busy = true; message = nil; status = "Opening folder…"; armDeadline()
        work = Task {
            do { let listing = try await store.directory(path); try check(token, job); directory = listing }
            catch { guard generation == token, operation == job else { return }; message = Self.operationMessage(error) }
            guard generation == token, operation == job else { return }
            deadline?.cancel(); busy = false; status = "Ready"
        }
    }
    func createFolder(_ name: String) {
        guard phase == .ready, connectionIsCurrent, !busy, let store, let directory, canAccess() else { return }
        do {
            let path = try DirectFilesPolicy.child(name, of: directory.path)
            let token = generation; operation = UUID(); let job = operation
            busy = true; message = nil; status = "Creating folder…"; armDeadline()
            work = Task {
                do { try await store.createDirectory(path); try check(token, job); let listing = try await store.directory(directory.path); try check(token, job); self.directory = listing }
                catch { guard generation == token, operation == job else { return }; message = Self.operationMessage(error) }
                guard generation == token, operation == job else { return }
                deadline?.cancel(); busy = false; status = "Ready"
            }
        } catch { message = error.localizedDescription }
    }
    private func root() throws -> URL {
        if let temporaryRoot { return temporaryRoot }
        let root = try DirectFilesLocalStore.root(); temporaryRoot = root; return root
    }
    func prepare(_ urls: [URL]) async throws -> [URL] {
        guard canAccess(), !closed, !Task.isCancelled else { throw CancellationError() }
        guard phase == .ready, !busy else { throw DirectFilesFailure.unavailable }
        guard !hasPendingResults else { throw DirectFilesFailure.pendingTransfers }
        guard (1...DirectFilesPolicy.maximumBatch).contains(urls.count) else { throw DirectFilesFailure.tooManyFiles }
        discardPreparedUploads()
        let root = try root(), token = generation
        busy = true; status = "Preparing files…"; message = nil
        let worker = Task.detached(priority: .userInitiated) { try DirectFilesLocalStore.stageBatch(urls, in: root) }
        stageWork = worker
        defer { if generation == token { busy = false; status = "Ready"; stageWork = nil } }
        let staged = try await worker.value
        do { try check(token) }
        catch { DirectFilesLocalStore.removeStaged(staged, in: root); throw error }
        preparedUploads = staged
        return staged
    }
    func discardPreparedUploads(_ urls: [URL]? = nil) {
        let removing = preparedUploads.filter { urls?.contains($0) ?? true }
        preparedUploads.removeAll { removing.contains($0) }
        if let temporaryRoot { DirectFilesLocalStore.removeStaged(removing, in: temporaryRoot) }
    }
    func upload(_ urls: [URL], to folder: String) {
        guard phase == .ready, connectionIsCurrent, !busy, canAccess(), (1...DirectFilesPolicy.maximumBatch).contains(urls.count), DirectFilesPolicy.validPath(folder) else { return }
        guard beginNewBatch() else { return }
        // Transfer results now own adopted sources. Release any unadopted review.
        preparedUploads.removeAll { urls.contains($0) }
        discardPreparedUploads()
        batch = .init(account: account, items: urls.map { .init(source: $0, remotePath: nil, folder: folder, name: $0.lastPathComponent) })
        runTransfers()
    }
    func download(_ entry: DirectFilesEntry) {
        guard phase == .ready, connectionIsCurrent, !busy, entry.kind == .file, let directory, canAccess(),
              let path = try? DirectFilesPolicy.child(entry.name, of: directory.path) else { return }
        guard beginNewBatch() else { return }
        discardPreparedUploads()
        batch = .init(account: account, items: [.init(source: nil, remotePath: path, folder: directory.path, name: entry.name)])
        runTransfers()
    }
    func retry(_ id: UUID) {
        guard phase == .ready, connectionIsCurrent, !busy, canAccess(), let index = results.firstIndex(where: { $0.id == id && $0.outcome == .interrupted }) else { return }
        guard account == resultsAccount else { message = "Reconnect as \(resultsAccount) to retry this transfer."; return }
        batch.items[index].outcome = .waiting; batch.items[index].bytes = 0; batch.items[index].message = "Waiting"; runTransfers()
    }
    private func runTransfers() {
        guard let store else { return }
        let token = generation; operation = UUID(); let job = operation
        batch.phase = .running(job)
        busy = true; message = nil; status = "Transferring"
        work = Task {
            for index in results.indices where batch.items[index].outcome == .waiting {
                do {
                    try check(token, job)
                    batch.items[index].outcome = .transferring; batch.items[index].message = batch.items[index].source == nil ? "Downloading" : "Uploading"; armDeadline()
                    let check: DirectFilesTransfer.Check = { try self.check(token, job) }
                    let progress: DirectFilesTransfer.Progress = { bytes, total in
                        guard self.generation == token, self.operation == job else { return }
                        self.batch.items[index].bytes = bytes; self.batch.items[index].total = total; self.armDeadline()
                    }
                    if let source = batch.items[index].source {
                        var name = batch.items[index].name; var replace = false
                        let path = try DirectFilesPolicy.child(name, of: batch.items[index].folder)
                        let attributes = try await store.attributes(path)
                        try check()
                        if let attrs = attributes {
                            deadline?.cancel()
                            let prompt = Conflict(name: name, replaceAllowed: attrs.kind == .file)
                            let choice = await withCheckedContinuation { reply in
                                batch.phase = .awaitingDecision(.init(prompt: prompt, job: job,
                                    item: batch.items[index].id, destination: path, reply: reply))
                            }
                            try check()
                            armDeadline()
                            switch choice {
                            case .cancel: throw CancellationError()
                            case .replace: guard attrs.kind == .file else { throw DirectFilesFailure.notRegular }; replace = true
                            case .keepBoth:
                                var found = false
                                for number in 2...1000 {
                                    let candidate = DirectFilesPolicy.duplicateName(name, number: number)
                                    let candidatePath = try DirectFilesPolicy.child(candidate, of: batch.items[index].folder)
                                    let candidateAttributes = try await store.attributes(candidatePath)
                                    try check()
                                    if candidateAttributes == nil { name = candidate; found = true; break }
                                }
                                guard found else { throw DirectFilesFailure.invalidName }
                            }
                        }
                        batch.items[index].destinationName = name
                        try await DirectFilesTransfer.upload(source: source, name: name, folder: batch.items[index].folder, replace: replace,
                                                             store: store, check: check, progress: progress)
                    } else if let path = batch.items[index].remotePath {
                        let target = try DirectFilesLocalStore.emptyFile(in: root(), name: batch.items[index].name)
                        try await DirectFilesTransfer.download(path: path, to: target, store: store, check: check, progress: progress)
                        try check(); batch.items[index].localDownload = target
                    }
                    try check(); batch.items[index].outcome = .completed
                    batch.items[index].message = batch.items[index].source == nil ? "Ready to save" : "Uploaded"
                } catch {
                    guard generation == token, operation == job else { return }
                    batch.items[index].outcome = .interrupted; batch.items[index].message = error is CancellationError ? "Cancelled · Retry when ready" : Self.operationMessage(error)
                    if error is CancellationError { break }
                }
            }
            guard generation == token, operation == job else { return }
            // Mark untouched queued files explicitly; retry never repeats completed files.
            for index in results.indices where batch.items[index].outcome == .waiting { batch.items[index].outcome = .interrupted; batch.items[index].message = "Not transferred" }
            batch.phase = .settled
            deadline?.cancel(); busy = false; status = "Ready"
            if let path = directory?.path { browse(path) }
        }
    }
    static func operationMessage(_ error: Error) -> String {
        if let status = error as? SFTPMessage.Status {
            switch status.errorCode {
            case .permissionDenied: return "This account cannot access that file or folder. Check permissions on the Mac."
            case .noSuchFile: return "The file or folder no longer exists. Refresh and try again."
            case .noConnection, .connectionLost: return "Connection interrupted. Reconnect and retry."
            default: return "The Mac could not finish this operation. Refresh and review the result before retrying."
            }
        }
        return (error as? DirectFilesFailure)?.localizedDescription ?? "The operation could not finish. Check available storage and permissions, then retry."
    }
    func markSaved(_ id: UUID) {
        guard canAccess(), let index = results.firstIndex(where: { $0.id == id }) else { return }
        batch.items[index].saved = true
        batch.items[index].message = "Saved"
    }
    private func beginNewBatch() -> Bool {
        guard !hasPendingResults else { message = DirectFilesFailure.pendingTransfers.localizedDescription; return false }
        discardResults()
        return true
    }
    func discardResults() {
        guard !closed, canAccess(), !busy else { return }
        if let temporaryRoot {
            for url in results.flatMap({ [$0.source, $0.localDownload].compactMap { $0 } }) {
                let folder = url.deletingLastPathComponent()
                // Remove only this owner's UUID staging folders, never picker
                // sources or files staged for a later upload review.
                if folder.deletingLastPathComponent().standardizedFileURL == temporaryRoot.standardizedFileURL {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
        batch = .init(); message = nil
    }
    @discardableResult func confirmExit(_ intent: DirectFilesExitIntent, retainWhenDismissed: Bool) -> Bool {
        if intent == .close && !retainWhenDismissed {
            // The user explicitly accepted losing pending results. Retire now
            // so native dismissal is enabled before requesting it.
            close()
            return true
        }
        disconnect(message: "Transfer stopped. Reconnect and Retry when ready.")
        return false
    }
    func pauseConnection(message: String) {
        guard phase == .connecting || phase == .ready else { return }
        disconnect(message: message)
    }
    func disconnect(message: String? = nil) {
        if case .ready(let connection) = connectionState, case .independent = connection.authority {
            loginDraft.passwordSessionEnded()
        }
        retire(); status = "Sign In Required"; self.message = message
        for index in results.indices where batch.items[index].outcome == .waiting || batch.items[index].outcome == .transferring {
            batch.items[index].outcome = .interrupted; batch.items[index].message = "Interrupted · Reconnect, then Retry. A temporary upload file may remain on the Mac."
        }
    }
    private func retire() {
        if !closed { connectionState = .interrupted(account: account) }
        connectionRecovery = nil
        #if os(iOS)
        let pendingWork = work
        #endif
        generation = UUID(); operation = UUID(); deadline?.cancel(); deadline = nil
        work?.cancel(); work = nil; stageWork?.cancel(); stageWork = nil
        discardPreparedUploads()
        let trust = trustReply; trustReply = nil; self.trust = nil; trust?.resume(returning: false)
        if case .awaitingDecision(let decision) = batch.phase { decision.reply.resume(returning: .cancel) }
        if transferActive { batch.phase = .settled }
        socket?.cancel(); socket = nil
        #if os(iOS)
        let lease = connectionLease; connectionLease = nil
        #endif
        let sftp = (store as? DirectFilesSFTPStore)?.client
        if sftp == nil { store?.close() }
        store = nil
        let old = ssh, channel = channel; ssh = nil; self.channel = nil
        Task {
            sftp?.setResponseActivityHandler(nil)
            try? await sftp?.close()
            try? await old?.close(); try? await channel?.close()
            #if os(iOS)
            await pendingWork?.value
            DirectMacConnections.shared.end(lease)
            #endif
        }
        busy = false
    }
    func close() {
        connectionState = .closed
        loginDraft.invalidate()
        backgroundObserver = nil
        removalObserver = nil
        disconnect()
        directory = nil; batch = .init(); home = ""
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }; temporaryRoot = nil
    }
    func endTemporarySession() {
        retireForDownloadRecovery(message: "This temporary connection ended. Save or discard your downloads to close Files.")
    }
    private func removedFromLibrary() {
        retireForDownloadRecovery(message: "This Mac was removed. Save or discard your downloads to close Files.")
    }
    private func retireForDownloadRecovery(message: String) {
        guard !closed, !macRemoved else { return }
        macRemoved = true
        backgroundObserver = nil
        removalObserver = nil
        loginDraft.invalidate()
        disconnect(message: message)
        directory = nil
        if !hasUnsavedDownloads { close() }
    }
}
#endif
