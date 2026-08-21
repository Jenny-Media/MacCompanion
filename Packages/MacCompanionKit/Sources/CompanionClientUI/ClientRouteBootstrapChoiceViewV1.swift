#if os(iOS)
import CompanionClient
import CompanionDiscovery
import SwiftUI

@available(iOS 17.0, *)
public struct ClientRouteBootstrapChoiceViewV1: View {
    private let projection: ClientRouteBootstrapProjectionV1
    private let selections: [
        EndpointCandidate: ClientRouteConfigurationTypeV1
    ]
    private let onSelect: (
        EndpointCandidate, ClientRouteConfigurationTypeV1?
    ) -> Void
    private let onCancel: () -> Void
    private let onComplete: (
        [EndpointCandidate: ClientConfiguredRouteProvenanceV1]
    ) -> Void

    public init(
        plan: ClientConfiguredRouteBootstrapPlanV1,
        selections: [
            EndpointCandidate: ClientRouteConfigurationTypeV1
        ],
        onSelect: @escaping (
            EndpointCandidate, ClientRouteConfigurationTypeV1?
        ) -> Void,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (
            [EndpointCandidate: ClientConfiguredRouteProvenanceV1]
        ) -> Void
    ) {
        projection = ClientRouteBootstrapProjectionV1(plan: plan)
        self.selections = selections
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onComplete = onComplete
    }

    public var body: some View {
        Form {
            Section {
                Text("Mac Companion cannot infer a private route from a DNS name or public address. Choose how each endpoint is reached.")
                    .foregroundStyle(.secondary)
            }

            ForEach(projection.rows, id: \.endpoint) { row in
                Section(row.endpointText) {
                    Picker(
                        "Route Type",
                        selection: selectionBinding(for: row.endpoint)
                    ) {
                        Text("Choose…")
                            .tag(ClientRouteConfigurationTypeV1?.none)
                        ForEach(row.choices) { choice in
                            Text(choice.title)
                                .tag(Optional(choice))
                        }
                    }
                }
            }

            Section {
                Button("Continue") {
                    guard let choices = try? projection.domainChoices(
                        selections
                    ) else { return }
                    onComplete(choices)
                }
                .disabled(!projection.isComplete(selections))

                Button("Cancel", role: .cancel, action: onCancel)
            } footer: {
                Text("Cancel saves no route configuration and starts no connection.")
            }
        }
        .navigationTitle("Choose Private Routes")
    }

    private func selectionBinding(
        for endpoint: EndpointCandidate
    ) -> Binding<ClientRouteConfigurationTypeV1?> {
        Binding(
            get: { selections[endpoint] },
            set: { onSelect(endpoint, $0) }
        )
    }
}
#endif
