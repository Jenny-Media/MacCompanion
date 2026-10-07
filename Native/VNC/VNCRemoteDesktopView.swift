#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Paint the hosting safe area with the same background as the native canvas.
/// This also gives SwiftUI's presenting controller the matching status text style.
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
                .ignoresSafeArea(.container, edges: immersive ? .top : [])
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
        viewer.inputOnly = inputOnly
        viewer.chromeHandler = { value in
            // Native state can change while SwiftUI mounts this controller.
            Task { @MainActor in chromeChanged(value) }
        }
        viewer.preferenceID = mac.id.uuidString.lowercased()
        viewer.pointerSpeed = VNCSessionPreferences.speed(mac.id)
        viewer.restoredDisplayID = VNCSessionPreferences.display(mac.id)
        viewer.fullscreen = VNCSessionPreferences.fullscreen(mac.id)
        viewer.presentationHandler = { value in MainActor.assumeIsolated { VNCSessionPreferences.setFullscreen(value, mac: mac.id) } }
        viewer.preferredTrackpad = VNCSessionPreferences.trackpad(mac.id)
        viewer.followCursorEnabled = VNCSessionPreferences.followCursor(mac.id)
        viewer.quickActions = VNCSessionPreferences.actions(mac.id).map(\.native)
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
            observers = [NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
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
            viewer?.prepareConnection()
            work = Task { [weak self] in
                guard let self, let viewer else { return }
                do {
                    // Previous Stop releases input and closes its native owner before reuse.
                    for _ in 0..<200 {
                        if previous?.running != true { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try Task.checkCancellation()
                    guard generation == token, previous?.running != true else { throw CancellationError() }
                    viewer.session.connectAddresses(mac.addresses, port: mac.port, username: user, password: password)
                    work = nil
                } catch {
                    if generation == token { disconnect(); viewer.showConnectionFailure() }
                }
            }
        }
        func showInputSettings() {
            guard let viewer, viewer.presentedViewController == nil else { return }
            let controller = UIHostingController(rootView: VNCInputSettings(macID: mac.id) { [weak viewer] in
                viewer?.pointerSpeed = VNCSessionPreferences.speed(self.mac.id)
                viewer?.followCursorEnabled = VNCSessionPreferences.followCursor(self.mac.id)
                viewer?.quickActions = VNCSessionPreferences.actions(self.mac.id).map(\.native)
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
        func disconnect() {
            generation = UUID(); work?.cancel(); work = nil
            viewer?.session.stop(); login = nil; remember = false
        }
        func endSession() {
            activity.finish(); disconnect(); viewer?.stop(); stopObserving(); showMacs()
        }
    }
}
#endif
