#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

@MainActor @Observable final class VisionCloudDeletion {
    private(set) var confirmation: UUID?
    var scenePhase: ScenePhase = .inactive {
        didSet { if scenePhase != .active { invalidate() } }
    }
    func review(unlocked: Bool, busy: Bool) {
        guard scenePhase == .active, unlocked, !busy else { return }
        confirmation = UUID()
    }
    func cancel(_ token: UUID) { if confirmation == token { invalidate() } }
    func invalidate() { confirmation = nil }
    @discardableResult func confirm(_ token: UUID, cloud: DirectCloudSyncV1, unlocked: Bool) -> Bool {
        guard confirmation == token else { return false }
        confirmation = nil
        guard scenePhase == .active, unlocked, !cloud.busy else { return false }
        cloud.removeCloudCopies()
        return true
    }
}

/// A separate keyed host keeps a retired alert's callbacks tied to its own token.
struct VisionCloudDeletionAlert: View {
    let token: UUID
    let deletion: VisionCloudDeletion
    let cloud: DirectCloudSyncV1
    let done: () -> Void
    @State private var presented = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .alert("Delete Mac Data from iCloud?", isPresented: $presented) {
                Button("Delete iCloud Data", role: .destructive) {
                    if deletion.confirm(token, cloud: cloud, unlocked: DirectAppLockV1.shared.canAccess) { done() }
                }
                Button("Cancel", role: .cancel) { deletion.cancel(token) }
            } message: {
                Text("This deletes the app’s synced Mac data and turns sync off here. Your local Macs and logins are kept. Other devices with sync enabled can upload data again.")
            }
            .onAppear { presented = true }
    }
}
#endif
