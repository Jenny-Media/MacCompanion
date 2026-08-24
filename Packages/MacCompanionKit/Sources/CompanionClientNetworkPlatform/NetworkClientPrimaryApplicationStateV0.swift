import CompanionClient
import CompanionDiscovery
import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionWire
import Foundation

public enum NetworkClientPrimaryAvailabilityV0:
    String, Equatable, Sendable
{
    case disconnected
    case connected
}

/// Content-free provenance retained only for the exact selected authenticated
/// route. Direct private addresses remain unclassified because an address does
/// not prove LAN or private-network provenance.
public enum NetworkClientAuthenticatedRouteClassV1:
    String, Equatable, Sendable
{
    case lan
    case privateDNS
    case privateNetwork

    package static func project(
        _ record: ClientConfiguredRouteRecordV1?
    ) -> Self? {
        switch record?.provenance {
        case .localDiscovery: .lan
        case .privateDNS: .privateDNS
        case .privateNetwork: .privateNetwork
        case .directPrivateAddress, nil: nil
        }
    }
}

public enum NetworkClientPrimaryApplicationCommandErrorV0:
    Error, Equatable, Sendable
{
    case unavailable
}

public enum NetworkClientPrimaryControlPreparationPhaseV0:
    String, Equatable, Sendable
{
    case roleChannelsConnecting
    case roleChannelsReady
    case initialSurface
}

public enum NetworkClientPrimaryControlStateV0: Equatable, Sendable {
    case inactive
    case requestSubmitted(effects: [InteractiveControlEffect])
    case approvalSubmitted(effects: [InteractiveControlEffect])
    case accepted(
        interactiveSessionID: UUID,
        expiresAtUnixMilliseconds: Int64,
        effects: [InteractiveControlEffect]
    )
    case preparing(
        interactiveSessionID: UUID,
        expiresAtUnixMilliseconds: Int64,
        effects: [InteractiveControlEffect],
        phase: NetworkClientPrimaryControlPreparationPhaseV0
    )
    case active(
        interactiveSessionID: UUID,
        expiresAtUnixMilliseconds: Int64,
        effects: [InteractiveControlEffect]
    )
    case ending(
        interactiveSessionID: UUID,
        effects: [InteractiveControlEffect]
    )
    case endFailed(
        interactiveSessionID: UUID,
        effects: [InteractiveControlEffect],
        error: ClientInteractiveRemoteErrorV0
    )
    case preparationFailed(
        interactiveSessionID: UUID,
        effects: [InteractiveControlEffect],
        phase: NetworkClientPrimaryControlPreparationPhaseV0
    )
    case remoteRejected(ClientInteractiveRemoteErrorV0)
}

package enum NetworkClientInteractiveProductProgressV0:
    Equatable, Sendable
{
    case roleChannelsConnecting
    case roleChannelsReady
    case initialSurfacePreparing
    case active
    case failed(NetworkClientPrimaryControlPreparationPhaseV0)
}

package struct NetworkClientInteractiveRoleCompositionV0: Sendable {
    package let endpoint: EndpointCandidate
    package let authenticatedSession: ClientAuthenticatedSessionV0
    package let interactiveSession: ClientInteractiveAcceptedSessionV0
}

public struct NetworkClientPrimaryApplicationSnapshotV0: Sendable {
    public let revision: UInt64
    public let hostID: UUID
    public let availability: NetworkClientPrimaryAvailabilityV0
    public let authenticatedRouteClass:
        NetworkClientAuthenticatedRouteClassV1?
    public let authenticatedSession: ClientAuthenticatedSessionV0?
    public let observeChannel: ClientObserveChannelV0?
    public let actChannel: ClientActChannelV1?
    public let controlChannel: ClientInteractivePrimaryChannelV0?
    public let observedStatus: ClientObservedStatusV0?
    public let latestAuditPage: AuditListResponseBodyV1?
    public let statusError: ClientObserveRemoteErrorV0?
    public let auditError: ClientObserveRemoteErrorV0?
    public let latestObserveErrorRequest: ClientObserveRequestKindV0?
    public let catalog: GrantedCapabilityCatalogV1?
    public let operationState: ClientOperationSessionStateV1?
    public let approvalPrompt: ClientOperationApprovalPromptV1?
    public let catalogRemoteError: ClientOperationRemoteErrorV1?
    public let operationRemoteError: ClientOperationRemoteErrorV1?
    public let latestActErrorRequest: ClientActRequestKindV1?
    public let controlState: NetworkClientPrimaryControlStateV0

