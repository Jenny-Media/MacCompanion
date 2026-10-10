#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Let the native backdrop cover the status area as well as the canvas. The
/// native controller keeps its login card and controls inside the safe area.
/// SwiftUI's presenting controller also gets the matching status text style.
struct DirectDesktopSessionView: View {
    let mac: DirectMacRecordV1
    var inputOnly = false
    var connectionMacNames: [String] = []
    let showMacs: @MainActor () -> Void
    @State private var immersive = false
    @State private var appearance = DirectAppearanceV1.shared
    var body: some View {
        ZStack {
            (immersive ? Color.black : Color(uiColor: .systemBackground)).ignoresSafeArea()
            VNCRemoteDesktopView(mac: mac, inputOnly: inputOnly, connectionMacNames: connectionMacNames,
                                 showMacs: showMacs, chromeChanged: { immersive = $0 })
                .ignoresSafeArea(.container, edges: .top)
        }
        .preferredColorScheme(immersive ? .dark : appearance.app.colorScheme)
    }
}

struct VNCRemoteDesktopView: UIViewControllerRepresentable {
    let mac: DirectMacRecordV1
    var inputOnly = false
    var connectionMacNames: [String] = []
    let showMacs: @MainActor () -> Void
    var chromeChanged: @MainActor (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(mac: mac, showMacs: showMacs) }
    func makeUIViewController(context: Context) -> CompanionVNCViewer {
        let viewer = CompanionVNCViewer()
        viewer.macName = mac.name
        viewer.connectionMacNames = connectionMacNames.isEmpty ? [mac.name] : connectionMacNames
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
        viewer.fullscreen = VNCSessionPreferences.fullscreen(mac.id)
        viewer.presentationHandler = { value in MainActor.assumeIsolated { VNCSessionPreferences.setFullscreen(value, mac: mac.id) } }
        viewer.preferredTrackpad = VNCSessionPreferences.trackpad(mac.id)
        viewer.followCursorEnabled = VNCSessionPreferences.followCursor(mac.id)
        viewer.quickActionsProvider = { onlyInput in
            MainActor.assumeIsolated { VNCSessionPreferences.actions(onlyInput ? .trackpad : .desktop, legacyMac: mac.id) }.map(\.native)
        }
        viewer.quickActions = VNCSessionPreferences.actions(inputOnly ? .trackpad : .desktop, legacyMac: mac.id).map(\.native)
        viewer.settingsHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.showInputSettings() }
        }
        viewer.appSettingsHandler = { [weak coordinator = context.coordinator] in
            MainActor.assumeIsolated { coordinator?.showAppSettings() }
        }
        viewer.displaySelectionHandler = { selected in
            MainActor.assumeIsolated { VNCSessionPreferences.setDisplay(selected, mac: mac.id) }
        }
        viewer.inputModeHandler = { trackpad in
            MainActor.assumeIsolated { VNCSessionPreferences.setTrackpad(trackpad, mac: mac.id) }
        }
        viewer.diagnosticHandler = { counters in
            // A bounded latest snapshot with fixed numeric counters and display
            // geometry only. Never persist endpoint, login, pixels, or input.
            let url = URL.cachesDirectory.appending(path: "VNCDisplayDiagnostics-v1.json")
            if let data = try? JSONSerialization.data(withJSONObject: counters, options: [.sortedKeys]) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
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
        return viewer
    }
    func updateUIViewController(_ controller: CompanionVNCViewer, context: Context) {}
    static func dismantleUIViewController(_ controller: CompanionVNCViewer, coordinator: Coordinator) {
        coordinator.disconnect(); coordinator.stopObserving(); coordinator.activity.finish()
        controller.stop()
    }

    @MainActor final class Coordinator {
        let mac: DirectMacRecordV1
        weak var viewer: CompanionVNCViewer?
        private var work: Task<Void, Never>?
        private var generation = UUID()
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
        private let showMacs: @MainActor () -> Void
        init(mac: DirectMacRecordV1, showMacs: @escaping @MainActor () -> Void = {}) {
            self.mac = mac; self.showMacs = showMacs; activity = VNCSessionActivityController(mac: mac)
        }
        func observeActivity() {
            observers = [NotificationCenter.default.addObserver(forName: VNCSessionPreferences.scrollSpeedChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.scrollSpeed = VNCSessionPreferences.scrollSpeed }
            }, NotificationCenter.default.addObserver(forName: VNCSessionPreferences.trackpadFeedbackChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.viewer?.showsTouchPoints = VNCSessionPreferences.showsTouchPoints
                    self?.viewer?.trackpadHapticsEnabled = VNCSessionPreferences.trackpadHaptics
                }
            }, NotificationCenter.default.addObserver(forName: VNCSessionPreferences.actionsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshControls() }
            }, NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }, NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishBackgroundWork(); self.activity.setForeground(true); if DirectAppLockV1.shared.canAccess { self.viewer?.foregrounded() }
                }
            }, NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewer?.foregrounded() }
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
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish session pause") { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.backgroundGeneration == token else { return }
                    self.viewer?.session.stop(); self.finishBackgroundWork()
                }
            }
            viewer?.background(completion: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.backgroundGeneration == token else { return }
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
                self.viewer?.session.stop(); self.finishBackgroundWork()
            }
        }
        private func finishBackgroundWork() {
            backgroundGeneration = UUID()
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
        }
        func saveSuccessfulLogin() {
            guard remember, let login else { return }
            remember = false
            do { try DesktopCredentialStoreV1.save(login, hostID: mac.id) }
            catch { viewer?.showLoginRetentionFailure() }
            self.login = nil
        }
        func connect(user: String, password: String, remember: Bool) {
            guard DirectAppLockV1.shared.canAccess else { return }
            guard work == nil else { return }
            let u = Array(user.utf8), p = Array(password.utf8)
            guard (1...63).contains(u.count), (1...63).contains(p.count), !u.contains(0), !p.contains(0) else {
                viewer?.showInvalidLogin(); return
            }
            do { if !remember { try DesktopCredentialStoreV1.remove(mac.id) } }
            catch { viewer?.showLoginRetentionFailure(); return }
            let token = UUID(); generation = token
            login = remember ? .init(username: user, password: password) : nil
            self.remember = remember
            let previous = viewer?.session
            previous?.stop()
            let retiring = retirement
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
                    try Task.checkCancellation()
                    guard generation == token, previous?.running != true else { throw CancellationError() }
                    let opened = try await DirectDesktopSSHTunnel.open(addresses: mac.addresses,
                        sshPort: mac.sshPort, screenSharingPort: mac.port, username: user, password: password,
                        validateHost: { [weak self] key in
                            guard let self else { throw CancellationError() }
                            try await self.verifyHost(key, generation: token)
                        }, progress: { [weak self] message in
                            guard let self, self.generation == token else { return }
                            self.viewer?.showConnectionProgress(message)
                        })
                    guard generation == token, !Task.isCancelled else { await opened.close(); throw CancellationError() }
                    tunnel = opened
                    viewer.session.connectSocket(opened.takeSocket(), username: user, password: password)
                    work = nil
                } catch {
                    if generation == token { disconnect(); viewer.showConnectionFailureStage(DirectDesktopSSHTunnel.failureStage(error)) }
                }
            }
        }
        func refreshControls() {
            guard let viewer else { return }
            viewer.quickActions = VNCSessionPreferences.actions(viewer.inputOnly ? .trackpad : .desktop, legacyMac: mac.id).map(\.native)
        }
        func showInputSettings() {
            guard let viewer, viewer.presentedViewController == nil else { return }
            let controller = UIHostingController(rootView: VNCInputSettings(macID: mac.id, mode: viewer.inputOnly ? .trackpad : .desktop) { [weak viewer] in
                viewer?.pointerSpeed = VNCSessionPreferences.speed(self.mac.id)
                viewer?.followCursorEnabled = VNCSessionPreferences.followCursor(self.mac.id)
                self.refreshControls()
            }.directAppearance())
            controller.modalPresentationStyle = .pageSheet
            viewer.present(controller, animated: true)
        }
        func showAppSettings() {
            guard let viewer, viewer.presentedViewController == nil else { return }
            let controller = UIHostingController(rootView: DirectSessionSettingsV1().directAppearance())
            controller.modalPresentationStyle = .pageSheet
            viewer.present(controller, animated: true)
        }
        private func verifyHost(_ key: String, generation token: UUID) async throws {
            guard generation == token, !Task.isCancelled, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
            if let saved = try TerminalSecretStore.hostKey(mac.id) {
                guard saved == key else { throw TerminalSecretStore.Failure.changedKey }
            } else {
                guard let fingerprint = TerminalSecretStore.fingerprint(key), let viewer,
                      viewer.presentedViewController == nil else { throw TerminalSecretStore.Failure.rejectedKey }
                let accepted = await withCheckedContinuation { reply in
                    trustReply = reply
                    let controller = UIHostingController(rootView: TerminalServerTrustView(macName: mac.name,
                        fingerprint: fingerprint, answer: { [weak self] accepted in
                            guard let self, self.generation == token else { return }
                            self.answerTrust(accepted)
                        }).directAppearance())
                    controller.modalPresentationStyle = .pageSheet
                    trustController = controller
                    viewer.present(controller, animated: true)
                }
                guard generation == token, !Task.isCancelled, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
                guard accepted else { throw TerminalSecretStore.Failure.rejectedKey }
                try TerminalSecretStore.write(Data(key.utf8), id: mac.id, kind: "host-key")
            }
            viewer?.showConnectionProgress("Signing in to Remote Login…")
        }
        func answerTrust(_ accepted: Bool) {
            let reply = trustReply; trustReply = nil
            let controller = trustController; trustController = nil
            controller?.dismiss(animated: false)
            reply?.resume(returning: accepted)
        }
        func disconnect() {
            generation = UUID(); work?.cancel(); work = nil; answerTrust(false)
            let native = viewer?.session
            native?.stop(); login = nil; remember = false
            guard let retired = tunnel else { return }
            tunnel = nil
            let earlier = retirement
            retirement = Task {
                await earlier?.value
                // Preserve the native owner's balanced key/button releases.
                // Its Stop is bounded; force wake-up if it cannot finish.
                for _ in 0..<200 {
                    if native?.running != true { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await retired.close()
            }
        }
        func endSession() {
            activity.finish(); disconnect(); viewer?.stop(); stopObserving(); showMacs()
        }
    }
}
#endif
