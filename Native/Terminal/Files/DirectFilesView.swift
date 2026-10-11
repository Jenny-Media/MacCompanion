#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct DirectFilesView: View {
    let mac: DirectMacRecordV1
    let retainWhenDismissed: Bool
    @State private var session: DirectFilesSession
    @State private var login = TerminalLoginSelection()
    @State private var password = ""
    @State private var remember = false
    @State private var key: TerminalNamedKey?
    @State private var keyName = ""
    @State private var passphrase = ""
    @State private var preparingKey = false
    @State private var preparation = UUID()
    #if os(macOS)
    @State private var keyFile: MacSSHKeyFileReference?
    @State private var savePicker = DirectFilesMacPicker()
    #endif
    @State private var sheet: Sheet?
    @State private var picker = false
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var disconnectConfirmation = false
    @State private var uploadURLs: [URL] = []
    @State private var uploadFolder = ""
    @State private var export: Export?
    @State private var loaded = false
    @State private var pro = DirectProAccess.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Sheet: String, Identifiable { case keys, setup, upload, pro; var id: String { rawValue } }
    private struct Export: Identifiable { let id = UUID(); let resultID: UUID; let url: URL }
    init(mac: DirectMacRecordV1, session: DirectFilesSession? = nil, retainWhenDismissed: Bool = false) {
        self.mac = mac; self.retainWhenDismissed = retainWhenDismissed
        _session = State(initialValue: session ?? DirectFilesSession(mac: mac))
    }
    private var canConnect: Bool {
        !login.username.isEmpty && !session.busy && !preparingKey &&
        (login.method == .password ? !password.isEmpty : !keyName.isEmpty)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                identity
                Divider()
                if session.phase == .ready { browser }
                else { signIn }
                if !session.results.isEmpty { transferResults }
            }
            .background(background)
            .navigationTitle("Files")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") {
                    if !retainWhenDismissed && session.transferActive { disconnectConfirmation = true }
                    else { dismiss() }
                }.accessibilityIdentifier("files-done") }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Setup Guide", systemImage: "questionmark.circle") { sheet = .setup }
                        if session.phase == .ready { Button("Disconnect Files", systemImage: "power") {
                            if session.transferActive { disconnectConfirmation = true } else { session.disconnect() }
                        } }
                    }
                }
            }
            .sheet(item: $sheet, onDismiss: { loadLogin() }) { destination in
                switch destination {
                case .keys:
                    #if os(macOS)
                    MacSSHKeyManager(mac: mac, changed: { loadLogin(preferSelected: true) }).modifier(MacSheetPrivacyCover())
                    #else
                    TerminalKeySettings(mac: mac, changed: { loadLogin(preferSelected: true) }).directAppearance()
                    #endif
                case .setup: DirectMacSetupGuide().directAppearance()
                case .upload: uploadReview
                case .pro: DirectProView().directAppearance()
                }
            }
            .sheet(item: Binding(get: { session.trust }, set: { if $0 == nil { session.answerTrust(false) } })) { trust in
                TerminalServerTrustView(macName: mac.name, fingerprint: trust.fingerprint, answer: session.answerTrust).directAppearance()
            }
            .confirmationDialog("A file named \(session.conflict?.name ?? "") already exists", isPresented: Binding(get: { session.conflict != nil }, set: { if !$0 { session.answerConflict(.cancel) } }), titleVisibility: .visible) {
                Button("Keep Both") { session.answerConflict(.keepBoth) }
                if session.conflict?.replaceAllowed == true { Button("Replace", role: .destructive) { session.answerConflict(.replace) } }
                Button("Cancel", role: .cancel) { session.answerConflict(.cancel) }
            }
            .alert("New Folder", isPresented: $newFolder) {
                TextField("Folder name", text: $folderName)
                Button("Create") { session.createFolder(folderName); folderName = "" }.disabled(!DirectFilesPolicy.validName(folderName))
                Button("Cancel", role: .cancel) { folderName = "" }
            }
            .confirmationDialog("Stop the current transfer?", isPresented: $disconnectConfirmation, titleVisibility: .visible) {
                Button("Stop Transfer", role: .destructive) { session.disconnect(message: "Transfer stopped. Reconnect and Retry when ready."); if !retainWhenDismissed { dismiss() } }
            } message: { Text("Completed files are kept. Unfinished uploads may leave a temporary file on the Mac.") }
            #if os(iOS)
            .sheet(isPresented: $picker) { DirectFilesDocumentPicker { result in picker = false; selected(result) } }
            .sheet(item: $export) { item in DirectFilesDocumentPicker(exporting: item.url) { result in
                export = nil
                if case .success = result { session.markSaved(item.resultID) }
            } }
            #else
            .fileImporter(isPresented: $picker, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: selected)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                guard session.phase == .ready, !session.busy, providers.count <= DirectFilesPolicy.maximumBatch else { return false }
                uploadFolder = session.directory?.path ?? ""
                let token = preparation
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                                continuation.resume(returning: url)
                            }
                        }
                        guard preparation == token, DirectAppLockV1.shared.canAccess else { return }
                        if let url { urls.append(url) }
                    }
                    selected(.success(urls))
                }
                return true
            }
            #endif
        }
        .directAppearance()
        .task { if !loaded { loaded = true; if !pro.ready { await pro.refresh() }; loadLogin(preferSelected: true) } }
        .onChange(of: session.phase) { _, phase in if phase == .ready { password = ""; passphrase = "" } }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
            if !allowed {
                preparation = UUID(); preparingKey = false; session.disconnect(); sheet = nil; picker = false; export = nil; password = ""; passphrase = ""; key = nil; keyName = ""; uploadURLs = []; newFolder = false; folderName = ""
                #if os(macOS)
                savePicker.cancel()
                #endif
            }
            else { loadLogin(preferSelected: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in
            preparation = UUID(); preparingKey = false
            #if os(macOS)
            savePicker.cancel()
            #endif
            password = ""; passphrase = ""; picker = false; export = nil
        }
        .onDisappear {
            preparation = UUID(); preparingKey = false; password = ""; passphrase = ""
            #if os(macOS)
            savePicker.cancel()
            #endif
            if !retainWhenDismissed { session.close() }
        }
        .interactiveDismissDisabled(!retainWhenDismissed && session.transferActive)
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 720, minHeight: 480, idealHeight: 640)
        #endif
    }
    private var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    private var identity: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identityDetails
                    connectionStatus
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    identityDetails
                    Spacer()
                    connectionStatus
                }
            }
        }.padding().accessibilityElement(children: .combine)
    }
    private var identityDetails: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mac.family.symbol).font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(mac.name).font(.headline).lineLimit(2)
                Text(session.account.isEmpty ? "SSH · Port \(mac.sshPort)" : "Account: " + session.account)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.layoutPriority(1)
        }
    }
    private var connectionStatus: some View {
        HStack(spacing: 6) {
            if session.busy { ProgressView().controlSize(.small) }
            Text(session.activityTitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var signIn: some View {
        Form {
            Section {
                Label("Requires Remote Login", systemImage: "terminal").font(.headline)
                Text("Enable Remote Login in System Settings → General → Sharing. Allow your account.").font(.subheadline).foregroundStyle(.secondary)
                Text("Uses your Terminal login settings. Other sessions stay connected.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sign In to " + mac.name) {
                Picker("Sign in with", selection: Binding(get: { login.method }, set: { login.select($0) })) {
                    ForEach(TerminalLoginMethod.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                #if os(macOS)
                MacCredentialFields(username: $login.username, password: $password, showsPassword: login.method == .password,
                                    enabled: !session.busy && !preparingKey && DirectAppLockV1.shared.canAccess, prefix: "files", submit: connect)
                    .frame(height: login.method == .password ? 104 : 45)
                #else
                TextField("Mac account", text: $login.username).textContentType(.username).directNoAutocapitalization().autocorrectionDisabled().accessibilityIdentifier("files-account")
                #endif
                if login.method == .password {
                    #if os(iOS)
                    SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("files-password")
                    #endif
                    Toggle("Save SSH login on this device", isOn: $remember)
                } else {
                    Button { sheet = .keys } label: { Label(keyName.isEmpty ? "Choose SSH Key" : keyName, systemImage: "key") }
                    #if os(macOS)
                    if keyFile != nil { SecureField("Key passphrase, if needed", text: $passphrase) }
                    #endif
                }
            }.disabled(session.busy || preparingKey)
            Section {
                if session.busy || preparingKey { Button("Cancel Connection") { preparation = UUID(); preparingKey = false; session.disconnect(); password = ""; passphrase = "" } }
                else { Button("Connect Files", systemImage: "folder") { connect() }.buttonStyle(.borderedProminent).disabled(!canConnect).accessibilityIdentifier("files-connect") }
            }
            if let message = session.message { Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) } }
        }.formStyle(.grouped)
    }
    private var browser: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Home", systemImage: "house") { session.browse(session.home) }
                Button("Up", systemImage: "arrow.up") { if let path = session.directory?.path { session.browse(DirectFilesPolicy.parent(path)) } }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { if let path = session.directory?.path { session.browse(path) } }
            }.buttonStyle(.borderless).padding(.horizontal).padding(.vertical, 10).disabled(session.busy)
            Text(session.directory?.path ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).textSelection(.enabled)
            if !uploadURLs.isEmpty { Text("Choose a folder, then tap Upload Here to review \(uploadURLs.count) selected files.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal) }
            if let message = session.message { Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.secondary).padding() }
            List {
                if session.directory?.entries.isEmpty == true { ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("Upload a file here or create a folder.")) }
                ForEach(session.directory?.entries ?? []) { entry in
                    HStack {
                        Button {
                            if entry.kind == .folder, let path = session.directory?.path, let child = try? DirectFilesPolicy.child(entry.name, of: path) { session.browse(child) }
                            else if entry.kind == .file { session.download(entry) }
                        } label: {
                            Label { VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).foregroundStyle(.primary).lineLimit(2)
                                if entry.kind == .file, let size = entry.size { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                                if entry.kind == .other { Text("Link or special file").font(.caption).foregroundStyle(.secondary) }
                            } } icon: { Image(systemName: entry.symbol).foregroundStyle(.tint) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(entry.kind == .other || session.busy)
                        if entry.kind == .folder { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        else if entry.kind == .file { Button("Download", systemImage: "arrow.down.to.line") { session.download(entry) }.labelStyle(.iconOnly).buttonStyle(.borderless).disabled(session.busy) }
                    }
                }
            }.accessibilityIdentifier("files-list")
            HStack {
                Button("New Folder", systemImage: "folder.badge.plus") { folderName = ""; newFolder = true }
                Spacer()
                Button("Upload Here", systemImage: "arrow.up.doc") { uploadFolder = session.directory?.path ?? ""; if uploadURLs.isEmpty { picker = true } else { sheet = .upload } }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("files-upload")
            }.padding().disabled(session.busy)
        }
    }
    private var transferResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("Transfers").font(.headline)
                Spacer()
                if session.transferActive { Button("Cancel") { session.disconnect(message: "Transfer stopped. Reconnect and Retry when ready.") } }
            }
            Text("Account: " + session.resultsAccount).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(session.results) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.destinationName ?? result.name).font(.subheadline).lineLimit(1)
                                Text(result.message).font(.caption).foregroundStyle(.secondary)
                                if result.outcome == .transferring {
                                    if let total = result.total, total > 0 { ProgressView(value: min(1, Double(result.bytes) / Double(total))) }
                                    else { ProgressView() }
                                }
                            }
                            Spacer()
                            if let url = result.localDownload { Button("Save…") { saveDownload(result.id, url: url) }.disabled(!DirectAppLockV1.shared.canAccess) }
                            if result.outcome == .interrupted { Button("Retry") { session.retry(result.id) }.disabled(session.busy || session.phase != .ready || session.account != session.resultsAccount) }
                        }
                    }
                }
            }.frame(maxHeight: 160)
            if session.phase == .ready && session.account != session.resultsAccount { Text("Reconnect as \(session.resultsAccount) to retry these transfers.").font(.caption).foregroundStyle(.secondary) }
            #if os(iOS)
            if session.transferActive { Text("Keep the app open until the transfer finishes.").font(.caption).foregroundStyle(.secondary) }
            #endif
        }.padding(.horizontal).padding(.bottom, 12)
    }
    private var uploadReview: some View {
        NavigationStack {
            Form {
                Section("Upload to") {
                    Label(mac.name + " · " + session.account, systemImage: "desktopcomputer")
                    Text(uploadFolder).font(.footnote.monospaced()).textSelection(.enabled)
                    Button("Change Folder") { sheet = nil }
                }
                Section("Files") { ForEach(uploadURLs, id: \.self) { url in Label(url.lastPathComponent, systemImage: "doc") } }
            }
            .navigationTitle("Upload Files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sheet = nil; uploadURLs = [] } }
                ToolbarItem(placement: .confirmationAction) { Button("Upload") { session.upload(uploadURLs, to: uploadFolder); sheet = nil; uploadURLs = [] }.disabled(session.phase != .ready || session.busy) }
            }
        }.directAppearance()
    }
    private func selected(_ result: Result<[URL], Error>) {
        guard DirectAppLockV1.shared.canAccess else { return }
        switch result {
        case .success(let urls):
            let token = preparation
            Task { @MainActor in
                do { let staged = try await session.prepare(urls); guard preparation == token, DirectAppLockV1.shared.canAccess else { return }; uploadURLs = staged; sheet = .upload }
                catch { if preparation == token, DirectAppLockV1.shared.canAccess, !(error is CancellationError) { session.message = DirectFilesSession.operationMessage(error) } }
            }
        case .failure(let error): if !(error is CancellationError) { session.message = "These files could not be selected. Try again." }
        }
    }
    private func saveDownload(_ id: UUID, url: URL) {
        guard DirectAppLockV1.shared.canAccess else { return }
        #if os(iOS)
        export = .init(resultID: id, url: url)
        #else
        let token = preparation
        savePicker.save(url) { result in
            guard preparation == token, DirectAppLockV1.shared.canAccess else { return }
            if case .success = result { session.markSaved(id) }
            else if case .failure(let error) = result, !(error is CancellationError) { session.message = "The downloaded file could not be saved. Choose another destination." }
        }
        #endif
    }
    private func loadLogin(preferSelected: Bool = false) {
        guard DirectAppLockV1.shared.canAccess, session.phase != .ready, !session.busy else { return }
        do {
            if let saved = try TerminalSecretStore.login(mac.id) { login.loadPasswordAccount(saved.username); password = saved.password; remember = true }
            #if os(macOS)
            if let selection = try MacSSHKeyFileStore.selected(mac.id) {
                keyFile = selection.file; key = nil; keyName = selection.file.name
                login.loadKeyAccount(selection.username, preferSelected: preferSelected); return
            }; keyFile = nil
            #endif
            key = try TerminalKeyLibraryStore.selected(mac.id); keyName = key?.name ?? ""
            login.loadKeyAccount(key?.key.username, preferSelected: preferSelected)
        } catch { session.message = "Saved SSH settings could not be read. Existing data is kept." }
    }
    private func connect() {
        guard canConnect, DirectAppLockV1.shared.canAccess else { return }
        let token = UUID()
        preparation = token; preparingKey = true
        Task { @MainActor in
            defer { if preparation == token { preparingKey = false } }
            if !pro.ready { await pro.refresh() }
            guard preparation == token, DirectAppLockV1.shared.canAccess else { return }
            let library = DirectMacLibraryV1()
            guard library.readable, pro.canUseMac(mac.id, among: library.macs.map(\.id)) else { sheet = .pro; return }
            if login.method == .sshKey {
                #if os(macOS)
                if let file = keyFile {
                    do {
                        guard try MacSSHKeyFileStore.canUse(file) else { sheet = .pro; return }
                        let account = login.username, secret = passphrase
                        passphrase = ""
                        let parsed = try await Task.detached { try file.read(passphrase: secret) }.value
                        guard preparation == token, DirectAppLockV1.shared.canAccess,
                              try MacSSHKeyFileStore.selected(mac.id)?.file == file else { return }
                        guard try MacSSHKeyFileStore.canUse(file) else { sheet = .pro; return }
                        session.connect(username: account, password: "", key: parsed, remember: false, keyFileID: file.id)
                    } catch { if preparation == token, DirectAppLockV1.shared.canAccess { session.message = error.localizedDescription } }
                    return
                }
                #endif
                do {
                    guard let key, try TerminalKeyLibraryStore.canUse(key) else { sheet = .pro; return }
                    session.connect(username: login.username, password: "", key: key.key, remember: false)
                } catch { session.message = "The selected key is unavailable. Choose an SSH key and retry." }
            } else { session.connect(username: login.username, password: password, key: nil, remember: remember) }
        }
    }
}
#endif
