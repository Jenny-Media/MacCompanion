#if os(macOS)
import CompanionInteractiveWire
import Foundation

public enum MacLocalXPCInteractiveRoleDataErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case malformedOrTransportError
    case replyTimedOut
    case cancelledAfterSend
}

/// Agent-side exact-generation input capability.
public protocol MacLocalXPCInteractiveInputSendingV1: Sendable {
    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws
}

package protocol MacLocalXPCGenerationBoundInteractiveInputSendingV1:
    AnyObject, Sendable
{
    func applyInteractiveInput(
        generation: UInt64,
        endpointToken: UUID,
        envelope: InteractiveInputEnvelope
    ) async throws
}

/// Menu runtime reached only after authenticated transport, method, framing,
/// generation, and readiness checks.
public protocol MacLocalXPCInteractiveInputHandlingV1: Sendable {
    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        nowMonotonicNanoseconds: UInt64
    ) async throws
}

/// Menu-side one-record-at-a-time publisher.
public protocol MacLocalXPCInteractiveMediaPublishingV1: Sendable {
    func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) async throws
}

/// Agent rendezvous reached only after authenticated transport, method,
/// generation, readiness, fixed-header, and record-bound validation.
public protocol MacLocalXPCInteractiveMediaHandlingV1: Sendable {
    func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data,
        transportGeneration: UInt64
    ) async throws

    func invalidateInteractiveMedia(
        transportGeneration: UInt64
    ) async
}

package struct MacLocalXPCInteractiveRoleDataTransactionGateV1:
    Sendable
{
    package struct Active: Equatable, Sendable {
        package let generation: UInt64
        package let operation: UInt64
    }

    private(set) var generation: UInt64?
    private(set) var active: Active?
    private var nextOperation: UInt64 = 0

    package init() {}

    package mutating func bind(generation: UInt64) -> Bool {
        guard generation > 0, self.generation == nil,
              active == nil else { return false }
        self.generation = generation
        return true
    }

    package mutating func begin(
        generation: UInt64,
        permitted: Bool
    ) -> Active? {
        guard permitted, self.generation == generation,
              active == nil, nextOperation < UInt64.max else { return nil }
        nextOperation += 1
        let value = Active(
            generation: generation,
            operation: nextOperation
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
