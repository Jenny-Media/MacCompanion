import CompanionDomain
import CompanionPersistence
import Foundation

public enum PairingAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol PairingAuditWritingV0: Sendable {
    func recordApprovedPairing(
        pairingID: UUID,
        device: StoredDeviceRecord
    ) async
}

/// Pairing authority remains the security database. This writer observes the
/// completed commit and cannot roll it back across the separate audit database.
public actor BoundedPairingAuditWriterV0: PairingAuditWritingV0 {
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: PairingAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> PairingAuditHealthV0 { currentHealth }

    public func recordApprovedPairing(
        pairingID: UUID,
        device: StoredDeviceRecord
    ) async {
        do {
            let result = try await store.append(try AuditEventDraftV0(
                eventID: pairingID,
                observedAtUnixMilliseconds: device.updatedAtUnixMilliseconds,
                actor: .localUser,
                visibility: .subjectDevice,
                subjectDeviceID: device.deviceID,
                code: .pairingApproved,
                policyRevision: device.policyRevision,
                authorizationEpoch: device.authorization.authorizationEpoch,
                grantRevision: device.authorization.grantRevision,
                outcome: .allowed,
                importance: .bestEffort
            ))
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            // Pairing IDs are unique durable commit IDs and make retry exact.
        } catch {
            currentHealth = .degraded
        }
    }
}
