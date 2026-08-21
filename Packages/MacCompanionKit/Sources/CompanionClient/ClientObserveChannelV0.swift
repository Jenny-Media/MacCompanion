import CompanionObservation
import CompanionWire
import Dispatch
import Foundation

public struct ClientObserveChannelEnvironmentV0: Sendable {
    public let makeMessageID: @Sendable () throws -> WireUUID
    public let wallNowUnixMilliseconds: @Sendable () -> Int64
    public let monotonicNowMilliseconds: @Sendable () -> Int64

    public init(
        makeMessageID: @escaping @Sendable () throws -> WireUUID,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.makeMessageID = makeMessageID
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    public static let live = Self(
        makeMessageID: { WireUUID(UUID()) },
        wallNowUnixMilliseconds: {
            let value = Date().timeIntervalSince1970 * 1_000
            guard value >= 0, value <= Double(Int64.max) else { return -1 }
            return Int64(value.rounded(.down))
        },
        monotonicNowMilliseconds: {
            let value = DispatchTime.now().uptimeNanoseconds / 1_000_000
            guard value <= UInt64(Int64.max) else { return -1 }
            return Int64(value)
        }
    )
}

public enum ClientObserveChannelStateV0: String, Equatable, Sendable {
    case ready
    case invalidated
}

public enum ClientObserveRequestKindV0: String, Equatable, Sendable {
    case status
    case audit
}

public struct ClientObserveRemoteErrorV0: Equatable, Sendable {
    public let code: String
    public let retry: ProtocolErrorRetry
    public let safeArguments: CanonicalJSONValue

    public init(_ body: ProtocolErrorResponseBody) {
        code = body.code
        retry = body.retry
        safeArguments = body.safeArguments
    }
}

public struct ClientObservedStatusV0: Equatable, Sendable {
    public let snapshot: StatusSnapshotBody
    public let freshness: ObservationFreshness

    public init(
        snapshot: StatusSnapshotBody,
        freshness: ObservationFreshness
    ) {
        self.snapshot = snapshot
        self.freshness = freshness
    }
}

public enum ClientObserveChannelEventV0: Equatable, Sendable {
    case status(ClientObservedStatusV0)
    case auditPage(AuditListResponseBodyV1)
    case remoteError(
        request: ClientObserveRequestKindV0,
        error: ClientObserveRemoteErrorV0
    )
}

public enum ClientObserveChannelErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidState(ClientObserveChannelStateV0)
    case statusRequestPending
    case invalidClock
    case duplicateMessageID
    case sendFailed
    case invalidFrame
    case invalidCorrelation
    case unexpectedMessage(WireMessageKind)
    case hostMismatch
    case statusSequenceViolation
    case freshnessRejected
    case auditRejected
}

