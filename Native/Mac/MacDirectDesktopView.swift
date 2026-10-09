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
    init(mac: DirectMacRecordV1, inputOnly: Bool, sessionID: UUID = UUID()) {
        self.mac = mac; self.sessionID = sessionID
        _session = State(initialValue: MacVNCSession(mac: mac, inputOnly: inputOnly))
    }
    private var phase: MacConnectionPhase {
        session.connected ? .connected : session.connecting ? .connecting : session.recovery != nil || session.status == "Disconnected" ? .disconnected : .signIn
    }
    var body: some View {
        ZStack {
            MacVNCSurface(session: session)
            if !session.connected {
                VStack(alignment: .leading, spacing: 18) {
                    Label(mac.name, systemImage: session.inputOnly ? "rectangle.and.hand.point.up.left" : "macwindow").font(.title2)
                    Text(session.inputOnly ? "Trackpad & Keyboard · Screen Sharing" : "Desktop · Screen Sharing").foregroundStyle(.secondary)
                    if session.inputOnly {
                        Text("Control the pointer and keyboard without showing the remote desktop.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let notice = issue ?? session.recovery {
                        DirectRecoveryCard(notice: notice, primary: .init(title: notice.reason == .savedDataUnavailable ? "Retry Saved Login" : "Reconnect") {
                            loadLogin()
                            if issue == nil, !username.isEmpty, !password.isEmpty { connect() }
                        })
                    }
                    if session.connecting {
                        ProgressView(session.status)
                        Button("Cancel") { session.disconnect(); password = "" }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mac account").font(.caption).foregroundStyle(.secondary)
                            TextField("Mac account", text: $username).textContentType(.username).accessibilityIdentifier("mac-vnc-account")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password").font(.caption).foregroundStyle(.secondary)
                            SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("mac-vnc-password")
                        }
                        Toggle("Remember login on this Mac", isOn: $remember)
                        Button("Connect", action: connect)
                            .buttonStyle(.borderedProminent).disabled(username.isEmpty || password.isEmpty)
                            .tint(username.isEmpty || password.isEmpty ? .gray : .accentColor)
                            .accessibilityIdentifier("mac-vnc-connect")
                    }
                }.padding(28).frame(maxWidth: 420).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if session.inputOnly {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.hand.point.up.left").font(.largeTitle)
                    Text("Trackpad & Keyboard").font(.title2)
                    Text("Click this pad to focus it, then move, scroll or type to control \(mac.name).")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("The remote desktop is not displayed.").font(.caption).foregroundStyle(.secondary)
                }.padding(32).frame(maxWidth: 460, minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.3)))
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MacConnectionStatusBar(phase: phase, service: "Screen Sharing", addresses: mac.addresses) }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle(mac.name + (session.inputOnly ? " · Trackpad & Keyboard" : " · Desktop"))
        .toolbar {
            if session.connected {
                Menu("Displays", systemImage: "display.2") {
                    Button("All Displays") { session.selectDisplay(nil) }
                    ForEach(session.displays) { display in Button("Display \(display.id)") { session.selectDisplay(display.id) } }
                }.help("Choose the remote display to control")
                if !session.inputOnly {
                    Menu("View", systemImage: "magnifyingglass") {
                        Button("Fit to Window") { session.fit() }
                        Button("Zoom In") { session.zoom = min(8, session.zoom * 1.25) }
                        Button("Zoom Out") { session.zoom = max(1, session.zoom / 1.25) }.disabled(session.zoom <= 1)
                        Divider()
                        Text("Zoom relative to fit: \(Int(session.zoom * 100))%")
                    }.help("Fit or zoom the remote desktop locally")
                    Toggle("Trackpad Input", isOn: $session.trackpad)
                        .help("Use relative pointer movement in this Desktop window")
                        .onChange(of: session.trackpad) { _, value in VNCSessionPreferences.setTrackpad(value, mac: mac.id) }
                }
                Button("Disconnect", systemImage: "power") { session.disconnect() }
                    .labelStyle(.titleAndIcon).help("End this Screen Sharing connection and keep its window open")
                Menu("Quick Actions", systemImage: "keyboard") {
                    ForEach(actions.filter(\.enabled)) { action in
                        Button(action.title, systemImage: action.symbol) { if window.acceptsActions { session.quickAction(action) } }
                    }
                }.help("Send a configured key or action to this Mac")
                Button(window.fullScreen ? "Exit Full Screen" : "Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { window.toggleFullScreen() }
                    .help("Toggle full screen for this window")
            }
            Button("Controls", systemImage: "slider.horizontal.3") { controls = true }.help("Configure pointer, display and keyboard controls")
        }
        .sheet(isPresented: $controls) {
            VNCInputSettings(macID: mac.id, mode: session.inputOnly ? .trackpad : .desktop) { session.reloadPreferences(); loadActions() }
                .frame(minWidth: 520, minHeight: 520)
        }
        .background(MacWindowLifetime { closed = true; password = ""; session.close(); MacConnectionRegistry.shared.remove(sessionID) }.frame(width: 0, height: 0))
        .background(MacWindowReader(handle: window, initiallyFullScreen: VNCSessionPreferences.fullscreen(mac.id)) {
            VNCSessionPreferences.setFullscreen($0, mac: mac.id)
        }.frame(width: 0, height: 0))
        .onAppear { loadLogin(); loadActions(); publishStatus() }
        .onChange(of: phase) { _, _ in publishStatus() }
        .onReceive(NotificationCenter.default.publisher(for: VNCSessionPreferences.actionsChanged)) { _ in loadActions() }
        .onChange(of: session.connected) { _, value in if value { password = "" } }
        .onReceive(NotificationCenter.default.publisher(for: DirectClientPlatformV1.didEnterBackground)) { _ in
            password = ""; session.pauseInput()
        }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in if !value { password = ""; session.pauseInput() } else { loadLogin() } }
    }
    private func publishStatus() {
        guard !closed else { return }
        MacConnectionRegistry.shared.update(id: sessionID, macID: mac.id, mode: session.inputOnly ? .trackpad : .desktop, phase: phase, window: window)
    }
    private func loadActions() { actions = VNCSessionPreferences.actions(session.inputOnly ? .trackpad : .desktop, legacyMac: mac.id) }
    private func loadLogin() {
        guard DirectAppLockV1.shared.canAccess, !session.connected, !session.connecting else { return }
        issue = nil
        do { if let saved = try DesktopCredentialStoreV1.readChecked(mac.id) { username = saved.username; password = saved.password; remember = true } }
        catch { issue = .make(.savedDataUnavailable) }
    }
    private func connect() {
        issue = nil; session.connect(username: username, password: password, remember: remember)
    }
}
#endif
