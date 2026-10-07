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
        case keys, install, manual, macSettings, appSettings, pro, keyboard, verifyGuide, connectionInfo, errorDetails, input, colors, session
        var id: String { rawValue }
    }
    @State private var sheet: Sheet?
    @Environment(DirectAppearanceV1.self) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicType
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
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                TerminalSurface(session: session, style: appearance.terminal.style(app: appearance.app), customize: { sheet = .keyboard }, action: handleControls)
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
                case .input: controlsSheet(title: "Keyboard & Input") { terminalInputActions }
                case .colors: controlsSheet(title: "Appearance") { terminalAppearanceActions }
                case .session: controlsSheet(title: "Session") { terminalSessionActions }
                }
            }
            .sheet(item: $session.trust) { request in
                TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust)
            }
        }
        .onAppear {
            guard !loadedLogin else { return }
            loadedLogin = true; loadLogin()
            if autoConnect && loginIssue == nil && session.recovery == nil { connect() }
        }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.background() }
    }
    private func handleControls(_ action: String) {
        switch action {
        case "inputMenu": sheet = .input
        case "appearance": sheet = .colors
        case "session": sheet = .session
        case "disconnect": session.stop(); exit()
        default: break
        }
    }
    private func controlsSheet<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            Form { content() }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }.presentationDetents([.medium, .large])
    }
    @ViewBuilder private var terminalInputActions: some View {
        Section("Keyboard") { Button("Customize Keys & Snippets", systemImage: "keyboard") { sheet = .keyboard } }
    }
    @ViewBuilder private var terminalSessionActions: some View {
        Section {
            Button("End Session", systemImage: "xmark") { session.stop(); exit() }
            Button("Connection Details", systemImage: "info.circle") { sheet = .connectionInfo }
        }
        Section("Mac") {
            Button("Choose or Manage Key", systemImage: "key") { sheet = .keys }
            Button("Set Up Key on This Mac", systemImage: "key.horizontal") { setupKey() }
            Button("Manual Key Setup", systemImage: "list.bullet") { sheet = .manual }
            Button("Mac Settings", systemImage: "gearshape") { sheet = .macSettings }
        }.disabled(session.connecting)
    }
    @ViewBuilder private var terminalAppearanceActions: some View {
        Section {
            Picker("Terminal Colors", selection: Binding(get: { appearance.terminal }, set: { appearance.terminal = $0 })) {
                ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) }
            }
            Button("App Settings", systemImage: "gearshape") { sheet = .appSettings }
        }
    }
    private var loginView: some View {
        GeometryReader { geometry in
            let compact = TerminalPresentationLayout.compactLogin(size: geometry.size, accessibility: dynamicType.isAccessibilitySize)
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: compact ? 14 : 22) {
                        Capsule().fill(.secondary.opacity(0.3)).frame(width: 34, height: 4).accessibilityHidden(true)
                        DirectConnectionIdentity(name: mac.name, service: "Terminal", symbol: "terminal", compact: compact,
                            cancel: session.connecting ? nil : { session.stop(); exit() })
                        loginForm(compact: compact)
                    }.padding(compact ? 16 : 22)
                        .background(Color(uiColor: DirectConnectionStyle.panel), in: RoundedRectangle(cornerRadius: 32))
                        .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color(uiColor: .separator).opacity(0.25)))
                        .frame(maxWidth: compact ? 720 : 440)
                }.frame(minHeight: max(0, geometry.size.height - 20), alignment: .bottom)
                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10)
            }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
        }
    }
    private func loginForm(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            if session.connecting {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text(session.phase == "Ready" ? "Connecting to Terminal…" : session.phase + "…")
                        .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("terminal-status")
                }.frame(maxWidth: .infinity, minHeight: compact ? 84 : 124)
                Button("Cancel") { session.stop(); exit() }.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 16))
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("terminal-login-cancel")
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

@MainActor class TerminalController: UIViewController, @preconcurrency TerminalViewDelegate {
    let session: DirectTerminalSession
    let terminal = SessionTerminalView(frame: .zero)
    let controls = CompanionVNCControls()
    private var paletteIsDark: Bool?
    private var normalBottom: NSLayoutConstraint!
    private var foldedBottom: NSLayoutConstraint!
    private let customize: @MainActor () -> Void
    private let action: @MainActor (String) -> Void
    init(session: DirectTerminalSession, customize: @escaping @MainActor () -> Void, action: @escaping @MainActor (String) -> Void = { _ in }) {
        self.session = session; self.customize = customize; self.action = action; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        terminal.terminalDelegate = self; terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        normalBottom = terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        foldedBottom = terminal.bottomAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), normalBottom, terminal.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)])
        controls.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(controls)
        NSLayoutConstraint.activate([controls.topAnchor.constraint(equalTo: view.topAnchor), controls.bottomAnchor.constraint(equalTo: view.bottomAnchor), controls.leadingAnchor.constraint(equalTo: view.leadingAnchor), controls.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
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
        terminal.focusChanged = { [weak self, weak session] visible in session?.keyboardVisible = visible; self?.updateControls(); self?.view.setNeedsLayout() }
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
        if !session.connected { controls.close() }
        controls.macName = session.mac.name
        controls.quickActions = [
            ["kind": "keyboard", "title": session.keyboardVisible ? "Hide Keyboard" : "Show Keyboard", "symbol": session.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard", "enabled": true],
            ["kind": "paste", "title": "Paste", "symbol": "document.on.clipboard", "enabled": true],
            ["kind": "interrupt", "title": "Ctrl-C", "symbol": "stop.circle", "enabled": true],
            ["kind": "disconnect", "title": "Done", "symbol": "xmark", "enabled": true]]
    }
    private func performControl(_ kind: String) {
        guard session.connected else { return }
        switch kind {
        case "keyboard": session.toggleKeyboard?()
        case "paste": terminal.resetModifiers(); terminal.paste(nil)
        case "interrupt":
            terminal.resetModifiers()
            terminal.send(data: TerminalKeyboardState.text("c", modifiers: .ctrl)[...])
            (terminal.inputAccessoryView as? TerminalKeyboardAccessory)?.refresh()
        default: action(kind)
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
        let inset = max(8, safe.maxY - ceiling + 8)
        if controls.bottomInset != inset { controls.cancelSlideForLayoutChange(); controls.bottomInset = inset; controls.setNeedsLayout() }
        // A closed or hardware-only keyboard leaves the entire terminal usable.
        // Only an onscreen keyboard reserves the lower tabletop region.
        let reserveUpper = tabletop && ceiling < safe.maxY - 1
        if reserveUpper {
            normalBottom.isActive = false
            foldedBottom.constant = max(safe.minY, min(content.maxY - 8, ceiling))
            foldedBottom.isActive = true
        } else {
            foldedBottom.isActive = false
            normalBottom.isActive = true
        }
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
                Section("Set Up Your Mac") {
                    Text("Enable Remote Login in System Settings → General → Sharing. Use your Mac account password or an SSH key installed for that account.")
                    Text("Desktop and Terminal save separate logins for each Mac. Choose this Mac’s login in Passwords or 1Password.")
                }
                Text("Change saved addresses and ports in My Macs → this Mac’s menu → Mac Settings.")
            }.navigationTitle("Connection Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
