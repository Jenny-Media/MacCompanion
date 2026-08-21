import CompanionAuthentication
import CompanionPersistence
import CryptoKit
import Foundation

public enum PrimarySessionAuditHealthV0: Equatable, Sendable {
    case healthy
    case degraded
}

public protocol PrimarySessionAuditWritingV0: Sendable {
    func recordAuthenticated(
        principal: AuthenticatedDevicePrincipal,
        connectionID: Data,
        observedAtUnixMilliseconds: Int64
    ) async

    func recordRejectedProof(
        proofMessageID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async

    func recordProtocolRejected(
        responseMessageID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async

    func recordClosed(
        principal: AuthenticatedDevicePrincipal,
        connectionID: Data,
        observedAtUnixMilliseconds: Int64
    ) async
}

public protocol PrimarySessionAuditWallClockV0: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemPrimarySessionAuditWallClockV0:
    PrimarySessionAuditWallClockV0
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        max(0, Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)))
    }
}

public actor BoundedPrimarySessionAuditWriterV0:
    PrimarySessionAuditWritingV0
{
    private let store: SQLiteBoundedAuditStoreV0
    private var currentHealth: PrimarySessionAuditHealthV0 = .healthy

    public init(store: SQLiteBoundedAuditStoreV0) {
        self.store = store
    }

    public func health() -> PrimarySessionAuditHealthV0 { currentHealth }

    public func recordAuthenticated(
        principal: AuthenticatedDevicePrincipal,
        connectionID: Data,
        observedAtUnixMilliseconds: Int64
    ) async {
        guard connectionID.count == 16 else {
            currentHealth = .degraded
            return
        }
        await append(try? subjectDraft(
            principal: principal,
            connectionID: connectionID,
            code: .authenticationSucceeded,
            outcome: .succeeded,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        ))
        await append(try? subjectDraft(
            principal: principal,
            connectionID: connectionID,
            code: .connectionOpened,
            outcome: .succeeded,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        ))
    }

    public func recordRejectedProof(
        proofMessageID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async {
        await append(try? AuditEventDraftV0(
            eventID: stableEventID(
                source: withUnsafeBytes(of: proofMessageID.uuid) { Data($0) },
                code: .authenticationRejected
            ),
            observedAtUnixMilliseconds: observedAtUnixMilliseconds,
            actor: .agent,
            visibility: .localOnly,
            correlationID: proofMessageID,
            code: .authenticationRejected,
            outcome: .denied,
            importance: .bestEffort
        ))
    }

    public func recordProtocolRejected(
        responseMessageID: UUID,
        observedAtUnixMilliseconds: Int64
    ) async {
        await append(try? AuditEventDraftV0(
            eventID: stableEventID(
                source: withUnsafeBytes(of: responseMessageID.uuid) { Data($0) },
                code: .protocolRejected
            ),
            observedAtUnixMilliseconds: observedAtUnixMilliseconds,
            actor: .agent,
            visibility: .localOnly,
            code: .protocolRejected,
            outcome: .denied,
            importance: .bestEffort
        ))
    }

    public func recordClosed(
        principal: AuthenticatedDevicePrincipal,
        connectionID: Data,
        observedAtUnixMilliseconds: Int64
    ) async {
        guard connectionID.count == 16 else {
            currentHealth = .degraded
            return
        }
        await append(try? subjectDraft(
            principal: principal,
            connectionID: connectionID,
            code: .connectionClosed,
            outcome: nil,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        ))
    }

    private func subjectDraft(
        principal: AuthenticatedDevicePrincipal,
        connectionID: Data,
        code: AuditEventCodeV0,
        outcome: AuditOutcomeV0?,
        observedAtUnixMilliseconds: Int64
    ) throws -> AuditEventDraftV0 {
        try AuditEventDraftV0(
            eventID: stableEventID(source: connectionID, code: code),
            observedAtUnixMilliseconds: observedAtUnixMilliseconds,
            actor: .pairedDevice,
            visibility: .subjectDevice,
            subjectDeviceID: principal.deviceID,
            code: code,
            policyRevision: principal.policyRevision,
            authorizationEpoch: principal.authorizationEpoch,
            grantRevision: principal.grantRevision,
            outcome: outcome,
            importance: .bestEffort
        )
    }

    private func append(_ draft: AuditEventDraftV0?) async {
        guard let draft else {
            currentHealth = .degraded
            return
        }
        do {
            let result = try await store.append(draft)
            if !result.wasRecorded { currentHealth = .degraded }
        } catch AuditStoreErrorV0.duplicateEventID {
            return
        } catch {
            currentHealth = .degraded
        }
    }

    private func stableEventID(
        source: Data,
        code: AuditEventCodeV0
    ) -> UUID {
        var input = Data("maccompanion.audit.primary-session.v0\0".utf8)
        input.append(source)
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
