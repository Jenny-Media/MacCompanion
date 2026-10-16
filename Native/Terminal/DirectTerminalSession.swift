#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Crypto
import Observation
#if os(iOS)
import UIKit
#endif
@preconcurrency import Citadel
@preconcurrency import NIO
@preconcurrency import NIOSSH

final class TerminalSocketOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var descriptor: Int32 = -1
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func register(_ fd: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        guard !cancelled else { return false }
        if fd >= 0 { descriptor = dup(fd) }
        return true
    }
    func cancel() {
        lock.lock(); cancelled = true
        if descriptor >= 0 { shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor); descriptor = -1 }
        lock.unlock()
    }
    deinit { cancel() }
}

final class TerminalHostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let validate: @MainActor @Sendable (String) async throws -> Void
    init(validate: @escaping @MainActor @Sendable (String) async throws -> Void) { self.validate = validate }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = String(openSSHPublicKey: hostKey)
        Task { @MainActor in
            do { try await validate(key); validationCompletePromise.succeed(()) }
            catch { validationCompletePromise.fail(error) }
        }
    }
}

// The writer contains only NIO's thread-safe Channel and no mutable state.
private struct TerminalWriter: @unchecked Sendable {
    let value: TTYStdinWriter
    func write(_ bytes: [UInt8]) async throws { try await value.write(ByteBuffer(bytes: bytes)) }
    func resize(columns: Int, rows: Int) async throws { try await value.changeSize(cols: columns, rows: rows, pixelWidth: 0, pixelHeight: 0) }
}
enum TerminalConnectionFailure: Error, Equatable { case lookup, socket, setupResponse, pausedOutputLimit }

private enum TerminalPTY {
    nonisolated static func run(client: SSHClient, columns: Int, rows: Int,
        ready: @escaping @MainActor @Sendable (TerminalWriter) throws -> Void,
        output: @escaping @MainActor @Sendable ([UInt8]) throws -> Void) async throws -> Int? {
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(wantReply: true, term: "xterm-256color",
            terminalCharacterWidth: columns, terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: .init([.ECHO: 1]))
        return try await client.withPTY(request) { stream, writer in
            try await ready(TerminalWriter(value: writer))
            for try await item in stream {
                try Task.checkCancellation()
                switch item { case .stdout(let buffer), .stderr(let buffer): try await output(Array(buffer.readableBytesView)) }
            }
        }
    }
}

