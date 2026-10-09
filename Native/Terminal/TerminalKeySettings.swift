#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif
import LocalAuthentication
import Crypto
import Citadel

struct SSHKeyDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data, .plainText]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct TerminalKeySettings: View {
    var mac: DirectMacRecordV1? = nil
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var library = TerminalKeyLibrary()
    @State private var pro = DirectProAccess.shared
    private enum Sheet: String, Identifiable { case create, importKey, pro; var id: String { rawValue } }
    @State private var sheet: Sheet?
    var body: some View {
        NavigationStack {
            List {
                if let mac {
                    Section {
                        Button("Use Password Login", systemImage: "person.badge.key") {
                            library.perform { try TerminalKeyLibraryStore.forgetAssociation(mac.id) }; changed()
                        }
                    } footer: { Text("Select a key below for \(mac.name). Keys can be used with any of your Macs.") }
                }
                Section("SSH Keys") {
                    ForEach(library.keys) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink {
                                TerminalKeyDetail(entry: entry, library: library, changed: changed)
                            } label: { VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(entry.name, systemImage: "key")
                                    if library.associations.contains(where: { $0.macID == mac?.id && $0.keyID == entry.id }) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                }
                                Text(entry.key.fingerprint).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            } }
                            if let mac {
                                let selected = library.associations.contains { $0.macID == mac.id && $0.keyID == entry.id }
                                if selected { Label("Selected for \(mac.name)", systemImage: "checkmark").font(.subheadline).foregroundStyle(.secondary) }
                                else { Button("Use for \(mac.name)") { select(entry, for: mac) }.buttonStyle(.borderless).disabled(!pro.ready) }
                            }
                        }
                    }
                    if library.keys.isEmpty && library.readable { Text("Create or import a key, then choose it for a Mac.").foregroundStyle(.secondary) }
                }
                Section {
                    Button("Create Key", systemImage: "plus") { sheet = pro.canAddKey(count: library.keys.count) ? .create : .pro }
                    Button("Import Key", systemImage: "square.and.arrow.down") { sheet = pro.canAddKey(count: library.keys.count) ? .importKey : .pro }
                }.disabled(!library.readable || !pro.ready)
                if let notice = library.recovery { Section { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry") { reload() }) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section {
                    #if os(macOS)
                    Text("Selecting or importing a key doesn’t add it to a Mac. Use that Mac’s Terminal Access settings to install its public key. Private keys stay in this Mac’s Keychain and are excluded from iCloud sync.")
                    #else
                    Text("Selecting or importing a key doesn’t add it to a Mac. Use that Mac’s Terminal Access settings to install its public key. Private keys stay in this iPhone’s Keychain and are excluded from iCloud sync.")
                    #endif
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("SSH Keys").directInlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .create, .importKey:
                    TerminalKeyComposer(importing: destination == .importKey) { key, name in
                        reload()
                        guard library.readable else { return false }
                        guard pro.ready, pro.canAddKey(count: library.keys.count) else { sheet = .pro; return false }
                        let saved = library.perform {
                            let id = try TerminalKeyLibraryStore.addForUser(key, name: name, access: pro)
                            if let mac { try TerminalKeyLibraryStore.associate(id, macID: mac.id, username: "") }
                        }
                        if saved { changed() }; return saved
                    }
                case .pro: DirectProView()
                }
            }
            .onAppear { reload(); pro.start() }
        }
    }
    private func reload() { library.reload(macs: mac.map { [$0] } ?? []) }
    private func select(_ entry: TerminalNamedKey, for mac: DirectMacRecordV1) {
        guard pro.ready else { return }
        guard pro.canUseKey(entry.id, among: library.keys.map(\.id)) else { sheet = .pro; return }
        library.perform {
            let username = library.associations.first(where: { $0.macID == mac.id })?.username ?? ""
            try TerminalKeyLibraryStore.associate(entry.id, macID: mac.id, username: username)
        }; changed()
    }
}

