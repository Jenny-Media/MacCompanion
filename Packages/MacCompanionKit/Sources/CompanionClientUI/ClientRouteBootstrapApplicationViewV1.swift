#if os(iOS)
import CompanionClient
import CompanionDiscovery
import SwiftUI

/// Value-owned first-pairing route choice surface. The view can select only
/// the provenance choices admitted by the package projection; it never infers
/// a route or performs persistence/network effects itself.
@available(iOS 17.0, *)
public struct ClientRouteBootstrapApplicationViewV1: View {
    private let plan: ClientConfiguredRouteBootstrapPlanV1
    private let onCancel: () -> Void
    private let onComplete: (
        [EndpointCandidate: ClientConfiguredRouteProvenanceV1]
    ) -> Void
    @State private var selections: [
        EndpointCandidate: ClientRouteConfigurationTypeV1
    ] = [:]

    public init(
        plan: ClientConfiguredRouteBootstrapPlanV1,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (
            [EndpointCandidate: ClientConfiguredRouteProvenanceV1]
        ) -> Void
    ) {
        self.plan = plan
        self.onCancel = onCancel
        self.onComplete = onComplete
    }

    public var body: some View {
        ClientRouteBootstrapChoiceViewV1(
            plan: plan,
            selections: selections,
            onSelect: { endpoint, choice in
                if let choice {
                    selections[endpoint] = choice
                } else {
                    selections.removeValue(forKey: endpoint)
                }
            },
            onCancel: onCancel,
            onComplete: onComplete
        )
    }
}
#endif
