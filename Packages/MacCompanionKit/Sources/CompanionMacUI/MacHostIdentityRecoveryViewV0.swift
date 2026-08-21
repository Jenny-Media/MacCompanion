#if os(macOS)
import CompanionIPC
import CompanionPresentation
import Foundation
import SwiftUI

public enum MacHostIdentityRecoveryViewActionV0:
    Equatable,
    Sendable
{
    case confirmRecovery
    case retryRecovery
    case cancelReview
    case done
}

public enum MacHostIdentityRecoveryViewErrorV0:
    Error,
    Equatable,
    Sendable
{
    case idlePresentation
}

public struct MacHostIdentityRecoveryViewProjectionV0:
    Equatable,
    Sendable
{
    public let title: String
    public let detail: String
    public let hostID: String
    public let fingerprint: String
    public let consequences: [MacHostIdentityRecoveryConsequenceV0]
    public let showsProgress: Bool
    public let primaryAction: MacHostIdentityRecoveryViewActionV0?
    public let primaryTitle: String?
    public let primaryIsDestructive: Bool
    public let showsCancel: Bool
    public let preventsImplicitDismissal: Bool

    public static func project(
        _ presentation: MacHostIdentityRecoveryPresentationV0
    ) -> Self? {
        let title: String
        let detail: String
        let hostID: UUID
        let fingerprintData: Data
        let showsProgress: Bool
        let primaryAction: MacHostIdentityRecoveryViewActionV0?
        let primaryTitle: String?
        let primaryIsDestructive: Bool
        let showsCancel: Bool

        switch presentation.phase {
        case .idle:
            return nil
        case let .reviewing(review):
            title = "Replace this Mac’s identity?"
            detail = causeDetail(review.cause)
            hostID = review.hostID
            fingerprintData = review.hostFingerprint.rawValue
            showsProgress = false
            primaryAction = .confirmRecovery
            primaryTitle = "Replace Identity"
            primaryIsDestructive = true
            showsCancel = true
        case let .recovering(command):
            title = "Replacing Mac identity"
            detail = "Remote access remains stopped while the Mac completes recovery."
            hostID = command.review.hostID
            fingerprintData = command.review.hostFingerprint.rawValue
            showsProgress = true
            primaryAction = nil
            primaryTitle = nil
            primaryIsDestructive = false
            showsCancel = false
        case let .recoveryFailed(command):
            title = "Recovery was not confirmed"
            detail = "Retry the exact same recovery. Starting a different reset is not allowed."
            hostID = command.review.hostID
            fingerprintData = command.review.hostFingerprint.rawValue
            showsProgress = false
            primaryAction = .retryRecovery
            primaryTitle = "Retry Recovery"
            primaryIsDestructive = true
            showsCancel = false
        case let .authorizationLost(command):
            title = "Reconnect to the Mac Agent"
            detail = "The submitted recovery is retained, but it cannot be retried until the authenticated Agent republishes the same review."
            hostID = command.review.hostID
            fingerprintData = command.review.hostFingerprint.rawValue
            showsProgress = false
            primaryAction = nil
            primaryTitle = nil
            primaryIsDestructive = false
            showsCancel = false
        case let .completed(_, receipt):
            title = "Mac identity replaced"
            detail = "Prior phones can no longer connect. Pair each phone again before using remote access."
            hostID = receipt.newHostID
            fingerprintData = receipt.newHostFingerprint.rawValue
            showsProgress = false
            primaryAction = .done
            primaryTitle = "Done"
            primaryIsDestructive = false
            showsCancel = false
        }

        return Self(
            title: title,
            detail: detail,
            hostID: hostID.uuidString.lowercased(),
            fingerprint: fingerprintData.map {
                String(format: "%02x", $0)
            }.joined(),
            consequences:
                MacHostIdentityRecoveryPresentationV0.requiredConsequences,
            showsProgress: showsProgress,
            primaryAction: primaryAction,
            primaryTitle: primaryTitle,
            primaryIsDestructive: primaryIsDestructive,
            showsCancel: showsCancel,
            preventsImplicitDismissal: true
        )
    }

    private static func causeDetail(
        _ cause: LocalHostIdentityRecoveryCauseV0
    ) -> String {
        switch cause {
        case .keyUnavailable:
            "This Mac’s established private identity key is unavailable. Recovery creates a new identity."
        case .suspectedCompromise:
            "Use recovery only because the current Mac identity may be compromised."
        case .userRequestedReset:
            "You requested a destructive reset of this Mac’s remote identity."
        }
    }
}

@available(macOS 14.0, *)
public struct MacHostIdentityRecoveryViewV0: View {
    private let projection: MacHostIdentityRecoveryViewProjectionV0
    private let perform: (MacHostIdentityRecoveryViewActionV0) -> Void

    public init(
        presentation: MacHostIdentityRecoveryPresentationV0,
        perform: @escaping (MacHostIdentityRecoveryViewActionV0) -> Void
    ) throws {
        guard let projection =
            MacHostIdentityRecoveryViewProjectionV0.project(presentation) else {
            throw MacHostIdentityRecoveryViewErrorV0.idlePresentation
        }
        self.projection = projection
        self.perform = perform
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(projection.title, systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.red)

            Text(projection.detail)
                .foregroundStyle(.secondary)

            GroupBox("Identity being replaced") {
                VStack(alignment: .leading, spacing: 8) {
                    recoveryValue("Host ID", projection.hostID)
                    recoveryValue("Fingerprint", projection.fingerprint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("This action will:")
                    .font(.headline)
                ForEach(projection.consequences, id: \.self) { consequence in
                    Label(
                        consequenceDetail(consequence),
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundStyle(.primary)
                }
            }

            if projection.showsProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for durable recovery to complete.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if projection.showsCancel {
                    Button("Cancel", role: .cancel) {
                        perform(.cancelReview)
                    }
                }
                Spacer()
                if let action = projection.primaryAction,
                   let title = projection.primaryTitle {
                    if projection.primaryIsDestructive {
                        Button(title, role: .destructive) { perform(action) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(title) { perform(action) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 500)
        .interactiveDismissDisabled(projection.preventsImplicitDismissal)
    }

    private func recoveryValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel(label)
                .accessibilityValue(value)
        }
    }

    private func consequenceDetail(
        _ consequence: MacHostIdentityRecoveryConsequenceV0
    ) -> String {
        switch consequence {
        case .stopRemoteAccess:
            "Stop remote access immediately"
        case .invalidateAllPairedPhones:
            "Invalidate every paired phone"
        case .removeAllCapabilityGrants:
            "Remove every capability grant"
        case .fenceQueuedAndActiveRemoteWork:
            "Fence queued and active remote work"
        case .requireRepairingEveryPhone:
            "Require every phone to pair again"
        }
    }
}
#endif
