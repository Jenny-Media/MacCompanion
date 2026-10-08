#if os(macOS)
import CompanionIPC
import CompanionPresentation
import SwiftUI

public enum MacPairingReviewSheetActionV0: Equatable, Sendable {
    case approve
    case decline
    case retryDecision
}

public enum MacPairingReviewViewErrorV0: Error, Equatable, Sendable {
    case idlePresentation
}

public struct MacPairingReviewSheetProjectionV0: Equatable, Sendable {
    public let authenticationString: String
    public let deviceNameDraft: String
    public let draftIssue: DeviceNameDraftIssue?
    public let allowsNameEditing: Bool
    public let showsProgress: Bool
    public let retryAction: MacPairingReviewSheetActionV0?

    public static func project(
        _ presentation: MacPairingReviewPresentationV0
    ) -> Self? {
        guard let review = presentation.review else { return nil }
        let allowsNameEditing: Bool
        let showsProgress: Bool
        let retryAction: MacPairingReviewSheetActionV0?
        switch presentation.phase {
        case .idle:
            return nil
        case .reviewing:
            allowsNameEditing = true
            showsProgress = false
            retryAction = nil
        case .deciding:
            allowsNameEditing = false
            showsProgress = true
            retryAction = nil
        case .decisionFailed:
            allowsNameEditing = false
            showsProgress = false
            retryAction = .retryDecision
        }
        return Self(
            authenticationString: review.authenticationString.rawValue,
            deviceNameDraft: presentation.deviceNameDraft,
            draftIssue: presentation.deviceNameDraftIssue(),
            allowsNameEditing: allowsNameEditing,
            showsProgress: showsProgress,
            retryAction: retryAction
        )
    }
}

@available(macOS 14.0, *)
public struct MacPairingReviewViewV0: View {
    private let projection: MacPairingReviewSheetProjectionV0
    private let onDraftChanged: @MainActor @Sendable (String) -> Void
    private let perform: (MacPairingReviewSheetActionV0) -> Void

    public init(
        presentation: MacPairingReviewPresentationV0,
        onDraftChanged: @escaping @MainActor @Sendable (String) -> Void,
        perform: @escaping (MacPairingReviewSheetActionV0) -> Void
    ) throws {
        guard let projection = MacPairingReviewSheetProjectionV0.project(
            presentation
        ) else {
            throw MacPairingReviewViewErrorV0.idlePresentation
        }
        self.projection = projection
        self.onDraftChanged = onDraftChanged
        self.perform = perform
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair and allow remote access")
                .font(.title2.weight(.semibold))

            Text("Compare this code with the one shown on the device. Approve only if they match.")
                .foregroundStyle(.secondary)

            Text(projection.authenticationString)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .textSelection(.disabled)
                .accessibilityLabel("Pairing comparison code")
                .accessibilityValue(projection.authenticationString)

            Text("Pairing allows this device to view your Mac’s screen and control its pointer, keyboard, and text input. It can reconnect without a session confirmation and stays trusted until you remove it in Devices. You can stop an active session from either app.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("For example, Jenny’s iPhone", text: Binding(
                get: { projection.deviceNameDraft },
                set: onDraftChanged
            ))
            .disabled(!projection.allowsNameEditing)

            if projection.allowsNameEditing,
               let issue = projection.draftIssue {
                Label(issueDetail(issue), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if projection.showsProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the Mac Agent to confirm the decision.")
                        .foregroundStyle(.secondary)
                }
            } else if let retry = projection.retryAction {
                Label(
                    "The decision was not confirmed. Retry the exact same decision.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Button("Retry Decision") { perform(retry) }
            } else {
                HStack {
                    Button("Decline", role: .cancel) {
                        perform(.decline)
                    }
                    Spacer()
                    Button("Pair & Allow Remote Access") { perform(.approve) }
                        .buttonStyle(.borderedProminent)
                        .disabled(projection.draftIssue != nil)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .interactiveDismissDisabled(true)
    }

    private func issueDetail(_ issue: DeviceNameDraftIssue) -> String {
        switch issue {
        case .empty: "Enter a local device name."
        case .tooLong: "Use a shorter device name."
        case .surroundingWhitespace: "Remove spaces at the beginning or end."
        case .nonCanonicalUnicode: "Use a standard Unicode spelling."
        case .unsupportedCharacters: "Remove unsupported or invisible characters."
        }
    }
}
#endif
