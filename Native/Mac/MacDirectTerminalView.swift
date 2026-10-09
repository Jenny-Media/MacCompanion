#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI
import SwiftTerm

struct MacDirectTerminalView: View {
    let mac: DirectMacRecordV1
    let sessionID: UUID
    @State private var session: DirectTerminalSession
    @State private var login = TerminalLoginSelection()
    @State private var password = ""
    @State private var remember = false
    @State private var key: TerminalSSHKey?
    @State private var keyName = ""
    @State private var sheet: Sheet?
    @State private var issue: DirectRecoveryNotice?
    @State private var window = MacWindowHandle()
    @State private var surface = MacTerminalHandle()
    @State private var actions: [VNCQuickAction] = []
    @State private var keyboard = TerminalKeyboardPreferences()
    @State private var appearance = DirectAppearanceV1.shared
    @State private var loadedInitialLogin = false
    @State private var storedFontSize: Double
    @State private var closed = false
    @Environment(\.colorScheme) private var colorScheme
    private enum Sheet: String, Identifiable { case keys, controls, keyboard, install, manual, identity, pro; var id: String { rawValue } }
    init(mac: DirectMacRecordV1, sessionID: UUID = UUID()) {
        self.mac = mac; self.sessionID = sessionID; _session = State(initialValue: DirectTerminalSession(mac: mac))
        _storedFontSize = State(initialValue: UserDefaults.standard.object(forKey: "mac-terminal-font-size-v1") as? Double ?? 14)
    }
    private var fontSize: Double { storedFontSize.isFinite ? min(28, max(10, storedFontSize)) : 14 }
    private var phase: MacConnectionPhase { session.connected ? .connected : session.connecting ? .connecting : session.recovery != nil ? .disconnected : .signIn }
    var body: some View {
        ZStack {
            MacTerminalSurface(session: session, handle: surface, colors: appearance.terminal, fontSize: fontSize)
                .padding(8).background(Color(nsColor: .textBackgroundColor))
                .environment(\.colorScheme, appearance.terminal == .app ? colorScheme : appearance.terminal == .dark ? .dark : .light)
                .opacity(session.connected ? 1 : 0)
            if !session.connected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(mac.name, systemImage: "terminal").font(.title2)
                        Text("Remote Login · SSH").foregroundStyle(.secondary)
                        if let issue { DirectRecoveryCard(notice: issue, primary: .init(title: "Retry") { loadLogin() }) }
                        if let recovery = session.recovery {
                            DirectRecoveryCard(notice: recovery, primary: recoveryAction(recovery), secondary: recovery.reason == .keyRejected ? .init(title: "Use Password") { login.select(.password); session.clearRecovery() } : nil)
                        }
                        if session.connecting {
                            ProgressView(session.status)
                            Button("Cancel") { session.cancelConnection(); password = "" }
                        } else {
                            Picker("Sign in with", selection: Binding(get: { login.method }, set: { login.select($0) })) {
                                ForEach(TerminalLoginMethod.allCases) { Text($0.rawValue).tag($0) }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mac account").font(.caption).foregroundStyle(.secondary)
                                TextField("Mac account", text: $login.username).textContentType(.username).accessibilityIdentifier("mac-terminal-account")
                            }
                            if login.method == .sshKey {
                                Text(key == nil ? "Choose an SSH key on this Mac" : keyName)
                                Button("Choose SSH Key") { sheet = .keys }
                                Button("Install Public Key") { sheet = DirectProAccess.shared.hasPro ? .install : .pro }
                                Button("Manual Key Setup") { sheet = .manual }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Password").font(.caption).foregroundStyle(.secondary)
                                    SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("mac-terminal-password")
                                }
                                Toggle("Remember login on this Mac", isOn: $remember)
                            }
                            Button("Connect") { connect() }.buttonStyle(.borderedProminent)
                                .disabled(login.username.isEmpty || (login.method == .sshKey ? key == nil : password.isEmpty))
                                .accessibilityIdentifier("mac-terminal-connect")
                        }
                    }.padding(28).frame(maxWidth: 420).frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MacConnectionStatusBar(phase: phase, service: "Remote Login · SSH", addresses: mac.addresses) }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle(mac.name + " · Terminal")
        .toolbar {
            if session.connected {
                Button("Interrupt", systemImage: "stop") { if window.acceptsActions { session.send([3]) } }
                    .labelStyle(.titleAndIcon).help("Send Ctrl+C to interrupt the running command")
                Button("Disconnect", systemImage: "power") { session.stop() }
                    .labelStyle(.titleAndIcon).help("End this SSH connection and keep its window open")
                Menu("Text Size", systemImage: "textformat.size") {
                    Button("Larger Text") { storedFontSize = min(28, fontSize + 1) }.disabled(fontSize >= 28)
                    Button("Smaller Text") { storedFontSize = max(10, fontSize - 1) }.disabled(fontSize <= 10)
                    Button("Reset Text Size") { storedFontSize = 14 }
                    Divider()
                    Text("\(Int(fontSize)) pt")
                }.help("Adjust terminal text size on this Mac")
                Menu("Quick Actions", systemImage: "keyboard") {
                    ForEach(actions.filter(\.enabled)) { action in Button(action.title, systemImage: action.symbol) { surface.view?.perform(action) } }
                    if DirectProAccess.shared.hasPro {
                        Divider()
                        ForEach(keyboard.keys) { key in Button(key.title) { surface.view?.sendAccessory(key) } }
                        ForEach(keyboard.snippets) { snippet in Button(snippet.name) { surface.view?.sendText(snippet.text) } }
                    }
                    Divider()
                    Button("Customize Keys & Snippets") { sheet = .keyboard }
                }.help("Send a configured key, shortcut or snippet")
                Button(window.fullScreen ? "Exit Full Screen" : "Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { window.toggleFullScreen() }.help("Toggle full screen for this window")
            }
            Button("Controls", systemImage: "slider.horizontal.3") { sheet = .controls }.help("Configure terminal appearance and quick actions")
        }
        .sheet(item: $sheet, onDismiss: { loadKey(); loadControls() }) { item in
            Group {
                switch item {
                case .keys: MacSSHKeyManager(mac: mac, changed: { loadKey(preferSelected: true); session.clearRecovery() })
                case .controls: VNCInputSettings(mode: .terminal, changed: loadControls)
                case .keyboard: TerminalKeyboardSettings(macID: mac.id, changed: loadControls)
                case .install: TerminalKeyInstallView(mac: mac, initialUsername: login.username, changed: { loadKey(preferSelected: true) })
                case .manual: TerminalManualKeySetupView(mac: mac)
                case .identity: TerminalIdentityGuide(macName: mac.name)
                case .pro: DirectProView()
                }
            }.frame(minWidth: 520, minHeight: 520).modifier(MacSheetPrivacyCover())
        }
        .sheet(item: Binding(get: { session.trust }, set: { if $0 == nil { session.answerTrust(false) } })) { request in
            TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint) { session.answerTrust($0) }
                .frame(width: 480, height: 410).modifier(MacSheetPrivacyCover())
        }
        .background(MacWindowLifetime { closed = true; password = ""; session.stop(); MacConnectionRegistry.shared.remove(sessionID) }.frame(width: 0, height: 0))
        .background(MacWindowReader(handle: window).frame(width: 0, height: 0))
        .onAppear { loadInitialLogin(); publishStatus() }
        .onChange(of: phase) { _, _ in publishStatus() }
        .onChange(of: storedFontSize) { _, value in UserDefaults.standard.set(value, forKey: "mac-terminal-font-size-v1") }
        .onReceive(NotificationCenter.default.publisher(for: VNCSessionPreferences.actionsChanged)) { _ in loadControls() }
        .onChange(of: session.connected) { _, connected in if connected { password = "" } }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
            if !allowed { sheet = nil; password = ""; surface.view?.lockLocalActions(); session.background() }
            else { session.foreground(); if loadedInitialLogin { loadLogin(); loadControls() } else { loadInitialLogin() } }
        }
    }
    private func publishStatus() {
        guard !closed else { return }
        MacConnectionRegistry.shared.update(id: sessionID, macID: mac.id, mode: .terminal, phase: phase, window: window)
    }
    private func loadInitialLogin() {
        guard !loadedInitialLogin, DirectAppLockV1.shared.canAccess else { return }
        loadedInitialLogin = true; loadLogin(preferSelected: true); loadControls()
        // Match iPhone's single initial attempt. Cancellation, disconnect and
        // later unlocks still require an explicit request for a new shell.
        if issue == nil, session.recovery == nil, !login.username.isEmpty,
           (login.method == .sshKey ? key != nil : !password.isEmpty) { connect() }
    }
    private func loadLogin(preferSelected: Bool = false) {
        guard DirectAppLockV1.shared.canAccess, !session.connected, !session.connecting else { return }
        issue = nil
        do {
            if let saved = try TerminalSecretStore.login(mac.id) { login.loadPasswordAccount(saved.username); password = saved.password; remember = true }
            loadKey(preferSelected: preferSelected)
        } catch { issue = .make(.savedDataUnavailable) }
    }
    private func loadKey(preferSelected: Bool = false) {
        guard DirectAppLockV1.shared.canAccess else { return }
        do {
            let selected = try TerminalKeyLibraryStore.selected(mac.id)
            key = selected?.key; keyName = selected?.name ?? ""
            login.loadKeyAccount(selected?.key.username, preferSelected: preferSelected)
        } catch { issue = .make(.savedDataUnavailable) }
    }
    private func loadControls() {
        guard DirectAppLockV1.shared.canAccess else { return }
        actions = VNCSessionPreferences.actions(.terminal)
        do { keyboard = try TerminalKeyboardPreferences.load(mac.id) }
        catch { session.controlsRecovery = .make(.controlsUnavailable) }
    }
    private func connect() {
        issue = nil
        guard DirectAppLockV1.shared.canAccess, !session.connected, !session.connecting else { return }
        if login.method == .sshKey {
            guard let key else { return }
            do { guard try MacLoginPolicy.canUseSSHKey(key) else { sheet = .pro; return } }
            catch { issue = .make(.savedDataUnavailable, message: "The selected SSH key is unavailable. Existing keys are kept; choose a key and retry."); return }
        }
        session.connect(username: login.username, password: password, remember: remember,
                        key: login.method == .sshKey ? key : nil)
    }
    private func recoveryAction(_ notice: DirectRecoveryNotice) -> DirectRecoveryAction {
        switch notice.reason {
        case .keyRejected: .init(title: "Set Up Key", pro: true) { sheet = DirectProAccess.shared.hasPro ? .install : .pro }
        case .serverChanged: .init(title: "How to Verify", perform: { sheet = .identity })
        case .savedDataUnavailable: .init(title: "Retry") { loadLogin(); session.clearRecovery() }
        case .terminalEnded, .inputPaused: .init(title: "Open New Shell", perform: reconnect)
        case .connectionCancelled: .init(title: "Return to Login", perform: session.clearRecovery)
        default: .init(title: "Try Again", perform: connect)
        }
    }
    private func reconnect() {
        if login.method == .password, password.isEmpty { loadLogin() }
        if login.method == .sshKey, key == nil { loadKey() }
        if issue == nil { connect() }
    }
}

