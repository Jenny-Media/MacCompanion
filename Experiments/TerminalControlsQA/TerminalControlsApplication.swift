import UIKit
import SwiftUI
import Observation
import Crypto
import NIO
import NIOSSH
import Citadel

// Simulator-only entry point. It presents the production settings sheet with
// in-memory persistence; no QA hooks or synthetic data enter the normal app.
@main final class TerminalControlsApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Terminal Controls QA", sessionRole: session.role)
        configuration.delegateClass = TerminalControlsScene.self; return configuration
    }
}
final class TerminalControlsScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        DirectAppearanceV1.shared.app = .light
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: TerminalControlsHarness().environment(DirectAppearanceV1.shared))
        self.window = window; window.makeKeyAndVisible()
    }
}
@MainActor @Observable final class TerminalControlsMemory {
    static let itemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    var writes = 0
    var dismissals = 0
    var data = try! JSONEncoder().encode(TerminalControlsProfile(actions: [
        TerminalControlAction(id: TerminalControlsMemory.itemID, title: "Project", kind: .text, text: "original", inRow: true)]))
    var profile: TerminalControlsProfile { try! JSONDecoder().decode(TerminalControlsProfile.self, from: data) }
    var store: TerminalControlsStore {
        .init(read: { self.data }, write: { self.data = $0; self.writes += 1 }, legacyIDs: { [] })
    }
}
struct TerminalControlsHarness: View {
    @State private var memory = TerminalControlsMemory()
    @State private var editing = false
    @State private var pro = DirectProAccess.shared
    @State private var live = TerminalControlsLiveHost()
    @State private var showingTerminal = false
    @State private var failure = ""
    @State private var reviewFinished = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 20) {
                Text(pro.hasPro ? "Pro ready" : "Checking Pro").accessibilityIdentifier("controls-qa-pro")
                Button("Refresh Pro") { Task { await pro.refresh() } }.accessibilityIdentifier("controls-qa-refresh-pro")
                Button("Customize Controls") { editing = true }.accessibilityIdentifier("controls-qa-open")
                Button("Open Live Terminal") {
                    Task { do { try await live.prepare(); showingTerminal = true } catch { failure = String(describing: error) } }
                }.accessibilityIdentifier("controls-qa-live")
                if !failure.isEmpty { Text(failure) }
                Text("Saved items: \(memory.profile.actions.count)").accessibilityIdentifier("controls-qa-count")
                Text("Writes: \(memory.writes)").accessibilityIdentifier("controls-qa-writes")
                Text("Closes: \(memory.dismissals)").accessibilityIdentifier("controls-qa-closes")
                Text(memory.profile.actions[0].title).accessibilityIdentifier("controls-qa-title")
                Text("Row: \(memory.profile.actions[0].inRow ? "on" : "off"); Menu: \(memory.profile.actions[0].inMenu ? "on" : "off")")
                    .accessibilityIdentifier("controls-qa-placements")
            }.frame(maxWidth: .infinity).padding(.vertical, 24) }.navigationTitle("Synthetic Controls QA")
                .sheet(isPresented: $editing) { TerminalControlsSettings(store: memory.store, close: { memory.dismissals += 1; editing = false }) }
                .fullScreenCover(isPresented: $showingTerminal) {
                    if let session = live.session {
                        DirectTerminalView(mac: session.mac, session: session, autoConnect: false, exit: { showingTerminal = false })
                            .overlay(alignment: .topLeading) {
                                TerminalControlsInputBadge(host: live).allowsHitTesting(false)
                            }
                            .overlay(alignment: .topTrailing) {
                                if ProcessInfo.processInfo.environment["MACCOMPANION_TERMINAL_CONTROLS_REVIEW"] == "1" {
                                    if reviewFinished { Text("Review finished").accessibilityIdentifier("controls-qa-review-finished") }
                                    else { Button("Finish Review") { reviewFinished = true }.buttonStyle(.bordered).accessibilityIdentifier("controls-qa-finish-review") }
                                }
                            }
                            .task { session.connect(username: "synthetic", password: "synthetic-only", remember: false) }
                            .onDisappear { live.close() }
                    }
                }
        }.task { pro.start(); await pro.refresh() }
    }
}

@MainActor @Observable final class TerminalControlsLiveHost {
    let record = SSHTestRecord(echoInput: false, initialOutput: "\u{1b}[?25lSynthetic Terminal UX QA\r\nConnected to local test SSH server\r\n")
    var session: DirectTerminalSession?
    private var server: Channel?
    var inputHex = ""
    func prepare() async throws {
        let key = NIOSSHPrivateKey(ed25519Key: .init())
        let record = record
        record.inputChanged = { [weak self] bytes in Task { @MainActor in self?.inputHex = bytes.map { String(format: "%02x", $0) }.joined() } }
        server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: SSHTestAuth(record))), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Terminal", addresses: ["127.0.0.1"], sshPort: server!.localAddress!.port!)
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        var profile = TerminalControlsProfile.defaults
        profile.actions.append(.init(id: TerminalControlsMemory.itemID, title: "Project", kind: .text, text: "original", inRow: true))
        profile.actions.append(.init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!, title: "Unicode Path", kind: .text, text: "中文😀", inMenu: false))
        if let url = Bundle.main.url(forResource: "terminal-compatibility-v1", withExtension: "json"),
           let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           let paste = json["paste"] as? [String: Any], let text = paste["text"] as? String {
            profile.actions.append(.init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!, title: "Multiline", kind: .text, text: text, inMenu: false))
        }
        for index in 1...40 { profile.actions.append(.init(title: "Saved Path \(index)", kind: .text, text: "/synthetic/path/\(index)", inMenu: false)) }
        try TerminalSecretStore.write(JSONEncoder().encode(profile), id: TerminalControlsStore.account, kind: TerminalControlsStore.kind)
        session = DirectTerminalSession(mac: mac); session?.saveMacRequested = false
    }
    func close() {
        if let session { session.stop(); try? TerminalSecretStore.remove(session.mac.id) }
        session = nil
        if let server { Task { try? await server.close() } }; server = nil
    }
}
private struct TerminalControlsInputBadge: View {
    let host: TerminalControlsLiveHost
    var body: some View { Text("Input: " + host.inputHex).font(.caption2).padding(4).background(.regularMaterial).accessibilityIdentifier("controls-qa-input") }
}
