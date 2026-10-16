#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Observation
import SwiftUI

@MainActor @Observable final class MacToolApplicationModel {
    let library: DirectMacLibraryV1
    private(set) var coordinator: MacToolCoordinator?
    private let openScreenSharing: @MainActor (URL) async throws -> Void
    private let canAccess: @MainActor () -> Bool
    init(library: DirectMacLibraryV1 = DirectMacLibraryV1(),
         openScreenSharing: @escaping @MainActor (URL) async throws -> Void = MacScreenSharingApplication.open,
         canAccess: @escaping @MainActor () -> Bool = { DirectAppLockV1.shared.canAccess }) {
        self.library = library; self.openScreenSharing = openScreenSharing; self.canAccess = canAccess
    }
    static func snapshot(_ mac: DirectMacRecordV1) -> MacToolMachine {
        .init(id: mac.id, name: mac.name, addresses: mac.addresses, desktopPort: mac.port, sshPort: mac.sshPort)
    }
    func install(openTerminal: @escaping @MainActor (UUID, UUID) -> Void) {
        guard coordinator == nil else { return }
        let library = library
        coordinator = MacToolCoordinator(openDesktop: openScreenSharing, openTerminal: openTerminal,
            canAccess: canAccess, isCurrent: { machine in
                library.readable && library.macs.contains { Self.snapshot($0) == machine }
            })
    }
}

struct MacScreenSharingHandoffStatus: View {
    let macID: UUID
    let tools: MacToolApplicationModel
    var body: some View {
        let state = tools.coordinator?.states[macID] ?? .idle
        if state != .idle {
            Label(state.title, systemImage: state == .opening ? "hourglass" : "arrow.up.forward.app")
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityIdentifier("mac-screen-sharing-status")
        }
        if case .failed(let reason) = state {
            Text(reason.message).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// A restored old screen request is a local explanation, never an implicit launch.
struct MacExternalScreenSharingWindow: View {
    let macID: UUID
    let tools: MacToolApplicationModel
    @Environment(\.openWindow) private var openWindow
    @State private var pro = false
    @State private var window = MacWindowHandle()
    private var mac: DirectMacRecordV1? { tools.library.macs.first { $0.id == macID } }
    var body: some View {
        Group {
            if let mac {
                VStack(spacing: 18) {
                    Label(mac.name, systemImage: mac.family.symbol).font(.title)
                    Text("Screen Sharing opens in Apple Screen Sharing.").foregroundStyle(.secondary)
                    Text("Use its controls for the Mac screen. Terminal and Files stay in Mac Companion.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open in Screen Sharing", systemImage: "arrow.up.forward.app") { open(mac) }
                        .buttonStyle(.borderedProminent)
                        .disabled(tools.coordinator?.states[macID] == .opening)
                        .accessibilityIdentifier("mac-restored-screen-sharing-open")
                    MacScreenSharingHandoffStatus(macID: macID, tools: tools)
                }.padding(32)
            } else {
                ContentUnavailableView("Mac unavailable", systemImage: "desktopcomputer",
                    description: Text("This Mac was removed from your library."))
            }
        }.frame(minWidth: 520, minHeight: 360)
            .navigationTitle((mac?.name ?? "Mac") + " · Screen Sharing")
            .directAppearance().modifier(MacPrivacyCover())
            .onAppear {
                tools.install { [openWindow] macID, windowID in
                    openWindow(id: "direct-session", value: MacSessionRequest(id: windowID, macID: macID, mode: .terminal))
                }
            }
            .sheet(isPresented: $pro) { DirectProView().modifier(MacSheetPrivacyCover()) }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
                if !allowed { pro = false; tools.coordinator?.invalidate() }
            }
            .background(MacWindowReader(handle: window).frame(width: 0, height: 0))
            .onChange(of: tools.library.macs.map(\.id)) { _, ids in
                if !ids.contains(macID) { pro = false; window.window?.close() }
            }
            .onChange(of: window.window != nil) { _, attached in
                if attached && mac == nil { window.window?.close() }
            }
    }
    private func open(_ mac: DirectMacRecordV1) {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            guard DirectAppLockV1.shared.canAccess, tools.library.readable else { return }
            guard DirectProAccess.shared.canUseMac(mac.id, among: tools.library.macs.map(\.id)) else { pro = true; return }
            tools.coordinator?.open(MacToolApplicationModel.snapshot(mac), action: .desktop)
        }
    }
}
#endif
