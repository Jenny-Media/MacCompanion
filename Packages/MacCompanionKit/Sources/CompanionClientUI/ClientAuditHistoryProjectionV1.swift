import CompanionPresentation
import CompanionWire
import Foundation

public struct ClientAuditRowProjectionV1: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sequence: Int64
    public let observedAt: Date
    public let title: String
    public let systemImage: String
    public let scopeLabel: String
    public let details: [String]

    public init(event: AuditSelfEventWireV1) {
        id = event.eventID.rawValue
        sequence = event.sequence
        observedAt = Date(
            timeIntervalSince1970:
                TimeInterval(event.observedAtUnixMilliseconds) / 1_000
        )
        let code = AuditPresentationCodeV0(rawValue: event.code.rawValue)!
        title = code.title
        systemImage = code.systemImage
        scopeLabel = event.scope == .host ? "Mac" : "This device"
        var details: [String] = []
        if let capabilityID = event.capabilityID {
            details.append("Capability: \(capabilityID)")
        }
        if let routeClass = event.routeClass {
            details.append(Self.routeLabel(routeClass))
        }
        if let surfaceKind = event.surfaceKind {
            details.append(Self.surfaceLabel(surfaceKind))
        }
        if let outcome = event.outcome,
           let presentation = AuditOutcomePresentationV0(
               rawValue: outcome.rawValue
           ) {
            details.append(presentation.label)
        }
        self.details = details
    }

    private static func routeLabel(_ route: AuditRouteClassWireV1) -> String {
        switch route {
        case .localDiscovery: "Local network"
        case .directPrivateAddress: "Private address"
        case .privateHostname: "Private hostname"
        }
    }

    private static func surfaceLabel(
        _ surface: AuditSurfaceKindWireV1
    ) -> String {
        switch surface {
        case .desktop: "Desktop"
        case .application: "Application Focus"
        case .window: "Window Focus"
        case .focusedRegion: "Smart Zoom"
        }
    }
}

public struct ClientAuditHistoryProjectionV1: Equatable, Sendable {
    public let rows: [ClientAuditRowProjectionV1]
    public let gaps: AuditGapPresentationV0
    public let canLoadOlder: Bool

    public init(page: AuditListResponseBodyV1) {
        rows = page.events.map(ClientAuditRowProjectionV1.init)
        gaps = AuditGapPresentationV0(
            prunedThroughSequence: page.gaps.prunedThroughSequence.map(UInt64.init),
            droppedEventCount: UInt64(page.gaps.droppedEventCount)
        )
        canLoadOlder = page.nextBeforeSequence != nil
    }
}
