#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import Observation
import UIKit

enum DirectSavedLoginService: String {
    case desktop, terminal
    var title: String { self == .desktop ? "Desktop Login" : "Terminal Login" }
    var accountLimit: Int { self == .desktop ? 63 : 255 }
    var passwordLimit: Int { self == .desktop ? 63 : 4096 }
}

@MainActor @Observable final class DirectSavedLoginDraft {
    let service: DirectSavedLoginService
    var username = ""
    var password = ""
    private(set) var readable = false
    var recovery: DirectRecoveryNotice?
    private let read: () throws -> DesktopCredentialStoreV1.Login?
    private let write: (DesktopCredentialStoreV1.Login) throws -> Void
    init(macID: UUID, service: DirectSavedLoginService,
         read: (() throws -> DesktopCredentialStoreV1.Login?)? = nil,
         write: ((DesktopCredentialStoreV1.Login) throws -> Void)? = nil) {
        self.service = service
        self.read = read ?? {
            if service == .desktop { return try DesktopCredentialStoreV1.readChecked(macID) }
            return try TerminalSecretStore.login(macID).map { .init(username: $0.username, password: $0.password) }
        }
        self.write = write ?? { login in
            if service == .desktop { try DesktopCredentialStoreV1.save(login, hostID: macID) }
            else { try TerminalSecretStore.save(.init(username: login.username, password: login.password), id: macID) }
        }
    }
    var valid: Bool {
        readable && !username.isEmpty && !password.isEmpty &&
        username.utf8.count <= service.accountLimit && password.utf8.count <= service.passwordLimit &&
        !username.contains("\0") && !password.contains("\0")
    }
    func load() {
        guard !readable else { return }
        do {
            guard DirectAppLockV1.shared.canAccess else { throw DesktopCredentialStoreV1.StoreFailure.unavailable }
            let login = try read(); username = login?.username ?? ""; password = login?.password ?? ""
            readable = true; recovery = nil
        } catch { recovery = .make(.savedDataUnavailable, message: "This saved login couldn’t be read. It has been kept; retry before editing.") }
    }
    func save() -> Bool {
        guard valid, DirectAppLockV1.shared.canAccess else { return false }
        do {
            // Recheck availability before replacing the existing item.
            _ = try read()
            try write(.init(username: username, password: password)); recovery = nil; return true
        } catch { recovery = .make(.saveFailed, message: "The previous saved login is kept. Your draft is still here; retry when Keychain is available."); return false }
    }
    func clear() { username = ""; password = ""; readable = false; recovery = nil }
}

struct DirectSavedLoginEditor: View {
    @Environment(\.dismiss) private var dismiss
    let mac: DirectMacRecordV1
    @State private var draft: DirectSavedLoginDraft
    init(mac: DirectMacRecordV1, service: DirectSavedLoginService) {
        self.mac = mac; _draft = State(initialValue: DirectSavedLoginDraft(macID: mac.id, service: service))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(mac.name, systemImage: draft.service == .desktop ? "desktopcomputer" : "terminal").font(.headline)
                    Text("Update the login saved on this iPhone for your next connection.").foregroundStyle(.secondary)
                }
                if let notice = draft.recovery {
                    Section { DirectRecoveryCard(notice: notice, primary: .init(title: draft.readable ? "Try Saving Again" : "Retry", perform: {
                        if draft.readable { if draft.save() { dismiss() } } else { draft.load() }
                    })) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    TextField("Mac account username", text: $draft.username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .accessibilityIdentifier("saved-login-username")
                    SecureField("Mac account password", text: $draft.password).textContentType(.password).privacySensitive()
                        .accessibilityIdentifier("saved-login-password")
                } header: { Text("Mac Account") } footer: {
                    Text("Account: up to \(draft.service.accountLimit) UTF-8 bytes. Password: up to \(draft.service.passwordLimit) UTF-8 bytes. Both are required.")
                }.disabled(!draft.readable)
                Section {
                    Text("This saves a login locally; it doesn’t change your Mac’s account password or test a connection. Desktop and Terminal logins are separate and aren’t included in iCloud Sync.")
                    if draft.service == .terminal { Text("This edits password login. Your selected SSH key and its account are kept.") }
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(draft.service.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if draft.save() { dismiss() } }.disabled(!draft.valid).accessibilityIdentifier("saved-login-save") }
            }
            .onAppear { draft.load() }
            .onDisappear { draft.clear() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in draft.clear(); dismiss() }
        }
    }
}
#endif
