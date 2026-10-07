import ActivityKit
import Foundation

struct RemoteSessionActivityAttributes: ActivityAttributes, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case desktop, terminal }
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
    // Optional so activities created by an older app retain Desktop routing.
    var kind: Kind? = nil
    var symbol: String { kind == .terminal ? "terminal" : "desktopcomputer" }
    var resumeURL: URL { URL(string: "maccompanion-session://" + (kind == .terminal ? "resume-terminal/" : "resume/") + macID.uuidString.lowercased())! }
    struct ResumeRoute: Equatable { let macID: UUID; let kind: Kind }
    static func resumeRoute(from url: URL) -> ResumeRoute? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "maccompanion-session", ["resume", "resume-terminal"].contains(parts.host),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.split(separator: "/", omittingEmptySubsequences: false).count == 2,
              let id = UUID(uuidString: String(parts.path.dropFirst())) else { return nil }
        return .init(macID: id, kind: parts.host == "resume-terminal" ? .terminal : .desktop)
    }
    static func resumeMacID(from url: URL) -> UUID? {
        resumeRoute(from: url)?.macID
    }
}
