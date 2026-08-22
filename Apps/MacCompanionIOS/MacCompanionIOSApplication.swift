import CompanionClientPlatform
import Foundation
import SwiftUI

@main
struct MacCompanionIOSApplication: App {
    private let bootstrap = IOSClientReleaseBootstrapV1()

    var body: some Scene {
        WindowGroup {
            MacCompanionIOSBootstrapView(bootstrap: bootstrap)
        }
    }
}

private struct MacCompanionIOSBootstrapView: View {
    let bootstrap: IOSClientReleaseBootstrapV1

    @State private var snapshot = IOSClientReleaseBootstrapSnapshotV1.idle

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Mac Companion")
        }
        .task {
            snapshot = await bootstrap.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.phase {
        case .idle, .preparing:
            ProgressView("Preparing protected device identity…")

        case .unpaired:
            ContentUnavailableView {
                Label("Connect your Mac", systemImage: "macbook.and.iphone")
            } description: {
                Text(
                    "This iPhone or iPad is protected and ready for direct, no-relay pairing. Pairing setup is not available in this build."
                )
            }

        case .paired:
            ContentUnavailableView {
                Label("Paired Mac protected", systemImage: "checkmark.shield")
            } description: {
                Text(
                    "Your saved Mac identity and private route passed protected restart checks. Connecting is not available in this build."
                )
            }

        case let .unavailable(reason):
            ContentUnavailableView {
                Label("Mac Companion unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason.detail)
            }

        case .closed:
            ContentUnavailableView(
                "Mac Companion closed",
                systemImage: "xmark.circle"
            )
        }
    }
}

private extension IOSClientReleaseBootstrapFailureV1 {
    var detail: String {
        switch self {
        case .storageUnavailable:
            "Protected local storage could not be opened. No connection was started."
        case .invalidInstallationIdentity:
            "The per-install device identity is invalid. No saved Mac was trusted."
        case .ambiguousSavedState:
            "This build supports one paired Mac and found ambiguous protected local state."
        case .keyUnavailable:
            "A saved Mac no longer matches this device’s protected keys. Pairing was not restored."
        case .routeConfigurationMissing:
            "The saved Mac has no complete private-route configuration. No connection was started."
        }
    }
}
