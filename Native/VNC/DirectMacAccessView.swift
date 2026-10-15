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
                    Text("One login for Desktop, Trackpad & Keyboard and Files. Terminal uses it unless you choose an SSH override.").foregroundStyle(.secondary)
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
                    TextField("Mac account username", text: username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("access-account")
                    SecureField("Mac account password", text: password).textContentType(.password).accessibilityIdentifier("access-password")
                } header: { Text("Mac Login") } footer: { Text("Stored once in this device’s Keychain. Saving here does not change the password on your Mac.") }
                    .disabled(!draft.editable).privacySensitive()
                Section {
                    Picker("Sign in with", selection: $draft.value.sshMethod) {
                        Text("Use Mac Login").tag(DirectMacAccessProfile.SSHMethod.inherit)
                        Text("SSH Key").tag(DirectMacAccessProfile.SSHMethod.key)
                        Text("Different Password Login").tag(DirectMacAccessProfile.SSHMethod.password)
                    }.accessibilityIdentifier("access-ssh-method")
                    if draft.value.sshMethod == .key {
                        if let selected = draft.value.keyID, !keys.contains(where: { $0.id == selected }) {
                            Text("The selected key is unavailable. Choose another key or use the Mac login.").foregroundStyle(.secondary)
                        }
                        Picker("SSH Key", selection: $draft.value.keyID) {
                            Text("Choose a key").tag(Optional<UUID>.none)
                            ForEach(keys) { Text($0.name).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("access-ssh-key")
                        TextField("SSH account username", text: $draft.value.keyUsername).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    } else if draft.value.sshMethod == .password {
                        TextField("SSH account username", text: sshUsername).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                        SecureField("SSH account password", text: sshPassword).textContentType(.password)
                    }
                } header: { Text("SSH Override") } footer: {
                    Text("Applies to Terminal and Files opened from Terminal. Files opened from Desktop or Trackpad uses that session’s account. Screen Sharing still needs the Mac password.")
                }.disabled(!draft.editable).privacySensitive()
                Section {
                    Button("SSH Key Library", systemImage: "key") { keyLibrary = true }
                    Button("Forget Saved Login", systemImage: "key.slash", role: .destructive) { forgetConfirmation = true }.disabled(!draft.editable)
                }
                Section { Text("Credentials stay on this device and are excluded from iCloud Sync.").font(.footnote).foregroundStyle(.secondary) }
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
    private func load() { draft.load(); loadKeys() }
    private func loadKeys() { do { keys = try TerminalKeyLibraryStore.load().keys } catch { draft.message = "The SSH key library could not be read. Existing keys are kept." } }
}
#endif
