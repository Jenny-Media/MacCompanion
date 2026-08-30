import CompanionClient
import CompanionTransport
import CompanionWire
import Foundation

private final class NetworkClientPrimaryTerminationRelayV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var pending = false

    func emit() {
        lock.lock()
        guard let handler else {
            pending = true
            lock.unlock()
            return
        }
        lock.unlock()
        handler()
    }

    func bind(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        let shouldEmit = pending
        pending = false
        lock.unlock()
        if shouldEmit { handler() }
    }
}

public struct NetworkClientConfiguredRouteApplicationProductV1: Sendable {
    public let lifecycle: ClientConfiguredRouteLifecycleV1
    public let binding: ClientConfiguredRouteApplicationBindingV1
    public let primaryState: NetworkClientPrimaryApplicationStateV0
    public let interactiveRoles:
        NetworkClientInteractiveRoleProductBindingV0

    package init(
        lifecycle: ClientConfiguredRouteLifecycleV1,
        binding: ClientConfiguredRouteApplicationBindingV1,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        interactiveRoles: NetworkClientInteractiveRoleProductBindingV0
    ) {
        self.lifecycle = lifecycle
        self.binding = binding
        self.primaryState = primaryState
        self.interactiveRoles = interactiveRoles
    }
}

/// Release construction for one selected durable paired host. Initial
/// scheduling is deliberately pessimistic; UIKit activity and Boolean-only
/// reachability may make it eligible only after durable reconciliation. Each
/// authenticated route owns an inert Observe/Act candidate; the reconnect
/// controller alone publishes the exact candidate it accepts as primary.
public enum NetworkClientConfiguredRouteApplicationProductFactoryV1 {
    public static func make(
        hostID: UUID,
        pairedHosts: any ClientPairedHostInventoryV1,
        routes: any ClientConfiguredRoutePersistenceV1,
        runtime: NetworkClientReconnectRuntimeV1
    ) async throws -> NetworkClientConfiguredRouteApplicationProductV1 {
        try await make(
            hostID: hostID,
            pairedHosts: pairedHosts,
            routes: routes,
            runtime: runtime,
            newRouteID: {
                let bytes = UUID().uuid
                return try withUnsafeBytes(of: bytes) {
                    try WireBytes16(Data($0))
                }
            },
            roundID: { UUID() }
        )
    }

    package static func make(
        hostID: UUID,
        pairedHosts: any ClientPairedHostInventoryV1,
        routes: any ClientConfiguredRoutePersistenceV1,
        runtime: NetworkClientReconnectRuntimeV1,
        newRouteID: @escaping ClientConfiguredRouteEditorV1.RouteID,
        roundID: @escaping ClientConfiguredRouteApplicationBindingV1.RoundID
    ) async throws -> NetworkClientConfiguredRouteApplicationProductV1 {
        try await make(
            hostID: hostID, pairedHosts: pairedHosts, routes: routes,
            connector: runtime.makeInteractiveRoleConnector(),
            monotonicNow: runtime.monotonicNow,
            newRouteID: newRouteID, roundID: roundID,
            makeController: { configuration, foreground, reachable, events in
                try NetworkClientConfiguredReconnectCompositionV1.makeController(
                    configuration: configuration, foreground: foreground,
                    networkReachable: reachable,
                    runtime: runtime.replacingProductEvents(
                        events.combined(with: runtime.productEvents)
                    )
                )
            }
        )
    }

    /// Shared composition, with transport construction injected at package
    /// scope. Both release and integration tests use these exact publication,
    /// termination, role ownership, and reconnect bindings.
    package static func make(
        hostID: UUID,
        pairedHosts: any ClientPairedHostInventoryV1,
        routes: any ClientConfiguredRoutePersistenceV1,
        connector: any NetworkClientInteractiveRoleConnectingV0,
        monotonicNow: @escaping ClientConfiguredRouteApplicationBindingV1.MonotonicNow,
        newRouteID: @escaping ClientConfiguredRouteEditorV1.RouteID,
        roundID: @escaping ClientConfiguredRouteApplicationBindingV1.RoundID,
        makeController: @escaping @Sendable (
            ClientReconnectConfigurationV1, Bool, Bool,
            NetworkClientPrimaryProductEventsV0
        ) throws -> ReconnectControllerV0
    ) async throws -> NetworkClientConfiguredRouteApplicationProductV1 {
        let terminationRelay = NetworkClientPrimaryTerminationRelayV1()
        let primaryState = NetworkClientPrimaryApplicationStateV0(
            hostID: hostID,
            selectedPrimaryTerminated: { terminationRelay.emit() }
        )
        let interactiveRoles = NetworkClientInteractiveRoleProductBindingV0(
            hostID: hostID,
            primaryState: primaryState,
            connector: connector
        )
        let events = primaryState.productEvents
            .combined(with: interactiveRoles.productEvents)
        let lifecycle = try await ClientConfiguredRouteLifecycleV1(
            hostID: hostID,
            pairedHosts: pairedHosts,
            routes: routes,
            foreground: false,
            networkReachable: false,
            makeController: { configuration, foreground, reachable in
                try makeController(configuration, foreground, reachable, events)
            },
            newRouteID: newRouteID
        )
        do {
            let binding = try await
                ClientConfiguredRouteApplicationBindingV1(
                    lifecycle: lifecycle,
                    monotonicNow: monotonicNow,
                    roundID: roundID
                )
            terminationRelay.bind { [weak binding] in
                Task {
                    try? await binding?.primaryConnectionLost()
                }
            }
            return NetworkClientConfiguredRouteApplicationProductV1(
                lifecycle: lifecycle,
                binding: binding,
                primaryState: primaryState,
                interactiveRoles: interactiveRoles
            )
        } catch {
            await interactiveRoles.close()
            await lifecycle.close()
            throw error
        }
    }
}
