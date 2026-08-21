import CompanionIPC
import CompanionLifecycle
import CompanionMacApp
import Foundation

public enum MacAgentDashboardStateV0: String, Equatable, Sendable {
    case loading
    case off
    case starting
    case ready
    case needsAttention
    case unavailable
}

public struct MacAgentDashboardActionProjectionV0:
    Equatable,
    Sendable
{
    public let action: MacAgentDashboardActionV0
    public let title: String
    public let systemImage: String
    public let enabled: Bool

    public init(
        action: MacAgentDashboardActionV0,
        title: String,
        systemImage: String,
        enabled: Bool
    ) {
        self.action = action
        self.title = title
        self.systemImage = systemImage
        self.enabled = enabled
    }
}

public struct MacAgentDashboardFactV0: Equatable, Sendable {
    public let id: String
    public let title: String
    public let value: String

    public init(id: String, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

public struct MacAgentDashboardWarningV0: Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Content-free menu-app projection of the Agent-owned local status snapshot.
/// It never accepts arbitrary status text, endpoints, paths, device names, or
/// provider identities. Buttons emit typed intents; they do not imply that a
/// lifecycle, pairing, or administration command succeeded.
public struct MacAgentDashboardProjectionV0: Equatable, Sendable {
    public let state: MacAgentDashboardStateV0
    public let title: String
    public let detail: String
    public let systemImage: String
    public let facts: [MacAgentDashboardFactV0]
    public let warnings: [MacAgentDashboardWarningV0]
    public let primaryAction: MacAgentDashboardActionProjectionV0?
    public let secondaryActions: [MacAgentDashboardActionProjectionV0]

    public init(source: MacAgentDashboardSourceV0) throws {
        switch source {
        case .loading:
            state = .loading
            title = "Checking Mac Companion"
            detail = "Waiting for a verified local status response."
            systemImage = "hourglass"
            facts = []
            warnings = []
            primaryAction = nil
            secondaryActions = []
        case .unavailable:
            state = .unavailable
            title = "Mac Agent unavailable"
            detail = "Mac Companion could not obtain a verified local status response."
            systemImage = "exclamationmark.triangle"
            facts = []
            warnings = []
            primaryAction = .init(
                action: .retryStatus,
                title: "Try Again",
                systemImage: "arrow.clockwise",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .retryStatus,
                    in: source
                )
            )
            secondaryActions = []
        case let .status(snapshot):
            try snapshot.validate()
            let derived = Self.deriveState(snapshot)
            state = derived.state
            title = derived.title
            detail = derived.detail
            systemImage = derived.systemImage
            facts = Self.facts(snapshot)
            warnings = snapshot.warningCodes.map(Self.warning)
            primaryAction = Self.primaryAction(snapshot)
            secondaryActions = Self.secondaryActions(snapshot)
        }
    }

    private static func deriveState(
        _ snapshot: LocalAgentStatusSnapshot
    ) -> (
        state: MacAgentDashboardStateV0,
        title: String,
        detail: String,
        systemImage: String
    ) {
        guard snapshot.desiredEnabled else {
            return (
                .off,
                "Mac Companion is off",
                "Remote access is disabled for this macOS account.",
                "power"
            )
        }
        let hasClosedFailure = snapshot.securityPosture != .nominal
            || !snapshot.warningCodes.isEmpty
            || snapshot.agentProcess == .stopped
            || snapshot.menuAppProcess == .stopped
            || snapshot.networkState == .stopped
            || snapshot.networkState == .degraded
            || snapshot.consoleSession == .loggedOut
        if hasClosedFailure {
            return (
                .needsAttention,
                "Mac Companion needs attention",
                "Review the status below before relying on remote access.",
                "exclamationmark.triangle.fill"
            )
        }
        let ready = snapshot.agentProcess == .ready
            && snapshot.menuAppProcess == .ready
            && snapshot.networkState == .listening
        guard ready else {
            return (
                .starting,
                "Mac Companion is starting",
                "The local components have not all reported ready yet.",
                "clock.arrow.circlepath"
            )
        }
        if snapshot.consoleSession == .locked {
            return (
                .ready,
                "Mac Companion is on",
                "This Mac is locked. Status may remain available; Control is limited to the genuine lock surface when supported.",
                "lock.shield"
            )
        }
        return (
            .ready,
            "Mac Companion is on",
            "This Mac is ready for independently authorized Observe, Act, and Control connections.",
            "checkmark.shield.fill"
        )
    }

    private static func facts(
        _ snapshot: LocalAgentStatusSnapshot
    ) -> [MacAgentDashboardFactV0] {
        [
            .init(
                id: "agent",
                title: "Mac Agent",
                value: process(snapshot.agentProcess)
            ),
            .init(
                id: "menu",
                title: "Visible menu app",
                value: process(snapshot.menuAppProcess)
            ),
            .init(
                id: "network",
                title: "Private listener",
                value: network(snapshot.networkState)
            ),
            .init(
                id: "session",
                title: "macOS session",
                value: consoleSession(snapshot.consoleSession)
            ),
            .init(
                id: "routes",
                title: "Available routes",
                value: routes(snapshot.routeKinds)
            ),
            .init(
                id: "devices",
                title: "Paired devices",
                value: String(snapshot.pairedDeviceCount)
            ),
            .init(
                id: "remoteSessions",
                title: "Active remote sessions",
                value: String(snapshot.activeRemoteSessionCount)
            ),
            .init(
                id: "providers",
                title: "Capability providers",
                value: String(snapshot.providerCount)
            ),
            .init(
                id: "security",
                title: "Security storage",
                value: security(snapshot.securityPosture)
            ),
        ]
    }

    private static func primaryAction(
        _ snapshot: LocalAgentStatusSnapshot
    ) -> MacAgentDashboardActionProjectionV0? {
        if snapshot.desiredEnabled {
            return .init(
                action: .disable,
                title: "Disable Mac Companion",
                systemImage: "power",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .disable,
                    in: .status(snapshot)
                )
            )
        }
        return .init(
            action: .enable,
            title: "Enable Mac Companion",
            systemImage: "power",
            enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                .enable,
                in: .status(snapshot)
            )
        )
    }

    private static func secondaryActions(
        _ snapshot: LocalAgentStatusSnapshot
    ) -> [MacAgentDashboardActionProjectionV0] {
        let source = MacAgentDashboardSourceV0.status(snapshot)
        return [
            .init(
                action: .startPairing,
                title: "Pair a Device",
                systemImage: "qrcode",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .startPairing,
                    in: source
                )
            ),
            .init(
                action: .openDevices,
                title: "Paired Devices",
                systemImage: "iphone",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .openDevices,
                    in: source
                )
            ),
            .init(
                action: .openActivityHistory,
                title: "Activity History",
                systemImage: "clock.arrow.circlepath",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .openActivityHistory,
                    in: source
                )
            ),
            .init(
                action: .exportDiagnostics,
                title: "Export Diagnostics",
                systemImage: "square.and.arrow.up",
                enabled: MacAgentDashboardActionPolicyV0.isEnabled(
                    .exportDiagnostics,
                    in: source
                )
            ),
        ]
    }

    private static func warning(
        _ code: SanitizedDiagnosticCode
    ) -> MacAgentDashboardWarningV0 {
        let content: (String, String) = switch code {
        case .agentUnavailable:
            ("Mac Agent unavailable", "Remote requests are not being accepted.")
        case .auditHistoryDegraded:
            ("Activity history degraded", "Some detailed local history may be unavailable.")
        case .authorizationChanged:
            ("Authorization changed", "Reconnect after reviewing this device’s access.")
        case .captureUnavailable:
            ("Screen capture unavailable", "Control cannot transmit the Mac screen.")
        case .denyLatchArmed:
            ("Remote access stopped", "A local security recovery is required before remote startup.")
        case .localNetworkDenied:
            ("Local Network access denied", "Review Local Network privacy settings on this Mac.")
        case .menuAppUnavailable:
            ("Visible menu app unavailable", "Interactive Control is stopped until the visible app returns.")
        case .permissionLost:
            ("Permission changed", "A required macOS permission must be reviewed locally.")
        case .routeUnavailable:
            ("No configured route available", "Check the local network or user-managed private route.")
        case .storageUnavailable:
            ("Security storage unavailable", "Remote work is denied until local storage recovers.")
        case .versionMismatch:
            ("Component update required", "Mac Companion components do not share a supported version.")
        }
        return .init(id: code.rawValue, title: content.0, detail: content.1)
    }

    private static func process(_ value: ManagedProcessState) -> String {
        switch value {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .ready: "Ready"
        }
    }

    private static func network(_ value: LocalAgentNetworkState) -> String {
        switch value {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .listening: "Listening"
        case .degraded: "Degraded"
        }
    }

    private static func consoleSession(_ value: ConsoleSessionState) -> String {
        switch value {
        case .active: "Active"
        case .locked: "Locked"
        case .loggedOut: "Logged out"
        }
    }

    private static func routes(_ values: [LocalRouteKind]) -> String {
        guard !values.isEmpty else { return "None" }
        return values.map {
            switch $0 {
            case .lan: "Local network"
            case .privateDNS: "Private DNS"
            case .privateNetwork: "Private network"
            }
        }.joined(separator: ", ")
    }

    private static func security(_ value: LocalSecurityPosture) -> String {
        switch value {
        case .nominal: "Available"
        case .denyLatched: "Recovery required"
        case .storageUnavailable: "Unavailable"
        }
    }
}

