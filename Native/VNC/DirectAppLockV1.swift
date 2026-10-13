#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class DirectAppLockV1 {
    static let shared = DirectAppLockV1()
    static let preferenceKey = "direct-client-require-device-unlock-v1"
    static let gracePreferenceKey = "direct-client-unlock-grace-seconds-v1"
    static let unlocked = Notification.Name("DirectClientUnlockedV1")
    static let locked = Notification.Name("DirectClientLockedV1")
    private(set) var authenticating = false
    private(set) var allowed: Bool
    private(set) var foregroundActive: Bool
    private(set) var graceSeconds: Int
    private(set) var message = "Unlock to access your Macs"
    var enabled: Bool { defaults.bool(forKey: Self.preferenceKey) }
    var canAccess: Bool { !enabled || (allowed && protectedDataAvailable()) }
    var canInteract: Bool { canAccess && foregroundActive }
    var contentVisible: Bool { canAccess || foregroundGracePending }
    var privacyCoverVisible: Bool { cover?.isHidden == false }
    private let contextFactory: () -> LAContext
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let isActive: () -> Bool
    private let isBackground: () -> Bool
    private let protectedDataAvailable: () -> Bool
    private var graceStarted: TimeInterval?
    private var graceDeadline: TimeInterval?
    private var unlockNeedsPublication = false
    private var foregroundGracePending = false
    private var context: LAContext?
    private var cover: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var attempt = UUID()
    init(contextFactory: @escaping () -> LAContext = { LAContext() }, defaults: UserDefaults = .standard,
         now: (() -> TimeInterval)? = nil,
         isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
         isBackground: @escaping () -> Bool = { UIApplication.shared.applicationState == .background },
         protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.contextFactory = contextFactory; self.defaults = defaults
        let origin = ContinuousClock.now
        self.now = now ?? {
            let elapsed = origin.duration(to: ContinuousClock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
        self.isActive = isActive; self.isBackground = isBackground; self.protectedDataAvailable = protectedDataAvailable
        foregroundActive = isActive()
        allowed = !defaults.bool(forKey: Self.preferenceKey)
        graceSeconds = defaults.integer(forKey: Self.gracePreferenceKey) == 30 ? 30 : 0
    }
    func install() {
        foregroundActive = isActive()
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers = [center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameInactive() }
            }, center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.prepareForeground() }
            }, center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.background() }
            }, center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            }, center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.protectedDataLost() }
            }, center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            }]
        }
        if canAccess { hideCover() } else { showCover(); authenticate() }
    }
    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        cover?.isHidden = true
    }
    func setEnabled(_ value: Bool) {
        if value {
            var error: NSError?
            guard contextFactory().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                message = "Set up an iPhone passcode before enabling app unlock."; return
            }
        }
        discardGrace(); defaults.set(value, forKey: Self.preferenceKey)
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false; unlockNeedsPublication = false
        if value { allowed = false; NotificationCenter.default.post(name: Self.locked, object: nil); showCover(); authenticate() }
        else {
            allowed = true; hideCover(); foregroundActive = isActive()
            if foregroundActive { publishUnlock() } else { unlockNeedsPublication = true }
        }
    }
    func setGraceSeconds(_ value: Int) {
        graceSeconds = value == 30 ? 30 : 0; defaults.set(graceSeconds, forKey: Self.gracePreferenceKey)
        discardGrace()
    }
    private func discardGrace() { graceStarted = nil; graceDeadline = nil; foregroundGracePending = false }
    private var graceValid: Bool {
        guard let start = graceStarted, let deadline = graceDeadline else { return false }
        let time = now()
        return time >= start && time < deadline && protectedDataAvailable()
    }
    func prepareForeground() {
        guard !isBackground() else { return }
        // Presentation can precede active admission. Do not publish unlock or
        // grant credential/input access while UIKit is still inactive.
        foregroundGracePending = enabled && !allowed && graceValid
        if canAccess || foregroundGracePending { hideCover() }
        else { showCover() }
    }
    func becameInactive() { foregroundActive = false }
    func background() {
        foregroundActive = false
        foregroundGracePending = false
        guard enabled else { return }
        if allowed && !unlockNeedsPublication && graceSeconds > 0 && protectedDataAvailable() {
            let time = now(); graceStarted = time; graceDeadline = time + TimeInterval(graceSeconds)
        } else if authenticating || unlockNeedsPublication { discardGrace() }
        revokeAccess()
    }
    func protectedDataLost() {
        discardGrace(); guard enabled else { return }; revokeAccess()
    }
    private func revokeAccess() {
        foregroundGracePending = false
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        unlockNeedsPublication = false
        allowed = false; message = "Unlock to access your Macs"; showCover()
        NotificationCenter.default.post(name: Self.locked, object: nil)
    }
    func becameActive() {
        foregroundActive = isActive()
        guard foregroundActive, !authenticating else { return }
        if canAccess {
            hideCover()
            if unlockNeedsPublication { publishUnlock() }
            return
        }
        if graceValid {
            discardGrace(); allowed = true; publishUnlock()
        } else { discardGrace(); authenticate() }
    }
    private func publishUnlock() {
        unlockNeedsPublication = false; hideCover()
        NotificationCenter.default.post(name: Self.unlocked, object: nil)
    }
    func authenticate() {
        guard enabled, !allowed, !authenticating, isActive(), protectedDataAvailable() else { return }
        discardGrace()
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
                guard success, self.protectedDataAvailable(), !self.isBackground() else { self.message = "App locked. Tap Unlock to try again."; return }
                self.foregroundActive = self.isActive(); self.allowed = true
                self.hideCover()
                if self.isActive() { self.publishUnlock() }
                else { self.unlockNeedsPublication = true }
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
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: "lock.fill").font(.largeTitle)
                        Text("Mac Companion").font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(lock.message).multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if lock.authenticating { ProgressView() }
                        else { Button("Unlock", systemImage: DirectUnlockMethod.current().symbol) { lock.authenticate() }.buttonStyle(.glassProminent).accessibilityIdentifier("app-unlock") }
                    }.padding(32).frame(maxWidth: 340).glassEffect(.regular, in: .rect(cornerRadius: 28))
                        .padding(16).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }.accessibilityIdentifier("app-privacy-cover")
    }
}
#endif