@MainActor @Observable final class DirectTerminalSession {
    static let maximumPausedOutputBytes = 1_048_576
    // Native windows admit input independently of other active scenes.
    var inputAvailable: @MainActor () -> Bool = { true }
    var suspendInput: (@MainActor () -> Void)?
    private(set) var suspended = false
    private(set) var activity: VNCSessionActivityController?
    private var pausedOutput: [UInt8] = []
    var pausedOutputByteCount: Int { pausedOutput.count }
    private var pauseWork: Task<Void, Never>?
    private var resumeWork: Task<Void, Never>?
    private var inputInactive = false
    private var readPauseCompleted = false
    private var pauseDeadline: Task<Void, Never>?
    #if os(iOS)
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var textSendNotice: DirectRecoveryNotice?
    func interruptComposedText() {
        textSendNotice = .init(reason: .inputPaused, title: "Check the sent text",
            message: "Sending text was interrupted. It may have been partially sent. Check your Mac before sending it again; input won’t be replayed.")
    }
    #endif
    private var lifecycleGeneration = UUID()
    private var writeGeneration = UUID()
    #if os(visionOS)
    var outputGeneration: UUID { generation }
    #endif
    #if os(macOS) || os(visionOS)
    private var nativeInputReleaseTail: Task<Void, Never>?
    private var nativeInputReleaseBytes = 0
    #endif
    private let activityDefaults: UserDefaults
    private let activityBackend: any RemoteSessionActivityBackend
    var reloadKeyboard: (@MainActor () -> Void)?
    var toggleKeyboard: (@MainActor () -> Void)?
    var keyboardVisible = false
    #if DEBUG
    // Hosted SSH tests can fail an advisory write before the peer's exit arrives.
    var resizeForTesting: ((Int, Int) async throws -> Void)?
    #endif
    struct TrustRequest: Identifiable { let id = UUID(); let fingerprint: String }
    private(set) var mac: DirectMacRecordV1
    private(set) var macRemoved = false
    @ObservationIgnored private var removalObserver: DirectMacRemovalObservation?
    var status = "Sign in to Remote Login"
    var connecting = false
    var connected = false
    private(set) var completedNormally = false
    var trust: TrustRequest?
    var installedKey: UUID?
    var recovery: DirectRecoveryNotice?
    var controlsRecovery: DirectRecoveryNotice?
    private(set) var setupPhase = TerminalSetupPhase.notSent
    private(set) var phase = "Ready"
    private var settingUp = false
    private var identityDetails: [DirectRecoveryNotice.Detail] = []
    static func reason(for error: Error, keyLogin: Bool) -> DirectRecoveryNotice.Reason {
        if let failure = error as? TerminalSecretStore.Failure {
            switch failure {
            case .changedKey: return .serverChanged
            case .rejectedKey: return .connectionCancelled
            case .locked, .storage: return .savedDataUnavailable
            case .network: return .macUnreachable
            }
        }
        if let failure = error as? TerminalConnectionFailure {
            switch failure { case .lookup: return .addressNotFound; case .socket: return .macUnreachable; case .setupResponse, .pausedOutputLimit: return .terminalConnection }
        }
        if let failure = error as? SSHClientError {
            switch failure {
            case .allAuthenticationOptionsFailed: return keyLogin ? .keyRejected : .loginRejected
            case .unsupportedPasswordAuthentication, .unsupportedPrivateKeyAuthentication, .unsupportedHostBasedAuthentication: return .unsupportedConnection
            case .channelCreationFailed: return .terminalConnection
            }
        }
        if error is AuthenticationFailed { return keyLogin ? .keyRejected : .loginRejected }
        return .terminalConnection
    }
    private func present(_ reason: DirectRecoveryNotice.Reason, message: String? = nil, stage: String? = nil) {
        #if os(iOS)
        let message = reason == .terminalEnded
            ? textSendNotice.map { (message ?? DirectRecoveryNotice.make(reason).message) + " " + $0.message } ?? message : message
        #endif
        recovery = .make(reason, message: message, details: (reason == .serverChanged ? identityDetails : []) + [.init(name: "Service", value: "Remote Login (SSH)"),
            .init(name: "SSH port", value: String(mac.sshPort)), .init(name: "Stage", value: stage ?? phase)])
        status = recovery?.title ?? ""
    }
    var setupProgress: String {
        switch setupPhase {
        case .notSent: return "Connecting for setup…"
        case .sent: return "Adding the public key…"
        case .acknowledged: return "Public key added · Testing key login…"
        case .verified: return "Key login verified · Saving preference…"
        }
    }
    private func presentSetupFailure(_ outcome: TerminalSetupPhase, cause: DirectRecoveryNotice.Reason? = nil, stage: String) {
        var message: String? = nil
        if let cause {
            let explanation = DirectRecoveryNotice.make(cause)
            if outcome == .acknowledged {
                message = "The public key is on this Mac, but the automatic key-only login test failed. " + explanation.message + " Your previous preferred login is kept."
            } else if outcome == .notSent {
                message = "No public key installation command was sent. " + explanation.message
            }
        }
        present(outcome.failure, message: message, stage: stage)
        if let cause { recovery?.details.append(.init(name: "Cause", value: DirectRecoveryNotice.make(cause).title)) }
    }
    func clearRecovery() { recovery = nil; status = "Sign in to Remote Login" }
    func cancelConnection() {
        let settingUp = self.settingUp, outcome = setupPhase, stage = phase
        stop()
        if settingUp { presentSetupFailure(outcome, stage: "Cancelled · " + stage) }
        else { present(.connectionCancelled, message: "The connection was cancelled. Your login fields are kept.", stage: stage) }
    }
    /// Cancel an active setup and keep its outcome visible before the sheet closes.
    func requestSetupDismissal() -> Bool {
        if connecting { cancelConnection(); return false }
        stop()
        return true
    }
    func testKeyLogin(username: String, target: TerminalNamedKey) {
        connect(username: username, password: "", remember: false, installation: target, verificationOnly: true)
    }
    var received: (([UInt8]) -> Void)?
    private var trustReply: CheckedContinuation<Bool, Never>?
    private var work: Task<Void, Never>?
    private var writeTail: Task<Void, Never>?
    private var queuedBytes = 0
    #if os(iOS)
    private var accessLease: UUID?
    #endif
    #if os(iOS) || os(macOS)
    private let accessOwnerID = UUID()
    private var authenticatedAccount = ""
    private var authenticatedKeyID: UUID?
    var filesContext: DirectFilesConnectionContext? {
        guard connected, let client, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return nil }
        let token = generation
        return .init(client: client, macID: mac.id, ownerID: accessOwnerID, account: authenticatedAccount, keyID: authenticatedKeyID, generation: token,
                     isCurrent: { [weak self] in
                         guard let self else { return false }
                         return self.connected && self.generation == token && !self.macRemoved &&
                             DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable
                     })
    }
    #endif
    private var client: SSHClient?
    private var channel: Channel?
    private var writer: TerminalWriter?
    private var socketOwner: TerminalSocketOwner?
    private var generation = UUID()
    private var columns = 80
    private var rows = 24
    init(mac: DirectMacRecordV1, activityDefaults: UserDefaults = .standard, activityBackend: any RemoteSessionActivityBackend = ActivityKitSessionBackend(),
         libraryURL: URL = DirectMacLibraryV1.defaultURL) {
        self.mac = mac; self.activityDefaults = activityDefaults; self.activityBackend = activityBackend
        removalObserver = DirectMacRemovalObservation(macID: mac.id, libraryURL: libraryURL) { [weak self] in
            guard let self else { return }
            self.macRemoved = true; self.stop()
        }
    }
    func updateMac(_ record: DirectMacRecordV1) { if record.id == mac.id { mac = record } }
    func connect(username: String, password: String, remember: Bool, key: TerminalSSHKey? = nil, installation: TerminalNamedKey? = nil, verificationOnly: Bool = false, keyFileID: UUID? = nil) {
        guard !macRemoved, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable, !connecting, !connected else { return }
        let loginKey = verificationOnly ? installation?.key : key
        #if os(iOS)
        if installation != nil, DirectMacConnections.shared.isActive(mac.id) {
            present(.savedDataUnavailable, message: "Disconnect this Mac before setting up an SSH key."); return
        }
        do { try DirectMacAccessStore.checkConnection(macID: mac.id, username: username, password: password, key: loginKey, ssh: true, ownerID: accessOwnerID) }
        catch { present(.savedDataUnavailable, message: "Disconnect this Mac before changing its login."); return }
        #endif
        guard !username.isEmpty, (loginKey != nil || !password.isEmpty), username.utf8.count <= 255, password.utf8.count <= 4096,
              !username.contains("\0"), !password.contains("\0") else { present(.loginRejected, message: "Enter a Mac account and password or choose an SSH key. Account names must be at most 255 UTF-8 bytes and passwords at most 4 KiB, with no NUL characters."); return }
        let authentication: @Sendable () -> SSHAuthenticationMethod
        if let key = loginKey {
            do { try key.validate(); let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)
                authentication = { .ed25519(username: username, privateKey: parsed) }
            } catch { present(.savedDataUnavailable, message: "The selected SSH key couldn’t be read. Existing keys are kept."); return }
        } else { authentication = { .passwordBased(username: username, password: password) } }
        #if os(macOS)
        let keyFileSelection: MacSSHKeyFileStore.LoginSelection?
        do {
            if installation == nil, let keyFileID, let key {
                keyFileSelection = try MacSSHKeyFileStore.loginSelection(fileID: keyFileID, macID: mac.id, fingerprint: key.fingerprint)
            } else { keyFileSelection = nil }
        } catch { present(.savedDataUnavailable, message: "The selected SSH key couldn’t be read. Existing keys are kept."); return }
        #endif
        #if os(iOS)
        do {
            if installation == nil && key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) }
        } catch { present(.savedDataUnavailable, message: "Disconnect this Mac before changing its saved login."); return }
        #endif
        stop()
        #if os(iOS) || os(macOS)
        authenticatedAccount = username
        #endif
        #if os(iOS)
        authenticatedKeyID = installation?.id ?? (key == nil ? nil : (try? DirectMacAccessStore.load(mac.id).keyID))
        accessLease = DirectMacConnections.shared.begin(macID: mac.id, kind: "terminal", keyID: authenticatedKeyID, ownerID: accessOwnerID,
            pendingAccessChange: installation != nil || DirectMacAccessStore.willRetainChange(macID: mac.id, username: username, password: password, key: loginKey, ssh: true, remember: remember), disconnect: { [weak self] in self?.stop() })
        textSendNotice = nil
        #endif
        identityDetails = []; installedKey = nil; recovery = nil; phase = "Contacting Mac"; setupPhase = .notSent; settingUp = installation != nil; let id = UUID(); generation = id
        let owner = TerminalSocketOwner(); socketOwner = owner
        connecting = true; phase = "Finding a reachable address"; status = "Contacting Remote Login…"
        let addresses = mac.addresses, port = mac.sshPort
        work = Task {
            do {
                #if !os(iOS)
                if installation == nil && key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) }
                #endif
                let client = try await dial(addresses: addresses, port: port, authentication: authentication, owner: owner, id: id)
                self.client = client
                if let installation {
                    let deadline = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        guard let self, self.generation == id else { return }
                        let outcome = self.setupPhase, stage = self.phase; self.stop(); self.presentSetupFailure(outcome, stage: "Timed out · " + stage)
                    }
                    defer { deadline.cancel() }
                    if !verificationOnly {
                        self.phase = "Adding the public key"; self.status = "Installing public key…"
                        self.setupPhase = .sent
                        let result = try await client.executeCommand(TerminalKeyInstallation.command(for: installation), maxResponseSize: 128)
                        let marker = String(decoding: result.readableBytesView, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard ["MC_KEY_INSTALLED", "MC_KEY_PRESENT"].contains(marker) else { throw TerminalConnectionFailure.setupResponse }
                        guard self.generation == id else { throw CancellationError() }
                        self.setupPhase = .acknowledged
                        let endpoint = self.channel?.remoteAddress?.ipAddress
                        try await client.close(); self.client = nil; self.channel = nil
                        self.phase = "Testing key login"; self.status = "Verifying key login…"
                        let target = try Curve25519.Signing.PrivateKey(rawRepresentation: installation.key.seed)
                        let verification = try await dial(addresses: endpoint.map { [$0] } ?? addresses, port: port,
                            authentication: { .ed25519(username: username, privateKey: target) }, owner: owner, id: id)
                        self.client = verification
                    }
                    self.setupPhase = .verified; self.phase = "Saving the preferred key"
                    guard self.generation == id, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
                    #if os(iOS)
                    if let owner = accessLease, DirectMacConnections.shared.owns(owner, macID: mac.id) {
                        var profile = try DirectMacAccessStore.load(mac.id)
                        profile.keyID = installation.id; profile.keyUsername = username; profile.sshMethod = .key
                        try DirectMacAccessStore.write(profile, id: mac.id)
                    }
                    #else
                    try TerminalKeyLibraryStore.associate(installation.id, macID: mac.id, username: username)
                    #endif
                    stop(); installedKey = installation.id; present(.setupVerified, stage: "Key-only login verified; preference saved")
                    return
                }
                var savedFileReference = false
                #if os(macOS)
                if keyFileID != nil, key != nil {
                    if let keyFileSelection { try MacSSHKeyFileStore.rememberAccount(username, selection: keyFileSelection) }
                    // Even if its association changed, never import a disk key
                    // through the legacy named-key retention path below.
                    savedFileReference = true
                }
                #endif
                if !savedFileReference {
                    #if os(iOS)
                    if let owner = accessLease {
                        if key != nil { try DirectMacAccessStore.retainKeyAccount(username, macID: mac.id, keyID: authenticatedKeyID, owner: owner) }
                        else if remember { try DirectMacAccessStore.retain(.init(username: username, password: password), macID: mac.id, ssh: true, owner: owner) }
                    }
                    #else
                    if var key { key.username = username; try TerminalSecretStore.saveKey(key, id: mac.id) }
                    else if remember { try TerminalSecretStore.save(.init(username: username, password: password), id: mac.id) }
                    #endif
                }
                self.phase = "Opening a new shell"
                let exitStatus = try await TerminalPTY.run(client: client, columns: columns, rows: rows, ready: { writer in
                    guard self.generation == id, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { throw CancellationError() }
                    self.writer = writer; self.connected = true; self.connecting = false; self.status = "Connected"; self.phase = "Shell open"; self.recovery = nil
                    self.activity = VNCSessionActivityController(mac: self.mac, kind: .terminal, defaults: self.activityDefaults, backend: self.activityBackend)
                    self.activity?.setPhase("connected")
                }, output: { bytes in
                    guard self.generation == id else { throw CancellationError() }
                    try self.receiveOutput(bytes)
                })
                guard generation == id else { return }
                stop()
                if exitStatus == 0 { completedNormally = true }
                else { present(.terminalEnded, message: "The connection closed unexpectedly. Open a new shell to continue.") }
            } catch {
                guard generation == id else { return }
                let stage = phase, outcome = setupPhase, wasConnected = connected
                stop()
                let reason = Self.reason(for: error, keyLogin: loginKey != nil || outcome == .acknowledged || outcome == .verified)
                if [.serverChanged, .connectionCancelled, .savedDataUnavailable].contains(reason) {
                    if installation != nil && outcome.mayBeInstalled && reason == .savedDataUnavailable { presentSetupFailure(outcome, cause: reason, stage: stage) }
                    else { present(reason, stage: stage) }
                } else if installation != nil && !verificationOnly {
                    presentSetupFailure(outcome, cause: reason, stage: stage)
                } else if error as? TerminalConnectionFailure == .pausedOutputLimit {
                    present(.terminalEnded, message: "The shell produced more output than could be kept while paused. Open a new shell to continue; previous input won’t be replayed.", stage: stage)
                } else if wasConnected {
                    let message = error is SSHClient.CommandFailed ? "The shell ended with an error. Open a new shell to continue."
                        : error is SSHClient.CommandSignalled ? "The shell was interrupted. Open a new shell to continue."
                        : "The connection was lost. Open a new shell to continue."
                    present(.terminalEnded, message: message, stage: stage)
                }
                else { present(reason, stage: stage) }
            }
        }
    }
    private func dial(addresses: [String], port: Int, authentication: @escaping @Sendable () -> SSHAuthenticationMethod,
                      owner: TerminalSocketOwner, id: UUID) async throws -> SSHClient {
        let connection = await Task.detached(priority: .userInitiated) {
            var failure = 0
            let fd = CompanionVNCConnectAddresses(addresses, port, { owner.isCancelled }, { owner.register($0) }, nil, &failure)
            return (fd, failure)
        }.value
        let (socket, failure) = connection
        guard socket >= 0 else {
            if owner.isCancelled { throw CancellationError() }
            throw failure == 10 ? TerminalConnectionFailure.lookup : TerminalConnectionFailure.socket
        }
        let fd = socket
        phase = "SSH handshake"
        if owner.isCancelled || generation != id { Darwin.close(fd); throw CancellationError() }
        // The server can send its banner as soon as this socket is registered.
        // Keep it queued until Citadel has installed its SSH parser.
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelOption(ChannelOptions.autoRead, value: false).withConnectedSocket(fd).get()
        guard generation == id, !Task.isCancelled else { try? await channel.close(); throw CancellationError() }
        self.channel = channel
        let validator = TerminalHostValidator { [weak self] key in
            guard let self, self.generation == id, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
            self.phase = "Verifying SSH server identity"
            if let saved = try TerminalSecretStore.hostKey(self.mac.id) {
                guard saved == key else {
                    self.identityDetails = [.init(name: "Previously trusted", value: TerminalSecretStore.fingerprint(saved) ?? "Unavailable"), .init(name: "Presented by server", value: TerminalSecretStore.fingerprint(key) ?? "Unavailable")]
                    throw TerminalSecretStore.Failure.changedKey
                }; self.phase = "Signing in"; return
            }
            guard let fingerprint = TerminalSecretStore.fingerprint(key) else { throw TerminalSecretStore.Failure.rejectedKey }
            self.trust = .init(fingerprint: fingerprint)
            let accepted = await withCheckedContinuation { self.trustReply = $0 }
            self.trust = nil
            guard accepted, self.generation == id, DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.rejectedKey }
            try TerminalSecretStore.approveHostKey(key, id: self.mac.id)
            self.phase = "Signing in"
        }
        var settings = SSHClientSettings(host: addresses.first ?? mac.address, port: port,
            authenticationMethod: authentication, hostKeyValidator: .custom(validator))
        settings.connectTimeout = .seconds(60)
        let client = try await SSHClient.connect(on: channel, settings: settings)
        guard generation == id, !Task.isCancelled else { try? await client.close(); throw CancellationError() }
        return client
    }
    func answerTrust(_ accepted: Bool) {
        let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: accepted)
        if !accepted, reply != nil { stop(); present(.connectionCancelled) }
    }
    enum OutputSource { case userInput, emulatorReply }
    private func admits(_ source: OutputSource) -> Bool {
        #if os(visionOS)
        VisionTerminalAdmission.allows(focused: inputAvailable(), emulatorReply: source == .emulatorReply,
                                      suspended: suspended, unlocked: DirectAppLockV1.shared.canAccess)
        #else
        !inputInactive && !suspended && DirectAppLockV1.shared.canAccess && inputAvailable()
        #endif
    }
    func send(_ data: [UInt8], source: OutputSource = .userInput) {
        guard admits(source), connected, DirectClientPlatformV1.sessionAvailable, let writer, !data.isEmpty else { return }
        #if os(macOS) || os(visionOS)
        let releasingBytes = nativeInputReleaseBytes
        #else
        let releasingBytes = 0
        #endif
        guard data.count <= 65536, queuedBytes + releasingBytes + data.count <= 65536 else { stop(); present(.inputPaused); return }
        queuedBytes += data.count; let id = generation, writeID = writeGeneration; let previous = writeTail
        #if os(macOS) || os(visionOS)
        let previousRelease = nativeInputReleaseTail
        #endif
        writeTail = Task {
            await previous?.value
            #if os(macOS) || os(visionOS)
            await previousRelease?.value
            #endif
            defer { if generation == id && writeGeneration == writeID { queuedBytes -= data.count } }
            guard admits(source), generation == id, writeGeneration == writeID, !Task.isCancelled, DirectClientPlatformV1.sessionAvailable else { return }
            do { try await writer.write(data) }
            catch { if generation == id && writeGeneration == writeID { stop(); present(.terminalEnded, message: "The connection ended while sending input. It won’t be replayed. Open a new shell to continue.") } }
        }
    }
    #if os(iOS)
    var composeGeneration: UUID { generation }
    var canComposeText: Bool { connected && !inputInactive && !suspended && DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable && writer != nil }
    /// Use the same PTY and write ordering as live typing. A completion confirms
    /// only the local write; the remote program supplies no consumption receipt.
    func sendComposedText(_ data: [UInt8], generation expected: UUID, completion: @escaping (String?) -> Void) {
        guard generation == expected, canComposeText, let writer, !data.isEmpty else {
            completion("The Terminal session changed. Nothing was sent."); return
        }
        guard data.count <= 4108, queuedBytes + data.count <= 65536 else {
            completion("Input is busy or the text is too large. Nothing was queued."); return
        }
        queuedBytes += data.count
        let id = generation, writeID = writeGeneration, previous = writeTail
        writeTail = Task {
            await previous?.value
            defer { if generation == id && writeGeneration == writeID { queuedBytes -= data.count } }
            guard generation == id, writeGeneration == writeID, canComposeText, !Task.isCancelled else {
                completion("Sending was interrupted. Check the Terminal before sending again."); return
            }
            do {
                try await writer.write(data)
                guard generation == id, writeGeneration == writeID else {
                    completion("Text may have been partially sent. Check the Terminal before sending again."); return
                }
                completion(nil)
            } catch {
                completion("Text may have been partially sent. Check the Terminal before sending again.")
                if generation == id && writeGeneration == writeID {
                    stop(); present(.terminalEnded, message: "The connection ended while sending text. It may have been partially sent and won’t be replayed. Check the Mac before opening a new shell.")
                }
            }
        }
    }
    #endif
    #if os(macOS) || os(visionOS)
    // This type is constructed only by the native owner ledger. Cleanup is
    // allowed after focus/lock, but remains bounded and tied to this generation.
    func releaseNativeInput(_ releases: MacTerminalInputReleases) {
        let data = releases.packets.flatMap { $0 }
        guard connected, let writer, !data.isEmpty else { return }
        guard data.count <= 16384, queuedBytes + nativeInputReleaseBytes + data.count <= 65536 else { failNativeInputAdmission(); return }
        let id = generation, previous = writeTail, previousRelease = nativeInputReleaseTail
        nativeInputReleaseBytes += data.count
        nativeInputReleaseTail = Task {
            await previous?.value; await previousRelease?.value
            guard generation == id, connected, !Task.isCancelled else { return }
            defer { if generation == id { nativeInputReleaseBytes -= data.count } }
            do { try await writer.write(data) }
            catch { if generation == id { stop(); present(.terminalEnded, message: "The Terminal ended while releasing held input. Open a new shell to continue.") } }
        }
    }
    func failNativeInputAdmission() { stop(); present(.inputPaused) }
    #endif
    func resize(columns: Int, rows: Int) {
        self.columns = max(1, min(500, columns)); self.rows = max(1, min(500, rows))
        guard !inputInactive, inputAvailable(), let writer, connected, !suspended, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
        let cols = self.columns, rows = self.rows, id = generation, writeID = writeGeneration
        let previous = writeTail
        #if os(macOS) || os(visionOS)
        let previousRelease = nativeInputReleaseTail
        #endif
        writeTail = Task {
            await previous?.value
            #if os(macOS) || os(visionOS)
            await previousRelease?.value
            #endif
            guard !inputInactive, inputAvailable(), generation == id, writeGeneration == writeID, !suspended, !Task.isCancelled,
                DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
            // A closing PTY may reject window-change before the reader drains
            // its exit status. This advisory write must not cancel that reader;
            // it owns normal exit versus transport-loss classification.
            try? await writeSize(writer, columns: cols, rows: rows)
        }
    }
    private func writeSize(_ writer: TerminalWriter, columns: Int, rows: Int) async throws {
        #if DEBUG
        if let resizeForTesting { try await resizeForTesting(columns, rows); return }
        #endif
        try await writer.resize(columns: columns, rows: rows)
    }
    func stop() {
        inputInactive = false; readPauseCompleted = false
        lifecycleGeneration = UUID(); writeGeneration = UUID()
        pauseWork?.cancel(); pauseWork = nil; resumeWork?.cancel(); resumeWork = nil; finishBackgroundWork()
        suspended = false; pausedOutput.removeAll(keepingCapacity: false)
        suspendInput?(); activity?.finish(); activity = nil
        let pendingConnection = work
        generation = UUID(); let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: false); work?.cancel(); work = nil; writeTail?.cancel(); writeTail = nil
        #if os(macOS) || os(visionOS)
        nativeInputReleaseTail?.cancel(); nativeInputReleaseTail = nil; nativeInputReleaseBytes = 0
        #endif
        socketOwner?.cancel(); socketOwner = nil
        let client = self.client, channel = self.channel; self.client = nil; self.channel = nil; writer = nil
        connected = false; connecting = false; completedNormally = false; queuedBytes = 0
        #if os(iOS)
        let lease = accessLease; accessLease = nil
        #endif
        #if os(iOS) || os(macOS)
        authenticatedAccount = ""; authenticatedKeyID = nil
        #endif
        Task {
            try? await client?.close(); try? await channel?.close()
            await pendingConnection?.value
            #if os(iOS)
            DirectMacConnections.shared.end(lease)
            #endif
        }
    }
    func receiveOutput(_ bytes: [UInt8]) throws {
        guard !inputInactive, !suspended, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else {
            // A brief inactive transition can retain reads while buffering UI
            // output. Actual background/lock entry separately pauses the channel.
            if !suspended && !(inputInactive && DirectAppLockV1.shared.canAccess) { background() }
            guard bytes.count <= Self.maximumPausedOutputBytes - pausedOutput.count else { throw TerminalConnectionFailure.pausedOutputLimit }
            pausedOutput.append(contentsOf: bytes); return
        }
        if !pausedOutput.isEmpty { let pending = pausedOutput; pausedOutput.removeAll(keepingCapacity: false); received?(pending) }
        received?(bytes)
        if !bytes.isEmpty { activity?.setPhase("connected") }
    }
    func becameInactive() {
        if connecting { cancelConnection(); return }
        guard connected, !inputInactive else { return }
        inputInactive = true; writeGeneration = UUID(); writeTail?.cancel(); writeTail = nil; queuedBytes = 0
        suspendInput?()
    }
    func background() {
        if connecting { cancelConnection(); return }
        guard connected, !suspended || resumeWork != nil else { return }
        suspended = true; lifecycleGeneration = UUID(); let token = lifecycleGeneration
        inputInactive = true; readPauseCompleted = false
        writeGeneration = UUID(); writeTail?.cancel()
        resumeWork?.cancel(); resumeWork = nil; suspendInput?()
        writeTail = nil; queuedBytes = 0
        activity?.setForeground(false); activity?.setPhase("paused")
        let readPause = channel?.setOption(ChannelOptions.autoRead, value: false)
        #if os(iOS)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Pause SSH session") { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lifecycleGeneration == token else { return }
                if !self.readPauseCompleted { self.stop(); self.present(.terminalEnded) }
                self.finishBackgroundWork()
            }
        }
        #endif
        pauseWork = Task { [weak self] in
            do { try await readPause?.get() } catch {
                guard let self, self.lifecycleGeneration == token else { return }
                self.stop(); self.present(.terminalEnded); return
            }
            guard let self, self.lifecycleGeneration == token else { return }
            self.readPauseCompleted = true
            // ActivityKit must not be on the transport-resume dependency chain.
            Task { [weak self, activity = self.activity] in
                await activity?.waitForUpdates()
                guard let self, self.lifecycleGeneration == token else { return }
                self.finishBackgroundWork()
            }
        }
        pauseDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.lifecycleGeneration == token else { return }
            if !self.readPauseCompleted { self.stop(); self.present(.terminalEnded) }
            self.finishBackgroundWork()
        }
    }
    func foreground() {
        guard connected, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
        let wasInactive = inputInactive
        inputInactive = false
        activity?.setForeground(true)
        guard suspended else {
            do { try receiveOutput([]) } catch { stop(); present(.terminalEnded); return }
            if wasInactive { resize(columns: columns, rows: rows) }
            activity?.setPhase("connected", verified: false); return
        }
        guard resumeWork == nil else { return }
        lifecycleGeneration = UUID(); let token = lifecycleGeneration, id = generation
        finishBackgroundWork(); let previousPause = pauseWork
        resumeWork = Task { [weak self] in
            await previousPause?.value
            guard let self else { return }
            defer { if self.lifecycleGeneration == token { self.resumeWork = nil } }
            guard self.generation == id, self.lifecycleGeneration == token,
                  self.connected, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
            guard let channel = self.channel, channel.isActive else { self.stop(); self.present(.terminalEnded); return }
            do {
                try await channel.setOption(ChannelOptions.autoRead, value: true).get()
                guard self.generation == id, self.lifecycleGeneration == token, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
                self.suspended = false; try self.receiveOutput([])
                self.resize(columns: self.columns, rows: self.rows)
                self.activity?.setPhase("connected", verified: false)
            } catch {
                if self.generation == id && self.lifecycleGeneration == token { self.stop(); self.present(.terminalEnded) }
            }
        }
    }
    func endActivity(_ id: String) -> Bool {
        guard activity?.ownsActivity(id) == true else { return false }
        stop(); return true
    }
    func waitForLifecycleUpdates() async {
        await pauseWork?.value; await resumeWork?.value; await activity?.waitForUpdates()
    }
    private func finishBackgroundWork() {
        pauseDeadline?.cancel(); pauseDeadline = nil
        #if os(iOS)
        if backgroundTask != .invalid { let task = backgroundTask; backgroundTask = .invalid; UIApplication.shared.endBackgroundTask(task) }
        #endif
    }
}
#endif
