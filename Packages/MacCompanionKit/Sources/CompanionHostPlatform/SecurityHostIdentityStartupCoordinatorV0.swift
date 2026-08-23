import CompanionPersistence
import CompanionSecurity
import Foundation

public enum SecurityHostIdentityStartupErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidTime
    case inconsistentDurableIdentity
    case keyOrCertificateMismatch
}

public enum SecurityHostIdentityStartupResultV0: Sendable {
    case ready(
        record: StoredHostIdentityRecord,
        issuedIdentity: SecurityHostIssuedIdentityV0,
        renewalRecommended: Bool
    )
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case recoveryFenced(UUID)
}

package protocol SecurityHostIdentityStartupCustodyV0: Sendable {
    func prepareKey(
        applicationTag: Data
    ) async throws -> SecurityHostPreparedIdentityKeyV0

    func availability(
        applicationTag: Data
    ) async throws -> HostIdentityKeyAvailability

    func issueListenerIdentity(
        applicationTag: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) async throws -> SecurityHostIssuedIdentityV0

    func loadListenerIdentity(
        applicationTag: Data,
        certificateDER: Data,
        wallNowUnixMilliseconds: Int64
    ) async throws -> SecurityHostIssuedIdentityV0
}

extension SecurityHostIdentityKeyCustodyV0:
    SecurityHostIdentityStartupCustodyV0
{}

