import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum ClientSurfaceChoiceIDV0: Hashable, Sendable {
    case desktop
    case opaqueTarget(UUID)
}

public struct ClientSurfaceChoiceV0: Equatable, Identifiable, Sendable {
    public let id: ClientSurfaceChoiceIDV0
    public let kind: InteractiveSurfaceKind
    public let targetToken: UUID?
    public let applicationName: String?
    public let windowTitle: String?
    public let windowOrdinal: Int64?
    public let available: Bool

    public static let desktop = ClientSurfaceChoiceV0(
        id: .desktop,
        kind: .desktop,
        targetToken: nil,
        applicationName: nil,
        windowOrdinal: nil,
        available: true
    )

    fileprivate init(
        id: ClientSurfaceChoiceIDV0,
        kind: InteractiveSurfaceKind,
        targetToken: UUID?,
        applicationName: String?,
        windowOrdinal: Int64?,
        available: Bool,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetToken = targetToken
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.windowOrdinal = windowOrdinal
        self.available = available
    }
}

public enum ClientSurfaceChoiceProjectionV0 {
    /// Names can coincide; the host's opaque application token is the only
    /// association used when choosing a window within an app.
    public static func windows(
        forApplication applicationToken: UUID,
        candidates: [InteractiveSurfaceTargetCandidateV0]
    ) -> [ClientSurfaceChoiceV0] {
        Array(make(candidates: candidates.filter {
            $0.kind == .window
                && $0.applicationToken.rawValue == applicationToken
        }).dropFirst())
    }

    public static func make(
        candidates: [InteractiveSurfaceTargetCandidateV0]
    ) -> [ClientSurfaceChoiceV0] {
        [.desktop] + candidates.filter(\.currentWindowAvailable).map { candidate in
            ClientSurfaceChoiceV0(
                id: .opaqueTarget(candidate.targetToken.rawValue),
                kind: candidate.kind,
                targetToken: candidate.targetToken.rawValue,
                applicationName: candidate.applicationName,
                windowOrdinal: candidate.windowOrdinal,
                available: candidate.currentWindowAvailable,
                windowTitle: candidate.windowTitle
            )
        }
    }
}
