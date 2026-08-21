import SwiftUI

@main
struct ClientUIHarnessApp: App {
    @StateObject private var lifecycle = HarnessApplicationLifecycleModel()

    var body: some Scene {
        WindowGroup {
            HarnessContentView()
                .environmentObject(lifecycle)
                .task { await lifecycle.start() }
        }
    }
}
