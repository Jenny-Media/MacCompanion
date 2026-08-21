import CompanionSecurity
import Foundation

public enum OperationApprovalStateV0: String, Equatable, Sendable {
    case pending
    case consumed
    case rejected
    case expired
    case invalidated
}

public enum OperationApprovalErrorV0: Error, Equatable, Sendable {
    case invalidLifetime
    case notPending
    case expired
    case currentStateChanged
    case invalidProof
}

public struct OperationApprovalChallengeV0: Equatable, Sendable {
    public let approvalID: UUID
    public let operationDigest: Data
    public let serverChallenge: Data
    public let issuedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64
}

public struct OperationApprovalCurrentStateV0: Equatable, Sendable {
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let authorizationEpoch: UInt64
    public let grantRevision: UInt64
    public let policyRevision: UInt64
    public let providerGeneration: UUID
    public let executionRevision: UUID
    public let approvalPublicKeyX963: Data

    public init(
        clientID: UUID,
        primaryConnectionID: Data,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        providerGeneration: UUID,
        executionRevision: UUID,
        approvalPublicKeyX963: Data
    ) {
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
        self.approvalPublicKeyX963 = approvalPublicKeyX963
    }
}

public struct ApprovedOperationIntentV0: Equatable, Sendable {
    public let approvalID: UUID
    public let operationDigest: Data
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let authorizationEpoch: UInt64
    public let grantRevision: UInt64
    public let policyRevision: UInt64
    public let providerGeneration: UUID
    public let executionRevision: UUID
    public let deadlineMonotonicMilliseconds: UInt64
}

public struct OperationApprovalAuthorityV0: Equatable, Sendable {
    public private(set) var state: OperationApprovalStateV0 = .pending
    public let challenge: OperationApprovalChallengeV0

    private let hostFingerprint: Data
    private let clientID: UUID
    private let primaryConnectionID: Data
    private let authorizationEpoch: UInt64
    private let grantRevision: UInt64
    private let policyRevision: UInt64
    private let providerGeneration: UUID
    private let executionRevision: UUID
    private let selectedMajor: UInt16
    private let selectedMinor: UInt16
    private let approvalPublicKeyX963: Data
    private let issuedAtMonotonicMilliseconds: UInt64
    private let expiresAtMonotonicMilliseconds: UInt64

    public init(
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        approvalID: UUID,
        operationDigest: Data,
        serverChallenge: Data,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        providerGeneration: UUID,
        executionRevision: UUID,
        issuedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64,
        selectedMajor: UInt16 = 0,
        selectedMinor: UInt16 = 1,
        approvalPublicKeyX963: Data,
        issuedAtMonotonicMilliseconds: UInt64,
        expiresAtMonotonicMilliseconds: UInt64
    ) throws {
        guard expiresAtMonotonicMilliseconds > issuedAtMonotonicMilliseconds,
              expiresAtMonotonicMilliseconds - issuedAtMonotonicMilliseconds
                <= 60_000 else {
            throw OperationApprovalErrorV0.invalidLifetime
        }
        try CompanionSecurityV0.validateSigningPublicKey(approvalPublicKeyX963)
        _ = try CompanionSecurityV0.operationApprovalSigningInput(
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            approvalID: approvalID,
            operationDigest: operationDigest,
            serverChallenge: serverChallenge,
            issuedAtUnixMilliseconds: issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        challenge = OperationApprovalChallengeV0(
            approvalID: approvalID,
            operationDigest: operationDigest,
            serverChallenge: serverChallenge,
            issuedAtUnixMilliseconds: issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds
        )
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
        self.selectedMajor = selectedMajor
        self.selectedMinor = selectedMinor
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.issuedAtMonotonicMilliseconds = issuedAtMonotonicMilliseconds
        self.expiresAtMonotonicMilliseconds = expiresAtMonotonicMilliseconds
    }

    public mutating func verifyAndConsume(
        rawSignature: Data,
        current: OperationApprovalCurrentStateV0,
        monotonicNowMilliseconds: UInt64
    ) throws -> ApprovedOperationIntentV0 {
        guard state == .pending else { throw OperationApprovalErrorV0.notPending }
        guard monotonicNowMilliseconds >= issuedAtMonotonicMilliseconds,
              monotonicNowMilliseconds < expiresAtMonotonicMilliseconds else {
            state = .expired
            throw OperationApprovalErrorV0.expired
        }
        guard current.clientID == clientID,
              current.primaryConnectionID == primaryConnectionID,
              current.authorizationEpoch == authorizationEpoch,
              current.grantRevision == grantRevision,
              current.policyRevision == policyRevision,
              current.providerGeneration == providerGeneration,
              current.executionRevision == executionRevision,
              current.approvalPublicKeyX963 == approvalPublicKeyX963 else {
            state = .invalidated
            throw OperationApprovalErrorV0.currentStateChanged
        }
        let input = try CompanionSecurityV0.operationApprovalSigningInput(
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            approvalID: challenge.approvalID,
            operationDigest: challenge.operationDigest,
            serverChallenge: challenge.serverChallenge,
            issuedAtUnixMilliseconds: challenge.issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: challenge.expiresAtUnixMilliseconds,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        let valid: Bool
        do {
            valid = try CompanionSecurityV0.verifySignature(
                rawSignature: rawSignature,
                signingInput: input,
                publicKeyX963: approvalPublicKeyX963
            )
        } catch {
            state = .rejected
            throw error
        }
        guard valid else {
            state = .rejected
            throw OperationApprovalErrorV0.invalidProof
        }
        state = .consumed
        return ApprovedOperationIntentV0(
            approvalID: challenge.approvalID,
            operationDigest: challenge.operationDigest,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            authorizationEpoch: authorizationEpoch,
            grantRevision: grantRevision,
            policyRevision: policyRevision,
            providerGeneration: providerGeneration,
            executionRevision: executionRevision,
            deadlineMonotonicMilliseconds: expiresAtMonotonicMilliseconds
        )
    }

    public mutating func invalidate() {
        if state == .pending { state = .invalidated }
    }
}
