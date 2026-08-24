import CompanionDomain
import CompanionPersistence
import CompanionSecurity
import Foundation

public enum AgentPairingRecoveryErrorV0: Error, Equatable, Sendable {
    case unavailable
    case invalidProof
}

public struct AgentPairingRecoveryChallengeV0: Equatable, Sendable {
    public let hostNonce: Data
    public let selectedMajor: UInt16
    public let selectedMinor: UInt16

    public init(
        hostNonce: Data,
        selectedMajor: UInt16 = 0,
        selectedMinor: UInt16 = 1
    ) throws {
        guard hostNonce.count == 32,
              selectedMajor == 0,
              selectedMinor == 1 else {
            throw AgentPairingRecoveryErrorV0.unavailable
        }
        self.hostNonce = hostNonce
        self.selectedMajor = selectedMajor
        self.selectedMinor = selectedMinor
    }
}

public struct AgentRecoveredPairingV0: Equatable, Sendable {
    public let deviceID: UUID
    public let policyRevision: PolicyRevision

    public init(deviceID: UUID, policyRevision: PolicyRevision) {
        self.deviceID = deviceID
        self.policyRevision = policyRevision
    }
}

public protocol AgentHostPairingRecoveryAuthorityV0: Sendable {
    func beginPairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data
    ) async throws -> AgentPairingRecoveryChallengeV0

    func provePairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        hostNonce: Data,
        hostFingerprint: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16,
        signature: Data
    ) async throws -> AgentRecoveredPairingV0
}

public struct UnavailableAgentHostPairingRecoveryAuthorityV0:
    AgentHostPairingRecoveryAuthorityV0, Sendable
{
    public init() {}

    public func beginPairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data
    ) async throws -> AgentPairingRecoveryChallengeV0 {
        throw AgentPairingRecoveryErrorV0.unavailable
    }

    public func provePairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        hostNonce: Data,
        hostFingerprint: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16,
        signature: Data
    ) async throws -> AgentRecoveredPairingV0 {
        throw AgentPairingRecoveryErrorV0.unavailable
    }
}

/// Durable exact-key recovery authority. It can only reproduce an already
/// committed Monitor Only pairing and has no mutation or local-approval API.
public struct SQLiteAgentHostPairingRecoveryAuthorityV0:
    AgentHostPairingRecoveryAuthorityV0, Sendable
{
    private let store: SQLiteSecurityStore
    private let makeHostNonce: @Sendable () -> Data

    public init(
        store: SQLiteSecurityStore,
        makeHostNonce: @escaping @Sendable () -> Data = {
            var generator = SystemRandomNumberGenerator()
            return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        }
    ) {
        self.store = store
        self.makeHostNonce = makeHostNonce
    }

    public func beginPairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data
    ) async throws -> AgentPairingRecoveryChallengeV0 {
        _ = try await exactRecord(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKeyX963,
            approvalPublicKeyX963: approvalPublicKeyX963
        )
        return try AgentPairingRecoveryChallengeV0(
            hostNonce: makeHostNonce()
        )
    }

    public func provePairingRecovery(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        hostNonce: Data,
        hostFingerprint: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16,
        signature: Data
    ) async throws -> AgentRecoveredPairingV0 {
        let record = try await exactRecord(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKeyX963,
            approvalPublicKeyX963: approvalPublicKeyX963
        )
        let transcript = try CompanionSecurityV0.pairingRecoveryTranscriptInput(
            pairingID: pairingID,
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKeyX963,
            approvalPublicKeyX963: approvalPublicKeyX963,
            clientNonce: clientNonce,
            hostNonce: hostNonce,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        let signingInput = try CompanionSecurityV0.pairingRecoverySignatureInput(
            transcriptDigest: CompanionSecurityV0.pairingRecoveryTranscriptDigest(
                transcript
            )
        )
        guard try CompanionSecurityV0.verifySignature(
            rawSignature: signature,
            signingInput: signingInput,
            publicKeyX963: record.sessionPublicKeyX963
        ) else {
            throw AgentPairingRecoveryErrorV0.invalidProof
        }
        return AgentRecoveredPairingV0(
            deviceID: record.deviceID,
            policyRevision: record.policyRevision
        )
    }

    private func exactRecord(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data
    ) async throws -> StoredDeviceRecord {
        guard let consumedDeviceID = try await store.pairingConsumptionDeviceID(
            pairingID
        ),
        let record = try await store.device(consumedDeviceID),
        record.clientID == clientID,
        record.sessionPublicKeyX963 == sessionPublicKeyX963,
        record.approvalPublicKeyX963 == approvalPublicKeyX963,
        record.authorization.state == .activeMonitorOnly,
        record.authorization.authorizationEpoch.rawValue == 1,
        record.authorization.grantRevision.rawValue == 1,
        record.revokedAtUnixMilliseconds == nil else {
            throw AgentPairingRecoveryErrorV0.unavailable
        }
        return record
    }
}
