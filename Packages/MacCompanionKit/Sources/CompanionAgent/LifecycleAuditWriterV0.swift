import CompanionDomain
import CompanionLifecycle
import CompanionPersistence
import CryptoKit
import Foundation

public enum LifecycleAuditTransitionErrorV0: Error, Equatable, Sendable {
    case mismatchedTransition
}

public struct CompletedLifecycleTransitionV0: Equatable, Sendable {
    public let transitionID: UUID
    public let observedAtUnixMilliseconds: Int64
    public let before: ProductLifecycleState
    public let event: ProductLifecycleEvent
    public let after: ProductLifecycleState
    public let effects: [ProductLifecycleEffect]

    public init(
        transitionID: UUID,
        observedAtUnixMilliseconds: Int64,
        before: ProductLifecycleState,
        event: ProductLifecycleEvent,
        after: ProductLifecycleState,
        effects: [ProductLifecycleEffect]
    ) throws {
        var expectedAfter = before
        let expectedEffects = try expectedAfter.apply(event)
        guard observedAtUnixMilliseconds >= 0,
              observedAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue),
              expectedAfter == after,
              expectedEffects == effects else {
            throw LifecycleAuditTransitionErrorV0.mismatchedTransition
        }
        self.transitionID = transitionID
        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.before = before
        self.event = event
        self.after = after
        self.effects = effects
    }
}

public enum LifecycleAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol LifecycleAuditWritingV0: Sendable {
    func recordCompletedTransition(
        _ transition: CompletedLifecycleTransitionV0
    ) async
}

public actor BoundedLifecycleAuditWriterV0: LifecycleAuditWritingV0 {
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: LifecycleAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> LifecycleAuditHealthV0 { currentHealth }

    public func recordCompletedTransition(
        _ transition: CompletedLifecycleTransitionV0
    ) async {
        if transition.before.desiredEnabled != transition.after.desiredEnabled {
            await append(
                transition: transition,
                code: .hostSecurityStateChanged,
                outcome: transition.after.desiredEnabled ? .succeeded : .unavailable
            )
        }
        if transition.before.observeAvailable != transition.after.observeAvailable {
            await append(
                transition: transition,
                code: .hostAvailabilityChanged,
                outcome: transition.after.observeAvailable ? .succeeded : .unavailable
            )
        }
    }

    private func append(
        transition: CompletedLifecycleTransitionV0,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0
    ) async {
        do {
            let result = try await store.append(try AuditEventDraftV0(
                eventID: stableEventID(
                    transitionID: transition.transitionID,
                    code: code
                ),
                observedAtUnixMilliseconds:
                    transition.observedAtUnixMilliseconds,
                actor: .system,
                visibility: .allPairedDevices,
                code: code,
                outcome: outcome,
                importance: .bestEffort
            ))
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            return
        } catch {
            currentHealth = .degraded
        }
    }

    private func stableEventID(
        transitionID: UUID,
        code: AuditEventCodeV0
    ) -> UUID {
        var input = Data("maccompanion.audit.lifecycle.v0\0".utf8)
        withUnsafeBytes(of: transitionID.uuid) { input.append(contentsOf: $0) }
        input.append(contentsOf: code.rawValue.utf8)
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
