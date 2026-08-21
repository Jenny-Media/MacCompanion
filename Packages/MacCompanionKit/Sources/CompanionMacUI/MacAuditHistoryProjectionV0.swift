import CompanionIPC
import CompanionPersistence
import CompanionPresentation
import Foundation

public struct MacAuditRowProjectionV0: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sequence: UInt64
    public let observedAt: Date
    public let title: String
    public let systemImage: String
    public let actorLabel: String
    public let deviceLabel: String?
    public let details: [String]

    public init(
        event: LocalAuditEventV0,
        locallyConfirmedDeviceNames: [UUID: String]
    ) {
        id = event.eventID
        sequence = event.sequence
        observedAt = Date(
            timeIntervalSince1970:
                TimeInterval(event.observedAtUnixMilliseconds) / 1_000
        )
        let code = AuditPresentationCodeV0(rawValue: event.code.rawValue)!
        title = code.title
        systemImage = code.systemImage
        actorLabel = Self.actorLabel(event.actor)
        deviceLabel = event.subjectDeviceID.map {
            locallyConfirmedDeviceNames[$0] ?? "Paired device"
        }
        var details: [String] = []
        if let capabilityID = event.capabilityID {
            details.append("Capability: \(capabilityID)")
        }
        if let route = event.routeClass {
            details.append(Self.routeLabel(route))
        }
        if let surface = event.surfaceKind {
            details.append(Self.surfaceLabel(surface))
        }
        if let outcome = event.outcome,
           let presentation = AuditOutcomePresentationV0(
               rawValue: outcome.rawValue
           ) {
            details.append(presentation.label)
        }
        self.details = details
    }

    private static func actorLabel(_ actor: AuditActorV0) -> String {
        switch actor {
        case .localUser: "Local user"
        case .agent: "Mac Companion Agent"
        case .menuApp: "Mac Companion menu app"
        case .diagnosticCLI: "Mac Companion diagnostics"
        case .pairedDevice: "Paired device"
        case .system: "macOS"
        }
    }

    private static func routeLabel(_ route: AuditRouteClassV0) -> String {
        switch route {
        case .localDiscovery: "Local network"
        case .directPrivateAddress: "Private address"
        case .privateHostname: "Private hostname"
        }
    }

    private static func surfaceLabel(_ surface: AuditSurfaceKindV0) -> String {
        switch surface {
        case .desktop: "Desktop"
        case .application: "Application Focus"
        case .window: "Window Focus"
        case .focusedRegion: "Smart Zoom"
        }
    }
}

public struct MacAuditHistoryProjectionV0: Equatable, Sendable {
    public let rows: [MacAuditRowProjectionV0]
    public let gaps: AuditGapPresentationV0
    public let canLoadOlder: Bool

    public init(
        page: LocalAuditPageResponseV0,
        locallyConfirmedDeviceNames: [UUID: String]
    ) {
        rows = page.events.map {
            MacAuditRowProjectionV0(
                event: $0,
                locallyConfirmedDeviceNames: locallyConfirmedDeviceNames
            )
        }
        gaps = AuditGapPresentationV0(
            prunedThroughSequence: page.gaps.prunedThroughSequence,
            droppedEventCount: page.gaps.droppedEventCount
        )
        canLoadOlder = page.nextBeforeSequence != nil
    }
}
