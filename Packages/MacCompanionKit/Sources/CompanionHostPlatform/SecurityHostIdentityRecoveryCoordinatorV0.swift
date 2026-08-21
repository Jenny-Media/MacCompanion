import CompanionPersistence
import CompanionSecurity
import Foundation

public enum SecurityHostIdentityRecoveryErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidRecoveryID
    case invalidTime
    case invalidReplacement
}

public struct SecurityHostIdentityRecoveryResultV0: Sendable {
    public let record: StoredHostIdentityRecord
    public let issuedIdentity: SecurityHostIssuedIdentityV0
}

package protocol SecurityHostIdentityRecoveryCustodyV0: Sendable {
    func prepareKey(
        applicationTag: Data
    ) async throws -> SecurityHostPreparedIdentityKeyV0

    func issueListenerIdentity(
        applicationTag: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) async throws -> SecurityHostIssuedIdentityV0

    func loadListenerIdentity(
        applicationTag: Data,
        certificateDER: Data,
        wallNowUnixMilliseconds: Int64
    ) async throws -> SecurityHostIssuedIdentityV0

    func deleteRetiredKeyForConfirmedRecovery(
        applicationTag: Data
    ) async throws
}

extension SecurityHostIdentityKeyCustodyV0:
    SecurityHostIdentityRecoveryCustodyV0
{}

/// Cross-store confirmed recovery owner. The caller must be the authenticated
/// local-administration path that displayed the destructive re-pairing copy.
/// This coordinator itself exposes no remote or UI authority.
public actor SecurityHostIdentityRecoveryCoordinatorV0 {
    private let store: SQLiteSecurityStore
    private let custody: any SecurityHostIdentityRecoveryCustodyV0
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private let makeHostID: @Sendable () -> UUID
    private let applicationTag: @Sendable (UUID) throws -> Data

    public init(
        store: SQLiteSecurityStore,
        configuration: SecurityHostIdentityKeyCustodyConfigurationV0
    ) {
        self.store = store
        custody = SecurityHostIdentityKeyCustodyV0(
            configuration: configuration
        )
        wallNowUnixMilliseconds = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
        makeHostID = { UUID() }
        applicationTag = { recoveryID in
            try configuration.applicationTag(reference: recoveryID)
        }
    }

    package init(
        store: SQLiteSecurityStore,
        custody: any SecurityHostIdentityRecoveryCustodyV0,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64,
        makeHostID: @escaping @Sendable () -> UUID,
        applicationTag: @escaping @Sendable (UUID) throws -> Data
    ) {
        self.store = store
        self.custody = custody
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.makeHostID = makeHostID
        self.applicationTag = applicationTag
    }

    public func recover(
        intent: StoredHostIdentityRecoveryIntent
    ) async throws -> SecurityHostIdentityRecoveryResultV0 {
        let recoveryID = intent.recoveryID
        let expectedHostID = intent.expectedHostID
        let expectedHostFingerprint = intent.expectedHostFingerprint
        guard recoveryID != UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        ) else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidRecoveryID
        }
        let now = wallNowUnixMilliseconds()
        guard now >= 0,
              now <= HostIdentityLifecycleV0.maximumSafeUnixMilliseconds else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidTime
        }

        let fenced: StoredHostIdentityRecord
        switch try await store.beginHostIdentityRecovery(
            intent: intent,
            occurredAtUnixMilliseconds: now
        ) {
        case let .fenced(record, _), let .alreadyFenced(record):
            fenced = record
        case let .alreadyCompleted(receipt):
            guard let record = try await store.hostIdentity(),
                  record.state == .ready,
                  record.recoveryID == nil,
                  receipt.replacedHostID == expectedHostID,
                  receipt.replacedHostFingerprint
                    == expectedHostFingerprint,
                  record.hostID == receipt.newHostID,
                  record.hostFingerprint == receipt.newHostFingerprint else {
                throw SecurityHostIdentityRecoveryErrorV0.invalidReplacement
            }
            let issued = try await custody.loadListenerIdentity(
                applicationTag: record.keyApplicationTag,
                certificateDER: record.certificateDER,
                wallNowUnixMilliseconds: now
            )
            guard issued.key.applicationTag == record.keyApplicationTag,
                  issued.key.hostFingerprint == record.hostFingerprint,
                  issued.certificateDER == record.certificateDER else {
                throw SecurityHostIdentityRecoveryErrorV0.invalidReplacement
            }
            return SecurityHostIdentityRecoveryResultV0(
                record: record,
                issuedIdentity: issued
            )
        }
        guard fenced.state == .fencedForReplacement,
              fenced.recoveryID == recoveryID,
              fenced.hostID == expectedHostID,
              fenced.hostFingerprint == expectedHostFingerprint,
              now >= fenced.updatedAtUnixMilliseconds else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidTime
        }

        let newTag = try applicationTag(recoveryID)
        guard newTag != fenced.keyApplicationTag else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidReplacement
        }
        let prepared = try await custody.prepareKey(
            applicationTag: newTag
        )
        guard prepared.applicationTag == newTag else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidReplacement
        }
        let issued = try await custody.issueListenerIdentity(
            applicationTag: newTag,
            issuanceTimeUnixMilliseconds: now
        )
        let hostID = makeHostID()
        guard issued.key == prepared,
              issued.key.applicationTag == newTag,
              issued.key.hostFingerprint != fenced.hostFingerprint,
              hostID != fenced.hostID else {
            throw SecurityHostIdentityRecoveryErrorV0.invalidReplacement
        }
        let replacement = try StoredHostIdentityRecord(
            hostID: hostID,
            keyApplicationTag: newTag,
            hostFingerprint: issued.key.hostFingerprint,
            certificateDER: issued.certificateDER,
            certificateNotBeforeUnixMilliseconds:
                issued.validity.notBeforeUnixMilliseconds,
            certificateNotAfterUnixMilliseconds:
                issued.validity.notAfterUnixMilliseconds,
            establishedAtUnixMilliseconds: now,
            updatedAtUnixMilliseconds: now
        )

        try await custody.deleteRetiredKeyForConfirmedRecovery(
            applicationTag: fenced.keyApplicationTag
        )
        try await store.completeHostIdentityRecovery(
            recoveryID: recoveryID,
            replacement: replacement
        )
        return SecurityHostIdentityRecoveryResultV0(
            record: replacement,
            issuedIdentity: issued
        )
    }
}
