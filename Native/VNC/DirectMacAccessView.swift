#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

@MainActor @Observable final class DirectMacAccessDraft {
    let macID: UUID
    var value = DirectMacAccessProfile()
    private(set) var original: DirectMacAccessProfile?
    var message: String?
    init(macID: UUID) { self.macID = macID }
    var editable: Bool { original != nil && !DirectMacConnections.shared.isActive(macID) }
    func load() {
        guard original == nil else { return }
        do { value = try DirectMacAccessStore.load(macID); original = value; message = nil }
        catch { message = "Saved access settings could not be read. They have been kept. Retry before editing." }
    }
    func save() -> Bool {
        guard let original else { return false }
        do {
            if value.sshMethod == .key, value.keyID != original.keyID || original.sshMethod != .key {
                guard let keyID = value.keyID, let selected = try TerminalKeyLibraryStore.load().keys.first(where: { $0.id == keyID }),
                      try TerminalKeyLibraryStore.canUse(selected) else { message = "Choose an available SSH key. Check Pro access if this key is outside the free allowance."; return false }
            }
            try DirectMacAccessStore.save(value, id: macID, replacing: original); self.original = value; message = nil; return true }
        catch DirectMacAccessStore.Failure.busy { message = "Disconnect this Mac before changing its login." }
        catch DirectMacAccessStore.Failure.changed { message = "Access settings changed elsewhere. Close and reopen this editor to review them." }
        catch { message = "The login could not be saved. Check the account, password and SSH selection. Existing settings are kept." }
        return false
    }
    func clear() { value = .init(); original = nil; message = nil }
}

