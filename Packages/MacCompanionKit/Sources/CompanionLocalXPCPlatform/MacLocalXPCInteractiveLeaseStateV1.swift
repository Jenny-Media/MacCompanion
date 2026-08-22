#if os(macOS)
import CompanionIPC
import Foundation

public enum MacLocalXPCInteractiveLeaseErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case malformedOrTransportError
    case replyTimedOut
    case cancelledAfterSend
}

/// Agent-side connection-scoped capability. Implementations send only through
/// the exact current authenticated and ready menu generation.
public protocol MacLocalXPCInteractiveLeaseSendingV1: Sendable {
    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0
}

package enum MacLocalXPCInteractiveLeaseCommandKindV1:
    Equatable,
    Sendable
{
    case install
    case renew
    case revoke
}

/// Menu-process runtime authority. The concrete receiver supplies its own
/// monotonic sample immediately before entering this serialized boundary.
/// Generation loss invokes `invalidateAgentAuthority` without waiting for a
/// network or Agent acknowledgement.
public protocol MacLocalXPCInteractiveLeaseHandlingV1: Sendable {
    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0

    func invalidateAgentAuthority() async
}

/// One cross-family transaction gate per authenticated generation. Interactive
/// lifecycle commands never queue: an ambiguous install, renewal, or revoke
/// must fence the generation and converge through teardown.
package struct MacLocalXPCInteractiveLeaseTransactionGateV1: Sendable {
    package struct Active: Equatable, Sendable {
        package let generation: UInt64
        package let operation: UInt64
        package let kind: MacLocalXPCInteractiveLeaseCommandKindV1
    }

    private(set) var generation: UInt64?
    private(set) var active: Active?
    private var nextOperation: UInt64 = 0

    package init() {}

    package mutating func bind(generation: UInt64) -> Bool {
        guard generation > 0,
              self.generation == nil,
              active == nil else { return false }
        self.generation = generation
        return true
    }

    package mutating func begin(
        generation: UInt64,
        kind: MacLocalXPCInteractiveLeaseCommandKindV1,
        permitted: Bool
    ) -> Active? {
        guard permitted,
              self.generation == generation,
              active == nil,
              nextOperation < UInt64.max else { return nil }
        nextOperation += 1
        let value = Active(
            generation: generation,
            operation: nextOperation,
            kind: kind
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
