#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class DirectAppLockV1 {
    static let shared = DirectAppLockV1(unlockTimings: DirectUnlockTimingsV1(persist: true))
    static let preferenceKey = "direct-client-require-device-unlock-v1"
    static let gracePreferenceKey = "direct-client-unlock-grace-seconds-v1"
    static let unlocked = Notification.Name("DirectClientUnlockedV1")
    static let locked = Notification.Name("DirectClientLockedV1")
    private(set) var authenticating = false
    private(set) var allowed: Bool
    private(set) var foregroundActive: Bool
    private(set) var protectedDataReady: Bool
    private(set) var graceSeconds: Int
    private(set) var message = "Unlock to access your Macs"
    var enabled: Bool { defaults.bool(forKey: Self.preferenceKey) }
    var canAccess: Bool { !enabled || (allowed && protectedDataAvailable()) }
    // A current authentication result can release local UI during system dismissal.
    // Remote-session resume still requires actual foreground activation.
    var canInteract: Bool { canAccess && (foregroundActive || authenticationSucceeded) }
    var canResumeRemoteSession: Bool { canAccess && foregroundActive }
    var contentVisible: Bool { canAccess || foregroundGracePending }
    var privacyCoverVisible: Bool { cover?.isHidden == false }
    var unlockTransitionVisible: Bool { authenticating }
    var unlockButtonTitle: String { authenticating ? "Unlocking…" : "Unlock" }
    var unlockButtonEnabled: Bool { enabled && !allowed && !unlockTransitionVisible && foregroundActive && protectedDataReady && protectedDataAvailable() }
    @ObservationIgnored let unlockTimings: DirectUnlockTimingsV1
    private(set) var unlockTimingToken: UUID?
    private let contextFactory: () -> LAContext
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let isActive: () -> Bool
    private let isBackground: () -> Bool
    private let protectedDataAvailable: () -> Bool
    private var graceStarted: TimeInterval?
    private var graceDeadline: TimeInterval?
    private var unlockNeedsPublication = false
    private var authenticationSucceeded = false
    private var authenticationAttempted = false
    private var foregroundGracePending = false
    private var context: LAContext?
    private var cover: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var attempt = UUID()
    init(contextFactory: @escaping () -> LAContext = { LAContext() }, defaults: UserDefaults = .standard,
         now: (() -> TimeInterval)? = nil, unlockTimings: DirectUnlockTimingsV1? = nil,
         isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
         isBackground: @escaping () -> Bool = { UIApplication.shared.applicationState == .background },
         protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.contextFactory = contextFactory; self.defaults = defaults
        self.unlockTimings = unlockTimings ?? DirectUnlockTimingsV1()
        let origin = ContinuousClock.now
        self.now = now ?? {
            let elapsed = origin.duration(to: ContinuousClock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
        self.isActive = isActive; self.isBackground = isBackground; self.protectedDataAvailable = protectedDataAvailable
        foregroundActive = isActive(); protectedDataReady = protectedDataAvailable()
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
                MainActor.assumeIsolated { self?.receivedActivationNotification() }
            }, center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.protectedDataLost() }
            }, center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            }]
        }
        // Reappearance is automatic; use the same admission/retry policy as
        // activation rather than starting a new request after cancellation.
        becameActive()
        if canAccess { hideCover() } else { showCover() }
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
        retireUnlockTiming(.preferenceChanged)
        discardGrace(); defaults.set(value, forKey: Self.preferenceKey)
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false; unlockNeedsPublication = false
        authenticationSucceeded = false; authenticationAttempted = false
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
    func becameInactive() {
        foregroundActive = false
        // This exception belongs only to the just-accepted authentication.
        authenticationSucceeded = false
    }
    func background() {
        foregroundActive = false
        foregroundGracePending = false
        guard enabled else { return }
        if allowed && !unlockNeedsPublication && graceSeconds > 0 && protectedDataAvailable() {
            let time = now(); graceStarted = time; graceDeadline = time + TimeInterval(graceSeconds)
        } else if authenticating || authenticationSucceeded || unlockNeedsPublication { discardGrace() }
        revokeAccess()
    }
    func protectedDataLost() {
        protectedDataReady = false
        discardGrace(); guard enabled else { return }; revokeAccess()
    }
    private func revokeAccess() {
        retireUnlockTiming(.revoked)
        foregroundGracePending = false
        attempt = UUID(); context?.invalidate(); context = nil; authenticating = false
        unlockNeedsPublication = false; authenticationSucceeded = false; authenticationAttempted = false
        allowed = false; message = "Unlock to access your Macs"; showCover()
        NotificationCenter.default.post(name: Self.locked, object: nil)
    }
    func receivedActivationNotification() {
        unlockTimings.mark(.activationNotification, token: unlockTimingToken)
        becameActive()
    }
    private func retireUnlockTiming(_ outcome: DirectUnlockTimingsV1.Outcome) {
        unlockTimings.finish(outcome, token: unlockTimingToken); unlockTimingToken = nil
    }
    func recordUnlockDisplayTick(token: UUID, phase: DirectUnlockTimingsV1.Phase) {
        guard unlockTimingToken == token, canResumeRemoteSession, contentVisible, !privacyCoverVisible else { return }
        guard [.libraryDisplayTick, .desktopDisplayTick, .terminalDisplayTick].contains(phase) else { return }
        unlockTimings.mark(phase, token: token); unlockTimings.finish(.success, token: token)
        unlockTimingToken = nil
    }
    func becameActive() {
        foregroundActive = isActive(); protectedDataReady = protectedDataAvailable()
        guard foregroundActive, !authenticating else { return }
        if authenticationSucceeded {
            guard enabled, protectedDataAvailable(), !isBackground() else { revokeAccess(); return }
            authenticationSucceeded = false; allowed = true; publishUnlock()
            return
        }
        if canAccess {
            hideCover()
            if unlockNeedsPublication { publishUnlock() }
            return
        }
        if graceValid {
            discardGrace(); allowed = true; publishUnlock()
        } else {
            discardGrace()
            if !authenticationAttempted { authenticate() }
        }
    }
    private func publishUnlock() {
        unlockTimings.mark(.activeAdmission, token: unlockTimingToken)
        unlockNeedsPublication = false; hideCover()
        unlockTimings.mark(.coverRemoved, token: unlockTimingToken)
        unlockTimings.mark(.unlockNotification, token: unlockTimingToken)
        NotificationCenter.default.post(name: Self.unlocked, object: nil)
        unlockTimings.mark(.unlockObserversReturned, token: unlockTimingToken)
        unlockTimings.stopActivationProbe()
        unlockTimings.checkpoint()
    }
    func authenticate() {
        guard enabled, !allowed, !authenticating, !authenticationSucceeded, isActive(), protectedDataAvailable() else { return }
        discardGrace()
        showCover(); authenticationAttempted = true
        let id = UUID(); attempt = id
        unlockTimingToken = unlockTimings.begin(active: isActive())
        let timingToken = unlockTimingToken, callbackClock = unlockTimings.callbackClock
        let context = contextFactory(); self.context = context
        // evaluatePolicy reports unavailable policy asynchronously. Repeating
        // canEvaluatePolicy here adds a blocking IPC before every real attempt.
        authenticating = true; message = "Authenticating…"
        unlockTimings.mark(.evaluationIssued, token: timingToken)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mac Companion to access your saved Macs") { [weak self] success, error in
            let callbackInstant = callbackClock()
            let passcodeMissing = !success && (error as? LAError)?.code == .passcodeNotSet
            Task { @MainActor in
                guard let self, self.attempt == id else { return }
                self.unlockTimings.mark(.authenticationCallback, token: timingToken, at: callbackInstant)
                self.unlockTimings.mark(.authenticationHandled, token: timingToken)
                // Consume this result once; a duplicate or retired callback
                // cannot replace a newer attempt or reopen a revoked transition.
                self.attempt = UUID()
                let completedContext = self.context
                self.context = nil; self.authenticating = false
                guard success, self.protectedDataAvailable(), !self.isBackground() else {
                    self.retireUnlockTiming(passcodeMissing ? .unavailable : .failed)
                    self.message = passcodeMissing ? "Set up a device passcode in iPhone Settings, then try again."
                        : "App locked. Tap Unlock to try again."
                    return
                }
                // Dropping our reference does not explicitly end the framework's
                // presentation. Dispose only after accepting and retiring this
                // reply. Cleanup itself cannot grant local or remote access.
                completedContext?.invalidate()
                self.unlockTimings.mark(.authenticationContextInvalidated, token: timingToken)
                // Reveal prepared content and enable local controls in the same turn,
                // without waiting for UIKit's authentication-dismissal activation.
                self.authenticationSucceeded = true
                self.allowed = true; self.unlockNeedsPublication = true
                self.foregroundActive = self.isActive()
                self.unlockTimings.mark(.localAdmission, token: timingToken)
                self.hideCover()
                self.unlockTimings.mark(.coverRemoved, token: timingToken)
                self.unlockTimings.startActivationProbe(token: timingToken) { [weak self] in
                    guard let self else { return (false, true) }
                    return (self.isActive(), self.isBackground())
                }
                // Only remote-session publication waits for activation. An already-
                // active success needs no additional lifecycle notification.
                self.becameActive()
                self.unlockTimings.checkpoint()
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
                        Text(lock.unlockTransitionVisible ? "Unlock to access your Macs" : lock.message)
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { lock.authenticate() } label: {
                            HStack {
                                if lock.unlockTransitionVisible { ProgressView().accessibilityHidden(true) }
                                else { Image(systemName: DirectUnlockMethod.current().symbol) }
                                Text(lock.unlockButtonTitle)
                            }
                        }.buttonStyle(.glassProminent).disabled(!lock.unlockButtonEnabled)
                            .accessibilityLabel(lock.unlockButtonTitle).accessibilityIdentifier("app-unlock")
                    }.padding(32).frame(maxWidth: 340).glassEffect(.regular, in: .rect(cornerRadius: 28))
                        .padding(16).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }.accessibilityIdentifier("app-privacy-cover")
    }
}
#endif
