import UIKit
import SwiftUI
import Observation

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
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(pro.hasPro ? "Pro ready" : "Checking Pro").accessibilityIdentifier("controls-qa-pro")
                Button("Refresh Pro") { Task { await pro.refresh() } }.accessibilityIdentifier("controls-qa-refresh-pro")
                Button("Customize Controls") { editing = true }.accessibilityIdentifier("controls-qa-open")
                Text("Writes: \(memory.writes)").accessibilityIdentifier("controls-qa-writes")
                Text(memory.profile.actions[0].title).accessibilityIdentifier("controls-qa-title")
                Text("Row: \(memory.profile.actions[0].inRow ? "on" : "off"); Menu: \(memory.profile.actions[0].inMenu ? "on" : "off")")
                    .accessibilityIdentifier("controls-qa-placements")
            }.navigationTitle("Synthetic Controls QA")
                .sheet(isPresented: $editing) { TerminalControlsSettings(store: memory.store) }
        }.task { pro.start(); await pro.refresh() }
    }
}
