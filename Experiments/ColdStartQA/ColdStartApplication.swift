import UIKit
import SwiftUI
import Observation
import LocalAuthentication

// Disposable simulator entry point; never linked into a release target.
@main final class ColdStartApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Synthetic Cold Start", sessionRole: session.role)
        configuration.delegateClass = ColdStartScene.self; return configuration
    }
}
final class ColdStartScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var controls: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let model = ColdStartProbe(), window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ColdStartShell(model: model).directAppearance())
        self.window = window; window.makeKeyAndVisible()
        let controls = ColdStartControlWindow(windowScene: scene)
        controls.windowLevel = .alert + 2; controls.backgroundColor = .clear
        let host = UIHostingController(rootView: ColdStartControls(model: model))
        host.view.backgroundColor = .clear; controls.rootViewController = host
        self.controls = controls; controls.isHidden = false
    }
}
final class ColdStartAuthentication: LAContext {
    var reply: ((Bool, Error?) -> Void)?
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String,
                                 reply: @escaping (Bool, Error?) -> Void) { self.reply = reply }
}
@MainActor final class ColdStartStore {
    var replies: [CheckedContinuation<DirectProSnapshot, Never>] = []
    func read() async -> DirectProSnapshot { await withCheckedContinuation { replies.append($0) } }
    func resolve() {
        let pending = replies; replies = []
        pending.forEach { $0.resume(returning: DirectProSnapshot(lifetime: true)) }
    }
}
@MainActor @Observable final class ColdStartActivity { var active = true }
@MainActor @Observable final class ColdStartProbe {
    let library: DirectMacLibraryV1
    let lock: DirectAppLockV1
    let pro: DirectProAccess
    let activity: ColdStartActivity
    let authentication: ColdStartAuthentication
    let store: ColdStartStore
    let needsAuthentication: Bool
    let timeout: Duration
    var stage = "Starting"
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let activity = ColdStartActivity(), authentication = ColdStartAuthentication(), store = ColdStartStore()
        self.activity = activity; self.authentication = authentication; self.store = store
        needsAuthentication = arguments.contains("--inactive-auth")
        timeout = arguments.contains("--fast-timeout") ? .seconds(2) : .seconds(5)
        let defaults = UserDefaults(suiteName: "dev.maccompanion.coldstartqa")!
        defaults.removePersistentDomain(forName: "dev.maccompanion.coldstartqa")
        defaults.set(needsAuthentication, forKey: DirectAppLockV1.preferenceKey)
        lock = DirectAppLockV1(contextFactory: { authentication }, defaults: defaults,
                               isActive: { activity.active }, isBackground: { false }, protectedDataAvailable: { true })
        pro = DirectProAccess(defaults: defaults, readEntitlements: { await store.read() })
        let url = URL.cachesDirectory.appending(path: "cold-start-synthetic-\(UUID()).json")
        library = DirectMacLibraryV1(url: url)
        if !arguments.contains("--empty-library") {
            _ = library.save(id: nil, name: "Free Mac", address: "127.0.0.1")
            _ = library.save(id: nil, name: "Second Mac", address: "127.0.0.1")
        }
    }
    func begin() async {
        guard needsAuthentication else { stage = "Active; purchases pending"; return }
        for _ in 0..<100 {
            if authentication.reply != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        activity.active = false; lock.becameInactive(); authentication.reply?(true, nil)
        for _ in 0..<100 {
            if !lock.authenticating { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        stage = "Authenticated; awaiting activation"
    }
    func activate() { activity.active = true; lock.becameActive(); stage = "Active; purchases pending" }
    func background() { activity.active = false; lock.background(); stage = "Background" }
}
final class ColdStartControlWindow: UIWindow {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.y >= bounds.maxY - 130 && super.point(inside: point, with: event)
    }
}
struct ColdStartControls: View {
    @State var model: ColdStartProbe
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Text(model.stage).accessibilityIdentifier("qa-startup-stage")
                HStack {
                    Button("Activate") { model.activate() }.accessibilityIdentifier("qa-activate")
                    Button("Background") { model.background() }.accessibilityIdentifier("qa-background")
                    Button("Resolve Store") { model.store.resolve() }.accessibilityIdentifier("qa-resolve-store")
                }.buttonStyle(.bordered)
            }.frame(height: 100).frame(maxWidth: .infinity).background(.background)
        }.ignoresSafeArea(.keyboard)
    }
}
struct ColdStartShell: View {
    @State var model: ColdStartProbe
    var body: some View {
        DirectMacLibraryRootV1(library: model.library, appLock: model.lock, pro: model.pro, accessTimeout: model.timeout)
            .padding(.bottom, 130)
            .environment(\.scenePhase, .inactive)
            .task { await model.begin() }
    }
}
