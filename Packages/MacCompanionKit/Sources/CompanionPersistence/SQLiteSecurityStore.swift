import CompanionDomain
import CryptoKit
import Foundation
#if os(macOS)
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteDatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
#endif

public enum PersistenceFaultPoint: String, CaseIterable, Sendable {
    case afterDeviceMutation
    case beforeSecurityEvent
    case beforeTransactionCommit
}

public enum SecurityStoreError: Error, Equatable, Sendable {
    case sqlite(operation: String, code: Int32, message: String)
    case storageQuotaBelowCurrentUsage(requested: Int32, current: Int32)
    case insecureStoragePath
    case futureSchema(found: Int32, supported: Int32)
    case invalidRecord
    case deviceNotFound(UUID)
    case pairingAlreadyConsumed(UUID)
    case statusSequenceConflict
    case hostIdentityAlreadyEstablished
    case hostIdentityBootstrapConflict
    case hostIdentityWriteConflict
    case hostIdentityNotFound
    case hostIdentityRecoveryConflict
    case deviceRevocationConflict
    case hostIdentityReplacementDidNotRotate
    case operationIDConflict(UUID)
    case operationQuotaExceeded(UUID)
    case operationNotFound(UUID)
    case operationNotClaimable(UUID, OperationState)
    case operationAuthorizationStale(UUID)
    case operationCapabilityNotGranted(UUID, String)
    case grantExpansionStale(UUID)
    case unsupportedGrantTransition(DeviceAuthorizationState)
    case unsupportedTransitionEvent(DeviceAuthorizationEvent)
    case injectedFault(PersistenceFaultPoint)
}

/// Exact, bounded public facts for one locally reviewed device revocation.
/// Keeping the review and confirmation durable lets the Agent finish or replay
/// the same destructive command after a process restart without reopening a
/// remote authority path.
public struct StoredDeviceRevocationIntent: Equatable, Sendable {
    public let commandID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let reviewedState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let reviewCreatedAtUnixMilliseconds: Int64
    public let reviewExpiresAtUnixMilliseconds: Int64
    public let confirmedAtUnixMilliseconds: Int64

    public init(
        commandID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        reviewedState: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        reviewCreatedAtUnixMilliseconds: Int64,
        reviewExpiresAtUnixMilliseconds: Int64,
        confirmedAtUnixMilliseconds: Int64
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard commandID != zero,
              reviewID != zero,
              deviceID != zero,
              commandID != reviewID,
              commandID != deviceID,
              reviewID != deviceID,
              reviewedState == .activeMonitorOnly
                || reviewedState == .activeGranted
                || reviewedState == .suspended,
              authorizationEpoch.rawValue >= 1,
              authorizationEpoch.rawValue < AuthorizationEpoch.maximumWireValue,
              grantRevision.rawValue >= 1,
              grantRevision.rawValue < GrantRevision.maximumWireValue,
              reviewCreatedAtUnixMilliseconds >= 0,
              reviewCreatedAtUnixMilliseconds <= 9_007_199_254_440_991,
              reviewExpiresAtUnixMilliseconds
                == reviewCreatedAtUnixMilliseconds + 300_000,
              confirmedAtUnixMilliseconds >= reviewCreatedAtUnixMilliseconds,
              confirmedAtUnixMilliseconds < reviewExpiresAtUnixMilliseconds
        else {
            throw SecurityStoreError.invalidRecord
        }
        self.commandID = commandID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.reviewedState = reviewedState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.reviewCreatedAtUnixMilliseconds = reviewCreatedAtUnixMilliseconds
        self.reviewExpiresAtUnixMilliseconds = reviewExpiresAtUnixMilliseconds
        self.confirmedAtUnixMilliseconds = confirmedAtUnixMilliseconds
    }
}

public struct StoredDeviceRevocationReceipt: Equatable, Sendable {
    public let commandID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let completedAtUnixMilliseconds: Int64

    public init(
        commandID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        completedAtUnixMilliseconds: Int64
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard commandID != zero,
              reviewID != zero,
              deviceID != zero,
              commandID != reviewID,
              commandID != deviceID,
              reviewID != deviceID,
              authorizationEpoch.rawValue >= 2,
              grantRevision.rawValue >= 2,
              completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds <= 9_007_199_254_740_991 else {
            throw SecurityStoreError.invalidRecord
        }
        self.commandID = commandID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }
}

public struct StoredDeviceRevocationRecord: Equatable, Sendable {
    public let intent: StoredDeviceRevocationIntent
    public let receipt: StoredDeviceRevocationReceipt?

    public init(
        intent: StoredDeviceRevocationIntent,
        receipt: StoredDeviceRevocationReceipt?
    ) throws {
        if let receipt {
            guard receipt.commandID == intent.commandID,
                  receipt.reviewID == intent.reviewID,
                  receipt.deviceID == intent.deviceID,
                  receipt.authorizationEpoch
                    == (try intent.authorizationEpoch.advanced()),
                  receipt.grantRevision
                    == (try intent.grantRevision.advanced()),
                  receipt.completedAtUnixMilliseconds
                    >= intent.confirmedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
        }
        self.intent = intent
        self.receipt = receipt
    }
}

public enum DeviceRevocationPrepareResult: Equatable, Sendable {
    case prepared
    case alreadyPrepared
    case alreadyCompleted(StoredDeviceRevocationReceipt)
}

public enum DeviceRevocationCommitResult: Equatable, Sendable {
    case committed(StoredDeviceRecord, StoredDeviceRevocationReceipt)
    case alreadyDurable(StoredDeviceRecord, StoredDeviceRevocationReceipt)
}

public enum StoredHostIdentityState: String, Equatable, Sendable {
    case ready
    case fencedForReplacement
}

public struct StoredHostIdentityBootstrapRecord: Equatable, Sendable {
    public let hostID: UUID
    public let keyApplicationTag: Data
    public let startedAtUnixMilliseconds: Int64

    public init(
        hostID: UUID,
        keyApplicationTag: Data,
        startedAtUnixMilliseconds: Int64
    ) throws {
        guard (16...128).contains(keyApplicationTag.count),
              startedAtUnixMilliseconds >= 0 else {
            throw SecurityStoreError.invalidRecord
        }
        self.hostID = hostID
        self.keyApplicationTag = keyApplicationTag
        self.startedAtUnixMilliseconds = startedAtUnixMilliseconds
    }
}

public struct StoredHostIdentityRecord: Equatable, Sendable {
    public let hostID: UUID
    public let keyApplicationTag: Data
    public let hostFingerprint: Data
    public let certificateDER: Data
    public let certificateNotBeforeUnixMilliseconds: Int64
    public let certificateNotAfterUnixMilliseconds: Int64
    public let establishedAtUnixMilliseconds: Int64
    public let updatedAtUnixMilliseconds: Int64
    public let state: StoredHostIdentityState
    public let recoveryID: UUID?

    public init(
        hostID: UUID,
        keyApplicationTag: Data,
        hostFingerprint: Data,
        certificateDER: Data,
        certificateNotBeforeUnixMilliseconds: Int64,
        certificateNotAfterUnixMilliseconds: Int64,
        establishedAtUnixMilliseconds: Int64,
        updatedAtUnixMilliseconds: Int64,
        state: StoredHostIdentityState = .ready,
        recoveryID: UUID? = nil
    ) throws {
        guard (16...128).contains(keyApplicationTag.count),
              hostFingerprint.count == 32,
              (1...4_096).contains(certificateDER.count),
              certificateNotBeforeUnixMilliseconds >= 0,
              certificateNotAfterUnixMilliseconds > certificateNotBeforeUnixMilliseconds,
              establishedAtUnixMilliseconds >= 0,
              updatedAtUnixMilliseconds >= establishedAtUnixMilliseconds,
              (state == .ready) == (recoveryID == nil) else {
            throw SecurityStoreError.invalidRecord
        }
        self.hostID = hostID
        self.keyApplicationTag = keyApplicationTag
        self.hostFingerprint = hostFingerprint
        self.certificateDER = certificateDER
        self.certificateNotBeforeUnixMilliseconds = certificateNotBeforeUnixMilliseconds
        self.certificateNotAfterUnixMilliseconds = certificateNotAfterUnixMilliseconds
        self.establishedAtUnixMilliseconds = establishedAtUnixMilliseconds
        self.updatedAtUnixMilliseconds = updatedAtUnixMilliseconds
        self.state = state
        self.recoveryID = recoveryID
    }
}

public enum HostIdentityRecoveryBeginResult: Equatable, Sendable {
    case fenced(record: StoredHostIdentityRecord, revokedDeviceCount: Int)
    case alreadyFenced(record: StoredHostIdentityRecord)
    case alreadyCompleted(receipt: StoredHostIdentityRecoveryReceipt)
}

public enum StoredHostIdentityRecoveryCause: String, Equatable, Sendable {
    case keyUnavailable
    case suspectedCompromise
    case userRequestedReset
}

/// Bounded public facts proving the exact local command reviewed before a
/// destructive identity fence. The fixed scope and protocol version are
/// intentionally implicit.
public struct StoredHostIdentityRecoveryIntent: Equatable, Sendable {
    public let commandID: UUID
    public let recoveryID: UUID
    public let reviewID: UUID
    public let expectedHostID: UUID
    public let expectedHostFingerprint: Data
    public let cause: StoredHostIdentityRecoveryCause
    public let reviewCreatedAtUnixMilliseconds: Int64
    public let reviewExpiresAtUnixMilliseconds: Int64
    public let confirmedAtUnixMilliseconds: Int64

    public init(
        commandID: UUID,
        recoveryID: UUID,
        reviewID: UUID,
        expectedHostID: UUID,
        expectedHostFingerprint: Data,
        cause: StoredHostIdentityRecoveryCause,
        reviewCreatedAtUnixMilliseconds: Int64,
        reviewExpiresAtUnixMilliseconds: Int64,
        confirmedAtUnixMilliseconds: Int64
    ) throws {
        let zero = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        )
        guard commandID != zero,
              recoveryID != zero,
              reviewID != zero,
              expectedHostID != zero,
              commandID != recoveryID,
              expectedHostFingerprint.count == 32,
              reviewCreatedAtUnixMilliseconds >= 0,
              reviewCreatedAtUnixMilliseconds
                <= 9_007_199_254_440_991,
              reviewExpiresAtUnixMilliseconds
                == reviewCreatedAtUnixMilliseconds + 300_000,
              confirmedAtUnixMilliseconds
                >= reviewCreatedAtUnixMilliseconds,
              confirmedAtUnixMilliseconds
                < reviewExpiresAtUnixMilliseconds else {
            throw SecurityStoreError.invalidRecord
        }
        self.commandID = commandID
        self.recoveryID = recoveryID
        self.reviewID = reviewID
        self.expectedHostID = expectedHostID
        self.expectedHostFingerprint = expectedHostFingerprint
        self.cause = cause
        self.reviewCreatedAtUnixMilliseconds =
            reviewCreatedAtUnixMilliseconds
        self.reviewExpiresAtUnixMilliseconds =
            reviewExpiresAtUnixMilliseconds
        self.confirmedAtUnixMilliseconds = confirmedAtUnixMilliseconds
    }
}

public struct StoredHostIdentityRecoveryReceipt: Equatable, Sendable {
    public let recoveryID: UUID
    public let replacedHostID: UUID
    public let replacedHostFingerprint: Data
    public let newHostID: UUID
    public let newHostFingerprint: Data
    public let completedAtUnixMilliseconds: Int64

    public init(
        recoveryID: UUID,
        replacedHostID: UUID,
        replacedHostFingerprint: Data,
        newHostID: UUID,
        newHostFingerprint: Data,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard replacedHostFingerprint.count == 32,
              newHostFingerprint.count == 32,
              replacedHostID != newHostID,
              replacedHostFingerprint != newHostFingerprint,
              completedAtUnixMilliseconds >= 0 else {
            throw SecurityStoreError.invalidRecord
        }
        self.recoveryID = recoveryID
        self.replacedHostID = replacedHostID
        self.replacedHostFingerprint = replacedHostFingerprint
        self.newHostID = newHostID
        self.newHostFingerprint = newHostFingerprint
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }
}

public struct StoredStatusSequenceRecord: Equatable, Sendable {
    public let generation: UUID
    public let nextRevision: UInt64
    public let exhausted: Bool

    public init(
        generation: UUID,
        nextRevision: UInt64,
        exhausted: Bool
    ) throws {
        let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        guard nextRevision <= maximum,
              !(exhausted && nextRevision < maximum) else {
            throw SecurityStoreError.invalidRecord
        }
        self.generation = generation
        self.nextRevision = nextRevision
        self.exhausted = exhausted
    }
}

public struct StoredDeviceRecord: Equatable, Sendable {
    public let deviceID: UUID
    public let clientID: UUID
    public let sessionPublicKeyX963: Data
    public let approvalPublicKeyX963: Data
    public let authorization: DeviceAuthorization
    public let policyRevision: PolicyRevision
    public let createdAtUnixMilliseconds: Int64
    public let updatedAtUnixMilliseconds: Int64
    public let revokedAtUnixMilliseconds: Int64?

    public init(
        deviceID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        authorization: DeviceAuthorization,
        policyRevision: PolicyRevision,
        createdAtUnixMilliseconds: Int64,
        updatedAtUnixMilliseconds: Int64,
        revokedAtUnixMilliseconds: Int64? = nil
    ) throws {
        guard sessionPublicKeyX963.count == 65,
              sessionPublicKeyX963.first == 0x04,
              (try? P256.Signing.PublicKey(x963Representation: sessionPublicKeyX963)) != nil,
              approvalPublicKeyX963.count == 65,
              approvalPublicKeyX963.first == 0x04,
              (try? P256.Signing.PublicKey(x963Representation: approvalPublicKeyX963)) != nil,
              authorization.authorizationEpoch.rawValue >= 1,
              authorization.grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              Self.storableStates.contains(authorization.state),
              createdAtUnixMilliseconds >= 0,
              updatedAtUnixMilliseconds >= createdAtUnixMilliseconds,
              revokedAtUnixMilliseconds.map({ $0 >= createdAtUnixMilliseconds }) ?? true,
              (authorization.state == .revoked) == (revokedAtUnixMilliseconds != nil) else {
            throw SecurityStoreError.invalidRecord
        }
        self.deviceID = deviceID
        self.clientID = clientID
        self.sessionPublicKeyX963 = sessionPublicKeyX963
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.authorization = authorization
        self.policyRevision = policyRevision
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.updatedAtUnixMilliseconds = updatedAtUnixMilliseconds
        self.revokedAtUnixMilliseconds = revokedAtUnixMilliseconds
    }

    static let storableStates: Set<DeviceAuthorizationState> = [
        .activeMonitorOnly,
        .activeGranted,
        .suspended,
        .revoked,
    ]
}

public struct StoredDeviceGrantSnapshot: Equatable, Sendable {
    public let device: StoredDeviceRecord
    public let grants: CapabilityGrantSet

