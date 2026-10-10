#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacSSHKeyFilesView: View {
    let mac: DirectMacRecordV1?
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var library = MacSSHKeyFileStore.Library()
    @State private var issue: DirectRecoveryNotice?
    @State private var sheet: Sheet?
    private enum Sheet: String, Identifiable { case choose, pro; var id: String { rawValue } }
    var body: some View {
        Form {
            Section {
                DirectGuidanceRow(title: "Use the original file", detail: "Choose a key in ~/.ssh or another folder. The app reads it when you connect.", symbol: "doc.badge.key")
                DirectGuidanceRow(title: "Keep it on this Mac", detail: "The file reference stays local. Private keys and passphrases are never synced.", symbol: "lock.shield")
            }
            Section("Key Files") {
                ForEach(library.files) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(file.name, systemImage: "doc.badge.key").font(.headline)
                        Text(file.fingerprint).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        if !DirectProAccess.shared.hasPro {
                            Button("Use as My Free Key") { perform { try MacSSHKeyFileStore.chooseFreeKey(file.id) } }
                                .disabled(!DirectProAccess.shared.ready)
                        }
                        HStack {
                            if let mac {
                                if library.associations.contains(where: { $0.macID == mac.id && $0.keyID == file.id }) { Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(.tint) }
                                else { Button("Use for \(mac.name)") { select(file, mac: mac) } }
                            }
                            Spacer()
                            Button("Remove Reference", systemImage: "minus.circle", role: .destructive) { perform { try MacSSHKeyFileStore.remove(file.id) } }
                        }
                    }.padding(.vertical, 4)
                }
                Button("Choose Key File…", systemImage: "folder") { sheet = .choose }
            }
            if let issue { Section { DirectRecoveryCard(notice: issue, primary: .init(title: "Retry", perform: reload)) } }
        }.formStyle(.grouped).navigationTitle("SSH Key Files")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .choose: MacSSHKeyFileComposer { id in
                    if let mac { try MacSSHKeyFileStore.associate(id, macID: mac.id, username: "") }
                    reload(); changed()
                }.modifier(MacSheetPrivacyCover())
                case .pro: DirectProView().modifier(MacSheetPrivacyCover())
                }
            }.onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: MacSSHKeyFileStore.changed)) { _ in reload() }
    }
    private func reload() { do { library = try MacSSHKeyFileStore.load(); issue = nil } catch { issue = .make(.savedDataUnavailable) } }
    private func perform(_ action: () throws -> Void) {
        do { try action(); reload(); changed() }
        catch MacSSHKeyFileStore.Failure.requiresPro { sheet = .pro }
        catch { issue = .make(.saveFailed, message: error.localizedDescription) }
    }
    private func select(_ file: MacSSHKeyFileReference, mac: DirectMacRecordV1) {
        perform { try MacSSHKeyFileStore.associate(file.id, macID: mac.id, username: "") }
    }
}

private struct MacSSHKeyFileComposer: View {
    let selected: @MainActor (UUID) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picker = MacSSHKeyFilePicker()
    @State private var window = MacWindowHandle()
    @State private var url: URL?
    @State private var name = ""
    @State private var passphrase = ""
    @State private var issue: DirectRecoveryNotice?
    @State private var busy = false
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    Text(url?.lastPathComponent ?? "No file selected").foregroundStyle(.secondary)
                    HStack {
                        Button("Choose from ~/.ssh…") { choose(sshFolder: true) }
                        Button("Choose File…") { choose(sshFolder: false) }
                    }
                    TextField("Name", text: $name)
                }.disabled(busy)
                Section {
                    SecureField("Key passphrase, if encrypted", text: $passphrase)
                } header: { Label("Unlock Key", systemImage: "lock") }
                footer: { Text("Used to verify the file now. Encrypted keys ask again when connecting; passphrases are never saved.") }
                    .disabled(busy)
                if busy { ProgressView("Checking key file…") }
                if let issue { DirectRecoveryCard(notice: issue) }
                Section { Text("Ed25519 OpenSSH keys, up to 32 KiB. The original file is never modified or copied into the key library.").font(.footnote).foregroundStyle(.secondary) }
            }.formStyle(.grouped).navigationTitle("Use SSH Key File")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Use File", action: save).disabled(busy || url == nil || !TerminalKeyLibraryStore.Library.validName(name)) }
                }
        }.frame(width: 520, height: 420)
            .background(MacWindowReader(handle: window).frame(width: 0, height: 0))
            .onDisappear { generation = UUID(); picker.cancel(); passphrase = ""; url = nil }
            .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in generation = UUID(); busy = false; picker.cancel(); passphrase = ""; url = nil }
    }
    private func choose(sshFolder: Bool) {
        guard !busy, let owner = window.window else { return }
        picker.choose(in: owner, sshFolder: sshFolder, referencing: true) { result in
            if case .success(let selected) = result { url = selected; name = selected.lastPathComponent; passphrase = ""; issue = nil }
        }
    }
    private func save() {
        guard !busy, let url, DirectAppLockV1.shared.canAccess else { return }
        let token = UUID(), name = name, secret = passphrase
        busy = true; generation = token; passphrase = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                try TerminalSSHKey.importOpenSSH(TerminalSSHKey.readOpenSSHFile(url), passphrase: secret)
            }.result
            guard generation == token, DirectAppLockV1.shared.canAccess else { return }
            busy = false
            do {
                let id = try MacSSHKeyFileStore.register(url: url, name: name, key: result.get())
                try selected(id); dismiss()
            } catch { issue = .make(.importInvalid, message: error.localizedDescription) }
        }
    }
}
#endif