#if os(macOS)
import SwiftUI

@available(macOS 14.0, *)
public struct MacAgentDashboardViewV0: View {
    private let projection: MacAgentDashboardProjectionV0
    private let perform: (MacAgentDashboardActionV0) -> Void

    public init(
        source: MacAgentDashboardSourceV0,
        perform: @escaping (MacAgentDashboardActionV0) -> Void
    ) throws {
        projection = try MacAgentDashboardProjectionV0(source: source)
        self.perform = perform
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if projection.state == .loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                ForEach(projection.warnings, id: \.id) { warning in
                    warningCard(warning)
                }

                if !projection.facts.isEmpty {
                    GroupBox("Status") {
                        Grid(alignment: .leading, horizontalSpacing: 24) {
                            ForEach(projection.facts, id: \.id) { fact in
                                GridRow {
                                    Text(fact.title)
                                        .foregroundStyle(.secondary)
                                    Text(fact.value)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                Divider()
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if !projection.secondaryActions.isEmpty {
                    GroupBox("Administration") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 170))],
                            spacing: 10
                        ) {
                            ForEach(
                                projection.secondaryActions,
                                id: \.action.rawValue
                            ) { action in
                                Button {
                                    perform(action.action)
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(!action.enabled)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: projection.systemImage)
                .font(.system(size: 30))
                .frame(width: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(projection.title)
                    .font(.title2.weight(.semibold))
                Text(projection.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action = projection.primaryAction {
                Button(action.title) { perform(action.action) }
                    .disabled(!action.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func warningCard(
        _ warning: MacAgentDashboardWarningV0
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(warning.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(warning.detail)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
#endif
