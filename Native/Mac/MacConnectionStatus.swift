#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import Observation
import SwiftUI

enum MacConnectionPhase: String {
    case signIn, connecting, connected, disconnected
    var title: String {
        switch self {
        case .signIn: "Sign In"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnected: "Not Connected"
        }
    }
    var symbol: String { self == .connected ? "checkmark.circle.fill" : self == .connecting ? "arrow.triangle.2.circlepath" : "circle" }
}

// Presentation only: no transport, credentials, persistence or cloud records.
@MainActor @Observable final class MacConnectionRegistry {
    static let shared = MacConnectionRegistry()
    struct Entry: Identifiable {
        let id: UUID
        let macID: UUID
        let mode: DirectMacConnection
        var phase: MacConnectionPhase
        let window: MacWindowHandle
    }
    private(set) var entries: [Entry] = []
    func update(id: UUID, macID: UUID, mode: DirectMacConnection, phase: MacConnectionPhase, window: MacWindowHandle) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            guard entries[index].macID == macID, entries[index].mode == mode else { return }
            entries[index].phase = phase
        } else { entries.append(.init(id: id, macID: macID, mode: mode, phase: phase, window: window)) }
    }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    func connections(for macID: UUID) -> [Entry] { entries.filter { $0.macID == macID } }
}

struct MacConnectionStatusBar: View {
    let phase: MacConnectionPhase
    let service: String
    let addresses: [String]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: phase.symbol).foregroundStyle(phase == .connected ? Color.green : Color.secondary)
            Text(phase.title)
            Text("· " + service).foregroundStyle(.secondary)
            Spacer()
            Text(addresses.count == 1 ? "Configured: " + addresses[0] : "\(addresses.count) configured addresses")
                .foregroundStyle(.secondary).lineLimit(1)
                .help("Configured addresses:\n" + addresses.joined(separator: "\n"))
        }.font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar).accessibilityElement(children: .combine)
            .accessibilityIdentifier("mac-connection-status")
    }
}

struct MacCloudStatusView: View {
    @State private var cloud = DirectCloudSyncV1.shared
    @Environment(\.openSettings) private var openSettings
    private var title: String {
        if !cloud.enabled { return "iCloud Sync Off" }
        if cloud.recovery != nil { return "iCloud Sync Needs Attention" }
        return cloud.busy ? "Refreshing iCloud…" : "iCloud Sync On"
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if cloud.busy { ProgressView().controlSize(.small) }
            else { Image(systemName: !cloud.enabled ? "icloud.slash" : cloud.recovery != nil ? "exclamationmark.icloud" : "icloud") }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout).accessibilityIdentifier("mac-icloud-status")
                Text(!cloud.enabled ? "Saved Macs stay on this device." : cloud.recovery != nil
                     ? "Local Macs are kept. Open settings to review the issue."
                     : "Apple manages delivery to your other devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("iCloud Settings", action: openSettings.callAsFunction)
                .accessibilityIdentifier("mac-icloud-settings")
        }.padding(12).background(.bar)
    }
}
#endif
