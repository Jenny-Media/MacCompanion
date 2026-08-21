import CompanionWire
import Foundation

public enum ClientConfiguredRouteUpdateErrorV1:
    Error, Equatable, Sendable
{
    case missingCatalog
    case runtimeOutOfSync
    case transitionInProgress
    case closed
}

/// Sole edit-to-runtime composition boundary. A durable revision is the source
/// of truth. If publication may have advanced but runtime activation cannot be
/// proven, the prior reconnect owner is closed instead of continuing stale.
public actor ClientConfiguredRouteUpdateServiceV1 {
    public typealias RouteID = ClientConfiguredRouteEditorV1.RouteID

    private let pairedHost: ClientDurablePairedHostV0
    private let persistence: any ClientConfiguredRoutePersistenceV1
    private let reconnectOwner: ClientConfiguredReconnectOwnerV1
    private let newRouteID: RouteID
    private var transitionInProgress = false
    private var closed = false

    public init(
        pairedHost: ClientDurablePairedHostV0,
        persistence: any ClientConfiguredRoutePersistenceV1,
        reconnectOwner: ClientConfiguredReconnectOwnerV1,
        newRouteID: @escaping RouteID
    ) async throws {
        guard let stored = try await persistence.snapshot(
            hostID: pairedHost.hostID
        ) else {
            throw ClientConfiguredRouteUpdateErrorV1.missingCatalog
        }
        let runtime = await reconnectOwner.snapshot()
        guard stored.hostID == pairedHost.hostID,
              runtime.hostID == pairedHost.hostID,
              runtime.configurationRevision == stored.revision,
              runtime.reconnect.candidates
                == stored.catalog.records.map(\.endpoint),
              runtime.reconnect.requiredHostFingerprint
                == pairedHost.hostFingerprint,
              !runtime.isClosed else {
            try? await reconnectOwner.close()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
        self.pairedHost = pairedHost
        self.persistence = persistence
        self.reconnectOwner = reconnectOwner
        self.newRouteID = newRouteID
    }

    public func apply(
        _ intent: ClientConfiguredRouteEditIntentV1
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        try beginTransition()
        defer { transitionInProgress = false }
        guard let current = try await persistence.snapshot(
            hostID: pairedHost.hostID
        ) else {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.missingCatalog
        }
        try await requireRuntime(revision: current.revision)
        let replacement = try ClientConfiguredRouteEditorV1.apply(
            intent,
            to: current,
            newRouteID: newRouteID
        )

        do {
            _ = try await persistence.replaceAtomically(
                replacement,
                expectedRevision: current.revision
            )
        } catch {
            let visible = try? await persistence.snapshot(
                hostID: pairedHost.hostID
            )
            if visible?.revision != current.revision {
                await failClosed()
            }
            throw error
        }

        do {
            try await reconnectOwner.replaceConfiguration(
                ClientReconnectConfigurationV1(
                    pairedHost: pairedHost,
                    routeSnapshot: replacement
                )
            )
        } catch {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
        return replacement
    }

    /// Reconciles a revision durably published by a prior process or by a
    /// crash after rename but before runtime activation. Regression or an
    /// unreadable/mismatched runtime closes the current controller.
    @discardableResult
    public func reconcileFromStorage() async throws
        -> ClientConfiguredRouteCatalogSnapshotV1
    {
        try beginTransition()
        defer { transitionInProgress = false }
        guard let stored = try await persistence.snapshot(
            hostID: pairedHost.hostID
        ) else {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.missingCatalog
        }
        let runtime = await reconnectOwner.snapshot()
        guard !runtime.isClosed,
              runtime.hostID == pairedHost.hostID else {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
        if runtime.configurationRevision == stored.revision {
            try await requireRuntime(revision: stored.revision)
            return stored
        }
        guard runtime.configurationRevision < stored.revision else {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
        do {
            try await reconnectOwner.replaceConfiguration(
                ClientReconnectConfigurationV1(
                    pairedHost: pairedHost,
                    routeSnapshot: stored
                )
            )
        } catch {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
        return stored
    }

    public func close() async {
        if closed { return }
        closed = true
        await failClosed()
    }

    private func requireRuntime(revision: UInt64) async throws {
        let runtime = await reconnectOwner.snapshot()
        guard !runtime.isClosed,
              runtime.hostID == pairedHost.hostID,
              runtime.configurationRevision == revision else {
            await failClosed()
            throw ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
        }
    }

    private func beginTransition() throws {
        guard !closed else {
            throw ClientConfiguredRouteUpdateErrorV1.closed
        }
        guard !transitionInProgress else {
            throw ClientConfiguredRouteUpdateErrorV1.transitionInProgress
        }
        transitionInProgress = true
    }

    private func failClosed() async {
        try? await reconnectOwner.close()
    }
}
