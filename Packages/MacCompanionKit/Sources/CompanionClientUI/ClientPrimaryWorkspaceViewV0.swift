#if os(iOS)
import CompanionClient
import CompanionClientNetworkPlatform
import CompanionInteractiveWire
import CompanionWire
import Combine
import SwiftUI

@available(iOS 17.0, *)
public struct ClientPrimaryWorkspaceViewV0: View {
    private let macName: String
    @ObservedObject private var model: ClientPrimaryWorkspaceModelV0
    @StateObject private var liveControl:
        ClientPrimaryLiveControlCoordinatorV0
    @State private var liveControlPresented = false
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void
    private let onReconnect: @MainActor @Sendable () async -> Void
    private let onShowMacLibrary: @MainActor @Sendable () async -> Void

    public init(
        macName: String,
        model: ClientPrimaryWorkspaceModelV0,
        interactiveRoles: NetworkClientInteractiveRoleProductBindingV0,
        liveProductFactory: ClientPrimaryLiveControlCoordinatorV0.ProductFactory? = nil,
        onSelectAction: @escaping (
            CapabilityDiscoveryDescriptorV1
        ) -> Void,
        onReconnect: @escaping @MainActor @Sendable () async -> Void = {},
        onShowMacLibrary: @escaping @MainActor @Sendable () async -> Void = {},
        onCommandFailure: @escaping @MainActor @Sendable
            (any Error) -> Void = { _ in }
    ) {
        self.macName = macName
        _model = ObservedObject(wrappedValue: model)
        let coordinator = liveProductFactory.map {
            ClientPrimaryLiveControlCoordinatorV0(
                productFactory: $0,
                failureRetirementFactory: {
                    await interactiveRoles.makeFailedSessionRetirement()
                },
                failure: onCommandFailure
            )
        } ?? ClientPrimaryLiveControlCoordinatorV0(roles: interactiveRoles, failure: onCommandFailure)
        _liveControl = StateObject(wrappedValue: coordinator)
        self.onReconnect = onReconnect
        self.onShowMacLibrary = onShowMacLibrary
        self.onCommandFailure = onCommandFailure
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Label(
                        model.projection.connected
                            ? "Authenticated connection"
                            : "Mac disconnected",
                        systemImage: model.projection.connected
                            ? "checkmark.shield"
                            : "wifi.exclamationmark"
                    )
                    .foregroundStyle(.secondary)
                    if !model.projection.connected {
                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            Task { await onReconnect() }
                        }
                    }
                }

                Section("Remote Control") {
                    controlEntry
                    Text(model.projection.control.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(macName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("My Macs", systemImage: "desktopcomputer") {
                        Task { await onShowMacLibrary() }
                    }
                    .accessibilityIdentifier("my-macs")
                }
            }
            .navigationDestination(isPresented: $liveControlPresented) {
                liveControlDestination
            }
        }
        .task { model.start() }
        // Readiness is a lifecycle event, not just a rendered-value change.
        // SwiftUI may coalesce rapid publication/render passes after a pop or
        // foreground return. Observe the model stream so a selected primary's
        // channels-ready transition always reaches the navigation owner.
        .onReceive(model.$projection.map { $0.control.mode }.removeDuplicates()) { mode in
            liveControl.acceptWorkspaceMode(mode)
            if mode == .channelsReady {
                // The host begins its bounded capture runtime as soon as both
                // role channels are authenticated. Present the destination
                // immediately so the client starts consuming and verifying
                // the initial stream before bounded media backpressure can
                // fail the session closed.
                liveControlPresented = true
            } else if shouldDismissLiveControl(for: mode) {
                liveControlPresented = false
            }
        }
        .onReceive(model.$projection.map { $0.connected }.removeDuplicates()) { connected in
            // A stream failure under a live primary keeps its recovery screen.
            // Once that authenticated primary ends, expose the workspace's
            // Reconnect action instead of stranding the user in that screen.
            guard !connected, liveControlPresented else { return }
            liveControl.closeLocalProduct()
            liveControlPresented = false
        }
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
        Button {
            liveControlPresented = true
        } label: {
            Label("Open Remote Control", systemImage: "display")
        }
    }

    private var liveControlDestination: some View {
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
    }

    private func shouldDismissLiveControl(
        for mode: ClientControlWorkspaceModeV0
    ) -> Bool {
        guard liveControl.phase != .failed else { return false }
        return switch mode {
        case .ready, .rejected, .preparationFailed, .endFailed,
             .unavailable, .grantRequired:
            true
        case .requesting, .awaitingAcceptance, .acceptedPreparingChannels,
             .channelsReady, .preparingInitialSurface, .active, .ending:
            false
        }
    }

    private func perform(
        _ command: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do { try await command() }
            catch {
                IOSClientRuntimeDiagnosticLogV0.record(
                    "ui.workspace.command.terminal",
                    error: error
                )
                onCommandFailure(error)
            }
        }
    }
}
#endif
