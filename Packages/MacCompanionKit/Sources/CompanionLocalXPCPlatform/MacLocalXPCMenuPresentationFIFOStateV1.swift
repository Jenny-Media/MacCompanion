#if os(macOS)
import Foundation

/// Peer-wide post-authentication cancellation ordering. Callers fence all
/// method admission and reply paths before claiming the one session cancel.
package struct MacLocalXPCPostAuthenticationTrafficFenceV1: Sendable {
    package private(set) var admitsTraffic = true
    private var sessionCancellationClaimed = false

    package init() {}

    @discardableResult
    package mutating func fence() -> Bool {
        guard admitsTraffic else { return false }
        admitsTraffic = false
        return true
    }

    package mutating func claimSessionCancellation() -> Bool {
        guard !admitsTraffic, !sessionCancellationClaimed else { return false }
        sessionCancellationClaimed = true
        return true
    }
}

/// Serialized admission state shared by the production XPC sender and focused
/// deterministic tests. Payloads and continuations stay with the peer owner;
/// this value owns only opaque local operation identities and ordering.
package struct MacLocalXPCMenuPresentationFIFOStateV1: Sendable {
    package struct Head: Equatable, Sendable {
        package let requestID: UUID
        package let operation: UInt64
        package let sent: Bool
    }

    package enum Admission: Equatable, Sendable {
        case admitted(operation: UInt64, startsImmediately: Bool)
        case cancelledBeforeAdmission
        case overflow(drainedRequestIDs: [UUID])
        case operationExhausted(drainedRequestIDs: [UUID])
        case terminal
    }

    package enum Cancellation: Equatable, Sendable {
        case absent
        case cancelledBeforeSend
        case terminalAfterSend(drainedRequestIDs: [UUID])
    }

    private struct Entry: Equatable, Sendable {
        let requestID: UUID
        let operation: UInt64
        var sent: Bool
    }

    private let limit: Int
    private var nextOperation: UInt64
    private var entries: [Entry] = []
    package private(set) var isTerminal = false

    package init(limit: Int = 8, nextOperation: UInt64 = 0) {
        precondition(limit > 0)
        self.limit = limit
        self.nextOperation = nextOperation
    }

    package var count: Int { entries.count }

    package var head: Head? {
        entries.first.map {
            Head(
                requestID: $0.requestID,
                operation: $0.operation,
                sent: $0.sent
            )
        }
    }

    package mutating func admit(
        requestID: UUID,
        cancelled: Bool
    ) -> Admission {
        guard !isTerminal else { return .terminal }
        guard !cancelled else { return .cancelledBeforeAdmission }
        guard entries.count < limit else {
            return .overflow(drainedRequestIDs: makeTerminal())
        }
        guard nextOperation < UInt64.max else {
            return .operationExhausted(
                drainedRequestIDs: makeTerminal()
            )
        }
        nextOperation += 1
        entries.append(
            Entry(
                requestID: requestID,
                operation: nextOperation,
                sent: false
            )
        )
        return .admitted(
            operation: nextOperation,
            startsImmediately: entries.count == 1
        )
    }

    @discardableResult
    package mutating func claimHeadForSend(
        requestID: UUID,
        operation: UInt64
    ) -> Bool {
        guard !isTerminal,
              !entries.isEmpty,
              entries[0].requestID == requestID,
              entries[0].operation == operation,
              !entries[0].sent else {
            return false
        }
        entries[0].sent = true
        return true
    }

    @discardableResult
    package mutating func completeHead(
        requestID: UUID,
        operation: UInt64
    ) -> Bool {
        guard !isTerminal,
              let first = entries.first,
              first.requestID == requestID,
              first.operation == operation,
              first.sent else {
            return false
        }
        entries.removeFirst()
        return true
    }

    package func admitsActiveCallback(
        requestID: UUID,
        operation: UInt64
    ) -> Bool {
        guard !isTerminal, let first = entries.first else { return false }
        return first.requestID == requestID
            && first.operation == operation
            && first.sent
    }

    package mutating func cancel(requestID: UUID) -> Cancellation {
        guard !isTerminal,
              let index = entries.firstIndex(where: {
                $0.requestID == requestID
              }) else {
            return .absent
        }
        if entries[index].sent {
            return .terminalAfterSend(drainedRequestIDs: makeTerminal())
        }
        entries.remove(at: index)
        return .cancelledBeforeSend
    }

    package mutating func fence() -> [UUID] {
        guard !isTerminal else { return [] }
        return makeTerminal()
    }

    private mutating func makeTerminal() -> [UUID] {
        isTerminal = true
        let requestIDs = entries.map(\.requestID)
        entries.removeAll()
        return requestIDs
    }
}
#endif
