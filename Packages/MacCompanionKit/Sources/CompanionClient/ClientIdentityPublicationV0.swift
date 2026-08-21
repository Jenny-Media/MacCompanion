import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import Foundation

public enum ClientSigningKeyRoleV0: String, Codable, CaseIterable, Sendable {
    case session
    case approval
}

public enum ClientKeyProtectionV0: String, Codable, CaseIterable, Sendable {
    /// Background reconnect is allowed after the device has been unlocked once
    /// since boot. The key remains nonexportable and this-device-only.
    case afterFirstUnlockThisDeviceOnly

    /// Every approval signature requires an unlocked device and fresh local
    /// user presence. The key remains nonexportable and this-device-only.
    case whenUnlockedThisDeviceOnlyUserPresence
}

public enum ClientApprovalPresenceReasonV0: String, Codable, CaseIterable, Sendable {
    case pairNewMac
    case approveOperation
    case startInteractiveControl
    case expandGrant
}

public enum ClientIdentityPublicationErrorV0: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidPhase
    case completionMismatch
    case keyUnavailable
    case persistenceConflict
}

public struct ClientSigningKeyReferenceV0: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) throws {
        guard rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.rawValue = rawValue
    }
}

public struct ClientCustodiedPublicKeyV0: Equatable, Sendable {
    public let role: ClientSigningKeyRoleV0
    public let reference: ClientSigningKeyReferenceV0
    public let publicKeyX963: Data
    public let protection: ClientKeyProtectionV0

    public init(
        role: ClientSigningKeyRoleV0,
        reference: ClientSigningKeyReferenceV0,
        publicKeyX963: Data,
        protection: ClientKeyProtectionV0
    ) throws {
        let requiredProtection: ClientKeyProtectionV0 = switch role {
        case .session: .afterFirstUnlockThisDeviceOnly
        case .approval: .whenUnlockedThisDeviceOnlyUserPresence
        }
        guard protection == requiredProtection else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        do {
            try CompanionSecurityV0.validateSigningPublicKey(publicKeyX963)
        } catch {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.role = role
        self.reference = reference
        self.publicKeyX963 = publicKeyX963
        self.protection = protection
    }
}

public struct ClientPreparedIdentityV0: Equatable, Sendable {
    public let pairingID: UUID
    public let clientID: UUID
    public let sessionKey: ClientCustodiedPublicKeyV0
    public let approvalKey: ClientCustodiedPublicKeyV0

    public init(
        pairingID: UUID,
        clientID: UUID,
        sessionKey: ClientCustodiedPublicKeyV0,
        approvalKey: ClientCustodiedPublicKeyV0
    ) throws {
        guard sessionKey.role == .session,
              approvalKey.role == .approval,
              sessionKey.reference != approvalKey.reference,
              sessionKey.publicKeyX963 != approvalKey.publicKeyX963 else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.pairingID = pairingID
        self.clientID = clientID
        self.sessionKey = sessionKey
        self.approvalKey = approvalKey
    }
}

/// Keychain/Secure Enclave adapter boundary. Private-key bytes and export
/// operations are intentionally absent. Validation checks the complete pair in
/// one custody-owner turn immediately before durable publication.
public protocol ClientIdentityKeyCustodyV0: Sendable {
    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws
}

/// Narrow adapter used by both pairing proof and ordinary reconnect. It holds
/// only an opaque session-key reference and delegates the normative input to
/// custody; approval-key access is impossible through this value.
public struct ClientCustodiedSessionSignerV0:
    ClientPairingSessionSigningV0,
    ClientSessionAuthenticationSigningV0,
    Sendable
{
    private let custody: any ClientIdentityKeyCustodyV0
    private let reference: ClientSigningKeyReferenceV0

    public init(
        custody: any ClientIdentityKeyCustodyV0,
        sessionKey: ClientCustodiedPublicKeyV0
    ) throws {
        guard sessionKey.role == .session,
              sessionKey.protection == .afterFirstUnlockThisDeviceOnly else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.custody = custody
        reference = sessionKey.reference
    }

    public func signPairingInput(_ input: Data) async throws -> Data {
        try await signature(input)
    }

    public func signAuthenticationInput(_ input: Data) async throws -> Data {
        try await signature(input)
    }

    private func signature(_ input: Data) async throws -> Data {
        let value = try await custody.signSessionInput(input, using: reference)
        guard value.count == 64 else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        return value
    }
}

public struct ClientDurablePairedHostV0: Equatable, Sendable {
    public let pairingID: UUID
    public let clientID: UUID
    public let hostID: UUID
    public let deviceID: UUID
    public let hostFingerprint: Data
    public let endpoints: [EndpointCandidate]
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let sessionKey: ClientCustodiedPublicKeyV0
    public let approvalKey: ClientCustodiedPublicKeyV0

