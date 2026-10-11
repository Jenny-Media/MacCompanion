#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

@main struct MacCompanionDirectApplication: App {
    @State private var library = DirectMacLibraryV1()
    var body: some Scene {
        Window("My Macs", id: "machine-library") {
            MacMachineLibraryView(library: library).directAppearance().modifier(MacPrivacyCover())
                .task {
                    DirectProAccess.shared.start()
                    DirectCloudSyncV1.shared.attach(library)
                    library.discovery.start()
                }
        }.defaultSize(width: 900, height: 600)
        WindowGroup("Connection", id: "direct-session", for: MacSessionRequest.self) { $request in
            if let request {
                MacSessionWindow(request: request, library: library)
            } else {
                ContentUnavailableView("Mac unavailable", systemImage: "desktopcomputer",
                    description: Text("This Mac was removed from your library. Add it again in My Macs."))
                    .frame(minWidth: 520, minHeight: 360).directAppearance().modifier(MacPrivacyCover())
            }
        }.defaultSize(width: 1000, height: 680)
            .commands { MacClientCommands() }
        WindowGroup("Files", id: "direct-files", for: DirectFilesWindowRequest.self) { $request in
            if let request, let mac = library.macs.first(where: { $0.id == request.macID }) {
                MacFilesWindow(mac: mac).directAppearance().modifier(MacPrivacyCover())
            } else {
                ContentUnavailableView("Mac unavailable", systemImage: "folder")
            }
        }.defaultSize(width: 720, height: 640)
        Settings {
            MacSettingsView()
        }
    }
}

private struct MacClientCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("My Macs") { openWindow(id: "machine-library") }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
#endif
