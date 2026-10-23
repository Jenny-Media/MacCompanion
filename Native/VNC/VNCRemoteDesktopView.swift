#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Let the native backdrop cover the status area as well as the canvas. The
/// native controller keeps its login card and controls inside the safe area.
/// SwiftUI's presenting controller also gets the matching status text style.
struct DirectDesktopSessionView: View {
    let mac: DirectMacRecordV1
    var inputOnly = false
    var autoConnect = true
    var connectionMacNames: [String] = []
    let showMacs: @MainActor () -> Void
    var connectionPanel: DirectConnectionPanelHost?
    var loginRetentionAllowed = true
    var connectionEstablished: @MainActor () -> Bool = { true }
    @State private var immersive = false
    @State private var appearance = DirectAppearanceV1.shared
    @State private var files: DirectFilesSession
    init(mac: DirectMacRecordV1, inputOnly: Bool = false, autoConnect: Bool = true, connectionMacNames: [String] = [], files: DirectFilesSession? = nil, libraryURL: URL = DirectMacLibraryV1.defaultURL, connectionPanel: DirectConnectionPanelHost? = nil, loginRetentionAllowed: Bool = true, connectionEstablished: @escaping @MainActor () -> Bool = { true }, showMacs: @escaping @MainActor () -> Void) {
        self.connectionPanel = connectionPanel; self.loginRetentionAllowed = loginRetentionAllowed; self.connectionEstablished = connectionEstablished
        self.mac = mac; self.inputOnly = inputOnly; self.autoConnect = autoConnect; self.connectionMacNames = connectionMacNames; self.showMacs = showMacs
        _files = State(initialValue: files ?? DirectFilesWorkspace.session(mac, libraryURL: libraryURL))
    }
    var body: some View {
        ZStack {
            (immersive ? Color.black : connectionPanel == nil ? Color(uiColor: .systemBackground) : Color.clear).ignoresSafeArea()
            if !files.macRemoved {
                VNCRemoteDesktopView(mac: mac, inputOnly: inputOnly, autoConnect: autoConnect, connectionMacNames: connectionMacNames, files: files,
                                     showMacs: showMacs, connectionPanel: connectionPanel, loginRetentionAllowed: loginRetentionAllowed, connectionEstablished: connectionEstablished, chromeChanged: { immersive = $0 })
                    .ignoresSafeArea(.container, edges: .top)
            }
            if files.macRemoved, files.hasUnsavedDownloads {
                DirectFilesView(mac: mac, session: files, closeOwnerWindow: showMacs)
            }
        }
        .preferredColorScheme(immersive ? .dark : appearance.app.colorScheme)
        .onChange(of: files.shouldCloseAfterRemoval) { _, close in if close { showMacs() } }
    }
}

