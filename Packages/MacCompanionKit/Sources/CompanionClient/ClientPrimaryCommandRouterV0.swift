import CompanionTransport
import CompanionWire
import Foundation

public enum ClientPrimaryProductLaneV0: String, Hashable, Sendable {
    case observe
    case act
    case control
}

public enum ClientPrimaryCommandRouterStateV0: String, Equatable, Sendable {
    case configuring
    case ready
    case invalidated
}

public enum ClientPrimaryCommandRouterErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case invalidState(ClientPrimaryCommandRouterStateV0)
    case receiverAlreadyInstalled(ClientPrimaryProductLaneV0)
    case unregisteredLane(ClientPrimaryProductLaneV0)
    case wrongLaneKind(ClientPrimaryProductLaneV0, WireMessageKind)
    case invalidClock
    case invalidEnvelope
    case routingRejected
    case transportSendFailed
    case invalidated
}

public struct ClientPrimaryPreparedReplyV0: Sendable {
    private let commit: @Sendable () -> Void

    public init(commit: @escaping @Sendable () -> Void = {}) {
        self.commit = commit
    }

    fileprivate func publish() { commit() }
}

public struct ClientPrimaryPreparedEventV0: Sendable {
    private let commit: @Sendable () -> Void

    public init(commit: @escaping @Sendable () -> Void = {}) {
        self.commit = commit
    }

    fileprivate func publish() { commit() }
}

