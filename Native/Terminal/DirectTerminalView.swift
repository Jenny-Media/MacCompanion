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
    @State private var passwordVisible = false
    @State private var loginIssue: DirectRecoveryNotice?
    @State private var key: TerminalSSHKey?
    @State private var keyName = ""
    @State private var useKey = false
    @State private var loadedLogin = false
    private let autoConnect: Bool
    private enum Sheet: String, Identifiable {
        case keys, install, manual, macSettings, appSettings, pro, keyboard, verifyGuide, connectionInfo, errorDetails
        var id: String { rawValue }
    }
    @State private var sheet: Sheet?
    @Environment(DirectAppearanceV1.self) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.colorScheme) private var colorScheme
    private var terminalScheme: ColorScheme? {
        switch appearance.terminal { case .dark: .dark; case .light: .light; case .app: appearance.app.colorScheme }
    }
    private var terminalBackground: SwiftUI.Color { (terminalScheme ?? colorScheme) == .dark ? .black : .white }
    private var canConnect: Bool {
        !username.isEmpty && username.utf8.count <= 255 && !username.contains("\0") &&
        (useKey ? key != nil : !password.isEmpty && password.utf8.count <= 4096 && !password.contains("\0"))
    }
    init(mac: DirectMacRecordV1, macLibrary: DirectMacLibraryV1? = nil, session: DirectTerminalSession? = nil, autoConnect: Bool = true, exit: @escaping @MainActor () -> Void) {
        self.macLibrary = macLibrary; self.exit = exit; _session = State(initialValue: session ?? DirectTerminalSession(mac: mac))
        self.autoConnect = autoConnect
    }
    private func connect() {
        guard canConnect, !session.connecting, !session.connected else { return }
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
        case .keyRejected: .init(title: "Set Up Key", symbol: "key", pro: true, perform: setupKey)
        case .loginRejected: .init(title: "Try Again") { connect() }
        case .serverChanged: .init(title: "How to Verify", symbol: "lock.shield") { sheet = .verifyGuide }
        case .savedDataUnavailable: .init(title: "Retry", symbol: "arrow.clockwise") { loadLogin(); session.clearRecovery() }
        case .terminalEnded, .inputPaused: .init(title: "Open New Shell", symbol: "terminal") { if canConnect { connect() } else { session.clearRecovery() } }
        case .connectionCancelled: .init(title: "Return to Login") { session.clearRecovery() }
        default: .init(title: "Try Again", symbol: "arrow.clockwise") { if canConnect { connect() } else { session.clearRecovery() } }
        }
    }
    private func secondaryAction(_ notice: DirectRecoveryNotice) -> DirectRecoveryAction? {
        if notice.reason == .keyRejected { return .init(title: "Use Password", symbol: "person.badge.key") { useKey = false; session.clearRecovery() } }
        if [.serverChanged, .connectionCancelled, .savedDataUnavailable].contains(notice.reason) { return nil }
        return .init(title: "Connection Settings", symbol: "gearshape") { sheet = .macSettings }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                (session.connected ? terminalBackground : Color(uiColor: .systemGroupedBackground)).ignoresSafeArea()
                TerminalSurface(session: session, style: appearance.terminal.style(app: appearance.app), customize: { sheet = .keyboard }, action: handleControls)
                    .ignoresSafeArea(.container, edges: session.connected ? .top : [])
                    .opacity(session.connected ? 1 : 0).allowsHitTesting(session.connected).accessibilityHidden(!session.connected)
                if !session.connected {
                    DirectConnectionBackdrop(names: macLibrary?.macs.map(\.name) ?? [mac.name])
                    loginView
                }
                else if let notice = session.controlsRecovery {
                    VStack { DirectRecoveryCard(notice: notice,
                        primary: .init(title: "Keyboard Settings", perform: { sheet = .keyboard }),
                        secondary: .init(title: "Use Standard Controls", perform: { session.controlsRecovery = nil })).padding(12); Spacer() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                case .connectionInfo: TerminalConnectionInfo(mac: mac)
                case .errorDetails:
                    controlsSheet(title: "Connection Issue") {
                        if let notice = loginIssue ?? session.recovery { DirectRecoveryCard(notice: notice) }
                    }
                }
            }
            .sheet(item: $session.trust) { request in
                TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust)
            }
        }
        // The native terminal owns keyboard avoidance through its layout guide.
        // Keep SwiftUI from shrinking the same connected surface a second time;
        // the sign-in card still uses SwiftUI's normal keyboard avoidance.
        .ignoresSafeArea(.keyboard, edges: session.connected ? .bottom : [])
        .preferredColorScheme(session.connected ? terminalScheme : appearance.app.colorScheme)
        .onAppear {
            guard !loadedLogin else { return }
            loadedLogin = true; loadLogin()
            if autoConnect && loginIssue == nil && session.recovery == nil { connect() }
        }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.background() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in session.foreground() }
        .onReceive(NotificationCenter.default.publisher(for: DirectAppLockV1.unlocked)) { _ in session.foreground() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in session.activity?.preferenceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: RemoteSessionActivityActions.endRequested)) { notification in
            if let id = notification.object as? String, session.endActivity(id) { exit() }
        }
    }
    private func handleControls(_ action: String) {
        switch action {
        case "connectionInfo": sheet = .connectionInfo
        case "appSettings": sheet = .appSettings
        case "macSettings": sheet = .macSettings
        case "keys": sheet = .keys
        case "install": setupKey()
        case "manual": sheet = .manual
        case "customize": sheet = .keyboard
        case "exit": session.stop(); exit()
        default: break
        }
    }
    private func controlsSheet<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            Form { content() }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }.presentationDetents([.medium, .large])
    }
    private var loginView: some View {
        GeometryReader { geometry in
            let compact = TerminalPresentationLayout.compactLogin(size: geometry.size, accessibility: dynamicType.isAccessibilitySize)
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: compact ? 14 : 22) {
                        DirectConnectionIdentity(name: mac.name, service: "Terminal", symbol: "terminal", compact: compact,
                            cancel: session.connecting ? nil : { session.stop(); exit() })
                        loginForm(compact: compact)
                    }.padding(compact ? 16 : 22)
                        .directConnectionCardSurface()
                        .frame(maxWidth: compact ? 720 : 440)
                }.frame(minHeight: max(0, geometry.size.height - 20), alignment: .center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10)
            }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
        }
    }
    private func loginForm(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            if session.connecting {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.regular)
                    Text(session.phase == "Ready" ? "Connecting to Terminal…" : session.phase + "…")
                        .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("terminal-status")
                }.frame(maxWidth: .infinity, minHeight: compact ? 84 : 124)
                Button { session.stop(); exit() } label: {
                    Text("Cancel").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 16)).controlSize(.regular)
                    .tint(.blue).accessibilityIdentifier("terminal-login-cancel")
            } else {
                let authentication = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                authentication {
                    Text("Sign in with").foregroundStyle(.secondary)
                    if !dynamicType.isAccessibilitySize { Spacer() }
                    Menu {
                        Button("Password") { useKey = false; session.clearRecovery() }
                        Button("SSH Key") { useKey = true; session.clearRecovery() }
                    } label: { HStack(spacing: 6) { Text(useKey ? "SSH Key" : "Password").fontWeight(.semibold).fixedSize(horizontal: true, vertical: false); Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)) }.foregroundStyle(.primary).frame(minHeight: 44) }.tint(.primary)
                }.font(.subheadline)
                let notice = loginIssue ?? session.recovery
                if let notice { DirectConnectionNotice(notice: notice) }
                let fields = compact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                fields {
                    accountField
                    if !useKey {
                        Divider().frame(width: compact ? 1 : nil, height: compact ? 56 : 1)
                        passwordField
                    }
                }.padding(14).background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.25)))
                if useKey {
                    selectedKeyView
                } else { Toggle("Save login", isOn: $remember).font(.subheadline).padding(.horizontal, 2) }
                if let notice {
                    let action = loginIssue != nil ? DirectRecoveryAction(title: "Retry", perform: loadLogin) : recoveryAction(notice)
                    connectionButton(action.title, symbol: action.symbol, enabled: ![.loginRejected, .terminalEnded, .inputPaused].contains(notice.reason) || canConnect, perform: action.perform)
                    if let secondary = secondaryAction(notice) {
                        Button(secondary.title, action: secondary.perform).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44)
                    }
                } else { connectionButton("Connect", enabled: canConnect, perform: connect) }
                Menu {
                    Button("Connection Details", systemImage: "info.circle") { sheet = .connectionInfo }
                    if notice != nil { Button("Error Details", systemImage: "exclamationmark.circle") { sheet = .errorDetails } }
                    Button("Mac Settings", systemImage: "gearshape") { sheet = .macSettings }
                    Button("Choose or Manage SSH Key", systemImage: "key") { sheet = .keys }
                    Button("Set Up Key on This Mac", systemImage: "key.horizontal", action: setupKey).accessibilityIdentifier("terminal-setup-ssh-key")
                    Button("Manual Key Setup", systemImage: "list.bullet") { sheet = .manual }
                } label: { Label("Connection Details", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44) }
                    .tint(.secondary).accessibilityIdentifier("terminal-login-details")
            }
        }
    }
    private func connectionButton(_ title: String, symbol: String? = nil, enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                if let symbol { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white).background(enabled ? Color.blue : Color.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier("terminal-connect")
    }
    private var accountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mac account").font(.caption).foregroundStyle(.secondary)
            TextField("Mac account username", text: Binding(get: { username }, set: { username = $0; session.clearRecovery() })).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().frame(minHeight: 32)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                DirectConnectionPasswordField(text: Binding(get: { password }, set: { password = $0; session.clearRecovery() }), secure: !passwordVisible, submit: connect).privacySensitive().frame(minHeight: 32)
                Button { passwordVisible.toggle() } label: { Image(systemName: passwordVisible ? "eye.slash" : "eye").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(passwordVisible ? "Hide Password" : "Show Password")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var selectedKeyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { sheet = .keys } label: {
                HStack { Label(key == nil ? "Choose SSH Key" : keyName, systemImage: "key"); Spacer(); Image(systemName: "chevron.right") }
            }.frame(minHeight: 44)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.25)))
    }
}

