import CompanionTransport
import Foundation

public protocol ClientPairedHostInventoryV1: Sendable {
    /// Returns exactly one fully validated durable identity for `hostID`.
    /// Implementations fail closed if the inventory contains ambiguous state.
    func pairedHost(
        hostID: UUID
    ) async throws -> ClientDurablePairedHostV0?
}

public enum ClientConfiguredRouteLifecyclePhaseV1:
    String, Equatable, Sendable
{
    case active
    case background
    case closed
}

public enum ClientConfiguredRouteLifecycleErrorV1:
    Error, Equatable, Sendable
{
    case missingPairedHost
    case missingCatalog
    case identityChanged
    case background
    case transitionInProgress
    case closed
}

public struct ClientConfiguredRouteLifecycleSnapshotV1:
    Equatable, Sendable
{
    public let phase: ClientConfiguredRouteLifecyclePhaseV1
    public let pairedHost: ClientDurablePairedHostV0
    public let routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1
    public let reconnect: ClientConfiguredReconnectSnapshotV1
    public let isTransitioning: Bool
}

/// Sole app-lifecycle composition for one paired host. Startup validates the
/// exact durable identity and route snapshot before constructing any reconnect
/// authority. Every dial revalidates identity and reconciles durable route
/// state first. Background state retains the composition but cannot start a
/// round; identity loss, unreadable state, or an ambiguous transition closes
/// the live reconnect authority.
public actor ClientConfiguredRouteLifecycleV1 {
    public typealias ControllerFactory =
        ClientConfiguredReconnectOwnerV1.ControllerFactory
    public typealias RouteID = ClientConfiguredRouteEditorV1.RouteID

    public nonisolated let reconnectStateChanges: AsyncStream<Void>

    private let hostID: UUID
    private let pairedHosts: any ClientPairedHostInventoryV1
    private let reconnectOwner: ClientConfiguredReconnectOwnerV1
    private let updateService: ClientConfiguredRouteUpdateServiceV1
    private let pairedHost: ClientDurablePairedHostV0
    private var routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1
    private var phase: ClientConfiguredRouteLifecyclePhaseV1
    private var transitionInProgress = false

    public init(
        hostID: UUID,
        pairedHosts: any ClientPairedHostInventoryV1,
        routes: any ClientConfiguredRoutePersistenceV1,
        foreground: Bool,
        networkReachable: Bool,
        makeController: @escaping ControllerFactory,
        newRouteID: @escaping RouteID
    ) async throws {
        guard let pairedHost = try await pairedHosts.pairedHost(
            hostID: hostID
        ) else {
            throw ClientConfiguredRouteLifecycleErrorV1.missingPairedHost
        }
        guard let routeSnapshot = try await routes.snapshot(hostID: hostID)
        else {
            throw ClientConfiguredRouteLifecycleErrorV1.missingCatalog
        }
        let configuration = try ClientReconnectConfigurationV1(
            pairedHost: pairedHost,
            routeSnapshot: routeSnapshot
        )
        let reconnectOwner = try await ClientConfiguredReconnectOwnerV1(
            configuration: configuration,
            foreground: foreground,
            networkReachable: networkReachable,
            makeController: makeController
        )
        let updateService: ClientConfiguredRouteUpdateServiceV1
        let reconciledSnapshot: ClientConfiguredRouteCatalogSnapshotV1
        do {
            updateService = try await ClientConfiguredRouteUpdateServiceV1(
                pairedHost: pairedHost,
                persistence: routes,
                reconnectOwner: reconnectOwner,
                newRouteID: newRouteID
            )
            reconciledSnapshot = try await updateService
                .reconcileFromStorage()
        } catch {
            try? await reconnectOwner.close()
            throw error
        }
        self.hostID = hostID
        self.pairedHosts = pairedHosts
        self.reconnectOwner = reconnectOwner
        self.updateService = updateService
        self.pairedHost = pairedHost
        self.routeSnapshot = reconciledSnapshot
        reconnectStateChanges = reconnectOwner.stateChanges
        phase = foreground ? .active : .background
    }

    public func snapshot() async -> ClientConfiguredRouteLifecycleSnapshotV1 {
        ClientConfiguredRouteLifecycleSnapshotV1(
            phase: phase,
            pairedHost: pairedHost,
            routeSnapshot: routeSnapshot,
            reconnect: await reconnectOwner.snapshot(),
            isTransitioning: transitionInProgress
        )
    }

    @discardableResult
    public func apply(
        _ intent: ClientConfiguredRouteEditIntentV1
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        try beginTransition()
        defer { transitionInProgress = false }
        do {
            try await requireCurrentIdentity()
        } catch {
            await failClosed()
            throw error
        }
        do {
            routeSnapshot = try await updateService.apply(intent)
            return routeSnapshot
        } catch {
            if await reconnectOwner.snapshot().isClosed { phase = .closed }
            throw error
        }
    }

    @discardableResult
    public func reconcile() async throws
        -> ClientConfiguredRouteCatalogSnapshotV1
    {
        try beginTransition()
        defer { transitionInProgress = false }
        do {
            try await requireCurrentIdentity()
            routeSnapshot = try await updateService.reconcileFromStorage()
            return routeSnapshot
        } catch {
            await failClosed()
            throw error
        }
    }

    public func setForeground(
        _ value: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        do {
            try await requireCurrentIdentity()
            try await reconnectOwner.setForeground(
                value,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            phase = value ? .active : .background
        } catch {
            await failClosed()
            throw error
        }
    }

    public func setNetworkReachable(
        _ value: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        do {
            try await requireCurrentIdentity()
            try await reconnectOwner.setNetworkReachable(
                value,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            await failClosed()
            throw error
        }
    }

    public func startRound(
        roundID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        guard phase == .active else {
            throw ClientConfiguredRouteLifecycleErrorV1.background
        }
        do {
            try await requireCurrentIdentity()
            routeSnapshot = try await updateService.reconcileFromStorage()
            try await reconnectOwner.startRound(
                roundID: roundID,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            await failClosed()
            throw error
        }
    }

    public func primaryConnectionLost(
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        do {
            try await requireCurrentIdentity()
            try await reconnectOwner.connectionLost(
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            await failClosed()
            throw error
        }
    }

    public func identityLost() async {
        await failClosed()
    }

    public func close() async {
        await failClosed()
    }

    private func requireCurrentIdentity() async throws {
        guard let current = try await pairedHosts.pairedHost(hostID: hostID)
        else {
            await failClosed()
            throw ClientConfiguredRouteLifecycleErrorV1.missingPairedHost
        }
        guard current == pairedHost else {
            await failClosed()
            throw ClientConfiguredRouteLifecycleErrorV1.identityChanged
        }
    }

    private func beginTransition() throws {
        guard phase != .closed else {
            throw ClientConfiguredRouteLifecycleErrorV1.closed
        }
        guard !transitionInProgress else {
            throw ClientConfiguredRouteLifecycleErrorV1.transitionInProgress
        }
        transitionInProgress = true
    }

    private func failClosed() async {
        guard phase != .closed else { return }
        phase = .closed
        await updateService.close()
    }
}
