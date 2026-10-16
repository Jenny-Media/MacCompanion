#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit

@MainActor enum MacScreenSharingApplication {
    static func open(_ url: URL) async throws {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenSharing") else {
            throw MacScreenSharingFailure.missingApplication
        }
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: .init()) { app, error in
                if app != nil && error == nil { reply.resume() }
                else { reply.resume(throwing: MacScreenSharingFailure.launchFailed) }
            }
        }
    }
}
#endif
