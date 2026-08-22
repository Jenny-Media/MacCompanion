import CompanionClientPlatform
import CompanionClientUI
import Foundation
import SwiftUI

@main
struct MacCompanionIOSApplication: App {
    @State private var application = IOSClientReleaseApplicationV1()

    var body: some Scene {
        WindowGroup {
            MacCompanionIOSRootView(application: application)
        }
    }
}

private enum MacCompanionIOSSheet: String, Identifiable {
    case pairingScanner

    var id: String { rawValue }
}

private struct MacCompanionIOSRootView: View {
    let application: IOSClientReleaseApplicationV1

    @State private var sheet: MacCompanionIOSSheet?

    var body: some View {
        content
            .task { await application.start() }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .pairingScanner:
                    ClientPairingScannerViewV0(
                        onScan: { value in
                            sheet = nil
                            Task {
                                await application.receivePairingScan(value)
                            }
                        },
                        onCancel: { sheet = nil }
                    )
                    .ignoresSafeArea()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch application.snapshot.phase {
        case .idle, .preparing:
            NavigationStack {
                ProgressView("Preparing protected device identity…")
                    .navigationTitle("Mac Companion")
            }

        case .pairing:
            if let pairing = application.snapshot.pairing {
                NavigationStack {
                    ClientPairingViewV0(
                        presentation: pairing,
                        onScan: { sheet = .pairingScanner },
                        onAcceptPreview: {
                            Task {
                                await application.acceptPairingPreview()
                            }
                        },
                        onCancel: {
                            Task { await application.cancelPairing() }
                        },
                        onRetry: {
                            Task { await application.cancelPairing() }
                        },
                        onDone: {
                            Task {
                                await application.continueAfterPairing()
                            }
                        }
                    )
                }
            } else {
                unavailable(
                    title: "Pairing unavailable",
                    detail: "The protected pairing surface could not be prepared."
                )
            }

        case .routeSetup:
            if let plan = application.snapshot.routePlan {
                NavigationStack {
                    ClientRouteBootstrapApplicationViewV1(
                        plan: plan,
                        onCancel: { application.deferRouteSetup() },
                        onComplete: { choices in
                            Task {
                                await application.completeRouteSetup(choices)
                            }
                        }
                    )
                }
            } else {
                unavailable(
                    title: "Private routes unavailable",
                    detail: "No connection was started."
                )
            }

        case .routeSetupDeferred:
            NavigationStack {
                ContentUnavailableView {
                    Label(
                        "Finish private-route setup",
                        systemImage: "network.badge.shield.half.filled"
                    )
                } description: {
                    Text(
                        "Your Mac identity is protected, but Mac Companion will not connect until you classify every ambiguous private route."
                    )
                } actions: {
                    Button("Continue Route Setup") {
                        application.resumeRouteSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Mac Companion")
            }

        case .connecting:
            NavigationStack {
                ProgressView("Starting direct private connection…")
                    .navigationTitle("Mac Companion")
            }

        case .workspace:
            if let workspace = application.snapshot.workspace {
                MacCompanionIOSWorkspaceRoot(workspace: workspace)
            } else {
                unavailable(
                    title: "Workspace unavailable",
                    detail: "No connection authority was retained."
                )
            }

        case .unavailable:
            unavailable(
                title: "Mac Companion unavailable",
                detail: application.snapshot.failure?.detail
                    ?? "Protected startup failed closed. No connection was started.",
                retry: true
            )

        case .closed:
            unavailable(
                title: "Mac Companion closed",
                detail: "Open the app again to resume."
            )
        }
    }

    private func unavailable(
        title: String,
        detail: String,
        retry: Bool = false
    ) -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail)
            } actions: {
                if retry {
                    Button("Retry") {
                        Task { await application.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Mac Companion")
        }
    }
}

private struct MacCompanionIOSWorkspaceRoot: View {
    let workspace: IOSClientReleaseWorkspaceV1

    @State private var model: ClientPrimaryWorkspaceModelV0?
    @State private var commandFailureShown = false

    init(workspace: IOSClientReleaseWorkspaceV1) {
        self.workspace = workspace
        _model = State(initialValue: try? ClientPrimaryWorkspaceModelV0(
            macName: workspace.macName,
            primaryState: workspace.primaryState,
            monotonicNowMilliseconds: {
                max(0, Int64(ProcessInfo.processInfo.systemUptime * 1_000))
            }
        ))
    }

    var body: some View {
        Group {
            if let model {
                ClientPrimaryWorkspaceApplicationViewV1(
                    macName: workspace.macName,
                    model: model,
                    interactiveRoles: workspace.interactiveRoles,
                    onCommandFailure: { _ in
                        commandFailureShown = true
                    }
                )
            } else {
                ContentUnavailableView(
                    "Workspace unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "The authenticated workspace could not be projected safely."
                    )
                )
            }
        }
        .alert("Command did not complete", isPresented: $commandFailureShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Mac Companion kept the previous verified state. Reconnect or retry from the relevant screen."
            )
        }
    }
}

private extension IOSClientReleaseApplicationFailureV1 {
    var detail: String {
        switch self {
        case .protectedStorageUnavailable:
            "Protected local storage could not be opened. No connection was started."
        case .invalidInstallationIdentity:
            "The per-install device identity is invalid. No saved Mac was trusted."
        case .ambiguousSavedState:
            "This build supports one paired Mac and found ambiguous protected local state."
        case .protectedKeyUnavailable:
            "A saved Mac no longer matches this device’s protected keys. Pairing was not restored."
        case .routeConfigurationUnavailable:
            "The saved Mac does not have a complete private-route configuration. No connection was started."
        case .pairingCompositionUnavailable:
            "Secure pairing could not be prepared. No camera or network connection was started."
        case .networkCompositionUnavailable:
            "The direct private connection closed safely. Your saved Mac identity remains protected."
        }
    }
}
