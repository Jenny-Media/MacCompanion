#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct VisionSessionWindow: View {
    let request: VisionSessionRequest
    let library: DirectMacLibraryV1
    @State private var desktop: VisionDesktopSession?
    @State private var terminal: DirectTerminalSession?
    @State private var terminalOutput: VisionTerminalOutput?
    @State private var terminalInteraction = VisionTerminalInteraction()
    @State private var lock = DirectAppLockV1.shared
    @State private var draft = DirectFilesLoginDraft()
    @State private var loginAttempt: DirectFilesLoginDraft.AuthenticationAttempt?
    private var username: String { draft.username }
    private var password: String { draft.password }
    private var remember: Bool { draft.remember }
    private var useKey: Bool { draft.method == .sshKey }
    @State private var key: TerminalNamedKey?
    @State private var desktopInteraction = VisionDesktopInteraction()
    @State private var keysShown = false
    @State private var draftError: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(VisionSessionRegistry.self) private var sessions
    @FocusState private var loginFocus: LoginField?
    @State private var closing = false
    private enum LoginField { case account, password }
    init(request: VisionSessionRequest, library: DirectMacLibraryV1) {
        self.request = request; self.library = library
        _desktop = State(initialValue: request.connection == .desktop ? VisionDesktopSession(mac: request.mac, libraryURL: library.storageURL) : nil)
        let session = request.connection == .terminal ? DirectTerminalSession(mac: request.mac, libraryURL: library.storageURL) : nil
        _terminal = State(initialValue: session)
        _terminalOutput = State(initialValue: session.map(VisionTerminalOutput.init))
    }
    private var connected: Bool { desktop?.connected == true || terminal?.connected == true }
    private var connecting: Bool { desktop?.connecting == true || terminal?.connecting == true }
    private var status: String { desktop?.status ?? terminal?.status ?? "Ready" }
    private var recovery: DirectRecoveryNotice? { desktop?.recovery ?? terminal?.recovery }
    private var trust: Binding<DirectTerminalSession.TrustRequest?> {
        Binding(get: { desktop?.trust ?? terminal?.trust }, set: { value in if value == nil { answerTrust(false) } })
    }
    var body: some View {
        NavigationStack { VStack(spacing: 0) {
            HStack {
                Label(request.mac.name + " · " + (request.connection == .desktop ? "Screen Sharing" : "Terminal"), systemImage: request.connection == .desktop ? "desktopcomputer" : "terminal")
                    .font(.headline)
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Your Macs", systemImage: "square.grid.2x2") { openWindow(id: "library") }.labelStyle(.iconOnly)
                Button("Close Window", systemImage: "xmark") {
                    closeWindow()
                }.labelStyle(.iconOnly).accessibilityIdentifier("vision-close-session")
            }.padding(16)
            if connected {
                if let desktop {
                    VisionDesktopSurface(session: desktop, interaction: desktopInteraction)
                        .overlay(alignment: .top) { if desktopInteraction.adjusting { viewAdjustmentControls() } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if desktopInteraction.keyboardVisible {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Typing on " + request.mac.name).font(.caption).foregroundStyle(.secondary)
                                VisionDesktopKeyboard(session: desktop, interaction: desktopInteraction).frame(height: 44)
                            }
                            Button("Done") { desktopInteraction.dismissKeyboard() }
                                .accessibilityIdentifier("vision-keyboard-done")
                        }.padding(16)
                    }
                } else if let terminal {
                    VisionTerminalSurface(session: terminal, interaction: terminalInteraction, output: terminalOutput)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                login
            }
        }.frame(minWidth: 600, minHeight: 420)
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    if connected {
                        if let desktop { desktopControls(desktop) }
                        else if let terminal { terminalControls(terminal) }
                    }
                }
            }
        }
            .sheet(item: trust) { value in TerminalServerTrustView(macName: request.mac.name, fingerprint: value.fingerprint, answer: answerTrust) }
            .sheet(isPresented: $keysShown, onDismiss: loadLogin) { TerminalKeySettings(mac: request.mac) }
            .confirmationDialog("Open this web link?", isPresented: Binding(get: { terminalInteraction.link != nil }, set: { if !$0 { terminalInteraction.link = nil } })) {
                Button("Open in Browser") {
                    if phase == .active, lock.canAccess, connected, let url = terminalInteraction.link { DirectClientPlatformV1.open(url) }
                    terminalInteraction.link = nil
                }
            } message: { Text(terminalInteraction.link?.absoluteString ?? "") }
            .onAppear { sessions.add(request); loadLogin() }
            .onDisappear { sessions.remove(request.id); desktop?.close(); terminal?.stop(); clearDraft() }
            .onChange(of: phase) { _, value in
                if value == .active && lock.canAccess { draft.resume(); desktop?.resume(); terminal?.foreground(); loadLogin() }
                else { interrupt() }
            }
            .onChange(of: lock.canAccess) { _, available in
                if available && phase == .active { draft.resume(); desktop?.resume(); terminal?.foreground(); loadLogin() }
                else { interrupt() }
            }
            .onChange(of: connected) { _, value in
                if value {
                    draft.authenticationSucceeded(loginAttempt, retention: remember && !useKey ? (recovery?.reason == .saveFailed ? .failed : .saved) : .notRequested)
                    loginAttempt = nil
                } else { draft.passwordSessionEnded(); loadLogin() }
            }
            .onChange(of: desktop?.closed) { _, value in if value == true { closeWindow() } }
            .onChange(of: terminal?.macRemoved) { _, value in if value == true { closeWindow() } }
            .onChange(of: library.macs) { _, records in
                if !records.contains(where: { $0.id == request.mac.id }) { closeWindow() }
            }
    }
    private func closeWindow() {
        guard !closing else { return }; closing = true
        desktop?.close(); terminal?.stop(); clearDraft()
        sessions.remove(request.id)
        dismissWindow(id: "connection", value: request)
    }
    private var login: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let recovery {
                    Text(recovery.title).font(.title2)
                    DirectNoticeMessage(message: recovery.message)
                }
                Text(request.connection == .desktop ? "Screen Sharing" : "Remote Login").font(.title2)
                if request.connection == .desktop { Text("View and control this Mac").foregroundStyle(.secondary) }
                Text(request.connection == .desktop ? "Enable Screen Sharing and Remote Login on your Mac, then sign in with an allowed Mac account." : "Enable Remote Login on your Mac, then sign in with an allowed Mac account.")
                    .foregroundStyle(.secondary)
                TextField("Mac Account", text: $draft.username).directNoAutocapitalization().autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("vision-login-account")
                    .focused($loginFocus, equals: .account).submitLabel(.next)
                    .onSubmit { loginFocus = .password }
                if request.connection == .terminal, let key {
                    Toggle("Use SSH Key: \(key.name)", isOn: Binding(get: { useKey }, set: { draft.selectMethod($0 ? .sshKey : .password); loadLogin() }))
                }
                if !useKey {
                    SecureField("Mac Password", text: $draft.password).textFieldStyle(.roundedBorder).accessibilityIdentifier("vision-login-password")
                        .focused($loginFocus, equals: .password).submitLabel(.go)
                        .onSubmit { if !connecting { connect() } }
                    Toggle("Remember This Login on This Device", isOn: $draft.remember)
                }
                if let draftError { Text(draftError).foregroundStyle(.red) }
                HStack {
                    if connecting {
                        ProgressView(); Button("Cancel Connection") { desktop?.disconnect(); terminal?.cancelConnection(); loginAttempt = nil }
                    } else {
                        Button("Connect") { connect() }.buttonStyle(.borderedProminent).accessibilityIdentifier("vision-connect")
                    }
                    if request.connection == .terminal { Button("SSH Keys") { keysShown = true } }
                }
            }.padding(32).frame(maxWidth: 560)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func desktopControls(_ session: VisionDesktopSession) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { desktopButtons(session) }
            HStack(spacing: 16) { desktopButtons(session) }.labelStyle(.iconOnly)
        }.controlSize(.large)
    }
    @ViewBuilder private func desktopButtons(_ session: VisionDesktopSession) -> some View {
            Button("Keyboard", systemImage: "keyboard") { desktopInteraction.requestKeyboard() }
                .accessibilityIdentifier("vision-keyboard-button")
            Menu("Displays", systemImage: "display.2") {
                Button("All Displays") { session.selectDisplay(nil) }
                ForEach(session.displays) { display in Button("Display \(display.id)") { session.selectDisplay(display.id) } }
            }
            Button("Adjust View", systemImage: "arrow.up.left.and.arrow.down.right") {
                desktopInteraction.canvas?.setAdjusting(!desktopInteraction.adjusting)
            }.accessibilityIdentifier("vision-adjust-view")
            Menu("More", systemImage: "ellipsis") {
                Button("Screen Sharing Actions") { desktopInteraction.canvas?.showActions() }
                ForEach(VisionQuickActionPresentation.presented(VNCSessionPreferences.actions(.desktop), mode: .desktop).filter { $0.enabled && $0.valid }) { action in
                    Button(action.displayTitle) { desktopInteraction.performQuickAction(action) }
                }
                Button("Disconnect", role: .destructive) { session.disconnect(); desktopInteraction.dismissKeyboard(); loadLogin() }
                    .accessibilityIdentifier("vision-disconnect")
            }
    }
    private func viewAdjustmentControls() -> some View {
        GeometryReader { geometry in
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { adjustmentButtons }.fixedSize()
                    VStack(spacing: 12) { adjustmentButtons }
                }.padding(12)
            }.accessibilityIdentifier("vision-view-adjustments")
                .frame(maxWidth: .infinity, maxHeight: min(220, max(100, geometry.size.height / 2)))
                .glassBackgroundEffect().padding(16)
        }
    }
    @ViewBuilder private var adjustmentButtons: some View {
        Text("Adjust View").font(.headline)
        Button("Fit") { desktopInteraction.canvas?.cancelSelection(); desktop?.fit() }
        Button("Zoom Out", systemImage: "minus.magnifyingglass") { desktopInteraction.canvas?.adjustZoom(0.8) }
        Button("Zoom In", systemImage: "plus.magnifyingglass") { desktopInteraction.canvas?.adjustZoom(1.25) }
        Menu("Pan", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
            Button("Pan Left") { desktopInteraction.canvas?.adjustPan(CGPoint(x: 80, y: 0)) }
            Button("Pan Right") { desktopInteraction.canvas?.adjustPan(CGPoint(x: -80, y: 0)) }
            Button("Pan Up") { desktopInteraction.canvas?.adjustPan(CGPoint(x: 0, y: 80)) }
            Button("Pan Down") { desktopInteraction.canvas?.adjustPan(CGPoint(x: 0, y: -80)) }
        }
        Button("Done") { desktopInteraction.canvas?.setAdjusting(false) }
            .accessibilityIdentifier("vision-adjustment-done")
    }
    private func terminalControls(_ session: DirectTerminalSession) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { terminalButtons(session) }
            HStack(spacing: 16) { terminalButtons(session) }.labelStyle(.iconOnly)
        }.controlSize(.large)
    }
    @ViewBuilder private func terminalButtons(_ session: DirectTerminalSession) -> some View {
            Button("Keyboard", systemImage: "keyboard") { terminalInteraction.keyboard?() }
            Button("Tab") { terminalInteraction.specialKey?(0xff09) }
            Menu("Keys", systemImage: "keyboard.badge.ellipsis") {
                Button("Escape") { terminalInteraction.specialKey?(0xff1b) }
                Button("Arrow Up") { terminalInteraction.specialKey?(0xff52) }
                Button("Arrow Down") { terminalInteraction.specialKey?(0xff54) }
                Button("Arrow Left") { terminalInteraction.specialKey?(0xff51) }
                Button("Arrow Right") { terminalInteraction.specialKey?(0xff53) }
                Button(terminalInteraction.control ? "Control: On" : "Control: Off") { terminalInteraction.toggleModifier?(true) }
                Button(terminalInteraction.option ? "Option: On" : "Option: Off") { terminalInteraction.toggleModifier?(false) }
                Button("Ctrl-C") { terminalInteraction.quickAction?(.init(title: "Interrupt", kind: .interrupt)) }
                Button("Ctrl-D") { terminalInteraction.sendControl?(4) }
                Button("Hide Keyboard") { terminalInteraction.dismissKeyboard?() }
            }
            Menu("More", systemImage: "ellipsis") {
                ForEach(VNCSessionPreferences.actions(.terminal).filter { $0.enabled && $0.valid && $0.compatible(with: .terminal) }) { action in
                    Button(action.displayTitle) { terminalInteraction.quickAction?(action) }
                }
                Button("New Shell") {
                    guard phase == .active, lock.canAccess else { return }
                    openWindow(id: "connection", value: VisionSessionRequest(mac: request.mac, connection: .terminal))
                }.accessibilityIdentifier("vision-new-shell")
                Button("End Shell", role: .destructive) { session.stop(); loadLogin() }
                    .accessibilityIdentifier("vision-end-shell")
            }
    }
    private func connect() {
        guard phase == .active, lock.canAccess, DirectProAccess.shared.ready,
              library.macs.contains(where: { $0.id == request.mac.id }),
              DirectProAccess.shared.canUseMac(request.mac.id, among: library.macs.map(\.id)) else {
            draftError = "Open an available saved Mac from Your Macs."; return
        }
        draftError = nil
        loginAttempt = draft.authenticationAttempt(account: username, password: useKey ? nil : password, remember: remember)
        if let desktop { desktop.connect(username: username, password: password, remember: remember) }
        else if let terminal {
            if useKey {
                do {
                    guard let key, try TerminalKeyLibraryStore.canUse(key) else { draftError = "Choose an available SSH key in Settings."; return }
                    terminal.connect(username: username, password: "", remember: false, key: key.key)
                } catch { draftError = "The selected key couldn’t be read. Existing keys are kept." }
            } else { terminal.connect(username: username, password: password, remember: remember) }
        }
    }
    private func loadLogin() {
        guard phase == .active, lock.canAccess, !connected, !connecting, !closing else { return }
        do {
            let initial = draft.needsInitialLoad(active: true, allowed: true, signIn: true)
            func saved() throws -> TerminalSecretStore.Login? {
                if request.connection == .desktop {
                    return try DesktopCredentialStoreV1.readChecked(request.mac.id).map { .init(username: $0.username, password: $0.password) }
                }
                return try TerminalSecretStore.login(request.mac.id)
            }
            if initial { draft.initialize(saved: try saved()) }
            if request.connection == .terminal {
                key = try TerminalKeyLibraryStore.selected(request.mac.id)
                let identity = key.map { DirectFilesLoginDraft.NamedKeyIdentity(id: $0.id, fingerprint: $0.key.fingerprint) }
                if draft.updateNamedKey(identity) || initial { draft.loadKeyAccount(key?.key.username, preferSelected: initial) }
            }
            try draft.restorePassword(active: true, allowed: true, signIn: true, read: saved)
        } catch { draftError = "The saved login couldn’t be read. Existing local data is kept." }
    }
    private func answerTrust(_ accepted: Bool) { desktop?.answerTrust(accepted); terminal?.answerTrust(accepted) }
    private func clearDraft() { draft.invalidate(); loginAttempt = nil; key = nil; draftError = nil }
    private func interrupt() { desktop?.pause(); terminal?.background(); draft.suspend(); desktopInteraction.dismissKeyboard() }
}
#endif