    public init(device: StoredDeviceRecord, grants: CapabilityGrantSet) {
        self.device = device
        self.grants = grants
    }
}

public struct StoredDeviceGrantIdentitySnapshot: Equatable, Sendable {
    public let device: StoredDeviceRecord
    public let grants: CapabilityGrantSet
    public let displayName: DeviceDisplayName?

    public init(
        device: StoredDeviceRecord,
        grants: CapabilityGrantSet,
        displayName: DeviceDisplayName?
    ) {
        self.device = device
        self.grants = grants
        self.displayName = displayName
    }
}

/// Every durable fact the local user saw before deciding whether to expand a
/// device grant. The SQLite authority compares all fields inside the same
/// immediate transaction that performs an approval, so no read/commit gap can
/// turn a stale review into broader authority.
public struct StoredGrantExpansionExpectation: Equatable, Sendable {
    public let deviceID: UUID
    public let displayName: DeviceDisplayName
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let currentGrants: CapabilityGrantSet
    public let proposedGrants: CapabilityGrantSet

    public init(
        deviceID: UUID,
        displayName: DeviceDisplayName,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        currentGrants: CapabilityGrantSet,
        proposedGrants: CapabilityGrantSet
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              Set(proposedGrants.capabilityIDs).isStrictSuperset(
                of: Set(currentGrants.capabilityIDs)
              ) else {
            throw SecurityStoreError.invalidRecord
        }
        self.deviceID = deviceID
        self.displayName = displayName
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.currentGrants = currentGrants
        self.proposedGrants = proposedGrants
    }
}

#if os(macOS)
public actor SQLiteSecurityStore {
    public static let schemaVersion: Int32 = 8
    public static let securityEventLimit = 4_096
    public static let operationRetentionMilliseconds: Int64 = 30 * 24 * 60 * 60 * 1_000

    private let handle: SQLiteDatabaseHandle
    private let preparedPath: String
    private let injectedFaults: Set<PersistenceFaultPoint>
    private let retainedOperationLimitPerDevice: Int

    private var database: OpaquePointer { handle.pointer }

    public init(
        path: String,
        injectedFaults: Set<PersistenceFaultPoint> = [],
        retainedOperationLimitPerDevice: Int = 10_000,
        maximumPageCount: Int32? = nil
    ) throws {
        guard (1...10_000).contains(retainedOperationLimitPerDevice),
              maximumPageCount.map({ (1...1_073_741_823).contains($0) })
                ?? true else {
            throw SecurityStoreError.invalidRecord
        }
        let preparedPath: String
        do {
            preparedPath = try SQLiteStorePathSecurity.prepareDatabase(
                at: path
            )
        } catch {
            throw SecurityStoreError.insecureStoragePath
        }
        var opened: OpaquePointer?
        let openResult = sqlite3_open_v2(
            preparedPath,
            &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,
            nil
        )
        guard openResult == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to allocate SQLite handle"
            if let opened { sqlite3_close(opened) }
            throw SecurityStoreError.sqlite(
                operation: "open",
                code: openResult,
                message: message
            )
        }

        do {
            let version = try Self.readUserVersion(opened)
            guard version <= Self.schemaVersion else {
                throw SecurityStoreError.futureSchema(
                    found: version,
                    supported: Self.schemaVersion
                )
            }
            try Self.configure(opened)
            try Self.migrate(opened)
            if let maximumPageCount {
                let effectivePageCount = try Self.setMaximumPageCount(
                    maximumPageCount,
                    on: opened
                )
                guard effectivePageCount <= maximumPageCount else {
                    throw SecurityStoreError.storageQuotaBelowCurrentUsage(
                        requested: maximumPageCount,
                        current: effectivePageCount
                    )
                }
            }
            try SQLiteStorePathSecurity.validateDatabaseArtifacts(
                at: preparedPath
            )
        } catch is SQLiteStorePathSecurityError {
            sqlite3_close(opened)
            throw SecurityStoreError.insecureStoragePath
        } catch {
            sqlite3_close(opened)
            throw error
        }
        handle = SQLiteDatabaseHandle(opened)
        self.preparedPath = preparedPath
        self.injectedFaults = injectedFaults
        self.retainedOperationLimitPerDevice = retainedOperationLimitPerDevice
    }

    /// Proves that the live SQLite handle still names the exact private file
    /// approved during construction. Callers use this before publishing a
    /// composition that would otherwise retain a path/handle split after a
    /// same-user rename or substitution.
    public nonisolated func validateStorageBinding() throws {
        var hasMoved: Int32 = 0
        guard sqlite3_file_control(
            handle.pointer,
            "main",
            SQLITE_FCNTL_HAS_MOVED,
            &hasMoved
        ) == SQLITE_OK,
              hasMoved == 0 else {
            throw SecurityStoreError.insecureStoragePath
        }
        do {
            try SQLiteStorePathSecurity.validateDatabaseArtifacts(
                at: preparedPath
            )
        } catch {
            throw SecurityStoreError.insecureStoragePath
        }
    }

    public func currentSchemaVersion() throws -> Int32 {
        try Self.readUserVersion(database)
    }

    /// Content-free inventory fact for local status. Revoked devices are not
    /// paired authorities and therefore are excluded from the count.