public protocol ClientPrimaryReplyReceivingV0: Sendable {
    /// Decode and update path-owned state, but defer outward publication until
    /// the router atomically checks that its connection generation is current.
    func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0
    func preparePrimaryEvent(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedEventV0
    func invalidatePrimaryReplyReceiver() async
}

public extension ClientPrimaryReplyReceivingV0 {
    func preparePrimaryEvent(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedEventV0 {
        throw ClientPrimaryCommandRouterErrorV0.routingRejected
    }
}

public struct ClientPrimaryLaneCommandSenderV0:
    ClientAuthenticatedCommandSendingV1,
    Sendable
{
    private let router: ClientPrimaryCommandRouterV0
    public let lane: ClientPrimaryProductLaneV0

    fileprivate init(
        router: ClientPrimaryCommandRouterV0,
        lane: ClientPrimaryProductLaneV0
    ) {
        self.router = router
        self.lane = lane
    }

    public func sendAuthenticatedCommand(_ frame: Data) async throws {
        try await router.send(frame, on: lane)
    }
}

/// One connection-scoped request/reply and ordered-event owner. Path receivers
/// still own exact bodies and state machines; this actor owns replay,
/// correlation, deadlines, and the non-crossable Observe/Act/Control lane
/// assignment.
public actor ClientPrimaryCommandRouterV0 {
    public let authenticatedSession: ClientAuthenticatedSessionV0
    public private(set) var state: ClientPrimaryCommandRouterStateV0 =
        .configuring

    private let transport: any ClientAuthenticatedCommandSendingV1
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private var receivers: [
        ClientPrimaryProductLaneV0: any ClientPrimaryReplyReceivingV0
    ] = [:]
    private var pending = InFlightCommandTracker()
    private var pendingLanes: [WireUUID: ClientPrimaryProductLaneV0] = [:]
    private var incomingReplay = ConnectionReplayWindow()
    private var incomingEventReplay = ConnectionReplayWindow()
    private var outgoingReplay = ConnectionReplayWindow()
    private var generation: UInt64 = 0

    public init(
        authenticatedSession: ClientAuthenticatedSessionV0,
        transport: any ClientAuthenticatedCommandSendingV1,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64
    ) throws {
        guard authenticatedSession.connectionID.count == 16,
              authenticatedSession.deviceState == .activeMonitorOnly
                || authenticatedSession.deviceState == .activeGranted else {
            throw ClientPrimaryCommandRouterErrorV0.invalidConfiguration
        }
        self.authenticatedSession = authenticatedSession
        self.transport = transport
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
    }

    public nonisolated func sender(
        for lane: ClientPrimaryProductLaneV0
    ) -> ClientPrimaryLaneCommandSenderV0 {
        ClientPrimaryLaneCommandSenderV0(router: self, lane: lane)
    }

    public func installReceiver(
        _ receiver: any ClientPrimaryReplyReceivingV0,
        for lane: ClientPrimaryProductLaneV0
    ) throws {
        guard state == .configuring else {
            throw ClientPrimaryCommandRouterErrorV0.invalidState(state)
        }
        guard receivers[lane] == nil else {
            throw ClientPrimaryCommandRouterErrorV0
                .receiverAlreadyInstalled(lane)
        }
        receivers[lane] = receiver
    }

    public func activate() throws {
        guard state == .configuring else {
            throw ClientPrimaryCommandRouterErrorV0.invalidState(state)
        }
        guard !receivers.isEmpty else {
            throw ClientPrimaryCommandRouterErrorV0.invalidConfiguration
        }
        state = .ready
    }

    public func receive(_ frame: Data) async throws {
        guard state == .ready else {
            throw ClientPrimaryCommandRouterErrorV0.invalidState(state)
        }
        let metadata: WireRoutingMetadata
        do {
            metadata = try WireCodec.routingMetadata(from: frame)
        } catch {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.invalidEnvelope
        }
        if metadata.channel == .events {
            try await receiveEvent(frame, metadata: metadata)
            return
        }
        guard let correlationID = metadata.correlationID else {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
        let lane: ClientPrimaryProductLaneV0
        let receiver: any ClientPrimaryReplyReceivingV0
        let expectedGeneration = generation
        do {
            try incomingReplay.admit(metadata.messageID)
            _ = try pending.resolve(
                correlationID: correlationID,
                responseKind: metadata.kind,
                nowMonotonicNanoseconds: monotonicNowNanoseconds()
            )
            guard let registeredLane = pendingLanes.removeValue(
                forKey: correlationID
            ), let registeredReceiver = receivers[registeredLane] else {
                throw ClientPrimaryCommandRouterErrorV0.routingRejected
            }
            lane = registeredLane
            receiver = registeredReceiver
        } catch {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
        do {
            let prepared = try await receiver.preparePrimaryReply(frame)
            guard state == .ready, generation == expectedGeneration,
                  receivers[lane] != nil else {
                throw ClientPrimaryCommandRouterErrorV0.invalidated
            }
            prepared.publish()
        } catch let error as ClientPrimaryCommandRouterErrorV0 {
            await invalidate()
            throw error
        } catch {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
    }

    public func invalidate() async {
        guard state != .invalidated else { return }
        generation &+= 1
        state = .invalidated
        let installed = Array(receivers.values)
        receivers.removeAll()
        pending = InFlightCommandTracker()
        pendingLanes.removeAll()
        incomingReplay = ConnectionReplayWindow()
        incomingEventReplay = ConnectionReplayWindow()
        outgoingReplay = ConnectionReplayWindow()
        for receiver in installed {
            await receiver.invalidatePrimaryReplyReceiver()
        }
    }

    fileprivate func send(
        _ frame: Data,
        on lane: ClientPrimaryProductLaneV0
    ) async throws {
        guard state == .ready else {
            throw ClientPrimaryCommandRouterErrorV0.invalidState(state)
        }
        guard receivers[lane] != nil else {
            throw ClientPrimaryCommandRouterErrorV0.unregisteredLane(lane)
        }
        let metadata: WireRoutingMetadata
        do {
            metadata = try WireCodec.routingMetadata(from: frame)
        } catch {
            throw ClientPrimaryCommandRouterErrorV0.invalidEnvelope
        }
        guard metadata.channel == .command else {
            throw ClientPrimaryCommandRouterErrorV0.invalidEnvelope
        }
        if metadata.kind == .interactiveSessionApprove {
            guard metadata.correlationID != nil else {
                throw ClientPrimaryCommandRouterErrorV0.invalidEnvelope
            }
        } else {
            guard metadata.correlationID == nil else {
                throw ClientPrimaryCommandRouterErrorV0.invalidEnvelope
            }
        }
        guard Self.requestKinds[lane]?.contains(metadata.kind) == true else {
            throw ClientPrimaryCommandRouterErrorV0.wrongLaneKind(
                lane,
                metadata.kind
            )
        }
        let now = monotonicNowNanoseconds()
        let (deadline, overflow) = now.addingReportingOverflow(
            V0ConnectionTiming.ordinaryCommandNanoseconds
        )
        guard !overflow else {
            throw ClientPrimaryCommandRouterErrorV0.invalidClock
        }
        let expectedGeneration = generation
        do {
            try outgoingReplay.admit(metadata.messageID)
            try pending.register(
                messageID: metadata.messageID,
                requestKind: metadata.kind,
                registeredAtMonotonicNanoseconds: now,
                deadlineMonotonicNanoseconds: deadline
            )
            pendingLanes[metadata.messageID] = lane
        } catch {
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
        do {
            try await transport.sendAuthenticatedCommand(frame)
        } catch {
            _ = pending.cancel(messageID: metadata.messageID)
            pendingLanes.removeValue(forKey: metadata.messageID)
            throw ClientPrimaryCommandRouterErrorV0.transportSendFailed
        }
        guard state == .ready, generation == expectedGeneration else {
            throw ClientPrimaryCommandRouterErrorV0.invalidated
        }
    }

    private static let requestKinds: [
        ClientPrimaryProductLaneV0: Set<WireMessageKind>
    ] = [
        .observe: [.statusSnapshotRequest, .auditListRequest],
        .act: [
            .capabilityRegistryRequest, .operationInvoke, .operationApprove,
            .operationStatusRequest, .operationCancel,
        ],
        .control: [
            .interactiveSessionRequest, .interactiveSessionApprove,
            .interactiveSessionEnd,
            .interactiveInitialSurfaceRequest,
            .interactiveInitialSurfaceAcknowledgement,
            .interactiveSurfaceTargetsRequest, .interactiveSurfaceSelect,
            .interactiveSurfaceAcknowledgement,
        ],
    ]

    private static let eventLanes: [
        WireMessageKind: ClientPrimaryProductLaneV0
    ] = [
        .interactiveSurfaceFocusChanged: .control,
    ]

    private func receiveEvent(
        _ frame: Data,
        metadata: WireRoutingMetadata
    ) async throws {
        guard metadata.correlationID == nil,
              let lane = Self.eventLanes[metadata.kind],
              let receiver = receivers[lane] else {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
        let expectedGeneration = generation
        do {
            try incomingEventReplay.admit(metadata.messageID)
            let prepared = try await receiver.preparePrimaryEvent(frame)
            guard state == .ready, generation == expectedGeneration,
                  receivers[lane] != nil else {
                throw ClientPrimaryCommandRouterErrorV0.invalidated
            }
            prepared.publish()
        } catch let error as ClientPrimaryCommandRouterErrorV0 {
            await invalidate()
            throw error
        } catch {
            await invalidate()
            throw ClientPrimaryCommandRouterErrorV0.routingRejected
        }
    }
}

public actor ClientActPrimaryReplyReceiverV1:
    ClientPrimaryReplyReceivingV0
{
    public let channel: ClientActChannelV1
    private let publish: @Sendable (ClientActChannelEventV1) -> Void

    public init(
        channel: ClientActChannelV1,
        publish: @escaping @Sendable (
            ClientActChannelEventV1
        ) -> Void = { _ in }
    ) {
        self.channel = channel
        self.publish = publish
    }

    public func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        guard let event = try await channel.receive(frame) else {
            return ClientPrimaryPreparedReplyV0()
        }
        return ClientPrimaryPreparedReplyV0 { [publish] in publish(event) }
    }

    public func invalidatePrimaryReplyReceiver() async {
        await channel.invalidate()
    }
}
