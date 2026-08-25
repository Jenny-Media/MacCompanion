#if os(iOS)
import CompanionClient
import CompanionClientNetworkPlatform
import CompanionWire
import SwiftUI

@available(iOS 17.0, *)
public struct ClientPrimaryWorkspaceViewV0: View {
    private let macName: String
    @ObservedObject private var model: ClientPrimaryWorkspaceModelV0
    @StateObject private var liveControl:
        ClientPrimaryLiveControlCoordinatorV0
    private let onSelectAction: (CapabilityDiscoveryDescriptorV1) -> Void
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void

    public init(
        macName: String,
        model: ClientPrimaryWorkspaceModelV0,
        interactiveRoles: NetworkClientInteractiveRoleProductBindingV0,
        onSelectAction: @escaping (
            CapabilityDiscoveryDescriptorV1
        ) -> Void,
        onCommandFailure: @escaping @MainActor @Sendable
            (any Error) -> Void = { _ in }
    ) {
        self.macName = macName
        _model = ObservedObject(wrappedValue: model)
        _liveControl = StateObject(wrappedValue:
            ClientPrimaryLiveControlCoordinatorV0(
                roles: interactiveRoles,
                failure: onCommandFailure
            )
        )
        self.onSelectAction = onSelectAction
        self.onCommandFailure = onCommandFailure
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Observe") {
                    NavigationLink("Mac Status") {
                        ClientObserveViewV0(
                            projection: model.projection.observe,
                            onRefreshStatus: refreshStatus,
                            onLoadActivity: loadActivity,
                            onLoadOlderActivity: loadActivity,
                            onRecordStudyJob: { category in
                                _ = try await model.recordObserveStudyJob(
                                    category: category
                                )
                            },
                            onCommandFailure: onCommandFailure
                        )
                    }
                    Label(
                        model.projection.connected
                            ? "Authenticated connection"
                            : "Last-known information only",
                        systemImage: model.projection.connected
                            ? "checkmark.shield"
                            : "wifi.exclamationmark"
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Act") {
                    NavigationLink("Approved Actions") {
                        approvedActionsDestination
                    }
                    Text("Approved Actions use bounded grants and do not start Remote Control.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Control") {
                    controlEntry
                    Text(model.projection.control.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(macName)
        }
        .task { model.start() }
    }

    @ViewBuilder
    private var approvedActionsDestination: some View {
        if let catalog = model.projection.approvedActions {
            ClientApprovedActionsViewV1(
                macName: macName,
                catalog: catalog,
                onSelect: onSelectAction,
                onReload: reloadActions
            )
        } else {
            ContentUnavailableView(
                "Approved Actions unavailable",
                systemImage: "checklist.unchecked",
                description: Text(
                    model.projection.connected
                        ? "Reload the authenticated granted-action catalog."
                        : "Reconnect to load actions granted by this Mac."
                )
            )
            .navigationTitle("Approved Actions")
            .toolbar {
                if model.projection.connected {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        reloadActions()
                    }
                }
            }
        }
    }

    private func refreshStatus() {
        perform { try await model.refreshStatus() }
    }

    private func loadActivity() {
        perform { try await model.loadNextActivityPage() }
    }

    private func reloadActions() {
        perform { try await model.reloadApprovedActions() }
    }

    @ViewBuilder
    private var controlEntry: some View {
        switch model.projection.control.entry(
            hasLocalLiveProduct: liveControl.product != nil
        ) {
        case .requestFullControl:
            Button("Request Remote Control", systemImage: "display") {
                perform {
                    try await model.beginInteractiveControl(
                        effects: [.view, .pointer, .keyboard, .text]
                    )
                }
            }
        case .openLiveControl:
            liveControlLink
        case .retryStop:
            Button("Retry Stop", systemImage: "stop.circle") {
                perform { try await model.endInteractiveControl() }
            }
        case .stopFailedSession:
            Button("Stop Failed Session", systemImage: "stop.circle") {
                perform { try await model.endInteractiveControl() }
            }
        case .unavailable:
            Label("Remote Control unavailable", systemImage: "display.slash")
                .foregroundStyle(.secondary)
        case .grantRequired:
            Label(
                "Allow Remote Control on Mac",
                systemImage: "lock.shield"
            )
            .foregroundStyle(.secondary)
        case .wait:
            Label(
                model.projection.control.mode == .ending
                    ? "Stopping Remote Control"
                    : "Preparing Remote Control",
                systemImage: model.projection.control.mode == .ending
                    ? "stop.circle" : "hourglass"
            )
                .foregroundStyle(.secondary)
        }
    }

    private var liveControlLink: some View {
        NavigationLink {
            ClientPrimaryLiveControlViewV0(
                macName: macName,
                revision: model.projection.revision,
                control: model.projection.control,
                coordinator: liveControl,
                onStop: { try await model.endInteractiveControl() },
                onRecordStudyJob: { category, snapshot in
                    _ = try await model.recordControlStudyJob(
                        category: category,
                        snapshot: snapshot
                    )
                },
                onCommandFailure: onCommandFailure
            )
        } label: {
            Label("Open Remote Control", systemImage: "display")
        }
    }

    private func perform(
        _ command: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do { try await command() }
            catch { onCommandFailure(error) }
        }
    }
}
#endif
