#if os(macOS)
import CompanionIPC
import Foundation

public enum MacLocalXPCMenuPairingCommandErrorV1:
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

package enum MacLocalXPCMenuPairingCommandKindV1:
    Equatable,
    Sendable
{
    case create
    case dismiss
    case resolveDecision
    case recoverHostIdentity
}

/// Destructive recovery authority is injected separately from pairing. The
/// shared transport gate serializes both secret-bearing command families, but
/// this protocol exposes only the exact recovery operation.
public protocol MacLocalXPCHostIdentityRecoveryHandlingV1: Sendable {
    func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0
}

/// Exact Agent authority injected only into the readiness-and-presentation
/// local-XPC profile. The transport authenticates and authorizes the peer,
/// decodes the closed payload, and fences the generation before invoking it.
public protocol MacLocalXPCMenuPairingCommandHandlingV1: Sendable {
    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0

    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0
}

/// One cross-family transaction gate per authenticated XPC generation. A
/// concurrent command is never queued because retaining a second secret-
/// bearing command across an ambiguous first delivery would weaken retry and
/// teardown semantics.
package struct MacLocalXPCMenuPairingCommandTransactionGateV1: Sendable {
    package struct Active: Equatable, Sendable {
        package let generation: UInt64
        package let operation: UInt64
        package let kind: MacLocalXPCMenuPairingCommandKindV1
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
        kind: MacLocalXPCMenuPairingCommandKindV1,
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
