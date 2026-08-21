#if os(macOS)
import AppKit
import CompanionPresentation
import SwiftUI

public enum MacPairingSessionSheetActionV0:
    Equatable,
    Sendable
{
    case retryCreation
    case dismissPairing
    case retryDismissal
}

public enum MacPairingSessionViewErrorV0: Error, Equatable, Sendable {
    case idlePresentation
}

public struct MacPairingSessionSheetProjectionV0:
    Equatable,
    Sendable
{
    public let title: String
    public let detail: String
    public let showsQRCode: Bool
    public let showsProgress: Bool
    public let action: MacPairingSessionSheetActionV0?
    public let actionTitle: String?
    public let preventsImplicitDismissal: Bool

    public static func project(
        _ phase: MacPairingSessionPresentationPhaseV0
    ) -> Self? {
        switch phase {
        case .idle:
            nil
        case .creating:
            Self(
                title: "Creating pairing code",
                detail: "Preparing a temporary code from this Mac.",
                showsQRCode: false,
                showsProgress: true,
                action: nil,
                actionTitle: nil,
                preventsImplicitDismissal: true
            )
        case .creationFailed:
            Self(
                title: "Pairing code unavailable",
                detail: "Mac Companion could not confirm a temporary code.",
                showsQRCode: false,
                showsProgress: false,
                action: .retryCreation,
                actionTitle: "Try Again",
                preventsImplicitDismissal: true
            )
        case .presenting:
            Self(
                title: "Scan with Mac Companion",
                detail: "This temporary code expires and can be used only once.",
                showsQRCode: true,
                showsProgress: false,
                action: .dismissPairing,
                actionTitle: "Cancel Pairing",
                preventsImplicitDismissal: true
            )
        case .dismissing:
            Self(
                title: "Canceling pairing",
                detail: "Waiting for the Mac Agent to invalidate this code.",
                showsQRCode: true,
                showsProgress: true,
                action: nil,
                actionTitle: nil,
                preventsImplicitDismissal: true
            )
        case .dismissalFailed:
            Self(
                title: "Pairing cancellation unconfirmed",
                detail: "This code may still be active. Retry cancellation before closing.",
                showsQRCode: true,
                showsProgress: false,
                action: .retryDismissal,
                actionTitle: "Retry Cancellation",
                preventsImplicitDismissal: true
            )
        }
    }
}

@available(macOS 14.0, *)
public struct MacPairingSessionViewV0: View {
    private let projection: MacPairingSessionSheetProjectionV0
    private let image: NSImage?
    private let perform: (MacPairingSessionSheetActionV0) -> Void

    public init(
        presentation: MacPairingSessionPresentationV0,
        perform: @escaping (MacPairingSessionSheetActionV0) -> Void
    ) throws {
        guard let projection = MacPairingSessionSheetProjectionV0.project(
            presentation.phase
        ) else {
            throw MacPairingSessionViewErrorV0.idlePresentation
        }
        self.projection = projection
        if projection.showsQRCode,
           let receipt = presentation.visibleReceipt {
            image = try MacPairingQRCodeRendererV0.image(
                encodedText: receipt.encodedQRCode
            )
        } else {
            image = nil
        }
        self.perform = perform
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(projection.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 240, minHeight: 240)
                    .accessibilityLabel("Temporary pairing code")
            }

            Text(projection.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if projection.showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            if let action = projection.action,
               let title = projection.actionTitle {
                Button(title) { perform(action) }
            }
        }
        .padding(24)
        .frame(minWidth: 340)
        .interactiveDismissDisabled(projection.preventsImplicitDismissal)
    }
}
#endif
