#if os(macOS)
import CompanionPresentation
import SwiftUI

@available(macOS 14.0, *)
public struct MacGrantExpansionViewV0: View {
    private let projection: MacGrantReviewProjectionV0
    private let onApprove: () -> Void
    private let onDecline: () -> Void

    public init(
        presentation: LocalGrantExpansionPresentation,
        onApprove: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        projection = MacGrantReviewProjectionV0(presentation: presentation)
        self.onApprove = onApprove
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Capability request", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text("\(projection.deviceDisplayName) is asking for additional capabilities on this Mac.")
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(projection.capabilities, id: \.capabilityID) { capability in
                        capabilityCard(capability)
                    }
                }
            }

            statusView
            Divider()
            HStack {
                Button("Decline", role: .cancel, action: onDecline)
                    .disabled(!projection.canDecline)
                Spacer()
                Button("Allow on This Mac", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .disabled(!projection.canApprove)
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 460)
    }

    private func capabilityCard(
        _ capability: MacGrantCapabilityProjectionV0
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(capability.title)
                .font(.headline)
            Text(capability.summary)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                ForEach(Array(capability.effects.enumerated()), id: \.offset) { _, effect in
                    GridRow {
                        Label(
                            effect.title,
                            systemImage: effect.requiresAttention
                                ? "exclamationmark.circle"
                                : "checkmark.circle"
                        )
                        .foregroundStyle(effect.requiresAttention ? .primary : .secondary)
                        Text(effect.detail)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(capability.capabilityID)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusView: some View {
        switch projection.status {
        case .reviewing:
            Text("Review every effect before allowing these capabilities.")
                .foregroundStyle(.secondary)
        case .applying:
            ProgressView("Saving the exact grant…")
        case .applied:
            Label("Capabilities allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .declined:
            Label("Request declined", systemImage: "xmark.circle")
        case .failed:
            Label(
                "The grant was not changed. You can review and try again.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }
}
#endif