enum TerminalPresentationLayout {
    static func compactLogin(size: CGSize, accessibility: Bool) -> Bool {
        !accessibility && size.width >= 520 && size.height < 520
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
    let action: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> TerminalController { TerminalController(session: session, customize: customize, action: action) }
    func updateUIViewController(_ controller: TerminalController, context: Context) {
        controller.terminal.isUserInteractionEnabled = session.connected
        if !session.connected { _ = controller.terminal.resignFirstResponder() }
        controller.updateControls()
        controller.applyAppearance(style)
    }
    static func dismantleUIViewController(_ controller: TerminalController, coordinator: ()) { controller.session.received = nil; controller.session.toggleKeyboard = nil; controller.session.reloadKeyboard = nil; controller.session.suspendInput = nil }
}

@MainActor final class SessionTerminalView: TerminalView {
    var focusChanged: ((Bool) -> Void)?
    var keyboardState = TerminalKeyboardState()
    weak var keyboardBar: TerminalKeyboardBar?
    private var deletingModifiers: TerminalModifiers?
    private var deletionEncoded = false
    // SwiftTerm pins short buffers to zero. With a canvas extending behind the
    // status bar, that resting offset must include the leading scroll inset.
    // Leave finger-driven scrolling and deceleration owned by UIScrollView.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            var offset = newValue
            if contentInset.top > 0, contentSize.height > 0, offset.y == 0,
               !isTracking, !isDecelerating, contentSize.height < bounds.height {
                offset.y = max(-contentInset.top, contentSize.height - bounds.height)
            }
            super.contentOffset = offset
        }
    }
    func resetModifiers() { keyboardState.reset(); controlModifier = false; metaModifier = false; keyboardBar?.refresh() }
    override func insertText(_ text: String) {
        let modifiers = keyboardState.consume()
        if modifiers.isEmpty { super.insertText(text) }
        else if getTerminal().keyboardEnhancementFlags.isEmpty { send(data: TerminalKeyboardState.text(text, modifiers: modifiers)[...]) }
        else { controlModifier = modifiers.contains(.ctrl); metaModifier = modifiers.contains(.alt); super.insertText(modifiers.contains(.shift) ? TerminalKeyboardState.shifted(text) : text) }
        keyboardBar?.refresh()
    }
    override func deleteBackward() {
        let modifiers = keyboardState.consume()
        let ordinary = modifiers.isEmpty || (modifiers == .shift && getTerminal().keyboardEnhancementFlags.isEmpty)
        deletingModifiers = ordinary || markedTextRange != nil ? nil : modifiers
        deletionEncoded = false
        defer { deletingModifiers = nil; deletionEncoded = false; keyboardBar?.refresh() }
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

@MainActor class TerminalController: UIViewController, @preconcurrency TerminalViewDelegate {
    static let numberRowPreference = "direct-terminal-number-row"
    let session: DirectTerminalSession
    let terminal = SessionTerminalView(frame: .zero)
    let controls = CompanionVNCControls()
    lazy var keyboardBar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
    private var reportedGrid: (columns: Int, rows: Int)?
    private var paletteIsDark: Bool?
    private var normalBottom: NSLayoutConstraint!
    private var foldedBottom: NSLayoutConstraint!
    private let customize: @MainActor () -> Void
    private let action: @MainActor (String) -> Void
    private let defaults: UserDefaults
    init(session: DirectTerminalSession, customize: @escaping @MainActor () -> Void, action: @escaping @MainActor (String) -> Void = { _ in }, defaults: UserDefaults = .standard) {
        self.session = session; self.customize = customize; self.action = action; self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { paletteIsDark == true ? .lightContent : .darkContent }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        terminal.terminalDelegate = self; terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        // The persistent toolbar owns the only bottom control space. No
        // additional row is reserved for the shared menu button.
        keyboardBar.showsNumberRow = defaults.object(forKey: Self.numberRowPreference) == nil || defaults.bool(forKey: Self.numberRowPreference)
        view.addSubview(keyboardBar)
        terminal.keyboardBar = keyboardBar
        terminal.inputAccessoryView = nil
        NSLayoutConstraint.activate([
            keyboardBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            keyboardBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        normalBottom = terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -keyboardBar.height)
        foldedBottom = terminal.bottomAnchor.constraint(equalTo: view.topAnchor)
        terminal.contentInsetAdjustmentBehavior = .never
        terminal.clipsToBounds = true
        setContentScrollView(terminal, for: .top)
        if #available(iOS 26, *) { terminal.topEdgeEffect.style = .automatic }
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.topAnchor), normalBottom, terminal.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)])
        controls.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(controls)
        NSLayoutConstraint.activate([controls.topAnchor.constraint(equalTo: view.topAnchor), controls.bottomAnchor.constraint(equalTo: view.bottomAnchor), controls.leadingAnchor.constraint(equalTo: view.leadingAnchor), controls.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        controls.buttonAnchorView = keyboardBar.menuAnchor
        controls.button.accessibilityLabel = "Terminal Controls"
        controls.button.accessibilityIdentifier = "terminal-controls"
        controls.categoryActions = [
            ["kind": "inputMenu", "title": "Keyboard & Input", "symbol": "keyboard"],
            ["kind": "appearance", "title": "Appearance", "symbol": "circle.lefthalf.filled"],
            ["kind": "session", "title": "Session", "symbol": "network"]]
        controls.actionHandler = { [weak self] item in self?.performControl(item["kind"] as? String ?? "") }
        CompanionVNCObserveDivision(view)
        session.received = { [weak self] bytes in self?.terminal.feed(byteArray: bytes[...]) }
        configureKeyboard()
        session.reloadKeyboard = { [weak self] in self?.configureKeyboard() }
        session.suspendInput = { [weak self] in self?.terminal.resetModifiers(); self?.controls.cancelSlideForLayoutChange(); self?.controls.close() }
        terminal.focusChanged = { [weak self, weak session] visible in session?.keyboardVisible = visible; self?.updateControls(); self?.view.setNeedsLayout() }
        keyboardBar.toggleKeyboard = { [weak session] in session?.toggleKeyboard?() }
        session.toggleKeyboard = { [weak self] in
            guard let self else { return }
            if terminal.isFirstResponder { _ = terminal.resignFirstResponder() }
            else { _ = terminal.becomeFirstResponder() }
        }
        terminal.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TerminalView, _: UITraitCollection) in self?.updatePalette() }
        updatePalette()
        updateControls()
    }
    func updateControls() {
        controls.isHidden = !session.connected
        keyboardBar.isHidden = !session.connected
        keyboardBar.setKeyboardFocused(terminal.isFirstResponder)
        if !session.connected { controls.close() }
        controls.macName = session.mac.name
        controls.quickActions = [
            ["kind": "paste", "title": "Paste", "symbol": "document.on.clipboard", "enabled": true],
            ["kind": "interrupt", "title": "Ctrl-C", "symbol": "stop.circle", "enabled": true]]
    }
    private func performControl(_ kind: String) {
        guard session.connected else { return }
        switch kind {
        case "inputMenu":
            presentControlsMenu("Keyboard & Input", sections: [["title": "Keyboard", "items": [
                ["kind": "numberRow", "title": "Show Number Row", "symbol": "textformat.123", "selected": keyboardBar.showsNumberRow],
                ["kind": "customize", "title": "Customize Keys & Snippets", "symbol": "slider.horizontal.3", "submenu": true]]]])
        case "appearance":
            let choices = DirectTerminalAppearance.allCases.map { value in
                ["kind": "colors-" + value.rawValue, "title": value.title, "symbol": "circle.lefthalf.filled", "selected": DirectAppearanceV1.shared.terminal == value] as [String: Any]
            }
            presentControlsMenu("Appearance", sections: [["title": "Terminal Colors", "items": choices]])
        case "session":
            presentControlsMenu(session.mac.name, sections: [
                ["title": "Session", "items": [
                    ["kind": "connectionInfo", "title": "Connection Details", "symbol": "network"],
                    ["kind": "appSettings", "title": "App Settings", "symbol": "gearshape", "submenu": true]]],
                ["title": "", "items": [["kind": "exit", "title": "Exit to My Macs", "symbol": "rectangle.portrait.and.arrow.right", "destructive": true]]]])
        case "connectionInfo":
            let message = ([session.mac.name, "SSH · Port \(session.mac.sshPort)"] + session.mac.addresses).joined(separator: "\n")
            let details = UIAlertController(title: "Connection Details", message: message, preferredStyle: .alert)
            details.overrideUserInterfaceStyle = paletteIsDark == true ? .dark : .light
            details.addAction(UIAlertAction(title: "Done", style: .cancel))
            present(details, animated: true)
        case "keyboard": session.toggleKeyboard?()
        case "numberRow":
            keyboardBar.showsNumberRow.toggle()
            defaults.set(keyboardBar.showsNumberRow, forKey: Self.numberRowPreference)
            view.setNeedsLayout()
        case "paste": terminal.resetModifiers(); terminal.paste(nil)
        case "interrupt":
            terminal.resetModifiers()
            terminal.send(data: TerminalKeyboardState.text("c", modifiers: .ctrl)[...])
            terminal.keyboardBar?.refresh()
        default:
            if kind.hasPrefix("colors-"), let value = DirectTerminalAppearance(rawValue: String(kind.dropFirst(7))) {
                DirectAppearanceV1.shared.terminal = value
            } else { action(kind) }
        }
    }
    private func presentControlsMenu(_ title: String, sections: [[String: Any]]) {
        let menu = CompanionVNCMenu(); menu.title = title; menu.sections = sections
        menu.selectionHandler = { [weak self] item in self?.performControl(item["kind"] as? String ?? "") }
        if let navigation = presentedViewController as? UINavigationController, navigation.topViewController is CompanionVNCMenu {
            navigation.pushViewController(menu, animated: true)
        } else if presentedViewController == nil {
            let navigation = CompanionVNCMenu.navigationController(for: menu, sourceView: controls.button)
            navigation.overrideUserInterfaceStyle = paletteIsDark == true ? .dark : .light
            present(navigation, animated: true)
        }
    }
    func activeDivision() -> CGRect { CompanionVNCActiveDivision(view) }
    func keyboardCeiling() -> CGFloat {
        let frame = view.keyboardLayoutGuide.layoutFrame
        return frame.width > 0 ? frame.minY : view.bounds.inset(by: view.safeAreaInsets).maxY
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        var content = CGRect.null, input = CGRect.null
        let tabletop = CompanionVNCTabletopRegions(safe, activeDivision(), &content, &input)
        let ceiling = keyboardCeiling()
        // A hosting controller can already end at the keyboard's top. Compare
        // against the physical window so that this still reveals the number row.
        let restingBottom = view.window.map { window in
            view.convert(CGPoint(x: 0, y: window.bounds.maxY - window.safeAreaInsets.bottom), from: window).y
        } ?? safe.maxY
        let softwareKeyboard = ceiling < restingBottom - 1
        keyboardBar.setSoftwareKeyboardVisible(softwareKeyboard)
        let inset = max(0, safe.maxY - ceiling)
        if controls.bottomInset != inset { controls.cancelSlideForLayoutChange(); controls.bottomInset = inset; controls.setNeedsLayout() }
        // A closed or hardware-only keyboard leaves the entire terminal usable.
        // Only an onscreen keyboard reserves the lower tabletop region.
        let reserveUpper = tabletop && softwareKeyboard
        let cell = terminal.caretFrame.height
        // SwiftUI can remove its top safe area from the native child. Use the
        // physical window boundary to reserve entry text below system icons.
        let top: CGFloat
        if let window = view.window {
            top = max(0, window.safeAreaInsets.top - view.convert(CGPoint.zero, to: window).y) + 8
        } else { top = safe.minY + 8 }
        if terminal.contentInset.top != top {
            terminal.contentInset.top = top
            terminal.verticalScrollIndicatorInsets.top = top
        }
        func wholeRowBottom(_ bottom: CGFloat) -> CGFloat {
            guard cell > 0 else { return bottom }
            return top + max(0, floor((bottom - top) / cell)) * cell
        }
        if reserveUpper {
            normalBottom.isActive = false
            foldedBottom.constant = wholeRowBottom(max(top, min(content.maxY - 8, ceiling - keyboardBar.height)))
            foldedBottom.isActive = true
        } else {
            foldedBottom.isActive = false
            normalBottom.constant = wholeRowBottom(ceiling - keyboardBar.height) - ceiling
            normalBottom.isActive = true
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardBar.layoutIfNeeded()
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        let grid = terminal.getTerminal()
        sizeChanged(source: terminal, newCols: grid.cols, newRows: grid.rows)
    }
    private func configureKeyboard() {
        let preferences: TerminalKeyboardPreferences
        do { preferences = try TerminalKeyboardPreferences.load(session.mac.id); session.controlsRecovery = nil }
        catch { preferences = .init(); session.controlsRecovery = .make(.controlsUnavailable, message: "Custom Terminal controls couldn’t be read. Existing data is kept; the standard keyboard remains available.") }
        terminal.resetModifiers()
        keyboardBar.configure(preferences)
        keyboardBar.customize = customize
        view.setNeedsLayout()
    }
    func applyAppearance(_ style: UIUserInterfaceStyle) {
        loadViewIfNeeded()
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style }
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        if terminal.overrideUserInterfaceStyle != style { terminal.overrideUserInterfaceStyle = style }
        updatePalette()
    }
    private func updatePalette() {
        let style = terminal.overrideUserInterfaceStyle == .unspecified ? terminal.traitCollection.userInterfaceStyle : terminal.overrideUserInterfaceStyle
        let dark = style == .dark
        guard paletteIsDark != dark else { return }; paletteIsDark = dark
        terminal.nativeBackgroundColor = dark ? .black : .white
        view.backgroundColor = dark ? .black : .white
        controls.overrideUserInterfaceStyle = dark ? .dark : .light
        keyboardBar.overrideUserInterfaceStyle = dark ? .dark : .light
        setNeedsStatusBarAppearanceUpdate()
        terminal.nativeForegroundColor = dark ? .white : .black
        terminal.caretColor = .systemBlue; terminal.keyboardAppearance = dark ? .dark : .light
        if terminal.isFirstResponder { terminal.reloadInputViews() }
        terminal.setNeedsDisplay()
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let cell = source.caretFrame.height
        guard cell > 0, source.bounds.height > source.contentInset.top else { return }
        // Keep the interactive grid in the unobscured viewport. Extra space
        // above it is for scrollback, not additional rows hidden by system UI.
        let rows = max(2, Int(floor((source.bounds.height - source.contentInset.top) / cell)))
        let grid = source.getTerminal()
        if grid.rows != rows { grid.resize(cols: newCols, rows: rows); source.setNeedsDisplay() }
        guard reportedGrid?.columns != newCols || reportedGrid?.rows != rows else { return }
        reportedGrid = (newCols, rows); session.resize(columns: newCols, rows: rows)
    }
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
            }.navigationTitle("Connection Details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
#endif