/// One authenticated Observe lane owner. Status and audit may each have one
/// pending read; all outward publication is deferred to the primary router.
public actor ClientObserveChannelV0: ClientPrimaryReplyReceivingV0 {
    public let authenticatedSession: ClientAuthenticatedSessionV0
    public private(set) var state: ClientObserveChannelStateV0 = .ready
    public private(set) var retainedStatus: ClientObservedStatusV0?
    public private(set) var auditPager = ClientAuditPagerV1()

    private struct PendingStatus: Sendable {
        let messageID: WireUUID
        let startedAtMonotonicMilliseconds: Int64
    }

    private let sender: any ClientAuthenticatedCommandSendingV1
    private let environment: ClientObserveChannelEnvironmentV0
    private let publish: @Sendable (ClientObserveChannelEventV0) -> Void
    private var pendingStatus: PendingStatus?
    private var pendingAuditMessageID: WireUUID?
    private var generation: UInt64 = 0
    private var issuedMessageIDs: [WireUUID] = []
    private var issuedMessageIDSet: Set<WireUUID> = []

    public init(
        authenticatedSession: ClientAuthenticatedSessionV0,
        sender: any ClientAuthenticatedCommandSendingV1,
        environment: ClientObserveChannelEnvironmentV0 = .live,
        publish: @escaping @Sendable (
            ClientObserveChannelEventV0
        ) -> Void = { _ in }
    ) throws {
        guard authenticatedSession.connectionID.count == 16,
              authenticatedSession.deviceState == .activeMonitorOnly
                || authenticatedSession.deviceState == .activeGranted else {
            throw ClientObserveChannelErrorV0.invalidConfiguration
        }
        self.authenticatedSession = authenticatedSession
        self.sender = sender
        self.environment = environment
        self.publish = publish
    }

    public func requestStatus() async throws {
        try requireReady()
        guard pendingStatus == nil else {
            throw ClientObserveChannelErrorV0.statusRequestPending
        }
        let messageID = try nextMessageID()
        let started = try monotonicNow()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: try wallNow(),
            body: StatusSnapshotRequestBody()
        ))
        let expectedGeneration = generation
        pendingStatus = PendingStatus(
            messageID: messageID,
            startedAtMonotonicMilliseconds: started
        )
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            guard state == .ready, generation == expectedGeneration else {
                throw ClientObserveChannelErrorV0.invalidState(state)
            }
            pendingStatus = nil
            throw ClientObserveChannelErrorV0.sendFailed
        }
        guard state == .ready, generation == expectedGeneration else {
            throw ClientObserveChannelErrorV0.invalidState(state)
        }
    }

    public func requestNextAuditPage(limit: UInt8 = 50) async throws {
        try requireReady()
        guard pendingAuditMessageID == nil else {
            throw ClientObserveChannelErrorV0.auditRejected
        }
        let messageID = try nextMessageID()
        let frame: Data
        do {
            frame = try auditPager.requestNextPage(
                messageID: messageID,
                limit: limit,
                sentAtUnixMilliseconds: try wallNow()
            )
        } catch {
            throw ClientObserveChannelErrorV0.auditRejected
        }
        let expectedGeneration = generation
        pendingAuditMessageID = messageID
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            guard state == .ready, generation == expectedGeneration else {
                throw ClientObserveChannelErrorV0.invalidState(state)
            }
            pendingAuditMessageID = nil
            auditPager.invalidate()
            throw ClientObserveChannelErrorV0.sendFailed
        }
        guard state == .ready, generation == expectedGeneration else {
            throw ClientObserveChannelErrorV0.invalidState(state)
        }
    }

    public func resetAudit() throws {
        try requireReady()
        guard pendingAuditMessageID == nil else {
            throw ClientObserveChannelErrorV0.auditRejected
        }
        auditPager.reset()
    }

    public func statusAssessment(
        monotonicNowMilliseconds: Int64
    ) throws -> ObservationAssessment? {
        try retainedStatus?.freshness.assess(
            reachability: state == .ready ? .reachable : .unreachable,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        try requireReady()
        let kind: WireMessageKind
        do { kind = try WireCodec.messageKind(from: frame) } catch {
            throw ClientObserveChannelErrorV0.invalidFrame
        }
        switch kind {
        case .statusSnapshotResponse:
            return try prepareStatus(frame)
        case .auditListResponse:
            return try prepareAudit(frame)
        case .error:
            return try prepareRemoteError(frame)
        default:
            throw ClientObserveChannelErrorV0.unexpectedMessage(kind)
        }
    }

    public func invalidatePrimaryReplyReceiver() async {
        guard state != .invalidated else { return }
        generation &+= 1
        state = .invalidated
        pendingStatus = nil
        pendingAuditMessageID = nil
        auditPager.invalidate()
    }

    private func prepareStatus(
        _ frame: Data
    ) throws -> ClientPrimaryPreparedReplyV0 {
        guard let pendingStatus else {
            throw ClientObserveChannelErrorV0.invalidCorrelation
        }
        let response: WireEnvelope<StatusSnapshotBody>
        do {
            response = try WireCodec.decode(
                WireEnvelope<StatusSnapshotBody>.self,
                from: frame
            )
        } catch {
            throw ClientObserveChannelErrorV0.freshnessRejected
        }
        guard response.correlationID == pendingStatus.messageID else {
            throw ClientObserveChannelErrorV0.invalidCorrelation
        }
        guard response.body.hostID.rawValue
                == authenticatedSession.hostID else {
            throw ClientObserveChannelErrorV0.hostMismatch
        }
        if let prior = retainedStatus {
            guard response.body.generation == prior.snapshot.generation,
                  response.body.revision > prior.snapshot.revision else {
                throw ClientObserveChannelErrorV0.statusSequenceViolation
            }
        }
        let freshness: ObservationFreshness
        do {
            freshness = try ObservationFreshness(
                observedAtUnixMilliseconds:
                    response.body.observedAtUnixMilliseconds,
                responseSentAtUnixMilliseconds:
                    response.sentAtUnixMilliseconds,
                requestStartedAtMonotonicMilliseconds:
                    pendingStatus.startedAtMonotonicMilliseconds,
                receivedAtMonotonicMilliseconds: try monotonicNow(),
                validForMilliseconds:
                    Int64(response.body.validForMilliseconds)
            )
        } catch {
            throw ClientObserveChannelErrorV0.freshnessRejected
        }
        let value = ClientObservedStatusV0(
            snapshot: response.body,
            freshness: freshness
        )
        self.pendingStatus = nil
        retainedStatus = value
        return ClientPrimaryPreparedReplyV0 { [publish] in
            publish(.status(value))
        }
    }

    private func prepareAudit(
        _ frame: Data
    ) throws -> ClientPrimaryPreparedReplyV0 {
        guard pendingAuditMessageID != nil else {
            throw ClientObserveChannelErrorV0.invalidCorrelation
        }
        let page: AuditListResponseBodyV1
        do { page = try auditPager.acceptPage(frame) } catch {
            pendingAuditMessageID = nil
            throw ClientObserveChannelErrorV0.auditRejected
        }
        pendingAuditMessageID = nil
        return ClientPrimaryPreparedReplyV0 { [publish] in
            publish(.auditPage(page))
        }
    }

    private func prepareRemoteError(
        _ frame: Data
    ) throws -> ClientPrimaryPreparedReplyV0 {
        let response: WireEnvelope<ProtocolErrorResponseBody>
        do {
            response = try WireCodec.decode(
                WireEnvelope<ProtocolErrorResponseBody>.self,
                from: frame
            )
        } catch {
            throw ClientObserveChannelErrorV0.invalidCorrelation
        }
        let request: ClientObserveRequestKindV0
        if response.correlationID == pendingStatus?.messageID {
            pendingStatus = nil
            request = .status
        } else if response.correlationID == pendingAuditMessageID {
            pendingAuditMessageID = nil
            auditPager.invalidate()
            request = .audit
        } else {
            throw ClientObserveChannelErrorV0.invalidCorrelation
        }
        let event = ClientObserveChannelEventV0.remoteError(
            request: request,
            error: ClientObserveRemoteErrorV0(response.body)
        )
        return ClientPrimaryPreparedReplyV0 { [publish] in
            publish(event)
        }
    }

    private func requireReady() throws {
        guard state == .ready else {
            throw ClientObserveChannelErrorV0.invalidState(state)
        }
    }

    private func nextMessageID() throws -> WireUUID {
        let value: WireUUID
        do { value = try environment.makeMessageID() } catch {
            throw ClientObserveChannelErrorV0.duplicateMessageID
        }
        guard issuedMessageIDSet.insert(value).inserted else {
            throw ClientObserveChannelErrorV0.duplicateMessageID
        }
        issuedMessageIDs.append(value)
        if issuedMessageIDs.count > 4_096 {
            issuedMessageIDSet.remove(issuedMessageIDs.removeFirst())
        }
        return value
    }

    private func wallNow() throws -> Int64 {
        let value = environment.wallNowUnixMilliseconds()
        guard (0...WireLimits.maximumSafeInteger).contains(value) else {
            throw ClientObserveChannelErrorV0.invalidClock
        }
        return value
    }

    private func monotonicNow() throws -> Int64 {
        let value = environment.monotonicNowMilliseconds()
        guard value >= 0 else {
            throw ClientObserveChannelErrorV0.invalidClock
        }
        return value
    }
}
