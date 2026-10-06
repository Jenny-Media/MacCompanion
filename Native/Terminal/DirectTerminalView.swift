#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import SwiftTerm
import UIKit

struct DirectTerminalView: View {
    private var mac: DirectMacRecordV1 { session.mac }
    let macLibrary: DirectMacLibraryV1?
    let exit: @MainActor () -> Void
    @State private var session: DirectTerminalSession
    @State private var username = ""
    @State private var password = ""
    @State private var remember = false
    @State private var loginIssue: DirectRecoveryNotice?
    @State private var key: TerminalSSHKey?
    @State private var keyName = ""
    @State private var useKey = false
    private enum Sheet: String, Identifiable {
        case keys, install, manual, macSettings, appSettings, pro, keyboard, verifyGuide
        var id: String { rawValue }
    }
    @State private var sheet: Sheet?
    @Environment(DirectAppearanceV1.self) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var canConnect: Bool {
        !username.isEmpty && username.utf8.count <= 255 && !username.contains("\0") &&
        (useKey ? key != nil : !password.isEmpty && password.utf8.count <= 4096 && !password.contains("\0"))
    }
    init(mac: DirectMacRecordV1, macLibrary: DirectMacLibraryV1? = nil, session: DirectTerminalSession? = nil, exit: @escaping @MainActor () -> Void) {
        self.macLibrary = macLibrary; self.exit = exit; _session = State(initialValue: session ?? DirectTerminalSession(mac: mac))
    }
    private func connect() {
        if useKey {
            do {
                let library = try TerminalKeyLibraryStore.load()
                if let selected = try TerminalKeyLibraryStore.selected(mac.id), !DirectProAccess.shared.canUseKey(selected.id, among: library.keys.map(\.id)) { sheet = .pro; return }
            } catch { loginIssue = .make(.savedDataUnavailable, message: "The SSH key library couldn’t be read. Existing keys are kept."); return }
        }
        loginIssue = nil
        session.connect(username: username, password: useKey ? "" : password, remember: !useKey && remember, key: useKey ? key : nil)
    }
    private func loadKey() {
        do {
            let selected = try TerminalKeyLibraryStore.selected(mac.id)
            key = selected?.key; keyName = selected?.name ?? ""; useKey = selected != nil
            if let key, !key.username.isEmpty { username = key.username }
        } catch { loginIssue = .make(.savedDataUnavailable, message: "The selected SSH key couldn’t be read. Existing keys are kept.") }
    }
    private func loadLogin() {
        loginIssue = nil
        do { if let login = try TerminalSecretStore.login(mac.id) { username = login.username; password = login.password; remember = true } }
        catch { loginIssue = .make(.savedDataUnavailable, message: "The saved Terminal login couldn’t be read. Existing data is kept.") }
        loadKey()
    }
    private func setupKey() {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            sheet = DirectProAccess.shared.hasPro ? .install : .pro
        }
    }
    private func recoveryAction(_ notice: DirectRecoveryNotice) -> DirectRecoveryAction {
        switch notice.reason {
        case .keyRejected: .init(title: "Use Password", symbol: "person.badge.key") { useKey = false; session.clearRecovery() }
        case .loginRejected: .init(title: "Edit Login") { session.clearRecovery() }
        case .serverChanged: .init(title: "How to Verify", symbol: "lock.shield") { sheet = .verifyGuide }
        case .savedDataUnavailable: .init(title: "Retry", symbol: "arrow.clockwise") { loadLogin(); session.clearRecovery() }
        case .terminalEnded, .inputPaused: .init(title: "Open New Shell", symbol: "terminal") { if canConnect { connect() } else { session.clearRecovery() } }
        case .connectionCancelled: .init(title: "Return to Login") { session.clearRecovery() }
        default: .init(title: "Try Again", symbol: "arrow.clockwise") { if canConnect { connect() } else { session.clearRecovery() } }
        }
    }
    private func secondaryAction(_ notice: DirectRecoveryNotice) -> DirectRecoveryAction? {
        if notice.reason == .keyRejected { return .init(title: "Set Up Key on Mac", symbol: "key", pro: true, perform: setupKey) }
        if [.serverChanged, .connectionCancelled, .savedDataUnavailable].contains(notice.reason) { return nil }
        return .init(title: "Connection Settings", symbol: "gearshape") { sheet = .macSettings }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                TerminalSurface(session: session, style: appearance.terminal.style(app: appearance.app), customize: { sheet = .keyboard })
                    .opacity(session.connected ? 1 : 0).allowsHitTesting(session.connected).accessibilityHidden(!session.connected)
                if !session.connected { loginView }
                else if let notice = session.controlsRecovery {
                    VStack { DirectRecoveryCard(notice: notice,
                        primary: .init(title: "Keyboard Settings", perform: { sheet = .keyboard }),
                        secondary: .init(title: "Use Standard Controls", perform: { session.controlsRecovery = nil })).padding(12); Spacer() }
                }
            }
            .navigationTitle("\(mac.name) · Terminal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { session.stop(); exit() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if session.connected {
                            Section("Terminal") { Button(session.keyboardVisible ? "Hide Keyboard" : "Show Keyboard", systemImage: session.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard") { session.toggleKeyboard?() } }
                        }
                        Section("Keyboard") { Button("Customize Keys & Snippets", systemImage: "keyboard") { sheet = .keyboard } }
                        Section("Mac") {
                            Button("Choose or Manage Key", systemImage: "key") { sheet = .keys }
                            Button("Set Up Key on This Mac", systemImage: "key.horizontal") { setupKey() }
                            Button("Manual Key Setup", systemImage: "list.bullet") { sheet = .manual }
                            Button("Mac Settings", systemImage: "gearshape") { sheet = .macSettings }
                        }.disabled(session.connecting)
                        Section("Appearance") {
                            Picker("Terminal Colors", selection: Binding(get: { appearance.terminal }, set: { appearance.terminal = $0 })) {
                                ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
                            }
                            Button("App Settings", systemImage: "gearshape") { sheet = .appSettings }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Terminal Controls")
                }
            }
            .sheet(item: $sheet, onDismiss: { if let updated = macLibrary?.macs.first(where: { $0.id == mac.id }) { session.updateMac(updated) } }) { destination in
                switch destination {
                case .keys: TerminalKeySettings(mac: mac, changed: { loadKey(); session.clearRecovery() })
                case .install: TerminalKeyInstallView(mac: mac, initialUsername: username, changed: { loadKey(); session.clearRecovery() })
                case .manual: TerminalManualKeySetupView(mac: mac)
                case .macSettings:
                    if let macLibrary { DirectMacEditorV1(mac: mac, library: macLibrary) }
                    else { TerminalConnectionInfo(mac: mac) }
                case .appSettings: DirectSessionSettingsV1()
                case .pro: DirectProView()
                case .keyboard: TerminalKeyboardSettings(macID: mac.id, changed: { session.reloadKeyboard?() })
                case .verifyGuide: TerminalIdentityGuide(macName: mac.name)
                }
            }
            .sheet(item: $session.trust) { request in
                TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust)
            }
        }
        .onAppear { loadLogin() }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.background() }
    }
    private var loginView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.blue)
                Text("Connect to Terminal").font(.title.bold())
                Text("Sign in with a Mac account or an SSH key.").foregroundStyle(.secondary)
                if let loginIssue {
                    DirectRecoveryCard(notice: loginIssue, primary: .init(title: "Retry", perform: loadLogin))
                }
                if let notice = session.recovery {
                    DirectRecoveryCard(notice: notice, primary: recoveryAction(notice), secondary: secondaryAction(notice))
                }
                if session.connecting {
                    ProgressView(session.phase).accessibilityIdentifier("terminal-status")
                    Button("Cancel Connection") { session.cancelConnection() }.frame(minHeight: 44)
                } else if session.recovery?.reason == .keyRejected {
                    selectedKeyView
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mac account").font(.caption).foregroundStyle(.secondary)
                        TextField("Mac account username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        if !useKey {
                            Divider()
                            Text("Password").font(.caption).foregroundStyle(.secondary)
                            SecureField("Mac account password", text: $password).textContentType(.password).privacySensitive()
                        }
                    }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    if dynamicType.isAccessibilitySize {
                        Button("Use Password Login") { useKey = false; session.clearRecovery() }
                        Button("Use SSH Key Login") { useKey = true; session.clearRecovery() }
                    } else {
                        Picker("Login method", selection: $useKey) { Text("Password").tag(false); Text("SSH Key").tag(true) }.pickerStyle(.segmented)
                    }
                    if useKey {
                        selectedKeyView
                        Button(action: setupKey) { HStack { Label("Set Up Key on This Mac", systemImage: "key.horizontal"); Spacer(); DirectProBadge() } }.frame(minHeight: 44)
                            .accessibilityIdentifier("terminal-setup-ssh-key")
                        Button("Manual Key Setup") { sheet = .manual }.frame(minHeight: 44)
                    } else { Toggle("Save Terminal login for this Mac", isOn: $remember) }
                    if !canConnect {
                        Text(useKey && key == nil ? "Choose an SSH key to connect, or use Password login." : "Enter the Mac account and password. Account names allow up to 255 UTF-8 bytes; passwords allow up to 4 KiB.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if session.recovery == nil {
                        Button(useKey ? "Connect with Key" : "Connect", systemImage: "terminal") { connect() }.buttonStyle(.glassProminent).controlSize(.large).disabled(!canConnect)
                    }
                    Text("Enable Remote Login in System Settings → General → Sharing on your Mac. Desktop and Terminal save separate logins.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: 520).padding(.top, 8)
        }.onChange(of: username) { _, _ in session.clearRecovery() }
            .onChange(of: password) { _, _ in session.clearRecovery() }
            .onChange(of: useKey) { _, _ in session.clearRecovery() }
    }
    private var selectedKeyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if key != nil { Label(keyName, systemImage: "key").font(.headline); Text("Selected on this iPhone").font(.caption).foregroundStyle(.secondary) }
            else { Text("Choose an SSH key").font(.headline) }
            Button("Choose or Manage Key", systemImage: "key") { sheet = .keys }.frame(minHeight: 44)
            Text("Choosing a key doesn’t add its public key to the Mac.").font(.footnote).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct TerminalIdentityGuide: View {
    let macName: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.red)
                    Text("Verify \(macName) independently").font(.title2.bold())
                    Text("A server key can change after reinstalling macOS, or when an address reaches a different machine. Login stays blocked until the saved and presented identities agree.")
                    Text("On the Mac, inspect the SSH server keys in /etc/ssh/ssh_host_*_key.pub with ssh-keygen -lf and compare the matching fingerprint.").font(.body.monospaced())
                    Text("Only after checking the Mac independently, use Mac Settings → Saved Logins & Server Trust → Forget SSH Server Key. The next connection asks you to verify the new fingerprint before sending login.")
                        .foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("Verify Server Identity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct TerminalSurface: UIViewControllerRepresentable {
    let session: DirectTerminalSession
    let style: UIUserInterfaceStyle
    let customize: @MainActor () -> Void
    func makeUIViewController(context: Context) -> TerminalController { TerminalController(session: session, customize: customize) }
    func updateUIViewController(_ controller: TerminalController, context: Context) {
        controller.terminal.isUserInteractionEnabled = session.connected
        if !session.connected { _ = controller.terminal.resignFirstResponder() }
        controller.applyAppearance(style)
    }
    static func dismantleUIViewController(_ controller: TerminalController, coordinator: ()) { controller.session.received = nil; controller.session.toggleKeyboard = nil; controller.session.reloadKeyboard = nil }
}

