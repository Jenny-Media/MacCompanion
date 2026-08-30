import CompanionWire
import Foundation

public enum TransportGuardError: Error, Equatable, Sendable {
    case duplicateMessage(WireUUID)
    case duplicatePendingRequest(WireUUID)
    case inFlightLimitReached(Int)
    case unsupportedRequestKind(WireMessageKind)
    case unknownCorrelation(WireUUID)
    case unexpectedResponse(
        request: WireMessageKind,
        response: WireMessageKind
    )
    case invalidDeadline
    case requestExpired(WireUUID)
}

public struct ConnectionReplayWindow: Sendable {
    public static let v0Capacity = 4_096

    private let capacity: Int
    private var identifiers: [WireUUID] = []
    private var head = 0
    private var membership = Set<WireUUID>()

    public init(capacity: Int = v0Capacity) {
        precondition(capacity > 0)
        self.capacity = capacity
        identifiers.reserveCapacity(capacity)
    }

    public var count: Int { membership.count }

    public mutating func admit(_ messageID: WireUUID) throws {
        guard membership.insert(messageID).inserted else {
            throw TransportGuardError.duplicateMessage(messageID)
        }
        identifiers.append(messageID)

        if membership.count > capacity {
            membership.remove(identifiers[head])
            head += 1
        }
        if head >= capacity, head * 2 >= identifiers.count {
            identifiers.removeFirst(head)
            head = 0
        }
    }
}

public struct PendingCommand: Equatable, Sendable {
    public let messageID: WireUUID
    public let requestKind: WireMessageKind
    public let registeredAtMonotonicNanoseconds: UInt64
    public let deadlineMonotonicNanoseconds: UInt64
}

public struct InFlightCommandTracker: Sendable {
    public static let v0Limit = 32

    private let limit: Int
    private var pending: [WireUUID: PendingCommand] = [:]

    public init(limit: Int = v0Limit) {
        precondition(limit > 0)
        self.limit = limit
        pending.reserveCapacity(limit)
    }

    public var count: Int { pending.count }

    public mutating func register(
        messageID: WireUUID,
        requestKind: WireMessageKind,
        registeredAtMonotonicNanoseconds: UInt64,
        deadlineMonotonicNanoseconds: UInt64
    ) throws {
        guard Self.responseKinds[requestKind] != nil else {
            throw TransportGuardError.unsupportedRequestKind(requestKind)
        }
        guard deadlineMonotonicNanoseconds > registeredAtMonotonicNanoseconds else {
            throw TransportGuardError.invalidDeadline
        }
        guard pending[messageID] == nil else {
            throw TransportGuardError.duplicatePendingRequest(messageID)
        }
        guard pending.count < limit else {
            throw TransportGuardError.inFlightLimitReached(limit)
        }
        pending[messageID] = PendingCommand(
            messageID: messageID,
            requestKind: requestKind,
            registeredAtMonotonicNanoseconds: registeredAtMonotonicNanoseconds,
            deadlineMonotonicNanoseconds: deadlineMonotonicNanoseconds
        )
    }

    @discardableResult
    public mutating func resolve(
        correlationID: WireUUID,
        responseKind: WireMessageKind,
        nowMonotonicNanoseconds: UInt64
    ) throws -> PendingCommand {
        guard let command = pending[correlationID] else {
            throw TransportGuardError.unknownCorrelation(correlationID)
        }
        guard nowMonotonicNanoseconds < command.deadlineMonotonicNanoseconds else {
            pending.removeValue(forKey: correlationID)
            throw TransportGuardError.requestExpired(correlationID)
        }
        guard Self.responseKinds[command.requestKind]?.contains(responseKind) == true else {
            throw TransportGuardError.unexpectedResponse(
                request: command.requestKind,
                response: responseKind
            )
        }
        pending.removeValue(forKey: correlationID)
        return command
    }

    public mutating func expire(
        at nowMonotonicNanoseconds: UInt64
    ) -> [PendingCommand] {
        let expired = pending.values
            .filter { nowMonotonicNanoseconds >= $0.deadlineMonotonicNanoseconds }
            .sorted { $0.messageID.description < $1.messageID.description }
        for command in expired {
            pending.removeValue(forKey: command.messageID)
        }
        return expired
    }

    /// Removes one locally failed send without pretending a reply arrived.
    @discardableResult
    public mutating func cancel(
        messageID: WireUUID
    ) -> PendingCommand? {
        pending.removeValue(forKey: messageID)
    }

    private static let responseKinds: [WireMessageKind: Set<WireMessageKind>] = [
        .authHello: [.authChallenge, .error],
        .authProof: [.sessionDescribeResponse, .error],
        .pairingBegin: [.pairingChallenge, .error],
        .pairingProve: [.pairingPendingApproval, .error],
        .pairingResume: [.pairingResumeChallenge, .error],
        .pairingResumeProve: [.pairingComplete, .error],
        .statusSnapshotRequest: [.statusSnapshotResponse, .error],
        .capabilityRegistryRequest: [.capabilityRegistryResponse, .error],
        .auditListRequest: [.auditListResponse, .error],
        .operationInvoke: [
            .operationApprovalRequired, .operationStatusResponse, .error,
        ],
        .operationApprove: [.operationStatusResponse, .error],
        .operationStatusRequest: [.operationStatusResponse, .error],
        .operationCancel: [.operationStatusResponse, .error],
        .interactiveSessionRequest: [
            .interactiveSessionApprovalRequired, .error,
        ],
        .interactiveSessionApprove: [.interactiveSessionAccepted, .error],
        .interactiveSessionEnd: [.interactiveSessionEnded, .error],
        .interactiveDisplayCatalogRequest: [
            .interactiveDisplayCatalogResponse, .error,
        ],
        .interactiveDisplaySelect: [.interactiveDisplaySelected, .error],
        .interactiveInitialSurfaceRequest: [
            .interactiveInitialSurfaceDescriptor, .error,
        ],
        .interactiveInitialSurfaceAcknowledgement: [
            .interactiveInitialSurfaceAcknowledged, .error,
        ],
        .interactiveSurfaceTargetsRequest: [
            .interactiveSurfaceTargetsResponse, .error,
        ],
        .interactiveSurfaceSelect: [.interactiveSurfaceSelected, .error],
        .interactiveSurfaceAcknowledgement: [
            .interactiveSurfaceAcknowledged, .error,
        ],
        .keepalivePing: [.keepalivePong, .error],
    ]
}

public enum V0ConnectionTiming {
    public static let tcpConnectNanoseconds: UInt64 = 10_000_000_000
    public static let authenticationNanoseconds: UInt64 = 10_000_000_000
    public static let ordinaryCommandNanoseconds: UInt64 = 30_000_000_000
    public static let keepaliveIdleNanoseconds: UInt64 = 15_000_000_000
    public static let authenticatedLivenessNanoseconds: UInt64 = 45_000_000_000
}
