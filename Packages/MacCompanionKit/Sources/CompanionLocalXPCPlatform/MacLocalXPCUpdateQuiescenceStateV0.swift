#if os(macOS)
import Foundation

public enum MacLocalXPCUpdateQuiescenceCommandV0:
    UInt32,
    CaseIterable,
    Equatable,
    Sendable
{
    case closeNetworkAdmission = 0
    case drainNetworkConnections = 1
    case reopenNetworkAdmission = 2
}

public enum MacLocalXPCUpdateQuiescenceErrorV0:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case commandFailed
    case malformedOrTransportError
    case replyTimedOut
    case cancelledAfterSend
}

/// Agent authority injected only into the authenticated, ready menu profile.
/// The transport owns peer identity, method authorization, single-flight, and
/// generation fencing before invoking this content-free lifecycle boundary.
public protocol MacLocalXPCUpdateQuiescenceHandlingV0: Sendable {
    func closeNetworkAdmissionForUpdate() async throws
    func drainNetworkConnectionsForUpdate() async throws
    func reopenNetworkAdmissionAfterUpdateFailure() async throws
}

package struct MacLocalXPCUpdateQuiescenceTransactionGateV0: Sendable {
    package struct Active: Equatable, Sendable {
        package let generation: UInt64
        package let operation: UInt64
        package let command: MacLocalXPCUpdateQuiescenceCommandV0
    }

    private(set) var generation: UInt64?
    private(set) var active: Active?
    private var nextOperation: UInt64 = 0

    package init() {}

    package mutating func bind(generation: UInt64) -> Bool {
        guard generation > 0, self.generation == nil, active == nil else {
            return false
        }
        self.generation = generation
        return true
    }

    package mutating func begin(
        generation: UInt64,
        command: MacLocalXPCUpdateQuiescenceCommandV0,
        permitted: Bool
    ) -> Active? {
        guard permitted, self.generation == generation, active == nil,
              nextOperation < UInt64.max else { return nil }
        nextOperation += 1
        let value = Active(
            generation: generation,
            operation: nextOperation,
            command: command
        )
        active = value
        return value
    }

    package func admits(_ value: Active) -> Bool {
        generation == value.generation && active == value
    }

    @discardableResult
    package mutating func finish(_ value: Active) -> Bool {
        guard admits(value) else { return false }
        active = nil
        return true
    }

    @discardableResult
    package mutating func invalidate(generation: UInt64) -> Active? {
        guard self.generation == generation else { return nil }
        self.generation = nil
        defer { active = nil }
        return active
    }
}
#endif
