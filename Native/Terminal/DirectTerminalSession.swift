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
    var toggleKeyboard: (@MainActor () -> Void)?
    var keyboardVisible = false
    struct TrustRequest: Identifiable { let id = UUID(); let fingerprint: String }
    let mac: DirectMacRecordV1
    var status = "Sign in to Remote Login"
    var connecting = false
    var connected = false
    var trust: TrustRequest?
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
    func connect(username: String, password: String, remember: Bool, key: TerminalSSHKey? = nil) {
        guard DirectAppLockV1.shared.canAccess, !connecting, !connected else { return }
        guard !username.isEmpty, (key != nil || !password.isEmpty), username.utf8.count <= 255, password.utf8.count <= 4096,
              !username.contains("\0"), !password.contains("\0") else { status = "Enter the Mac account username and password."; return }
        let authentication: @Sendable () -> SSHAuthenticationMethod
        if let key {
            do { try key.validate(); let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)
                authentication = { .ed25519(username: username, privateKey: parsed) }
            } catch { status = "The saved SSH key could not be read. It has been preserved."; return }
        } else { authentication = { .passwordBased(username: username, password: password) } }
        stop(); let id = UUID(); generation = id
        let owner = TerminalSocketOwner(); socketOwner = owner
        connecting = true; status = "Contacting Remote Login…"
        let addresses = mac.addresses, port = mac.sshPort
        work = Task {
            do {
                if key == nil && !remember { try TerminalSecretStore.forgetLogin(mac.id) }
                let fd = await Task.detached(priority: .userInitiated) {
                    var failure = 0
                    return CompanionVNCConnectAddresses(addresses, port, { owner.isCancelled }, { owner.register($0) }, nil, &failure)
                }.value
                guard fd >= 0 else { throw TerminalSecretStore.Failure.network }
                if owner.isCancelled || generation != id { Darwin.close(fd); throw CancellationError() }
                let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton).withConnectedSocket(fd).get()
                guard generation == id, !Task.isCancelled else { try? await channel.close(); throw CancellationError() }
                self.channel = channel
                let validator = TerminalHostValidator { [weak self] key in
                    guard let self, self.generation == id, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
                    if let saved = try TerminalSecretStore.hostKey(self.mac.id) {
                        guard saved == key else { throw TerminalSecretStore.Failure.changedKey }
                        return
                    }
                    guard let fingerprint = TerminalSecretStore.fingerprint(key) else { throw TerminalSecretStore.Failure.rejectedKey }
                    self.trust = .init(fingerprint: fingerprint)
                    let accepted = await withCheckedContinuation { self.trustReply = $0 }
                    self.trust = nil
                    guard accepted, self.generation == id, DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.rejectedKey }
                    try TerminalSecretStore.write(Data(key.utf8), id: self.mac.id, kind: "host-key")
                }
                var settings = SSHClientSettings(host: mac.address, port: port,
                    authenticationMethod: authentication, hostKeyValidator: .custom(validator))
                settings.connectTimeout = .seconds(60)
                let client = try await SSHClient.connect(on: channel, settings: settings)
                guard generation == id, !Task.isCancelled else { try? await client.close(); throw CancellationError() }
                self.client = client
                if var key { key.username = username; try TerminalSecretStore.saveKey(key, id: mac.id) }
                else if remember { try TerminalSecretStore.save(.init(username: username, password: password), id: mac.id) }
                try await TerminalPTY.run(client: client, columns: columns, rows: rows, ready: { writer in
                    guard self.generation == id else { throw CancellationError() }
                    self.writer = writer; self.connected = true; self.connecting = false; self.status = "Connected"
                }, output: { bytes in
                    guard self.generation == id, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { throw CancellationError() }
                    self.received?(bytes)
                })
                if generation == id { stop(); status = "Session ended. Reconnect to open a new shell." }
            } catch {
                guard generation == id else { return }
                stop()
                if case TerminalSecretStore.Failure.changedKey = error { status = "SSH server key changed. Verify the Mac, then forget its server key in Edit Mac to reconnect." }
                else if case TerminalSecretStore.Failure.storage = error { status = "Saved Terminal data could not be read or saved. Existing data has been preserved." }
                else if case TerminalSecretStore.Failure.rejectedKey = error { status = "Server key was not trusted. No login was sent." }
                else { status = "Terminal connection ended. Check Remote Login, your Mac account, network and SSH port, then retry." }
            }
        }
    }
    func answerTrust(_ accepted: Bool) {
        let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: accepted)
        if !accepted, reply != nil { stop(); status = "Server key was not trusted. No login was sent." }
    }
    func send(_ data: [UInt8]) {
        guard connected, DirectAppLockV1.shared.canAccess, let writer, !data.isEmpty else { return }
        guard data.count <= 65536, queuedBytes + data.count <= 65536 else { stop(); status = "Input queue full. Reconnect before continuing."; return }
        queuedBytes += data.count; let id = generation; let previous = writeTail
        writeTail = Task {
            await previous?.value
            guard generation == id, !Task.isCancelled else { return }
            do { try await writer.write(data); if generation == id { queuedBytes -= data.count } }
            catch { if generation == id { stop(); status = "Terminal disconnected. Input was not replayed." } }
        }
    }
    func resize(columns: Int, rows: Int) {
        self.columns = max(1, min(500, columns)); self.rows = max(1, min(500, rows))
        guard let writer, connected else { return }; let cols = self.columns, rows = self.rows, id = generation
        let previous = writeTail
        writeTail = Task {
            await previous?.value; guard generation == id else { return }
            do { try await writer.resize(columns: cols, rows: rows) }
            catch { if generation == id { stop(); status = "Terminal disconnected during resize." } }
        }
    }
    func stop() {
        generation = UUID(); let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: false); work?.cancel(); work = nil; writeTail?.cancel(); writeTail = nil
        socketOwner?.cancel(); socketOwner = nil
        let client = self.client, channel = self.channel; self.client = nil; self.channel = nil; writer = nil
        connected = false; connecting = false; queuedBytes = 0
        Task { try? await client?.close(); try? await channel?.close() }
    }
    func background() { stop(); status = "Terminal paused. Reconnect to open a new shell; previous input is not replayed." }
}
#endif