/// Owns the recoverable first-install and established-certificate startup
/// sequence. SQLite mutation always precedes pending Keychain creation, while
/// ready identity publication always follows the exact durable commit.
public actor SecurityHostIdentityStartupCoordinatorV0 {
    private let store: SQLiteSecurityStore
    private let custody: any SecurityHostIdentityStartupCustodyV0
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private let makeUUID: @Sendable () -> UUID
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
        makeUUID = { UUID() }
        applicationTag = { reference in
            try configuration.applicationTag(reference: reference)
        }
    }

    package init(
        store: SQLiteSecurityStore,
        configuration: SecurityHostIdentityKeyCustodyConfigurationV0,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64,
        makeUUID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.store = store
        custody = SecurityHostIdentityKeyCustodyV0(
            configuration: configuration
        )
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.makeUUID = makeUUID
        applicationTag = { reference in
            try configuration.applicationTag(reference: reference)
        }
    }

    package init(
        store: SQLiteSecurityStore,
        custody: any SecurityHostIdentityStartupCustodyV0,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64,
        makeUUID: @escaping @Sendable () -> UUID,
        applicationTag: @escaping @Sendable (UUID) throws -> Data
    ) {
        self.store = store
        self.custody = custody
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.makeUUID = makeUUID
        self.applicationTag = applicationTag
    }

    public func start() async throws -> SecurityHostIdentityStartupResultV0 {
        let now = wallNowUnixMilliseconds()
        guard now >= 0,
              now <= HostIdentityLifecycleV0.maximumSafeUnixMilliseconds else {
            throw SecurityHostIdentityStartupErrorV0.invalidTime
        }

        if let established = try await store.hostIdentity() {
            return try await startEstablished(established, now: now)
        }
        return try await startBootstrap(now: now)
    }

    private func startBootstrap(
        now: Int64
    ) async throws -> SecurityHostIdentityStartupResultV0 {
        let reference = makeUUID()
        let candidate = try StoredHostIdentityBootstrapRecord(
            hostID: makeUUID(),
            keyApplicationTag: try applicationTag(reference),
            startedAtUnixMilliseconds: now
        )
        let pending = try await store.beginHostIdentityBootstrap(
            candidate: candidate
        )
        guard now >= pending.startedAtUnixMilliseconds else {
            throw SecurityHostIdentityStartupErrorV0.invalidTime
        }

        let prepared: SecurityHostPreparedIdentityKeyV0
        do {
            prepared = try await custody.prepareKey(
                applicationTag: pending.keyApplicationTag
            )
        } catch SecurityHostIdentityKeyCustodyErrorV0
            .keyUnavailableBeforeFirstUnlock {
            return .waitForFirstUnlock
        }
        guard prepared.applicationTag == pending.keyApplicationTag else {
            throw SecurityHostIdentityStartupErrorV0
                .keyOrCertificateMismatch
        }
        let issued: SecurityHostIssuedIdentityV0
        do {
            issued = try await custody.issueListenerIdentity(
                applicationTag: pending.keyApplicationTag,
                issuanceTimeUnixMilliseconds: now
            )
        } catch SecurityHostIdentityKeyCustodyErrorV0
            .keyUnavailableBeforeFirstUnlock {
            return .waitForFirstUnlock
        }
        guard issued.key == prepared else {
            throw SecurityHostIdentityStartupErrorV0
                .keyOrCertificateMismatch
        }
        let record = try StoredHostIdentityRecord(
            hostID: pending.hostID,
            keyApplicationTag: pending.keyApplicationTag,
            hostFingerprint: issued.key.hostFingerprint,
            certificateDER: issued.certificateDER,
            certificateNotBeforeUnixMilliseconds:
                issued.validity.notBeforeUnixMilliseconds,
            certificateNotAfterUnixMilliseconds:
                issued.validity.notAfterUnixMilliseconds,
            establishedAtUnixMilliseconds: now,
            updatedAtUnixMilliseconds: now
        )
        try await store.completeHostIdentityBootstrap(
            expected: pending,
            identity: record
        )
        return .ready(
            record: record,
            issuedIdentity: issued,
            renewalRecommended: false
        )
    }

    private func startEstablished(
        _ record: StoredHostIdentityRecord,
        now: Int64
    ) async throws -> SecurityHostIdentityStartupResultV0 {
        let recoveryIntent = try await store.hostIdentityRecoveryIntent()
        let recoveryReceipt = try await store.hostIdentityRecoveryReceipt()
        if let recoveryReceipt {
            guard let recoveryIntent,
                  recoveryIntent.recoveryID == recoveryReceipt.recoveryID,
                  recoveryIntent.expectedHostID
                    == recoveryReceipt.replacedHostID,
                  recoveryIntent.expectedHostFingerprint
                    == recoveryReceipt.replacedHostFingerprint,
                  record.state == .ready,
                  record.recoveryID == nil,
                  record.hostID == recoveryReceipt.newHostID,
                  record.hostFingerprint
                    == recoveryReceipt.newHostFingerprint,
                  record.updatedAtUnixMilliseconds
                    == recoveryReceipt.completedAtUnixMilliseconds else {
                throw SecurityHostIdentityStartupErrorV0
                    .inconsistentDurableIdentity
            }
            return .recoveryFenced(recoveryReceipt.recoveryID)
        }
        guard record.state == .ready, record.recoveryID == nil else {
            guard let recoveryID = record.recoveryID,
                  recoveryIntent?.recoveryID == recoveryID else {
                throw SecurityHostIdentityStartupErrorV0
                    .inconsistentDurableIdentity
            }
            return .recoveryFenced(recoveryID)
        }
        guard recoveryIntent == nil else {
            throw SecurityHostIdentityStartupErrorV0
                .inconsistentDurableIdentity
        }

        let key = try await custody.availability(
            applicationTag: record.keyApplicationTag
        )
        let certificate = certificateAvailability(record, now: now)
        let disposition = try HostIdentityLifecycleV0.evaluate(
            HostIdentityInventory(
                establishedIdentity: true,
                key: key,
                certificate: certificate
            ),
            wallNowUnixMilliseconds: now
        )

        switch disposition {
        case .bootstrapNewIdentity:
            throw SecurityHostIdentityStartupErrorV0
                .inconsistentDurableIdentity
        case .waitForFirstUnlock:
            return .waitForFirstUnlock
        case let .requireLocalRecovery(reason):
            return .requireLocalRecovery(reason)
        case .issueCertificate:
            let issued = try await custody.issueListenerIdentity(
                applicationTag: record.keyApplicationTag,
                issuanceTimeUnixMilliseconds: now
            )
            guard issued.key.applicationTag == record.keyApplicationTag,
                  issued.key.hostFingerprint == record.hostFingerprint else {
                throw SecurityHostIdentityStartupErrorV0
                    .keyOrCertificateMismatch
            }
            let replacement = try certificateReplacement(
                record,
                issued: issued,
                now: now
            )
            try await store.replaceHostIdentityCertificate(
                expected: record,
                replacement: replacement
            )
            return .ready(
                record: replacement,
                issuedIdentity: issued,
                renewalRecommended: false
            )
        case let .ready(fingerprint, _, renewalRecommended):
            guard fingerprint == record.hostFingerprint else {
                throw SecurityHostIdentityStartupErrorV0
                    .keyOrCertificateMismatch
            }
            let issued = try await custody.loadListenerIdentity(
                applicationTag: record.keyApplicationTag,
                certificateDER: record.certificateDER,
                wallNowUnixMilliseconds: now
            )
            guard issued.key.applicationTag == record.keyApplicationTag,
                  issued.key.hostFingerprint == record.hostFingerprint,
                  issued.certificateDER == record.certificateDER else {
                throw SecurityHostIdentityStartupErrorV0
                    .keyOrCertificateMismatch
            }
            return .ready(
                record: record,
                issuedIdentity: issued,
                renewalRecommended: renewalRecommended
            )
        }
    }

    private func certificateAvailability(
        _ record: StoredHostIdentityRecord,
        now: Int64
    ) -> HostIdentityCertificateAvailability {
        guard let inspection = try? HostIdentityCertificateInspectorV0.inspect(
            certificateDER: record.certificateDER,
            wallNowUnixMilliseconds: now
        ),
        inspection.validity.notBeforeUnixMilliseconds
            == record.certificateNotBeforeUnixMilliseconds,
        inspection.validity.notAfterUnixMilliseconds
            == record.certificateNotAfterUnixMilliseconds,
        let fingerprint = try? CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: inspection.subjectPublicKeyInfoDER
        ),
        fingerprint == record.hostFingerprint else {
            return .invalid
        }
        return .available(
            subjectPublicKeyInfoDER: inspection.subjectPublicKeyInfoDER,
            notBeforeUnixMilliseconds:
                inspection.validity.notBeforeUnixMilliseconds,
            notAfterUnixMilliseconds:
                inspection.validity.notAfterUnixMilliseconds
        )
    }

    private func certificateReplacement(
        _ record: StoredHostIdentityRecord,
        issued: SecurityHostIssuedIdentityV0,
        now: Int64
    ) throws -> StoredHostIdentityRecord {
        try StoredHostIdentityRecord(
            hostID: record.hostID,
            keyApplicationTag: record.keyApplicationTag,
            hostFingerprint: record.hostFingerprint,
            certificateDER: issued.certificateDER,
            certificateNotBeforeUnixMilliseconds:
                issued.validity.notBeforeUnixMilliseconds,
            certificateNotAfterUnixMilliseconds:
                issued.validity.notAfterUnixMilliseconds,
            establishedAtUnixMilliseconds:
                record.establishedAtUnixMilliseconds,
            updatedAtUnixMilliseconds: now
        )
    }
}
