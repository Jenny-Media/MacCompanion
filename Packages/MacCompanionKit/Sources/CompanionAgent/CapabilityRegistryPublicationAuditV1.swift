import CompanionPersistence
import Foundation

public enum CapabilityRegistryPublicationAuditHealthV1:
    Equatable, Sendable
{
    case healthy
    case degraded
}

public protocol CapabilityRegistryPublicationAuditWritingV1: Sendable {
    func recordCompletedReplacement(
        currentGeneration: UUID,
        observedAtUnixMilliseconds: Int64
    ) async
}

/// Writes only the closed fact that one already-completed publication swap
/// occurred. Registry contents and provider identities remain local authority
/// and never become audit payload.
public actor BoundedCapabilityRegistryPublicationAuditWriterV1:
    CapabilityRegistryPublicationAuditWritingV1
{
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth:
        CapabilityRegistryPublicationAuditHealthV1 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> CapabilityRegistryPublicationAuditHealthV1 {
        currentHealth
    }

    public func recordCompletedReplacement(
        currentGeneration: UUID,
        observedAtUnixMilliseconds: Int64
    ) async {
        do {
            let result = try await store.append(try AuditEventDraftV0(
                eventID: currentGeneration,
                observedAtUnixMilliseconds: observedAtUnixMilliseconds,
                actor: .agent,
                visibility: .localOnly,
                code: .capabilityRegistryChanged,
                outcome: .succeeded,
                importance: .bestEffort
            ))
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            return
        } catch {
            currentHealth = .degraded
        }
    }
}

public protocol CapabilityRegistryPublicationWallClockV1: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemCapabilityRegistryPublicationWallClockV1:
    CapabilityRegistryPublicationWallClockV1
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}