@MainActor final class SessionTerminalView: TerminalView {
    var focusChanged: ((Bool) -> Void)?
    var keyboardState = TerminalKeyboardState()
    private var deletingModifiers: TerminalModifiers?
    private var deletionEncoded = false
    func resetModifiers() { keyboardState.reset(); controlModifier = false; metaModifier = false; (inputAccessoryView as? TerminalKeyboardAccessory)?.refresh() }
    override func insertText(_ text: String) {
        let modifiers = keyboardState.consume()
        if modifiers.isEmpty { super.insertText(text) }
        else if getTerminal().keyboardEnhancementFlags.isEmpty { send(data: TerminalKeyboardState.text(text, modifiers: modifiers)[...]) }
        else { controlModifier = modifiers.contains(.ctrl); metaModifier = modifiers.contains(.alt); super.insertText(modifiers.contains(.shift) ? TerminalKeyboardState.shifted(text) : text) }
        (inputAccessoryView as? TerminalKeyboardAccessory)?.refresh()
    }
    override func deleteBackward() {
        let modifiers = keyboardState.consume()
        let ordinary = modifiers.isEmpty || (modifiers == .shift && getTerminal().keyboardEnhancementFlags.isEmpty)
        deletingModifiers = ordinary || markedTextRange != nil ? nil : modifiers
        deletionEncoded = false
        defer { deletingModifiers = nil; deletionEncoded = false; (inputAccessoryView as? TerminalKeyboardAccessory)?.refresh() }
        // Keep SwiftTerm's UITextInput/IME bookkeeping; transform only its outbound deletion.
        super.deleteBackward()
    }
    func encodeOutput(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard let deletingModifiers else { return Array(bytes) }
        // Native range deletion may emit several backspaces for one logical keypress.
        guard !deletionEncoded else { return [] }; deletionEncoded = true
        return TerminalKeyboardState.backspace(modifiers: deletingModifiers, controlH: backspaceSendsControlH,
            enhanced: !getTerminal().keyboardEnhancementFlags.isEmpty)
    }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); if result { focusChanged?(true) }; return result
    }
    override func resignFirstResponder() -> Bool {
        resetModifiers(); let result = super.resignFirstResponder(); if result { focusChanged?(false) }; return result
    }
}

