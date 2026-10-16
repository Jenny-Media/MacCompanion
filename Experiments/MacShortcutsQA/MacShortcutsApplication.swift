import UIKit
import SwiftUI

// Simulator-only host: real production rows and editor, with recorded route
// callbacks instead of network connections. No production entry-point hooks.
@main final class MacShortcutsApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Synthetic Mac Shortcuts", sessionRole: session.role)
        config.delegateClass = MacShortcutsScene.self; return config
    }
}
final class MacShortcutsScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let folder = URL.cachesDirectory.appending(path: "synthetic-mac-shortcuts")
        if ProcessInfo.processInfo.arguments.contains("--reset-library") { try? FileManager.default.removeItem(at: folder) }
        let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"), removeLogin: { _ in })
        if library.macs.isEmpty {
            _ = library.save(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011"), name: "First Mac", address: "first.invalid")
            _ = library.save(id: UUID(uuidString: "00000000-0000-0000-0000-000000000022"), name: "Second Mac", address: "second.invalid")
        }
        let window = UIWindow(windowScene: scene)
        if ProcessInfo.processInfo.arguments.contains("--dark") { window.overrideUserInterfaceStyle = .dark }
        var root = AnyView(MacShortcutsHarness(library: library))
        if ProcessInfo.processInfo.arguments.contains("--large-text") { root = AnyView(root.dynamicTypeSize(.accessibility3)) }
        let host = UIHostingController(rootView: root)
        if ProcessInfo.processInfo.arguments.contains("--large-text") {
            // A presented sheet obtains its Dynamic Type from UIKit traits.
            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        }
        window.rootViewController = host
        self.window = window; window.makeKeyAndVisible()
    }
}
private struct MacShortcutsHarness: View {
    @State var library: DirectMacLibraryV1
    @State private var editor: DirectMacRecordV1?
    @State private var mode: EditMode = .inactive
    @State private var last = "No connection opened"
    var body: some View {
        NavigationStack {
            List {
                ForEach(library.macs) { mac in
                    DirectMacLibraryRow(mac: mac, reordering: mode.isEditing, canChooseFreeMac: false,
                        open: { last = mac.name + " · " + $0.title }, browseFiles: { last = "Files" },
                        edit: { editor = mac }, remove: { last = "Removal confirmation" }, chooseFreeMac: {})
                }.onMove { _ = library.move(fromOffsets: $0, toOffset: $1) }
                Text(last).accessibilityIdentifier("qa-shortcut-route")
            }.environment(\.editMode, $mode)
                .navigationTitle("My Macs")
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button(mode.isEditing ? "Done" : "Reorder") { mode = mode.isEditing ? .inactive : .active }
                        .accessibilityIdentifier("macs-edit-order")
                } }
                .sheet(item: $editor) {
                    DirectMacEditorV1(mac: $0, library: library)
                        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility3 : .large)
                }
        }
    }
}
