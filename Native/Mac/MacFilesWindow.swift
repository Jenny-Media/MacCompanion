#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct DirectFilesWindowRequest: Codable, Hashable {
    let id: UUID
    let macID: UUID
    init(macID: UUID) { id = UUID(); self.macID = macID }
}
struct MacFilesWindow: View {
    let mac: DirectMacRecordV1
    @State private var session: DirectFilesSession
    init(mac: DirectMacRecordV1) { self.mac = mac; _session = State(initialValue: DirectFilesSession(mac: mac)) }
    var body: some View {
        DirectFilesView(mac: mac, session: session)
            .navigationTitle(mac.name + " · Files")
            .windowDismissBehavior(session.transferActive ? .disabled : .automatic)
            .background(MacWindowLifetime { session.close() }.frame(width: 0, height: 0))
    }
}
#endif