@MainActor final class MacTerminalHandle { weak var view: MacRemoteTerminalSurface? }

struct MacTerminalSurface: NSViewRepresentable {
    let session: DirectTerminalSession
    let handle: MacTerminalHandle
    let colors: DirectTerminalAppearance
    var fontSize: Double = 14
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> MacRemoteTerminalSurface {
        let view = MacRemoteTerminalSurface(frame: CGRect(x: 0, y: 0, width: 700, height: 440), font: .monospacedSystemFont(ofSize: fontSize, weight: .regular))
        view.session = session; view.terminalDelegate = context.coordinator; view.installInputGate()
        session.suspendInput = { [weak view] in view?.releaseHeldInput() }
        handle.view = view
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Remote SSH terminal")
        view.setAccessibilityIdentifier("mac-terminal-surface")
        session.received = { [weak view] bytes in view?.feed(byteArray: bytes[...]) }
        return view
    }
    func updateNSView(_ view: MacRemoteTerminalSurface, context: Context) {
        if view.font.pointSize != fontSize { view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
        view.setAccessibilityHidden(!session.connected)
        view.appearance = colors == .app ? nil : NSAppearance(named: colors == .dark ? .darkAqua : .aqua)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.nativeForegroundColor = .textColor; view.nativeBackgroundColor = .textBackgroundColor
        }
        if session.connecting && !view.wasConnecting { view.releaseHeldInput(); view.getTerminal().resetToInitialState() }
        view.wasConnecting = session.connecting
        if session.connected, view.window?.isKeyWindow == true, view.window?.firstResponder == nil { view.window?.makeFirstResponder(view) }
    }
    static func dismantleNSView(_ view: MacRemoteTerminalSurface, coordinator: Coordinator) {
        view.releaseHeldInput(); view.session?.received = nil; view.session?.suspendInput = nil
        view.detachInputGate(); view.session = nil; view.terminalDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        private weak var session: DirectTerminalSession?
        init(session: DirectTerminalSession) { self.session = session }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session?.resize(columns: newCols, rows: newRows) }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let surface = source as? MacRemoteTerminalSurface, surface.admitGeneratedOutput(data) else { return }
            session?.send(Array(data))
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func bell(source: TerminalView) { NSSound.beep() }
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let surface = source as? MacRemoteTerminalSurface, surface.localActionsAllowed else { return }
            guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
            let alert = NSAlert(); alert.messageText = "Open link in your browser?"; alert.informativeText = url.absoluteString
            alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn, surface.accessAllowed(), session?.connected == true {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

@MainActor final class MacRemoteTerminalSurface: TerminalView {
    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        getTerminal().semanticPromptClickBehavior = .disabled
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        getTerminal().semanticPromptClickBehavior = .disabled
    }
    weak var session: DirectTerminalSession?
    var accessAllowed: () -> Bool = { DirectAppLockV1.shared.canAccess }
    var copyPasteboard: NSPasteboard = .general
    var wasConnecting = false
    private var inputMonitor: Any?
    private var observations: [NSObjectProtocol] = []
    private var heldInput = MacTerminalHeldInput()
    private var protocolOutputDepth = 0
    private var releasedButton: Int?
    private var admitsInput: Bool { session?.connected == true && accessAllowed() && window?.isKeyWindow == true && window?.firstResponder === self }
    var localActionsAllowed: Bool { admitsInput }
    override var hasFocus: Bool {
        get { super.hasFocus }
        set { if !newValue, session != nil { releaseHeldInput() }; super.hasFocus = newValue }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations.forEach(NotificationCenter.default.removeObserver); observations = []
        guard let window else { releaseHeldInput(); return }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApplication.shared as AnyObject)] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.releaseHeldInput() }
            })
        }
    }
    func releaseHeldInput() {
        session?.releaseNativeInput(heldInput.releaseAll())
        unmarkText(); inputContext?.discardMarkedText()
    }
    func lockLocalActions() {
        releaseHeldInput(); selectNone()
        func clearFields(_ view: NSView) {
            if let field = view as? NSTextField {
                (field.currentEditor() as? NSTextView)?.string = ""
                field.stringValue = ""
            }
            view.subviews.forEach(clearFields)
        }
        clearFields(self)
        let hide = NSMenuItem(); hide.tag = NSTextFinder.Action.hideFindInterface.rawValue
        super.performTextFinderAction(hide)
        window?.endEditing(for: nil); window?.makeFirstResponder(nil)
    }
    func admitGeneratedOutput(_ data: ArraySlice<UInt8>) -> Bool {
        let mouse = MacTerminalMouseReport.contains(data)
        guard (!mouse && protocolOutputDepth > 0) || admitsInput else { return false }
        guard heldInput.observe(data, keyboardEvents: protocolOutputDepth == 0 && getTerminal().keyboardEnhancementFlags.contains(.reportEvents),
                                releasedButton: releasedButton) else {
            session?.failNativeInputAdmission(); return false
        }
        return true
    }
    // SwiftTerm's keyDown is public, but not open. Gate AppKit event delivery
    // for this responder without changing the pinned dependency or blocking
    // terminal protocol responses generated while a window is in the background.
    func installInputGate() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .scrollWheel, .mouseMoved]) { [weak self] event in
            let admitted = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.filterInputEvent(event) != nil
            }
            return admitted ? event : nil
        }
    }
    func filterInputEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        if [.keyDown, .keyUp, .flagsChanged].contains(event.type) {
            guard window.firstResponder === self else { return event }
        } else {
            // A wheel event can target an inactive window without changing its
            // first responder. Hit-test the actual surface so this monitor does
            // not swallow scrolling or pointer events in another control.
            guard let content = window.contentView else { return event }
            let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            guard let target = content.hitTest(point), target === self || target.isDescendant(of: self) else { return event }
        }
        return admitsInput ? event : nil
    }
    func detachInputGate() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }; inputMonitor = nil
        observations.forEach(NotificationCenter.default.removeObserver); observations = []
    }
    private var admitsAction: Bool { session?.connected == true && accessAllowed() && window?.isKeyWindow == true }
    func sendText(_ text: String) {
        guard admitsAction, !text.isEmpty, text.utf8.count <= 65536 else { return }
        let payload = getTerminal().bracketedPasteMode ? "\u{1b}[200~" + text + "\u{1b}[201~" : text
        session?.send(Array(payload.utf8))
    }
    func sendAccessory(_ key: TerminalAccessoryKey) {
        guard admitsAction else { return }
        session?.send(key.bytes(applicationCursor: getTerminal().applicationCursor))
    }
    func perform(_ action: VNCQuickAction) {
        guard admitsAction, action.valid, action.enabled, action.compatible(with: .terminal) else { return }
        switch action.kind {
        case .shortcut: if DirectProAccess.shared.hasPro { session?.send(action.terminalBytes(applicationCursor: getTerminal().applicationCursor)) }
        case .text: if DirectProAccess.shared.hasPro { sendText(action.text) }
        case .paste: if let text = NSPasteboard.general.string(forType: .string) { sendText(text) }
        case .interrupt: session?.send([3])
        case .escape: sendAccessory(.escape)
        case .tab: sendAccessory(.tab)
        case .returnKey: session?.send([13])
        default: break
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) { guard admitsInput else { return }; super.insertText(insertString, replacementRange: replacementRange) }
    override func paste(_ sender: Any) { guard admitsInput else { return }; super.paste(sender) }
    override func copy(_ sender: Any) {
        guard admitsInput, let text = getSelection() else { return }
        copyPasteboard.clearContents(); copyPasteboard.setString(text, forType: .string)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        admitsInput && super.validateUserInterfaceItem(item)
    }
    override func performFindPanelAction(_ sender: Any?) { guard admitsInput else { return }; super.performFindPanelAction(sender) }
    override func performTextFinderAction(_ sender: Any?) { guard admitsInput else { return }; super.performTextFinderAction(sender) }
    override func mouseDown(with event: NSEvent) {
        guard admitsAction else { return }
        window?.makeFirstResponder(self)
        guard admitsInput else { return }
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        guard admitsInput else { return }
        releasedButton = event.buttonNumber; defer { releasedButton = nil }
        super.mouseUp(with: event)
    }
    override func mouseDragged(with event: NSEvent) { guard admitsInput else { return }; super.mouseDragged(with: event) }
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        guard admitsInput || !MacTerminalMouseReport.contains(data) else { return }
        protocolOutputDepth += 1; defer { protocolOutputDepth -= 1 }
        if let corrected = MacTerminalMouseReport.correctingSGRRelease(data, button: releasedButton) {
            super.send(source: source, data: corrected[...])
        } else { super.send(source: source, data: data) }
    }
}
#endif
