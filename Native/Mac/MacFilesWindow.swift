#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct DirectFilesWindowRequest: Codable, Hashable {
    let id: UUID
    let macID: UUID
    init(macID: UUID) { id = UUID(); self.macID = macID }
}
struct MacFilesWindow: View {
    @State private var session: DirectFilesSession
    init(mac: DirectMacRecordV1) { _session = State(initialValue: DirectFilesSession(mac: mac)) }
    var body: some View {
        DirectFilesView(mac: session.mac, session: session)
            .navigationTitle(session.mac.name + " · Files")
            .windowDismissBehavior(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults) ? .disabled : .automatic)
            .background(MacWindowLifetime { session.close() }.frame(width: 0, height: 0))
    }
}
#endif
