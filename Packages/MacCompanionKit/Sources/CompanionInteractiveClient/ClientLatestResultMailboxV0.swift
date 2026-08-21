import Foundation

public enum ClientLatestResultOfferV0: Equatable, Sendable {
    case accepted(scheduleDrain: Bool, replacedPending: Bool)
    case acceptedTerminal(scheduleDrain: Bool, replacedPending: Bool)
    case discardedNotNewer
    case rejectedTerminalPending
    case rejectedClosed
}

public struct ClientLatestResultOrderV0:
    Comparable,
    Equatable,
    Sendable
{
    public let generation: UInt64
    public let sequence: UInt64

    public init(generation: UInt64, sequence: UInt64) {
        self.generation = generation
        self.sequence = sequence
    }

    public static func < (
        lhs: ClientLatestResultOrderV0,
        rhs: ClientLatestResultOrderV0
    ) -> Bool {
        if lhs.generation != rhs.generation {
            return lhs.generation < rhs.generation
        }
        return lhs.sequence < rhs.sequence
    }
}

/// A one-slot callback-to-main-actor handoff. The caller schedules a drain only
/// when instructed; a scheduled drain remains owned until `completeDrain()`.
public final class ClientLatestResultMailboxV0<Value: Sendable>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var pending: Value?
    private var pendingOrder: ClientLatestResultOrderV0?
    private var drainScheduled = false
    private var terminalPending = false
    private var closed = false

    public init() {}

    @discardableResult
    public func offer(
        _ value: Value,
        order: ClientLatestResultOrderV0? = nil,
        terminal: Bool = false
    ) -> ClientLatestResultOfferV0 {
        lock.withLock {
            guard !closed else {
                return .rejectedClosed
            }
            guard !terminalPending else {
                return .rejectedTerminalPending
            }
            if !terminal,
               let order,
               let pendingOrder,
               order <= pendingOrder {
                return .discardedNotNewer
            }
            if terminal,
               let order,
               let pendingOrder,
               order.generation < pendingOrder.generation {
                return .discardedNotNewer
            }
            let replaced = pending != nil
            pending = value
            pendingOrder = order
            terminalPending = terminal
            let shouldSchedule = !drainScheduled
            drainScheduled = true
            if terminal {
                return .acceptedTerminal(
                    scheduleDrain: shouldSchedule,
                    replacedPending: replaced
                )
            }
            return .accepted(
                scheduleDrain: shouldSchedule,
                replacedPending: replaced
            )
        }
    }

    public func takePendingForScheduledDrain() -> Value? {
        lock.withLock {
            guard drainScheduled else { return nil }
            defer {
                pending = nil
                pendingOrder = nil
            }
            return pending
        }
    }

    /// Returns true only when the current drain owns one successor turn.
    public func completeDrain() -> Bool {
        lock.withLock {
            guard drainScheduled else { return false }
            if pending != nil {
                return true
            }
            terminalPending = false
            drainScheduled = false
            return false
        }
    }

    @discardableResult
    public func discardPending() -> Value? {
        lock.withLock {
            guard !terminalPending else { return nil }
            defer {
                pending = nil
                pendingOrder = nil
            }
            return pending
        }
    }

    @discardableResult
    public func close() -> Value? {
        lock.withLock {
            closed = true
            terminalPending = false
            drainScheduled = false
            defer {
                pending = nil
                pendingOrder = nil
            }
            return pending
        }
    }
}
