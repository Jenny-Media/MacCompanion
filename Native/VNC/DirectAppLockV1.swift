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
    private enum Admission {
        case disabled(needsPublication: Bool)
        case locked(attempted: Bool)
        case evaluating(UUID, LAContext)
        case awaitingActivation(localInteraction: Bool)
        case unlocked
    }
    private var admission: Admission
    var authenticating: Bool { if case .evaluating = admission { true } else { false } }
    var allowed: Bool {
        switch admission {
        case .disabled, .awaitingActivation, .unlocked: true
        case .locked, .evaluating: false
        }
    }
    private var localInteractionDuringActivation: Bool {
        if case .awaitingActivation(let value) = admission { return value }
        return false
    }
    private(set) var foregroundActive: Bool
    private(set) var protectedDataReady: Bool
    private(set) var graceSeconds: Int
    private(set) var message = "Unlock to access your Macs"
    var enabled: Bool { defaults.bool(forKey: Self.preferenceKey) }
    var canAccess: Bool { !enabled || (allowed && protectedDataAvailable()) }
    // A current authentication result can release local UI during system dismissal.
    // Remote-session resume still requires actual foreground activation.
    var canInteract: Bool { canAccess && (foregroundActive || localInteractionDuringActivation) }
    var canResumeRemoteSession: Bool { canAccess && foregroundActive }
    var contentVisible: Bool { canAccess || foregroundGracePending }
    var privacyCoverVisible: Bool { cover?.isHidden == false }
    var unlockTransitionVisible: Bool { authenticating }
    var unlockButtonTitle: String { authenticating ? "Unlocking…" : "Unlock" }
    var unlockButtonEnabled: Bool { enabled && !allowed && !unlockTransitionVisible && foregroundActive && protectedDataReady && protectedDataAvailable() }
    func availableUnlockMethod() async -> DirectUnlockMethod { await unlockMethod() }
    @ObservationIgnored let unlockTimings: DirectUnlockTimingsV1
    private(set) var unlockTimingToken: UUID?
    private let contextFactory: () -> LAContext
    @ObservationIgnored private let unlockMethod: @Sendable () async -> DirectUnlockMethod
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let isActive: () -> Bool
    private let isBackground: () -> Bool
    private let protectedDataAvailable: () -> Bool
    private enum Grace {
        case none
        case retained(Range<TimeInterval>)
        case preview(Range<TimeInterval>)

        var window: Range<TimeInterval>? {
            switch self {
            case .none: nil
            case .retained(let window), .preview(let window): window
            }
        }
    }
    private var grace = Grace.none
    private var foregroundGracePending: Bool { if case .preview = grace { true } else { false } }
    private var cover: UIWindow?
    private var observers: [NSObjectProtocol] = []
    init(contextFactory: @escaping () -> LAContext = { LAContext() }, defaults: UserDefaults = .standard,
         unlockMethod: @escaping @Sendable () async -> DirectUnlockMethod = { await DirectUnlockMethod.available() },
         now: (() -> TimeInterval)? = nil, unlockTimings: DirectUnlockTimingsV1? = nil,
         isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
         isBackground: @escaping () -> Bool = { UIApplication.shared.applicationState == .background },
         protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.contextFactory = contextFactory; self.defaults = defaults; self.unlockMethod = unlockMethod
        self.unlockTimings = unlockTimings ?? DirectUnlockTimingsV1()
        let origin = ContinuousClock.now
        self.now = now ?? {
            let elapsed = origin.duration(to: ContinuousClock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
        self.isActive = isActive; self.isBackground = isBackground; self.protectedDataAvailable = protectedDataAvailable
        foregroundActive = isActive(); protectedDataReady = protectedDataAvailable()
        admission = defaults.bool(forKey: Self.preferenceKey) ? .locked(attempted: false) : .disabled(needsPublication: false)
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
        if value {
            replaceAdmission(.locked(attempted: false))
            NotificationCenter.default.post(name: Self.locked, object: nil)
            showCover()
            authenticate()
        } else {
            foregroundActive = isActive()
            replaceAdmission(.disabled(needsPublication: !foregroundActive))
            hideCover()
            if foregroundActive { publishUnlock() }
        }
    }
    func setGraceSeconds(_ value: Int) {
        graceSeconds = value == 30 ? 30 : 0; defaults.set(graceSeconds, forKey: Self.gracePreferenceKey)
        discardGrace()
    }
    private func discardGrace() { grace = .none }
    private var validGraceWindow: Range<TimeInterval>? {
        guard let window = grace.window, window.contains(now()), protectedDataAvailable() else { return nil }
        return window
    }
    func prepareForeground() {
        guard !isBackground() else { return }
        // Preview can precede activation but never grants credential or input access.
        if enabled, !allowed, let window = validGraceWindow { grace = .preview(window) }
        else if case .preview(let window) = grace { grace = .retained(window) }
        if canAccess || foregroundGracePending { hideCover() }
        else { showCover() }
    }
    func becameInactive() {
        foregroundActive = false
        if case .awaitingActivation = admission { admission = .awaitingActivation(localInteraction: false) }
    }
    func background() {
        foregroundActive = false
        if case .preview(let window) = grace { grace = .retained(window) }
        guard enabled else { return }
        switch admission {
        case .unlocked where graceSeconds > 0 && protectedDataAvailable():
            let start = now()
            grace = .retained(start..<(start + TimeInterval(graceSeconds)))
        case .evaluating, .awaitingActivation:
            discardGrace()
        case .locked, .disabled, .unlocked:
            break
        }
        revokeAccess()
    }
    func protectedDataLost() {
        protectedDataReady = false
        discardGrace(); guard enabled else { return }; revokeAccess()
    }
    private func replaceAdmission(_ next: Admission) {
        let previous = admission
        admission = next
        if case .evaluating(_, let context) = previous { context.invalidate() }
    }
    private func revokeAccess() {
        retireUnlockTiming(.revoked)
        replaceAdmission(.locked(attempted: false))
        message = "Unlock to access your Macs"; showCover()
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
        guard foregroundActive else { return }
        switch admission {
        case .evaluating:
            return
        case .awaitingActivation:
            guard enabled, protectedDataAvailable(), !isBackground() else { revokeAccess(); return }
            admission = .unlocked
            publishUnlock()
        case .disabled(let needsPublication):
            hideCover()
            if needsPublication {
                admission = .disabled(needsPublication: false)
                publishUnlock()
            }
        case .unlocked:
            if canAccess { hideCover() }
        case .locked(let attempted):
            let eligible = validGraceWindow != nil
            discardGrace()
            if eligible {
                admission = .unlocked
                publishUnlock()
            } else if !attempted { authenticate() }
        }
    }
    private func publishUnlock() {
        unlockTimings.mark(.activeAdmission, token: unlockTimingToken)
        hideCover()
        unlockTimings.mark(.coverRemoved, token: unlockTimingToken)
        unlockTimings.mark(.unlockNotification, token: unlockTimingToken)
        NotificationCenter.default.post(name: Self.unlocked, object: nil)
        unlockTimings.mark(.unlockObserversReturned, token: unlockTimingToken)
        unlockTimings.stopActivationProbe()
        unlockTimings.checkpoint()
    }
    func authenticate() {
        guard enabled, case .locked = admission, isActive(), protectedDataAvailable() else { return }
        discardGrace()
        showCover()
        let id = UUID()
        unlockTimingToken = unlockTimings.begin(active: isActive())
        let timingToken = unlockTimingToken, callbackClock = unlockTimings.callbackClock
        let context = contextFactory()
        admission = .evaluating(id, context)
        // evaluatePolicy reports unavailable policy asynchronously. Repeating
        // canEvaluatePolicy here adds a blocking IPC before every real attempt.
        message = "Authenticating…"
        unlockTimings.mark(.evaluationIssued, token: timingToken)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mac Companion to access your saved Macs") { [weak self] success, error in
            let callbackInstant = callbackClock()
            let passcodeMissing = !success && (error as? LAError)?.code == .passcodeNotSet
            Task { @MainActor in
                guard let self, case .evaluating(let current, let completedContext) = self.admission, current == id else { return }
                self.unlockTimings.mark(.authenticationCallback, token: timingToken, at: callbackInstant)
                self.unlockTimings.mark(.authenticationHandled, token: timingToken)
                // Consume this result once; a duplicate or retired callback
                // cannot replace a newer attempt or reopen a revoked transition.
                guard success, self.protectedDataAvailable(), !self.isBackground() else {
                    self.admission = .locked(attempted: true)
                    self.retireUnlockTiming(passcodeMissing ? .unavailable : .failed)
                    self.message = passcodeMissing ? "Set up a device passcode in iPhone Settings, then try again."
                        : "Unlock to access your Macs."
                    return
                }
                // Dropping our reference does not explicitly end the framework's
                // presentation. Dispose only after accepting and retiring this
                // reply. Cleanup itself cannot grant local or remote access.
                self.admission = .awaitingActivation(localInteraction: true)
                completedContext.invalidate()
                self.unlockTimings.mark(.authenticationContextInvalidated, token: timingToken)
                // Reveal prepared content and enable local controls in the same turn,
                // without waiting for UIKit's authentication-dismissal activation.
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
        // The privacy window must not inherit a responder from the sign-in
        // sheet below it, including while Face ID temporarily deactivates us.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window !== cover { window.endEditing(true) }
        }
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

struct DirectUnlockCover: View {
    @Bindable var lock: DirectAppLockV1
    @State private var method = DirectUnlockMethod.passcode
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    VStack(spacing: 20) {
                        Image("MacCompanionMark")
                            .resizable().scaledToFit().frame(width: 80, height: 80)
                            .clipShape(.rect(cornerRadius: 18))
                            .accessibilityHidden(true)
                        Text("Mac Companion").font(.title.bold()).multilineTextAlignment(.center)
                            .accessibilityIdentifier("app-unlock-brand")
                        Text(method == .unavailable ? method.returningDescription : lock.unlockTransitionVisible ? "Unlock to access your Macs." : lock.message)
                            .font(.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: 360)
                    Spacer(minLength: 48)
                    Button { lock.authenticate() } label: {
                        HStack(spacing: 10) {
                            if lock.unlockTransitionVisible { ProgressView().tint(.secondary).accessibilityHidden(true) }
                            else { Image(systemName: method.symbol) }
                            Text(lock.unlockTransitionVisible ? lock.unlockButtonTitle : method.buttonTitle)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.headline).frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 6)
                            .foregroundStyle(lock.unlockTransitionVisible ? Color.primary : .white)
                            .background(lock.unlockTransitionVisible ? Color(uiColor: .secondarySystemGroupedBackground) : .blue, in: Capsule())
                    }.buttonStyle(.plain)
                        .disabled(!lock.unlockButtonEnabled || method == .unavailable).frame(maxWidth: 400)
                        .accessibilityLabel(lock.unlockTransitionVisible ? lock.unlockButtonTitle : method.buttonTitle)
                        .accessibilityIdentifier("app-unlock")
                }.frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 64))
                    .padding(.horizontal, 28).padding(.vertical, 32)
            }.scrollBounceBehavior(.basedOnSize)
        }.ignoresSafeArea(.keyboard)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .task(id: [scenePhase == .active, lock.authenticating]) {
                let refreshed = await lock.availableUnlockMethod()
                guard !Task.isCancelled else { return }
                method = refreshed
            }
            .accessibilityIdentifier("app-privacy-cover")
    }
}
#endif
