#if os(iOS)
import CompanionInteractiveShared
import CompanionPresentation
import SwiftUI

@available(iOS 17.0, *)
public struct ClientHostSummaryViewV0: View {
    private let projection: ClientHostSurfaceProjectionV0
    private let onPrimaryAction: (ClientHostPrimaryActionV0) -> Void

    public init(
        snapshot: InteractiveClientPresentationSnapshot,
        onPrimaryAction: @escaping (ClientHostPrimaryActionV0) -> Void
    ) {
        projection = ClientHostSurfaceProjectionV0(snapshot: snapshot)
        self.onPrimaryAction = onPrimaryAction
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.title)
                        .frame(width: 52, height: 52)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(projection.displayName)
                            .font(.title2.weight(.semibold))
                        if let route = projection.route {
                            Label(routeTitle(route), systemImage: "network")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                statusCard

                if let action = projection.primaryAction {
                    Button(
                        actionTitle(action),
                        systemImage: actionSystemImage(action)
                    ) {
                        onPrimaryAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(action == .stopInteractiveControl ? .red : nil)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Mac Companion")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(statusTitle, systemImage: statusSystemImage)
                .font(.headline)
            Text(statusDetail)
                .foregroundStyle(.secondary)
            if let surface = projection.surface {
                Label(surfaceTitle(surface), systemImage: "rectangle.on.rectangle")
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch projection.status {
        case .background: "Paused in Background"
        case .noNetwork: "No Private Network"
        case .connecting: "Connecting"
        case .retryScheduled: "Reconnecting"
        case .actionRequired: "Action Required"
        case .disconnected: "Disconnected"
        case .ready: "Ready"
        case .approvalRequired: "Waiting for Mac Approval"
        case .starting: "Starting Interactive Control"
        case .viewing: "Viewing Mac"
        case .controlling: "Controlling Mac"
        case .paused: "Interactive Control Paused"
        case .ending: "Ending Interactive Control"
        }
    }

    private var statusDetail: String {
        switch projection.status {
        case .background: "Return to Mac Companion to reconnect."
        case .noNetwork: "Connect both devices through your local or private network."
        case .connecting, .retryScheduled: "Mac Companion is verifying the saved Mac identity."
        case .actionRequired: "Review the connection guidance before trying again."
        case .disconnected: "This Mac will not reconnect until you ask it to."
        case .ready: "Status and approved Mac actions are available without opening Remote Control."
        case .approvalRequired: "Approve this session from the visible Mac Companion menu app."
        case .starting: "The Mac is preparing the selected surface."
        case .viewing: "The Mac screen is visible. Input is not enabled."
        case .controlling: "Screen, pointer, and keyboard access are active for this session."
        case let .paused(lock): pausedDetail(lock)
        case .ending: "Input and capture are being removed on the Mac."
        }
    }

    private var statusSystemImage: String {
        switch projection.status {
        case .ready: "checkmark.circle"
        case .viewing: "eye"
        case .controlling: "cursorarrow.motionlines"
        case .approvalRequired: "person.badge.clock"
        case .starting, .connecting, .retryScheduled, .ending: "arrow.triangle.2.circlepath"
        case .background, .paused: "pause.circle"
        case .noNetwork, .actionRequired, .disconnected: "exclamationmark.triangle"
        }
    }

    private func pausedDetail(_ lock: HostLockPresentation) -> String {
        switch lock {
        case .lockedInteractionUnavailable: "The Mac is locked and interaction is unavailable."
        case .lockedControlAvailable: "The Mac is locked; the approved session remains available."
        case .unknown, .unlocked: "The Mac temporarily suspended this session."
        }
    }

    private func routeTitle(_ route: PairedMacRoutePresentation) -> String {
        switch route {
        case .localDiscovery: "Local network"
        case .directPrivateAddress: "Private address"
        case .privateHostname: "Private hostname"
        }
    }

    private func surfaceTitle(_ surface: InteractiveSurfaceKind) -> String {
        switch surface {
        case .desktop: "Desktop"
        case .application: "Application Focus"
        case .window: "Window Focus"
        case .focusedRegion: "Smart Zoom"
        }
    }

    private func actionTitle(_ action: ClientHostPrimaryActionV0) -> String {
        switch action {
        case .reconnect: "Reconnect"
        case .startInteractiveControl: "Open Remote Control"
        case .stopInteractiveControl: "Stop Interactive Control"
        }
    }

    private func actionSystemImage(
        _ action: ClientHostPrimaryActionV0
    ) -> String {
        switch action {
        case .reconnect: "arrow.clockwise"
        case .startInteractiveControl: "rectangle.inset.filled.and.person.filled"
        case .stopInteractiveControl: "stop.circle"
        }
    }
}
#endif