public func activePairedDeviceCount() throws -> Int {
        try activeDeviceIDs().count
    }

    /// Returns the complete locally named grant identities for active devices.
    /// The store remains the source of device identifiers; callers may filter
    /// these snapshots only for an explicitly local administration policy.
    public func activeDeviceGrantIdentitySnapshots()
        throws -> [StoredDeviceGrantIdentitySnapshot]
    {
        try activeDeviceIDs().map(deviceGrantIdentitySnapshot)
    }

    public func establishHostIdentity(_ record: StoredHostIdentityRecord) throws {
        guard record.state == .ready, record.recoveryID == nil else {
            throw SecurityStoreError.invalidRecord
        }
        try transaction {
            guard try hostIdentity() == nil else {
                throw SecurityStoreError.hostIdentityAlreadyEstablished
            }
            guard try hostIdentityBootstrap() == nil else {
                throw SecurityStoreError.hostIdentityBootstrapConflict
            }
            try insertHostIdentity(record)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.established",
                deviceID: nil,
                occurredAtUnixMilliseconds: record.updatedAtUnixMilliseconds
            )
        }
    }

    /// Persists the exact first-install candidate before any Keychain
    /// mutation. A restart supplies a fresh candidate but always adopts the
    /// already durable row.
    public func beginHostIdentityBootstrap(
        candidate: StoredHostIdentityBootstrapRecord
    ) throws -> StoredHostIdentityBootstrapRecord {
        try transaction {
            guard try hostIdentity() == nil else {
                throw SecurityStoreError.hostIdentityAlreadyEstablished
            }
            if let existing = try hostIdentityBootstrap() {
                return existing
            }
            try insertHostIdentityBootstrap(candidate)
            return candidate
        }
    }

    public func hostIdentityBootstrap()
        throws -> StoredHostIdentityBootstrapRecord?
    {
        let statement = try prepare(
            """
            SELECT host_id, key_application_tag, started_at_ms
            FROM host_identity_bootstrap WHERE singleton = 1
            """
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let hostText = sqlite3_column_text(statement, 0),
              let hostID = UUID(uuidString: String(cString: hostText)) else {
            if result != SQLITE_ROW {
                throw sqliteError(
                    operation: "read host identity bootstrap",
                    code: result
                )
            }
            throw SecurityStoreError.invalidRecord
        }
        return try StoredHostIdentityBootstrapRecord(
            hostID: hostID,
            keyApplicationTag: try columnData(statement, at: 1),
            startedAtUnixMilliseconds: sqlite3_column_int64(statement, 2)
        )
    }

    /// Publishes a ready identity only while atomically consuming the exact
    /// durable candidate and recording the minimal establishment event.
    public func completeHostIdentityBootstrap(
        expected: StoredHostIdentityBootstrapRecord,
        identity: StoredHostIdentityRecord
    ) throws {
        guard identity.state == .ready,
              identity.recoveryID == nil,
              identity.hostID == expected.hostID,
              identity.keyApplicationTag == expected.keyApplicationTag,
              identity.establishedAtUnixMilliseconds
                >= expected.startedAtUnixMilliseconds else {
            throw SecurityStoreError.hostIdentityBootstrapConflict
        }
        try transaction {
            guard try hostIdentity() == nil else {
                throw SecurityStoreError.hostIdentityAlreadyEstablished
            }
            guard try hostIdentityBootstrap() == expected else {
                throw SecurityStoreError.hostIdentityBootstrapConflict
            }
            try insertHostIdentity(identity)
            try executeBound(
                "DELETE FROM host_identity_bootstrap WHERE singleton = 1"
            ) { _ in }
            guard sqlite3_changes(database) == 1 else {
                throw SecurityStoreError.hostIdentityBootstrapConflict
            }
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.established",
                deviceID: nil,
                occurredAtUnixMilliseconds:
                    identity.updatedAtUnixMilliseconds
            )
        }
    }

    /// Atomically replaces only public certificate material around the same
    /// established host key. The complete expected row is a stale-write fence.
    public func replaceHostIdentityCertificate(
        expected: StoredHostIdentityRecord,
        replacement: StoredHostIdentityRecord
    ) throws {
        guard expected.state == .ready,
              expected.recoveryID == nil,
              replacement.state == .ready,
              replacement.recoveryID == nil,
              replacement.hostID == expected.hostID,
              replacement.keyApplicationTag
                == expected.keyApplicationTag,
              replacement.hostFingerprint == expected.hostFingerprint,
              replacement.establishedAtUnixMilliseconds
                == expected.establishedAtUnixMilliseconds,
              replacement.updatedAtUnixMilliseconds
                >= expected.updatedAtUnixMilliseconds else {
            throw SecurityStoreError.hostIdentityWriteConflict
        }
        try transaction {
            guard try hostIdentity() == expected else {
                throw SecurityStoreError.hostIdentityWriteConflict
            }
            try updateHostIdentity(replacement)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.certificateReplaced",
                deviceID: nil,
                occurredAtUnixMilliseconds:
                    replacement.updatedAtUnixMilliseconds
            )
        }
    }

    public func hostIdentity() throws -> StoredHostIdentityRecord? {
        let statement = try prepare(
            """
            SELECT host_id, key_application_tag, host_fingerprint, certificate_der,
                   certificate_not_before_ms, certificate_not_after_ms,
                   established_at_ms, updated_at_ms, state, recovery_id
            FROM host_identity WHERE singleton = 1
            """
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let hostText = sqlite3_column_text(statement, 0),
              let hostID = UUID(uuidString: String(cString: hostText)),
              let stateText = sqlite3_column_text(statement, 8),
              let state = StoredHostIdentityState(rawValue: String(cString: stateText)) else {
            if result != SQLITE_ROW {
                throw sqliteError(operation: "read host identity", code: result)
            }
            throw SecurityStoreError.invalidRecord
        }
        let recoveryID: UUID?
        if sqlite3_column_type(statement, 9) == SQLITE_NULL {
            recoveryID = nil
        } else if let text = sqlite3_column_text(statement, 9),
                  let value = UUID(uuidString: String(cString: text)) {
            recoveryID = value
        } else {
            throw SecurityStoreError.invalidRecord
        }
        return try StoredHostIdentityRecord(
            hostID: hostID,
            keyApplicationTag: try columnData(statement, at: 1),
            hostFingerprint: try columnData(statement, at: 2),
            certificateDER: try columnData(statement, at: 3),
            certificateNotBeforeUnixMilliseconds: sqlite3_column_int64(statement, 4),
            certificateNotAfterUnixMilliseconds: sqlite3_column_int64(statement, 5),
            establishedAtUnixMilliseconds: sqlite3_column_int64(statement, 6),
            updatedAtUnixMilliseconds: sqlite3_column_int64(statement, 7),
            state: state,
            recoveryID: recoveryID
        )
    }

    public func beginHostIdentityRecovery(
        intent: StoredHostIdentityRecoveryIntent,
        occurredAtUnixMilliseconds: Int64
    ) throws -> HostIdentityRecoveryBeginResult {
        guard occurredAtUnixMilliseconds >= intent.confirmedAtUnixMilliseconds
        else {
            throw SecurityStoreError.invalidRecord
        }
        return try transaction {
            if let receipt = try hostIdentityRecoveryReceipt(),
               receipt.recoveryID == intent.recoveryID {
                guard try hostIdentityRecoveryIntent() == intent,
                      receipt.replacedHostID == intent.expectedHostID,
                      receipt.replacedHostFingerprint
                        == intent.expectedHostFingerprint else {
                    throw SecurityStoreError.hostIdentityRecoveryConflict
                }
                return .alreadyCompleted(receipt: receipt)
            }
            guard let existing = try hostIdentity() else {
                throw SecurityStoreError.hostIdentityNotFound
            }
            if existing.state == .fencedForReplacement {
                guard existing.recoveryID == intent.recoveryID,
                      try hostIdentityRecoveryIntent() == intent,
                      existing.hostID == intent.expectedHostID,
                      existing.hostFingerprint
                        == intent.expectedHostFingerprint else {
                    throw SecurityStoreError.hostIdentityRecoveryConflict
                }
                return .alreadyFenced(record: existing)
            }
            guard existing.hostID == intent.expectedHostID,
                  existing.hostFingerprint
                    == intent.expectedHostFingerprint else {
                throw SecurityStoreError.hostIdentityRecoveryConflict
            }
            guard occurredAtUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            guard try pendingDeviceRevocationIntent() == nil else {
                throw SecurityStoreError.deviceRevocationConflict
            }

            try replaceHostIdentityRecoveryIntent(intent)
            let deviceIDs = try activeDeviceIDs()
            for deviceID in deviceIDs {
                guard let device = try readDevice(deviceID) else {
                    throw SecurityStoreError.deviceNotFound(deviceID)
                }
                let authorization = try device.authorization.applying(.revoke)
                let revoked = try StoredDeviceRecord(
                    deviceID: device.deviceID,
                    clientID: device.clientID,
                    sessionPublicKeyX963: device.sessionPublicKeyX963,
                    approvalPublicKeyX963: device.approvalPublicKeyX963,
                    authorization: authorization,
                    policyRevision: device.policyRevision,
                    createdAtUnixMilliseconds: device.createdAtUnixMilliseconds,
                    updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                    revokedAtUnixMilliseconds: occurredAtUnixMilliseconds
                )
                try updateDevice(revoked)
                try executeBound(
                    "DELETE FROM device_grants WHERE device_id = ?1"
                ) { statement in
                    try bind(uuid: deviceID, to: statement, at: 1)
                }
                try fenceDurableOperations(
                    for: deviceID,
                    atUnixMilliseconds: occurredAtUnixMilliseconds
                )
            }

            let fenced = try StoredHostIdentityRecord(
                hostID: existing.hostID,
                keyApplicationTag: existing.keyApplicationTag,
                hostFingerprint: existing.hostFingerprint,
                certificateDER: existing.certificateDER,
                certificateNotBeforeUnixMilliseconds: existing.certificateNotBeforeUnixMilliseconds,
                certificateNotAfterUnixMilliseconds: existing.certificateNotAfterUnixMilliseconds,
                establishedAtUnixMilliseconds: existing.establishedAtUnixMilliseconds,
                updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                state: .fencedForReplacement,
                recoveryID: intent.recoveryID
            )
            try updateHostIdentity(fenced)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.recoveryFenced",
                deviceID: nil,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return .fenced(record: fenced, revokedDeviceCount: deviceIDs.count)
        }
    }

    public func completeHostIdentityRecovery(
        recoveryID: UUID,
        replacement: StoredHostIdentityRecord
    ) throws {
        guard replacement.state == .ready, replacement.recoveryID == nil else {
            throw SecurityStoreError.invalidRecord
        }
        try transaction {
            guard let existing = try hostIdentity() else {
                throw SecurityStoreError.hostIdentityNotFound
            }
            guard existing.state == .fencedForReplacement,
                  existing.recoveryID == recoveryID,
                  try hostIdentityRecoveryIntent()?.recoveryID
                    == recoveryID else {
                throw SecurityStoreError.hostIdentityRecoveryConflict
            }
            guard replacement.hostID != existing.hostID,
                  replacement.hostFingerprint != existing.hostFingerprint,
                  replacement.keyApplicationTag != existing.keyApplicationTag else {
                throw SecurityStoreError.hostIdentityReplacementDidNotRotate
            }
            guard replacement.updatedAtUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            try updateHostIdentity(replacement)
            try replaceHostIdentityRecoveryReceipt(
                StoredHostIdentityRecoveryReceipt(
                    recoveryID: recoveryID,
                    replacedHostID: existing.hostID,
                    replacedHostFingerprint: existing.hostFingerprint,
                    newHostID: replacement.hostID,
                    newHostFingerprint: replacement.hostFingerprint,
                    completedAtUnixMilliseconds:
                        replacement.updatedAtUnixMilliseconds
                )
            )
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.recovered",
                deviceID: nil,
                occurredAtUnixMilliseconds: replacement.updatedAtUnixMilliseconds
            )
        }
    }

    public func hostIdentityRecoveryReceipt() throws
        -> StoredHostIdentityRecoveryReceipt?
    {
        let statement = try prepare(
            """
            SELECT recovery_id, replaced_host_id, replaced_host_fingerprint,
                   new_host_id, new_host_fingerprint, completed_at_ms
            FROM host_identity_recovery_receipt WHERE singleton = 1
            """
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let recoveryText = sqlite3_column_text(statement, 0),
              let recoveryID = UUID(
                uuidString: String(cString: recoveryText)
              ),
              let replacedText = sqlite3_column_text(statement, 1),
              let replacedHostID = UUID(
                uuidString: String(cString: replacedText)
              ),
              let newText = sqlite3_column_text(statement, 3),
              let newHostID = UUID(uuidString: String(cString: newText)) else {
            if result != SQLITE_ROW {
                throw sqliteError(
                    operation: "read host identity recovery receipt",
                    code: result
                )
            }
            throw SecurityStoreError.invalidRecord
        }
        return try StoredHostIdentityRecoveryReceipt(
            recoveryID: recoveryID,
            replacedHostID: replacedHostID,
            replacedHostFingerprint: try columnData(statement, at: 2),
            newHostID: newHostID,
            newHostFingerprint: try columnData(statement, at: 4),
            completedAtUnixMilliseconds: sqlite3_column_int64(statement, 5)
        )
    }

    /// Retires only the exact completed replay journal after the authenticated
    /// menu has validated its full receipt. The recovered identity and coarse
    /// security history remain durable.
    public func acknowledgeHostIdentityRecoveryCompletion(
        commandID: UUID,
        receipt: StoredHostIdentityRecoveryReceipt,
        occurredAtUnixMilliseconds: Int64
    ) throws {
        guard occurredAtUnixMilliseconds >= receipt.completedAtUnixMilliseconds,
              occurredAtUnixMilliseconds <= 9_007_199_254_440_991 else {
            throw SecurityStoreError.invalidRecord
        }
        try transaction {
            guard try hostIdentityRecoveryReceipt() == receipt,
                  let intent = try hostIdentityRecoveryIntent(),
                  intent.commandID == commandID,
                  intent.recoveryID == receipt.recoveryID,
                  intent.expectedHostID == receipt.replacedHostID,
                  intent.expectedHostFingerprint
                    == receipt.replacedHostFingerprint,
                  let identity = try hostIdentity(),
                  identity.state == .ready,
                  identity.recoveryID == nil,
                  identity.hostID == receipt.newHostID,
                  identity.hostFingerprint == receipt.newHostFingerprint,
                  identity.updatedAtUnixMilliseconds
                    == receipt.completedAtUnixMilliseconds else {
                throw SecurityStoreError.hostIdentityRecoveryConflict
            }
            try execute(
                "DELETE FROM host_identity_recovery_receipt WHERE singleton = 1"
            )
            guard sqlite3_changes(database) == 1 else {
                throw SecurityStoreError.hostIdentityRecoveryConflict
            }
            try execute(
                "DELETE FROM host_identity_recovery_intent WHERE singleton = 1"
            )
            guard sqlite3_changes(database) == 1 else {
                throw SecurityStoreError.hostIdentityRecoveryConflict
            }
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "hostIdentity.recoveryAcknowledged",
                deviceID: nil,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
        }
    }

    public func hostIdentityRecoveryIntent() throws
        -> StoredHostIdentityRecoveryIntent?
    {
        let statement = try prepare(
            """
            SELECT command_id, recovery_id, review_id, expected_host_id,
                   expected_host_fingerprint, cause, review_created_at_ms,
                   review_expires_at_ms, confirmed_at_ms
            FROM host_identity_recovery_intent WHERE singleton = 1
            """
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let commandText = sqlite3_column_text(statement, 0),
              let commandID = UUID(uuidString: String(cString: commandText)),
              let recoveryText = sqlite3_column_text(statement, 1),
              let recoveryID = UUID(uuidString: String(cString: recoveryText)),
              let reviewText = sqlite3_column_text(statement, 2),
              let reviewID = UUID(uuidString: String(cString: reviewText)),
              let hostText = sqlite3_column_text(statement, 3),
              let hostID = UUID(uuidString: String(cString: hostText)),
              let causeText = sqlite3_column_text(statement, 5),
              let cause = StoredHostIdentityRecoveryCause(
                rawValue: String(cString: causeText)
              ) else {
            if result != SQLITE_ROW {
                throw sqliteError(
                    operation: "read host identity recovery intent",
                    code: result
                )
            }
            throw SecurityStoreError.invalidRecord
        }
        return try StoredHostIdentityRecoveryIntent(
            commandID: commandID,
            recoveryID: recoveryID,
            reviewID: reviewID,
            expectedHostID: hostID,
            expectedHostFingerprint: try columnData(statement, at: 4),
            cause: cause,
            reviewCreatedAtUnixMilliseconds: sqlite3_column_int64(statement, 6),
            reviewExpiresAtUnixMilliseconds: sqlite3_column_int64(statement, 7),
            confirmedAtUnixMilliseconds: sqlite3_column_int64(statement, 8)
        )
    }

    public func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord
    ) throws {
        try commitPairing(
            pairingID: pairingID,
            record: record,
            displayName: nil
        )
    }

    public func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName?
    ) throws {
        guard record.authorization.state == .activeMonitorOnly,
              record.authorization.authorizationEpoch.rawValue == 1,
              record.authorization.grantRevision.rawValue == 1,
              record.revokedAtUnixMilliseconds == nil else {
            throw SecurityStoreError.invalidRecord
        }

        try transaction {
            guard try pairingConsumptionDeviceID(pairingID) == nil else {
                throw SecurityStoreError.pairingAlreadyConsumed(pairingID)
            }
            try executeBound(
                "INSERT INTO pairing_consumptions (pairing_id, device_id, consumed_at_ms) VALUES (?1, ?2, ?3)"
            ) { statement in
                try bind(uuid: pairingID, to: statement, at: 1)
                try bind(uuid: record.deviceID, to: statement, at: 2)
                sqlite3_bind_int64(statement, 3, record.updatedAtUnixMilliseconds)
            }
            try insertDevice(record)
            if let displayName {
                try executeBound(
                    "INSERT INTO device_display_names(device_id, display_name, updated_at_ms) VALUES (?1, ?2, ?3)"
                ) { statement in
                    try bind(uuid: record.deviceID, to: statement, at: 1)
                    try bind(text: displayName.rawValue, to: statement, at: 2)
                    sqlite3_bind_int64(
                        statement,
                        3,
                        record.updatedAtUnixMilliseconds
                    )
                }
            }
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "pairing.committedMonitorOnly",
                deviceID: record.deviceID,
                occurredAtUnixMilliseconds: record.updatedAtUnixMilliseconds
            )
        }
    }

    public func pairingConsumptionDeviceID(_ pairingID: UUID) throws -> UUID? {
        let statement = try prepare(
            "SELECT device_id FROM pairing_consumptions WHERE pairing_id = ?1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: pairingID, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              let value = UUID(uuidString: String(cString: text)) else {
            if result != SQLITE_ROW {
                throw sqliteError(operation: "read pairing consumption", code: result)
            }
            throw SecurityStoreError.invalidRecord
        }
        return value
    }

    public func device(_ deviceID: UUID) throws -> StoredDeviceRecord? {
        try readDevice(deviceID)
    }

    public func device(clientID: UUID) throws -> StoredDeviceRecord? {
        let statement = try prepare(
            "SELECT device_id FROM device_authorizations WHERE client_id = ?1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: clientID, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              let deviceID = UUID(uuidString: String(cString: text)) else {
            if result != SQLITE_ROW {
                throw sqliteError(operation: "read device by client ID", code: result)
            }
            throw SecurityStoreError.invalidRecord
        }
        return try readDevice(deviceID)
    }

    public func deviceRevocationRecord(
        commandID: UUID
    ) throws -> StoredDeviceRevocationRecord? {
        try readDeviceRevocationRecord(
            whereClause: "command_id = ?1",
            bind: { statement in
                try bind(uuid: commandID, to: statement, at: 1)
            }
        )
    }

    public func deviceRevocationRecord(
        deviceID: UUID
    ) throws -> StoredDeviceRevocationRecord? {
        try readDeviceRevocationRecord(
            whereClause: "device_id = ?1",
            bind: { statement in
                try bind(uuid: deviceID, to: statement, at: 1)
            }
        )
    }

    public func pendingDeviceRevocationIntent() throws
        -> StoredDeviceRevocationIntent?
    {
        try readDeviceRevocationRecord(
            whereClause: "phase = 'pending'",
            bind: { _ in }
        )?.intent
    }

    /// Durably accepts an exact, still-current local review before the deny
    /// latch is activated. No authorization mutation occurs in this phase.
    public func beginDeviceRevocation(
        _ intent: StoredDeviceRevocationIntent
    ) throws -> DeviceRevocationPrepareResult {
        try transaction {
            if let existing = try readDeviceRevocationRecord(
                whereClause: "command_id = ?1",
                bind: { statement in
                    try bind(uuid: intent.commandID, to: statement, at: 1)
                }
            ) {
                guard existing.intent == intent else {
                    throw SecurityStoreError.deviceRevocationConflict
                }
                if let receipt = existing.receipt {
                    return .alreadyCompleted(receipt)
                }
                return .alreadyPrepared
            }
            guard try readDeviceRevocationRecord(
                whereClause: "review_id = ?1 OR device_id = ?2 OR phase = 'pending'",
                bind: { statement in
                    try bind(uuid: intent.reviewID, to: statement, at: 1)
                    try bind(uuid: intent.deviceID, to: statement, at: 2)
                }
            ) == nil,
            let device = try readDevice(intent.deviceID),
            device.authorization.state == intent.reviewedState,
            device.authorization.authorizationEpoch
                == intent.authorizationEpoch,
            device.authorization.grantRevision == intent.grantRevision,
            try deviceDisplayName(intent.deviceID)
                == intent.deviceDisplayName else {
                throw SecurityStoreError.deviceRevocationConflict
            }

            try executeBound(
                """
                INSERT INTO device_revocation_commands (
                    command_id, review_id, device_id, device_display_name,
                    expected_state, expected_authorization_epoch,
                    expected_grant_revision, review_created_at_ms,
                    review_expires_at_ms, confirmed_at_ms, phase, pending_slot,
                    result_authorization_epoch, result_grant_revision,
                    completed_at_ms
                ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,
                    'pending', 1, NULL, NULL, NULL
                )
                """
            ) { statement in
                try bind(uuid: intent.commandID, to: statement, at: 1)
                try bind(uuid: intent.reviewID, to: statement, at: 2)
                try bind(uuid: intent.deviceID, to: statement, at: 3)
                try bind(
                    text: intent.deviceDisplayName.rawValue,
                    to: statement,
                    at: 4
                )
                try bind(
                    text: intent.reviewedState.rawValue,
                    to: statement,
                    at: 5
                )
                sqlite3_bind_int64(
                    statement,
                    6,
                    Int64(intent.authorizationEpoch.rawValue)
                )
                sqlite3_bind_int64(
                    statement,
                    7,
                    Int64(intent.grantRevision.rawValue)
                )
                sqlite3_bind_int64(
                    statement,
                    8,
                    intent.reviewCreatedAtUnixMilliseconds
                )
                sqlite3_bind_int64(
                    statement,
                    9,
                    intent.reviewExpiresAtUnixMilliseconds
                )
                sqlite3_bind_int64(
                    statement,
                    10,
                    intent.confirmedAtUnixMilliseconds
                )
            }
            return .prepared
        }
    }

    /// Atomically advances the exact reviewed authority, fences its durable
    /// work, emits one minimal event, and records the replayable receipt.
    public func completeDeviceRevocation(
        _ intent: StoredDeviceRevocationIntent,
        occurredAtUnixMilliseconds: Int64
    ) throws -> DeviceRevocationCommitResult {
        guard occurredAtUnixMilliseconds
                >= intent.confirmedAtUnixMilliseconds else {
            throw SecurityStoreError.invalidRecord
        }
        return try transaction {
            guard let stored = try readDeviceRevocationRecord(
                whereClause: "command_id = ?1",
                bind: { statement in
                    try bind(uuid: intent.commandID, to: statement, at: 1)
                }
            ), stored.intent == intent,
            let current = try readDevice(intent.deviceID) else {
                throw SecurityStoreError.deviceRevocationConflict
            }
            if let receipt = stored.receipt {
                guard current.authorization.state == .revoked,
                      current.authorization.authorizationEpoch
                        == receipt.authorizationEpoch,
                      current.authorization.grantRevision
                        == receipt.grantRevision,
                      current.updatedAtUnixMilliseconds
                        == receipt.completedAtUnixMilliseconds else {
                    throw SecurityStoreError.deviceRevocationConflict
                }
                return .alreadyDurable(current, receipt)
            }

            let resultEpoch = try intent.authorizationEpoch.advanced()
            let resultRevision = try intent.grantRevision.advanced()
            if current.authorization.state == .revoked {
                guard current.authorization.authorizationEpoch == resultEpoch,
                      current.authorization.grantRevision == resultRevision,
                      current.updatedAtUnixMilliseconds
                        >= intent.confirmedAtUnixMilliseconds else {
                    throw SecurityStoreError.deviceRevocationConflict
                }
                let receipt = try StoredDeviceRevocationReceipt(
                    commandID: intent.commandID,
                    reviewID: intent.reviewID,
                    deviceID: intent.deviceID,
                    authorizationEpoch: resultEpoch,
                    grantRevision: resultRevision,
                    completedAtUnixMilliseconds:
                        current.updatedAtUnixMilliseconds
                )
                try completeDeviceRevocationRow(receipt)
                return .alreadyDurable(current, receipt)
            }

            guard current.authorization.state == intent.reviewedState,
                  current.authorization.authorizationEpoch
                    == intent.authorizationEpoch,
                  current.authorization.grantRevision
                    == intent.grantRevision,
                  try deviceDisplayName(intent.deviceID)
                    == intent.deviceDisplayName,
                  occurredAtUnixMilliseconds
                    >= current.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.deviceRevocationConflict
            }
            let authorization = try current.authorization.applying(.revoke)
            let revoked = try StoredDeviceRecord(
                deviceID: current.deviceID,
                clientID: current.clientID,
                sessionPublicKeyX963: current.sessionPublicKeyX963,
                approvalPublicKeyX963: current.approvalPublicKeyX963,
                authorization: authorization,
                policyRevision: current.policyRevision,
                createdAtUnixMilliseconds:
                    current.createdAtUnixMilliseconds,
                updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                revokedAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            let receipt = try StoredDeviceRevocationReceipt(
                commandID: intent.commandID,
                reviewID: intent.reviewID,
                deviceID: intent.deviceID,
                authorizationEpoch: resultEpoch,
                grantRevision: resultRevision,
                completedAtUnixMilliseconds: occurredAtUnixMilliseconds
            )

            // Complete the row first inside this transaction so the pending
            // mutation fence admits only this exact revocation write.
            try completeDeviceRevocationRow(receipt)
            try updateDevice(revoked)
            try executeBound(
                "DELETE FROM device_grants WHERE device_id = ?1"
            ) { statement in
                try bind(uuid: intent.deviceID, to: statement, at: 1)
            }
            try fenceDurableOperations(
                for: intent.deviceID,
                atUnixMilliseconds: occurredAtUnixMilliseconds
            )
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.revoke",
                deviceID: intent.deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return .committed(revoked, receipt)
        }
    }

    public func transitionDevice(
        _ deviceID: UUID,
        event: DeviceAuthorizationEvent,
        occurredAtUnixMilliseconds: Int64
    ) throws -> StoredDeviceRecord? {
        let allowedEvents: Set<DeviceAuthorizationEvent> = [
            .suspend,
            .revoke,
            .expireRevokedTombstone,
        ]
        guard allowedEvents.contains(event) else {
            throw SecurityStoreError.unsupportedTransitionEvent(event)
        }
        guard occurredAtUnixMilliseconds >= 0 else {
            throw SecurityStoreError.invalidRecord
        }

        return try transaction {
            guard let existing = try readDevice(deviceID) else {
                throw SecurityStoreError.deviceNotFound(deviceID)
            }
            try ensureNoPendingDeviceRevocation(for: deviceID)
            guard occurredAtUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            let authorization = try existing.authorization.applying(event)
            let result: StoredDeviceRecord?

            if authorization.state == .unpaired {
                try executeBound(
                    "DELETE FROM device_authorizations WHERE device_id = ?1"
                ) { statement in
                    try bind(uuid: deviceID, to: statement, at: 1)
                }
                result = nil
            } else {
                let revokedAt = authorization.state == .revoked
                    ? occurredAtUnixMilliseconds
                    : existing.revokedAtUnixMilliseconds
                let updated = try StoredDeviceRecord(
                    deviceID: existing.deviceID,
                    clientID: existing.clientID,
                    sessionPublicKeyX963: existing.sessionPublicKeyX963,
                    approvalPublicKeyX963: existing.approvalPublicKeyX963,
                    authorization: authorization,
                    policyRevision: existing.policyRevision,
                    createdAtUnixMilliseconds: existing.createdAtUnixMilliseconds,
                    updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                    revokedAtUnixMilliseconds: revokedAt
                )
                try updateDevice(updated)
                if authorization.state == .revoked {
                    try executeBound(
                        "DELETE FROM device_grants WHERE device_id = ?1"
                    ) { statement in
                        try bind(uuid: deviceID, to: statement, at: 1)
                    }
                }
                if authorization.state == .suspended
                    || authorization.state == .revoked {
                    try fenceDurableOperations(
                        for: deviceID,
                        atUnixMilliseconds: occurredAtUnixMilliseconds
                    )
                }
                result = updated
            }

            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.\(event.rawValue)",
                deviceID: deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return result
        }
    }

    public func securityEventCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM security_events")
    }

    public func deviceGrants(_ deviceID: UUID) throws -> CapabilityGrantSet {
        guard try readDevice(deviceID) != nil else {
            throw SecurityStoreError.deviceNotFound(deviceID)
        }
        let statement = try prepare(
            "SELECT capability_id FROM device_grants WHERE device_id = ?1 ORDER BY capability_id"
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: deviceID, to: statement, at: 1)
        var capabilityIDs: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return try CapabilityGrantSet(capabilityIDs)
            }
            guard result == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) else {
                if result != SQLITE_ROW {
                    throw sqliteError(operation: "read device grants", code: result)
                }
                throw SecurityStoreError.invalidRecord
            }
            capabilityIDs.append(String(cString: text))
        }
    }

    /// Reads the device security fences and its exact grant set in one actor
    /// turn so discovery cannot join revisions from different transactions.
    public func deviceGrantSnapshot(
        _ deviceID: UUID
    ) throws -> StoredDeviceGrantSnapshot {
        guard let device = try readDevice(deviceID) else {
            throw SecurityStoreError.deviceNotFound(deviceID)
        }
        return try StoredDeviceGrantSnapshot(
            device: device,
            grants: deviceGrants(deviceID)
        )
    }

    /// Reads security fences, exact grants, and the locally confirmed
    /// presentation name in one actor turn.
    public func deviceGrantIdentitySnapshot(
        _ deviceID: UUID
    ) throws -> StoredDeviceGrantIdentitySnapshot {
        let snapshot = try deviceGrantSnapshot(deviceID)
        return StoredDeviceGrantIdentitySnapshot(
            device: snapshot.device,
            grants: snapshot.grants,
            displayName: try deviceDisplayName(deviceID)
        )
    }

    public func deviceDisplayName(_ deviceID: UUID) throws
        -> DeviceDisplayName? {
        let statement = try prepare(
            "SELECT display_name FROM device_display_names WHERE device_id = ?1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: deviceID, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            if result != SQLITE_ROW {
                throw sqliteError(operation: "read device display name", code: result)
            }
            throw SecurityStoreError.invalidRecord
        }
        return try DeviceDisplayName(String(cString: text))
    }

    /// This method is exposed only to authenticated local administration
    /// composition. Remote command dispatchers never receive it.
    public func setDeviceDisplayName(
        _ deviceID: UUID,
        displayName: DeviceDisplayName,
        occurredAtUnixMilliseconds: Int64
    ) throws {
        try transaction {
            guard let device = try readDevice(deviceID) else {
                throw SecurityStoreError.deviceNotFound(deviceID)
            }
            try ensureNoPendingDeviceRevocation(for: deviceID)
            guard device.authorization.state != .revoked,
                  occurredAtUnixMilliseconds >= device.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            try executeBound(
                """
                INSERT INTO device_display_names(device_id, display_name, updated_at_ms)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(device_id) DO UPDATE SET
                    display_name = excluded.display_name,
                    updated_at_ms = excluded.updated_at_ms
                """
            ) { statement in
                try bind(uuid: deviceID, to: statement, at: 1)
                try bind(text: displayName.rawValue, to: statement, at: 2)
                sqlite3_bind_int64(statement, 3, occurredAtUnixMilliseconds)
            }
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.displayNameConfirmed",
                deviceID: deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
        }
    }

    public func replaceDeviceGrants(
        _ deviceID: UUID,
        grants: CapabilityGrantSet,
        occurredAtUnixMilliseconds: Int64
    ) throws -> StoredDeviceRecord {
        try transaction {
            guard let existing = try readDevice(deviceID) else {
                throw SecurityStoreError.deviceNotFound(deviceID)
            }
            try ensureNoPendingDeviceRevocation(for: deviceID)
            guard occurredAtUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            guard existing.authorization.state == .activeMonitorOnly
                    || existing.authorization.state == .activeGranted else {
                throw SecurityStoreError.unsupportedGrantTransition(
                    existing.authorization.state
                )
            }
            let current = try deviceGrants(deviceID)
            if current == grants { return existing }

            let event: DeviceAuthorizationEvent
            switch (existing.authorization.state, grants.isEmpty) {
            case (.activeMonitorOnly, false): event = .expandGrant
            case (.activeGranted, true): event = .reduceToMonitorOnly
            case (.activeGranted, false): event = .replaceGrant
            default:
                throw SecurityStoreError.unsupportedGrantTransition(
                    existing.authorization.state
                )
            }
            let authorization = try existing.authorization.applying(event)
            let updated = try StoredDeviceRecord(
                deviceID: existing.deviceID,
                clientID: existing.clientID,
                sessionPublicKeyX963: existing.sessionPublicKeyX963,
                approvalPublicKeyX963: existing.approvalPublicKeyX963,
                authorization: authorization,
                policyRevision: existing.policyRevision,
                createdAtUnixMilliseconds: existing.createdAtUnixMilliseconds,
                updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                revokedAtUnixMilliseconds: existing.revokedAtUnixMilliseconds
            )
            try updateDevice(updated)
            try replaceGrantRows(deviceID: deviceID, grants: grants)
            try fenceDurableOperations(
                for: deviceID,
                atUnixMilliseconds: occurredAtUnixMilliseconds
            )
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.grantsReplaced",
                deviceID: deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return updated
        }
    }

    /// Resolves a locally presented grant-expansion review. Approval performs
    /// the exact compare, grant write, both authorization-fence increments,
    /// queued-work fencing, and security event in one SQLite transaction.
    /// Decline performs the same exact comparison but leaves durable state and
    /// the audit stream unchanged.
    public func decideGrantExpansion(
        expected: StoredGrantExpansionExpectation,
        approve: Bool,
        occurredAtUnixMilliseconds: Int64
    ) throws -> StoredDeviceGrantIdentitySnapshot {
        try transaction {
            guard occurredAtUnixMilliseconds >= 0,
                  let existing = try readDevice(expected.deviceID),
                  occurredAtUnixMilliseconds
                    >= existing.updatedAtUnixMilliseconds,
                  existing.authorization.state == .activeMonitorOnly
                    || existing.authorization.state == .activeGranted,
                  existing.authorization.authorizationEpoch
                    == expected.authorizationEpoch,
                  existing.authorization.grantRevision
                    == expected.grantRevision,
                  existing.policyRevision == expected.policyRevision,
                  try deviceGrants(expected.deviceID)
                    == expected.currentGrants,
                  try deviceDisplayName(expected.deviceID)
                    == expected.displayName else {
                throw SecurityStoreError.grantExpansionStale(expected.deviceID)
            }

            guard approve else {
                return StoredDeviceGrantIdentitySnapshot(
                    device: existing,
                    grants: expected.currentGrants,
                    displayName: expected.displayName
                )
            }
            try ensureNoPendingDeviceRevocation(for: expected.deviceID)

            let event: DeviceAuthorizationEvent =
                existing.authorization.state == .activeMonitorOnly
                ? .expandGrant : .replaceGrant
            let authorization = try existing.authorization.applying(event)
            let updated = try StoredDeviceRecord(
                deviceID: existing.deviceID,
                clientID: existing.clientID,
                sessionPublicKeyX963: existing.sessionPublicKeyX963,
                approvalPublicKeyX963: existing.approvalPublicKeyX963,
                authorization: authorization,
                policyRevision: existing.policyRevision,
                createdAtUnixMilliseconds: existing.createdAtUnixMilliseconds,
                updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                revokedAtUnixMilliseconds: existing.revokedAtUnixMilliseconds
            )
            try updateDevice(updated)
            try replaceGrantRows(
                deviceID: expected.deviceID,
                grants: expected.proposedGrants
            )
            try fenceDurableOperations(
                for: expected.deviceID,
                atUnixMilliseconds: occurredAtUnixMilliseconds
            )
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.grantExpansionApproved",
                deviceID: expected.deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return StoredDeviceGrantIdentitySnapshot(
                device: updated,
                grants: expected.proposedGrants,
                displayName: expected.displayName
            )
        }
    }

    public func resumeDevice(
        _ deviceID: UUID,
        grants: CapabilityGrantSet,
        occurredAtUnixMilliseconds: Int64
    ) throws -> StoredDeviceRecord {
        try transaction {
            guard let existing = try readDevice(deviceID) else {
                throw SecurityStoreError.deviceNotFound(deviceID)
            }
            try ensureNoPendingDeviceRevocation(for: deviceID)
            guard existing.authorization.state == .suspended else {
                throw SecurityStoreError.unsupportedGrantTransition(
                    existing.authorization.state
                )
            }
            guard occurredAtUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }
            let event: DeviceAuthorizationEvent = grants.isEmpty
                ? .resumeMonitorOnly
                : .resumeGranted
            let authorization = try existing.authorization.applying(event)
            let updated = try StoredDeviceRecord(
                deviceID: existing.deviceID,
                clientID: existing.clientID,
                sessionPublicKeyX963: existing.sessionPublicKeyX963,
                approvalPublicKeyX963: existing.approvalPublicKeyX963,
                authorization: authorization,
                policyRevision: existing.policyRevision,
                createdAtUnixMilliseconds: existing.createdAtUnixMilliseconds,
                updatedAtUnixMilliseconds: occurredAtUnixMilliseconds,
                revokedAtUnixMilliseconds: nil
            )
            try updateDevice(updated)
            try replaceGrantRows(deviceID: deviceID, grants: grants)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "device.resumedWithReviewedGrants",
                deviceID: deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return updated
        }
    }

    public func statusSequence() throws -> StoredStatusSequenceRecord? {
        let statement = try prepare(
            "SELECT generation, next_revision, exhausted FROM status_sequence WHERE singleton = 1"
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let generationText = sqlite3_column_text(statement, 0),
              let generation = UUID(uuidString: String(cString: generationText)) else {
            if result != SQLITE_ROW {
                throw sqliteError(operation: "read status sequence", code: result)
            }
            throw SecurityStoreError.invalidRecord
        }
        let revision = sqlite3_column_int64(statement, 1)
        guard revision >= 0 else { throw SecurityStoreError.invalidRecord }
        return try StoredStatusSequenceRecord(
            generation: generation,
            nextRevision: UInt64(revision),
            exhausted: sqlite3_column_int(statement, 2) == 1
        )
    }

    public func initializeStatusSequence(
        _ record: StoredStatusSequenceRecord
    ) throws {
        try transaction {
            try executeBound(
                "INSERT INTO status_sequence (singleton, generation, next_revision, exhausted) VALUES (1, ?1, ?2, ?3)"
            ) { statement in
                try bind(uuid: record.generation, to: statement, at: 1)
                sqlite3_bind_int64(statement, 2, Int64(record.nextRevision))
                sqlite3_bind_int(statement, 3, record.exhausted ? 1 : 0)
            }
        }
    }

    public func compareAndSwapStatusSequence(
        expected: StoredStatusSequenceRecord,
        replacement: StoredStatusSequenceRecord
    ) throws {
        try transaction {
            try executeBound(
                """
                UPDATE status_sequence SET
                    generation = ?4,
                    next_revision = ?5,
                    exhausted = ?6
                WHERE singleton = 1
                  AND generation = ?1
                  AND next_revision = ?2
                  AND exhausted = ?3
                """
            ) { statement in
                try bind(uuid: expected.generation, to: statement, at: 1)
                sqlite3_bind_int64(statement, 2, Int64(expected.nextRevision))
                sqlite3_bind_int(statement, 3, expected.exhausted ? 1 : 0)
                try bind(uuid: replacement.generation, to: statement, at: 4)
                sqlite3_bind_int64(statement, 5, Int64(replacement.nextRevision))
                sqlite3_bind_int(statement, 6, replacement.exhausted ? 1 : 0)
            }
            guard sqlite3_changes(database) == 1 else {
                throw SecurityStoreError.statusSequenceConflict
            }
        }
    }

    public func durableOperation(
        _ operationID: UUID
    ) throws -> StoredDurableOperationRecord? {
        try readDurableOperation(operationID)
    }

    public func retainedOperationCount(deviceID: UUID) throws -> Int {
        try scalarIntBound(
            "SELECT COUNT(*) FROM durable_operations WHERE device_id = ?1"
        ) { statement in
            try bind(uuid: deviceID, to: statement, at: 1)
        }
    }

    public func admitDurableOperation(
        _ record: StoredDurableOperationRecord
    ) throws -> DurableOperationAdmissionResult {
        guard [.pendingPolicy, .awaitingApproval, .queued].contains(record.state),
              record.terminalAtUnixMilliseconds == nil,
              record.terminalCode == nil else {
            throw SecurityStoreError.invalidRecord
        }
        return try transaction {
            if let existing = try readDurableOperation(record.operationID) {
                guard existing.requestDigest == record.requestDigest else {
                    throw SecurityStoreError.operationIDConflict(record.operationID)
                }
                return .existing(existing)
            }

            _ = try purgeExpiredTerminalOperations(
                nowUnixMilliseconds: record.createdAtUnixMilliseconds
            )
            guard try retainedOperationCount(deviceID: record.deviceID)
                    < retainedOperationLimitPerDevice else {
                throw SecurityStoreError.operationQuotaExceeded(record.deviceID)
            }
            guard let device = try readDevice(record.deviceID) else {
                throw SecurityStoreError.deviceNotFound(record.deviceID)
            }
            guard device.clientID == record.clientID,
                  device.authorization.state == .activeGranted,
                  device.authorization.authorizationEpoch.rawValue
                    == record.authorizationEpoch,
                  device.authorization.grantRevision.rawValue
                    == record.grantRevision,
                  device.policyRevision.rawValue == record.policyRevision else {
                throw SecurityStoreError.operationAuthorizationStale(
                    record.operationID
                )
            }
            let grantCount = try scalarIntBound(
                "SELECT COUNT(*) FROM device_grants WHERE device_id = ?1 AND capability_id = ?2"
            ) { statement in
                try bind(uuid: record.deviceID, to: statement, at: 1)
                try bind(text: record.capabilityID, to: statement, at: 2)
            }
            guard grantCount == 1 else {
                throw SecurityStoreError.operationCapabilityNotGranted(
                    record.operationID,
                    record.capabilityID
                )
            }
            try insertDurableOperation(record)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "operation.admitted",
                deviceID: record.deviceID,
                occurredAtUnixMilliseconds: record.updatedAtUnixMilliseconds
            )
            return .created(record)
        }
    }

    public func claimDurableOperationExecution(
        _ operationID: UUID,
        snapshot: DurableOperationExecutionSnapshot
    ) throws -> DurableOperationClaimResult {
        try transaction {
            guard let existing = try readDurableOperation(operationID) else {
                throw SecurityStoreError.operationNotFound(operationID)
            }
            guard existing.state == .queued else {
                throw SecurityStoreError.operationNotClaimable(
                    operationID,
                    existing.state
                )
            }
            guard snapshot.nowUnixMilliseconds >= existing.updatedAtUnixMilliseconds else {
                throw SecurityStoreError.invalidRecord
            }

            let device = try readDevice(existing.deviceID)
            let isExpired = snapshot.nowUnixMilliseconds >= existing.expiresAtUnixMilliseconds
            let authorizationMatches = device.map {
                $0.clientID == existing.clientID
                    && $0.authorization.state == .activeGranted
                    && $0.authorization.authorizationEpoch.rawValue == existing.authorizationEpoch
                    && $0.authorization.grantRevision.rawValue == existing.grantRevision
                    && $0.policyRevision.rawValue == existing.policyRevision
            } ?? false
            let executionMatches = snapshot.providerGeneration == existing.providerGeneration
                && snapshot.executionRevision == existing.executionRevision
                && snapshot.hostState == existing.requiredHostState

            if isExpired || !authorizationMatches || !executionMatches {
                let code = isExpired
                    ? "operation.expired"
                    : "operation.authorizationRevoked"
                let failed = try transitionedOperation(
                    existing,
                    to: .failed,
                    at: snapshot.nowUnixMilliseconds,
                    terminalCode: code
                )
                try updateDurableOperation(failed)
                try inject(.afterDeviceMutation)
                try inject(.beforeSecurityEvent)
                try insertSecurityEvent(
                    kind: code,
                    deviceID: existing.deviceID,
                    occurredAtUnixMilliseconds: snapshot.nowUnixMilliseconds
                )
                return .failed(failed)
            }

            let running = try transitionedOperation(
                existing,
                to: .running,
                at: snapshot.nowUnixMilliseconds
            )
            try updateDurableOperation(running)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "operation.executionClaimed",
                deviceID: existing.deviceID,
                occurredAtUnixMilliseconds: snapshot.nowUnixMilliseconds
            )
            return .claimed(running)
        }
    }

    public func transitionDurableOperation(
        _ operationID: UUID,
        to state: OperationState,
        occurredAtUnixMilliseconds: Int64,
        terminalCode: String? = nil
    ) throws -> StoredDurableOperationRecord {
        try transaction {
            guard let existing = try readDurableOperation(operationID) else {
                throw SecurityStoreError.operationNotFound(operationID)
            }
            let replacement = try transitionedOperation(
                existing,
                to: state,
                at: occurredAtUnixMilliseconds,
                terminalCode: terminalCode
            )
            try updateDurableOperation(replacement)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "operation.\(state.rawValue)",
                deviceID: existing.deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return replacement
        }
    }

    public func failQueuedOperationForUnavailableProvider(
        _ operationID: UUID,
        occurredAtUnixMilliseconds: Int64
    ) throws -> StoredDurableOperationRecord {
        try transaction {
            guard let existing = try readDurableOperation(operationID) else {
                throw SecurityStoreError.operationNotFound(operationID)
            }
            guard existing.state == .queued else { return existing }
            let failed = try transitionedOperation(
                existing,
                to: .failed,
                at: max(
                    occurredAtUnixMilliseconds,
                    existing.updatedAtUnixMilliseconds
                ),
                terminalCode: "provider.unavailable"
            )
            try updateDurableOperation(failed)
            try inject(.afterDeviceMutation)
            try inject(.beforeSecurityEvent)
            try insertSecurityEvent(
                kind: "provider.unavailable",
                deviceID: existing.deviceID,
                occurredAtUnixMilliseconds: failed.updatedAtUnixMilliseconds
            )
            return failed
        }
    }

    public func reconcileOperationsAtStartup(
        atUnixMilliseconds timestamp: Int64
    ) throws -> DurableOperationStartupReconciliation {
        guard timestamp >= 0 else { throw SecurityStoreError.invalidRecord }
        return try transaction {
            let operationIDs = try operationIDs(
                in: [.queued, .running, .cancelRequested]
            )
            var queuedFailed = 0
            var inFlightOutcomeUnknown = 0
            var replacements: [StoredDurableOperationRecord] = []
            for operationID in operationIDs {
                guard let existing = try readDurableOperation(operationID) else {
                    throw SecurityStoreError.operationNotFound(operationID)
                }
                let occurredAt = max(timestamp, existing.updatedAtUnixMilliseconds)
                let state: OperationState
                let code: String
                switch existing.state {
                case .queued:
                    state = .failed
                    code = "operation.hostRestarted"
                    queuedFailed += 1
                case .running, .cancelRequested:
                    state = .outcomeUnknown
                    code = "operation.outcomeUnknown"
                    inFlightOutcomeUnknown += 1
                default:
                    throw SecurityStoreError.invalidRecord
                }
                let replacement = try transitionedOperation(
                    existing,
                    to: state,
                    at: occurredAt,
                    terminalCode: code
                )
                try updateDurableOperation(replacement)
                replacements.append(replacement)
            }
            if !replacements.isEmpty {
                try inject(.afterDeviceMutation)
                try inject(.beforeSecurityEvent)
            }
            for replacement in replacements {
                try insertSecurityEvent(
                    kind: replacement.terminalCode!,
                    deviceID: replacement.deviceID,
                    occurredAtUnixMilliseconds:
                        replacement.updatedAtUnixMilliseconds
                )
            }
            return DurableOperationStartupReconciliation(
                queuedFailed: queuedFailed,
                inFlightOutcomeUnknown: inFlightOutcomeUnknown
            )
        }
    }

    public func purgeExpiredTerminalOperations(
        nowUnixMilliseconds: Int64
    ) throws -> Int {
        guard nowUnixMilliseconds >= 0 else {
            throw SecurityStoreError.invalidRecord
        }
        guard nowUnixMilliseconds >= Self.operationRetentionMilliseconds else {
            return 0
        }
        let cutoff = nowUnixMilliseconds - Self.operationRetentionMilliseconds
        try executeBound(
            "DELETE FROM durable_operations WHERE terminal_at_ms IS NOT NULL AND terminal_at_ms <= ?1"
        ) { statement in
            sqlite3_bind_int64(statement, 1, cutoff)
        }
        return Int(sqlite3_changes(database))
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try inject(.beforeTransactionCommit)
            try execute("COMMIT")
            return result
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertDevice(_ record: StoredDeviceRecord) throws {
        try executeBound(
            """
            INSERT INTO device_authorizations (
                device_id, client_id, session_public_key, approval_public_key,
                state, authorization_epoch, grant_revision, policy_revision,
                created_at_ms, updated_at_ms, revoked_at_ms
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            """
        ) { statement in
            try bind(record, to: statement)
        }
    }

    private func insertHostIdentity(_ record: StoredHostIdentityRecord) throws {
        try executeBound(
            """
            INSERT INTO host_identity (
                singleton, host_id, key_application_tag, host_fingerprint,
                certificate_der, certificate_not_before_ms, certificate_not_after_ms,
                established_at_ms, updated_at_ms, state, recovery_id
            ) VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            """
        ) { statement in
            try bind(record, to: statement)
        }
    }

    private func insertHostIdentityBootstrap(
        _ record: StoredHostIdentityBootstrapRecord
    ) throws {
        try executeBound(
            """
            INSERT INTO host_identity_bootstrap (
                singleton, host_id, key_application_tag, started_at_ms
            ) VALUES (1, ?1, ?2, ?3)
            """
        ) { statement in
            try bind(uuid: record.hostID, to: statement, at: 1)
            try bind(data: record.keyApplicationTag, to: statement, at: 2)
            sqlite3_bind_int64(
                statement,
                3,
                record.startedAtUnixMilliseconds
            )
        }
    }

    private func updateHostIdentity(_ record: StoredHostIdentityRecord) throws {
        try executeBound(
            """
            UPDATE host_identity SET
                host_id = ?1,
                key_application_tag = ?2,
                host_fingerprint = ?3,
                certificate_der = ?4,
                certificate_not_before_ms = ?5,
                certificate_not_after_ms = ?6,
                established_at_ms = ?7,
                updated_at_ms = ?8,
                state = ?9,
                recovery_id = ?10
            WHERE singleton = 1
            """
        ) { statement in
            try bind(record, to: statement)
        }
        guard sqlite3_changes(database) == 1 else {
            throw SecurityStoreError.hostIdentityNotFound
        }
    }

    private func replaceHostIdentityRecoveryReceipt(
        _ receipt: StoredHostIdentityRecoveryReceipt
    ) throws {
        try executeBound(
            """
            INSERT INTO host_identity_recovery_receipt (
                singleton, recovery_id, replaced_host_id,
                replaced_host_fingerprint, new_host_id, new_host_fingerprint,
                completed_at_ms
            ) VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(singleton) DO UPDATE SET
                recovery_id = excluded.recovery_id,
                replaced_host_id = excluded.replaced_host_id,
                replaced_host_fingerprint = excluded.replaced_host_fingerprint,
                new_host_id = excluded.new_host_id,
                new_host_fingerprint = excluded.new_host_fingerprint,
                completed_at_ms = excluded.completed_at_ms
            """
        ) { statement in
            try bind(uuid: receipt.recoveryID, to: statement, at: 1)
            try bind(uuid: receipt.replacedHostID, to: statement, at: 2)
            try bind(
                data: receipt.replacedHostFingerprint,
                to: statement,
                at: 3
            )
            try bind(uuid: receipt.newHostID, to: statement, at: 4)
            try bind(data: receipt.newHostFingerprint, to: statement, at: 5)
            sqlite3_bind_int64(
                statement,
                6,
                receipt.completedAtUnixMilliseconds
            )
        }
    }

    private func replaceHostIdentityRecoveryIntent(
        _ intent: StoredHostIdentityRecoveryIntent
    ) throws {
        try executeBound(
            """
            INSERT INTO host_identity_recovery_intent (
                singleton, command_id, recovery_id, review_id,
                expected_host_id, expected_host_fingerprint, cause,
                review_created_at_ms, review_expires_at_ms, confirmed_at_ms
            ) VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(singleton) DO UPDATE SET
                command_id = excluded.command_id,
                recovery_id = excluded.recovery_id,
                review_id = excluded.review_id,
                expected_host_id = excluded.expected_host_id,
                expected_host_fingerprint = excluded.expected_host_fingerprint,
                cause = excluded.cause,
                review_created_at_ms = excluded.review_created_at_ms,
                review_expires_at_ms = excluded.review_expires_at_ms,
                confirmed_at_ms = excluded.confirmed_at_ms
            """
        ) { statement in
            try bind(uuid: intent.commandID, to: statement, at: 1)
            try bind(uuid: intent.recoveryID, to: statement, at: 2)
            try bind(uuid: intent.reviewID, to: statement, at: 3)
            try bind(uuid: intent.expectedHostID, to: statement, at: 4)
            try bind(
                data: intent.expectedHostFingerprint,
                to: statement,
                at: 5
            )
            try bind(text: intent.cause.rawValue, to: statement, at: 6)
            sqlite3_bind_int64(
                statement,
                7,
                intent.reviewCreatedAtUnixMilliseconds
            )
            sqlite3_bind_int64(
                statement,
                8,
                intent.reviewExpiresAtUnixMilliseconds
            )
            sqlite3_bind_int64(
                statement,
                9,
                intent.confirmedAtUnixMilliseconds
            )
        }
    }

    private func updateDevice(_ record: StoredDeviceRecord) throws {
        try executeBound(
            """
            UPDATE device_authorizations SET
                state = ?2,
                authorization_epoch = ?3,
                grant_revision = ?4,
                updated_at_ms = ?5,
                revoked_at_ms = ?6
            WHERE device_id = ?1
            """
        ) { statement in
            try bind(uuid: record.deviceID, to: statement, at: 1)
            try bind(text: record.authorization.state.rawValue, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, Int64(record.authorization.authorizationEpoch.rawValue))
            sqlite3_bind_int64(statement, 4, Int64(record.authorization.grantRevision.rawValue))
            sqlite3_bind_int64(statement, 5, record.updatedAtUnixMilliseconds)
            if let revokedAt = record.revokedAtUnixMilliseconds {
                sqlite3_bind_int64(statement, 6, revokedAt)
            } else {
                sqlite3_bind_null(statement, 6)
            }
        }
        guard sqlite3_changes(database) == 1 else {
            throw SecurityStoreError.deviceNotFound(record.deviceID)
        }
    }

    private func insertDurableOperation(
        _ record: StoredDurableOperationRecord
    ) throws {
        try executeBound(
            """
            INSERT INTO durable_operations (
                operation_id, device_id, client_id, request_digest, state,
                capability_id, schema_version, provider_id, provider_version,
                provider_generation, execution_revision, authorization_epoch,
                grant_revision, policy_revision, required_host_state,
                expires_at_ms, created_at_ms, updated_at_ms, terminal_at_ms,
                terminal_code
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,
                ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20
            )
            """
        ) { statement in
            try bind(record, to: statement)
        }
    }

    private func updateDurableOperation(
        _ record: StoredDurableOperationRecord
    ) throws {
        try executeBound(
            """
            UPDATE durable_operations SET
                state = ?2,
                updated_at_ms = ?3,
                terminal_at_ms = ?4,
                terminal_code = ?5
            WHERE operation_id = ?1
            """
        ) { statement in
            try bind(uuid: record.operationID, to: statement, at: 1)
            try bind(text: record.state.rawValue, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, record.updatedAtUnixMilliseconds)
            if let terminalAt = record.terminalAtUnixMilliseconds {
                sqlite3_bind_int64(statement, 4, terminalAt)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            if let terminalCode = record.terminalCode {
                try bind(text: terminalCode, to: statement, at: 5)
            } else {
                sqlite3_bind_null(statement, 5)
            }
        }
        guard sqlite3_changes(database) == 1 else {
            throw SecurityStoreError.operationNotFound(record.operationID)
        }
    }

    private func readDurableOperation(
        _ operationID: UUID
    ) throws -> StoredDurableOperationRecord? {
        let statement = try prepare(
            """
            SELECT device_id, client_id, request_digest, state, capability_id,
                   schema_version, provider_id, provider_version,
                   provider_generation, execution_revision,
                   authorization_epoch, grant_revision, policy_revision,
                   required_host_state, expires_at_ms, created_at_ms,
                   updated_at_ms, terminal_at_ms, terminal_code
            FROM durable_operations WHERE operation_id = ?1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: operationID, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let deviceText = sqlite3_column_text(statement, 0),
              let deviceID = UUID(uuidString: String(cString: deviceText)),
              let clientText = sqlite3_column_text(statement, 1),
              let clientID = UUID(uuidString: String(cString: clientText)),
              let stateText = sqlite3_column_text(statement, 3),
              let state = OperationState(rawValue: String(cString: stateText)),
              let capabilityText = sqlite3_column_text(statement, 4),
              let providerText = sqlite3_column_text(statement, 6),
              let providerVersionText = sqlite3_column_text(statement, 7),
              let providerGenerationText = sqlite3_column_text(statement, 8),
              let providerGeneration = UUID(
                uuidString: String(cString: providerGenerationText)
              ),
              let executionRevisionText = sqlite3_column_text(statement, 9),
              let executionRevision = UUID(
                uuidString: String(cString: executionRevisionText)
              ),
              let hostStateText = sqlite3_column_text(statement, 13),
              let requiredHostState = HostState(
                rawValue: String(cString: hostStateText)
              ) else {
            throw SecurityStoreError.invalidRecord
        }
        let schemaVersion = sqlite3_column_int64(statement, 5)
        let authorizationEpoch = sqlite3_column_int64(statement, 10)
        let grantRevision = sqlite3_column_int64(statement, 11)
        let policyRevision = sqlite3_column_int64(statement, 12)
        guard schemaVersion >= 1,
              schemaVersion <= Int64(UInt32.max),
              authorizationEpoch >= 1,
              grantRevision >= 1,
              policyRevision >= 1 else {
            throw SecurityStoreError.invalidRecord
        }
        let terminalAt = sqlite3_column_type(statement, 17) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 17)
        let terminalCode: String?
        if sqlite3_column_type(statement, 18) == SQLITE_NULL {
            terminalCode = nil
        } else if let text = sqlite3_column_text(statement, 18) {
            terminalCode = String(cString: text)
        } else {
            throw SecurityStoreError.invalidRecord
        }
        return try StoredDurableOperationRecord(
            operationID: operationID,
            deviceID: deviceID,
            clientID: clientID,
            requestDigest: try columnData(statement, at: 2),
            state: state,
            capabilityID: String(cString: capabilityText),
            schemaVersion: UInt32(schemaVersion),
            providerID: String(cString: providerText),
            providerVersion: String(cString: providerVersionText),
            providerGeneration: providerGeneration,
            executionRevision: executionRevision,
            authorizationEpoch: UInt64(authorizationEpoch),
            grantRevision: UInt64(grantRevision),
            policyRevision: UInt64(policyRevision),
            requiredHostState: requiredHostState,
            expiresAtUnixMilliseconds: sqlite3_column_int64(statement, 14),
            createdAtUnixMilliseconds: sqlite3_column_int64(statement, 15),
            updatedAtUnixMilliseconds: sqlite3_column_int64(statement, 16),
            terminalAtUnixMilliseconds: terminalAt,
            terminalCode: terminalCode
        )
    }

    private func transitionedOperation(
        _ existing: StoredDurableOperationRecord,
        to state: OperationState,
        at timestamp: Int64,
        terminalCode: String? = nil
    ) throws -> StoredDurableOperationRecord {
        guard timestamp >= existing.updatedAtUnixMilliseconds else {
            throw SecurityStoreError.invalidRecord
        }
        _ = try OperationLifecycle(state: existing.state).transitioning(to: state)
        return try StoredDurableOperationRecord(
            operationID: existing.operationID,
            deviceID: existing.deviceID,
            clientID: existing.clientID,
            requestDigest: existing.requestDigest,
            state: state,
            capabilityID: existing.capabilityID,
            schemaVersion: existing.schemaVersion,
            providerID: existing.providerID,
            providerVersion: existing.providerVersion,
            providerGeneration: existing.providerGeneration,
            executionRevision: existing.executionRevision,
            authorizationEpoch: existing.authorizationEpoch,
            grantRevision: existing.grantRevision,
            policyRevision: existing.policyRevision,
            requiredHostState: existing.requiredHostState,
            expiresAtUnixMilliseconds: existing.expiresAtUnixMilliseconds,
            createdAtUnixMilliseconds: existing.createdAtUnixMilliseconds,
            updatedAtUnixMilliseconds: timestamp,
            terminalAtUnixMilliseconds: state.isTerminal ? timestamp : nil,
            terminalCode: state.isTerminal ? terminalCode : nil
        )
    }

    private func operationIDs(
        in states: Set<OperationState>
    ) throws -> [UUID] {
        guard !states.isEmpty else { return [] }
        let placeholders = states.map { _ in "?" }.joined(separator: ", ")
        let statement = try prepare(
            "SELECT operation_id FROM durable_operations WHERE state IN (\(placeholders)) ORDER BY operation_id"
        )
        defer { sqlite3_finalize(statement) }
        for (offset, state) in states.sorted(by: { $0.rawValue < $1.rawValue }).enumerated() {
            try bind(text: state.rawValue, to: statement, at: Int32(offset + 1))
        }
        var result: [UUID] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0),
                  let operationID = UUID(uuidString: String(cString: text)) else {
                if step != SQLITE_ROW {
                    throw sqliteError(operation: "read operation IDs", code: step)
                }
                throw SecurityStoreError.invalidRecord
            }
            result.append(operationID)
        }
    }

    private func fenceDurableOperations(
        for deviceID: UUID,
        atUnixMilliseconds timestamp: Int64
    ) throws {
        let newest = try scalarInt64Bound(
            """
            SELECT COALESCE(MAX(updated_at_ms), 0)
            FROM durable_operations
            WHERE device_id = ?1
              AND state IN ('pendingPolicy', 'awaitingApproval', 'queued', 'running')
            """
        ) { statement in
            try bind(uuid: deviceID, to: statement, at: 1)
        }
        guard timestamp >= newest else { throw SecurityStoreError.invalidRecord }
        try executeBound(
            """
            UPDATE durable_operations SET
                state = CASE
                    WHEN state IN ('pendingPolicy', 'awaitingApproval') THEN 'denied'
                    WHEN state = 'queued' THEN 'failed'
                    WHEN state = 'running' THEN 'cancelRequested'
                    ELSE state
                END,
                updated_at_ms = ?2,
                terminal_at_ms = CASE
                    WHEN state IN ('pendingPolicy', 'awaitingApproval', 'queued') THEN ?2
                    ELSE NULL
                END,
                terminal_code = CASE
                    WHEN state IN ('pendingPolicy', 'awaitingApproval', 'queued')
                        THEN 'operation.authorizationRevoked'
                    ELSE NULL
                END
            WHERE device_id = ?1
              AND state IN ('pendingPolicy', 'awaitingApproval', 'queued', 'running')
            """
        ) { statement in
            try bind(uuid: deviceID, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, timestamp)
        }
    }

    private func readDeviceRevocationRecord(
        whereClause: String,
        bind: (OpaquePointer) throws -> Void
    ) throws -> StoredDeviceRevocationRecord? {
        let statement = try prepare(
            """
            SELECT command_id, review_id, device_id, device_display_name,
                   expected_state, expected_authorization_epoch,
                   expected_grant_revision, review_created_at_ms,
                   review_expires_at_ms, confirmed_at_ms, phase,
                   result_authorization_epoch, result_grant_revision,
                   completed_at_ms
            FROM device_revocation_commands
            WHERE \(whereClause)
            ORDER BY command_id
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW,
              let commandText = sqlite3_column_text(statement, 0),
              let commandID = UUID(uuidString: String(cString: commandText)),
              let reviewText = sqlite3_column_text(statement, 1),
              let reviewID = UUID(uuidString: String(cString: reviewText)),
              let deviceText = sqlite3_column_text(statement, 2),
              let deviceID = UUID(uuidString: String(cString: deviceText)),
              let displayNameText = sqlite3_column_text(statement, 3),
              let stateText = sqlite3_column_text(statement, 4),
              let state = DeviceAuthorizationState(
                rawValue: String(cString: stateText)
              ),
              let phaseText = sqlite3_column_text(statement, 10) else {
            if result != SQLITE_ROW {
                throw sqliteError(
                    operation: "read device revocation command",
                    code: result
                )
            }
            throw SecurityStoreError.invalidRecord
        }
        let intent = try StoredDeviceRevocationIntent(
            commandID: commandID,
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: DeviceDisplayName(
                String(cString: displayNameText)
            ),
            reviewedState: state,
            authorizationEpoch: AuthorizationEpoch(
                rawValue: UInt64(sqlite3_column_int64(statement, 5))
            ),
            grantRevision: GrantRevision(
                rawValue: UInt64(sqlite3_column_int64(statement, 6))
            ),
            reviewCreatedAtUnixMilliseconds:
                sqlite3_column_int64(statement, 7),
            reviewExpiresAtUnixMilliseconds:
                sqlite3_column_int64(statement, 8),
            confirmedAtUnixMilliseconds:
                sqlite3_column_int64(statement, 9)
        )
        let phase = String(cString: phaseText)
        let receipt: StoredDeviceRevocationReceipt?
        if phase == "pending" {
            guard sqlite3_column_type(statement, 11) == SQLITE_NULL,
                  sqlite3_column_type(statement, 12) == SQLITE_NULL,
                  sqlite3_column_type(statement, 13) == SQLITE_NULL else {
                throw SecurityStoreError.invalidRecord
            }
            receipt = nil
        } else if phase == "completed",
                  sqlite3_column_type(statement, 11) != SQLITE_NULL,
                  sqlite3_column_type(statement, 12) != SQLITE_NULL,
                  sqlite3_column_type(statement, 13) != SQLITE_NULL {
            receipt = try StoredDeviceRevocationReceipt(
                commandID: commandID,
                reviewID: reviewID,
                deviceID: deviceID,
                authorizationEpoch: AuthorizationEpoch(
                    rawValue: UInt64(sqlite3_column_int64(statement, 11))
                ),
                grantRevision: GrantRevision(
                    rawValue: UInt64(sqlite3_column_int64(statement, 12))
                ),
                completedAtUnixMilliseconds:
                    sqlite3_column_int64(statement, 13)
            )
        } else {
            throw SecurityStoreError.invalidRecord
        }
        return try StoredDeviceRevocationRecord(
            intent: intent,
            receipt: receipt
        )
    }

    private func completeDeviceRevocationRow(
        _ receipt: StoredDeviceRevocationReceipt
    ) throws {
        try executeBound(
            """
            UPDATE device_revocation_commands SET
                phase = 'completed',
                pending_slot = NULL,
                result_authorization_epoch = ?2,
                result_grant_revision = ?3,
                completed_at_ms = ?4
            WHERE command_id = ?1 AND phase = 'pending'
            """
        ) { statement in
            try bind(uuid: receipt.commandID, to: statement, at: 1)
            sqlite3_bind_int64(
                statement,
                2,
                Int64(receipt.authorizationEpoch.rawValue)
            )
            sqlite3_bind_int64(
                statement,
                3,
                Int64(receipt.grantRevision.rawValue)
            )
            sqlite3_bind_int64(
                statement,
                4,
                receipt.completedAtUnixMilliseconds
            )
        }
        guard sqlite3_changes(database) == 1 else {
            throw SecurityStoreError.deviceRevocationConflict
        }
    }

    private func ensureNoPendingDeviceRevocation(
        for deviceID: UUID
    ) throws {
        if let pending = try pendingDeviceRevocationIntent(),
           pending.deviceID == deviceID {
            throw SecurityStoreError.deviceRevocationConflict
        }
    }

    private func readDevice(_ deviceID: UUID) throws -> StoredDeviceRecord? {
        let statement = try prepare(
            """
            SELECT client_id, session_public_key, approval_public_key, state,
                   authorization_epoch, grant_revision, policy_revision,
                   created_at_ms, updated_at_ms, revoked_at_ms
            FROM device_authorizations WHERE device_id = ?1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(uuid: deviceID, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: "read device", code: result)
        }

        guard let clientText = sqlite3_column_text(statement, 0),
              let clientID = UUID(uuidString: String(cString: clientText)),
              let stateText = sqlite3_column_text(statement, 3),
              let state = DeviceAuthorizationState(rawValue: String(cString: stateText)) else {
            throw SecurityStoreError.invalidRecord
        }
        let revokedAt = sqlite3_column_type(statement, 9) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 9)
        return try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: try columnData(statement, at: 1),
            approvalPublicKeyX963: try columnData(statement, at: 2),
            authorization: DeviceAuthorization(
                state: state,
                authorizationEpoch: .init(rawValue: UInt64(sqlite3_column_int64(statement, 4))),
                grantRevision: .init(rawValue: UInt64(sqlite3_column_int64(statement, 5)))
            ),
            policyRevision: .init(rawValue: UInt64(sqlite3_column_int64(statement, 6))),
            createdAtUnixMilliseconds: sqlite3_column_int64(statement, 7),
            updatedAtUnixMilliseconds: sqlite3_column_int64(statement, 8),
            revokedAtUnixMilliseconds: revokedAt
        )
    }

    private func activeDeviceIDs() throws -> [UUID] {
        let statement = try prepare(
            "SELECT device_id FROM device_authorizations WHERE state != 'revoked' ORDER BY device_id"
        )
        defer { sqlite3_finalize(statement) }
        var result: [UUID] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0),
                  let value = UUID(uuidString: String(cString: text)) else {
                if step != SQLITE_ROW {
                    throw sqliteError(operation: "read active device IDs", code: step)
                }
                throw SecurityStoreError.invalidRecord
            }
            result.append(value)
        }
    }

    private func insertSecurityEvent(
        kind: String,
        deviceID: UUID?,
        occurredAtUnixMilliseconds: Int64
    ) throws {
        try executeBound(
            "INSERT INTO security_events (occurred_at_ms, event_kind, device_id) VALUES (?1, ?2, ?3)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, occurredAtUnixMilliseconds)
            try bind(text: kind, to: statement, at: 2)
            if let deviceID {
                try bind(uuid: deviceID, to: statement, at: 3)
            } else {
                sqlite3_bind_null(statement, 3)
            }
        }
        try execute(
            """
            DELETE FROM security_events
            WHERE event_sequence <= (
                SELECT COALESCE(MAX(event_sequence), 0) - \(Self.securityEventLimit)
                FROM security_events
            )
            """
        )
    }

    private func replaceGrantRows(
        deviceID: UUID,
        grants: CapabilityGrantSet
    ) throws {
        try executeBound(
            "DELETE FROM device_grants WHERE device_id = ?1"
        ) { statement in
            try bind(uuid: deviceID, to: statement, at: 1)
        }
        for capabilityID in grants.capabilityIDs {
            try executeBound(
                "INSERT INTO device_grants (device_id, capability_id) VALUES (?1, ?2)"
            ) { statement in
                try bind(uuid: deviceID, to: statement, at: 1)
                try bind(text: capabilityID, to: statement, at: 2)
            }
        }
    }

    private func bind(_ record: StoredDeviceRecord, to statement: OpaquePointer) throws {
        try bind(uuid: record.deviceID, to: statement, at: 1)
        try bind(uuid: record.clientID, to: statement, at: 2)
        try bind(data: record.sessionPublicKeyX963, to: statement, at: 3)
        try bind(data: record.approvalPublicKeyX963, to: statement, at: 4)
        try bind(text: record.authorization.state.rawValue, to: statement, at: 5)
        sqlite3_bind_int64(statement, 6, Int64(record.authorization.authorizationEpoch.rawValue))
        sqlite3_bind_int64(statement, 7, Int64(record.authorization.grantRevision.rawValue))
        sqlite3_bind_int64(statement, 8, Int64(record.policyRevision.rawValue))
        sqlite3_bind_int64(statement, 9, record.createdAtUnixMilliseconds)
        sqlite3_bind_int64(statement, 10, record.updatedAtUnixMilliseconds)
        if let revokedAt = record.revokedAtUnixMilliseconds {
            sqlite3_bind_int64(statement, 11, revokedAt)
        } else {
            sqlite3_bind_null(statement, 11)
        }
    }

    private func bind(_ record: StoredHostIdentityRecord, to statement: OpaquePointer) throws {
        try bind(uuid: record.hostID, to: statement, at: 1)
        try bind(data: record.keyApplicationTag, to: statement, at: 2)
        try bind(data: record.hostFingerprint, to: statement, at: 3)
        try bind(data: record.certificateDER, to: statement, at: 4)
        sqlite3_bind_int64(statement, 5, record.certificateNotBeforeUnixMilliseconds)
        sqlite3_bind_int64(statement, 6, record.certificateNotAfterUnixMilliseconds)
        sqlite3_bind_int64(statement, 7, record.establishedAtUnixMilliseconds)
        sqlite3_bind_int64(statement, 8, record.updatedAtUnixMilliseconds)
        try bind(text: record.state.rawValue, to: statement, at: 9)
        if let recoveryID = record.recoveryID {
            try bind(uuid: recoveryID, to: statement, at: 10)
        } else {
            sqlite3_bind_null(statement, 10)
        }
    }

    private func bind(
        _ record: StoredDurableOperationRecord,
        to statement: OpaquePointer
    ) throws {
        try bind(uuid: record.operationID, to: statement, at: 1)
        try bind(uuid: record.deviceID, to: statement, at: 2)
        try bind(uuid: record.clientID, to: statement, at: 3)
        try bind(data: record.requestDigest, to: statement, at: 4)
        try bind(text: record.state.rawValue, to: statement, at: 5)
        try bind(text: record.capabilityID, to: statement, at: 6)
        sqlite3_bind_int64(statement, 7, Int64(record.schemaVersion))
        try bind(text: record.providerID, to: statement, at: 8)
        try bind(text: record.providerVersion, to: statement, at: 9)
        try bind(uuid: record.providerGeneration, to: statement, at: 10)
        try bind(uuid: record.executionRevision, to: statement, at: 11)
        sqlite3_bind_int64(statement, 12, Int64(record.authorizationEpoch))
        sqlite3_bind_int64(statement, 13, Int64(record.grantRevision))
        sqlite3_bind_int64(statement, 14, Int64(record.policyRevision))
        try bind(text: record.requiredHostState.rawValue, to: statement, at: 15)
        sqlite3_bind_int64(statement, 16, record.expiresAtUnixMilliseconds)
        sqlite3_bind_int64(statement, 17, record.createdAtUnixMilliseconds)
        sqlite3_bind_int64(statement, 18, record.updatedAtUnixMilliseconds)
        if let terminalAt = record.terminalAtUnixMilliseconds {
            sqlite3_bind_int64(statement, 19, terminalAt)
        } else {
            sqlite3_bind_null(statement, 19)
        }
        if let terminalCode = record.terminalCode {
            try bind(text: terminalCode, to: statement, at: 20)
        } else {
            sqlite3_bind_null(statement, 20)
        }
    }

    private func bind(uuid: UUID, to statement: OpaquePointer, at index: Int32) throws {
        try bind(text: uuid.uuidString.lowercased(), to: statement, at: index)
    }

    private func bind(text: String, to statement: OpaquePointer, at index: Int32) throws {
        let result = text.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind text", code: result)
        }
    }

    private func bind(data: Data, to statement: OpaquePointer, at index: Int32) throws {
        let result = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind data", code: result)
        }
    }

    private func columnData(_ statement: OpaquePointer, at index: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count >= 0, let pointer = sqlite3_column_blob(statement, index) else {
            throw SecurityStoreError.invalidRecord
        }
        return Data(bytes: pointer, count: count)
    }

    private func inject(_ point: PersistenceFaultPoint) throws {
        if injectedFaults.contains(point) {
            throw SecurityStoreError.injectedFault(point)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: sql, code: result)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func scalarIntBound(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void
    ) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: sql, code: result)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func scalarInt64Bound(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void
    ) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: sql, code: result)
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func executeBound(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteError(operation: sql, code: result)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw sqliteError(operation: sql, code: result)
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        try Self.execute(sql, on: database)
    }

    private func sqliteError(operation: String, code: Int32) -> SecurityStoreError {
        Self.sqliteError(operation: operation, code: code, database: database)
    }

    private static func configure(_ database: OpaquePointer) throws {
        sqlite3_busy_timeout(database, 2_000)
        try execute("PRAGMA foreign_keys = ON", on: database)
        try execute("PRAGMA trusted_schema = OFF", on: database)
        try execute("PRAGMA journal_mode = WAL", on: database)
        try execute("PRAGMA synchronous = FULL", on: database)
    }

    private static func setMaximumPageCount(
        _ maximumPageCount: Int32,
        on database: OpaquePointer
    ) throws -> Int32 {
        let sql = "PRAGMA max_page_count = \(maximumPageCount)"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        )
        guard prepareResult == SQLITE_OK, let statement else {
            throw sqliteError(
                operation: sql,
                code: prepareResult,
                database: database
            )
        }
        defer { sqlite3_finalize(statement) }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw sqliteError(
                operation: sql,
                code: stepResult,
                database: database
            )
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func migrate(_ database: OpaquePointer) throws {
        let version = try readUserVersion(database)
        guard version <= schemaVersion else {
            throw SecurityStoreError.futureSchema(found: version, supported: schemaVersion)
        }
        guard version < schemaVersion else { return }

        try execute("BEGIN EXCLUSIVE", on: database)
        do {
            if version == 0 {
                try execute(
                    """
                    CREATE TABLE device_authorizations (
                        device_id TEXT PRIMARY KEY NOT NULL,
                        client_id TEXT UNIQUE NOT NULL,
                        session_public_key BLOB NOT NULL CHECK(length(session_public_key) = 65),
                        approval_public_key BLOB NOT NULL CHECK(length(approval_public_key) = 65),
                        state TEXT NOT NULL CHECK(state IN ('activeMonitorOnly', 'activeGranted', 'suspended', 'revoked')),
                        authorization_epoch INTEGER NOT NULL CHECK(authorization_epoch BETWEEN 1 AND 9007199254740991),
                        grant_revision INTEGER NOT NULL CHECK(grant_revision BETWEEN 1 AND 9007199254740991),
                        policy_revision INTEGER NOT NULL CHECK(policy_revision BETWEEN 1 AND 9007199254740991),
                        created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                        revoked_at_ms INTEGER,
                        CHECK((state = 'revoked') = (revoked_at_ms IS NOT NULL))
                    );
                    CREATE TABLE pairing_consumptions (
                        pairing_id TEXT PRIMARY KEY NOT NULL,
                        device_id TEXT UNIQUE NOT NULL,
                        consumed_at_ms INTEGER NOT NULL CHECK(consumed_at_ms >= 0)
                    ) WITHOUT ROWID;
                    CREATE TABLE device_grants (
                        device_id TEXT NOT NULL REFERENCES device_authorizations(device_id) ON DELETE CASCADE,
                        capability_id TEXT NOT NULL CHECK(length(capability_id) BETWEEN 1 AND 96),
                        PRIMARY KEY(device_id, capability_id)
                    ) WITHOUT ROWID;
                    CREATE TABLE security_events (
                        event_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                        occurred_at_ms INTEGER NOT NULL CHECK(occurred_at_ms >= 0),
                        event_kind TEXT NOT NULL CHECK(length(event_kind) BETWEEN 1 AND 96),
                        device_id TEXT
                    );
                    CREATE TABLE security_control (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        last_integrity_check_ms INTEGER
                    );
                    INSERT INTO security_control(singleton, last_integrity_check_ms) VALUES (1, NULL);
                    CREATE TABLE status_sequence (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        generation TEXT NOT NULL,
                        next_revision INTEGER NOT NULL CHECK(next_revision BETWEEN 0 AND 9007199254740991),
                        exhausted INTEGER NOT NULL CHECK(exhausted IN (0, 1)),
                        CHECK(exhausted = 0 OR next_revision = 9007199254740991)
                    );
                    CREATE TABLE host_identity (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        host_id TEXT UNIQUE NOT NULL,
                        key_application_tag BLOB NOT NULL CHECK(length(key_application_tag) BETWEEN 16 AND 128),
                        host_fingerprint BLOB NOT NULL CHECK(length(host_fingerprint) = 32),
                        certificate_der BLOB NOT NULL CHECK(length(certificate_der) BETWEEN 1 AND 4096),
                        certificate_not_before_ms INTEGER NOT NULL CHECK(certificate_not_before_ms >= 0),
                        certificate_not_after_ms INTEGER NOT NULL CHECK(certificate_not_after_ms > certificate_not_before_ms),
                        established_at_ms INTEGER NOT NULL CHECK(established_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= established_at_ms),
                        state TEXT NOT NULL CHECK(state IN ('ready', 'fencedForReplacement')),
                        recovery_id TEXT,
                        CHECK((state = 'ready') = (recovery_id IS NULL))
                    );
                    CREATE TABLE durable_operations (
                        operation_id TEXT PRIMARY KEY NOT NULL,
                        device_id TEXT NOT NULL REFERENCES device_authorizations(device_id),
                        client_id TEXT NOT NULL,
                        request_digest BLOB NOT NULL CHECK(length(request_digest) = 32),
                        state TEXT NOT NULL CHECK(state IN (
                            'pendingPolicy', 'denied', 'awaitingApproval', 'expired',
                            'queued', 'running', 'cancelRequested', 'succeeded',
                            'failed', 'cancelled', 'outcomeUnknown'
                        )),
                        capability_id TEXT NOT NULL CHECK(length(capability_id) BETWEEN 1 AND 96),
                        schema_version INTEGER NOT NULL CHECK(schema_version BETWEEN 1 AND 4294967295),
                        provider_id TEXT NOT NULL CHECK(length(provider_id) BETWEEN 1 AND 96),
                        provider_version TEXT NOT NULL CHECK(length(provider_version) BETWEEN 1 AND 64),
                        provider_generation TEXT NOT NULL,
                        execution_revision TEXT NOT NULL,
                        authorization_epoch INTEGER NOT NULL CHECK(authorization_epoch BETWEEN 1 AND 9007199254740991),
                        grant_revision INTEGER NOT NULL CHECK(grant_revision BETWEEN 1 AND 9007199254740991),
                        policy_revision INTEGER NOT NULL CHECK(policy_revision BETWEEN 1 AND 9007199254740991),
                        required_host_state TEXT NOT NULL CHECK(required_host_state IN (
                            'userSessionActive', 'userSessionLocked', 'otherConsoleUserActive',
                            'serviceStoppingForLogout', 'hostPreparingForSleep'
                        )),
                        expires_at_ms INTEGER NOT NULL CHECK(expires_at_ms BETWEEN 1 AND 9007199254740991),
                        created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                        terminal_at_ms INTEGER,
                        terminal_code TEXT CHECK(terminal_code IS NULL OR length(terminal_code) BETWEEN 1 AND 96),
                        CHECK(expires_at_ms > created_at_ms),
                        CHECK((state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown')) = (terminal_at_ms IS NOT NULL)),
                        CHECK(terminal_at_ms IS NULL OR (terminal_at_ms >= created_at_ms AND terminal_at_ms <= updated_at_ms)),
                        CHECK(state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown') OR terminal_code IS NULL)
                    );
                    CREATE INDEX durable_operations_device_retention
                        ON durable_operations(device_id, terminal_at_ms);
                    CREATE INDEX durable_operations_recovery
                        ON durable_operations(state);
                    PRAGMA user_version = 3;
                    """,
                    on: database
                )
            } else if version == 1 {
                try execute(
                    """
                    CREATE TABLE host_identity (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        host_id TEXT UNIQUE NOT NULL,
                        key_application_tag BLOB NOT NULL CHECK(length(key_application_tag) BETWEEN 16 AND 128),
                        host_fingerprint BLOB NOT NULL CHECK(length(host_fingerprint) = 32),
                        certificate_der BLOB NOT NULL CHECK(length(certificate_der) BETWEEN 1 AND 4096),
                        certificate_not_before_ms INTEGER NOT NULL CHECK(certificate_not_before_ms >= 0),
                        certificate_not_after_ms INTEGER NOT NULL CHECK(certificate_not_after_ms > certificate_not_before_ms),
                        established_at_ms INTEGER NOT NULL CHECK(established_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= established_at_ms),
                        state TEXT NOT NULL CHECK(state IN ('ready', 'fencedForReplacement')),
                        recovery_id TEXT,
                        CHECK((state = 'ready') = (recovery_id IS NULL))
                    );
                    CREATE TABLE durable_operations (
                        operation_id TEXT PRIMARY KEY NOT NULL,
                        device_id TEXT NOT NULL REFERENCES device_authorizations(device_id),
                        client_id TEXT NOT NULL,
                        request_digest BLOB NOT NULL CHECK(length(request_digest) = 32),
                        state TEXT NOT NULL CHECK(state IN (
                            'pendingPolicy', 'denied', 'awaitingApproval', 'expired',
                            'queued', 'running', 'cancelRequested', 'succeeded',
                            'failed', 'cancelled', 'outcomeUnknown'
                        )),
                        capability_id TEXT NOT NULL CHECK(length(capability_id) BETWEEN 1 AND 96),
                        schema_version INTEGER NOT NULL CHECK(schema_version BETWEEN 1 AND 4294967295),
                        provider_id TEXT NOT NULL CHECK(length(provider_id) BETWEEN 1 AND 96),
                        provider_version TEXT NOT NULL CHECK(length(provider_version) BETWEEN 1 AND 64),
                        provider_generation TEXT NOT NULL,
                        execution_revision TEXT NOT NULL,
                        authorization_epoch INTEGER NOT NULL CHECK(authorization_epoch BETWEEN 1 AND 9007199254740991),
                        grant_revision INTEGER NOT NULL CHECK(grant_revision BETWEEN 1 AND 9007199254740991),
                        policy_revision INTEGER NOT NULL CHECK(policy_revision BETWEEN 1 AND 9007199254740991),
                        required_host_state TEXT NOT NULL CHECK(required_host_state IN (
                            'userSessionActive', 'userSessionLocked', 'otherConsoleUserActive',
                            'serviceStoppingForLogout', 'hostPreparingForSleep'
                        )),
                        expires_at_ms INTEGER NOT NULL CHECK(expires_at_ms BETWEEN 1 AND 9007199254740991),
                        created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                        terminal_at_ms INTEGER,
                        terminal_code TEXT CHECK(terminal_code IS NULL OR length(terminal_code) BETWEEN 1 AND 96),
                        CHECK(expires_at_ms > created_at_ms),
                        CHECK((state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown')) = (terminal_at_ms IS NOT NULL)),
                        CHECK(terminal_at_ms IS NULL OR (terminal_at_ms >= created_at_ms AND terminal_at_ms <= updated_at_ms)),
                        CHECK(state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown') OR terminal_code IS NULL)
                    );
                    CREATE INDEX durable_operations_device_retention
                        ON durable_operations(device_id, terminal_at_ms);
                    CREATE INDEX durable_operations_recovery
                        ON durable_operations(state);
                    PRAGMA user_version = 3;
                    """,
                    on: database
                )
            } else if version == 2 {
                try execute(
                    """
                    CREATE TABLE durable_operations (
                        operation_id TEXT PRIMARY KEY NOT NULL,
                        device_id TEXT NOT NULL REFERENCES device_authorizations(device_id),
                        client_id TEXT NOT NULL,
                        request_digest BLOB NOT NULL CHECK(length(request_digest) = 32),
                        state TEXT NOT NULL CHECK(state IN (
                            'pendingPolicy', 'denied', 'awaitingApproval', 'expired',
                            'queued', 'running', 'cancelRequested', 'succeeded',
                            'failed', 'cancelled', 'outcomeUnknown'
                        )),
                        capability_id TEXT NOT NULL CHECK(length(capability_id) BETWEEN 1 AND 96),
                        schema_version INTEGER NOT NULL CHECK(schema_version BETWEEN 1 AND 4294967295),
                        provider_id TEXT NOT NULL CHECK(length(provider_id) BETWEEN 1 AND 96),
                        provider_version TEXT NOT NULL CHECK(length(provider_version) BETWEEN 1 AND 64),
                        provider_generation TEXT NOT NULL,
                        execution_revision TEXT NOT NULL,
                        authorization_epoch INTEGER NOT NULL CHECK(authorization_epoch BETWEEN 1 AND 9007199254740991),
                        grant_revision INTEGER NOT NULL CHECK(grant_revision BETWEEN 1 AND 9007199254740991),
                        policy_revision INTEGER NOT NULL CHECK(policy_revision BETWEEN 1 AND 9007199254740991),
                        required_host_state TEXT NOT NULL CHECK(required_host_state IN (
                            'userSessionActive', 'userSessionLocked', 'otherConsoleUserActive',
                            'serviceStoppingForLogout', 'hostPreparingForSleep'
                        )),
                        expires_at_ms INTEGER NOT NULL CHECK(expires_at_ms BETWEEN 1 AND 9007199254740991),
                        created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                        terminal_at_ms INTEGER,
                        terminal_code TEXT CHECK(terminal_code IS NULL OR length(terminal_code) BETWEEN 1 AND 96),
                        CHECK(expires_at_ms > created_at_ms),
                        CHECK((state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown')) = (terminal_at_ms IS NOT NULL)),
                        CHECK(terminal_at_ms IS NULL OR (terminal_at_ms >= created_at_ms AND terminal_at_ms <= updated_at_ms)),
                        CHECK(state IN ('denied', 'expired', 'succeeded', 'failed', 'cancelled', 'outcomeUnknown') OR terminal_code IS NULL)
                    );
                    CREATE INDEX durable_operations_device_retention
                        ON durable_operations(device_id, terminal_at_ms);
                    CREATE INDEX durable_operations_recovery
                        ON durable_operations(state);
                    PRAGMA user_version = 3;
                    """,
                    on: database
                )
            }
            if version < 4 {
                try execute(
                    """
                    CREATE TABLE device_display_names (
                        device_id TEXT PRIMARY KEY NOT NULL
                            REFERENCES device_authorizations(device_id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL
                            CHECK(length(CAST(display_name AS BLOB)) BETWEEN 1 AND 64),
                        updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= 0)
                    ) WITHOUT ROWID;
                    PRAGMA user_version = 4;
                    """,
                    on: database
                )
            }
            if version < 5 {
                try execute(
                    """
                    CREATE TABLE host_identity_bootstrap (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        host_id TEXT UNIQUE NOT NULL,
                        key_application_tag BLOB UNIQUE NOT NULL
                            CHECK(length(key_application_tag) BETWEEN 16 AND 128),
                        started_at_ms INTEGER NOT NULL CHECK(started_at_ms >= 0)
                    );
                    PRAGMA user_version = 5;
                    """,
                    on: database
                )
            }
            if version < 6 {
                try execute(
                    """
                    CREATE TABLE host_identity_recovery_receipt (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        recovery_id TEXT UNIQUE NOT NULL,
                        replaced_host_id TEXT NOT NULL,
                        replaced_host_fingerprint BLOB NOT NULL
                            CHECK(length(replaced_host_fingerprint) = 32),
                        new_host_id TEXT NOT NULL,
                        new_host_fingerprint BLOB NOT NULL
                            CHECK(length(new_host_fingerprint) = 32),
                        completed_at_ms INTEGER NOT NULL
                            CHECK(completed_at_ms >= 0),
                        CHECK(replaced_host_id != new_host_id),
                        CHECK(replaced_host_fingerprint != new_host_fingerprint)
                    );
                    PRAGMA user_version = 6;
                    """,
                    on: database
                )
            }
            if version < 7 {
                try execute(
                    """
                    CREATE TABLE host_identity_recovery_intent (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        command_id TEXT UNIQUE NOT NULL,
                        recovery_id TEXT UNIQUE NOT NULL,
                        review_id TEXT UNIQUE NOT NULL,
                        expected_host_id TEXT NOT NULL,
                        expected_host_fingerprint BLOB NOT NULL
                            CHECK(length(expected_host_fingerprint) = 32),
                        cause TEXT NOT NULL CHECK(cause IN (
                            'keyUnavailable', 'suspectedCompromise',
                            'userRequestedReset'
                        )),
                        review_created_at_ms INTEGER NOT NULL
                            CHECK(review_created_at_ms >= 0),
                        review_expires_at_ms INTEGER NOT NULL,
                        confirmed_at_ms INTEGER NOT NULL,
                        CHECK(command_id != recovery_id),
                        CHECK(review_expires_at_ms = review_created_at_ms + 300000),
                        CHECK(confirmed_at_ms >= review_created_at_ms),
                        CHECK(confirmed_at_ms < review_expires_at_ms)
                    );
                    PRAGMA user_version = 7;
                    """,
                    on: database
                )
            }
            if version < 8 {
                try execute(
                    """
                    CREATE TABLE device_revocation_commands (
                        command_id TEXT PRIMARY KEY NOT NULL,
                        review_id TEXT UNIQUE NOT NULL,
                        device_id TEXT UNIQUE NOT NULL
                            REFERENCES device_authorizations(device_id)
                            ON DELETE CASCADE,
                        device_display_name TEXT NOT NULL
                            CHECK(length(CAST(device_display_name AS BLOB)) BETWEEN 1 AND 64),
                        expected_state TEXT NOT NULL CHECK(expected_state IN (
                            'activeMonitorOnly', 'activeGranted', 'suspended'
                        )),
                        expected_authorization_epoch INTEGER NOT NULL CHECK(
                            expected_authorization_epoch BETWEEN 1 AND 9007199254740990
                        ),
                        expected_grant_revision INTEGER NOT NULL CHECK(
                            expected_grant_revision BETWEEN 1 AND 9007199254740990
                        ),
                        review_created_at_ms INTEGER NOT NULL CHECK(
                            review_created_at_ms BETWEEN 0 AND 9007199254440991
                        ),
                        review_expires_at_ms INTEGER NOT NULL,
                        confirmed_at_ms INTEGER NOT NULL,
                        phase TEXT NOT NULL CHECK(phase IN ('pending', 'completed')),
                        pending_slot INTEGER UNIQUE,
                        result_authorization_epoch INTEGER,
                        result_grant_revision INTEGER,
                        completed_at_ms INTEGER,
                        CHECK(command_id != review_id),
                        CHECK(command_id != device_id),
                        CHECK(review_id != device_id),
                        CHECK(review_expires_at_ms = review_created_at_ms + 300000),
                        CHECK(confirmed_at_ms >= review_created_at_ms),
                        CHECK(confirmed_at_ms < review_expires_at_ms),
                        CHECK(
                            (phase = 'pending'
                                AND pending_slot = 1
                                AND result_authorization_epoch IS NULL
                                AND result_grant_revision IS NULL
                                AND completed_at_ms IS NULL)
                            OR
                            (phase = 'completed'
                                AND pending_slot IS NULL
                                AND result_authorization_epoch IS NOT NULL
                                AND result_grant_revision IS NOT NULL
                                AND completed_at_ms IS NOT NULL
                                AND result_authorization_epoch
                                    = expected_authorization_epoch + 1
                                AND result_grant_revision
                                    = expected_grant_revision + 1
                                AND completed_at_ms >= confirmed_at_ms
                                AND completed_at_ms <= 9007199254740991)
                        )
                    ) WITHOUT ROWID;
                    PRAGMA user_version = 8;
                    """,
                    on: database
                )
            }
            try execute("COMMIT", on: database)
        } catch {
            _ = try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    private static func readUserVersion(_ database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            database,
            "PRAGMA user_version",
            -1,
            &statement,
            nil
        )
        guard prepareResult == SQLITE_OK, let statement else {
            throw sqliteError(
                operation: "read user_version",
                code: prepareResult,
                database: database
            )
        }
        defer { sqlite3_finalize(statement) }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw sqliteError(
                operation: "read user_version",
                code: stepResult,
                database: database
            )
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SecurityStoreError.sqlite(
                operation: sql,
                code: result,
                message: message
            )
        }
    }

    private static func sqliteError(
        operation: String,
        code: Int32,
        database: OpaquePointer
    ) -> SecurityStoreError {
        SecurityStoreError.sqlite(
            operation: operation,
            code: code,
            message: String(cString: sqlite3_errmsg(database))
        )
    }
}
#endif
