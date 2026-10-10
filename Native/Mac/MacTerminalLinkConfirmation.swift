#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit

/// A link confirmation belongs to its Terminal window and ends on lock/close.
@MainActor final class MacTerminalLinkConfirmation {
    private(set) var alert: NSAlert?
    private weak var owner: NSWindow?
    private var generation = UUID()
    private var backgroundObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    init() {
        backgroundObserver = NotificationCenter.default.addObserver(forName: DirectClientPlatformV1.didEnterBackground, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }
    isolated deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
    func present(_ url: URL, in window: NSWindow, canOpen: @escaping @MainActor () -> Bool,
                 open: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        guard alert == nil, canOpen() else { return }
        let alert = NSAlert(), token = UUID()
        alert.messageText = "Open link in your browser?"; alert.informativeText = url.absoluteString
        alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
        self.alert = alert; owner = window; generation = token
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        alert.beginSheetModal(for: window) { [weak self, weak alert] response in
            guard let self, self.generation == token, self.alert === alert else { return }
            self.alert = nil; self.owner = nil; self.removeCloseObserver()
            alert?.informativeText = ""
            if response == .alertFirstButtonReturn, canOpen() { open(url) }
        }
    }
    func cancel() {
        generation = UUID()
        guard let alert else { return }
        self.alert = nil; let window = owner; owner = nil; removeCloseObserver()
        alert.informativeText = ""; alert.messageText = ""
        // Hide immediately, before AppKit completes the sheet's dismissal.
        alert.window.orderOut(nil)
        window?.endSheet(alert.window, returnCode: .cancel)
    }
    private func removeCloseObserver() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }; closeObserver = nil
    }
}
#endif
