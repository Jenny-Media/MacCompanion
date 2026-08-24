import Foundation

/// A deliberately narrow local command surface for macOS automation.
///
/// The URL scheme does not expose arbitrary Agent lifecycle or remote-control
/// operations. Registration repair is idempotent: the containing app accepts
/// it only while Mac Companion is already configured as enabled and restores
/// that same state against the currently installed signed bundle.
public enum MacCompanionLocalCommandV1: Equatable, Sendable {
    public static let scheme = "maccompanion"

    case openWindow
    case repairAgentRegistration

    public init?(url: URL) {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == Self.scheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty else {
            return nil
        }

        switch components.host?.lowercased() {
        case "open":
            self = .openWindow
        case "repair-agent-registration":
            self = .repairAgentRegistration
        default:
            return nil
        }
    }
}