struct DirectMacAccessView: View {
    let mac: DirectMacRecordV1
    @State private var draft: DirectMacAccessDraft
    @State private var connections = DirectMacConnections.shared
    @State private var keys: [TerminalNamedKey] = []
    @State private var disconnectConfirmation = false
    @State private var disconnecting = false
    @State private var keyLibrary = false
    @State private var forgetConfirmation = false
    @Environment(\.dismiss) private var dismiss
    init(mac: DirectMacRecordV1) { self.mac = mac; _draft = State(initialValue: DirectMacAccessDraft(macID: mac.id)) }
    private var busy: Bool { connections.isActive(mac.id) }
    private var username: Binding<String> { .init(get: { draft.value.login?.username ?? "" }, set: { draft.value.login = .init(username: $0, password: draft.value.login?.password ?? "") }) }
    private var password: Binding<String> { .init(get: { draft.value.login?.password ?? "" }, set: { draft.value.login = .init(username: draft.value.login?.username ?? "", password: $0) }) }
    private var sshUsername: Binding<String> { .init(get: { draft.value.sshPassword?.username ?? "" }, set: { draft.value.sshPassword = .init(username: $0, password: draft.value.sshPassword?.password ?? "") }) }
    private var sshPassword: Binding<String> { .init(get: { draft.value.sshPassword?.password ?? "" }, set: { draft.value.sshPassword = .init(username: draft.value.sshPassword?.username ?? "", password: $0) }) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Label(mac.name, systemImage: "desktopcomputer").font(.headline)
                    Text("Enter the username and password you use to sign in to this Mac.").foregroundStyle(.secondary)
                }
                if busy {
                    Section {
                        Label("Disconnect this Mac to edit its login", systemImage: "lock.fill")
                        Text("Its connections and transfers keep using the account they signed in with.").font(.footnote).foregroundStyle(.secondary)
                        Button(disconnecting ? "Disconnecting…" : "Disconnect & Edit", role: .destructive) { disconnectConfirmation = true }
                            .disabled(disconnecting).accessibilityIdentifier("access-disconnect-edit")
                    }
                }
                if let message = draft.message { Section { Text(message).foregroundStyle(.secondary); if draft.original == nil { Button("Retry") { load() } } } }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username").font(.caption).foregroundStyle(.secondary)
                        TextField("Username", text: username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("access-account")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.caption).foregroundStyle(.secondary)
                        SecureField("Password", text: password).textContentType(.password).accessibilityIdentifier("access-password")
                    }
                } header: { Text("Mac Account") } footer: { Text("Saved securely on this device for future connections. This does not change your Mac’s password.") }
                    .disabled(!draft.editable).privacySensitive()
                Section {
                    Picker("Sign in with", selection: $draft.value.sshMethod) {
                        Text("Use Mac Account").tag(DirectMacAccessProfile.SSHMethod.inherit)
                        Text("SSH Key").tag(DirectMacAccessProfile.SSHMethod.key)
                        Text("Different Account").tag(DirectMacAccessProfile.SSHMethod.password)
                    }.accessibilityIdentifier("access-ssh-method")
                    if draft.value.sshMethod == .key {
                        if let selected = draft.value.keyID, !keys.contains(where: { $0.id == selected }) {
                            Text("The selected key is unavailable. Choose another key or use the Mac account.").foregroundStyle(.secondary)
                        }
                        Picker("SSH Key", selection: $draft.value.keyID) {
                            Text("Choose a key").tag(Optional<UUID>.none)
                            ForEach(keys) { Text($0.name).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("access-ssh-key")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username").font(.caption).foregroundStyle(.secondary)
                            TextField("Username", text: $draft.value.keyUsername).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).accessibilityIdentifier("access-terminal-account")
                        }
                    } else if draft.value.sshMethod == .password {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username").font(.caption).foregroundStyle(.secondary)
                            TextField("Username", text: sshUsername).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).accessibilityIdentifier("access-terminal-account")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password").font(.caption).foregroundStyle(.secondary)
                            SecureField("Password", text: sshPassword).textContentType(.password).accessibilityIdentifier("access-terminal-password")
                        }
                    }
                } header: { Text("Terminal Sign-In") } footer: {
                    Text(terminalDescription)
                }.disabled(!draft.editable).privacySensitive()
                Section {
                    Button("SSH Key Library", systemImage: "key") { keyLibrary = true }
                    Button("Forget Saved Login", systemImage: "key.slash", role: .destructive) { forgetConfirmation = true }.disabled(!draft.editable)
                }
                Section { Text("Saved logins and SSH keys stay on this device and don’t sync with iCloud.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Login & Access").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if draft.save() { dismiss() } }.disabled(!draft.editable).accessibilityIdentifier("access-save") }
            }
            .onAppear(perform: load)
            .task { if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() } }
            .onChange(of: draft.value.keyID) { _, _ in
                if draft.value.keyUsername.isEmpty { draft.value.keyUsername = draft.value.login?.username ?? "" }
            }
            .sheet(isPresented: $keyLibrary, onDismiss: loadKeys) { TerminalKeySettings(embedded: false).directAppearance() }
            .confirmationDialog("Disconnect from " + mac.name + "?", isPresented: $disconnectConfirmation, titleVisibility: .visible) {
                Button("Disconnect & Edit", role: .destructive) {
                    disconnecting = true
                    Task { @MainActor in
                        let finished = await connections.disconnect(mac.id)
                        disconnecting = false
                        if !finished { draft.message = "Connections are still closing. Wait a moment and retry." }
                    }
                }
            } message: { Text(connections.hasTransfers(mac.id) ? "Active file transfers will be interrupted. Completed downloads are kept so you can save them." : "Desktop, Terminal and Files connections to this Mac will close. Other Macs stay connected.") }
            .confirmationDialog("Forget this Mac’s saved login?", isPresented: $forgetConfirmation, titleVisibility: .visible) {
                Button("Forget Saved Login", role: .destructive) {
                    guard draft.editable else { return }; draft.value = .init()
                    if draft.save() { dismiss() }
                }
            } message: { Text("Saved passwords and this Mac’s key selection are removed. Keys in the library and the verified SSH server identity are kept.") }
            .onDisappear { draft.clear() }
            .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in draft.clear(); dismiss() }
        }.directAppearance()
    }
    private var terminalDescription: String {
        switch draft.value.sshMethod {
        case .inherit: "Terminal uses your Mac account."
        case .key: "Terminal signs in using this SSH key. Desktop still requires your Mac password."
        case .password: "Terminal uses this account. Desktop still uses the Mac account above."
        }
    }
    private func load() { draft.load(); loadKeys() }
    private func loadKeys() { do { keys = try TerminalKeyLibraryStore.load().keys } catch { draft.message = "The SSH key library could not be read. Existing keys are kept." } }
}
#endif
