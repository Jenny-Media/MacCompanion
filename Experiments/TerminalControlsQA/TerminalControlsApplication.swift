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
        let functionalTest = ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_FUNCTIONAL_TEST"] == "1"
        if functionalTest { UIView.setAnimationsEnabled(false) }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: TerminalControlsHarness().environment(DirectAppearanceV1.shared)
            .transaction { if functionalTest { $0.disablesAnimations = true; $0.animation = nil } })
        self.window = window; window.makeKeyAndVisible()
    }
}
@MainActor @Observable final class TerminalControlsMemory {
    static let itemID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    var writes = 0
    var dismissals = 0
    var failWrites = ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_FAIL_WRITE"] == "1"
    var remainingWriteFailures = ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_FAIL_WRITE_ONCE"] == "1" ? 1 : 0
    var remainingReadFailures = ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_FAIL_READ_ONCE"] == "1" ? 1 : 0
    var data: Data = {
        var profile = TerminalControlsProfile(actions: [
            TerminalControlAction(id: TerminalControlsMemory.itemID, title: "Project", kind: .text, text: "original", inRow: true)])
        // Transaction journeys start after migration; migration has its own
        // hosted tests. A failed explicit Save must not fail the initial load.
        profile.freezeKeyboardLayout()
        if ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_LEGACY_ROWS"] == "1" {
            // An unreleased saved layout with custom row options. Its rows
            // reset while its saved definitions and favorites remain intact.
            profile.rowsSchema = 2
            profile.keyboardRows = profile.resolvedRows
            let main = profile.keyboardRows!.firstIndex { $0.kind == .main }!
            profile.keyboardRows![main].alignment = .right
        }
        if ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_ROTATION"] == "1" {
            profile.actions = []
            profile.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", items: TerminalRowPreset.functions.items, alignment: .right, scrollStart: .right)]
        }
        if ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_FUTURE_FORMAT"] == "1" { profile.rowsSchema = TerminalControlsProfile.currentRowsSchema + 1 }
        return try! JSONEncoder().encode(profile)
    }()
    var profile: TerminalControlsProfile { try! JSONDecoder().decode(TerminalControlsProfile.self, from: data) }
    var store: TerminalControlsStore {
        .init(read: {
            if self.remainingReadFailures > 0 { self.remainingReadFailures -= 1; throw TerminalControlsStore.Failure.unreadable }
            return self.data
        }, write: {
            if self.remainingWriteFailures > 0 { self.remainingWriteFailures -= 1; throw TerminalControlsStore.Failure.unreadable }
            if self.failWrites { throw TerminalControlsStore.Failure.unreadable }
            self.data = $0; self.writes += 1
        }, legacyIDs: { [] })
    }
}
struct TerminalControlsHarness: View {
    private enum ControlsEntry: String, Identifiable {
        case settings, shortcuts, text
        var id: String { rawValue }
        var library: TerminalSavedItemsSection? {
            switch self { case .settings: nil; case .shortcuts: .shortcuts; case .text: .text }
        }
    }
    @State private var memory = TerminalControlsMemory()
    @State private var controlsEntry: ControlsEntry?
    @State private var pro = DirectProAccess.shared
    @State private var live = TerminalControlsLiveHost()
    @State private var showingTerminal = false
    @State private var showingRemote = false
    @State private var failure = ""
    @State private var reviewFinished = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 20) {
                Text(pro.hasPro ? "Pro ready" : "Checking Pro").accessibilityIdentifier("controls-qa-pro")
                Button("Refresh Pro") { Task { await pro.refresh() } }.accessibilityIdentifier("controls-qa-refresh-pro")
                Button("Customize Controls") { controlsEntry = .settings }.accessibilityIdentifier("controls-qa-open")
                Button("Manage Shortcuts") { controlsEntry = .shortcuts }.accessibilityIdentifier("controls-qa-shortcuts")
                Button("Manage Saved Text") { controlsEntry = .text }.accessibilityIdentifier("controls-qa-text")
                Button("Open Remote Controls") { showingRemote = true }.accessibilityIdentifier("controls-qa-remote")
                Button("Open Live Terminal") {
                    Task { do { try await live.prepare(); showingTerminal = true } catch { failure = String(describing: error) } }
                }.accessibilityIdentifier("controls-qa-live")
                if !failure.isEmpty { Text(failure) }
                Text("Saved items: \(memory.profile.actions.count)").accessibilityIdentifier("controls-qa-count")
                Text("Writes: \(memory.writes)").accessibilityIdentifier("controls-qa-writes")
                Text("Closes: \(memory.dismissals)").accessibilityIdentifier("controls-qa-closes")
                Text(memory.profile.actions.first?.title ?? "No saved items").accessibilityIdentifier("controls-qa-title")
                Text("Row: \(memory.profile.actions.first?.inRow == true ? "on" : "off"); Menu: \(memory.profile.actions.first?.inMenu == true ? "on" : "off")")
                    .accessibilityIdentifier("controls-qa-placements")
                Text("Rows: " + memory.profile.resolvedRows.map(\.title).joined(separator: " | "))
                    .accessibilityIdentifier("controls-qa-row-order")
                Text("Favorites: " + memory.profile.placed(.menu).map(\.title).joined(separator: " | "))
                    .accessibilityIdentifier("controls-qa-menu-order")
            }.frame(maxWidth: .infinity).padding(.vertical, 24) }.navigationTitle("Synthetic Controls QA")
                .sheet(item: $controlsEntry) { entry in
                    TerminalControlsSettings(store: memory.store, initialLibrary: entry.library,
                        close: { memory.dismissals += 1; controlsEntry = nil })
                }
                .fullScreenCover(isPresented: $showingRemote) { TerminalRemoteControlsHost(close: { showingRemote = false }) }
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
    let record = SSHTestRecord(echoInput: false, initialOutput: "\u{1b}[?25lSynthetic Terminal UX QA\r\nConnected to local test SSH server\r\n" + (ProcessInfo.processInfo.environment["MACCOMPANION_COMMAND_QA"] == "1" ? "\u{1b}[=3u" : ""))
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
        var shortcut = TerminalControlAction(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C004")!, title: "Prefix Ctrl-B", kind: .shortcut, inMenu: false)
        shortcut.character = 0x62; shortcut.modifiers = [0xffe3]; profile.actions.append(shortcut)
        profile.actions.append(.init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!, title: "Unicode Path", kind: .text, text: "中文😀", inMenu: false))
        if let url = Bundle.main.url(forResource: "terminal-compatibility-v1", withExtension: "json"),
           let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           let paste = json["paste"] as? [String: Any], let text = paste["text"] as? String {
            profile.actions.append(.init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!, title: "Multiline", kind: .text, text: text, inMenu: false))
        }
        var sequence = TerminalControlAction(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C005")!, title: "Review Sequence", kind: .shortcut, inRow: true, inMenu: true)
        sequence.steps = [.init(character: 0x62, modifiers: [0xffe3]), .init(kind: .text, text: "synthetic"), .init(character: 0xff0d)]
        profile.actions.append(sequence)
        for index in 1...40 { profile.actions.append(.init(title: "Saved Path \(index)", kind: .text, text: "/synthetic/path/\(index)", inMenu: false)) }
        if ProcessInfo.processInfo.environment["MACCOMPANION_CONTROLS_REPEATED_UTILITIES"] == "1" {
            profile.addPreset(.essentials, before: TerminalKeyboardRow.mainID)
        }
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
    var body: some View {
        VStack(alignment: .leading) {
            Text("Input: " + host.inputHex).accessibilityIdentifier("controls-qa-input")
            Text(host.session?.canSendUserInput == true && DirectProAccess.shared.hasPro ? "Input ready" : "Input paused").accessibilityIdentifier("controls-qa-input-ready")
        }.font(.caption2).padding(4).background(.regularMaterial)
    }
}


