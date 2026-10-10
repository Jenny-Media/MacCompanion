#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct MacDirectDesktopView: View {
    let mac: DirectMacRecordV1
    let sessionID: UUID
    @State private var session: MacVNCSession
    @State private var username = ""
    @State private var password = ""
    @State private var remember = false
    @State private var issue: DirectRecoveryNotice?
    @State private var window = MacWindowHandle()
    @State private var controls = false
    @State private var actions: [VNCQuickAction] = []
    @State private var closed = false
    @State private var initialLogin = MacVNCInitialLogin()
    init(mac: DirectMacRecordV1, sessionID: UUID = UUID()) {
        self.mac = mac; self.sessionID = sessionID
        _session = State(initialValue: MacVNCSession(mac: mac))
    }
    private var phase: MacConnectionPhase {
        session.connected ? .connected : session.connecting ? .connecting : session.recovery != nil || session.status == "Disconnected" ? .disconnected : .signIn
    }
    var body: some View {
        ZStack {
            MacVNCSurface(session: session)
            if !session.connected {
                MacSignInPanel(mac: mac, mode: .desktop) {
                    MacCredentialFields(username: $username, password: $password, enabled: !session.connecting && DirectAppLockV1.shared.canAccess, prefix: "mac-vnc", submit: connect)
                        .frame(height: 104)
                    Toggle("Remember login on this Mac", isOn: $remember).disabled(session.connecting)
                    if let notice = issue ?? session.recovery {
                        DirectRecoveryCard(notice: notice, primary: notice.reason == .savedDataUnavailable
                            ? .init(title: "Retry Saved Login", perform: loadLogin) : nil)
                    }
                } status: {
                    HStack {
                    if session.connecting {
                        ProgressView().controlSize(.small)
                        Text(session.status).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { session.disconnect(); password = "" }
                    } else {
                        Spacer()
                        Button("Connect", systemImage: "arrow.right", action: connect)
                            .buttonStyle(.borderedProminent).disabled(username.isEmpty || password.isEmpty)
                            .keyboardShortcut(.defaultAction).controlSize(.large)
                            .accessibilityIdentifier("mac-vnc-connect")
                    }
                    }.frame(height: 36)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !window.fullScreen || !session.connected { MacConnectionStatusBar(phase: phase, service: "Screen Sharing", addresses: mac.addresses) }
        }
        .overlay(alignment: .top) {
            if window.fullScreen && session.connected { MacDesktopFullScreenControls(session: session, window: window, actions: actions) { controls = true } }
        }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle(mac.name + " · Desktop")
        .toolbar {
            if session.connected {
                Menu("Displays", systemImage: "display.2") {
                    Button("All Displays") { session.selectDisplay(nil) }
                    ForEach(session.displays) { display in Button("Display \(display.id)") { session.selectDisplay(display.id) } }
                }.help("Choose the remote display to control")
                Menu("View", systemImage: "magnifyingglass") {
                    Button("Fit to Window") { session.fit() }
                    Button("Zoom In") { session.zoom = min(8, session.zoom * 1.25) }
                    Button("Zoom Out") { session.zoom = max(1, session.zoom / 1.25) }.disabled(session.zoom <= 1)
                    Divider()
                    Text("Zoom relative to fit: \(Int(session.zoom * 100))%")
                }.help("Fit or zoom the remote desktop locally")
                Button("Disconnect", systemImage: "power") { session.disconnect() }
                    .labelStyle(.titleAndIcon).help("End this Screen Sharing connection and keep its window open")
                Menu("Send Key", systemImage: "keyboard") {
                    ForEach(actions.filter(\.enabled)) { action in
                        Button(action.title, systemImage: action.symbol) { if window.acceptsActions { session.quickAction(action) } }
                    }
                }.help("Send a configured key or action to this Mac")
                Button(window.fullScreen ? "Exit Full Screen" : "Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { window.toggleFullScreen() }
                    .help("Toggle full screen for this window")
            }
            Button("Controls", systemImage: "slider.horizontal.3") { controls = true }.help("Configure display, scrolling and optional shortcuts")
        }
        .toolbarVisibility(window.fullScreen && session.connected ? .hidden : .automatic, for: .windowToolbar)
        .sheet(isPresented: $controls) {
            MacDesktopSettings(macID: mac.id) { loadActions() }.modifier(MacSheetPrivacyCover())
        }
        .background(MacWindowLifetime { closed = true; password = ""; session.close(); MacConnectionRegistry.shared.remove(sessionID) }.frame(width: 0, height: 0))
        .background(MacWindowReader(handle: window, initiallyFullScreen: VNCSessionPreferences.fullscreen(mac.id)) {
            VNCSessionPreferences.setFullscreen($0, mac: mac.id)
        }.frame(width: 0, height: 0))
        .onAppear { loadInitialLogin(); loadActions(); publishStatus() }
        .onChange(of: phase) { _, _ in publishStatus() }
        .onReceive(NotificationCenter.default.publisher(for: VNCSessionPreferences.actionsChanged)) { _ in loadActions() }
        .onChange(of: session.connected) { _, value in if value { password = "" } }
        .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in
            password = ""; session.pauseInput()
        }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in
            if !value { controls = false; password = ""; session.pauseInput() }
            else if initialLogin.loaded { restoreRememberedPassword() }
            else { loadInitialLogin() }
        }
    }
    private func publishStatus() {
        guard !closed else { return }
        MacConnectionRegistry.shared.update(id: sessionID, macID: mac.id, mode: .desktop, phase: phase, window: window)
    }
    private func loadActions() { actions = VNCSessionPreferences.actions(.desktop, legacyMac: mac.id).filter { $0.kind != .mode } }
    private func loadInitialLogin() {
        guard !closed, !session.connected, !session.connecting else { return }
        do {
            guard let saved = try initialLogin.loadIfNeeded(canAccess: DirectAppLockV1.shared.canAccess,
                hasExplicitLogin: !username.isEmpty || !password.isEmpty, usable: { login in
                    do {
                        try MacLoginPolicy.prepareVNC(username: login.username, password: login.password,
                                                      remember: true, macID: mac.id)
                        return true
                    } catch { return false }
                },
                read: { try DesktopCredentialStoreV1.readChecked(mac.id) }) else { return }
            issue = nil
            username = saved.login.username; password = saved.login.password; remember = true
            if saved.shouldConnect { connect() }
        } catch { issue = .make(.savedDataUnavailable) }
    }
    private func restoreRememberedPassword() {
        guard DirectAppLockV1.shared.canAccess, !closed, !session.connected, !session.connecting,
              remember, password.isEmpty, !username.isEmpty else { return }
        do {
            if let saved = try DesktopCredentialStoreV1.readChecked(mac.id), saved.username == username {
                password = saved.password
            }
        } catch { issue = .make(.savedDataUnavailable) }
    }
    private func loadLogin() {
        guard DirectAppLockV1.shared.canAccess, !session.connected, !session.connecting else { return }
        issue = nil
        do { if let saved = try DesktopCredentialStoreV1.readChecked(mac.id) { username = saved.username; password = saved.password; remember = true } }
        catch { issue = .make(.savedDataUnavailable) }
    }
    private func connect() {
        guard !closed, !session.connecting, !session.connected, DirectAppLockV1.shared.canAccess else { return }
        issue = nil; session.connect(username: username, password: password, remember: remember)
    }
}
#endif
