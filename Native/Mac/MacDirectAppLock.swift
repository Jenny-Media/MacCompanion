#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import LocalAuthentication
import Observation

@MainActor @Observable final class DirectAppLockV1 {
    static let shared = DirectAppLockV1()
    static let preferenceKey = "direct-client-require-device-unlock-v1"
    static let unlocked = Notification.Name("DirectClientUnlockedV1")
    private(set) var authenticating = false
    private(set) var allowed: Bool
    private(set) var message = "Unlock to access your Macs"
    private(set) var enabled: Bool
    var canAccess: Bool { !enabled || allowed }
    private var context: LAContext?
    private var attempt = UUID()
    private var observers: [NSObjectProtocol] = []
    init() {
        let value = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        enabled = value; allowed = !value
    }
    func install() {
        guard observers.isEmpty else { return }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
                    self?.background()
                }
            })
        }
        if !canAccess { authenticate() }
    }
    func setEnabled(_ value: Bool) {
        if value {
            var error: NSError?
            guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                message = "Set up a Mac login password before enabling app unlock."; return
            }
        }
        enabled = value; UserDefaults.standard.set(value, forKey: Self.preferenceKey)
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        allowed = !value
        if value { authenticate() }
    }
    func background() {
        guard enabled else { return }
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        allowed = false; message = "Unlock to access your Macs"
    }
    func authenticate() {
        guard enabled, !allowed, !authenticating else { return }
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Mac authentication is unavailable. Try again after unlocking your Mac."; return
        }
        let id = UUID(); attempt = id; self.context = context; authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mac Companion to access your saved Macs") { [weak self] success, _ in
            Task { @MainActor in
                guard let self, self.attempt == id else { return }
                self.context = nil; self.authenticating = false; self.allowed = success
                self.message = success ? "Unlocked" : "App locked. Tap Unlock to try again."
                if success { NotificationCenter.default.post(name: Self.unlocked, object: nil) }
            }
        }
    }
}
#endif
