import AppKit

@MainActor enum AppleScreenSharing {
    static func open(_ url: URL) async throws {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenSharing") else {
            throw WorkspaceFailure.missingApplication
        }
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: .init()) { app, error in
                if app != nil && error == nil { reply.resume() }
                else { reply.resume(throwing: WorkspaceFailure.launchFailed) }
            }
        }
    }
}
