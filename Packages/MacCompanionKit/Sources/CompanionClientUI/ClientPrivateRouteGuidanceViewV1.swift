#if os(iOS)
import SwiftUI

@available(iOS 17.0, *)
public struct ClientPrivateRouteGuidanceViewV1: View {
    private let projection: ClientPrivateRouteGuidanceProjectionV1

    public init(projection: ClientPrivateRouteGuidanceProjectionV1) {
        self.projection = projection
    }

    public var body: some View {
        Form {
            Section("Connection") {
                Label(projection.status.title, systemImage: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(projection.status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(projection.methods) { method in
                Section(method.title) {
                    Text(method.summary)
                        .foregroundStyle(.secondary)
                    ForEach(Array(method.steps.enumerated()), id: \.offset) {
                        index, step in
                        LabeledContent(String(index + 1)) {
                            Text(step)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }

            Section("Security Boundary") {
                Text(projection.securityBoundary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Private Access")
    }

    private var statusSymbol: String {
        switch projection.status.tone {
        case .neutral: "network"
        case .progress: "arrow.clockwise"
        case .success: "checkmark.shield"
        case .needsAttention: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch projection.status.tone {
        case .success: .green
        case .needsAttention: .orange
        case .neutral, .progress: .primary
        }
    }
}
#endif
