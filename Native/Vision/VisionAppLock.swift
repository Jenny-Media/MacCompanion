#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// App-wide authentication, rendered by every scene, rather than a cover on
/// whichever connected UIWindowScene happens to be enumerated first.
@MainActor @Observable final class DirectAppLockV1 {
    static let shared = DirectAppLockV1()
    static let preferenceKey = "direct-client-require-device-unlock-v1"
    static let unlocked = Notification.Name("DirectClientUnlockedV1")
    private(set) var authenticating = false
    private(set) var allowed = !UserDefaults.standard.bool(forKey: preferenceKey)
    private(set) var covered = false
    private(set) var message = "Unlock to access your Macs"
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
    var canAccess: Bool { !covered && (!enabled || allowed) }
    private var context: LAContext?
    private var attempt = UUID()
    private var observers: [NSObjectProtocol] = []
    private var covers: [String: UIWindow] = [:]
    var method: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "device authentication" }
        return context.biometryType == .opticID ? "Optic ID or your device passcode" : "device authentication"
    }
    func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let event = note.name
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if event == UIApplication.didBecomeActiveNotification { self.foreground() }
                    else if event == UIApplication.didEnterBackgroundNotification { self.background() }
                    else { self.covered = true; self.updateCovers() }
                }
            })
        }
        for name in [UIScene.willDeactivateNotification, UIScene.didActivateNotification, UIScene.didDisconnectNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let scene = note.object as? UIWindowScene, event = note.name
                MainActor.assumeIsolated {
                    guard let self, let scene else { return }
                    let id = scene.session.persistentIdentifier
                    if event == UIScene.didDisconnectNotification {
                        self.covers[id]?.isHidden = true; self.covers[id]?.rootViewController = nil; self.covers.removeValue(forKey: id)
                    } else if event == UIScene.willDeactivateNotification { self.covers[id]?.isHidden = false }
                    else { self.updateCovers() }
                }
            })
        }
    }
    func register(_ scene: UIWindowScene) {
        let id = scene.session.persistentIdentifier
        if covers[id] == nil {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: VisionUnlockPanel(lock: self).directAppearance())
            window.rootViewController?.view.accessibilityViewIsModal = true
            covers[id] = window
        }
        updateCovers()
    }
    private func updateCovers() {
        for window in covers.values { window.isHidden = canAccess && window.windowScene?.activationState == .foregroundActive }
    }
    func foreground() { covered = false; updateCovers() }
    func setEnabled(_ value: Bool) {
        if value, !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            message = "Set up device authentication before enabling app unlock."; return
        }
        UserDefaults.standard.set(value, forKey: Self.preferenceKey)
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        allowed = !value
        updateCovers()
        if value { authenticate() }
    }
    func background() {
        covered = true; attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        if enabled { allowed = false; message = "Unlock to access your Macs" }
        updateCovers()
    }
    func authenticate() {
        guard enabled, !allowed, !authenticating, UIApplication.shared.applicationState == .active else { return }
        let context = LAContext(), token = UUID(); attempt = token; self.context = context
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            message = "Device authentication is unavailable. Check Vision Pro Settings and try again."; return
        }
        authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mac Companion to access your saved Macs") { [weak self] success, _ in
            Task { @MainActor in
                guard let self, self.attempt == token else { return }
                self.context = nil; self.authenticating = false
                guard success, UIApplication.shared.applicationState != .background else {
                    self.message = "App locked. Tap Unlock to try again."; return
                }
                self.allowed = true
                self.updateCovers()
                NotificationCenter.default.post(name: Self.unlocked, object: nil)
            }
        }
    }
}

struct VisionPrivacy: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var lock = DirectAppLockV1.shared
    func body(content: Content) -> some View {
        let hidden = phase != .active || !lock.canAccess
        ZStack {
            content.opacity(hidden ? 0 : 1).disabled(hidden).accessibilityHidden(hidden)
            if hidden {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.largeTitle)
                    Text("Mac Companion").font(.title)
                    Text(lock.message).foregroundStyle(.secondary)
                    if phase == .active, lock.enabled, !lock.allowed {
                        if lock.authenticating { ProgressView() }
                        else { Button("Unlock with \(lock.method)") { lock.authenticate() }.accessibilityIdentifier("vision-unlock") }
                    }
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial).accessibilityIdentifier("vision-privacy-cover")
            }
        }.onAppear { lock.install() }
            .background(VisionSceneCapture { if let scene = $0 { lock.register(scene) } })
    }
}
private struct VisionUnlockPanel: View {
    @Bindable var lock: DirectAppLockV1
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.largeTitle)
            Text("Mac Companion").font(.title)
            Text(lock.message).foregroundStyle(.secondary)
            if lock.enabled && !lock.allowed {
                if lock.authenticating { ProgressView() }
                else { Button("Unlock with \(lock.method)") { lock.authenticate() } }
            }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial).accessibilityIdentifier("vision-scene-privacy-cover")
    }
}
extension View { func visionPrivacy() -> some View { modifier(VisionPrivacy()) } }

enum VisionSensitiveLifecycle {
    static func interrupts(phase: ScenePhase, locked: Bool) -> Bool { phase == .background || locked }
}
private struct VisionSensitiveState: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var lock = DirectAppLockV1.shared
    let interrupt: @MainActor () -> Void
    private var locked: Bool { lock.enabled && !lock.allowed }
    func body(content: Content) -> some View {
        content
            .onAppear { if VisionSensitiveLifecycle.interrupts(phase: phase, locked: locked) { interrupt() } }
            .onChange(of: phase) { _, value in
                if VisionSensitiveLifecycle.interrupts(phase: value, locked: locked) { interrupt() }
            }
            .onChange(of: locked) { _, value in if value { interrupt() } }
    }
}
extension View {
    func visionSensitiveState(_ interrupt: @escaping @MainActor () -> Void) -> some View {
        modifier(VisionSensitiveState(interrupt: interrupt))
    }
}
#endif
