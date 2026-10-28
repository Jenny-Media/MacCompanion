#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers

struct DirectLocalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= DirectLocalBackup.maximumBytes else { throw DirectLocalBackup.Failure.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DirectLocalBackupSettings: View {
    @State private var store: DirectLocalBackupStore
    @State private var lock = DirectAppLockV1.shared
    @State private var connections = DirectMacConnections.shared
    @State private var document: DirectLocalBackupDocument?
    @State private var exporting = false
    @State private var picking = false
    @State private var preparing = false
    @State private var notice: String?
    @State private var issue: String?
    @State private var importGeneration = UUID()
    @State private var selection: RestoreSelection?
    private struct RestoreSelection: Identifiable {
        let id = UUID()
        var backup: DirectLocalBackup
        var previous = false
    }
    init(library: DirectMacLibraryV1? = nil, store: DirectLocalBackupStore? = nil, preview: DirectLocalBackup? = nil) {
        _store = State(initialValue: store ?? DirectLocalBackupStore(library: library))
        _selection = State(initialValue: preview.map { RestoreSelection(backup: $0) })
    }
    private var working: Bool { preparing || store.busy }
    var body: some View {
        Form {
            Section {
                Button("Create Backup…", systemImage: "square.and.arrow.up", action: exportBackup)
                    .accessibilityIdentifier("backup-create")
                Button("Restore Backup…", systemImage: "square.and.arrow.down") {
                    importGeneration = UUID(); issue = nil; notice = nil; picking = true
                }.accessibilityIdentifier("backup-import")
            } footer: { Text("Save a copy in Files or on another device. iCloud isn’t required.") }
                .disabled(working || !lock.canAccess)
            Section("Included") {
                Label("Saved Macs and connection settings", systemImage: "desktopcomputer")
                Label("Keyboard layouts and shortcuts", systemImage: "keyboard")
                Label("Saved text and button positions", systemImage: "text.quote")
                Label("Recovered changes", systemImage: "arrow.clockwise")
            }
            Section {
                Label("Passwords, SSH keys and trusted identities aren’t included.", systemImage: "lock.shield")
            } footer: { Text("Backup files contain saved text and network addresses. Keep them private.") }
            if store.hasRecoveryCopy {
                Section {
                    Button("Restore Previous Data…", systemImage: "arrow.uturn.backward") {
                        do { selection = .init(backup: try store.recoveryPreview(), previous: true); issue = nil }
                        catch { issue = "The recovery copy couldn’t be read. Your current data is kept." }
                    }.accessibilityIdentifier("backup-previous").disabled(working)
                } header: { Text("Recovery Copy") } footer: { Text("A copy of your current data is kept before every restore.") }
            }
            if !connections.entries.isEmpty {
                Section { Label("Disconnect your sessions before restoring.", systemImage: "rectangle.connected.to.line.below") }
            }
            if working { Section { ProgressView(store.busy ? "Restoring…" : "Preparing backup…") } }
            if let problem = issue ?? store.problem {
                Section { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("backup-error") }
            } else if let status = notice ?? store.message {
                Section { Label(status, systemImage: "checkmark.circle").accessibilityIdentifier("backup-status") }
            }
        }.navigationTitle("Backup & Restore").directInlineNavigationTitle()
        .privacySensitive()
        .onAppear { store.refreshRecoveryCopy() }
        .onChange(of: lock.canAccess) { _, allowed in
            store.refreshRecoveryCopy()
            if !allowed {
                importGeneration = UUID(); selection = nil; document = nil
                exporting = false; picking = false; preparing = false; notice = nil; issue = nil
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
            defaultFilename: "Mac Companion Backup " + Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))) { [generation = importGeneration] result in
                guard generation == importGeneration else { return }
                defer { document = nil }
                guard lock.canAccess else { return }
                switch result {
                case .success: notice = "Backup saved."; issue = nil
                case .failure(let error): if !Self.cancelled(error) { issue = "The backup couldn’t be saved. Your data is kept." }
                }
            }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json], allowsMultipleSelection: false) { [generation = importGeneration] result in
            readSelection(result, generation: generation)
        }
        .sheet(item: $selection) { selected in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent("Created", value: selected.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Saved Macs", value: String(selected.backup.macs.count))
                        LabeledContent("Keyboard layouts", value: "2")
                        LabeledContent("Shortcuts", value: String(selected.backup.shortcutCount))
                        LabeledContent("Saved text", value: String(selected.backup.savedTextCount))
                        if selected.backup.recoveredCount > 0 { LabeledContent("Recovered changes", value: String(selected.backup.recoveredCount)) }
                    }
                    Section {
                        Label("Replaces saved Macs and controls on this device.", systemImage: "arrow.triangle.2.circlepath")
                        Label("Your current data is kept as a recovery copy.", systemImage: "arrow.uturn.backward")
                        if !selected.previous { Label("Sign in and confirm restored Macs again.", systemImage: "key") }
                        Label("iCloud Sync turns off. Existing iCloud data is kept.", systemImage: "icloud.slash")
                    }
                    if let problem = store.problem {
                        Section { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                    }
                    Section {
                        Button(role: .destructive) {
                            Task {
                                if selected.previous { await store.restorePrevious() }
                                else { await store.restore(selected.backup) }
                                if store.problem == nil { selection = nil }
                            }
                        } label: {
                            if store.busy { HStack { ProgressView(); Text("Restoring…") } }
                            else { Text(selected.previous ? "Restore Previous Data" : "Restore Backup") }
                        }.disabled(working || !lock.canAccess || !connections.entries.isEmpty)
                            .accessibilityIdentifier("backup-confirm-restore")
                    }
                }.navigationTitle(selected.previous ? "Previous Data" : "Restore Backup").directInlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selection = nil }.disabled(store.busy).accessibilityIdentifier("backup-cancel") } }
            }.directAppearance().interactiveDismissDisabled(store.busy)
        }
    }
    private func exportBackup() {
        guard !working, lock.canAccess else { return }
        importGeneration = UUID(); let generation = importGeneration
        preparing = true; issue = nil; notice = nil
        Task {
            await Task.yield()
            defer { if generation == importGeneration { preparing = false } }
            guard generation == importGeneration, lock.canAccess else { return }
            do { document = .init(data: try store.makeBackup().encoded()); exporting = true }
            catch { issue = "Saved data couldn’t be read. Existing data is kept. Try again when storage is available." }
        }
    }
    private func readSelection(_ result: Result<[URL], Error>, generation: UUID) {
        guard generation == importGeneration, lock.canAccess else { return }
        switch result {
        case .failure(let error): if !Self.cancelled(error) { issue = "The backup couldn’t be opened. Try selecting it again." }
        case .success(let urls):
            guard let url = urls.first, url.isFileURL else { issue = "Choose a Mac Companion backup file."; return }
            preparing = true
            Task {
                defer { if generation == importGeneration { preparing = false } }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let bytes = try await Task.detached {
                        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                        let data = try file.read(upToCount: DirectLocalBackup.maximumBytes + 1) ?? Data()
                        guard data.count <= DirectLocalBackup.maximumBytes else { throw DirectLocalBackup.Failure.tooLarge }
                        return data
                    }.value
                    guard generation == importGeneration, lock.canAccess else { return }
                    selection = .init(backup: try DirectLocalBackup.decode(bytes)); issue = nil
                } catch {
                    guard generation == importGeneration, lock.canAccess else { return }
                    switch error {
                    case DirectLocalBackup.Failure.newerVersion: issue = "Update Mac Companion to restore this backup."
                    case DirectLocalBackup.Failure.tooLarge: issue = "This backup is too large to open."
                    default: issue = "This isn’t a valid Mac Companion backup. Your data is kept."
                    }
                }
            }
        }
    }
    private static func cancelled(_ error: Error) -> Bool {
        error is CancellationError || (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError
    }
}
#endif
