import Foundation

public enum ClientRouteConfigurationIntentAdapterErrorV1:
    Error, Equatable, Sendable
{
    case transitionInProgress
    case closed
}

/// Serialized UI boundary. The callback observes a snapshot only after the
/// lifecycle composition has both durably committed and activated it. Failed
/// edits publish nothing and retain their original error.
public actor ClientRouteConfigurationIntentAdapterV1 {
    public typealias Publish = @Sendable (
        ClientConfiguredRouteCatalogSnapshotV1
    ) async -> Void

    private let lifecycle: ClientConfiguredRouteLifecycleV1
    private let publish: Publish
    private var transitionInProgress = false
    private var closed = false

    public init(
        lifecycle: ClientConfiguredRouteLifecycleV1,
        publish: @escaping Publish
    ) {
        self.lifecycle = lifecycle
        self.publish = publish
    }

    @discardableResult
    public func submit(
        _ intent: ClientConfiguredRouteEditIntentV1
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        try beginTransition()
        defer { transitionInProgress = false }
        let snapshot = try await lifecycle.apply(intent)
        await publish(snapshot)
        return snapshot
    }

    @discardableResult
    public func reconcileAndPublish() async throws
        -> ClientConfiguredRouteCatalogSnapshotV1
    {
        try beginTransition()
        defer { transitionInProgress = false }
        let snapshot = try await lifecycle.reconcile()
        await publish(snapshot)
        return snapshot
    }

    public func close() async {
        if closed { return }
        closed = true
        await lifecycle.close()
    }

    private func beginTransition() throws {
        guard !closed else {
            throw ClientRouteConfigurationIntentAdapterErrorV1.closed
        }
        guard !transitionInProgress else {
            throw ClientRouteConfigurationIntentAdapterErrorV1
                .transitionInProgress
        }
        transitionInProgress = true
    }
}
