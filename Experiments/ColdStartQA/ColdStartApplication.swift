import UIKit
import SwiftUI
import Observation
import LocalAuthentication
import NIO
import NIOSSH
import Crypto

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
        let host = UIHostingController(rootView: ColdStartControls(model: model).dynamicTypeSize(.medium))
        host.view.backgroundColor = .clear; controls.rootViewController = host
        self.controls = controls; controls.isHidden = ProcessInfo.processInfo.arguments.contains("--unlock-layout") || ProcessInfo.processInfo.arguments.contains("--connect-flow")
    }
}
final class ColdStartAuthentication: LAContext {
    var reply: ((Bool, Error?) -> Void)?
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String,
                                 reply: @escaping (Bool, Error?) -> Void) { self.reply = reply }
}
final class ColdStartLibraryReadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    func wait() { condition.lock(); defer { condition.unlock() }; while !released { condition.wait() } }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
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
    let libraryRead = ColdStartLibraryReadGate()
    var stage = "Starting"
    private var sessionPeer: Channel?
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let activity = ColdStartActivity(), authentication = ColdStartAuthentication(), store = ColdStartStore()
        self.activity = activity; self.authentication = authentication; self.store = store
        needsAuthentication = arguments.contains("--inactive-auth")
        timeout = arguments.contains("--fast-timeout") ? .seconds(2) : .seconds(5)
        let defaults = UserDefaults(suiteName: "dev.maccompanion.coldstartqa")!
        defaults.removePersistentDomain(forName: "dev.maccompanion.coldstartqa")
        defaults.set(needsAuthentication, forKey: DirectAppLockV1.preferenceKey)
        lock = DirectAppLockV1(contextFactory: { authentication }, defaults: defaults, unlockMethod: { .passcode },
                               isActive: { activity.active }, isBackground: { false }, protectedDataAvailable: { true })
        pro = DirectProAccess(defaults: defaults, readEntitlements: { await store.read() })
        let url = URL.cachesDirectory.appending(path: "cold-start-synthetic-\(UUID()).json")
        let seeded = DirectMacLibraryV1(url: url)
        if !arguments.contains("--empty-library") {
            _ = seeded.save(id: nil, name: "Free Mac", address: "127.0.0.1")
            _ = seeded.save(id: nil, name: "Second Mac", address: "127.0.0.1")
            if arguments.contains("--row-modes-review") {
                VNCSessionPreferences.setDesktopSize(0, mac: seeded.macs[1].id)
                _ = seeded.save(id: nil, name: "Terminal Mac", addresses: ["terminal-fixture.local"], preferredConnection: .terminal)
                _ = seeded.save(id: nil, name: "Trackpad Mac", addresses: ["trackpad-fixture.local"], preferredConnection: .trackpad)
            }
        }
        if arguments.contains("--saved-login-tests"), let mac = seeded.macs.first {
            // Test-only credentials in the QA app's Keychain, never real accounts.
            try? DirectMacAccessStore.write(.init(login: .init(username: "synthetic-account", password: "synthetic-password")), id: mac.id)
        }
        let gate = libraryRead
        if !arguments.contains("--held-library") { gate.release() }
        library = DirectMacLibraryV1(url: url, loadInBackground: !arguments.contains("--progress-review"), readInitialRecords: {
            gate.wait(); return try DirectMacLibraryV1.readRecords(at: $0)
        })
    }
    func begin() async {
        if ProcessInfo.processInfo.arguments.contains("--connected-session-review") {
            do {
                while library.loading { try await Task.sleep(for: .milliseconds(10)) }
                let key = NIOSSHPrivateKey(ed25519Key: .init())
                sessionPeer = try await ColdStartSSHFixture.start(key: key)
                guard let mac = library.macs.first, let port = sessionPeer?.localAddress?.port else { return }
                _ = library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: port, preferredConnection: .terminal)
                try DirectMacAccessStore.write(.init(login: .init(username: "synthetic", password: "synthetic-only")), id: mac.id)
                try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: key.publicKey), id: mac.id)
                stage = "Connected-session fixture ready"
            } catch { stage = "Connected-session fixture failed" }
            return
        }
        guard needsAuthentication else { stage = "Active; purchases pending"; return }
        for _ in 0..<100 {
            if authentication.reply != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        activity.active = false; lock.becameInactive()
        if ProcessInfo.processInfo.arguments.contains("--manual-auth") { stage = "Authenticating; inactive"; return }
        await completeAuthentication()
        for _ in 0..<100 {
            if !lock.authenticating { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        stage = "Authenticated; awaiting activation"
    }
    func completeAuthentication() async {
        authentication.reply?(true, nil)
        for _ in 0..<100 {
            if !lock.authenticating { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        stage = "Authenticated; awaiting activation"
    }
    func activate() { activity.active = true; lock.receivedActivationNotification(); stage = "Active; purchases pending" }
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
                    Text(model.lock.unlockTimingToken == nil && model.lock.unlockTimings.records.last?.outcome == .success ? "Timing ready" : "Timing pending")
                        .accessibilityIdentifier("qa-timing-status")
                    Text(model.lock.canResumeRemoteSession ? "Remote ready" : "Remote paused")
                        .accessibilityIdentifier("qa-remote-ready")
                }.font(.caption)
                Text(model.lock.unlockTimings.records.last?.events.map { $0.phase.rawValue }.joined(separator: ",") ?? "")
                    .font(.caption2).lineLimit(1).accessibilityIdentifier("qa-timing-phases")

                HStack {
                    Button("Load") { model.libraryRead.release() }.accessibilityIdentifier("qa-load-macs")
                    Button("Finish Auth") { Task { await model.completeAuthentication() } }.accessibilityIdentifier("qa-finish-auth")
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
        if ProcessInfo.processInfo.arguments.contains("--progress-review") {
            PresentationProgressReview(model: model)
        } else if ProcessInfo.processInfo.arguments.contains("--unlock-layout") {
            // Render the actual cover without QA controls obscuring its bottom action.
            DirectUnlockCover(lock: model.lock)
        } else {
            DirectMacLibraryRootV1(library: model.library, appLock: model.lock, pro: model.pro, accessTimeout: model.timeout)
                .padding(.bottom, ProcessInfo.processInfo.arguments.contains("--connect-flow") ? 0 : 130)
                .environment(\.scenePhase, .inactive)
                .task { await model.begin() }
        }
    }
}

// Real connection views with a held, synthetic progress state. No socket,
// credentials or remote input is used for presentation screenshots.
struct PresentationProgressReview: View {
    let model: ColdStartProbe
    @State private var panel = DirectConnectionPanelHost()
    @State private var terminal: DirectTerminalSession
    @State private var showing = true
    init(model: ColdStartProbe) {
        self.model = model
        let terminal = DirectTerminalSession(mac: model.library.macs.first!)
        terminal.connecting = true
        _terminal = State(initialValue: terminal)
    }
    var body: some View {
        DirectMacLibraryRootV1(library: model.library, appLock: model.lock, pro: model.pro)
            .background(DirectConnectionPanelAnchor(host: panel).frame(width: 0, height: 0))
            .overlay {
                if showing {
                    if ProcessInfo.processInfo.arguments.contains("--trust-review") {
                        DirectConnectionPanelContent(host: panel, cancel: cancel, preferredHeight: 620, preventsDismissal: true) {
                            TerminalServerTrustView(macName: "Free Mac", fingerprint: "SHA256:synthetic-simulator-fingerprint", answer: { _ in cancel() }).directAppearance()
                        }
                    } else if ProcessInfo.processInfo.arguments.contains("--terminal-review") {
                        DirectTerminalView(mac: model.library.macs.first!, session: terminal, autoConnect: false, connectionPanel: panel, exit: cancel)
                    } else { PresentationDesktopProgress(panel: panel, cancel: cancel) }
                }
            }

    }
    private func cancel() { panel.close(); showing = false }
}
struct PresentationDesktopProgress: UIViewControllerRepresentable {
    let panel: DirectConnectionPanelHost
    let cancel: () -> Void
    func makeUIViewController(context: Context) -> CompanionVNCViewer {
        let viewer = CompanionVNCViewer(); viewer.macName = "Free Mac"; viewer.connectionPanelHost = panel
        viewer.restoredDesktopSizePreset = ProcessInfo.processInfo.arguments.contains("--mirror-review") ? 0 : 2
        viewer.macsHandler = cancel
        viewer.loadViewIfNeeded(); viewer.setValue(true, forKey: "starting")
        viewer.showConnectionProgress("Opening encrypted connection…")
        return viewer
    }
    func updateUIViewController(_ controller: CompanionVNCViewer, context: Context) {}
    static func dismantleUIViewController(_ controller: CompanionVNCViewer, coordinator: ()) { controller.stop() }
}

// Loopback-only SSH peer for the production-root accessibility journey. The
// normal handshake, host pin, password authentication and shell still run.
private enum ColdStartSSHFixture {
    static func start(key: NIOSSHPrivateKey) async throws -> Channel {
        try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: ColdStartSSHAuthentication())),
                allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in
                    child.pipeline.addHandler(ColdStartSSHShell())
                }))
        }.bind(host: "127.0.0.1", port: 0).get()
    }
}
private final class ColdStartSSHAuthentication: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .password(let login) = request.request, request.username == "synthetic", login.password == "synthetic-only" {
            responsePromise.succeed(.success)
        } else { responsePromise.succeed(.failure) }
    }
}
private final class ColdStartSSHShell: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is SSHChannelRequestEvent.PseudoTerminalRequest {
            context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
        } else if event is SSHChannelRequestEvent.ShellRequest {
            context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(ByteBuffer(string: "synthetic-ready\r\n")))), promise: nil)
        } else { context.fireUserInboundEventTriggered(event) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(wrapOutboundOut(unwrapInboundIn(data)), promise: nil)
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
