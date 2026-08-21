import CompanionDiscovery
import CompanionDomain
import CompanionWire
import Foundation

public enum ClientPairedHostStorageErrorV0: Error, Equatable, Sendable {
    case invalidRecord
    case nonCanonicalEncoding
    case recoveryConflict
    case keyUnavailable
}

private struct StoredAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireStoredKeys(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(keyedBy: StoredAnyCodingKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw ClientPairedHostStorageErrorV0.invalidRecord
    }
}

private struct StoredClientKeyV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role, reference, publicKey, protection
    }

    let role: ClientSigningKeyRoleV0
    let reference: WireUUID
    let publicKey: WireBytes65
    let protection: ClientKeyProtectionV0

    init(_ value: ClientCustodiedPublicKeyV0) throws {
        role = value.role
        reference = WireUUID(value.reference.rawValue)
        publicKey = try WireBytes65(value.publicKeyX963)
        protection = value.protection
    }

    init(from decoder: Decoder) throws {
        try requireStoredKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ClientSigningKeyRoleV0.self, forKey: .role)
        reference = try container.decode(WireUUID.self, forKey: .reference)
        publicKey = try container.decode(WireBytes65.self, forKey: .publicKey)
        protection = try container.decode(ClientKeyProtectionV0.self, forKey: .protection)
        _ = try domainValue()
    }

    func domainValue() throws -> ClientCustodiedPublicKeyV0 {
        try ClientCustodiedPublicKeyV0(
            role: role,
            reference: ClientSigningKeyReferenceV0(reference.rawValue),
            publicKeyX963: publicKey.rawValue,
            protection: protection
        )
    }
}

private struct StoredPairedHostV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, pairingID, clientID, hostID, deviceID
        case hostFingerprint, endpoints, deviceState, authorizationEpoch
        case grantRevision, policyRevision, sessionKey, approvalKey
    }

    let schemaVersion: UInt16
    let pairingID: WireUUID
    let clientID: WireUUID
    let hostID: WireUUID
    let deviceID: WireUUID
    let hostFingerprint: WireFingerprint
    let endpoints: [EndpointCandidate]
    let deviceState: DeviceAuthorizationState
    let authorizationEpoch: AuthorizationEpoch
    let grantRevision: GrantRevision
    let policyRevision: PolicyRevision
    let sessionKey: StoredClientKeyV0
    let approvalKey: StoredClientKeyV0

    init(_ value: ClientDurablePairedHostV0) throws {
        schemaVersion = 1
        pairingID = WireUUID(value.pairingID)
        clientID = WireUUID(value.clientID)
        hostID = WireUUID(value.hostID)
        deviceID = WireUUID(value.deviceID)
        hostFingerprint = try WireFingerprint(value.hostFingerprint)
        endpoints = value.endpoints
        deviceState = value.deviceState
        authorizationEpoch = value.authorizationEpoch
        grantRevision = value.grantRevision
        policyRevision = value.policyRevision
        sessionKey = try StoredClientKeyV0(value.sessionKey)
        approvalKey = try StoredClientKeyV0(value.approvalKey)
    }

    init(from decoder: Decoder) throws {
        try requireStoredKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
        pairingID = try container.decode(WireUUID.self, forKey: .pairingID)
        clientID = try container.decode(WireUUID.self, forKey: .clientID)
        hostID = try container.decode(WireUUID.self, forKey: .hostID)
        deviceID = try container.decode(WireUUID.self, forKey: .deviceID)
        hostFingerprint = try container.decode(WireFingerprint.self, forKey: .hostFingerprint)
        endpoints = try container.decode([EndpointCandidate].self, forKey: .endpoints)
        deviceState = try container.decode(DeviceAuthorizationState.self, forKey: .deviceState)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        grantRevision = try container.decode(GrantRevision.self, forKey: .grantRevision)
        policyRevision = try container.decode(PolicyRevision.self, forKey: .policyRevision)
        sessionKey = try container.decode(StoredClientKeyV0.self, forKey: .sessionKey)
        approvalKey = try container.decode(StoredClientKeyV0.self, forKey: .approvalKey)
        _ = try domainValue()
    }

    func domainValue() throws -> ClientDurablePairedHostV0 {
        guard schemaVersion == 1 else {
            throw ClientPairedHostStorageErrorV0.invalidRecord
        }
        let prepared = try ClientPreparedIdentityV0(
            pairingID: pairingID.rawValue,
            clientID: clientID.rawValue,
            sessionKey: sessionKey.domainValue(),
            approvalKey: approvalKey.domainValue()
        )
        let host = ClientPairedHostV0(
            pairingID: pairingID.rawValue,
            clientID: clientID.rawValue,
            hostID: hostID.rawValue,
            deviceID: deviceID.rawValue,
            hostFingerprint: hostFingerprint.rawValue,
            endpoints: endpoints,
            deviceState: deviceState,
            authorizationEpoch: authorizationEpoch,
            grantRevision: grantRevision,
            policyRevision: policyRevision
        )
        return try ClientDurablePairedHostV0(host: host, identity: prepared)
    }
}