struct TerminalKeyComposer: View {
    let importing: Bool
    let save: @MainActor (TerminalSSHKey, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var passphrase = ""
    @State private var picking = false
    @State private var busy = false
    @State private var issue: DirectRecoveryNotice?
    @State private var generation = UUID()
    #if os(macOS)
    @State private var importWindow = MacWindowHandle()
    @State private var filePicker = MacSSHKeyFilePicker()
    #endif
    var body: some View {
        NavigationStack {
            Form {
                Section("Key Name") { TextField("Name", text: $name).autocorrectionDisabled()
                    if !valid { Text("Use a name from 1 to 80 characters, without control characters.").font(.footnote).foregroundStyle(.secondary) }
                }
                if importing {
                    Section {
                        SecureField("Import passphrase, if encrypted", text: $passphrase).textContentType(nil).privacySensitive()
                        #if os(macOS)
                        Button("Choose from ~/.ssh…") { chooseFile(sshFolder: true) }.disabled(!valid || busy || picking)
                        Button("Choose File…") { chooseFile(sshFolder: false) }.disabled(!valid || busy || picking)
                        #else
                        Button("Import from Files") { picking = true }.disabled(!valid || busy)
                        #endif
                        PasteButton(payloadType: String.self) { values in if let text = values.first { decode(text) } }.disabled(!valid || busy)
                    } footer: {
                        Text("Ed25519 OpenSSH keys only, up to 32 KiB. Import passphrases are used once and never saved.")
                        #if os(macOS)
                        Text("Choose a private key such as id_ed25519, not its .pub file. Import saves a local Keychain copy; the original file is kept and future file edits won’t change the imported key.")
                        #endif
                    }
                } else {
                    Section { Button("Create Ed25519 Key") { if save(.create(), name) { dismiss() } else { issue = .make(.saveFailed, message: "The key couldn’t be saved. Keep this form open and try again.") } }.disabled(!valid || busy) }
                }
                if busy { ProgressView("Importing…") }
                if let issue { DirectRecoveryCard(notice: issue) }
            }
            .navigationTitle(importing ? "Import SSH Key" : "Create SSH Key").directInlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            #if os(macOS)
            .background(MacWindowReader(handle: importWindow).frame(width: 0, height: 0))
            #else
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .plainText], onCompletion: readFile)
            #endif
            .onDisappear { generation = UUID(); passphrase = ""; cancelPicker() }
            .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.willResignActive)) { _ in generation = UUID(); passphrase = ""; busy = false }
            .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in generation = UUID(); passphrase = ""; busy = false; cancelPicker() }
        }
    }
    private func readFile(_ result: Result<URL, Error>) {
        guard DirectAppLockV1.shared.canAccess else { return }
        do { decode(try TerminalSSHKey.readOpenSSHFile(result.get())) }
        catch { if !DirectCancellation.isCancellation(error) { issue = importNotice(error) } }
    }
    private func cancelPicker() {
        picking = false
        #if os(macOS)
        filePicker.cancel()
        #endif
    }
    #if os(macOS)
    private func chooseFile(sshFolder: Bool) {
        guard valid, !busy, !picking, DirectAppLockV1.shared.canAccess, let window = importWindow.window else { return }
        picking = true
        filePicker.choose(in: window, sshFolder: sshFolder) { result in picking = false; readFile(result) }
    }
    #endif
    private func importNotice(_ error: Error) -> DirectRecoveryNotice {
        guard let failure = error as? TerminalSSHKey.KeyFailure else { return .make(.importInvalid, message: "The file couldn’t be read. Choose another Ed25519 OpenSSH key, up to 32 KiB.") }
        switch failure {
        case .invalid: return .make(.importInvalid)
        case .unsupported: return .make(.importUnsupported)
        case .tooLarge: return .make(.importTooLarge)
        case .passphrase: return .make(.importUnlock)
        case .workLimit: return .make(.importWorkLimit)
        }
    }
    private var valid: Bool { TerminalKeyLibraryStore.Library.validName(name) }
    private func decode(_ text: String) {
        guard valid, !busy, DirectAppLockV1.shared.canAccess else { return }
        busy = true; let token = generation, secret = passphrase; passphrase = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try TerminalSSHKey.importOpenSSH(text, passphrase: secret) } }.value
            guard token == generation, DirectAppLockV1.shared.canAccess else { return }; busy = false
            switch result {
            case .success(let key): if save(key, name) { dismiss() } else { issue = .make(.saveFailed, message: "The key couldn’t be saved. Keep this form open and try again.") }
            case .failure(let failure): issue = importNotice(failure)
            }
        }
    }
}

