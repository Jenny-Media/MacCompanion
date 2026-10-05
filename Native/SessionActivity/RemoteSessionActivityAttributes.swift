import ActivityKit
import Foundation

struct RemoteSessionActivityAttributes: ActivityAttributes, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        case connected, paused, reconnecting
        var title: String {
            switch self {
            case .connected: "Connected"
            case .paused: "Paused"
            case .reconnecting: "Reconnecting"
            }
        }
    }
    struct ContentState: Codable, Hashable, Sendable { var phase: Phase }
    let macID: UUID
    let macName: String
    var resumeURL: URL { URL(string: "maccompanion-session://resume/" + macID.uuidString.lowercased())! }
    static func resumeMacID(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "maccompanion-session", parts.host == "resume",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.split(separator: "/", omittingEmptySubsequences: false).count == 2 else { return nil }
        return UUID(uuidString: String(parts.path.dropFirst()))
    }
}
