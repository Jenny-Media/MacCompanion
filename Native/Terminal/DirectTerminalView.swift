#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import SwiftTerm
import UIKit

struct DirectTerminalView: View {
    let mac: DirectMacRecordV1
    let exit: @MainActor () -> Void
    @State private var session: DirectTerminalSession
    @State private var username = ""
    @State private var password = ""
    @State private var remember = false
    @State private var loginError: String?
    @State private var settings = false
    @State private var keySettings = false
    @State private var key: TerminalSSHKey?
    @State private var useKey = false
    private var canConnect: Bool { !username.isEmpty && (useKey ? key != nil : !password.isEmpty) }
    private func connect() { session.connect(username: username, password: useKey ? "" : password, remember: !useKey && remember, key: useKey ? key : nil) }
    private func loadKey() {
        do { key = try TerminalSecretStore.sshKey(mac.id); if let key { useKey = true; if !key.username.isEmpty { username = key.username } } }
        catch { loginError = "The saved SSH key could not be read. It has been preserved." }
    }
    @Environment(DirectAppearanceV1.self) private var appearance
    init(mac: DirectMacRecordV1, exit: @escaping @MainActor () -> Void) {
        self.mac = mac; self.exit = exit; _session = State(initialValue: DirectTerminalSession(mac: mac))
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                TerminalSurface(session: session, style: appearance.terminal.style(app: appearance.app)).opacity(session.connected ? 1 : 0).allowsHitTesting(session.connected).accessibilityHidden(!session.connected)
                if !session.connected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.blue)
                            Text(mac.name).font(.title.bold())
                            Text("Terminal uses your Mac’s built-in Remote Login (SSH).").foregroundStyle(.secondary)
                            Text(session.status).accessibilityIdentifier("terminal-status")
                            if let loginError { Text(loginError).foregroundStyle(.red) }
                            if session.connecting { ProgressView(); Button("Cancel Connection") { session.stop() } }
                            else {
                                TextField("Mac account username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                Picker("Authentication", selection: $useKey) { Text("Password").tag(false); Text("SSH Key").tag(true) }.pickerStyle(.segmented)
                                if useKey {
                                    if let key { Label("Ed25519 · " + key.fingerprint, systemImage: "key.fill").font(.caption) }
                                    else { Text("Create or import an SSH key for this Mac.").foregroundStyle(.secondary) }
                                    Button(key == nil ? "Set Up SSH Key" : "Manage SSH Key", systemImage: "key") { keySettings = true }
                                } else {
                                    SecureField("Mac account password", text: $password).textContentType(.password)
                                    Toggle("Save Terminal login for this Mac", isOn: $remember)
                                }
                                Button("Connect", systemImage: "terminal") { connect() }.buttonStyle(.glassProminent).disabled(!canConnect)
                                Text("Enable Remote Login in System Settings → General → Sharing on your Mac. Desktop and Terminal save separate logins.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(24).frame(maxWidth: 520).padding(.top, 24)
                    }
                }
            }
            .navigationTitle("\(mac.name) · Terminal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { session.stop(); exit() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Terminal") {
                            if session.connected {
                                Button(session.keyboardVisible ? "Hide Keyboard" : "Show Keyboard", systemImage: session.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard") { session.toggleKeyboard?() }
                            }
                            else { Button("Reconnect", systemImage: "arrow.clockwise") { connect() }.disabled(session.connecting || !canConnect) }
                        }
                        Section("Appearance") {
                            Picker("Terminal Colors", selection: Binding(get: { appearance.terminal }, set: { appearance.terminal = $0 })) {
                                ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
                            }
                            Button("App Settings", systemImage: "gearshape") { settings = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Terminal Controls")
                }
            }
            .sheet(isPresented: $keySettings) { TerminalKeySettings(mac: mac, changed: { loadKey() }) }
            .sheet(isPresented: $settings) { DirectSessionSettingsV1() }
            .alert(item: $session.trust) { request in
                Alert(title: Text("Trust this SSH server?"), message: Text("Verify this fingerprint belongs to \(mac.name) before sending your login.\n\n\(request.fingerprint)"),
                    primaryButton: .default(Text("Trust & Connect")) { session.answerTrust(true) }, secondaryButton: .cancel { session.answerTrust(false) })
            }
        }
        .onAppear {
            do { if let login = try TerminalSecretStore.login(mac.id) { username = login.username; password = login.password; remember = true } }
            catch { loginError = "Saved Terminal login could not be read. It has been preserved." }
            loadKey()
        }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.background() }
    }
}

private struct TerminalSurface: UIViewControllerRepresentable {
    let session: DirectTerminalSession
    let style: UIUserInterfaceStyle
    func makeUIViewController(context: Context) -> TerminalController { TerminalController(session: session) }
    func updateUIViewController(_ controller: TerminalController, context: Context) {
        controller.terminal.isUserInteractionEnabled = session.connected
        if !session.connected { _ = controller.terminal.resignFirstResponder() }
        controller.applyAppearance(style)
    }
    static func dismantleUIViewController(_ controller: TerminalController, coordinator: ()) { controller.session.received = nil; controller.session.toggleKeyboard = nil }
}

@MainActor final class SessionTerminalView: TerminalView {
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); if result { focusChanged?(true) }; return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder(); if result { focusChanged?(false) }; return result
    }
}

@MainActor final class TerminalController: UIViewController, @preconcurrency TerminalViewDelegate {
    let session: DirectTerminalSession
    let terminal = SessionTerminalView(frame: .zero)
    private var paletteIsDark: Bool?
    init(session: DirectTerminalSession) { self.session = session; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        terminal.terminalDelegate = self; terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.topAnchor), terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        session.received = { [weak self] bytes in self?.terminal.feed(byteArray: bytes[...]) }
        terminal.focusChanged = { [weak session] visible in session?.keyboardVisible = visible }
        session.toggleKeyboard = { [weak self] in
            guard let self else { return }
            if terminal.isFirstResponder { _ = terminal.resignFirstResponder() }
            else { _ = terminal.becomeFirstResponder() }
        }
        terminal.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TerminalView, _: UITraitCollection) in self?.updatePalette() }
        updatePalette()
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
    func send(source: TerminalView, data: ArraySlice<UInt8>) { session.send(Array(data)) }
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
#endif
