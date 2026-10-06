#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Crypto
import Observation
import UIKit
@preconcurrency import Citadel
@preconcurrency import NIO
@preconcurrency import NIOSSH

private final class TerminalSocketOwner: @unchecked Sendable {
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
enum TerminalConnectionFailure: Error { case lookup, socket, setupResponse }

private enum TerminalPTY {
    nonisolated static func run(client: SSHClient, columns: Int, rows: Int,
        ready: @escaping @MainActor @Sendable (TerminalWriter) throws -> Void,
        output: @escaping @MainActor @Sendable ([UInt8]) throws -> Void) async throws {
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(wantReply: true, term: "xterm-256color",
            terminalCharacterWidth: columns, terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: .init([.ECHO: 1]))
        try await client.withPTY(request) { stream, writer in
            try await ready(TerminalWriter(value: writer))
            for try await item in stream {
                try Task.checkCancellation()
                switch item { case .stdout(let buffer), .stderr(let buffer): try await output(Array(buffer.readableBytesView)) }
            }
        }
    }
}

@MainActor @Observable final class DirectTerminalSession {
    var reloadKeyboard: (@MainActor () -> Void)?
    var toggleKeyboard: (@MainActor () -> Void)?
    var keyboardVisible = false
    struct TrustRequest: Identifiable { let id = UUID(); let fingerprint: String }
    private(set) var mac: DirectMacRecordV1
    var status = "Sign in to Remote Login"
    var connecting = false
    var connected = false
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
            switch failure { case .lookup: return .addressNotFound; case .socket: return .macUnreachable; case .setupResponse: return .terminalConnection }
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
    func testKeyLogin(username: String, target: TerminalNamedKey) {
        connect(username: username, password: "", remember: false, installation: target, verificationOnly: true)
    }
    var received: (([UInt8]) -> Void)?
    private var trustReply: CheckedContinuation<Bool, Never>?
    private var work: Task<Void, Never>?
    private var writeTail: Task<Void, Never>?
    private var queuedBytes = 0
    private var client: SSHClient?
    private var channel: Channel?
    private var writer: TerminalWriter?
    private var socketOwner: TerminalSocketOwner?
    private var generation = UUID()
    private var columns = 80
    private var rows = 24
    init(mac: DirectMacRecordV1) { self.mac = mac }
    func updateMac(_ record: DirectMacRecordV1) { if record.id == mac.id { mac = record } }
    func connect(username: String, password: String, remember: Bool, key: TerminalSSHKey? = nil, installation: TerminalNamedKey? = nil, verificationOnly: Bool = false) {
        guard DirectAppLockV1.shared.canAccess, !connecting, !connected else { return }
        let loginKey = verificationOnly ? installation?.key : key
        guard !username.isEmpty, (loginKey != nil || !password.isEmpty), username.utf8.count <= 255, password.utf8.count <= 4096,
              !username.contains("\0"), !password.contains("\0") else { present(.loginRejected, message: "Enter a Mac account and password or choose an SSH key. Account names must be at most 255 UTF-8 bytes and passwords at most 4 KiB, with no NUL characters."); return }
        let authentication: @Sendable () -> SSHAuthenticationMethod
        if let key = loginKey {
            do { try key.validate(); let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)
                authentication = { .ed25519(username: username, privateKey: parsed) }
            } catch { present(.savedDataUnavailable, message: "The selected SSH key couldn’t be read. Existing keys are kept."); return }
        } else { authentication = { .passwordBased(username: username, password: password) } }
        stop(); identityDetails = []; installedKey = nil; recovery = nil; phase = "Contacting Mac"; setupPhase = .notSent; settingUp = installation != nil; let id = UUID(); generation = id
        let owner = TerminalSocketOwner(); socketOwner = owner
        connecting = true; phase = "Finding a reachable address"; status = "Contacting Remote Login…"
        let addresses = mac.addresses, port = mac.sshPort
        work = Task {
            do {
                if installation == nil && key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) }
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
                    try TerminalKeyLibraryStore.associate(installation.id, macID: mac.id, username: username)
                    stop(); installedKey = installation.id; present(.setupVerified, stage: "Key-only login verified; preference saved")
                    return
                }
                if var key { key.username = username; try TerminalSecretStore.saveKey(key, id: mac.id) }
                else if remember { try TerminalSecretStore.save(.init(username: username, password: password), id: mac.id) }
                self.phase = "Opening a new shell"
                try await TerminalPTY.run(client: client, columns: columns, rows: rows, ready: { writer in
                    guard self.generation == id else { throw CancellationError() }
                    self.writer = writer; self.connected = true; self.connecting = false; self.status = "Connected"; self.phase = "Shell open"; self.recovery = nil
                }, output: { bytes in
                    guard self.generation == id, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { throw CancellationError() }
                    self.received?(bytes)
                })
                if generation == id { stop(); present(.terminalEnded) }
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
                } else if wasConnected { present(.terminalEnded, message: "The SSH connection ended. Open a new shell to continue; previous input won’t be replayed.", stage: stage) }
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
            try TerminalSecretStore.write(Data(key.utf8), id: self.mac.id, kind: "host-key")
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
    func send(_ data: [UInt8]) {
        guard connected, DirectAppLockV1.shared.canAccess, let writer, !data.isEmpty else { return }
        guard data.count <= 65536, queuedBytes + data.count <= 65536 else { stop(); present(.inputPaused); return }
        queuedBytes += data.count; let id = generation; let previous = writeTail
        writeTail = Task {
            await previous?.value
            guard generation == id, !Task.isCancelled else { return }
            do { try await writer.write(data); if generation == id { queuedBytes -= data.count } }
            catch { if generation == id { stop(); present(.terminalEnded, message: "The connection ended while sending input. It won’t be replayed. Open a new shell to continue.") } }
        }
    }
    func resize(columns: Int, rows: Int) {
        self.columns = max(1, min(500, columns)); self.rows = max(1, min(500, rows))
        guard let writer, connected else { return }; let cols = self.columns, rows = self.rows, id = generation
        let previous = writeTail
        writeTail = Task {
            await previous?.value; guard generation == id else { return }
            do { try await writer.resize(columns: cols, rows: rows) }
            catch { if generation == id { stop(); present(.terminalEnded, message: "The connection ended while resizing the Terminal. Open a new shell to continue.") } }
        }
    }
    func stop() {
        generation = UUID(); let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: false); work?.cancel(); work = nil; writeTail?.cancel(); writeTail = nil
        socketOwner?.cancel(); socketOwner = nil
        let client = self.client, channel = self.channel; self.client = nil; self.channel = nil; writer = nil
        connected = false; connecting = false; queuedBytes = 0
        Task { try? await client?.close(); try? await channel?.close() }
    }
    func background() { if connecting && settingUp { cancelConnection() } else { let active = connecting || connected; stop(); if active { present(.terminalEnded, message: "The SSH shell closed while the app was in the background. Open a new shell to continue; previous input won’t be replayed.") } } }
}
#endif
