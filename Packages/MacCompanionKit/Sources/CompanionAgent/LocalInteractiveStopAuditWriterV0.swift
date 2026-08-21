import CompanionIPC
import CompanionPersistence
import Foundation

public enum LocalInteractiveStopAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol LocalInteractiveStopAuditWritingV0: Sendable {
    func recordCompletedStop(
        command: LocalInteractiveStopCommandV0,
        receipt: LocalInteractiveStoppedReceiptV0
    ) async
}

public actor BoundedLocalInteractiveStopAuditWriterV0:
    LocalInteractiveStopAuditWritingV0
{
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: LocalInteractiveStopAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> LocalInteractiveStopAuditHealthV0 { currentHealth }

    public func recordCompletedStop(
        command: LocalInteractiveStopCommandV0,
        receipt: LocalInteractiveStoppedReceiptV0
    ) async {
        do {
            let result = try await store.append(try AuditEventDraftV0(
                eventID: command.commandID,
                observedAtUnixMilliseconds:
                    receipt.completedAtUnixMilliseconds,
                actor: .localUser,
                visibility: .subjectDevice,
                subjectDeviceID: command.deviceID,
                correlationID: command.requestID,
                interactiveSessionID: command.interactiveSessionID,
                code: .interactiveStopped,
                capabilityID: "maccompanion.interactive.control",
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
