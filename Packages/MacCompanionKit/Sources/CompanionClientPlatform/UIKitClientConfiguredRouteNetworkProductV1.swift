#if os(iOS)
import CompanionClient
import CompanionClientNetworkPlatform
import Foundation

@available(iOS 17.0, *)
@MainActor
public struct UIKitClientConfiguredRouteNetworkProductV1 {
    public let lifecycle: ClientConfiguredRouteLifecycleV1
    public let primaryState: NetworkClientPrimaryApplicationStateV0
    public let interactiveRoles:
        NetworkClientInteractiveRoleProductBindingV0
    public let applicationOwner:
        UIKitClientConfiguredRouteNetworkApplicationOwnerV1

    package init(
        lifecycle: ClientConfiguredRouteLifecycleV1,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        interactiveRoles: NetworkClientInteractiveRoleProductBindingV0,
        applicationOwner:
            UIKitClientConfiguredRouteNetworkApplicationOwnerV1
    ) {
        self.lifecycle = lifecycle
        self.primaryState = primaryState
        self.interactiveRoles = interactiveRoles
        self.applicationOwner = applicationOwner
    }
}

/// Thin UIKit release factory over the complete Network-platform product.
/// The default owner has only Boolean reachability and application-activity
/// scheduling authority; it cannot infer or author routes.
@available(iOS 17.0, *)
@MainActor
public enum UIKitClientConfiguredRouteNetworkProductFactoryV1 {
    public static func make(
        hostID: UUID,
        pairedHosts: any ClientPairedHostInventoryV1,
        routes: any ClientConfiguredRoutePersistenceV1,
        runtime: NetworkClientReconnectRuntimeV1,
        failure: @escaping
            UIKitClientConfiguredRouteNetworkApplicationOwnerV1.Failure,
        stateChanged: @escaping
            UIKitClientConfiguredRouteNetworkApplicationOwnerV1.StateChanged = {
                _ in
            }
    ) async throws -> UIKitClientConfiguredRouteNetworkProductV1 {
        let network = try await
            NetworkClientConfiguredRouteApplicationProductFactoryV1.make(
                hostID: hostID,
                pairedHosts: pairedHosts,
                routes: routes,
                runtime: runtime
            )
        let owner = UIKitClientConfiguredRouteNetworkApplicationOwnerV1(
            binding: network.binding,
            failure: failure,
            stateChanged: stateChanged
        )
        return UIKitClientConfiguredRouteNetworkProductV1(
            lifecycle: network.lifecycle,
            primaryState: network.primaryState,
            interactiveRoles: network.interactiveRoles,
            applicationOwner: owner
        )
    }
}
#endif
