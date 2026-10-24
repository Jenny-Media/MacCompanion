#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import SwiftTerm
import UIKit
import Observation

/// One ephemeral form owner; never used as the live SSH recovery owner.
@MainActor @Observable final class DirectTerminalLoginForm {
    var draft: DirectFilesLoginDraft
    @ObservationIgnored private var macID: UUID?
    @ObservationIgnored private var forgetObserver: DirectMacAccessForgetObservation?
    init(draft: DirectFilesLoginDraft = DirectFilesLoginDraft()) { self.draft = draft }
    func bind(to macID: UUID) {
        guard self.macID != macID else { return }
        if self.macID != nil { draft = .init() }
        self.macID = macID
        forgetObserver = DirectMacAccessForgetObservation(macID: macID) { [weak self] in self?.draft = .init() }
    }
}

struct DirectTerminalView: View {
    private var mac: DirectMacRecordV1 { session.mac }
    let macLibrary: DirectMacLibraryV1?
    let exit: @MainActor () -> Void
    @State private var files: DirectFilesSession
    @State private var session: DirectTerminalSession
    @State private var form: DirectTerminalLoginForm
    private var draft: DirectFilesLoginDraft {
        get { form.draft }
        nonmutating set { form.draft = newValue }
    }
    @State private var loginAttempt: DirectFilesLoginDraft.AuthenticationAttempt?
    private var username: String { get { draft.username } nonmutating set { draft.username = newValue } }
    private var password: String { get { draft.password } nonmutating set { draft.password = newValue } }
    private var remember: Bool { get { draft.remember } nonmutating set { draft.remember = newValue } }
    @State private var passwordVisible = false
    @State private var nativeFormHeight: CGFloat = 420
    @State private var nativeFooterHeight: CGFloat = 112
    @State private var nativeProgressHeight: CGFloat = 240
    @State private var detailsExpanded = false
    @State private var loginIssue: DirectRecoveryNotice?
    @State private var key: TerminalSSHKey?
    @State private var keyName = ""
    private var useKey: Bool { draft.method == .sshKey }
    @State private var loadedLogin = false
    // Connection state describes the transport; departure belongs to this view.
    // Preserve the outgoing panel's content until UIKit finishes dismissing it.
    private enum ClosingContent { case login, progress }
    @State private var closingContent: ClosingContent?
    private var isClosing: Bool { closingContent != nil }
    private let autoConnect: Bool
    private let connectionPanel: DirectConnectionPanelHost?
    private let loginRetentionAllowed: Bool
    private let connectionEstablished: @MainActor () -> Bool
    private enum Sheet: Identifiable {
        case keys, install, manual, macSettings, appSettings, pro, quickActions, savedTextLibrary, keyboard, verifyGuide, connectionInfo, files, access
        var id: String {
            switch self {
            case .keys: "keys"; case .install: "install"; case .manual: "manual"; case .macSettings: "macSettings"
            case .appSettings: "appSettings"; case .pro: "pro"; case .quickActions: "quickActions"; case .savedTextLibrary: "savedTextLibrary"; case .keyboard: "keyboard"
            case .access: "access"; case .files: "files"; case .verifyGuide: "verifyGuide"; case .connectionInfo: "connectionInfo"
            }
        }
    }
    @State private var sheet: Sheet?
    @State private var confirmingExit = false
    @State private var controlsReloadPending = false
    @State private var controlsContextImage: UIImage?
    @Environment(DirectAppearanceV1.self) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.colorScheme) private var colorScheme
    private var terminalScheme: ColorScheme? {
        switch appearance.terminal { case .dark: .dark; case .light: .light; case .app: appearance.app.colorScheme }
    }
    private var terminalBackground: SwiftUI.Color { (terminalScheme ?? colorScheme) == .dark ? .black : .white }
    // The outgoing sheet still observes this session while UIKit dismisses it.
    // Keep its progress content through success instead of rebuilding the form.
    private var showsConnectionProgress: Bool {
        if let closingContent { return closingContent == .progress }
        return session.connecting || session.connected || (autoConnect && !loadedLogin)
    }
    private var canConnect: Bool {
        !username.isEmpty && username.utf8.count <= 255 && !username.contains("\0") &&
        (useKey ? key != nil : !password.isEmpty && password.utf8.count <= 4096 && !password.contains("\0"))
    }
    init(mac: DirectMacRecordV1, macLibrary: DirectMacLibraryV1? = nil, session: DirectTerminalSession? = nil, files: DirectFilesSession? = nil, autoConnect: Bool = true, loginForm: DirectTerminalLoginForm = DirectTerminalLoginForm(), connectionPanel: DirectConnectionPanelHost? = nil, loginRetentionAllowed: Bool = true, connectionEstablished: @escaping @MainActor () -> Bool = { true }, exit: @escaping @MainActor () -> Void) {
        self.connectionPanel = connectionPanel; self.loginRetentionAllowed = loginRetentionAllowed; self.connectionEstablished = connectionEstablished
        self.macLibrary = macLibrary; self.exit = exit
        loginForm.bind(to: mac.id)
        _form = State(initialValue: loginForm)
        let libraryURL = macLibrary?.storageURL ?? DirectMacLibraryV1.defaultURL
        _session = State(initialValue: session ?? DirectTerminalSession(mac: mac, libraryURL: libraryURL))
        _files = State(initialValue: files ?? DirectFilesWorkspace.session(mac, libraryURL: libraryURL))
        self.autoConnect = autoConnect
    }
    private func connect() {
        guard !isClosing, canConnect, !session.connecting, !session.connected else { return }
        if useKey {
            do {
                let library = try TerminalKeyLibraryStore.load()
                if let selected = try TerminalKeyLibraryStore.selected(mac.id), !DirectProAccess.shared.canUseKey(selected.id, among: library.keys.map(\.id)) { sheet = .pro; return }
            } catch { loginIssue = .make(.savedDataUnavailable, message: "The SSH key library couldn’t be read. Existing keys are kept."); return }
        }
        loginIssue = nil
        session.connectionEstablished = connectionEstablished
        session.saveMacRequested = loginRetentionAllowed
        if !loginRetentionAllowed { remember = false }
        loginAttempt = draft.authenticationAttempt(account: username, password: useKey ? nil : password, remember: remember)
        session.connect(username: username, password: useKey ? "" : password, remember: !useKey && remember, key: useKey ? key : nil)
    }
    private func loadKey(preferSelected: Bool = false) {
        do {
            let selected = try TerminalKeyLibraryStore.selected(mac.id)
            key = selected?.key; keyName = selected?.name ?? ""
            let identity = selected.map { DirectFilesLoginDraft.NamedKeyIdentity(id: $0.id, fingerprint: $0.key.fingerprint) }
            if draft.updateNamedKey(identity) || preferSelected { draft.loadKeyAccount(selected?.key.username, preferSelected: preferSelected) }
        } catch { loginIssue = .make(.savedDataUnavailable, message: "The selected SSH key couldn’t be read. Existing keys are kept.") }
    }
    private func loadLogin(reload: Bool = false) {
        guard !isClosing, !session.completedNormally, !session.connected, !session.connecting, !session.macRemoved,
              DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { return }
        loginIssue = nil
        if reload { draft = DirectFilesLoginDraft() }
        do {
            if draft.needsInitialLoad(active: true, allowed: true, signIn: true) {
                draft.initialize(saved: try TerminalSecretStore.login(mac.id))
            }
            try draft.restorePassword(active: true, allowed: true, signIn: true) { try TerminalSecretStore.login(mac.id) }
        } catch { loginIssue = .make(.savedDataUnavailable, message: "The saved Terminal login couldn’t be read. Existing data is kept.") }
        loadKey(preferSelected: !loadedLogin || reload)
        if (!loadedLogin || reload), let profile = try? DirectMacAccessStore.load(mac.id) {
            draft.selectMethod(profile.sshMethod == .key ? .sshKey : .password)
        }
    }
    private func selectLoginMethod(_ method: TerminalLoginMethod) {
        draft.selectMethod(method)
        loadLogin(); session.clearRecovery()
    }
    private func retirePresentation() {
        guard !isClosing else { return }
        closingContent = showsConnectionProgress ? .progress : .login
        sheet = nil; loginAttempt = nil
    }
    private func refreshControlsAfterDismissal() {
        session.finishControlsCustomization?(); controlsContextImage = nil
        guard controlsReloadPending else { return }
        controlsReloadPending = false; session.reloadKeyboard?()
    }
    private func closeSession() {
        guard !isClosing else { return }
        retirePresentation()
        session.stop(); exit()
    }
    private func returnAfterNormalExit() {
        guard session.completedNormally, DirectAppLockV1.shared.canAccess, UIApplication.shared.applicationState == .active else { return }
        closeSession()
    }
    private func setupKey() {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            guard !isClosing else { return }
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
        if notice.reason == .keyRejected { return .init(title: "Use Password", symbol: "person.badge.key") { selectLoginMethod(.password) } }
        return nil
    }
    var body: some View {
        NavigationStack {
            ZStack {
                (session.connected ? terminalBackground : connectionPanel == nil ? Color(uiColor: .systemGroupedBackground) : Color.clear).ignoresSafeArea()
                TerminalSurface(session: session, style: appearance.terminal.style(app: appearance.app), customize: { sheet = .keyboard }, contextImage: { controlsContextImage = $0 }, filesStatus: files.transferActive ? files.activityTitle : "", action: handleControls)
                    .ignoresSafeArea(.container, edges: session.connected ? .top : [])
                    .opacity(session.connected ? 1 : 0).allowsHitTesting(session.connected).accessibilityHidden(!session.connected)
                if !isClosing && !session.macRemoved && !session.connected && !session.completedNormally {
                    if let connectionPanel {
                        DirectConnectionPanelContent(host: connectionPanel, cancel: closeSession, preferredHeight: showsConnectionProgress ? nativeProgressHeight : nativeFormHeight + nativeFooterHeight, preventsDismissal: showsConnectionProgress) {
                            nativeLoginContent
                                .sheet(item: $sheet, onDismiss: refreshControlsAfterDismissal) { destination in secondarySheet(destination) }
                        }
                    } else {
                        DirectConnectionBackdrop(names: macLibrary?.macs.map(\.name) ?? [mac.name])
                        loginView
                    }
                }
                else if let notice = session.textSendNotice {
                    VStack { Spacer(); DirectRecoveryCard(notice: notice,
                        primary: .init(title: "Continue", perform: { session.textSendNotice = nil }), secondary: nil).padding(12); Spacer() }
                }
                else if let notice = session.controlsRecovery {
                    VStack { DirectRecoveryCard(notice: notice,
                        primary: .init(title: "Keyboard Settings", perform: { sheet = .keyboard }),
                        secondary: .init(title: "Use Standard Controls", perform: { session.controlsRecovery = nil })).padding(12); Spacer() }
                }
                if session.macRemoved, files.hasUnsavedDownloads {
                    DirectFilesView(mac: mac, session: files, closeOwnerWindow: closeSession)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: Binding(get: { connectionPanel != nil && !session.connected ? nil : sheet }, set: { sheet = $0 }), onDismiss: { refreshControlsAfterDismissal(); if let updated = macLibrary?.macs.first(where: { $0.id == mac.id }) { session.updateMac(updated) } }) { destination in
                secondarySheet(destination)
            }
            .sheet(item: Binding(get: { connectionPanel == nil ? session.trust : nil }, set: { session.trust = $0 })) { request in
                TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust)
            }
        }
        // Keep the mounted session owner, but let the real Mac list show through
        // while its login/progress content lives in the native sheet. Removed-Mac
        // downloads stay visible in this owner until they are saved or discarded.
        .opacity(connectionPanel != nil && !session.connected && !session.macRemoved ? 0 : 1)
        // The native terminal owns keyboard avoidance through its layout guide.
        // Keep SwiftUI from shrinking the same connected surface a second time;
        // the sign-in card still uses SwiftUI's normal keyboard avoidance.
        .ignoresSafeArea(.keyboard, edges: session.connected ? .bottom : [])
        .preferredColorScheme(session.connected ? terminalScheme : appearance.app.colorScheme)
        .onAppear {
            guard !isClosing, !loadedLogin else { return }
            loadLogin(); loadedLogin = true
            if autoConnect && loginIssue == nil && session.recovery == nil { connect() }
        }
        .confirmationDialog("End this session?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { CompanionVNCPlayInterfaceFeedback("end"); closeSession() }
            Button("Keep Session", role: .cancel) {}
        } message: { Text("The active file transfer will be interrupted. Completed downloads are kept in Files.") }
        .onDisappear { retirePresentation(); if let context = session.filesContext { files.disconnectBorrowed(context.generation) }; session.stop() }
        .onChange(of: session.connected) { _, connected in
            if connected {
                draft.authenticationSucceeded(loginAttempt, retention: remember && !useKey ? .saved : .notRequested)
                loginAttempt = nil
            } else { draft.passwordSessionEnded(); loadLogin() }
        }
        .onChange(of: session.trust?.id) { _, _ in updateNativeTrust() }
        .onChange(of: session.completedNormally) { _, _ in returnAfterNormalExit() }
        .onChange(of: session.macRemoved) { _, removed in
            if removed { sheet = nil; draft.invalidate(); key = nil; if !files.hasUnsavedDownloads { closeSession() } }
        }
        .onChange(of: files.shouldCloseAfterRemoval) { _, close in if close { closeSession() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.becameInactive() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in draft.suspend(); session.background() }
        .onReceive(NotificationCenter.default.publisher(for: DirectAppLockV1.locked)) { _ in draft.suspend(); session.background() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in draft.resume(); returnAfterNormalExit(); session.foreground(); loadLogin() }
        .onReceive(NotificationCenter.default.publisher(for: DirectAppLockV1.unlocked)) { _ in draft.resume(); returnAfterNormalExit(); session.foreground(); loadLogin() }
        .onReceive(NotificationCenter.default.publisher(for: VNCSessionPreferences.actionsChanged)) { _ in session.reloadKeyboard?() }
        .onReceive(NotificationCenter.default.publisher(for: TerminalControlsStore.changed)) { _ in
            if sheet == .keyboard || sheet == .quickActions || sheet == .savedTextLibrary { controlsReloadPending = true } else { session.reloadKeyboard?() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in session.activity?.preferenceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: RemoteSessionActivityActions.endRequested)) { notification in
            if let id = notification.object as? String, session.endActivity(id) { closeSession() }
        }
    }
    @State private var nativeTrustController: UIViewController?
    private func updateNativeTrust() {
        guard !isClosing, let connectionPanel else { return }
        if let request = session.trust {
            let controller = UIHostingController(rootView: TerminalServerTrustView(macName: mac.name, fingerprint: request.fingerprint, answer: session.answerTrust).directAppearance())
            nativeTrustController = controller; connectionPanel.showTrust(controller)
        } else if let controller = nativeTrustController {
            connectionPanel.finishTrust(controller); nativeTrustController = nil
        }
    }
    @ViewBuilder private func secondarySheet(_ destination: Sheet) -> some View {
                switch destination {
                case .files: DirectFilesView(mac: mac, session: files, retainWhenDismissed: true).usingConnection { session.filesContext }
                case .keys, .access: DirectMacAccessView(mac: mac, saved: { loadLogin(reload: true) }).onDisappear { loadLogin() }
                case .install: TerminalKeyInstallView(mac: mac, initialUsername: username, changed: { loadKey(preferSelected: true); session.clearRecovery() })
                case .manual: TerminalManualKeySetupView(mac: mac)
                case .macSettings:
                    if let macLibrary { DirectMacEditorV1(mac: mac, library: macLibrary) }
                    else { TerminalConnectionInfo(mac: mac) }
                case .appSettings: DirectSessionSettingsV1()
                case .pro: DirectProView()
                case .quickActions: TerminalControlsSettings(initialLibrary: .shortcuts, contextImage: controlsContextImage, close: { sheet = nil })
                case .savedTextLibrary: TerminalControlsSettings(initialLibrary: .text, contextImage: controlsContextImage, close: { sheet = nil })
                case .keyboard: TerminalControlsSettings(contextImage: controlsContextImage, close: { sheet = nil })
                case .verifyGuide: TerminalIdentityGuide(macName: mac.name)
                case .connectionInfo: TerminalConnectionInfo(mac: mac)
                }
    }
    @ViewBuilder private var nativeLoginContent: some View {
        if showsConnectionProgress {
            DirectConnectionProgress(name: mac.name, service: "Terminal", symbol: "terminal", progress: session.connectionProgress, addresses: mac.addresses, sshPort: mac.sshPort, cancel: closeSession, contentHeightChanged: { if showsConnectionProgress { nativeProgressHeight = $0 } })
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    DirectConnectionIdentity(name: mac.name, service: "Terminal", symbol: "terminal")
                    loginForm(compact: false, includesActions: false)
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                    .frame(maxWidth: 520).frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { nativeFormHeight = $0 }
            }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let notice = resumableRecovery {
                            let action = recoveryAction(notice)
                            connectionButton(action.title, symbol: action.symbol, perform: action.perform)
                        } else { formActions(notice: loginIssue ?? session.recovery) }
                        Button("Cancel", action: closeSession)
                            .font(.headline).foregroundStyle(.blue).buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 48).accessibilityIdentifier("terminal-login-cancel")
                    }.padding(.horizontal, 24).padding(.vertical, 4).frame(maxWidth: 520).frame(maxWidth: .infinity)
                        .background(Color(uiColor: DirectConnectionStyle.panel))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { nativeFooterHeight = $0 }
                }.background(Color(uiColor: DirectConnectionStyle.panel)).directAppearance()
        }
    }
    private func handleControls(_ action: String) {
        switch action {
        case "files": sheet = .files
        case "connectionInfo": sheet = .connectionInfo
        case "appSettings": sheet = .appSettings
        case "macSettings": sheet = .macSettings
        case "keys": sheet = .keys
        case "install": setupKey()
        case "manual": sheet = .manual
        case "quickActions": sheet = .quickActions
        case "savedTextLibrary": sheet = .savedTextLibrary
        case "customize": sheet = .keyboard
        case "pro": sheet = .pro
        case "exit":
            if files.isBorrowed && files.transferActive { confirmingExit = true }
            else { if session.connected { CompanionVNCPlayInterfaceFeedback("end") }; closeSession() }
        default: break
        }
    }
    private var loginView: some View {
        GeometryReader { geometry in
            let compact = TerminalPresentationLayout.compactLogin(size: geometry.size, accessibility: dynamicType.isAccessibilitySize)
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: compact ? 14 : 22) {
                        DirectConnectionIdentity(name: mac.name, service: "Terminal", symbol: "terminal", compact: compact,
                            cancel: session.connecting ? nil : { closeSession() })
                        loginForm(compact: compact)
                    }.padding(compact ? 16 : 22)
                        .directConnectionCardSurface()
                        .frame(maxWidth: compact ? 720 : 440)
                }.frame(minHeight: max(0, geometry.size.height - 20), alignment: .center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10)
            }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
        }
    }
    private var resumableRecovery: DirectRecoveryNotice? {
        guard let notice = session.recovery, loginIssue == nil,
              [.terminalEnded, .inputPaused, .terminalConnection, .addressNotFound, .macUnreachable].contains(notice.reason), canConnect else { return nil }
        return notice
    }
    private func loginForm(compact: Bool, includesActions: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            if session.connecting {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.regular)
                    Text("Connecting…")
                        .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("terminal-status")
                }.frame(maxWidth: .infinity, minHeight: compact ? 84 : 124)
                Button(action: closeSession) {
                    Text("Cancel").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.plain).frame(minHeight: 48)
                    .tint(.blue).accessibilityIdentifier("terminal-login-cancel")
            } else if let notice = resumableRecovery {
                DirectConnectionNotice(notice: notice)
                let action = recoveryAction(notice)
                if includesActions { connectionButton(action.title, symbol: action.symbol, perform: action.perform) }
                detailsButton(notice: notice)
            } else {
                if !autoConnect && session.recovery == nil && loginIssue == nil {
                    Text("The previous Terminal session is unavailable in this app. Connect to open a new shell.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("terminal-previous-session-unavailable")
                }
                let authentication = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                authentication {
                    Text("Mac account").foregroundStyle(.secondary)
                    if !dynamicType.isAccessibilitySize { Spacer() }
                    Menu {
                        Button("Password") { selectLoginMethod(.password) }
                        Button("SSH Key") { selectLoginMethod(.sshKey) }
                        Divider()
                        Button("Saved Login Settings") { sheet = .access }
                    } label: {
                        HStack(spacing: 6) {
                            Text(useKey ? "SSH Key" : "Password")
                            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44)
                    }.disabled(DirectMacConnections.shared.isActive(mac.id))
                        .accessibilityLabel("Sign-in method").accessibilityValue(useKey ? "SSH Key" : "Password")
                        .accessibilityIdentifier("terminal-login-access")
                }.font(.subheadline)
                let notice = loginIssue ?? session.recovery
                if let notice { DirectConnectionNotice(notice: notice) }
                VStack(spacing: 0) {
                    accountField
                    if !useKey {
                        Divider().padding(.leading, 14)
                        passwordField
                    }
                }.disabled(DirectMacConnections.shared.isActive(mac.id))
                    .background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 12))
                if useKey {
                    selectedKeyView
                } else if loginRetentionAllowed { Toggle("Save Login", isOn: Binding(get: { remember }, set: { remember = $0 })).font(.subheadline).padding(.horizontal, 2).disabled(DirectMacConnections.shared.isActive(mac.id)) }
                if includesActions { formActions(notice: notice) }
                detailsButton(notice: notice)
            }
        }
    }
    @ViewBuilder private func formActions(notice: DirectRecoveryNotice?) -> some View {
        if let notice {
            let action = loginIssue != nil ? DirectRecoveryAction(title: "Retry", perform: { loadLogin() }) : recoveryAction(notice)
            connectionButton(action.title, symbol: action.symbol, enabled: ![.loginRejected, .terminalEnded, .inputPaused].contains(notice.reason) || canConnect, perform: action.perform)
            if let secondary = secondaryAction(notice) {
                Button(secondary.title, action: secondary.perform).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44)
            }
        } else { connectionButton("Connect", enabled: canConnect, perform: connect) }
    }
    private func detailsButton(notice: DirectRecoveryNotice?) -> some View {
        DirectConnectionDisclosure(isExpanded: $detailsExpanded, identifier: "terminal-login-details") {
            DirectConnectionDetailsRows(mac: mac, desktop: false).padding(.top, 8)
            if let notice, !notice.details.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Issue Details").font(.subheadline.weight(.semibold))
                ForEach(Array(notice.details.enumerated()), id: \.offset) { offset, detail in
                    LabeledContent(detail.name, value: detail.value)
                        .accessibilityIdentifier("terminal-issue-detail-\(offset)")
                }
            }
        }
    }
    private func connectionButton(_ title: String, symbol: String? = nil, enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                if let symbol { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(enabled ? Color.white : Color.secondary).background(enabled ? Color.blue : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier("terminal-connect")
    }
    private var accountField: some View {
        DirectCredentialRow {
            DirectConnectionCredentialField(text: Binding(get: { username }, set: { username = $0; session.clearRecovery() }), secure: false, title: "Username", returnKey: .default, identifier: "terminal-login-username") {}.privacySensitive()
        }
    }
    private var passwordField: some View {
        DirectCredentialRow {
            HStack(spacing: 4) {
                DirectConnectionCredentialField(text: Binding(get: { password }, set: { password = $0; session.clearRecovery() }), secure: !passwordVisible, submit: connect).privacySensitive().frame(minHeight: 44)
                Button { passwordVisible.toggle() } label: { Image(systemName: passwordVisible ? "eye.slash" : "eye").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(passwordVisible ? "Hide Password" : "Show Password")
            }
        }
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

private struct TerminalSurface: UIViewControllerRepresentable {
    let session: DirectTerminalSession
    let style: UIUserInterfaceStyle
    let customize: @MainActor () -> Void
    let contextImage: @MainActor (UIImage) -> Void
    var filesStatus = ""
    let action: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> TerminalController {
        let controller = TerminalController(session: session, customize: customize, action: action)
        controller.customizationContext = contextImage
        return controller
    }
    func updateUIViewController(_ controller: TerminalController, context: Context) {
        controller.filesStatus = filesStatus
        controller.terminal.isUserInteractionEnabled = session.connected
        if !session.connected { _ = controller.terminal.resignFirstResponder() }
        controller.updateControls()
        controller.applyAppearance(style)
    }
    static func dismantleUIViewController(_ controller: TerminalController, coordinator: ()) { controller.textComposer.invalidate(); controller.session.received = nil; controller.session.prepareTerminal = nil; controller.session.toggleKeyboard = nil; controller.session.reloadKeyboard = nil; controller.session.suspendInput = nil; controller.session.finishControlsCustomization = nil }
}

@MainActor final class SessionTerminalView: TerminalView {
    var focusChanged: ((Bool) -> Void)?
    var keyboardState = TerminalKeyboardState()
    weak var keyboardBar: TerminalKeyboardBar?
    private var deletingModifiers: TerminalModifiers?
    private var deletionEncoded = false
    var customInputEpoch: () -> UUID? = { nil }
    var inputReserved: () -> Bool = { false }
    // Track physical presses, not HID codes: a rejected press must never gain
    // a release endpoint just because shortcut ownership has since ended.
    private let admittedHardwarePresses = NSHashTable<UIPress>(options: [.weakMemory, .objectPointerPersonality])
    var admitCustomInput: ([UInt8]) -> Bool = { _ in false }
    var admitCustomSequence: ([[UInt8]], @escaping @MainActor () -> Bool, @escaping @MainActor (Int) -> Void, @escaping @MainActor (String?) -> Void) -> Bool = { _, _, _, complete in
        complete("The input owner is unavailable. Nothing was queued."); return false
    }
    var admitCustomPlan: ([TerminalSequenceOperation<Int>], @escaping @MainActor (Int) -> [UInt8]?, @escaping @MainActor () -> Bool, @escaping @MainActor (Int) -> Void, @escaping @MainActor (String?) -> Void) -> Bool = { _, _, _, _, complete in
        complete("The input owner is unavailable. Nothing was queued."); return false
    }
    var cancelCustomPlan: (UUID) -> Void = { _ in }
    private var customInputBytes: [UInt8]?
    private var modifiedText: [UInt8]?
    private var modifiedTextEncoded = false
    var keyEncoding: TerminalKeyEncoding {
        .init(flags: getTerminal().keyboardEnhancementFlags, applicationCursor: getTerminal().applicationCursor,
              backspaceSendsControlH: backspaceSendsControlH)
    }
    func sendKey(_ key: TerminalKeyInput, modifiers: TerminalModifiers = []) {
        send(data: keyEncoding.bytes(key, modifiers: modifiers)[...])
    }
    func sendShortcut(_ action: VNCQuickAction) {
        resetModifiers(); send(data: action.terminalBytes(encoding: keyEncoding)[...])
    }
    func retireInput() {
        // Detach the delegate first: native responder/composition cleanup must
        // never write to the replacement shell, even through a delayed callback.
        terminalDelegate = nil; focusChanged = nil
        admittedHardwarePresses.removeAllObjects()
        customInputEpoch = { nil }; admitCustomInput = { _ in false }; admitCustomSequence = { _, _, _, complete in complete("The input owner retired."); return false }; customInputBytes = nil
        admitCustomPlan = { _, _, _, _, complete in complete("The input owner retired."); return false }; cancelCustomPlan = { _ in }
        _ = resignFirstResponder()
        resetModifiers(); clearSelection()
        setMarkedText("", selectedRange: NSRange(location: 0, length: 0)); unmarkText()
        super.insertText("\n")
    }
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
    override func copy(_ sender: Any?) {
        guard let selected = getSelection(), !selected.isEmpty else { return }
        let previous = UIPasteboard.general.changeCount
        super.copy(sender)
        if UIPasteboard.general.changeCount != previous { keyboardBar?.keyFeedback.feedback("success") }
    }
    /// Buffer one explicit accessory action so its encoded bytes are admitted
    /// together. Ordinary system typing keeps the existing delegate path.
    @discardableResult func performCustomInput(feedbackKind: String? = "key", ignoringFramingBytes: Int = 0, _ action: () -> Void) -> Bool {
        guard !inputReserved(), customInputBytes == nil, let epoch = customInputEpoch() else { return false }
        customInputBytes = []
        action()
        let bytes = customInputBytes ?? []
        customInputBytes = nil
        guard bytes.count > ignoringFramingBytes, customInputEpoch() == epoch, admitCustomInput(bytes) else { return false }
        if let feedbackKind { keyboardBar?.keyFeedback.feedback(feedbackKind) }
        return true
    }
    func pasteWithFeedback(feedbackKind: String? = "key") {
        // Retain SwiftTerm's single clipboard read and selection bookkeeping.
        let framing = getTerminal().bracketedPasteMode ? "\u{1b}[200~\u{1b}[201~".utf8.count : 0
        if performCustomInput(feedbackKind: feedbackKind, ignoringFramingBytes: framing, { super.paste(nil) }) { resetModifiers() }
    }
    func resetModifiers() { keyboardState.reset(); controlModifier = false; metaModifier = false; keyboardBar?.refresh() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Hardware keys own their real modifier/repeat/release metadata. Do not
        // replace their later UITextInput commit with a discrete software key.
        let available = !inputReserved() && customInputEpoch() != nil
        let accepted = Set(presses.filter { $0.key == nil || available })
        for press in accepted where press.key != nil { admittedHardwarePresses.add(press) }
        if accepted.contains(where: { $0.key != nil }) { resetModifiers() }
        if !accepted.isEmpty { super.pressesBegan(accepted, with: event) }
    }
    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let accepted = Set(presses.filter { $0.key == nil || admittedHardwarePresses.contains($0) })
        if !accepted.isEmpty { super.pressesChanged(accepted, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let accepted = takeAdmittedPresses(presses)
        // SwiftTerm's release handler also cancels its global repeat timer.
        // Even an otherwise harmless rejected key-up must not reach it.
        if !accepted.isEmpty { super.pressesEnded(accepted, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let accepted = takeAdmittedPresses(presses)
        let hardware = Set(accepted.filter { $0.key != nil })
        let other = accepted.subtracting(hardware)
        // UIKit cancellation must retire SwiftTerm's repeat and modifier state
        // just as a normal release does. Repeated endpoints are ignored.
        if !hardware.isEmpty { super.pressesEnded(hardware, with: event) }
        if !other.isEmpty { super.pressesCancelled(other, with: event) }
    }
    private func takeAdmittedPresses(_ presses: Set<UIPress>) -> Set<UIPress> {
        Set(presses.filter { press in
            guard press.key != nil else { return true }
            guard admittedHardwarePresses.contains(press) else { return false }
            admittedHardwarePresses.remove(press)
            return true
        })
    }
    override func insertText(_ text: String) {
        guard !inputReserved() else { return }
        let modifiers = keyboardState.consume()
        if markedTextRange != nil || text.unicodeScalars.count != 1 || !text.unicodeScalars.allSatisfy({ $0.isASCII }) {
            // IME, dictation and native normalization can emit several edits.
            // Preserve those emissions rather than replacing the first one.
            controlModifier = false; metaModifier = false
            super.insertText(text); keyboardBar?.refresh()
            return
        }
        modifiedText = modifiers.isEmpty ? nil : keyEncoding.bytes(text == "\n" || text == "\r" ? .enter : .text(text), modifiers: modifiers)
        modifiedTextEncoded = false
        defer { modifiedText = nil; modifiedTextEncoded = false; keyboardBar?.refresh() }
        // Keep the frontend's native range/composition bookkeeping, replacing
        // only the outbound bytes for explicit software modifiers.
        super.insertText(modifiers.contains(.shift) ? TerminalKeyboardState.shifted(text) : text)
    }
    override func deleteBackward() {
        guard !inputReserved() else { return }
        let modifiers = keyboardState.consume()
        let ordinary = modifiers.isEmpty || (modifiers == .shift && getTerminal().keyboardEnhancementFlags.isEmpty)
        deletingModifiers = ordinary || markedTextRange != nil ? nil : modifiers
        deletionEncoded = false
        defer { deletingModifiers = nil; deletionEncoded = false; keyboardBar?.refresh() }
        // Keep SwiftTerm's UITextInput/IME bookkeeping; transform only its outbound deletion.
        super.deleteBackward()
    }
    func encodeOutput(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let encoded = encodeKeyboardOutput(bytes)
        if customInputBytes != nil {
            // One extra byte preserves the existing explicit oversized-input
            // failure while bounding this temporary accessory-action buffer.
            let room = DirectTerminalSession.maximumQueuedInputBytes + 1 - customInputBytes!.count
            if room > 0 { customInputBytes! += encoded.prefix(room) }
            return []
        }
        return encoded
    }
    private func encodeKeyboardOutput(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        if let modifiedText {
            guard !modifiedTextEncoded else { return [] }; modifiedTextEncoded = true
            return modifiedText
        }
        guard let deletingModifiers else { return Array(bytes) }
        // Native range deletion may emit several backspaces for one logical keypress.
        guard !deletionEncoded else { return [] }; deletionEncoded = true
        return keyEncoding.bytes(.backspace, modifiers: deletingModifiers)
    }
    override func becomeFirstResponder() -> Bool {
        guard !inputReserved() else { return false }
        let result = super.becomeFirstResponder(); if result { focusChanged?(true) }; return result
    }
    override func resignFirstResponder() -> Bool {
        resetModifiers(); let result = super.resignFirstResponder(); if result { focusChanged?(false) }; return result
    }
}

@MainActor class TerminalController: UIViewController, @preconcurrency TerminalViewDelegate {
    var filesStatus = ""
    let session: DirectTerminalSession
    private(set) var terminal = SessionTerminalView(frame: .zero)
    let controls = CompanionVNCControls()
    lazy var textComposer: DirectTextComposer = {
        let composer = DirectTextComposer(macName: session.mac.name, mode: "terminal")
        composer.interruptionHandler = { [weak session] in session?.interruptComposedText() }
        composer.presentationChanged = { [weak self] visible in
            guard let self else { return }
            self.composerVisible = visible
            self.updateKeyboardBarVisibility(); self.view.setNeedsLayout()
        }
        return composer
    }()
    lazy var keyboardBar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
    private var reportedGrid: (columns: Int, rows: Int)?
    private var composerVisible = false
    private var paletteIsDark: Bool?
    private(set) var preparedGeneration: UUID?
    private var resettingPTY = false
    private(set) var controlProfile = TerminalControlsProfile.defaults
    private var inputPanel: UIViewController?
    private var keypadState: TerminalKeypadState?
    private var savingControls = false
    private var appliedInputEpoch: UUID?
    private var normalBottom: NSLayoutConstraint!
    private var foldedBottom: NSLayoutConstraint!
    private var barLeading: NSLayoutConstraint!, barTrailing: NSLayoutConstraint!
    private var terminalLeading: NSLayoutConstraint!, terminalTrailing: NSLayoutConstraint!
    private let customize: @MainActor () -> Void
    private let action: @MainActor (String) -> Void
    private let defaults: UserDefaults
    private let controlsStore: TerminalControlsStore
    var customizationContext: ((UIImage) -> Void)?
    private var customizingControls = false
    private var customizationEpoch: UUID?
    private var customizationKeyboard = false
    private var controlsInputEpoch = UUID()
    private var observedSessionInputEpoch: UUID?
    private var feedingRemoteOutput = false
    private var shortcutConfirmations = TerminalShortcutConfirmations()
    init(session: DirectTerminalSession, customize: @escaping @MainActor () -> Void, action: @escaping @MainActor (String) -> Void = { _ in }, defaults: UserDefaults = .standard, controlsStore: TerminalControlsStore = .init()) {
        self.session = session; self.customize = customize; self.action = action; self.defaults = defaults
        self.controlsStore = controlsStore
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { paletteIsDark == true ? .lightContent : .darkContent }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        installTerminalSurface()
        controls.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(controls)
        NSLayoutConstraint.activate([controls.topAnchor.constraint(equalTo: view.topAnchor), controls.bottomAnchor.constraint(equalTo: view.bottomAnchor), controls.leadingAnchor.constraint(equalTo: view.leadingAnchor), controls.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        controls.buttonAnchorView = keyboardBar.menuAnchor
        controls.button.accessibilityLabel = "Terminal Controls"
        controls.button.accessibilityIdentifier = "terminal-controls"
        controls.categoryActions = TerminalControlNavigation.items
        controls.actionHandler = { [weak self] item in self?.performQuickAction(item) }
        controls.openingHandler = { [weak self] in self?.updateControls() }
        CompanionVNCObserveDivision(view)
        session.prepareTerminal = { [weak self] generation in self?.prepareForPTY(generation) }
        session.received = { [weak self] bytes in
            guard let self, session.connected else { return }
            prepareForPTY(session.outputGeneration)
            let supportedCommand = terminal.keyEncoding.supportsCommand
            feedingRemoteOutput = true
            terminal.feed(byteArray: bytes[...])
            feedingRemoteOutput = false
            if supportedCommand != terminal.keyEncoding.supportsCommand {
                keyboardBar.refresh()
                keypadState?.supportsCommand = terminal.keyEncoding.supportsCommand
                keypadState?.armed = terminal.keyboardState.armed
                keypadState?.locked = terminal.keyboardState.locked
            }
            if bytes.isEmpty { updateControls() } // A completed resume delivers an empty refresh.
        }
        if session.connected { prepareForPTY(session.outputGeneration) }
        configureKeyboard()
        session.reloadKeyboard = { [weak self] in self?.configureKeyboard(); self?.updateControls() }
        session.finishControlsCustomization = { [weak self] in self?.finishCustomization() }
        session.suspendInput = { [weak self] in
            guard let self else { return }
            if textComposer.sending { session.interruptComposedText() }
            textComposer.invalidate(); terminal.resetModifiers(); controls.cancelSlideForLayoutChange(); controls.close()
            keypadState?.ready = false
            if let sequenceReview, presentedViewController === sequenceReview { dismiss(animated: false); self.sequenceReview = nil }
            runningShortcut?.close(restoreKeyboard: false); runningShortcut = nil
            if let navigation = presentedViewController as? UINavigationController, navigation.topViewController is CompanionVNCMenu { dismiss(animated: false) }
            if let inputPanel, presentedViewController === inputPanel { dismiss(animated: false); self.inputPanel = nil }
        }
        session.toggleKeyboard = { [weak self] in
            guard let self else { return }
            if terminal.isFirstResponder { _ = terminal.resignFirstResponder() }
            else { _ = terminal.becomeFirstResponder() }
        }
        updatePalette()
        updateControls()
    }
    private func installTerminalSurface() {
        terminal.customInputEpoch = { [weak self] in self?.currentControlsInputEpoch() }
        terminal.admitCustomInput = { [weak self] bytes in guard let self, !customizingControls else { return false }; return session.trySend(bytes) }
        terminal.admitCustomSequence = { [weak self] packets, valid, progress, complete in
            guard let self, !customizingControls, let epoch = session.customInputEpoch else { complete("The session input owner changed."); return false }
            return session.sendSequence(packets, epoch: epoch, stillValid: valid, progress: progress, completion: complete)
        }
        terminal.admitCustomPlan = { [weak self] operations, resolve, valid, progress, complete in
            guard let self, !customizingControls, let epoch = session.customInputEpoch else { complete("The session input owner changed."); return false }
            return session.sendSequencePlan(operations, epoch: epoch, resolve: resolve, stillValid: valid, progress: progress, completion: complete)
        }
        terminal.inputReserved = { [weak session] in session?.isSendingCustomSequence == true }
        terminal.cancelCustomPlan = { [weak self] epoch in
            guard let self, terminal.customInputEpoch() == epoch, let sessionEpoch = session.customInputEpoch else { return }
            session.cancelSequence(epoch: sessionEpoch)
        }
        terminal.accessibilityIdentifier = "terminal-surface"
        terminal.terminalDelegate = self; terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        // The persistent toolbar owns the only bottom control space. No
        // additional row is reserved for the shared menu button.
        view.addSubview(keyboardBar)
        terminal.keyboardBar = keyboardBar
        terminal.inputAccessoryView = nil
        keyboardBar.openKeypad = { [weak self] numbersFirst in self?.showKeypad(numbersFirst: numbersFirst) }
        keyboardBar.layoutChanged = { [weak self] in self?.persistBarLayout(); self?.view.setNeedsLayout() }
        textComposer.shortcutBar = keyboardBar
        barLeading = keyboardBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        barTrailing = keyboardBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        terminalLeading = terminal.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        terminalTrailing = terminal.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            keyboardBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            barLeading, barTrailing
        ])
        normalBottom = terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -keyboardBar.height)
        foldedBottom = terminal.bottomAnchor.constraint(equalTo: view.topAnchor)
        terminal.contentInsetAdjustmentBehavior = .never
        terminal.clipsToBounds = true
        setContentScrollView(terminal, for: .top)
        if #available(iOS 26, *) { terminal.topEdgeEffect.style = .automatic }
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.topAnchor), normalBottom, terminalLeading, terminalTrailing])
        terminal.focusChanged = { [weak self, weak session] visible in
            if self?.executionKeyboardChange != true { session?.keyboardVisible = visible }
            self?.updateControls(); self?.view.setNeedsLayout()
        }
        keyboardBar.toggleKeyboard = { [weak session] in session?.toggleKeyboard?() }
        terminal.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TerminalView, _: UITraitCollection) in self?.updatePalette() }
    }
    func updateControls() {
        keyboardBar.refresh()
        controls.isHidden = !session.connected
        updateKeyboardBarVisibility()
        keyboardBar.setKeyboardFocused(terminal.isFirstResponder)
        if !session.connected { controls.close() }
        controls.macName = session.mac.name
        controls.quickActions = DirectProAccess.shared.hasPro
            ? controlProfile.resolvedMenuPlacements.compactMap { placement in
                guard let item = controlProfile.actions.first(where: { $0.id == placement.actionID }) else { return nil }
                var native = item.native
                native["id"] = placement.id.uuidString
                native["definitionID"] = item.id.uuidString
                if item.operation == .keyboard { native["title"] = terminal.isFirstResponder ? "Hide Keyboard" : "Show Keyboard" }
                if item.operation == .expandRows { native["title"] = keyboardBar.showsExtraRows ? "Collapse Rows" : "Expand Rows" }
                return inputItem(native)
            }
            : DirectControlMode.terminal.defaults.map { inputItem($0.native) }
    }
    private func inputItem(_ item: [String: Any]) -> [String: Any] {
        var item = item
        if item["requiresCommand"] as? Bool == true && !terminal.keyEncoding.supportsCommand {
            item["disabled"] = true
        }
        item["inputEpoch"] = terminal.customInputEpoch()?.uuidString ?? "unavailable"
        if item["kind"] as? String == "terminalAction" { item["controlsRevision"] = controlProfile.revision.uuidString }
        return item
    }
    func performControlAction(_ id: UUID, feedback: String? = nil, feedbackHandled: Bool = false) {
        guard DirectProAccess.shared.hasPro, DirectAppLockV1.shared.canAccess,
              let item = controlProfile.actions.first(where: { $0.id == id }), item.valid else { return }
        guard !item.requiresCommand || terminal.keyEncoding.supportsCommand else { return }
        guard runningShortcut == nil else { return }
        switch item.kind {
        case .builtIn: performControl(item.operation?.rawValue ?? item.builtIn?.rawValue ?? "", feedbackHandled: feedbackHandled, inputFeedback: feedback)
        case .key:
            terminal.performCustomInput(feedbackKind: feedback) {
                if let key = item.key { terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume()) }
            }
        case .shortcut: runShortcut(item, feedback: feedback)
        case .text: reviewSavedText(item)
        }
        keyboardBar.refresh()
    }
    private var sequenceReview: UIViewController?
    private var runningShortcut: TerminalSequenceBannerController?
    private var executionKeyboardChange = false
    private func runShortcut(_ item: TerminalControlAction, feedback: String?) {
        guard runningShortcut == nil, let epoch = terminal.customInputEpoch() else { return }
        let schedule: [TerminalSequenceOperation<Int>]
        let packets: [[UInt8]]
        do {
            schedule = try item.terminalSchedule()
            packets = item.hasSequenceWait ? [] : try item.terminalSequence(encoding: terminal.keyEncoding, bracketedPaste: terminal.getTerminal().bracketedPasteMode)
        } catch {
            session.textSendNotice = .init(reason: .inputPaused, title: "Shortcut unavailable", message: "This shortcut is too large or contains an unsupported step. Nothing was sent.")
            return
        }
        let revision = controlProfile.revision
        let connectionID = session.outputGeneration.uuidString
        let keyboardEpoch = session.keyboardPresentationEpoch
        let send = { [weak self] in
            guard let self, terminal.customInputEpoch() == epoch,
                  controlProfile.revision == revision, DirectProAccess.shared.hasPro else { return }
            let progress = TerminalSequenceProgress(action: item)
            let keyboard = TerminalSequenceKeyboard(visible: { [weak self] in
                guard let self else { return false }
                return TerminalSequenceKeyboard.softwareVisible(in: view, responder: terminal)
            }, current: { [weak self] in
                guard let self else { return false }
                return session.outputGeneration.uuidString == connectionID && session.keyboardPresentationEpoch == keyboardEpoch && session.canSendUserInput
                    && TerminalSequenceKeyboard.presentationCurrent(in: self, responder: terminal)
            }, hide: { [weak self] in
                guard let self else { return false }
                executionKeyboardChange = true
                let modifiers = terminal.keyboardState
                defer { executionKeyboardChange = false; terminal.keyboardState = modifiers; keyboardBar.refresh() }
                return terminal.resignFirstResponder()
            }, restore: { [weak self] in
                guard let self else { return }
                executionKeyboardChange = true
                defer { executionKeyboardChange = false }
                _ = terminal.becomeFirstResponder()
            })
            let panel = TerminalSequenceBannerController(progress: progress, keyboard: keyboard, cancel: { [weak self] in
                guard let self, runningShortcut?.rootView.progress === progress else { return }
                progress.cancelled = true; terminal.cancelCustomPlan(epoch)
            })
            runningShortcut = panel; panel.attach(to: self, covering: keyboardBar, blocking: [controls])
            let current: @MainActor () -> Bool = { [weak self] in
                guard let self else { return false }
                return !progress.cancelled && terminal.customInputEpoch() == epoch && DirectProAccess.shared.hasPro
                    && controlProfile.actions.contains { $0.id == item.id && $0.sameDefinition(as: item) }
            }
            let completed: @MainActor (String?) -> Void = { [weak self, weak panel] message in
                guard let self, let panel, runningShortcut === panel else { return }
                panel.close(); runningShortcut = nil; keyboardBar.refresh()
                if let message, !progress.cancelled, terminal.customInputEpoch() == epoch {
                    session.textSendNotice = .init(reason: .inputPaused, title: "Shortcut stopped", message: message)
                }
            }
            let accepted: Bool
            if item.hasSequenceWait {
                accepted = terminal.admitCustomPlan(schedule, { [weak self] index in
                    guard let self, item.resolvedSteps.indices.contains(index) else { return nil }
                    return try? item.resolvedSteps[index].terminalBytes(encoding: terminal.keyEncoding, bracketedPaste: terminal.getTerminal().bracketedPasteMode)
                }, current, { progress.move(to: $0) }, completed)
            } else {
                // Keep the no-wait packet path, but reserve the same input owner.
                accepted = terminal.admitCustomSequence(packets, { [weak self] in
                    guard let self, current() else { return false }
                    return (try? item.terminalSequence(encoding: terminal.keyEncoding, bracketedPaste: terminal.getTerminal().bracketedPasteMode)) == packets
                }, { progress.move(to: $0) }, completed)
            }
            keyboardBar.refresh()
            if accepted, let feedback { keyboardBar.keyFeedback.feedback(feedback) }

        }
        guard shortcutConfirmations.requiresReview(item, connectionID: connectionID) else { send(); return }
        let modifiers = terminal.keyboardState, focused = terminal.isFirstResponder
        let restore = { [weak self] in
            guard let self, terminal.customInputEpoch() == epoch else { return }
            if focused { _ = terminal.becomeFirstResponder() }
            terminal.keyboardState = modifiers; keyboardBar.refresh()
        }
        let show = { [weak self] in
            guard let self, terminal.customInputEpoch() == epoch else { return }
            _ = terminal.resignFirstResponder(); terminal.keyboardState = modifiers; keyboardBar.refresh()
            let panel = UIHostingController(rootView: TerminalSequenceReview(action: item, send: { [weak self] skip in
                guard let self, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
                if skip { shortcutConfirmations.skip(item, connectionID: connectionID) }
                dismiss(animated: true) { [weak self] in self?.sequenceReview = nil; restore(); send() }
            }, cancel: { [weak self] in self?.dismiss(animated: true) { self?.sequenceReview = nil; restore() } }))
            sequenceReview = panel; panel.modalPresentationStyle = .pageSheet; present(panel, animated: true)
        }
        if presentedViewController != nil { dismiss(animated: true, completion: show) } else { show() }
    }
    private func reviewSavedText(_ item: TerminalControlAction) {
        guard let epoch = terminal.customInputEpoch() else { return }
        let revision = controlProfile.revision
        let review = { [weak self] in
            guard let self, DirectProAccess.shared.hasPro, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
            showTextComposer(initialText: item.text)
        }
        guard !textComposer.draft.text.isEmpty, textComposer.draft.text != item.text else { review(); return }
        let confirm = { [weak self] in
            guard let self, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
            let alert = UIAlertController(title: "Replace unsent draft?", message: "Your current draft has not been sent. Replace it with “" + item.title + "”?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep Draft", style: .cancel))
            alert.addAction(UIAlertAction(title: "Replace Draft", style: .destructive) { _ in review() })
            present(alert, animated: true)
        }
        if presentedViewController != nil { dismiss(animated: true, completion: confirm) } else { confirm() }
    }
    private func performQuickAction(_ item: [AnyHashable: Any]) {
        guard !customizingControls, session.connected, DirectAppLockV1.shared.canAccess else { return }
        if let epoch = item["inputEpoch"] as? String, epoch != terminal.customInputEpoch()?.uuidString { return }
        let kind = item["kind"] as? String ?? ""
        let inputFeedback: String? = item["inputFeedback"] as? Bool == true && item["interfaceFeedbackHandled"] as? Bool != true ? "commit" : nil
        if kind == "terminalAction", let value = item["id"] as? String, let id = UUID(uuidString: value) {
            guard item["controlsRevision"] as? String == controlProfile.revision.uuidString else { return }
            let definitionID: UUID
            if let value = item["definitionID"] as? String {
                guard let placement = controlProfile.resolvedMenuPlacements.first(where: { $0.id == id }), placement.actionID.uuidString == value else { return }
                definitionID = placement.actionID
            } else { definitionID = id }
            performControlAction(definitionID, feedback: inputFeedback, feedbackHandled: item["interfaceFeedbackHandled"] as? Bool == true)
        } else if kind == "shortcut" || kind == "text" {
            guard DirectProAccess.shared.hasPro,
                  let id = item["id"] as? String,
                  let saved = VNCSessionPreferences.actions(.terminal).first(where: { $0.id.uuidString == id && $0.enabled }),
                  saved.compatible(with: .terminal) else { return }
            terminal.performCustomInput(feedbackKind: inputFeedback) {
                terminal.resetModifiers()
                if saved.kind == .text {
                    let text = terminal.getTerminal().bracketedPasteMode ? "\u{1b}[200~" + saved.text + "\u{1b}[201~" : saved.text
                    terminal.send(data: Array(text.utf8)[...])
                } else {
                    terminal.sendShortcut(saved)
                }
            }
            terminal.keyboardBar?.refresh()
        } else { performControl(kind, feedbackHandled: item["interfaceFeedbackHandled"] as? Bool == true, inputFeedback: inputFeedback) }
    }
    private func performControl(_ kind: String, feedbackHandled: Bool = false, inputFeedback: String? = nil) {
        guard session.connected, runningShortcut == nil else { return }
        switch kind {
        case "moreKeys":
            showKeypad()
        case "savedText":
            showSavedItems(.text)
        case "savedShortcuts":
            showSavedItems(.shortcuts)
        case "customize": beginCustomization()
        case "shiftNext": keyboardBar.toggle(.shift)
        case "shiftLock": keyboardBar.toggle(.shift, lock: true)
        case "ctrlLock": keyboardBar.toggle(.ctrl, lock: true)
        case "altLock": keyboardBar.toggle(.alt, lock: true)
        case "copySelection": terminal.copy(nil)
        case "endInput", "suspendProcess":
            terminal.performCustomInput {
                terminal.resetModifiers()
                terminal.sendKey(.text(kind == "endInput" ? "d" : "z"), modifiers: .ctrl)
            }
            keyboardBar.refresh()
        case "appearance":
            let choices = DirectTerminalAppearance.allCases.map { value in
                ["kind": "colors-" + value.rawValue, "title": value.title, "symbol": "circle.lefthalf.filled", "selected": DirectAppearanceV1.shared.terminal == value] as [String: Any]
            }
            presentControlsMenu("Appearance", sections: [["title": "Terminal Colors", "items": choices]])
        case "session":
            presentControlsMenu(session.mac.name, sections: [
                ["title": "Keyboard Bar", "items": [
                    ["kind": "keyboard", "title": terminal.isFirstResponder ? "Hide Keyboard" : "Show Keyboard", "symbol": "keyboard"],
                    ["kind": "expandRows", "title": keyboardBar.showsExtraRows ? "Collapse Rows" : "Expand Rows", "symbol": "rectangle.expand.vertical"]]],
                ["title": "Session", "items": [
                    ["kind": "files", "title": filesStatus.isEmpty ? "Files" : "Files · " + filesStatus, "symbol": "folder", "submenu": true],
                    ["kind": "connectionInfo", "title": "Connection Details", "symbol": "info.circle"],
                    ["kind": "appSettings", "title": "App Settings", "symbol": "gearshape", "submenu": true]]],
                ["title": "", "items": [["kind": "exit", "title": "Disconnect", "symbol": "xmark.circle", "destructive": true]]]])
        case "connectionInfo":
            let message = ([session.mac.name, "SSH · Port \(session.mac.sshPort)"] + session.mac.addresses).joined(separator: "\n")
            let details = UIAlertController(title: "Connection Details", message: message, preferredStyle: .alert)
            details.overrideUserInterfaceStyle = paletteIsDark == true ? .dark : .light
            details.addAction(UIAlertAction(title: "Done", style: .cancel))
            present(details, animated: true)
        case "keyboard":
            let wasVisible = terminal.isFirstResponder
            session.toggleKeyboard?()
            if wasVisible != terminal.isFirstResponder && !feedbackHandled { keyboardBar.keyFeedback.feedback("selection") }
        case "expandRows":
            keyboardBar.showsExtraRows.toggle()
            if !feedbackHandled { keyboardBar.keyFeedback.feedback("selection") }
            persistBarLayout(); view.setNeedsLayout()
        case "paste": terminal.pasteWithFeedback(feedbackKind: inputFeedback)
        case "composeText": showTextComposer()
        case "escape", "tab", "returnKey":
            terminal.performCustomInput(feedbackKind: inputFeedback) {
                terminal.resetModifiers()
                terminal.sendKey(kind == "escape" ? .accessory(.escape) : kind == "tab" ? .accessory(.tab) : .enter)
            }
            terminal.keyboardBar?.refresh()
        case "interrupt":
            terminal.performCustomInput(feedbackKind: inputFeedback) {
                terminal.resetModifiers()
                terminal.sendKey(.text("c"), modifiers: .ctrl)
            }
            terminal.keyboardBar?.refresh()
        default:
            if kind.hasPrefix("terminalNumber-"), let number = kind.last, number.isNumber {
                terminal.performCustomInput { terminal.insertText(String(number)) }
                keyboardBar.refresh()
            } else if kind.hasPrefix("terminalKey-"), let key = TerminalAccessoryKey(rawValue: String(kind.dropFirst(12))) {
                terminal.performCustomInput { terminal.sendKey(.accessory(key), modifiers: terminal.keyboardState.consume()) }
                keyboardBar.refresh()
            } else if kind.hasPrefix("paletteKey-"), let key = TerminalKeyCatalog.key(String(kind.dropFirst(11))) {
                terminal.performCustomInput {
                    var modifiers = terminal.keyboardState.consume()
                    for value in key.modifiers {
                        if value == 0xffe3 { modifiers.insert(.ctrl) }
                        if value == 0xffe9 { modifiers.insert(.alt) }
                        if value == 0xffe1 { modifiers.insert(.shift) }
                    }
                    let input: TerminalKeyInput
                    if let accessory = key.accessory { input = .accessory(accessory) }
                    else if key.character == 0xff08 { input = .backspace }
                    else if key.character == 0xff0d { input = .enter }
                    else if key.character == 0xff09 { input = .accessory(.tab) }
                    else if let scalar = UnicodeScalar(key.character) { input = .text(String(scalar)) }
                    else { return }
                    terminal.sendKey(input, modifiers: modifiers)
                }; keyboardBar.refresh()
            } else if kind.hasPrefix("colors-"), let value = DirectTerminalAppearance(rawValue: String(kind.dropFirst(7))) {
                if DirectAppearanceV1.shared.terminal != value {
                    DirectAppearanceV1.shared.terminal = value
                    if !feedbackHandled { keyboardBar.keyFeedback.feedback("selection") }
                }
            } else { action(kind) }
        }
    }
    func showTextComposer(initialText: String? = nil) {
        guard session.canComposeText else { return }
        terminal.resetModifiers(); _ = terminal.resignFirstResponder(); controls.close()
        let generation = session.composeGeneration
        let present = { [weak self] in
            guard let self, session.composeGeneration == generation, session.canComposeText else { return }
            textComposer.present(from: self, available: { [weak session] in
                session?.composeGeneration == generation && session?.canComposeText == true
            }, send: { [weak self] text, complete in
                guard let self, let prepared = try? DirectComposedText(text, mode: .terminal) else {
                    complete("The Terminal session ended. Nothing was sent."); return
                }
                terminal.resetModifiers()
                session.sendComposedText(prepared.terminalBytes(bracketedPaste: terminal.getTerminal().bracketedPasteMode),
                                         generation: generation, completion: complete)
            })
            if let initialText { textComposer.draft.edit(initialText) }
        }
        if presentedViewController != nil { dismiss(animated: true, completion: present) }
        else { present() }
    }
    private func presentControlsMenu(_ title: String, sections: [[String: Any]]) {
        let menu = CompanionVNCMenu(); menu.title = title; menu.sections = sections
        bindMenu(menu)
        presentControlsMenu(menu)
    }
    private func bindMenu(_ menu: CompanionVNCMenu) {
        let epoch = terminal.customInputEpoch()
        let revision = controlProfile.revision
        menu.selectionHandler = { [weak self] item in
            guard let self else { return }
            let kind = item["kind"] as? String ?? ""
            let input = kind.hasPrefix("terminalKey-") || ["terminalAction", "shortcut", "text", "shiftNext", "shiftLock", "ctrlLock", "altLock", "copySelection", "paste", "escape", "tab", "returnKey", "interrupt", "endInput", "suspendProcess"].contains(kind)
            if input {
                guard let epoch, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
            }
            performQuickAction(item)
        }
    }
    func makeMoreKeysMenu() -> CompanionVNCMenu {
        let menu = CompanionVNCMenu(); menu.title = "More Keys"
        let keys = TerminalAccessoryKey.allCases.map { ["kind": "terminalKey-" + $0.rawValue, "title": $0.title, "symbol": "keyboard"] }
        menu.sections = [["title": "Modifiers & Clipboard", "items": [
            ["kind": "shiftNext", "title": "Shift for Next Key"], ["kind": "shiftLock", "title": "Lock/Unlock Shift"],
            ["kind": "ctrlLock", "title": "Lock/Unlock Ctrl"], ["kind": "altLock", "title": "Lock/Unlock Alt"],
            ["kind": "copySelection", "title": "Copy Selection"], ["kind": "paste", "title": "Paste"]]],
            ["title": "Shortcuts", "items": [
                ["kind": "interrupt", "title": "Interrupt · Ctrl-C"],
                ["kind": "endInput", "title": "End Input · Ctrl-D"],
                ["kind": "suspendProcess", "title": "Suspend · Ctrl-Z"]]],
            ["title": "Navigation & Function Keys", "items": keys]]
        bindMenu(menu); return menu
    }
    private func presentControlsMenu(_ menu: CompanionVNCMenu) {
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
    private func updateKeyboardBarVisibility() {
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let room = keyboardCeiling() - safe.minY - 16 - keyboardBar.height
        // The local editor needs its own text and 44-point actions. The remote
        // shortcut row can yield in a short landscape viewport and returns on close.
        let hidden = !session.connected || (composerVisible && room < 112)
        keyboardBar.isHidden = hidden; controls.isHidden = hidden
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        var content = CGRect.null, input = CGRect.null
        let division = activeDivision()
        let tabletop = CompanionVNCTabletopRegions(safe, division, &content, &input)
        let book = !tabletop && CompanionVNCBookRegions(safe, division, &content, &input)
        terminalLeading.constant = book ? content.minX - safe.minX : 0
        terminalTrailing.constant = book ? content.maxX - safe.maxX : 0
        barLeading.constant = book ? input.minX - safe.minX : 0
        barTrailing.constant = book ? input.maxX - safe.maxX : 0
        let ceiling = keyboardCeiling()
        // A hosting controller can already end at the keyboard's top. Compare
        // against the physical window so that this still reveals the number row.
        let restingBottom = view.window.map { window in
            view.convert(CGPoint(x: 0, y: window.bounds.maxY - window.safeAreaInsets.bottom), from: window).y
        } ?? safe.maxY
        let softwareKeyboard = ceiling < restingBottom - 1
        updateKeyboardBarVisibility()
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
        let reservedBarHeight = book || (composerVisible && keyboardBar.isHidden) ? 0 : keyboardBar.height
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
            foldedBottom.constant = wholeRowBottom(max(top, min(content.maxY - 8, ceiling - reservedBarHeight)))
            foldedBottom.isActive = true
        } else {
            foldedBottom.isActive = false
            normalBottom.constant = wholeRowBottom(ceiling - reservedBarHeight) - ceiling
            normalBottom.isActive = true
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardBar.layoutIfNeeded(); keyboardBar.layoutRows()
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        let grid = terminal.getTerminal()
        sizeChanged(source: terminal, newCols: grid.cols, newRows: grid.rows)
    }
    private func configureKeyboard() {
        guard !savingControls else { return }
        do {
            let loaded = try controlsStore.load(); session.controlsRecovery = nil
            if loaded.revision == controlProfile.revision, appliedInputEpoch == terminal.customInputEpoch() { applyBarProfile(); return }
            controlProfile = loaded
            shortcutConfirmations.definitionsChanged(loaded.actions)
        } catch TerminalControlsStore.Failure.newerFormat {
            controlProfile = .defaults; session.controlsRecovery = .make(.controlsUnavailable, message: TerminalControlsStore.newerFormatMessage)
        } catch { controlProfile = .defaults; session.controlsRecovery = .make(.controlsUnavailable, message: "Custom Terminal controls couldn’t be read. Existing data is kept; the standard keyboard remains available.") }
        controls.cancelSlideForLayoutChange(); controls.close()
        if let navigation = presentedViewController as? UINavigationController, navigation.topViewController is CompanionVNCMenu { dismiss(animated: false) }
        if let inputPanel, presentedViewController === inputPanel { dismiss(animated: false); self.inputPanel = nil }
        keypadState?.ready = false; keypadState = nil
        terminal.resetModifiers()
        applyBarProfile()
    }
    private func applyBarProfile() {
        appliedInputEpoch = terminal.customInputEpoch()
        let revision = controlProfile.revision
        keyboardBar.configure(controlProfile) { [weak self] id in
            guard let self, controlProfile.revision == revision else { return }
            performControlAction(id)
        }
        view.setNeedsLayout()
    }
    private func persistBarLayout() {
        var draft = controlProfile
        draft.rowsExpanded = keyboardBar.showsExtraRows
        savingControls = true
        defer { savingControls = false }
        do {
            // Reuse the optimistic revision check; never overwrite newer editor content.
            controlProfile = try controlsStore.save(draft)
            applyBarProfile(); updateControls()
        } catch {
            savingControls = false; configureKeyboard()
            session.controlsRecovery = .make(.saveFailed, message: "The keyboard layout couldn’t be saved. Existing controls are kept.")
        }
    }
    func beginCustomization(library: Bool = false, section: TerminalSavedItemsSection = .shortcuts) {
        guard !customizingControls else { return }
        customizationEpoch = session.customInputEpoch
        customizationKeyboard = terminal.isFirstResponder
        let snapshot = UIGraphicsImageRenderer(bounds: terminal.bounds).image { _ in
            terminal.drawHierarchy(in: terminal.bounds, afterScreenUpdates: false)
        }
        customizationContext?(snapshot)
        customizingControls = true
        controlsInputEpoch = UUID()
        terminal.resetModifiers(); controls.close(); _ = terminal.resignFirstResponder()
        keyboardBar.refresh()
        if library { action(section == .text ? "savedTextLibrary" : "quickActions") } else { customize() }
    }
    func finishCustomization() {
        guard customizingControls else { return }
        let restore = customizationKeyboard && customizationEpoch != nil && customizationEpoch == session.customInputEpoch
        customizingControls = false; customizationKeyboard = false; customizationEpoch = nil
        configureKeyboard(); updateControls()
        if restore { _ = terminal.becomeFirstResponder() }
    }
    private func currentControlsInputEpoch() -> UUID? {
        guard !customizingControls, let epoch = session.customInputEpoch else { return nil }
        if observedSessionInputEpoch != epoch { observedSessionInputEpoch = epoch; controlsInputEpoch = UUID() }
        return controlsInputEpoch
    }
    private func showKeypad(numbersFirst: Bool = false) {
        guard presentedViewController == nil else { return }
        let restoreKeyboard = terminal.isFirstResponder
        let modifiers = terminal.keyboardState
        _ = terminal.resignFirstResponder()
        terminal.keyboardState = modifiers; keyboardBar.refresh()
        let epoch = terminal.customInputEpoch()
        let state = TerminalKeypadState(); state.profileRevision = controlProfile.revision; keypadState = state
        func admitted(_ controller: TerminalController, _ state: TerminalKeypadState) -> Bool {
            epoch != nil && controller.terminal.customInputEpoch() == epoch && controller.controlProfile.revision == state.profileRevision && DirectAppLockV1.shared.canAccess
        }
        let sync: (TerminalController) -> Void = { [weak state] controller in
            if let state { state.ready = admitted(controller, state) }
            state?.supportsCommand = controller.terminal.keyEncoding.supportsCommand
            state?.armed = controller.terminal.keyboardState.armed
            state?.locked = controller.terminal.keyboardState.locked
            state?.canPin = DirectProAccess.shared.hasPro
            state?.items = DirectProAccess.shared.hasPro ? controller.controlProfile.actions : []
        }
        state.toggle = { [weak self, weak state] modifier, lock in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state) else { return }
            keyboardBar.toggle(modifier, lock: lock); sync(self)
        }
        state.send = { [weak self, weak state] kind in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state) else { return }
            state.notice = nil; performControl(kind); sync(self)
        }
        state.beginSearch = { [weak self, weak state] in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state), traitCollection.horizontalSizeClass == .regular else { return }
            // Keep the regular-width sheet stable through keyboard show/hide;
            // filtering must not resize a floating medium sheet under its field.
            inputPanel?.sheetPresentationController?.selectedDetentIdentifier = .large
        }
        state.pin = { [weak self, weak state] keyID, destination in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state), DirectProAccess.shared.hasPro,
                  let key = TerminalKeyCatalog.key(keyID) else { return }
            var draft = controlProfile; draft.pin(key, in: destination)
            savingControls = true
            defer { savingControls = false }
            do {
                controlProfile = try controlsStore.save(draft); state.profileRevision = controlProfile.revision
                applyBarProfile(); updateControls(); sync(self)
                state.notice = key.name + " pinned to " + destination.title + ". Nothing sent."
            } catch {
                state.ready = false
                state.notice = "Controls changed or couldn’t be saved. Close Keypad and reopen it. Existing saved items are kept."
            }
        }
        state.useSaved = { [weak self, weak state] id in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state) else { return }
            performControlAction(id); sync(self)
        }
        state.compose = { [weak self, weak state] in
            guard let self, let state, state.ready, keypadState === state, admitted(self, state) else { return }
            showTextComposer()
        }
        sync(self)
        let panel = UIHostingController(rootView: TerminalKeypad(state: state, macName: session.mac.name, numbersFirst: numbersFirst, onClose: { [weak self, weak state] in
            guard let self, let state, keypadState === state else { return }
            dismiss(animated: true) { [weak self, weak state] in
                guard let self, let state, keypadState === state, admitted(self, state), restoreKeyboard else { return }
                DispatchQueue.main.async { [weak self, weak state] in
                    guard let self, let state, keypadState === state, admitted(self, state) else { return }
                    _ = terminal.becomeFirstResponder(); terminal.reloadInputViews(); view.setNeedsLayout()
                }
            }
        }))
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .large : .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        inputPanel = panel; present(panel, animated: true)
    }
    private func showSavedItems(_ section: TerminalSavedItemsSection) {
        guard presentedViewController == nil else { return }
        let epoch = terminal.customInputEpoch(), revision = controlProfile.revision
        let panel = UIHostingController(rootView: TerminalSavedItems(section: section, items: DirectProAccess.shared.hasPro ? controlProfile.savedItems(section) : [], macName: session.mac.name, supportsCommand: terminal.keyEncoding.supportsCommand, select: { [weak self] id in
            guard let self, let epoch, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
            dismiss(animated: true) { [weak self] in
                guard let self, terminal.customInputEpoch() == epoch, controlProfile.revision == revision else { return }
                performControlAction(id)
            }
        }, customize: { [weak self] in self?.dismiss(animated: true) { [weak self] in self?.beginCustomization(library: true, section: section) } }, compose: { [weak self] in
            self?.showTextComposer()
        }))
        panel.sheetPresentationController?.detents = [.large()]
        inputPanel = panel; present(panel, animated: true)
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
        guard source === terminal else { return }
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
    private func prepareForPTY(_ generation: UUID) {
        guard preparedGeneration != generation, generation == session.outputGeneration else { return }
        resettingPTY = true
        defer { resettingPTY = false }
        if presentedViewController is UIAlertController { dismiss(animated: false) }
        textComposer.invalidate(); controls.cancelSlideForLayoutChange(); controls.close()
        let retired = terminal, grid = terminal.getTerminal()
        let columns = grid.cols, rows = grid.rows, style = retired.overrideUserInterfaceStyle
        let inset = retired.contentInset
        retired.retireInput()
        session.keyboardVisible = false
        normalBottom.isActive = false; foldedBottom.isActive = false
        retired.removeFromSuperview(); keyboardBar.removeFromSuperview()
        // A new frontend also resets private parser, UTF-8, mouse protocol,
        // cursor visibility, IME and pending physical-key state. The pinned
        // renderer's RIS reset intentionally preserves some of those values.
        terminal = SessionTerminalView(frame: retired.frame)
        keyboardBar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        installTerminalSurface()
        terminal.contentInset = inset; terminal.overrideUserInterfaceStyle = style
        terminal.getTerminal().resize(cols: columns, rows: rows)
        configureKeyboard()
        controls.buttonAnchorView = keyboardBar.menuAnchor; view.bringSubviewToFront(controls)
        paletteIsDark = nil; reportedGrid = nil; updatePalette()
        preparedGeneration = generation
        view.setNeedsLayout(); view.layoutIfNeeded()
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard source === terminal, (!customizingControls || feedingRemoteOutput), !resettingPTY, preparedGeneration == session.outputGeneration else { return }
        if feedingRemoteOutput { session.send(Array(data), source: .emulatorReply) }
        else { session.send(terminal.encodeOutput(data)) }
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard source === terminal, !resettingPTY, preparedGeneration == session.outputGeneration, session.connected, DirectAppLockV1.shared.canAccess else { return }
        let generation = session.outputGeneration
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let alert = UIAlertController(title: "Open terminal link?", message: url.host, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let self, session.outputGeneration == generation, session.connected, DirectAppLockV1.shared.canAccess else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        guard source === terminal, !resettingPTY, preparedGeneration == session.outputGeneration, session.connected, DirectAppLockV1.shared.canAccess else { return }
        let generation = session.outputGeneration
        guard content.count <= 65536, let text = String(data: content, encoding: .utf8) else { return }
        let alert = UIAlertController(title: "Copy terminal text?", message: "The Mac requested copying text to your iPhone clipboard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
            guard let self, session.outputGeneration == generation, session.connected, DirectAppLockV1.shared.canAccess else { return }
            UIPasteboard.general.string = text
        })
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
                    DirectConnectionDetailsRows(mac: mac, desktop: false)
                }
            }.navigationTitle("Connection Details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
#endif
