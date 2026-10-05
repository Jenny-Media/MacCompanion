#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TerminalKeySettings: View {
    let mac: DirectMacRecordV1
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var key: TerminalSSHKey?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var readable = true
    @State private var removing = false
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            Form {
                if let key {
                    Section("Ed25519 Key") {
                        Label("Saved on this iPhone", systemImage: "key.fill")
                        Text(key.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copy Public Key", systemImage: "document.on.document") { UIPasteboard.general.string = key.publicKey + " mac-companion" }
                        Text(key.publicKey).font(.caption.monospaced()).textSelection(.enabled).lineLimit(4)
                    }
                    Section {
                        Text("Add the public key to ~/.ssh/authorized_keys for your Mac account. Keep ~/.ssh private (700) and authorized_keys private (600), and enable Remote Login. Never copy the private key there.")
                    } header: { Text("On Your Mac") }
                    Section {
                        Button("Remove Key from This iPhone", systemImage: "key.slash", role: .destructive) { removing = true }
                    } footer: { Text("Removing this key does not revoke it on the Mac. Remove its public line from authorized_keys to revoke access.") }
                } else {
                    Section {
                        Button("Create Ed25519 Key", systemImage: "key") { save(.create()) }.disabled(!readable || busy)
                    } header: { Text("New Key") } footer: { Text("Create a key for \(mac.name), then install its public key on the Mac. The private key stays in this iPhone’s Keychain.") }
                    Section {
                        SecureField("Key passphrase, if encrypted", text: $passphrase).textContentType(nil).autocorrectionDisabled().privacySensitive()
                        Button("Import Key from Files", systemImage: "doc") { importing = true }.disabled(!readable || busy)
                        PasteButton(payloadType: String.self) { values in if let value = values.first { decode(value) } }.disabled(!readable || busy)
                    } header: { Text("Existing Key") } footer: { Text("Ed25519 OpenSSH private keys only, up to 32 KiB. Enter the passphrase before importing an encrypted key. The passphrase is used once and is never saved.") }
                }
                if busy { Section { ProgressView("Checking key…") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("Private keys are device-only and excluded from iCloud library sync. Mac Companion does not export them.").foregroundStyle(.secondary) }
            }
            .navigationTitle("SSH Key · \(mac.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text]) { result in
                readFile(result)
            }
            .confirmationDialog("Remove this iPhone’s SSH key?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove Key", role: .destructive) {
                    do { try TerminalSecretStore.forgetKey(mac.id); key = nil; changed() }
                    catch { self.error = "Could not remove the key. It has been preserved." }
                }
            }
        }
        .onAppear {
            do { key = try TerminalSecretStore.sshKey(mac.id) }
            catch { readable = false; self.error = "The saved key could not be read. It has been preserved." }
        }
        .onDisappear { generation = UUID(); passphrase = "" }
    }
    private func readFile(_ result: Result<URL, Error>) {
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try handle.read(upToCount: 32769) ?? Data()
                    guard data.count <= 32768, let text = String(data: data, encoding: .utf8) else { throw TerminalSSHKey.KeyFailure.tooLarge }
                    decode(text)
                } catch { self.error = "Could not import this file. Use an Ed25519 OpenSSH private key up to 32 KiB." }
    }
    private func save(_ value: TerminalSSHKey) {
        do { try TerminalSecretStore.saveKey(value, id: mac.id); key = value; error = nil; passphrase = ""; changed() }
        catch { self.error = "Could not save the key. Existing data has been preserved." }
    }
    private func decode(_ text: String) {
        guard !busy, readable, key == nil else { return }
        busy = true; error = nil; let passphrase = self.passphrase, id = generation
        self.passphrase = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try TerminalSSHKey.importOpenSSH(text, passphrase: passphrase) } }.value
            guard generation == id, DirectAppLockV1.shared.canAccess else { return }; busy = false
            switch result { case .success(let key): save(key); case .failure(let failure): error = failure.localizedDescription }
        }
    }
}
#endif