public enum ClientPairedHostStorageCodecV0 {
    public static func encode(_ value: ClientDurablePairedHostV0) throws -> Data {
        try encodeStored(StoredPairedHostV0(value))
    }

    public static func decode(_ data: Data) throws -> ClientDurablePairedHostV0 {
        do {
            try StrictJSON.validate(data)
            let stored = try JSONDecoder().decode(StoredPairedHostV0.self, from: data)
            guard try encodeStored(stored) == data else {
                throw ClientPairedHostStorageErrorV0.nonCanonicalEncoding
            }
            return try stored.domainValue()
        } catch let error as ClientPairedHostStorageErrorV0 {
            throw error
        } catch {
            throw ClientPairedHostStorageErrorV0.invalidRecord
        }
    }

    private static func encodeStored(_ value: StoredPairedHostV0) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

public protocol ClientIdentityRecoveryCustodyV0: ClientIdentityKeyCustodyV0 {
    /// Prepared identities are non-secret public metadata plus opaque refs.
    func preparedIdentities() async throws -> [ClientPreparedIdentityV0]

    /// Idempotently removes only the unpublished marker, preserving both keys.
    func markPreparedIdentityPublished(
        _ identity: ClientPreparedIdentityV0
    ) async throws
}

public protocol ClientPairedHostRecoveryPersistenceV0: Sendable {
    func storedRecord(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientDurablePairedHostV0?
}

public struct ClientIdentityRecoveryResultV0: Equatable, Sendable {
    public let adoptedPublishedCount: Int
    public let discardedOrphanCount: Int
}

/// Preflights the full inventory before changing custody, so a conflicting
/// committed record preserves all evidence and fails closed. Adoption and
/// orphan deletion operations must be idempotent for crash-loop convergence.
public enum ClientIdentityRestartReconcilerV0 {
    public static func reconcile(
        custody: any ClientIdentityRecoveryCustodyV0,
        persistence: any ClientPairedHostRecoveryPersistenceV0
    ) async throws -> ClientIdentityRecoveryResultV0 {
        let prepared = try await custody.preparedIdentities()
        var adopt: [ClientPreparedIdentityV0] = []
        var discard: [ClientPreparedIdentityV0] = []

        for identity in prepared {
            if let stored = try await persistence.storedRecord(
                pairingID: identity.pairingID,
                clientID: identity.clientID
            ) {
                guard stored.pairingID == identity.pairingID,
                      stored.clientID == identity.clientID,
                      stored.sessionKey == identity.sessionKey,
                      stored.approvalKey == identity.approvalKey else {
                    throw ClientPairedHostStorageErrorV0.recoveryConflict
                }
                guard try await custody.validatePreparedIdentity(identity) else {
                    throw ClientPairedHostStorageErrorV0.keyUnavailable
                }
                adopt.append(identity)
            } else {
                discard.append(identity)
            }
        }

        for identity in adopt {
            try await custody.markPreparedIdentityPublished(identity)
        }
        for identity in discard {
            try await custody.discardPreparedIdentity(identity)
        }
        return ClientIdentityRecoveryResultV0(
            adoptedPublishedCount: adopt.count,
            discardedOrphanCount: discard.count
        )
    }
}