struct TerminalKeyDetail: View {
    let entry: TerminalNamedKey
    @Bindable var library: TerminalKeyLibrary
    let changed: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var privateExport = false
    @State private var exportData: Data?
    @State private var exportFilename = "ssh-key.pub"
    @State private var exporting = false
    @State private var busy = false
    @State private var deleting = false
    @State private var issue: DirectRecoveryNotice?
    @State private var generation = UUID()
    @State private var authentication: LAContext?
    init(entry: TerminalNamedKey, library: TerminalKeyLibrary, changed: @escaping @MainActor () -> Void) {
        self.entry = entry; self.library = library; self.changed = changed; _name = State(initialValue: entry.name)
    }
    var body: some View {
        Form {
            if let notice = library.recovery { DirectRecoveryCard(notice: notice, primary: .init(title: "Review Keys", perform: { library.reload() })) }
            Section("Key") {
                TextField("Name", text: $name)
                Button("Save Name") { library.perform { try TerminalKeyLibraryStore.rename(entry.id, name: name) }; changed() }
                    .disabled(!TerminalKeyLibraryStore.Library.validName(name))
                Text(entry.key.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                Text("Used by \(library.associations.filter { $0.keyID == entry.id }.count) saved Mac(s)").foregroundStyle(.secondary)
                if !DirectProAccess.shared.hasPro { Button("Use as My Free Key") { DirectProAccess.shared.chooseFreeKey(entry.id); changed() } }
            }
            Section("Public Key") {
                Button("Copy Public Key") { DirectClientPlatformV1.copy(publicLine) }
                Button("Export Public Key") { exportFilename = filename + ".pub"; exportData = Data((publicLine + "\n").utf8); exporting = true }
            }
            Section {
                Toggle("Export Encrypted Private Key", isOn: $privateExport)
                if privateExport {
                    SecureField("Export passphrase", text: $passphrase).textContentType(nil).privacySensitive()
                    SecureField("Confirm passphrase", text: $confirmPassphrase).textContentType(nil).privacySensitive()
                    Button("Authenticate & Export") { exportPrivate() }.disabled(busy || passphrase.isEmpty || passphrase != confirmPassphrase || passphrase.utf8.count > 4096)
                    if !passphrase.isEmpty && passphrase != confirmPassphrase { Text("The passphrases must match.").font(.footnote).foregroundStyle(.secondary) }
                    if passphrase.utf8.count > 4096 { Text("Use a passphrase up to 4 KiB.").font(.footnote).foregroundStyle(.secondary) }
                    if busy { ProgressView("Preparing encrypted key…") }
                }
            } header: { Text("Private Key Backup") } footer: { Text("Exports use passphrase-encrypted OpenSSH format and require Face ID or your passcode. Keep the file and passphrase safe; a forgotten passphrase cannot be recovered.") }
            if let issue { DirectRecoveryCard(notice: issue) }
            Section {
                Button("Delete Key from This iPhone", role: .destructive) { deleting = true }
            } footer: { Text("This clears local selections. It does not remove the public key or revoke access on your Macs.") }
        }
        .navigationTitle("SSH Key").directInlineNavigationTitle()
        .fileExporter(isPresented: $exporting, document: exportData.map(SSHKeyDocument.init(data:)), contentType: .data, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { issue = .make(DirectCancellation.isCancellation(error) ? .exportCancelled : .exportFailed) }
            exportData = nil; passphrase = ""; confirmPassphrase = ""
        }
        .confirmationDialog("Delete this key and its local selections?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Key", role: .destructive) { library.perform { try TerminalKeyLibraryStore.delete(entry.id) }; changed(); if library.error == nil { dismiss() } }
        }
        .onDisappear { clearExport() }
        .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.willResignActive)) { _ in
            // A system authentication prompt temporarily resigns active without backgrounding.
            passphrase = ""; confirmPassphrase = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in clearExport() }
    }
    private var publicLine: String { entry.key.publicKey + " mac-companion-" + entry.id.uuidString.lowercased() }
    private var filename: String { "ssh-" + entry.id.uuidString.lowercased() }
    private func clearExport() { generation = UUID(); authentication?.invalidate(); authentication = nil; exportData = nil; exporting = false; passphrase = ""; confirmPassphrase = ""; busy = false }
    private func exportPrivate() {
        guard !busy, DirectAppLockV1.shared.canAccess else { return }
        let token = generation, secret = passphrase, context = LAContext()
        authentication = context; busy = true; issue = nil; passphrase = ""; confirmPassphrase = ""
        Task {
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Export this SSH private key in encrypted form.") else { throw CancellationError() }
                guard token == generation, DirectAppLockV1.shared.canAccess,
                      let current = try TerminalKeyLibraryStore.load().keys.first(where: { $0.id == entry.id }) else { throw CancellationError() }
                let data = try await Task.detached(priority: .userInitiated) {
                    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: current.key.seed)
                    return Data(try key.makeEncryptedSSHRepresentation(passphrase: secret, comment: current.name).utf8)
                }.value
                guard token == generation, DirectAppLockV1.shared.canAccess else { return }
                exportFilename = filename; exportData = data; exporting = true
            } catch { if token == generation { self.issue = .make(DirectCancellation.isCancellation(error) ? .exportCancelled : .exportFailed) } }
            if token == generation { busy = false; authentication = nil }
        }
    }
}
#endif
