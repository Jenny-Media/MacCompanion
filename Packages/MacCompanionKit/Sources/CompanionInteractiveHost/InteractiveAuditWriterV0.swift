import CompanionPersistence
import CryptoKit
import Foundation

public enum InteractiveAuditWriterErrorV0: Error, Equatable, Sendable {
    case storageUnavailable
}

public enum InteractiveAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol InteractiveAuditWritingV0: Sendable {
    func recordRequested(
        requestID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async

    func recordRequiredApproval(
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async throws

    func recordStarted(
        requestID: UUID,
        interactiveSessionID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async

    func recordTerminal(
        requestID: UUID,
        interactiveSessionID: UUID,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0,
        observedAtUnixMilliseconds: Int64,
        context: InteractiveSessionCommandContextV0
    ) async
}

public protocol InteractiveAuditWallClockV0: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemInteractiveAuditWallClockV0: InteractiveAuditWallClockV0 {
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        max(0, Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)))
    }
}

public actor BoundedInteractiveAuditWriterV0: InteractiveAuditWritingV0 {
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: InteractiveAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> InteractiveAuditHealthV0 { currentHealth }

    public func recordRequested(
        requestID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async {
        await appendBestEffort(
            eventID: stableEventID(source: requestID, phase: "requested"),
            requestID: requestID,
            interactiveSessionID: nil,
            code: .interactiveRequested,
            outcome: nil,
            context: context
        )
    }

    public func recordRequiredApproval(
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async throws {
        do {
            _ = try await store.append(try draft(
                eventID: stableEventID(source: approvalID, phase: "approved"),
                requestID: requestID,
                interactiveSessionID: interactiveSessionID,
                code: .interactiveApproved,
                outcome: .allowed,
                importance: .requiredBeforeEffect,
                context: context
            ))
        } catch AuditStoreErrorV0.duplicateEventID {
            return
        } catch {
            currentHealth = .degraded
            throw InteractiveAuditWriterErrorV0.storageUnavailable
        }
    }

    public func recordStarted(
        requestID: UUID,
        interactiveSessionID: UUID,
        context: InteractiveSessionCommandContextV0
    ) async {
        await appendBestEffort(
            eventID: stableEventID(source: interactiveSessionID, phase: "started"),
            requestID: requestID,
            interactiveSessionID: interactiveSessionID,
            code: .interactiveStarted,
            outcome: .succeeded,
            context: context
        )
    }

    public func recordTerminal(
        requestID: UUID,
        interactiveSessionID: UUID,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0,
        observedAtUnixMilliseconds: Int64,
        context: InteractiveSessionCommandContextV0
    ) async {
        guard code == .interactiveStopped || code == .interactiveFailed else {
            currentHealth = .degraded
            return
        }
        let phase = code == .interactiveStopped
            ? "stopped.remoteDisconnect" : "failed.runtime"
        await appendBestEffort(
            eventID: stableEventID(source: interactiveSessionID, phase: phase),
            requestID: requestID,
            interactiveSessionID: interactiveSessionID,
            code: code,
            outcome: outcome,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds,
            context: context
        )
    }

    private func appendBestEffort(
        eventID: UUID,
        requestID: UUID,
        interactiveSessionID: UUID?,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0?,
        observedAtUnixMilliseconds: Int64? = nil,
        context: InteractiveSessionCommandContextV0
    ) async {
        do {
            let result = try await store.append(try draft(
                eventID: eventID,
                requestID: requestID,
                interactiveSessionID: interactiveSessionID,
                code: code,
                outcome: outcome,
                importance: .bestEffort,
                observedAtUnixMilliseconds: observedAtUnixMilliseconds,
                context: context
            ))
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            return
        } catch {
            currentHealth = .degraded
        }
    }

    private func draft(
        eventID: UUID,
        requestID: UUID,
        interactiveSessionID: UUID?,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0?,
        importance: AuditImportanceV0,
        observedAtUnixMilliseconds: Int64? = nil,
        context: InteractiveSessionCommandContextV0
    ) throws -> AuditEventDraftV0 {
        try AuditEventDraftV0(
            eventID: eventID,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
                ?? context.wallNowUnixMilliseconds,
            actor: .pairedDevice,
            visibility: .subjectDevice,
            subjectDeviceID: context.deviceID,
            correlationID: requestID,
            interactiveSessionID: interactiveSessionID,
            code: code,
            capabilityID: InteractiveControlCapabilityV0.identifier,
            policyRevision: context.policyRevision,
            authorizationEpoch: context.authorizationEpoch,
            grantRevision: context.grantRevision,
            surfaceKind: .desktop,
            outcome: outcome,
            importance: importance
        )
    }

    private func stableEventID(source: UUID, phase: String) -> UUID {
        var input = Data("maccompanion.audit.interactive.v0\0".utf8)
        withUnsafeBytes(of: source.uuid) { input.append(contentsOf: $0) }
        input.append(contentsOf: phase.utf8)
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
