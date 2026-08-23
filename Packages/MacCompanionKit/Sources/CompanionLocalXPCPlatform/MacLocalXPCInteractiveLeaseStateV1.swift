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

    func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1
    func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1
    func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0
    func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1
    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1
}

extension MacLocalXPCInteractiveLeaseSendingV1 {
    public func interactiveSurfaceTargets(
        _: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func resolveInteractiveSurface(
        _: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func prepareInteractiveSurfaceTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func acknowledgeInteractiveSurface(
        _: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func terminateInteractiveSurfaceFailure(
        _: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func interactiveFocusSnapshot(
        _: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
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

    func interactiveSurfaceTargets(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1
    func resolveInteractiveSurface(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1
    func prepareInteractiveSurfaceTransition(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0
    func acknowledgeInteractiveSurface(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    func terminateInteractiveSurfaceFailure(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1
    func interactiveFocusSnapshot(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1
}

extension MacLocalXPCGenerationBoundInteractiveLeaseSendingV1 {
    package func interactiveSurfaceTargets(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func resolveInteractiveSurface(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func prepareInteractiveSurfaceTransition(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func acknowledgeInteractiveSurface(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func terminateInteractiveSurfaceFailure(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func interactiveFocusSnapshot(
        generation _: UInt64,
        endpointToken _: UUID,
        command _: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
}

package enum MacLocalXPCInteractiveLeaseCommandKindV1:
    Equatable,
    Sendable
{
    case prepareInitialDesktop
    case install
    case renew
    case revoke
    case surfaceTargets
    case surfaceResolve
    case surfaceTransition
    case surfaceAcknowledgement
    case surfaceFailure
    case focusSnapshot
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

    func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1
    func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1
    func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0
    func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1
    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1

    func invalidateAgentAuthority() async
}

extension MacLocalXPCInteractiveLeaseHandlingV1 {
    public func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    public func interactiveSurfaceTargets(
        _: LocalInteractiveSurfaceTargetsCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func resolveInteractiveSurface(
        _: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func prepareInteractiveSurfaceTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func acknowledgeInteractiveSurface(
        _: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func terminateInteractiveSurfaceFailure(
        _: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    public func interactiveFocusSnapshot(
        _: LocalInteractiveFocusSnapshotCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
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
