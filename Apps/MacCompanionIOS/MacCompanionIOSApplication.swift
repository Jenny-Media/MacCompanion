#if !MACCOMPANION_VNC_DEVELOPMENT
import CompanionClientPlatform
import CompanionClientUI
import Foundation
#endif
import SwiftUI

@main
struct MacCompanionIOSApplication: App {
    #if !MACCOMPANION_VNC_DEVELOPMENT
    @State private var application = Self.makeApplication()

    @MainActor
    private static func makeApplication() -> IOSClientReleaseApplicationV1 {
        #if DEBUG && MACCOMPANION_VNC_DEVELOPMENT
        #if DEBUG && targetEnvironment(simulator)
        return IOSClientReleaseApplicationV1(simulatorDevelopmentNativeVideoAdapterFactory: nil,
            desktopCredentialRemoval: { try DesktopCredentialStoreV1.remove($0) })
        #else
        return IOSClientReleaseApplicationV1(desktopCredentialRemoval: { try DesktopCredentialStoreV1.remove($0) })
        #endif
        #else
        #if DEBUG && MACCOMPANION_ADMITTED_NATIVE_DEVELOPMENT && canImport(CompanionMoonlightEngine)
        let factory: UIKitClientNativeVideoCompositionV1.AdapterFactory = { signer, route in
            MoonlightNativeLaunchAdapterV0(signer: signer, verifiedPrimaryRoute: route)
        }
        #if targetEnvironment(simulator)
        return IOSClientReleaseApplicationV1(simulatorDevelopmentNativeVideoAdapterFactory: factory)
        #else
        return IOSClientReleaseApplicationV1(nativeVideoAdapterFactory: factory)
        #endif
        #else
        return IOSClientReleaseApplicationV1()
        #endif
        #endif
    }

    #endif
    var body: some Scene {
        WindowGroup {
            #if MACCOMPANION_VNC_DEVELOPMENT
            DirectMacLibraryRootV1().directAppearance()
            #else
            MacCompanionIOSRootView(application: application)
            #endif
        }
    }
}

#if !MACCOMPANION_VNC_DEVELOPMENT
private enum MacCompanionIOSSheet: String, Identifiable {
    case pairingScanner
    case studyReport

    var id: String { rawValue }
}

private struct MacCompanionIOSRootView: View {
    @Bindable var application: IOSClientReleaseApplicationV1

    @State private var sheet: MacCompanionIOSSheet?

    var body: some View {
        content
            #if DEBUG && MACCOMPANION_ADMITTED_NATIVE_DEVELOPMENT && targetEnvironment(simulator)
            .safeAreaInset(edge: .bottom) {
                // The warning is shown during setup. Once the workspace opens,
                // its own controls must keep their full touch area, including
                // the Control screen's keyboard, shortcuts, and Stop actions.
                if application.snapshot.phase != .workspace {
                    Text("Simulator testing · Device protection is unavailable")
                        .font(.caption).padding(8)
                        .frame(maxWidth: .infinity).background(.thinMaterial)
                }
            }
            #endif
            .task { await application.start() }
            .toolbar {
                if application.studyReportOwner != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Study Report", systemImage: "doc.text") {
                            sheet = .studyReport
                        }
                    }
                }
            }
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
                case .studyReport:
                    if let owner = application.studyReportOwner,
                       let capture = application.studyCapture {
                        NavigationStack {
                            ClientStage3StudyReportViewV1(
                                owner: owner,
                                capture: capture,
                                captureFailed:
                                    application.studyCaptureFailed
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "Report unavailable",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
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
                        },
                        onPastePairingCode: { value in
                            Task { await application.receivePairingScan(value) }
                        }
                    )
                    .toolbar { macLibraryToolbar }
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
                    .toolbar { macLibraryToolbar }
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
                .toolbar { macLibraryToolbar }
            }

        case .macLibrary:
            ClientMacLibraryViewV1(macs: application.savedMacs, failed: application.macManagementFailed,
                onConnect: { await application.selectMac($0) },
                onPair: { await application.pairAnotherMac() },
                onRename: { await application.renameMac($0, name: $1) },
                onForget: { await application.forgetMac($0) })

        case .connecting:
            NavigationStack {
                ProgressView("Starting direct private connection…")
                    .navigationTitle("Mac Companion")
            }

        case .workspace:
            if let workspace = application.snapshot.workspace {
                #if DEBUG && MACCOMPANION_VNC_DEVELOPMENT
                VNCRemoteDesktopView(workspace: workspace,
                    showMacs: { await application.showMacLibrary() })
                    .ignoresSafeArea(.container, edges: .bottom)
                    .id(workspace.id)
                #else
                MacCompanionIOSWorkspaceRoot(
                    workspace: workspace,
                    onReconnect: { await application.reconnect() },
                    onShowMacLibrary: { await application.showMacLibrary() }
                )
                .id(workspace.id)
                #endif
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
            .toolbar { macLibraryToolbar }
        }
    }

    @ToolbarContentBuilder
    private var macLibraryToolbar: some ToolbarContent {
        if !application.savedMacs.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button("My Macs") { Task { await application.showMacLibrary() } }
                    .accessibilityIdentifier("my-macs")
            }
        }
    }
}

private struct MacCompanionIOSWorkspaceRoot: View {
    let workspace: IOSClientReleaseWorkspaceV1
    let onReconnect: @MainActor @Sendable () async -> Void
    let onShowMacLibrary: @MainActor @Sendable () async -> Void

    @State private var model: ClientPrimaryWorkspaceModelV0?
    @State private var commandFailureShown = false
    @State private var commandFailureDetail = "The request failed. Stop the failed session if that option is shown, then reconnect and try again."

    init(
        workspace: IOSClientReleaseWorkspaceV1,
        onReconnect: @escaping @MainActor @Sendable () async -> Void,
        onShowMacLibrary: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.workspace = workspace
        self.onReconnect = onReconnect
        self.onShowMacLibrary = onShowMacLibrary
        _model = State(initialValue: try? ClientPrimaryWorkspaceModelV0(
            macName: workspace.macName,
            primaryState: workspace.primaryState,
            monotonicNowMilliseconds: {
                max(0, Int64(ProcessInfo.processInfo.systemUptime * 1_000))
            },
            studyCapture: workspace.studyCapture,
            studyCaptureFailure: workspace.studyCaptureFailure
        ))
    }

    var body: some View {
        Group {
            if let model {
                ClientPrimaryWorkspaceApplicationViewV1(
                    macName: workspace.macName,
                    model: model,
                    interactiveRoles: workspace.interactiveRoles,
                    liveProductFactory: workspace.initialDesktopProductFactory.map { factory in
                        { mode, failure in try await factory(mode, failure) }
                    },
                    onReconnect: onReconnect,
                    onShowMacLibrary: onShowMacLibrary,
                    onCommandFailure: { error in
                        commandFailureDetail = (error as? any ClientCommandFailurePresentingV0)?.commandFailureDetail
                            ?? "The request failed. Stop the failed session if that option is shown, then reconnect and try again."
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
            Text(commandFailureDetail)
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
            "The saved Mac identities or connection settings conflict. No connection was started."
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

#endif
