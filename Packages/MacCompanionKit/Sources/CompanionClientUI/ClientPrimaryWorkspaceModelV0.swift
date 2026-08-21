import CompanionClient
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionWire
import Combine
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class ClientPrimaryWorkspaceModelV0: ObservableObject {
    @Published public private(set) var projection:
        ClientPrimaryWorkspaceProjectionV0
    @Published public private(set) var projectionFailed = false

    private let macName: String
    private let primaryState:
        NetworkClientPrimaryApplicationStateV0
    private let monotonicNowMilliseconds:
        @Sendable () -> Int64
    private let updates: AsyncStream<
        NetworkClientPrimaryApplicationSnapshotV0
    >
    private var updateTask: Task<Void, Never>?

    public convenience init(
        macName: String,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64
    ) throws {
        try self.init(
            macName: macName,
            primaryState: primaryState,
            initialSnapshot: primaryState.snapshot(),
            updates: primaryState.updates,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    package init(
        macName: String,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        initialSnapshot: NetworkClientPrimaryApplicationSnapshotV0,
        updates: AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64
    ) throws {
        self.macName = macName
        self.primaryState = primaryState
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.updates = updates
        projection = try ClientPrimaryWorkspaceProjectionV0(
            macName: macName,
            snapshot: initialSnapshot,
            monotonicNowMilliseconds: monotonicNowMilliseconds()
        )
    }

    public func start() {
        guard updateTask == nil else { return }
        let updates = updates
        updateTask = Task { [weak self, updates] in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    public func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    public func refreshStatus() async throws {
        try await primaryState.refreshStatus()
    }

    public func loadNextActivityPage(limit: UInt8 = 50) async throws {
        try await primaryState.loadNextActivityPage(limit: limit)
    }

    public func resetActivityTraversal() async throws {
        try await primaryState.resetActivityTraversal()
    }

    public func reloadApprovedActions() async throws {
        try await primaryState.reloadApprovedActions()
    }

    @discardableResult
    public func beginOperation(
        capabilityID: String,
        parameters: CanonicalJSONValue,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        try await primaryState.beginOperation(
            capabilityID: capabilityID,
            parameters: parameters,
            operationID: operationID
        )
    }

    @discardableResult
    public func resumeOperationStatus(
        capabilityID: String,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        try await primaryState.resumeOperationStatus(
            capabilityID: capabilityID,
            operationID: operationID
        )
    }

    @discardableResult
    public func queryOperation() async throws -> ClientActChannelEventV1 {
        try await primaryState.queryOperation()
    }

    @discardableResult
    public func cancelOperation() async throws -> ClientActChannelEventV1 {
        try await primaryState.cancelOperation()
    }

    public func finishOperation() async throws {
        try await primaryState.finishOperation()
    }

    @discardableResult
    public func beginInteractiveControl(
        effects: Set<InteractiveControlEffect>
    ) async throws -> ClientInteractivePrimarySessionEventV0 {
        try await primaryState.beginInteractiveControl(effects: effects)
    }

    @discardableResult
    public func endInteractiveControl()
        async throws -> ClientInteractivePrimarySessionEventV0
    {
        try await primaryState.endInteractiveControl()
    }

    private func apply(_ snapshot: NetworkClientPrimaryApplicationSnapshotV0) {
        guard snapshot.revision > projection.revision else { return }
        do {
            projection = try ClientPrimaryWorkspaceProjectionV0(
                macName: macName,
                snapshot: snapshot,
                monotonicNowMilliseconds: monotonicNowMilliseconds()
            )
            projectionFailed = false
        } catch {
            projectionFailed = true
        }
    }

    deinit {
        updateTask?.cancel()
    }
}
