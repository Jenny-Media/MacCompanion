#if os(macOS)
import CompanionIPC

public enum MacLocalXPCInteractiveAdmissionErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case malformedOrTransportError
    case replyTimedOut
    case cancelledAfterSend
}

/// Menu-side publisher for the current visible interactive admission. The
/// concrete local-XPC client binds each publication to its authenticated
/// transport generation and treats any ambiguous delivery as generation loss.
public protocol MacLocalXPCInteractiveAdmissionPublishingV1: Sendable {
    func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1
}

/// Agent authority reached only after exact local-XPC authentication,
/// readiness publication, method authorization, and payload validation.
public protocol MacLocalXPCInteractiveAdmissionHandlingV1: Sendable {
    func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1,
        transportGeneration: UInt64
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1

    func invalidateInteractiveAdmission(
        transportGeneration: UInt64
    ) async
}

/// Visible-admission publication has its own single-flight transaction gate so
/// it cannot interfere with pairing commands or Agent-to-menu lease traffic.
package struct MacLocalXPCInteractiveAdmissionTransactionGateV1: Sendable {
    package struct Active: Equatable, Sendable {
        package let generation: UInt64
        package let operation: UInt64
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
        permitted: Bool
    ) -> Active? {
        guard permitted,
              self.generation == generation,
              active == nil,
              nextOperation < UInt64.max else { return nil }
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
