import Foundation

/// Fences the short iOS background grace used by the UIKit lifecycle bridge.
/// A stale deadline can never publish a background transition after the app
/// has already returned to the foreground.
public struct ClientApplicationBackgroundGraceV1: Sendable {
    public static let durationNanoseconds: UInt64 = 10_000_000_000

    public private(set) var pendingToken: UUID?

    public init() {}

    public mutating func begin(token: UUID) -> Bool {
        guard pendingToken == nil else { return false }
        pendingToken = token
        return true
    }

    @discardableResult
    public mutating func cancel() -> Bool {
        guard pendingToken != nil else { return false }
        pendingToken = nil
        return true
    }

    public mutating func consume(token: UUID) -> Bool {
        guard pendingToken == token else { return false }
        pendingToken = nil
        return true
    }
}
