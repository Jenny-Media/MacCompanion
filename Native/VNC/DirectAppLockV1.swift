#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class DirectAppLockV1 {
    static let shared = DirectAppLockV1()
    static let preferenceKey = "direct-client-require-device-unlock-v1"
    static let unlocked = Notification.Name("DirectClientUnlockedV1")
    private(set) var authenticating = false
    private(set) var allowed: Bool
    private(set) var message = "Unlock to access your Macs"
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
    var canAccess: Bool { !enabled || allowed }
    private let contextFactory: () -> LAContext
    private var context: LAContext?
    private var cover: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var attempt = UUID()
    init(contextFactory: @escaping () -> LAContext = { LAContext() }) { self.contextFactory = contextFactory; allowed = !UserDefaults.standard.bool(forKey: Self.preferenceKey) }
    func install() {
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers = [center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, !self.authenticating else { return }; self.showCover() }
            }, center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.background() }
            }, center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, !self.authenticating else { return }; if self.canAccess { self.hideCover() } else { self.authenticate() } }
            }]
        }
        if canAccess { hideCover() } else { showCover(); authenticate() }
    }
    func setEnabled(_ value: Bool) {
        if value {
            var error: NSError?
            guard contextFactory().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                message = "Set up an iPhone passcode before enabling app unlock."; return
            }
        }
        UserDefaults.standard.set(value, forKey: Self.preferenceKey)
        if value { allowed = false; showCover(); authenticate() }
        else { attempt = UUID(); context?.invalidate(); context = nil; authenticating = false; allowed = true; hideCover() }
    }
    func background() {
        guard enabled else { return }
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        allowed = false; message = "Unlock to access your Macs"; showCover()
    }
    func authenticate() {
        guard enabled, !allowed, !authenticating, UIApplication.shared.applicationState == .active else { return }
        showCover(); let id = UUID(); attempt = id
        let context = contextFactory(); self.context = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set up a device passcode in iPhone Settings, then try again."; return
        }
        authenticating = true; message = "Authenticating…"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mac Companion to access your saved Macs") { [weak self] success, _ in
            Task { @MainActor in
                guard let self, self.attempt == id else { return }
                self.context = nil; self.authenticating = false
                guard success, UIApplication.shared.applicationState != .background else { self.message = "Authentication cancelled. Tap Unlock to try again."; return }
                self.allowed = true; self.hideCover()
                NotificationCenter.default.post(name: Self.unlocked, object: nil)
            }
        }
    }
    private func showCover() {
        guard enabled else { return }
        if cover == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState != .unattached }) {
            let window = UIWindow(windowScene: scene); window.windowLevel = .alert + 1
            window.overrideUserInterfaceStyle = DirectAppearanceV1.shared.app.interfaceStyle
            window.rootViewController = UIHostingController(rootView: DirectUnlockCover(lock: self).directAppearance())
            window.rootViewController?.view.accessibilityViewIsModal = true
            window.backgroundColor = .systemBackground; cover = window
        }
        cover?.isHidden = false
    }
    private func hideCover() { cover?.isHidden = true }
}

private struct DirectUnlockCover: View {
    @Bindable var lock: DirectAppLockV1
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.largeTitle)
                Text("Mac Companion").font(.title2.bold())
                Text(lock.message).multilineTextAlignment(.center).foregroundStyle(.secondary)
                if lock.authenticating { ProgressView() }
                else { Button("Unlock", systemImage: "faceid") { lock.authenticate() }.buttonStyle(.glassProminent).accessibilityIdentifier("app-unlock") }
            }.padding(32).frame(maxWidth: 340).glassEffect(.regular, in: .rect(cornerRadius: 28))
        }.accessibilityIdentifier("app-privacy-cover")
    }
}
#endif