    public var connectionID: Data? {
        authenticatedSession?.connectionID
    }
}

/// Latest-one application state for one expected paired host. Product event
/// callbacks mutate synchronously under a narrow lock; consumers observe
/// immutable snapshots through a bounded stream and fence by `revision`.
public final class NetworkClientPrimaryApplicationStateV0:
    @unchecked Sendable
{
    private struct Storage {
        var revision: UInt64 = 0
        var session: ClientAuthenticatedSessionV0?
        var selectedEndpoint: EndpointCandidate?
        var authenticatedRouteClass:
            NetworkClientAuthenticatedRouteClassV1?
        var observeChannel: ClientObserveChannelV0?
        var actChannel: ClientActChannelV1?
        var controlChannel: ClientInteractivePrimaryChannelV0?
        var observedStatus: ClientObservedStatusV0?
        var latestAuditPage: AuditListResponseBodyV1?
        var statusError: ClientObserveRemoteErrorV0?
        var auditError: ClientObserveRemoteErrorV0?
        var latestObserveErrorRequest: ClientObserveRequestKindV0?
        var catalog: GrantedCapabilityCatalogV1?
        var operationState: ClientOperationSessionStateV1?
        var approvalPrompt: ClientOperationApprovalPromptV1?
        var catalogRemoteError: ClientOperationRemoteErrorV1?
        var operationRemoteError: ClientOperationRemoteErrorV1?
        var latestActErrorRequest: ClientActRequestKindV1?
        var controlState: NetworkClientPrimaryControlStateV0 = .inactive
        var acceptedControlSession: ClientInteractiveAcceptedSessionV0?
        var droppedStaleEventCount: UInt64 = 0
    }

    public let hostID: UUID
    public let updates: AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>

    private let lock = NSLock()
    private let continuation: AsyncStream<
        NetworkClientPrimaryApplicationSnapshotV0
    >.Continuation
    private let selectedPrimaryTerminated: @Sendable () -> Void
    private var storage = Storage()

    public init(
        hostID: UUID,
        selectedPrimaryTerminated: @escaping @Sendable () -> Void = {}
    ) {
        self.hostID = hostID
        self.selectedPrimaryTerminated = selectedPrimaryTerminated
        let pair = AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = pair.stream
        continuation = pair.continuation
        continuation.yield(makeSnapshot(storage))
    }

    public var productEvents: NetworkClientPrimaryProductEventsV0 {
        NetworkClientPrimaryProductEventsV0(
            publishObserve: { [weak self] in self?.accept($0) },
            publishAct: { [weak self] in self?.accept($0) },
            publishControl: { [weak self] in self?.accept($0) },
            primarySelected: { [weak self] in self?.select($0) },
            primaryTerminated: { [weak self] hostID, connectionID in
                self?.terminate(hostID: hostID, connectionID: connectionID)
            }
        )
    }

    public func snapshot() -> NetworkClientPrimaryApplicationSnapshotV0 {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshot(storage)
    }

    public func droppedStaleEventCount() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return storage.droppedStaleEventCount
    }

    package func acceptedControlSessionForRoleChannelComposition()
        -> NetworkClientInteractiveRoleCompositionV0?
    {
        lock.lock()
        defer { lock.unlock() }
        guard let session = storage.session,
              let endpoint = storage.selectedEndpoint,
              let interactiveSession = storage.acceptedControlSession,
              interactiveSession.primary.hostID == session.hostID,
              interactiveSession.primary.clientID == session.clientID,
              interactiveSession.primary.primaryConnectionID
                == session.connectionID,
              interactiveSession.primary.authorizationEpoch
                == session.authorizationEpoch else { return nil }
        return NetworkClientInteractiveRoleCompositionV0(
            endpoint: endpoint,
            authenticatedSession: session,
            interactiveSession: interactiveSession
        )
    }

    package func makeInteractiveRolePairOwner(
        connector: any NetworkClientInteractiveRoleConnectingV0
    ) -> NetworkClientInteractiveRolePairOwnerV0? {
        guard let composition =
            acceptedControlSessionForRoleChannelComposition() else {
            return nil
        }
        return NetworkClientInteractiveRolePairOwnerV0(
            composition: composition,
            connector: connector,
            isCurrent: { [weak self] hostID, connectionID in
                self?.interactiveRoleCompositionIsCurrent(
                    composition,
                    hostID: hostID,
                    connectionID: connectionID
                ) ?? false
            }
        )
    }

    package func interactiveControlChannelForInitialDesktop()
        -> ClientInteractivePrimaryChannelV0?
    {
        lock.lock()
        defer { lock.unlock() }
        guard storage.acceptedControlSession != nil else { return nil }
        return storage.controlChannel
    }

    /// Accepts only monotonic product progress for the exact accepted Control
    /// session on the current primary connection. Transport readiness is kept
    /// distinct from a rendered and acknowledged interactive surface.
    package func acceptInteractiveProductProgress(
        connectionID: Data,
        interactiveSessionID: UUID,
        progress: NetworkClientInteractiveProductProgressV0
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrent(hostID: hostID, connectionID: connectionID),
              storage.acceptedControlSession?.interactiveSessionID
                == interactiveSessionID,
              let context = controlContext(
                interactiveSessionID: interactiveSessionID
              ) else {
            incrementDroppedStaleEventCount()
            return
        }
        guard let next = nextControlState(
            from: storage.controlState,
            context: context,
            progress: progress
        ) else { return }
        guard advanceRevision() else { return }
        storage.controlState = next
        continuation.yield(makeSnapshot(storage))
    }

    public func refreshStatus() async throws {
        let channel = try currentObserveChannel()
        try await channel.requestStatus()
    }

    public func loadNextActivityPage(limit: UInt8 = 50) async throws {
        let channel = try currentObserveChannel()
        try await channel.requestNextAuditPage(limit: limit)
    }

    public func resetActivityTraversal() async throws {
        let channel = try currentObserveChannel()
        try await channel.resetAudit()
    }

    public func reloadApprovedActions() async throws {
        let channel = try currentActChannel().channel
        try await channel.reloadCatalog()
    }

    @discardableResult
    public func beginOperation(
        capabilityID: String,
        parameters: CanonicalJSONValue,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        let current = try currentActChannel()
        let event = try await current.channel.beginOperation(
            capabilityID: capabilityID,
            parameters: parameters,
            operationID: operationID
        )
        acceptActCommandEvent(event, current: current)
        return event
    }

    @discardableResult
    public func resumeOperationStatus(
        capabilityID: String,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        let current = try currentActChannel()
        let event = try await current.channel.resumeOperationStatus(
            capabilityID: capabilityID,
            operationID: operationID
        )
        acceptActCommandEvent(event, current: current)
        return event
    }

    @discardableResult
    public func queryOperation() async throws -> ClientActChannelEventV1 {
        let current = try currentActChannel()
        let event = try await current.channel.queryOperation()
        acceptActCommandEvent(event, current: current)
        return event
    }

    @discardableResult
    public func cancelOperation() async throws -> ClientActChannelEventV1 {
        let current = try currentActChannel()
        let event = try await current.channel.cancelOperation()
        acceptActCommandEvent(event, current: current)
        return event
    }

    public func finishOperation() async throws {
        let current = try currentActChannel()
        try await current.channel.finishOperation()
        finishOperationState(connectionID: current.connectionID)
    }

    @discardableResult
    public func beginInteractiveControl(
        effects: Set<InteractiveControlEffect>
    ) async throws -> ClientInteractivePrimarySessionEventV0 {
        let channel = try currentControlChannel().channel
        return try await channel.beginSession(effects: effects)
    }

    @discardableResult
    public func endInteractiveControl()
        async throws -> ClientInteractivePrimarySessionEventV0
    {
        let channel = try currentControlChannel().channel
        return try await channel.endSession()
    }

    private func finishOperationState(connectionID: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrent(
            hostID: hostID,
            connectionID: connectionID
        ), advanceRevision() else { return }
        storage.operationState = nil
        storage.approvalPrompt = nil
        storage.operationRemoteError = nil
        if storage.latestActErrorRequest == .operation {
            storage.latestActErrorRequest = nil
        }
        continuation.yield(makeSnapshot(storage))
    }

    private func select(_ value: NetworkClientPrimaryProductSelectionV0) {
        let session = value.authenticatedSession
        guard session.hostID == hostID, session.connectionID.count == 16 else {
            recordStaleEvent()
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if storage.session?.connectionID == session.connectionID { return }
        guard advanceRevision() else { return }
        storage.session = session
        storage.selectedEndpoint = value.endpoint
        storage.authenticatedRouteClass = value.authenticatedRouteClass
        storage.observeChannel = value.observeChannel
        storage.actChannel = value.actChannel
        storage.controlChannel = value.controlChannel
        storage.observedStatus = nil
        storage.latestAuditPage = nil
        storage.statusError = nil
        storage.auditError = nil
        storage.latestObserveErrorRequest = nil
        clearActState()
        clearControlState()
        continuation.yield(makeSnapshot(storage))
    }

    private func terminate(hostID: UUID, connectionID: Data) {
        lock.lock()
        guard hostID == self.hostID,
              storage.session?.connectionID == connectionID else {
            incrementDroppedStaleEventCount()
            lock.unlock()
            return
        }
        guard advanceRevision() else {
            lock.unlock()
            return
        }
        storage.session = nil
        storage.selectedEndpoint = nil
        storage.authenticatedRouteClass = nil
        storage.observeChannel = nil
        storage.actChannel = nil
        storage.controlChannel = nil
        storage.statusError = nil
        storage.auditError = nil
        storage.latestObserveErrorRequest = nil
        clearActState()
        clearControlState()
        continuation.yield(makeSnapshot(storage))
        lock.unlock()
        selectedPrimaryTerminated()
    }

    private func accept(_ publication: NetworkClientObservePublicationV0) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrent(
            hostID: publication.hostID,
            connectionID: publication.connectionID
        ) else {
            incrementDroppedStaleEventCount()
            return
        }
        guard advanceRevision() else { return }
        switch publication.event {
        case let .status(value):
            storage.observedStatus = value
            storage.statusError = nil
            if storage.latestObserveErrorRequest == .status {
                storage.latestObserveErrorRequest = nil
            }
        case let .auditPage(value):
            storage.latestAuditPage = value
            storage.auditError = nil
            if storage.latestObserveErrorRequest == .audit {
                storage.latestObserveErrorRequest = nil
            }
        case let .remoteError(request, error):
            storage.latestObserveErrorRequest = request
            switch request {
            case .status: storage.statusError = error
            case .audit: storage.auditError = error
            }
        }
        continuation.yield(makeSnapshot(storage))
    }

    private func accept(_ publication: NetworkClientActPublicationV0) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrent(
            hostID: publication.hostID,
            connectionID: publication.connectionID
        ) else {
            incrementDroppedStaleEventCount()
            return
        }
        guard advanceRevision() else { return }
        switch publication.event {
        case let .catalogPublished(value):
            storage.catalog = value
            storage.operationState = nil
            storage.approvalPrompt = nil
            storage.catalogRemoteError = nil
            if storage.latestActErrorRequest == .catalog {
                storage.latestActErrorRequest = nil
            }
        case let .operationState(value):
            storage.operationState = value
            storage.approvalPrompt = nil
            storage.operationRemoteError = nil
            if storage.latestActErrorRequest == .operation {
                storage.latestActErrorRequest = nil
            }
        case let .operationApprovalSubmitted(value):
            storage.operationState = .awaitingApprovalReply
            storage.approvalPrompt = value
            storage.operationRemoteError = nil
            if storage.latestActErrorRequest == .operation {
                storage.latestActErrorRequest = nil
            }
        case let .remoteError(request, error):
            storage.latestActErrorRequest = request
            switch request {
            case .catalog:
                storage.catalog = nil
                storage.catalogRemoteError = error
            case .operation:
                storage.operationState = .remoteRejected(error)
                storage.approvalPrompt = nil
                storage.operationRemoteError = error
            }
        }
        continuation.yield(makeSnapshot(storage))
    }

    private func accept(_ publication: NetworkClientControlPublicationV0) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrent(
            hostID: publication.hostID,
            connectionID: publication.connectionID
        ) else {
            incrementDroppedStaleEventCount()
            return
        }
        guard controlEventIsAdmissible(publication.event) else {
            incrementDroppedStaleEventCount()
            return
        }
        guard advanceRevision() else { return }
        switch publication.event {
        case let .requestSubmitted(effects):
            storage.controlState = .requestSubmitted(effects: effects)
            storage.acceptedControlSession = nil
        case let .approvalSubmitted(effects):
            storage.controlState = .approvalSubmitted(effects: effects)
            storage.acceptedControlSession = nil
        case let .accepted(session, effects):
            storage.controlState = .accepted(
                interactiveSessionID: session.interactiveSessionID,
                expiresAtUnixMilliseconds:
                    session.expiresAtUnixMilliseconds,
                effects: effects
            )
            storage.acceptedControlSession = session
        case let .endSubmitted(interactiveSessionID, effects):
            storage.controlState = .ending(
                interactiveSessionID: interactiveSessionID,
                effects: effects
            )
        case .ended:
            storage.controlState = .inactive
            storage.acceptedControlSession = nil
        case let .endRejected(interactiveSessionID, error):
            let effects = controlEffects(
                interactiveSessionID: interactiveSessionID
            ) ?? []
            storage.controlState = .endFailed(
                interactiveSessionID: interactiveSessionID,
                effects: effects,
                error: error
            )
        case let .remoteRejected(error):
            storage.controlState = .remoteRejected(error)
            storage.acceptedControlSession = nil
        }
        continuation.yield(makeSnapshot(storage))
    }

    private func isCurrent(hostID: UUID, connectionID: Data) -> Bool {
        hostID == self.hostID
            && storage.session?.connectionID == connectionID
    }

    private func currentObserveChannel() throws -> ClientObserveChannelV0 {
        lock.lock()
        defer { lock.unlock() }
        guard let channel = storage.observeChannel else {
            throw NetworkClientPrimaryApplicationCommandErrorV0.unavailable
        }
        return channel
    }

    private func currentActChannel() throws -> (
        channel: ClientActChannelV1,
        connectionID: Data
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard let channel = storage.actChannel,
              let connectionID = storage.session?.connectionID else {
            throw NetworkClientPrimaryApplicationCommandErrorV0.unavailable
        }
        return (channel, connectionID)
    }

    private func currentControlChannel() throws -> (
        channel: ClientInteractivePrimaryChannelV0,
        connectionID: Data
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard let channel = storage.controlChannel,
              let connectionID = storage.session?.connectionID else {
            throw NetworkClientPrimaryApplicationCommandErrorV0.unavailable
        }
        return (channel, connectionID)
    }

    private func acceptActCommandEvent(
        _ event: ClientActChannelEventV1,
        current: (channel: ClientActChannelV1, connectionID: Data)
    ) {
        accept(NetworkClientActPublicationV0(
            hostID: hostID,
            connectionID: current.connectionID,
            event: event
        ))
    }

    private func clearActState() {
        storage.catalog = nil
        storage.operationState = nil
        storage.approvalPrompt = nil
        storage.catalogRemoteError = nil
        storage.operationRemoteError = nil
        storage.latestActErrorRequest = nil
    }

    private func clearControlState() {
        storage.controlState = .inactive
        storage.acceptedControlSession = nil
    }

    private func controlEventIsAdmissible(
        _ event: ClientInteractivePrimarySessionEventV0
    ) -> Bool {
        switch event {
        case let .endSubmitted(interactiveSessionID, effects):
            guard storage.acceptedControlSession?.interactiveSessionID
                    == interactiveSessionID,
                  let currentEffects = controlEffects(
                    interactiveSessionID: interactiveSessionID
                  ) else { return false }
            return effects == currentEffects
        case let .ended(interactiveSessionID, _):
            guard storage.acceptedControlSession?.interactiveSessionID
                    == interactiveSessionID,
                  case let .ending(currentSessionID, _) =
                    storage.controlState,
                  currentSessionID == interactiveSessionID else {
                return false
            }
            return true
        case let .endRejected(interactiveSessionID, _):
            guard storage.acceptedControlSession?.interactiveSessionID
                    == interactiveSessionID,
                  case let .ending(currentSessionID, _) =
                    storage.controlState,
                  currentSessionID == interactiveSessionID else {
                return false
            }
            return true
        case .requestSubmitted, .approvalSubmitted, .accepted,
             .remoteRejected:
            return true
        }
    }

    private func controlEffects(
        interactiveSessionID: UUID
    ) -> [InteractiveControlEffect]? {
        switch storage.controlState {
        case let .accepted(sessionID, _, effects),
             let .preparing(sessionID, _, effects, _),
             let .active(sessionID, _, effects),
             let .ending(sessionID, effects),
             let .endFailed(sessionID, effects, _),
             let .preparationFailed(sessionID, effects, _):
            return sessionID == interactiveSessionID ? effects : nil
        case .inactive, .requestSubmitted, .approvalSubmitted,
             .remoteRejected:
            return nil
        }
    }

    private typealias ControlContext = (
        interactiveSessionID: UUID,
        expiresAtUnixMilliseconds: Int64,
        effects: [InteractiveControlEffect]
    )

    private func controlContext(
        interactiveSessionID: UUID
    ) -> ControlContext? {
        switch storage.controlState {
        case let .accepted(sessionID, expiresAt, effects),
             let .preparing(sessionID, expiresAt, effects, _),
             let .active(sessionID, expiresAt, effects):
            guard sessionID == interactiveSessionID else { return nil }
            return (sessionID, expiresAt, effects)
        case let .preparationFailed(sessionID, effects, _),
             let .ending(sessionID, effects),
             let .endFailed(sessionID, effects, _):
            guard sessionID == interactiveSessionID,
                  let expiresAt = storage.acceptedControlSession?
                    .expiresAtUnixMilliseconds else { return nil }
            return (sessionID, expiresAt, effects)
        case .inactive, .requestSubmitted, .approvalSubmitted,
             .remoteRejected:
            return nil
        }
    }

    private func nextControlState(
        from current: NetworkClientPrimaryControlStateV0,
        context: ControlContext,
        progress: NetworkClientInteractiveProductProgressV0
    ) -> NetworkClientPrimaryControlStateV0? {
        let preparing: (
            NetworkClientPrimaryControlPreparationPhaseV0
        ) -> NetworkClientPrimaryControlStateV0 = { phase in
            .preparing(
                interactiveSessionID: context.interactiveSessionID,
                expiresAtUnixMilliseconds:
                    context.expiresAtUnixMilliseconds,
                effects: context.effects,
                phase: phase
            )
        }
        let failed: (
            NetworkClientPrimaryControlPreparationPhaseV0
        ) -> NetworkClientPrimaryControlStateV0 = { phase in
            .preparationFailed(
                interactiveSessionID: context.interactiveSessionID,
                effects: context.effects,
                phase: phase
            )
        }
        switch (current, progress) {
        case (.accepted, .roleChannelsConnecting):
            return preparing(.roleChannelsConnecting)
        case (.accepted, .failed(.roleChannelsConnecting)):
            return failed(.roleChannelsConnecting)
        case (
            .preparing(_, _, _, .roleChannelsConnecting),
            .roleChannelsReady
        ):
            return preparing(.roleChannelsReady)
        case (
            .preparing(_, _, _, .roleChannelsConnecting),
            .failed(.roleChannelsConnecting)
        ):
            return failed(.roleChannelsConnecting)
        case (
            .preparing(_, _, _, .roleChannelsReady),
            .initialSurfacePreparing
        ):
            return preparing(.initialSurface)
        case (
            .preparing(_, _, _, .roleChannelsReady),
            .failed(.initialSurface)
        ), (
            .preparing(_, _, _, .initialSurface),
            .failed(.initialSurface)
        ):
            return failed(.initialSurface)
        case (.preparing(_, _, _, .initialSurface), .active):
            return .active(
                interactiveSessionID: context.interactiveSessionID,
                expiresAtUnixMilliseconds:
                    context.expiresAtUnixMilliseconds,
                effects: context.effects
            )
        case (.active, .active),
             (.preparationFailed, .failed):
            return nil
        default:
            incrementDroppedStaleEventCount()
            return nil
        }
    }

    private func interactiveRoleCompositionIsCurrent(
        _ composition: NetworkClientInteractiveRoleCompositionV0,
        hostID: UUID,
        connectionID: Data
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hostID == self.hostID
            && connectionID == composition.authenticatedSession.connectionID
            && storage.session == composition.authenticatedSession
            && storage.selectedEndpoint == composition.endpoint
            && storage.acceptedControlSession
                == composition.interactiveSession
    }

    private func advanceRevision() -> Bool {
        guard storage.revision < UInt64.max else { return false }
        storage.revision += 1
        return true
    }

    private func incrementDroppedStaleEventCount() {
        if storage.droppedStaleEventCount < UInt64.max {
            storage.droppedStaleEventCount += 1
        }
    }

    private func recordStaleEvent() {
        lock.lock()
        incrementDroppedStaleEventCount()
        lock.unlock()
    }

    private func makeSnapshot(
        _ value: Storage
    ) -> NetworkClientPrimaryApplicationSnapshotV0 {
        NetworkClientPrimaryApplicationSnapshotV0(
            revision: value.revision,
            hostID: hostID,
            availability: value.session == nil ? .disconnected : .connected,
            authenticatedRouteClass: value.authenticatedRouteClass,
            authenticatedSession: value.session,
            observeChannel: value.observeChannel,
            actChannel: value.actChannel,
            controlChannel: value.controlChannel,
            observedStatus: value.observedStatus,
            latestAuditPage: value.latestAuditPage,
            statusError: value.statusError,
            auditError: value.auditError,
            latestObserveErrorRequest: value.latestObserveErrorRequest,
            catalog: value.catalog,
            operationState: value.operationState,
            approvalPrompt: value.approvalPrompt,
            catalogRemoteError: value.catalogRemoteError,
            operationRemoteError: value.operationRemoteError,
            latestActErrorRequest: value.latestActErrorRequest,
            controlState: value.controlState
        )
    }

    deinit {
        continuation.finish()
    }
}
