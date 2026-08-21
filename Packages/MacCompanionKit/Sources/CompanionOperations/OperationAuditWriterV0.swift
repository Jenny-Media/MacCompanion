import CompanionDomain
import CompanionPersistence
import CryptoKit
import Foundation

public enum OperationAuditWriterErrorV0: Error, Equatable, Sendable {
    case storageUnavailable
}

public enum OperationAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol OperationAuditWritingV0: Sendable {
    func recordRequiredExecutionStart(
        _ operation: StoredDurableOperationRecord
    ) async throws

    func recordTerminal(
        _ operation: StoredDurableOperationRecord
    ) async
}

/// The detailed audit store is an observer and effect gate, never operation
/// authority. Security-state transitions remain owned by SQLiteSecurityStore.
public actor BoundedOperationAuditWriterV0: OperationAuditWritingV0 {
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: OperationAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> OperationAuditHealthV0 {
        currentHealth
    }

    public func recordRequiredExecutionStart(
        _ operation: StoredDurableOperationRecord
    ) async throws {
        guard operation.state == .running else {
            currentHealth = .degraded
            throw OperationAuditWriterErrorV0.storageUnavailable
        }
        do {
            let result = try await store.append(try draft(
                operation: operation,
                code: .operationAdmitted,
                outcome: .allowed,
                importance: .requiredBeforeEffect
            ))
            guard result.wasRecorded else {
                currentHealth = .degraded
                throw OperationAuditWriterErrorV0.storageUnavailable
            }
        } catch AuditStoreErrorV0.duplicateEventID {
            // Stable event IDs make a retry after publication idempotent.
        } catch {
            currentHealth = .degraded
            throw OperationAuditWriterErrorV0.storageUnavailable
        }
    }

    public func recordTerminal(
        _ operation: StoredDurableOperationRecord
    ) async {
        guard let terminal = Self.terminalPresentation(operation.state) else {
            return
        }
        do {
            let result = try await store.append(try draft(
                operation: operation,
                code: terminal.code,
                outcome: terminal.outcome,
                importance: .bestEffort
            ))
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            // The same terminal transition may be observed again on retry.
        } catch {
            // A completed effect or safety transition is never rewritten by a
            // secondary audit failure. Health stays degraded for local repair.
            currentHealth = .degraded
        }
    }

    private func draft(
        operation: StoredDurableOperationRecord,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0,
        importance: AuditImportanceV0
    ) throws -> AuditEventDraftV0 {
        try AuditEventDraftV0(
            eventID: Self.stableEventID(
                operationID: operation.operationID,
                code: code
            ),
            observedAtUnixMilliseconds: operation.updatedAtUnixMilliseconds,
            actor: .pairedDevice,
            visibility: .subjectDevice,
            subjectDeviceID: operation.deviceID,
            operationID: operation.operationID,
            code: code,
            capabilityID: operation.capabilityID,
            policyRevision: PolicyRevision(rawValue: operation.policyRevision),
            authorizationEpoch: AuthorizationEpoch(
                rawValue: operation.authorizationEpoch
            ),
            grantRevision: GrantRevision(rawValue: operation.grantRevision),
            outcome: outcome,
            importance: importance
        )
    }

    private static func terminalPresentation(
        _ state: OperationState
    ) -> (code: AuditEventCodeV0, outcome: AuditOutcomeV0)? {
        switch state {
        case .denied:
            (.operationDenied, .denied)
        case .expired:
            (.operationDenied, .expired)
        case .succeeded:
            (.operationCompleted, .succeeded)
        case .failed:
            (.operationFailed, .failed)
        case .cancelled:
            (.operationCancelled, .cancelled)
        case .outcomeUnknown:
            (.operationOutcomeUnknown, .outcomeUnknown)
        case .pendingPolicy, .awaitingApproval, .queued, .running,
             .cancelRequested:
            nil
        }
    }

    private static func stableEventID(
        operationID: UUID,
        code: AuditEventCodeV0
    ) -> UUID {
        var input = Data("maccompanion.audit.operation.v0\0".utf8)
        withUnsafeBytes(of: operationID.uuid) { input.append(contentsOf: $0) }
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
