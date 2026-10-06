#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

struct TerminalKeyInstallView: View {
    let mac: DirectMacRecordV1
    var changed: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var library = TerminalKeyLibrary()
    @State private var session: DirectTerminalSession
    @State private var selectedKeyID: UUID?
    @State private var bootstrapKeyID: UUID?
    @State private var username: String
    @State private var password = ""
    @State private var useBootstrapKey = false
    @State private var manual = false
    @State private var identityGuide = false
    @State private var pro = false
    init(mac: DirectMacRecordV1, initialUsername: String = "", changed: @escaping @MainActor () -> Void = {}) {
        self.mac = mac; self.changed = changed
        _session = State(initialValue: DirectTerminalSession(mac: mac)); _username = State(initialValue: initialUsername)
    }
    private var target: TerminalNamedKey? { library.keys.first { $0.id == selectedKeyID } }
    private var bootstrap: TerminalSSHKey? { library.keys.first { $0.id == bootstrapKeyID }?.key }
    private var accountValid: Bool { !username.isEmpty && username.utf8.count <= 255 && !username.contains("\0") }
    private var valid: Bool { target != nil && accountValid && (useBootstrapKey ? bootstrap != nil : !password.isEmpty && password.utf8.count <= 4096 && !password.contains("\0")) && library.readable }
    private var uncertain: Bool { session.recovery != nil && session.setupPhase.mayBeInstalled && session.installedKey == nil }
    private var canTest: Bool { target != nil && accountValid && library.readable && !session.connecting }
    private func install() {
        guard let target, DirectProAccess.shared.hasPro, valid else { pro = true; return }
        session.connect(username: username, password: useBootstrapKey ? "" : password,
            remember: false, key: useBootstrapKey ? bootstrap : nil, installation: target)
        password = ""
    }
    private func test() {
        guard let target, canTest else { return }
        session.testKeyLogin(username: username, target: target)
    }
    private var recoveryPrimary: DirectRecoveryAction? {
        guard let reason = session.recovery?.reason else { return nil }
        if reason == .setupVerified { return nil }
        if reason == .serverChanged { return .init(title: "How to Verify", perform: { identityGuide = true }) }
        if [.setupUncertain, .setupLoginUnverified, .setupPreferenceUnverified, .keyRejected].contains(reason) && canTest {
            return .init(title: "Test Key Login", symbol: "key", perform: test)
        }
        return .init(title: "Review Setup") { session.clearRecovery() }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add your public key").font(.title2.bold())
                    Text("Allow a key on this iPhone to sign in to \(mac.name).").foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
                if let notice = session.recovery {
                    Section { DirectRecoveryCard(notice: notice, primary: recoveryPrimary,
                        secondary: [.setupVerified, .serverChanged].contains(notice.reason) ? nil : .init(title: "Manual Steps") { manual = true }) }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if let notice = library.recovery { Section { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry") { load() }) } }
                Section("Target Account & Key") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac account").font(.caption).foregroundStyle(.secondary)
                        TextField("Mac account username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Picker("SSH Key", selection: $selectedKeyID) {
                        Text("Choose a Key").tag(nil as UUID?)
                        ForEach(library.keys) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if let target { DisclosureGroup("Key Fingerprint") { Text(target.key.fingerprint).font(.caption.monospaced()).textSelection(.enabled) } }
                }.disabled(session.connecting || session.installedKey != nil || uncertain)
                if session.installedKey == nil {
                    Section {
                        if dynamicType.isAccessibilitySize {
                            Button("Use Password") { useBootstrapKey = false }
                            Button("Use Working Key") { useBootstrapKey = true }
                        } else {
                            Picker("Setup Login", selection: $useBootstrapKey) {
                                Text("Password").tag(false); Text("Working Key").tag(true)
                            }.pickerStyle(.segmented)
                        }
                        if useBootstrapKey {
                            Picker("Working Key", selection: $bootstrapKeyID) {
                                Text("Choose a Key").tag(nil as UUID?)
                                ForEach(library.keys) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } else { SecureField("Password for this Mac account", text: $password).textContentType(.password).privacySensitive() }
                    } header: { Text("Sign in Once to Install") } footer: {
                        Text("Use a login that already works for this account. This password is used only for setup and won’t be saved.")
                    }.disabled(session.connecting || uncertain)
                    Section {
                        Label("Add the public key", systemImage: [TerminalSetupPhase.acknowledged, .verified].contains(session.setupPhase) ? "checkmark.circle" : "1.circle")
                        Text("Keep existing authorized keys. Your private key stays on this iPhone.").font(.footnote).foregroundStyle(.secondary)
                        Label("Test key login", systemImage: session.setupPhase == .verified ? "checkmark.circle" : "2.circle")
                        Text("Verify a fresh key-only login before making this key preferred.").font(.footnote).foregroundStyle(.secondary)
                        if session.connecting {
                            ProgressView(session.setupProgress).accessibilityIdentifier("ssh-install-status")
                            Button("Cancel Setup") { session.cancelConnection(); password = "" }
                        }
                    }.listRowBackground(Color.clear)
                } else { Section { Text("Your preferred Terminal key is saved. Tap Done to return.").foregroundStyle(.secondary) } }
                Section { Button("Manual Key Setup") { manual = true } }
            }
            .safeAreaInset(edge: .bottom) {
                if session.installedKey == nil && !session.connecting && !uncertain {
                    VStack(spacing: 8) {
                        Button(action: install) { HStack { Text("Install Public Key"); if !DirectProAccess.shared.hasPro { DirectProBadge() } }.frame(maxWidth: .infinity, minHeight: 32) }
                            .buttonStyle(.glassProminent).controlSize(.large).disabled(!valid).accessibilityIdentifier("ssh-install-key")
                        if !valid { Text("Choose a key, enter the Mac account, and provide a working setup login.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(16).background(.bar)
                }
            }
            .navigationTitle("Set Up SSH Key").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { session.stop(); if session.installedKey != nil { changed() }; dismiss() } } }
            .sheet(isPresented: $identityGuide) { TerminalIdentityGuide(macName: mac.name) }
            .sheet(isPresented: $manual) { TerminalManualKeySetupView(mac: mac, keyID: selectedKeyID) }
            .sheet(isPresented: $pro) { DirectProView() }
            .sheet(item: $session.trust) { request in TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust) }
            .onAppear { load() }
            .onDisappear { password = ""; session.stop() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in password = ""; session.background() }
        }
    }
    private func load() {
        library.reload(macs: [mac])
        do {
            let selected = try TerminalKeyLibraryStore.selected(mac.id)
            selectedKeyID = selectedKeyID ?? selected?.id
            if username.isEmpty { username = selected?.key.username ?? "" }
            if let login = try TerminalSecretStore.login(mac.id) { if username.isEmpty { username = login.username }; password = login.password }
        } catch { library.recovery = .make(.savedDataUnavailable, message: "The saved setup login couldn’t be read. Existing data is kept.") }
    }
}

struct TerminalManualKeySetupView: View {
    let mac: DirectMacRecordV1
    var keyID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var library = TerminalKeyLibrary()
    @State private var selectedID: UUID?
    @State private var copied = false
    private var target: TerminalNamedKey? { library.keys.first { $0.id == selectedID } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a public key yourself").font(.title2.bold())
                    Text("Free manual setup for \(mac.name)").foregroundStyle(.secondary)
                }
                if let notice = library.recovery { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry") { library.reload(macs: [mac]) }) }
                Section("Public Key") {
                    Picker("Key", selection: $selectedID) { Text("Choose a Key").tag(nil as UUID?); ForEach(library.keys) { Text($0.name).tag(Optional($0.id)) } }
                    Button(copied ? "Public Key Copied" : "Copy Public Key", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        guard let target else { return }
                        UIPasteboard.general.string = target.key.publicKey + " mac-companion-" + target.id.uuidString.lowercased(); copied = true
                    }.disabled(target == nil)
                }
                Section("On Your Mac") {
                    Text("1. Sign in to the Mac account you will use for Terminal.")
                    Text("2. Add the public key as its own line in ~/.ssh/authorized_keys. Keep existing entries.")
                    Text("3. Make sure ~/.ssh is private to that account (mode 700), and authorized_keys is mode 600. Enable Remote Login for the account.")
                    Text("4. Return to Terminal, choose this key and connect. A successful login confirms the Mac accepts it.")
                }
                Text("Only the public key goes on the Mac. Never copy your private key into authorized_keys.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Manual Key Setup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { library.reload(macs: [mac]); selectedID = keyID ?? (try? TerminalKeyLibraryStore.selected(mac.id))?.id }
        }
    }
}
#endif
