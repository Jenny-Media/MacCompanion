import SwiftUI
import Foundation
import Tunnel
import CRFBProbe

@MainActor final class ProbeModel: ObservableObject {
    @Published var username = NSUserName()
    @Published var password = ""
    @Published var status = "Ready to test built-in Remote Login and Screen Sharing on this Mac."
    @Published var running = false
    private var tunnel: SSHTunnel?
    private var task: Task<Void, Never>?
    private var attempt = UUID()
    func verify() {
        guard !running, !username.isEmpty, !password.isEmpty else { return }
        guard username.utf8.count <= 63, password.utf8.count <= 63,
              !username.contains("\0"), !password.contains("\0") else {
            status = "Use a Mac account and password of at most 63 UTF-8 bytes, with no NUL characters."
            return
        }
        let user = username, secret = password, id = UUID()
        password = ""; running = true; attempt = id
        status = "Verifying this Mac's SSH host identity and signing in…"
        task = Task {
            do {
                let files = ["ssh_host_ed25519_key.pub", "ssh_host_ecdsa_key.pub", "ssh_host_rsa_key.pub"]
                let keys = files.compactMap { try? String(contentsOfFile: "/etc/ssh/" + $0, encoding: .utf8) }
                guard !keys.isEmpty else { throw ProbeFailure.hostIdentity }
                let connection = try await SSHTunnel.open(sshPort: 22, username: user, password: secret, trustedKeys: keys)
                guard attempt == id, !Task.isCancelled else { await connection.close(); return }
                tunnel = connection; status = "SSH verified. Testing Apple ARD through the encrypted tunnel…"
                let fd = connection.takeSocket()
                let passed = await Task.detached {
                    user.withCString { u in secret.withCString { p in ProbeARDHandshake(fd, u, p) != 0 } }
                }.value
                let counts = try await connection.counts()
                await connection.close(); tunnel = nil
                guard attempt == id else { return }
                status = passed
                    ? "Verified: Apple Screen Sharing authenticated through SSH. The tunnel is closed."
                    : "SSH authenticated, but Apple Screen Sharing authentication did not complete. The tunnel is closed."
                record(passed ? "ardHandshakePassed" : "ardHandshakeFailed", outbound: counts.outbound, inbound: counts.inbound, peak: counts.peak)
            } catch {
                await tunnel?.close(); tunnel = nil
                guard attempt == id else { return }
                status = "Verification failed before Screen Sharing completed. Check that Remote Login and Screen Sharing are enabled, and use this Mac's account password."
                record("connectionFailed", outbound: 0, inbound: 0, peak: 0)
            }
            if attempt == id { running = false }
        }
        // No unbounded authentication wait, even if a server never replies.
        Task { try? await Task.sleep(for: .seconds(30)); if running && attempt == id { cancel(timedOut: true) } }
    }
    func cancel(timedOut: Bool = false) {
        attempt = UUID(); task?.cancel(); tunnel?.cancelReads()
        let connection = tunnel; tunnel = nil
        Task { await connection?.close() }
        running = false; status = timedOut ? "Verification timed out. Any open tunnel is closing." : "Cancelled. Any open tunnel is closing."
    }
    private func record(_ outcome: String, outbound: Int, inbound: Int, peak: Int) {
        // Aggregate evidence only. Never persist username, credentials or RFB bytes.
        let report: [String: Any] = ["profile": "maccompanion.ssh-screen-sharing-loopback-probe.v1",
            "outcome": outcome, "outboundBytes": outbound, "inboundBytes": inbound, "peakQueuedBytes": peak,
            "requestedFramebufferUpdates": false, "sentUserInput": false, "closed": true]
        if let path = ProcessInfo.processInfo.environment["MACCOMPANION_SSH_PROBE_RESULT"]
                ?? Bundle.main.object(forInfoDictionaryKey: "ProbeResultPath") as? String,
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

@main struct ProbeApp: App {
    @StateObject private var model = ProbeModel()
    var body: some Scene {
        WindowGroup("SSH Screen Sharing Probe") {
            VStack(alignment: .leading, spacing: 22) {
                Text("Built-in services · loopback only").font(.headline)
                Text("Sign in to this Mac to verify Apple Screen Sharing over an encrypted SSH tunnel. Host identity is checked against this Mac's public SSH host keys.")
                Text("Your password is not saved. No desktop screenshots or keyboard input are collected. The connection closes after verification.")
                    .foregroundStyle(.secondary)
                TextField("Mac account", text: $model.username)
                SecureField("Mac password", text: $model.password).onSubmit { model.verify() }
                HStack {
                    Button("Sign In and Verify") { model.verify() }
                        .buttonStyle(.borderedProminent).disabled(model.running || model.password.isEmpty)
                    if model.running { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() } }
                }
                Divider()
                Text(model.status).textSelection(.enabled).accessibilityIdentifier("probe-status")
            }
            .textFieldStyle(.roundedBorder).padding(28).frame(width: 580).frame(minHeight: 360)
            .onDisappear { model.cancel() }
        }.windowResizability(.contentSize)
    }
}