@MainActor final class TerminalController: UIViewController, @preconcurrency TerminalViewDelegate {
    let session: DirectTerminalSession
    let terminal = SessionTerminalView(frame: .zero)
    private var paletteIsDark: Bool?
    private let customize: @MainActor () -> Void
    init(session: DirectTerminalSession, customize: @escaping @MainActor () -> Void) { self.session = session; self.customize = customize; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        terminal.terminalDelegate = self; terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.topAnchor), terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        session.received = { [weak self] bytes in self?.terminal.feed(byteArray: bytes[...]) }
        configureKeyboard()
        session.reloadKeyboard = { [weak self] in self?.configureKeyboard() }
        terminal.focusChanged = { [weak session] visible in session?.keyboardVisible = visible }
        session.toggleKeyboard = { [weak self] in
            guard let self else { return }
            if terminal.isFirstResponder { _ = terminal.resignFirstResponder() }
            else { _ = terminal.becomeFirstResponder() }
        }
        terminal.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TerminalView, _: UITraitCollection) in self?.updatePalette() }
        updatePalette()
    }
    private func configureKeyboard() {
        let preferences: TerminalKeyboardPreferences
        do { preferences = try TerminalKeyboardPreferences.load(session.mac.id); session.controlsRecovery = nil }
        catch { preferences = .init(); session.controlsRecovery = .make(.controlsUnavailable, message: "Custom Terminal controls couldn’t be read. Existing data is kept; the standard keyboard remains available.") }
        terminal.resetModifiers()
        let accessory = TerminalKeyboardAccessory(terminal: terminal, preferences: preferences)
        accessory.customize = customize
        terminal.inputAccessoryView = accessory
        terminal.reloadInputViews()
    }
    func applyAppearance(_ style: UIUserInterfaceStyle) {
        loadViewIfNeeded()
        if terminal.overrideUserInterfaceStyle != style { terminal.overrideUserInterfaceStyle = style }
        updatePalette()
    }
    private func updatePalette() {
        let dark = terminal.traitCollection.userInterfaceStyle == .dark
        guard paletteIsDark != dark else { return }; paletteIsDark = dark
        terminal.nativeBackgroundColor = dark ? .black : .white
        terminal.nativeForegroundColor = dark ? .white : .black
        terminal.caretColor = .systemBlue; terminal.keyboardAppearance = dark ? .dark : .light
        if terminal.isFirstResponder { terminal.reloadInputViews() }
        terminal.setNeedsDisplay()
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session.resize(columns: newCols, rows: newRows) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { session.send(terminal.encodeOutput(data)) }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let alert = UIAlertController(title: "Open terminal link?", message: url.host, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in UIApplication.shared.open(url) })
        present(alert, animated: true)
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        guard content.count <= 65536, let text = String(data: content, encoding: .utf8) else { return }
        let alert = UIAlertController(title: "Copy terminal text?", message: "The Mac requested copying text to your iPhone clipboard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Copy", style: .default) { _ in UIPasteboard.general.string = text })
        present(alert, animated: true)
    }
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
struct TerminalConnectionInfo: View {
    let mac: DirectMacRecordV1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Login") {
                    LabeledContent("Mac", value: mac.name)
                    LabeledContent("SSH Port", value: String(mac.sshPort))
                    ForEach(mac.addresses, id: \.self) { Text($0).textSelection(.enabled) }
                }
                Text("Change saved addresses and ports in My Macs → this Mac’s menu → Mac Settings.")
            }.navigationTitle("Connection Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