struct VNCRemoteDesktopView: UIViewControllerRepresentable {
    let mac: DirectMacRecordV1
    var inputOnly = false
    var autoConnect = true
    var connectionMacNames: [String] = []
    let files: DirectFilesSession
    let showMacs: @MainActor () -> Void
    var connectionPanel: DirectConnectionPanelHost?
    var loginRetentionAllowed = true
    var connectionEstablished: @MainActor () -> Bool = { true }
    var chromeChanged: @MainActor (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(mac: mac, files: files, showMacs: showMacs)
        coordinator.connectionEstablished = connectionEstablished; coordinator.saveMacRequested = loginRetentionAllowed
        return coordinator
    }
    func makeUIViewController(context: Context) -> CompanionVNCTextNavigation {
        let viewer = CompanionVNCViewer()
        viewer.preventsAutomaticConnection = !autoConnect
        viewer.connectionPanelHost = connectionPanel; viewer.preventsLoginRetention = !loginRetentionAllowed
        viewer.macName = mac.name
        viewer.connectionMacNames = connectionMacNames.isEmpty ? [mac.name] : connectionMacNames
        viewer.connectionAddresses = mac.addresses
        viewer.servicePort = mac.port
        viewer.sshPort = mac.sshPort
        viewer.inputOnly = inputOnly
        viewer.chromeHandler = { value in
            // Native state can change while SwiftUI mounts this controller.
            Task { @MainActor in chromeChanged(value) }
        }
        viewer.preferenceID = mac.id.uuidString.lowercased()
        viewer.pointerSpeed = VNCSessionPreferences.speed(mac.id)
        viewer.scrollSpeed = VNCSessionPreferences.scrollSpeed
        viewer.showsTouchPoints = VNCSessionPreferences.showsTouchPoints
        viewer.trackpadHapticsEnabled = VNCSessionPreferences.trackpadHaptics
        viewer.restoredDisplayID = VNCSessionPreferences.display(mac.id)
        viewer.restoredDesktopSizePreset = VNCSessionPreferences.desktopSize(mac.id)
        viewer.desktopSizeSelectionHandler = { selected in
            MainActor.assumeIsolated { VNCSessionPreferences.setDesktopSize(selected, mac: mac.id) }
        }
        viewer.fullscreen = VNCSessionPreferences.fullscreen(mac.id)
        viewer.presentationHandler = { value in MainActor.assumeIsolated { VNCSessionPreferences.setFullscreen(value, mac: mac.id) } }
        viewer.preferredTrackpad = VNCSessionPreferences.trackpad(mac.id)
        viewer.followCursorEnabled = VNCSessionPreferences.followCursor(mac.id)
        viewer.settingsHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.showInputSettings() }
        }
        viewer.accessEditingAllowed = { MainActor.assumeIsolated { !DirectMacConnections.shared.isActive(mac.id) } }
        viewer.accessHandler = { [weak coordinator = context.coordinator] in MainActor.assumeIsolated { coordinator?.showAccess() } }
        viewer.requestExitHandler = { [weak coordinator = context.coordinator] in MainActor.assumeIsolated { coordinator?.confirmExitIfNeeded() ?? false } }
        viewer.filesHandler = { [weak coordinator = context.coordinator] in MainActor.assumeIsolated { coordinator?.showFiles() } }
        viewer.filesTransferActiveHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.files.isBorrowed == true && coordinator?.files.transferActive == true }
        }
        context.coordinator.files.activityChanged = { [weak viewer] value in viewer?.filesStatus = value == "Ready" ? "" : value }
        viewer.appSettingsHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.showAppSettings() }
        }
        viewer.displaySelectionHandler = { selected in
            MainActor.assumeIsolated { VNCSessionPreferences.setDisplay(selected, mac: mac.id) }
        }
        viewer.inputModeHandler = { trackpad in
            MainActor.assumeIsolated { VNCSessionPreferences.setTrackpad(trackpad, mac: mac.id) }
        }
        viewer.diagnosticHandler = { [weak coordinator = context.coordinator] counters in
            MainActor.assumeIsolated { coordinator?.recordDiagnostics(counters) }
        }
        context.coordinator.viewer = viewer
        viewer.sessionPhaseHandler = { [weak coordinator = context.coordinator] phase in
            MainActor.assumeIsolated { coordinator?.activity.setPhase(phase) }
        }
        if let login = DesktopCredentialStoreV1.read(mac.id) {
            viewer.savedUsername = login.username; viewer.savedPassword = login.password
        }
        viewer.connectHandler = { [weak coordinator = context.coordinator] user, password, remember in
            MainActor.assumeIsolated { coordinator?.connect(user: user, password: password, remember: remember) }
        }
        viewer.connectedHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.saveSuccessfulLogin() }
        }
        viewer.disconnectHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.disconnect() }
        }
        viewer.macsHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.endSession() }
        }
        context.coordinator.observeActivity()
        let navigation = CompanionVNCTextNavigation(rootViewController: viewer); navigation.view.backgroundColor = .clear
        return navigation
    }
    func updateUIViewController(_ controller: CompanionVNCTextNavigation, context: Context) {}
    static func dismantleUIViewController(_ controller: CompanionVNCTextNavigation, coordinator: Coordinator) {
        // Removal tears down the remote controller while its SwiftUI parent
        // owns the download-only recovery presentation.
        if !coordinator.files.macRemoved { coordinator.files.disconnectBorrowed(coordinator.authenticatedGeneration) }
        coordinator.disconnect(); coordinator.stopObserving(); coordinator.activity.finish()
        coordinator.viewer?.stop()
    }

    @MainActor final class Coordinator {
        let files: DirectFilesSession
        let mac: DirectMacRecordV1
        weak var viewer: CompanionVNCViewer?
        private let accessOwnerID = UUID()
        private var accessLease: UUID?
        private var authenticatedAccount = ""
        var authenticatedGeneration = UUID()
        private var work: Task<Void, Never>?
        private var generation = UUID()
        private var diagnosticTicket = UUID()
        private var tunnel: DirectDesktopSSHTunnel?
        private var retirement: Task<Void, Never>?
        private var trustReply: CheckedContinuation<Bool, Never>?
        private var trustController: UIViewController?
        private var login: DesktopCredentialStoreV1.Login?
        private var remember = false
        private var observers: [NSObjectProtocol] = []
        let activity: VNCSessionActivityController
        private var backgroundTask = UIBackgroundTaskIdentifier.invalid
        private var backgroundGeneration = UUID()
        private var inputReleaseCompleted = false
        private let showMacs: @MainActor () -> Void
        var connectionEstablished: @MainActor () -> Bool = { true }
        /// False for an intentional temporary Quick Connect session.
        var saveMacRequested = true
        private var macSaveFailureReported = false
        private var removed = false
        private var removalObserver: DirectMacRemovalObservation?
        private var forgetObserver: DirectMacAccessForgetObservation?
        init(mac: DirectMacRecordV1, files: DirectFilesSession? = nil, activityController: VNCSessionActivityController? = nil, showMacs: @escaping @MainActor () -> Void = {}) {
            self.mac = mac; self.files = files ?? DirectFilesWorkspace.session(mac); self.showMacs = showMacs; activity = activityController ?? VNCSessionActivityController(mac: mac)
            forgetObserver = DirectMacAccessForgetObservation(macID: mac.id) { [weak self] in
                guard let self else { return }
                self.login = nil; self.remember = false
                self.viewer?.savedUsername = nil; self.viewer?.savedPassword = nil
                if self.viewer?.isViewLoaded == true { self.viewer?.reloadAccessUsername("", password: "") }
            }
            removalObserver = DirectMacRemovalObservation(macID: mac.id, libraryURL: self.files.libraryURL) { [weak self] in
                guard let self else { return }
                self.removed = true; self.disconnect(); self.viewer?.stop(); self.activity.finish()
                self.viewer?.dismiss(animated: false); self.stopObserving()
            }
        }
        func observeActivity() {
            observers = [NotificationCenter.default.addObserver(forName: DirectMacConnections.changed, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.refreshAccessEditing() }
            }, NotificationCenter.default.addObserver(forName: VNCSessionPreferences.scrollSpeedChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.scrollSpeed = VNCSessionPreferences.scrollSpeed }
            }, NotificationCenter.default.addObserver(forName: VNCSessionPreferences.trackpadFeedbackChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.viewer?.showsTouchPoints = VNCSessionPreferences.showsTouchPoints
                    self?.viewer?.trackpadHapticsEnabled = VNCSessionPreferences.trackpadHaptics
                }
            }, NotificationCenter.default.addObserver(forName: VNCSessionPreferences.actionsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshControls() }
            }, NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.becameInactive() }
            }, NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }, NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishBackgroundWork(); self.activity.setForeground(true); if DirectAppLockV1.shared.canAccess { self.viewer?.foregrounded() }
                }
            }, NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.foregrounded() }
            }, NotificationCenter.default.addObserver(forName: DirectAppLockV1.locked, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }, NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.activity.preferenceChanged() }
            }, NotificationCenter.default.addObserver(forName: RemoteSessionActivityActions.endRequested, object: nil, queue: .main) { [weak self] notification in
                guard let id = notification.object as? String else { return }
                MainActor.assumeIsolated {
                    guard let self, self.activity.ownsActivity(id) else { return }
                    self.endSession()
                }
            }]
        }
        func stopObserving() { observers.forEach(NotificationCenter.default.removeObserver); observers = []; finishBackgroundWork() }
        private func pause() {
            activity.setForeground(false)
            guard backgroundTask == .invalid else { return }
            let token = UUID(); backgroundGeneration = token
            inputReleaseCompleted = false
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish session pause") { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.backgroundGeneration == token else { return }
                    if !self.inputReleaseCompleted { self.viewer?.session.stop(); self.activity.setPhase("ended") }
                    self.finishBackgroundWork()
                }
            }
            viewer?.background(completion: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.backgroundGeneration == token else { return }
                    self.inputReleaseCompleted = true
                    Task { [weak self] in
                        guard let self else { return }
                        await self.activity.waitForUpdates()
                        if self.backgroundGeneration == token { self.finishBackgroundWork() }
                    }
                }
            })
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.backgroundGeneration == token else { return }
                // Only a stalled release is retired; no idle background assertion remains.
                if !self.inputReleaseCompleted { self.viewer?.session.stop(); self.activity.setPhase("ended") }
                self.finishBackgroundWork()
            }
        }
        private func finishBackgroundWork() {
            backgroundGeneration = UUID()
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
        }
        func recordDiagnostics(_ counters: [AnyHashable: Any]) {
            let ticket = UUID(); diagnosticTicket = ticket
            let generation = generation, owner = tunnel
            Task { [weak self] in
                let transport = try? await owner?.diagnosticCounters()
                guard let self, self.diagnosticTicket == ticket, self.generation == generation,
                      self.tunnel === owner, !self.removed else { return }
                // Fixed numeric aggregates and geometry only; latest owner wins.
                var snapshot = counters
                if let transport { snapshot["desktopSSH"] = transport }
                let url = URL.cachesDirectory.appending(path: "VNCDisplayDiagnostics-v1.json")
                if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
                    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }
        }
        func saveSuccessfulLogin() {
            guard !removed else { return }
            let canRetain = connectionEstablished()
            guard canRetain else {
                let loginRequested = remember
                self.login = nil; remember = false
                if saveMacRequested && !macSaveFailureReported {
                    macSaveFailureReported = true
                    viewer?.showMacSaveFailure(loginRequested)
                }
                return
            }
            guard remember, let login, let owner = accessLease else { return }
            remember = false
            do { try DirectMacAccessStore.retain(.init(username: login.username, password: login.password), macID: mac.id, ssh: false, owner: owner) }
            catch { viewer?.showLoginRetentionFailure() }
            self.login = nil
        }
        func connect(user: String, password: String, remember: Bool) {
            guard !removed, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
            guard work == nil else { return }
            let u = Array(user.utf8), p = Array(password.utf8)
            guard (1...63).contains(u.count), (1...63).contains(p.count), !u.contains(0), !p.contains(0) else {
                viewer?.showInvalidLogin(); return
            }
            do {
                try DirectMacAccessStore.checkConnection(macID: mac.id, username: user, password: password, key: nil, ssh: false, ownerID: accessOwnerID)
                if !remember { try DesktopCredentialStoreV1.remove(mac.id) }
            }
            catch { viewer?.showLoginRetentionFailure(); return }
            let token = UUID(); generation = token
            authenticatedAccount = user; authenticatedGeneration = token
            accessLease = DirectMacConnections.shared.begin(macID: mac.id, kind: "desktop", ownerID: accessOwnerID,
                pendingAccessChange: DirectMacAccessStore.willRetainChange(macID: mac.id, username: user, password: password, key: nil, ssh: false, remember: remember), disconnect: { [weak self] in self?.disconnect() })
            login = remember ? .init(username: user, password: password) : nil
            self.remember = remember; macSaveFailureReported = false
            let previous = viewer?.session
            previous?.stop()
            let retiring = retirement
            let mirrorGrace = viewer?.mirrorRetirementDelay ?? 0
            if viewer?.restoredDesktopSizePreset == 0 {
                viewer?.restoredDisplayID = VNCSessionPreferences.display(mac.id)
            }
            viewer?.prepareConnection()
            work = Task { [weak self] in
                guard let self, let viewer else { return }
                do {
                    // Retire native input and the preceding SSH owner before reuse.
                    await retiring?.value
                    for _ in 0..<200 {
                        if previous?.running != true { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    if mirrorGrace > 0 {
                        // Stay completely disconnected beyond the inspected host's
                        // no-viewer exit timer. Reopening during this interval can
                        // preserve the very virtual display we are trying to retire.
                        let deadline = ContinuousClock.now.advanced(by: .seconds(mirrorGrace))
                        var displayed = -1
                        while ContinuousClock.now < deadline {
                            try Task.checkCancellation()
                            guard generation == token, viewer.connectionForegroundAvailable,
                                  DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { throw CancellationError() }
                            let remaining = ContinuousClock.now.duration(to: deadline).components
                            let seconds = max(1, Int(remaining.seconds) + (remaining.attoseconds > 0 ? 1 : 0))
                            if displayed != seconds { viewer.showMirrorCleanupRemaining(UInt(seconds)); displayed = seconds }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        try Task.checkCancellation()
                        guard generation == token, viewer.connectionForegroundAvailable,
                              DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { throw CancellationError() }
                        viewer.finishMirrorCleanup()
                    }
                    try Task.checkCancellation()
                    guard generation == token, previous?.running != true, viewer.connectionForegroundAvailable, DirectAppLockV1.shared.canAccess,
                          DirectClientPlatformV1.sessionAvailable else { throw CancellationError() }
                    let opened = try await DirectDesktopSSHTunnel.open(addresses: mac.addresses,
                        sshPort: mac.sshPort, screenSharingPort: mac.port, username: user, password: password,
                        validateHost: { [weak self] key in
                            guard let self else { throw CancellationError() }
                            try await self.verifyHost(key, generation: token)
                        }, progress: { [weak self] message in
                            guard let self, self.generation == token else { return }
                            self.viewer?.showConnectionProgress(message)
                        })
                    guard generation == token, !Task.isCancelled, viewer.connectionForegroundAvailable,
                          DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else {
                        if generation == token, !Task.isCancelled, !viewer.connectionForegroundAvailable {
                            // Publish the pause before awaited channel retirement:
                            // activation during close must resume that pause,
                            // not turn the original interruption into cancellation.
                            viewer.background(completion: {})
                        }
                        await opened.close(); throw CancellationError()
                    }
                    tunnel = opened
                    viewer.session.connectSocket(opened.takeSocket(), username: user, password: password)
                    work = nil
                } catch {
                    if generation == token {
                        if error is CancellationError, !Task.isCancelled, !viewer.connectionForegroundAvailable {
                            // Control Center and other temporary inactivity are a
                            // lifecycle pause, not explicit cancellation of login.
                            // This retires the opener and resumes with the same
                            // private credentials and cleanup requirement on return.
                            viewer.background(completion: {})
                        } else {
                            disconnect(); viewer.showConnectionFailureStage(error is CancellationError ? 113 : DirectDesktopSSHTunnel.failureStage(error))
                        }
                    }
                }
            }
        }
        func refreshControls() {
            guard let viewer else { return }
            viewer.refreshControlsMenu()
        }
        func showInputSettings() { viewer?.showControlsSettings() }
        func showAccess() {
            guard let viewer, viewer.presentedViewController == nil else { return }
            let root = DirectMacAccessView(mac: mac, saved: { [weak self, weak viewer] in
                guard let self, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
                let login = DesktopCredentialStoreV1.read(self.mac.id)
                viewer?.reloadAccessUsername(login?.username ?? "", password: login?.password ?? "")
            })
            let controller = UIHostingController(rootView: root); controller.modalPresentationStyle = .pageSheet
            if let panel = viewer.connectionPanelHost, panel.isVisible { panel.presentSecondary(controller) }
            else { viewer.present(controller, animated: true) }
        }
        func confirmExitIfNeeded() -> Bool {
            guard files.isBorrowed, files.transferActive, let viewer, viewer.presentedViewController == nil else { return false }
            let alert = UIAlertController(title: "End this session?", message: "The active file transfer will be interrupted. Completed downloads are kept in Files.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep Session", style: .cancel))
            alert.addAction(UIAlertAction(title: "End Session", style: .destructive) { [weak self] _ in
                guard let self else { return }
                CompanionVNCPlayInterfaceFeedback("end")
                self.endSession()
            })
            viewer.present(alert, animated: true); return true
        }
        func showFiles() {
            guard let viewer, viewer.presentedViewController == nil, DirectAppLockV1.shared.canAccess else { return }
            let controller = UIHostingController(rootView: DirectFilesView(mac: mac, session: files, retainWhenDismissed: true).usingConnection { [weak self] in
                guard let self, let tunnel = self.tunnel, self.viewer?.session.running == true else { return nil }
                return .init(client: tunnel.client, macID: self.mac.id, ownerID: self.accessOwnerID, account: self.authenticatedAccount, keyID: nil, generation: self.authenticatedGeneration)
            }.directAppearance())
            controller.modalPresentationStyle = .pageSheet
            controller.sheetPresentationController?.detents = [.medium(), .large()]
            controller.sheetPresentationController?.prefersGrabberVisible = true
            viewer.present(controller, animated: true)
        }
        func showAppSettings() {
            guard let viewer, viewer.presentedViewController == nil else { return }
            viewer.view.endEditing(true)
            let controller = UIHostingController(rootView: DirectSessionSettingsV1().directAppearance())
            controller.modalPresentationStyle = .pageSheet
            viewer.present(controller, animated: true)
        }
        private func verifyHost(_ key: String, generation token: UUID) async throws {
            guard generation == token, !Task.isCancelled, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
            if let saved = try TerminalSecretStore.hostKey(mac.id) {
                guard saved == key else { throw TerminalSecretStore.Failure.changedKey }
            } else {
                guard let fingerprint = TerminalSecretStore.fingerprint(key), let viewer else { throw TerminalSecretStore.Failure.rejectedKey }
                // UIKit reports an ancestor's presented connection sheet here.
                // The shared panel replaces its contents for trust; only the
                // legacy presentation path needs an unused modal presenter.
                guard viewer.connectionPanelHost?.isVisible == true || viewer.presentedViewController == nil else { throw TerminalSecretStore.Failure.rejectedKey }
                let accepted = await withCheckedContinuation { reply in
                    trustReply = reply
                    let controller = UIHostingController(rootView: TerminalServerTrustView(macName: mac.name,
                        fingerprint: fingerprint, answer: { [weak self] accepted in
                            guard let self, self.generation == token else { return }
                            self.answerTrust(accepted)
                        }).directAppearance())
                    controller.modalPresentationStyle = .pageSheet
                    trustController = controller
                    if let panel = viewer.connectionPanelHost { panel.showTrust(controller) }
                    else { viewer.present(controller, animated: true) }
                }
                guard generation == token, !Task.isCancelled, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
                guard accepted else { throw TerminalSecretStore.Failure.rejectedKey }
                try TerminalSecretStore.approveHostKey(key, id: mac.id)
            }
            viewer?.showConnectionProgress("Verifying SSH server…")
        }
        func answerTrust(_ accepted: Bool) {
            let reply = trustReply; trustReply = nil
            let controller = trustController; trustController = nil
            if let controller, let panel = viewer?.connectionPanelHost { panel.finishTrust(controller) }
            else { controller?.dismiss(animated: false) }
            reply?.resume(returning: accepted)
        }
        func disconnect() {
            let pendingConnection = work
            generation = UUID(); work?.cancel(); work = nil; answerTrust(false)
            let native = viewer?.session
            native?.stop(); login = nil; remember = false
            let lease = accessLease; accessLease = nil
            files.disconnectBorrowed(authenticatedGeneration)
            let retired = tunnel; tunnel = nil
            let earlier = retirement
            retirement = Task {
                await earlier?.value
                // A cancelled opener can own a forwarded channel before it has
                // published `tunnel`. Its cleanup must finish before our quiet
                // interval or the next connection, just like an established one.
                await pendingConnection?.value
                for _ in 0..<200 {
                    if native?.running != true { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await retired?.close()
                DirectMacConnections.shared.end(lease)
            }
        }
        func endSession() {
            activity.finish(); disconnect(); viewer?.stop(); stopObserving(); showMacs()
        }
    }
}
#endif
