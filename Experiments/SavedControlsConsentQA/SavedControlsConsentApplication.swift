import SwiftUI

private struct NoCloudEffects: DirectCloudTransport {
    func read() throws -> [Data] { throw DirectCloudError.storage }
    func write(_ data: Data, account: String) throws { throw DirectCloudError.storage }
    func removeAll() throws { throw DirectCloudError.storage }
}

/// Private QA target only. Injecting a writer bypasses shared cloud engines.
@main @MainActor struct SavedControlsConsentApplication: App {
    let cloud: DirectCloudSyncV1
    init() {
        let name = "dev.maccompanion.savedcontrolsqa.fixture"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: DirectCloudSyncV1.enabledKey)
        cloud = DirectCloudSyncV1(defaults: defaults,
            url: URL.temporaryDirectory.appending(path: UUID().uuidString + ".json"),
            transport: NoCloudEffects(), writerID: UUID())
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DirectSyncSecurityForm(cloud: cloud).navigationTitle("Sync & Security")
                    .navigationBarTitleDisplayMode(.inline)
            }.directAppearance()
        }
    }
}