/// Uses the shipping remote adapter and editor with an in-memory transport.
/// Packet ownership/cancellation is tested against the real session separately.
private struct TerminalRemoteControlsHost: UIViewControllerRepresentable {
    let close: () -> Void
    func makeUIViewController(context: Context) -> TerminalRemoteControlsViewer { .init(close: close) }
    func updateUIViewController(_ controller: TerminalRemoteControlsViewer, context: Context) {}
}
@MainActor private final class TerminalRemoteControlsViewer: CompanionVNCViewer {
    let close: () -> Void
    private var controlsHost: RemoteMacControls!
    private let inputField = UITextField()
    private let output = UILabel()
    private var sent = 0
    private var epoch: UInt = 1
    private var available = true
    private var data: Data
    init(close: @escaping () -> Void) {
        self.close = close
        var profile = TerminalControlsProfile.remoteDefaults; profile.freezeKeyboardLayout()
        data = try! JSONEncoder().encode(profile)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() { view = UIView(); view.backgroundColor = .systemBackground }
    override func viewDidLoad() {
        preferenceID = "00000000-0000-4000-8000-00000000D001"
        setValue(CompanionVNCInterfaceFeedback(view: view), forKey: "keyFeedback")
        controlsHost = RemoteMacControls(viewer: self, store: .init(read: { self.data }, write: { self.data = $0 }, legacyIDs: { [] }, legacyActions: { [] }, family: .remoteMac))
        let edit = UIButton(type: .system); edit.setTitle("Customize Remote Keyboard", for: .normal)
        edit.accessibilityIdentifier = "remote-qa-edit"; edit.addAction(.init { [weak self] _ in self?.controlsHost.showSettings() }, for: .touchUpInside)
        let done = UIButton(type: .system); done.setTitle("Close Remote Controls", for: .normal)
        done.addAction(.init { [weak self] _ in self?.close() }, for: .touchUpInside)
        output.text = "Remote events: 0"; output.accessibilityIdentifier = "remote-qa-events"; output.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [edit, output, done]); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        let bar = controlsHost.bar; view.addSubview(bar)
        view.addSubview(inputField); inputField.frame = .init(x: 0, y: 0, width: 1, height: 1); inputField.alpha = 0.01
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
    }
    override func viewWillLayoutSubviews() {}
    override func viewDidLayoutSubviews() {}
    override var controlsEpoch: UInt { epoch }
    override func controlsInputAvailable() -> Bool { available }
    override func beginKeyboardCustomization() { available = false; epoch += 1; controlsHost.reset(); view.endEditing(true) }
    override func endKeyboardCustomization() { available = true }
    override func sendControlEvents(_ events: [[AnyHashable: Any]], completion: @escaping (Bool) -> Void) -> Bool {
        sent += events.count; output.text = "Remote events: \(sent)"; completion(true); return true
    }
    override func sendOrdinaryControlEvents(_ events: [[AnyHashable: Any]]) { sent += events.count; output.text = "Remote events: \(sent)" }
    override func toggleControlsKeyboard() { if inputField.isFirstResponder { inputField.resignFirstResponder() } else { inputField.becomeFirstResponder() }; controlsHost.keyboardFocused(inputField.isFirstResponder) }
}
