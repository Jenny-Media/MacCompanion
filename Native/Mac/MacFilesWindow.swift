#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct DirectFilesWindowRequest: Codable, Hashable {
    let id: UUID
    let macID: UUID
    let terminalID: UUID?
    let connectionGeneration: UUID?
    init(macID: UUID, terminalID: UUID? = nil, connectionGeneration: UUID? = nil) {
        id = UUID(); self.macID = macID; self.terminalID = terminalID; self.connectionGeneration = connectionGeneration
    }
}
struct MacFilesWindow: View {
    @State private var session: DirectFilesSession?
    var contextProvider: (@MainActor () -> DirectFilesConnectionContext?)?
    @State private var window = MacWindowHandle()
    init(mac: DirectMacRecordV1?, contextProvider: (@MainActor () -> DirectFilesConnectionContext?)? = nil, makeSession: @MainActor (DirectMacRecordV1) -> DirectFilesSession = { DirectFilesSession(mac: $0) }) {
        // Resolve library membership only when this window's state is created.
        // Later removal must not replace the owner or lose pending downloads.
        self.contextProvider = contextProvider
        _session = State(initialValue: mac.map(makeSession))
    }
    private func filesView(_ session: DirectFilesSession) -> DirectFilesView {
        var view = DirectFilesView(mac: session.mac, session: session, closeOwnerWindow: { window.window?.close() })
        view.contextProvider = contextProvider
        return view
    }
    var body: some View {
        if let session {
            // Confirmed closure must not depend on the last rendered dismissal
            // policy. Close only this window after Done has checked its owner.
            filesView(session)
                .navigationTitle(session.mac.name + " · Files")
                .windowDismissBehavior(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults) ? .disabled : .automatic)
                .background(MacWindowReader(handle: window).frame(width: 0, height: 0))
                .background(MacWindowLifetime { session.close() }.frame(width: 0, height: 0))
                .onChange(of: window.window != nil) { _, attached in
                    if attached, session.shouldCloseAfterRemoval { window.window?.close() }
                }
        } else {
            ContentUnavailableView("Mac unavailable", systemImage: "folder",
                description: Text("This Mac was removed from your library. Add it again in My Macs."))
        }
    }
}
#endif
