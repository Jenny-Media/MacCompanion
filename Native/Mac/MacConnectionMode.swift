#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

enum MacConnectionMode: String, Codable, CaseIterable, Identifiable {
    case desktop, terminal
    var id: String { rawValue }
    var shared: DirectMacConnection { self == .terminal ? .terminal : .desktop }
    var title: String { shared.title }
    var symbol: String { shared.symbol }
    var actionTitle: String { shared.actionTitle }

    init(_ shared: DirectMacConnection) { self = shared == .terminal ? .terminal : .desktop }
    init(from decoder: Decoder) throws {
        // Previously saved window requests used the shared iPhone mode enum.
        self.init(try DirectMacConnection(from: decoder))
    }
}

struct MacConnectionPreference {
    private(set) var shared: DirectMacConnection
    init(_ shared: DirectMacConnection) { self.shared = shared }
    var mode: MacConnectionMode {
        get { MacConnectionMode(shared) }
        set { shared = newValue.shared }
    }
}

struct MacSessionRequest: Codable, Hashable, Identifiable {
    let id: UUID
    let macID: UUID
    let mode: MacConnectionMode
    init(macID: UUID, mode: MacConnectionMode) { id = UUID(); self.macID = macID; self.mode = mode }
}
#endif