    public init(
        host: ClientPairedHostV0,
        identity: ClientPreparedIdentityV0
    ) throws {
        guard host.pairingID == identity.pairingID,
              host.clientID == identity.clientID,
              host.hostFingerprint.count == 32,
              (1...8).contains(host.endpoints.count),
              Set(host.endpoints).count == host.endpoints.count,
              host.deviceState == .activeMonitorOnly,
              host.authorizationEpoch.rawValue == 1,
              host.grantRevision.rawValue == 1,
              host.policyRevision.rawValue >= 1 else {
            throw ClientIdentityPublicationErrorV0.completionMismatch
        }
        pairingID = host.pairingID
        clientID = host.clientID
        hostID = host.hostID
        deviceID = host.deviceID
        hostFingerprint = host.hostFingerprint
        endpoints = host.endpoints
        deviceState = host.deviceState
        authorizationEpoch = host.authorizationEpoch
        grantRevision = host.grantRevision
        policyRevision = host.policyRevision
        sessionKey = identity.sessionKey
        approvalKey = identity.approvalKey
    }
}

public enum ClientPairedHostCommitResultV0: Equatable, Sendable {
    case inserted
    case alreadyPresentExactRecord
}

/// Implementations make a complete record visible in one transaction. They
/// return `alreadyPresentExactRecord` only for byte-for-byte semantic identity;
/// an existing conflicting pairing, host, device, or key reference fails.
public protocol ClientPairedHostPersistenceV0: Sendable {
    func commitAtomically(
        _ record: ClientDurablePairedHostV0
    ) async throws -> ClientPairedHostCommitResultV0
}

public enum ClientIdentityPublicationPhaseV0: String, Equatable, Sendable {
    case idle
    case preparing
    case ready
    case publishing
    case published
    case discarding
    case closed
}

/// Cross-store publication owner. Both nonexportable keys are created first;
/// their exact references/public keys are revalidated immediately before the
/// complete paired-host record is atomically made visible. A database failure
/// returns to `ready` for retry and publishes no partial record.
public actor ClientIdentityPublicationAuthorityV0 {
    public private(set) var phase: ClientIdentityPublicationPhaseV0 = .idle

    private let custody: any ClientIdentityKeyCustodyV0
    private let persistence: any ClientPairedHostPersistenceV0
    private var preparedIdentity: ClientPreparedIdentityV0?

    public init(
        custody: any ClientIdentityKeyCustodyV0,
        persistence: any ClientPairedHostPersistenceV0
    ) {
        self.custody = custody
        self.persistence = persistence
    }

    @discardableResult
    public func prepare(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        guard phase == .idle else {
            throw ClientIdentityPublicationErrorV0.invalidPhase
        }
        phase = .preparing
        do {
            let identity = try await custody.prepareIdentity(
                pairingID: pairingID,
                clientID: clientID
            )
            guard identity.pairingID == pairingID,
                  identity.clientID == clientID else {
                throw ClientIdentityPublicationErrorV0.invalidIdentity
            }
            preparedIdentity = identity
            phase = .ready
            return identity
        } catch {
            phase = .idle
            throw error
        }
    }

    @discardableResult
    public func publish(
        _ host: ClientPairedHostV0
    ) async throws -> ClientDurablePairedHostV0 {
        guard phase == .ready, let identity = preparedIdentity else {
            throw ClientIdentityPublicationErrorV0.invalidPhase
        }
        let record = try ClientDurablePairedHostV0(
            host: host,
            identity: identity
        )
        phase = .publishing
        do {
            guard try await custody.validatePreparedIdentity(identity) else {
                phase = .ready
                throw ClientIdentityPublicationErrorV0.keyUnavailable
            }
            _ = try await persistence.commitAtomically(record)
            preparedIdentity = nil
            phase = .published
            return record
        } catch {
            if phase == .publishing {
                phase = .ready
            }
            throw error
        }
    }

    public func discard() async throws {
        guard phase == .ready, let identity = preparedIdentity else {
            throw ClientIdentityPublicationErrorV0.invalidPhase
        }
        phase = .discarding
        do {
            try await custody.discardPreparedIdentity(identity)
            preparedIdentity = nil
            phase = .closed
        } catch {
            phase = .ready
            throw error
        }
    }
}
