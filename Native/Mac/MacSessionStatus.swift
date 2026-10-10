#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

// Live Activities are iOS-only. Shared SSH session ownership uses this Mac
// adapter; native window chrome presents its connection state instead.
@MainActor protocol RemoteSessionActivityBackend {}
@MainActor struct ActivityKitSessionBackend: RemoteSessionActivityBackend {}
enum RemoteSessionActivityAttributes { enum Kind { case desktop, terminal } }
@MainActor final class VNCSessionActivityController {
    init(mac: DirectMacRecordV1, kind: RemoteSessionActivityAttributes.Kind = .desktop,
         defaults: UserDefaults = .standard, backend: any RemoteSessionActivityBackend = ActivityKitSessionBackend()) {}
    func setPhase(_ value: String) {}
    func setForeground(_ value: Bool) {}
    func finish() {}
    func ownsActivity(_ id: String) -> Bool { false }
    func waitForUpdates() async {}
}
#endif
