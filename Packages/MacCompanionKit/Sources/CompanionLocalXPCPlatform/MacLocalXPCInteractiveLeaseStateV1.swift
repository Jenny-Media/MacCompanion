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
    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1

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

/// Transport-internal sender used only by the opaque endpoint issued for one
/// exact authenticated-and-ready menu generation. Both generation and private
/// endpoint token are rechecked in the server queue at command admission, so a
/// retained stale endpoint can never redirect a command to its replacement.
package protocol MacLocalXPCGenerationBoundInteractiveLeaseSendingV1:
    AnyObject,
    Sendable
{
    func prepareInitialInteractiveDesktop(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1

    func installInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renewInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws

    func revokeInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0
}

package enum MacLocalXPCInteractiveLeaseCommandKindV1:
    Equatable,
    Sendable
{
    case prepareInitialDesktop
    case install
    case renew
    case revoke
}

/// Pure queue-admission binding copied from the opaque ready-generation
/// endpoint. Both values are mandatory and exact.
package struct MacLocalXPCInteractiveLeaseEndpointBindingV1:
    Equatable,
    Sendable
{
    package let generation: UInt64
    package let endpointToken: UUID

    package init(generation: UInt64, endpointToken: UUID) {
        self.generation = generation
        self.endpointToken = endpointToken
    }

    package func admits(
        generation: UInt64,
        issuedEndpointToken: UUID?
    ) -> Bool {
        self.generation > 0
            && self.generation == generation
            && endpointToken == issuedEndpointToken
    }
}

/// Menu-process runtime authority. The concrete receiver supplies its own
/// monotonic sample immediately before entering this serialized boundary.
/// Generation loss invokes `invalidateAgentAuthority` without waiting for a
/// network or Agent acknowledgement.
public protocol MacLocalXPCInteractiveLeaseHandlingV1: Sendable {
    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1

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

extension MacLocalXPCInteractiveLeaseHandlingV1 {
    public func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
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
