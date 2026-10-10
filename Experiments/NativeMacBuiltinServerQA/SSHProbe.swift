// Disposable live-server probe. Never linked into an application target.
import Foundation
import Crypto
@preconcurrency import Citadel
@preconcurrency import NIO
@preconcurrency import NIOSSH

private enum ProbeFailure: Error { case configuration, identity, response }

private final class PinnedHost: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let fingerprint: String
    init(_ fingerprint: String) { self.fingerprint = fingerprint }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let parts = String(openSSHPublicKey: hostKey).split(separator: " ")
        guard parts.count >= 2, let key = Data(base64Encoded: String(parts[1])) else {
            validationCompletePromise.fail(ProbeFailure.identity); return
        }
        let actual = "SHA256:" + Data(SHA256.hash(data: key)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        if actual == fingerprint { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(ProbeFailure.identity) }
    }
}

@main private struct SSHProbe {
    static func main() async throws { try await run() }
    nonisolated static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let host = environment["MC_VM_HOST"], let account = environment["MC_VM_ACCOUNT"],
              let password = environment["MC_VM_PASSWORD"], let fingerprint = environment["MC_VM_HOST_KEY"],
              !password.isEmpty, fingerprint.hasPrefix("SHA256:") else { throw ProbeFailure.configuration }
        func connect() async throws -> SSHClient {
            // Match the direct client's paused-read admission before installing
            // Citadel's parser; the shared pinned implementation handles SSH.
            let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .channelOption(ChannelOptions.autoRead, value: false).connect(host: host, port: 22).get()
            var settings = SSHClientSettings(host: host, port: 22,
                authenticationMethod: { .passwordBased(username: account, password: password) },
                hostKeyValidator: .custom(PinnedHost(fingerprint)))
            settings.connectTimeout = .seconds(15)
            do { return try await SSHClient.connect(on: channel, settings: settings) }
            catch { try? await channel.close(); throw error }
        }
        let first = try await connect()
        let second: SSHClient
        do { second = try await connect() }
        catch { try? await first.close(); throw error }
        do {
            let system = try await first.executeCommand("/usr/bin/uname -s", maxResponseSize: 1024)
            guard String(decoding: system.readableBytesView, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "Darwin" else {
                throw ProbeFailure.response
            }
            try await first.close()
            let alive = try await second.executeCommand("/usr/bin/true", maxResponseSize: 1024)
            guard alive.readableBytes == 0 else { throw ProbeFailure.response }
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(wantReply: true, term: "xterm-256color",
                terminalCharacterWidth: 80, terminalRowHeight: 24, terminalPixelWidth: 0, terminalPixelHeight: 0,
                terminalModes: .init([.ECHO: 1]))
            var output = [UInt8]()
            let status = try await second.withPTY(request) { stream, writer in
                try await writer.changeSize(cols: 101, rows: 31, pixelWidth: 0, pixelHeight: 0)
                try await writer.write(ByteBuffer(string: "/bin/stty size; exit\r"))
                for try await item in stream {
                    let buffer: ByteBuffer
                    switch item { case .stdout(let value), .stderr(let value): buffer = value }
                    output.append(contentsOf: buffer.readableBytesView)
                    guard output.count <= 65536 else { throw ProbeFailure.response }
                }
            }
            guard status == 0, String(decoding: output, as: UTF8.self).contains("\r\n31 101\r\n") else {
                throw ProbeFailure.response
            }
            try await second.close()
            print("PASS: pinned host identity, two built-in SSH connections, owning-connection closure, PTY input/output and resize")
        } catch {
            try? await first.close(); try? await second.close(); throw error
        }
    }
}
