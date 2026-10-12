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
    enum ConflictChoice { case keepBoth, replace, cancel }
    struct Trust: Identifiable { let id = UUID(); let fingerprint: String }
    struct Conflict: Identifiable { let id = UUID(); let name: String; let replaceAllowed: Bool }
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
    private(set) var account = ""
    private(set) var phase: Phase = .signIn
    @ObservationIgnored var activityChanged: (@MainActor (String) -> Void)?
    private(set) var status = "Sign In Required" { didSet { activityChanged?(activityTitle) } }
    private(set) var directory: DirectFilesDirectory?
    private(set) var home = ""
    private(set) var results: [ResultItem] = [] { didSet { activityChanged?(activityTitle) } }
    private(set) var resultsAccount = ""
    private(set) var preparedUploads: [URL] = []
    private(set) var busy = false
    var message: String?
    var trust: Trust?
    var conflict: Conflict?
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
    private var conflictReply: CheckedContinuation<ConflictChoice, Never>?
    private var temporaryRoot: URL?
    @ObservationIgnored private var backgroundObserver: DirectFilesBackgroundObservation?
    private var closed = false
    var isClosed: Bool { closed }
    private(set) var macRemoved = false
    var shouldCloseAfterRemoval: Bool { macRemoved && !hasUnsavedDownloads }
    @ObservationIgnored private var removalObserver: DirectMacRemovalObservation?
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
        removalObserver = DirectMacRemovalObservation(macID: mac.id, libraryURL: libraryURL) { [weak self] in self?.removedFromLibrary() }
    }
    private func observeLifecycle() {
        guard backgroundObserver == nil else { return }
        observeAccess()
        backgroundObserver = DirectFilesBackgroundObservation { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.closed, !self.macRemoved else { return }
                self.loginDraft.suspend()
                self.disconnect(message: "Files paused. Reconnect, then Retry any interrupted transfer.")
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
                    self.disconnect(message: "Files stopped when the app locked. Reconnect after unlocking.")
                }
                self.observeAccess()
            }
        }
    }
    var transferActive: Bool { results.contains { $0.outcome == .transferring || $0.outcome == .waiting } && busy }
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
        guard !closed, !macRemoved, generation == token, job == nil || operation == job, canAccess(), !Task.isCancelled else { throw CancellationError() }
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
    func connect(username: String, password: String, key: TerminalSSHKey?, remember: Bool, keyFileID: UUID? = nil) {
        guard !closed, !macRemoved, canAccess(), !busy, phase != .ready else { return }
        guard !username.isEmpty, username.utf8.count <= 255, !username.contains("\0"),
              (key != nil || !password.isEmpty), password.utf8.count <= 4096, !password.contains("\0") else {
            message = "Enter a Mac account and password, or choose its SSH key."; return
        }
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
        observeLifecycle()
        retire(); let token = generation, owner = TerminalSocketOwner(); socket = owner
        phase = .connecting; busy = true; account = username; message = nil; status = "Contacting Remote Login…"; armDeadline(after: .seconds(60))
        let addresses = mac.addresses, port = mac.sshPort
        work = Task {
            do {
                do { if key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) } }
                catch {
                    retire(); phase = .interrupted; status = "Sign In Required"
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
                    if let saved = try TerminalSecretStore.hostKey(self.mac.id) {
                        guard saved == publicKey else { throw TerminalSecretStore.Failure.changedKey }; return
                    }
                    guard let fingerprint = TerminalSecretStore.fingerprint(publicKey) else { throw TerminalSecretStore.Failure.rejectedKey }
                    self.status = "Verify this Mac’s identity"; self.trust = .init(fingerprint: fingerprint)
                    let accepted = await withCheckedContinuation { self.trustReply = $0 }
                    self.trust = nil; try self.check(token)
                    guard accepted else { throw TerminalSecretStore.Failure.rejectedKey }
                    try TerminalSecretStore.approveHostKey(publicKey, id: self.mac.id)
                }
                var settings = SSHClientSettings(host: addresses.first ?? "", port: port,
                    authenticationMethod: authentication, hostKeyValidator: .custom(validator))
                settings.connectTimeout = .seconds(60)
                let ssh = try await SSHClient.connect(on: channel, settings: settings)
                do { try check(token) } catch { try? await ssh.close(); throw error }; self.ssh = ssh
                self.status = "Opening Files…"; self.armDeadline()
                let logger = Logger(label: "Files", factory: { _ in SwiftLogNoOpLogHandler() })
                let client = try await ssh.openSFTP(logger: logger)
                try check(token)
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
                    do { try saveLogin(login, mac.id); retention = .saved }
                    catch { retention = .failed; throw error }
                }
                } catch { self.message = "Connected. The SSH login could not be saved on this device." }
                loginDraft.authenticationSucceeded(attempt, retention: retention)
                self.directory = directory; self.home = directory.path
                self.deadline?.cancel(); self.busy = false; self.phase = .ready; self.status = "Ready"
                channel.closeFuture.whenComplete { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.disconnect(message: "Files connection lost. Reconnect to continue; transfers will not restart automatically.")
                    }
                }
            } catch {
                guard generation == token else { return }
                let openingFiles = ssh != nil
                retire(); phase = .interrupted
                if let failure = error as? TerminalSecretStore.Failure, failure == .changedKey {
                    message = "The Mac’s SSH identity changed. Verify it before reconnecting. Existing trust is kept."
                } else if let failure = error as? TerminalSecretStore.Failure, failure == .rejectedKey {
                    message = "Server identity was not approved. No file connection was opened."
                } else if DirectTerminalSession.reason(for: error, keyLogin: key != nil) == .loginRejected || DirectTerminalSession.reason(for: error, keyLogin: key != nil) == .keyRejected {
                    message = "Remote Login did not accept this account or key. Check the login and allowed users on the Mac."
                } else if openingFiles { message = "SSH connected, but Files could not open. Check SFTP availability and this account’s folder permissions." }
                else { message = "Couldn’t connect to Remote Login. Check the network, saved SSH port and Remote Login settings on your Mac." }
                status = "Sign In Required"
            }
        }
    }
    func answerTrust(_ accepted: Bool) { let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: accepted && canAccess()) }
    func answerConflict(_ choice: ConflictChoice) {
        let reply = conflictReply; conflictReply = nil; conflict = nil
        reply?.resume(returning: canAccess() ? choice : .cancel)
    }
    func browse(_ path: String) {
        guard phase == .ready, !busy, let store, canAccess() else { return }
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
        guard phase == .ready, !busy, let store, let directory, canAccess() else { return }
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
        guard phase == .ready, !busy, canAccess(), (1...DirectFilesPolicy.maximumBatch).contains(urls.count), DirectFilesPolicy.validPath(folder) else { return }
        guard beginNewBatch() else { return }
        // Transfer results now own adopted sources. Release any unadopted review.
        preparedUploads.removeAll { urls.contains($0) }
        discardPreparedUploads()
        resultsAccount = account
        results = urls.map { .init(source: $0, remotePath: nil, folder: folder, name: $0.lastPathComponent) }
        runTransfers()
    }
    func download(_ entry: DirectFilesEntry) {
        guard phase == .ready, !busy, entry.kind == .file, let directory, canAccess(),
              let path = try? DirectFilesPolicy.child(entry.name, of: directory.path) else { return }
        guard beginNewBatch() else { return }
        discardPreparedUploads()
        resultsAccount = account
        results = [.init(source: nil, remotePath: path, folder: directory.path, name: entry.name)]
        runTransfers()
    }
    func retry(_ id: UUID) {
        guard phase == .ready, !busy, canAccess(), let index = results.firstIndex(where: { $0.id == id && $0.outcome == .interrupted }) else { return }
        guard account == resultsAccount else { message = "Reconnect as \(resultsAccount) to retry this transfer."; return }
        results[index].outcome = .waiting; results[index].bytes = 0; results[index].message = "Waiting"; runTransfers()
    }
    private func runTransfers() {
        guard let store else { return }
        let token = generation; operation = UUID(); let job = operation
        busy = true; message = nil; status = "Transferring"
        work = Task {
            for index in results.indices where results[index].outcome == .waiting {
                do {
                    try check(token, job)
                    results[index].outcome = .transferring; results[index].message = results[index].source == nil ? "Downloading" : "Uploading"; armDeadline()
                    let check: DirectFilesTransfer.Check = { try self.check(token, job) }
                    let progress: DirectFilesTransfer.Progress = { bytes, total in
                        guard self.generation == token, self.operation == job else { return }
                        self.results[index].bytes = bytes; self.results[index].total = total; self.armDeadline()
                    }
                    if let source = results[index].source {
                        var name = results[index].name; var replace = false
                        let path = try DirectFilesPolicy.child(name, of: results[index].folder)
                        let attributes = try await store.attributes(path)
                        try check()
                        if let attrs = attributes {
                            deadline?.cancel()
                            conflict = .init(name: name, replaceAllowed: attrs.kind == .file)
                            let choice = await withCheckedContinuation { conflictReply = $0 }; try check()
                            armDeadline()
                            switch choice {
                            case .cancel: throw CancellationError()
                            case .replace: guard attrs.kind == .file else { throw DirectFilesFailure.notRegular }; replace = true
                            case .keepBoth:
                                var found = false
                                for number in 2...1000 {
                                    let candidate = DirectFilesPolicy.duplicateName(name, number: number)
                                    let candidatePath = try DirectFilesPolicy.child(candidate, of: results[index].folder)
                                    let candidateAttributes = try await store.attributes(candidatePath)
                                    try check()
                                    if candidateAttributes == nil { name = candidate; found = true; break }
                                }
                                guard found else { throw DirectFilesFailure.invalidName }
                            }
                        }
                        results[index].destinationName = name
                        try await DirectFilesTransfer.upload(source: source, name: name, folder: results[index].folder, replace: replace,
                                                             store: store, check: check, progress: progress)
                    } else if let path = results[index].remotePath {
                        let target = try DirectFilesLocalStore.emptyFile(in: root(), name: results[index].name)
                        try await DirectFilesTransfer.download(path: path, to: target, store: store, check: check, progress: progress)
                        try check(); results[index].localDownload = target
                    }
                    try check(); results[index].outcome = .completed
                    results[index].message = results[index].source == nil ? "Ready to save" : "Uploaded"
                } catch {
                    guard generation == token, operation == job else { return }
                    results[index].outcome = .interrupted; results[index].message = error is CancellationError ? "Cancelled · Retry when ready" : Self.operationMessage(error)
                    if error is CancellationError { break }
                }
            }
            guard generation == token, operation == job else { return }
            // Mark untouched queued files explicitly; retry never repeats completed files.
            for index in results.indices where results[index].outcome == .waiting { results[index].outcome = .interrupted; results[index].message = "Not transferred" }
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
        results[index].saved = true
        results[index].message = "Saved"
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
        results = []; resultsAccount = ""; message = nil
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
    func disconnect(message: String? = nil) {
        retire(); phase = .interrupted; status = "Sign In Required"; self.message = message
        for index in results.indices where results[index].outcome == .waiting || results[index].outcome == .transferring {
            results[index].outcome = .interrupted; results[index].message = "Interrupted · Reconnect, then Retry. A temporary upload file may remain on the Mac."
        }
    }
    private func retire() {
        generation = UUID(); operation = UUID(); deadline?.cancel(); deadline = nil
        work?.cancel(); work = nil; stageWork?.cancel(); stageWork = nil
        discardPreparedUploads()
        let trust = trustReply; trustReply = nil; self.trust = nil; trust?.resume(returning: false)
        let conflict = conflictReply; conflictReply = nil; self.conflict = nil; conflict?.resume(returning: .cancel)
        socket?.cancel(); socket = nil
        store?.close(); store = nil
        let old = ssh, channel = channel; ssh = nil; self.channel = nil
        Task { try? await old?.close(); try? await channel?.close() }
        busy = false
    }
    func close() {
        closed = true
        loginDraft.invalidate()
        backgroundObserver = nil
        removalObserver = nil
        disconnect()
        directory = nil; results = []; resultsAccount = ""; account = ""; home = ""
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }; temporaryRoot = nil
    }
    private func removedFromLibrary() {
        guard !closed, !macRemoved else { return }
        macRemoved = true
        backgroundObserver = nil
        removalObserver = nil
        loginDraft.invalidate()
        disconnect(message: "This Mac was removed. Save or discard your downloads to close Files.")
        directory = nil
        if !hasUnsavedDownloads { close() }
    }
}
#endif
