#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct DirectFilesWindowRequest: Codable, Hashable {
    let id: UUID
    let macID: UUID
    init(macID: UUID) { id = UUID(); self.macID = macID }
}
struct MacFilesWindow: View {
    @State private var session: DirectFilesSession?
    init(mac: DirectMacRecordV1?, makeSession: @MainActor (DirectMacRecordV1) -> DirectFilesSession = { DirectFilesSession(mac: $0) }) {
        // Resolve library membership only when this window's state is created.
        // Later removal must not replace the owner or lose pending downloads.
        _session = State(initialValue: mac.map(makeSession))
    }
    var body: some View {
        if let session {
            DirectFilesView(mac: session.mac, session: session)
                .navigationTitle(session.mac.name + " · Files")
                .windowDismissBehavior(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults) ? .disabled : .automatic)
                .background(MacWindowLifetime { session.close() }.frame(width: 0, height: 0))
        } else {
            ContentUnavailableView("Mac unavailable", systemImage: "folder",
                description: Text("This Mac was removed from your library. Add it again in My Macs."))
        }
    }
}
#endif
