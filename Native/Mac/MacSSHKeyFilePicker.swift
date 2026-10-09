#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit

@MainActor final class MacSSHKeyFilePicker {
    private(set) var panel: NSOpenPanel?
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
    static func makePanel(sshFolder: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Import SSH Private Key"; panel.prompt = "Import"
        panel.message = "Choose an Ed25519 OpenSSH private key, such as id_ed25519."
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true; panel.allowsOtherFileTypes = true
        // No extension filter: OpenSSH private keys commonly have no extension.
        if sshFolder { panel.directoryURL = home.appendingPathComponent(".ssh", isDirectory: true) }
        return panel
    }
    func choose(in window: NSWindow, sshFolder: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        guard panel == nil, DirectAppLockV1.shared.canAccess else { return }
        let panel = Self.makePanel(sshFolder: sshFolder, home: home), token = UUID()
        self.panel = panel; owner = window; generation = token
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self, self.generation == token, self.panel === panel else { return }
            self.panel = nil; self.owner = nil; self.removeCloseObserver()
            guard DirectAppLockV1.shared.canAccess else { return }
            if response == .OK, let url = panel?.url { completion(.success(url)) }
            else { completion(.failure(CancellationError())) }
        }
    }
    func cancel() {
        generation = UUID()
        guard let panel else { return }
        self.panel = nil; let window = owner; owner = nil; removeCloseObserver()
        panel.orderOut(nil); window?.endSheet(panel, returnCode: .cancel)
        panel.cancel(nil)
    }
    private func removeCloseObserver() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }; closeObserver = nil
    }
}
#endif
