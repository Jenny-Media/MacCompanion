import CompanionSecurity
import Foundation

public enum InteractiveCredentialState: String, Equatable, Sendable {
    case pending
    case challenged
    case consumed
    case rejected
    case expired
    case invalidated
}

public enum InteractiveSecurityAuthorityError: Error, Equatable, Sendable {
    case invalidLifetime
    case notPending
    case notChallenged
    case expired
    case currentStateChanged
    case invalidProof
}

public struct InteractiveApprovalCurrentState: Equatable, Sendable {
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let authorizationEpoch: UInt64
    public let grantRevision: UInt64
    public let policyRevision: UInt64
    public let approvalPublicKeyX963: Data

    public init(
        clientID: UUID,
        primaryConnectionID: Data,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        approvalPublicKeyX963: Data
    ) {
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.approvalPublicKeyX963 = approvalPublicKeyX963
    }
}

public struct InteractiveApprovedSessionIntent: Equatable, Sendable {
    public let hostID: UUID
    public let hostFingerprint: Data
    public let requestID: UUID
    public let approvalID: UUID
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let authorizationEpoch: UInt64
    public let selectedDisplayID: UUID
    public let initialSurface: InteractiveInitialSurfaceCode
    public let effects: InteractiveApprovalEffects
    public let selectedMajor: UInt16
    public let selectedMinor: UInt16
    public let approvalDeadlineMonotonicMilliseconds: UInt64
}

public struct InteractiveApprovalAuthority: Equatable, Sendable {
    public private(set) var state: InteractiveCredentialState = .pending

    private let hostID: UUID
    private let hostFingerprint: Data
    private let clientID: UUID
    private let primaryConnectionID: Data
    private let requestID: UUID
    private let approvalID: UUID
    private let serverChallenge: Data
    private let authorizationEpoch: UInt64
    private let grantRevision: UInt64
    private let policyRevision: UInt64
    private let selectedDisplayID: UUID
    private let initialSurface: InteractiveInitialSurfaceCode
    private let effects: InteractiveApprovalEffects
    private let issuedAtUnixMilliseconds: UInt64
    private let expiresAtUnixMilliseconds: UInt64
    private let selectedMajor: UInt16
    private let selectedMinor: UInt16
    private let approvalPublicKeyX963: Data
    private let issuedAtMonotonicMilliseconds: UInt64
    private let expiresAtMonotonicMilliseconds: UInt64

    public init(
        hostID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        requestID: UUID,
        approvalID: UUID,
        serverChallenge: Data,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        selectedDisplayID: UUID,
        initialSurface: InteractiveInitialSurfaceCode,
        effects: InteractiveApprovalEffects,
        issuedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64,
        selectedMajor: UInt16 = 0,
        selectedMinor: UInt16 = 1,
        approvalPublicKeyX963: Data,
        issuedAtMonotonicMilliseconds: UInt64,
        expiresAtMonotonicMilliseconds: UInt64
    ) throws {
        guard issuedAtMonotonicMilliseconds <= UInt64(Int64.max),
              expiresAtMonotonicMilliseconds <= UInt64(Int64.max),
              expiresAtMonotonicMilliseconds > issuedAtMonotonicMilliseconds,
              expiresAtMonotonicMilliseconds - issuedAtMonotonicMilliseconds <= 60_000 else {
            throw InteractiveSecurityAuthorityError.invalidLifetime
        }
        try CompanionSecurityV0.validateSigningPublicKey(approvalPublicKeyX963)
        _ = try CompanionSecurityV0.interactiveApprovalSigningInput(
            hostID: hostID,
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            requestID: requestID,
            approvalID: approvalID,
            serverChallenge: serverChallenge,
            authorizationEpoch: authorizationEpoch,
            grantRevision: grantRevision,
            policyRevision: policyRevision,
            selectedDisplayID: selectedDisplayID,
            initialSurface: initialSurface,
            effects: effects,
            issuedAtUnixMilliseconds: issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.requestID = requestID
        self.approvalID = approvalID
        self.serverChallenge = serverChallenge
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.selectedDisplayID = selectedDisplayID
        self.initialSurface = initialSurface
        self.effects = effects
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.selectedMajor = selectedMajor
        self.selectedMinor = selectedMinor
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.issuedAtMonotonicMilliseconds = issuedAtMonotonicMilliseconds
        self.expiresAtMonotonicMilliseconds = expiresAtMonotonicMilliseconds
    }

    public mutating func verifyAndConsume(
        rawSignature: Data,
        current: InteractiveApprovalCurrentState,
        monotonicNowMilliseconds: UInt64
    ) throws -> InteractiveApprovedSessionIntent {
        guard state == .pending else { throw InteractiveSecurityAuthorityError.notPending }
        guard monotonicNowMilliseconds >= issuedAtMonotonicMilliseconds,
              monotonicNowMilliseconds < expiresAtMonotonicMilliseconds else {
            state = .expired
            throw InteractiveSecurityAuthorityError.expired
        }
        guard current.clientID == clientID,
              current.primaryConnectionID == primaryConnectionID,
              current.authorizationEpoch == authorizationEpoch,
              current.grantRevision == grantRevision,
              current.policyRevision == policyRevision,
              current.approvalPublicKeyX963 == approvalPublicKeyX963 else {
            state = .invalidated
            throw InteractiveSecurityAuthorityError.currentStateChanged
        }
        let signingInput = try CompanionSecurityV0.interactiveApprovalSigningInput(
            hostID: hostID,
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            requestID: requestID,
            approvalID: approvalID,
            serverChallenge: serverChallenge,
            authorizationEpoch: authorizationEpoch,
            grantRevision: grantRevision,
            policyRevision: policyRevision,
            selectedDisplayID: selectedDisplayID,
            initialSurface: initialSurface,
            effects: effects,
            issuedAtUnixMilliseconds: issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        let valid: Bool
        do {
            valid = try CompanionSecurityV0.verifySignature(
                rawSignature: rawSignature,
                signingInput: signingInput,
                publicKeyX963: approvalPublicKeyX963
            )
        } catch {
            state = .rejected
            throw error
        }
        guard valid else {
            state = .rejected
            throw InteractiveSecurityAuthorityError.invalidProof
        }
        state = .consumed
        return InteractiveApprovedSessionIntent(
            hostID: hostID,
            hostFingerprint: hostFingerprint,
            requestID: requestID,
            approvalID: approvalID,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            authorizationEpoch: authorizationEpoch,
            selectedDisplayID: selectedDisplayID,
            initialSurface: initialSurface,
            effects: effects,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor,
            approvalDeadlineMonotonicMilliseconds: expiresAtMonotonicMilliseconds
        )
    }

    public mutating func invalidate() {
        if state == .pending { state = .invalidated }
    }
}

public struct InteractiveChannelCurrentState: Equatable, Sendable {
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let interactiveSessionID: UUID
    public let authorizationEpoch: UInt64

    public init(
        clientID: UUID,
        primaryConnectionID: Data,
        interactiveSessionID: UUID,
        authorizationEpoch: UInt64
    ) {
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
    }
}

public struct InteractiveChannelChallenge: Equatable, Sendable {
    public let channelID: UUID
    public let role: InteractiveChannelRole
    public let hostNonce: Data
}

public struct InteractiveChannelAcceptance: Equatable, Sendable {
    public let channelID: UUID
    public let role: InteractiveChannelRole
    public let serverProof: Data
}

public struct InteractiveChannelCredentialAuthority: Equatable, Sendable {
    public private(set) var state: InteractiveCredentialState = .pending

    private let channelID: UUID
    private let role: InteractiveChannelRole
    private let hostID: UUID
    private let hostFingerprint: Data
    private let clientID: UUID
    private let primaryConnectionID: Data
    private let interactiveSessionID: UUID
    private let authorizationEpoch: UInt64
    private let selectedMajor: UInt16
    private let selectedMinor: UInt16
    private let issuedAtMonotonicMilliseconds: UInt64
    private let expiresAtMonotonicMilliseconds: UInt64
    private var credential: Data?
    private var transcriptDigest: Data?

    public init(
        channelID: UUID,
        role: InteractiveChannelRole,
        credential: Data,
        hostID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        interactiveSessionID: UUID,
        authorizationEpoch: UInt64,
        selectedMajor: UInt16 = 0,
        selectedMinor: UInt16 = 1,
        issuedAtMonotonicMilliseconds: UInt64,
        expiresAtMonotonicMilliseconds: UInt64
    ) throws {
        guard credential.count == 32,
              expiresAtMonotonicMilliseconds > issuedAtMonotonicMilliseconds,
              expiresAtMonotonicMilliseconds - issuedAtMonotonicMilliseconds <= 30_000 else {
            throw InteractiveSecurityAuthorityError.invalidLifetime
        }
        _ = try CompanionSecurityV0.interactiveChannelTranscriptInput(
            channelID: channelID,
            role: role,
            hostID: hostID,
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            clientNonce: Data(repeating: 0, count: 32),
            hostNonce: Data(repeating: 0, count: 32),
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        self.channelID = channelID
        self.role = role
        self.credential = credential
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedMajor = selectedMajor
        self.selectedMinor = selectedMinor
        self.issuedAtMonotonicMilliseconds = issuedAtMonotonicMilliseconds
        self.expiresAtMonotonicMilliseconds = expiresAtMonotonicMilliseconds
    }

    public mutating func beginChallenge(
        clientNonce: Data,
        hostNonce: Data,
        current: InteractiveChannelCurrentState,
        monotonicNowMilliseconds: UInt64
    ) throws -> InteractiveChannelChallenge {
        guard state == .pending else { throw InteractiveSecurityAuthorityError.notPending }
        try validateCurrent(current, now: monotonicNowMilliseconds)
        let input = try CompanionSecurityV0.interactiveChannelTranscriptInput(
            channelID: channelID,
            role: role,
            hostID: hostID,
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            clientNonce: clientNonce,
            hostNonce: hostNonce,
            selectedMajor: selectedMajor,
            selectedMinor: selectedMinor
        )
        transcriptDigest = CompanionSecurityV0.interactiveChannelTranscriptDigest(input)
        state = .challenged
        return InteractiveChannelChallenge(channelID: channelID, role: role, hostNonce: hostNonce)
    }

    public mutating func verifyAndConsume(
        clientProof: Data,
        current: InteractiveChannelCurrentState,
        monotonicNowMilliseconds: UInt64
    ) throws -> InteractiveChannelAcceptance {
        guard state == .challenged, let digest = transcriptDigest,
              let credential else {
            throw InteractiveSecurityAuthorityError.notChallenged
        }
        try validateCurrent(current, now: monotonicNowMilliseconds)
        let valid: Bool
        do {
            valid = try CompanionSecurityV0.verifyInteractiveChannelClientProof(
                clientProof,
                credential: credential,
                transcriptDigest: digest
            )
        } catch {
            terminal(.rejected)
            throw error
        }
        guard valid else {
            terminal(.rejected)
            throw InteractiveSecurityAuthorityError.invalidProof
        }
        let serverProof = try CompanionSecurityV0.interactiveChannelServerProof(
            credential: credential,
            transcriptDigest: digest
        )
        terminal(.consumed)
        return InteractiveChannelAcceptance(
            channelID: channelID,
            role: role,
            serverProof: serverProof
        )
    }

    public mutating func invalidate() {
        if state == .pending || state == .challenged { terminal(.invalidated) }
    }

    private mutating func validateCurrent(
        _ current: InteractiveChannelCurrentState,
        now: UInt64
    ) throws {
        guard now >= issuedAtMonotonicMilliseconds, now < expiresAtMonotonicMilliseconds else {
            terminal(.expired)
            throw InteractiveSecurityAuthorityError.expired
        }
        guard current.clientID == clientID,
              current.primaryConnectionID == primaryConnectionID,
              current.interactiveSessionID == interactiveSessionID,
              current.authorizationEpoch == authorizationEpoch else {
            terminal(.invalidated)
            throw InteractiveSecurityAuthorityError.currentStateChanged
        }
    }

    private mutating func terminal(_ next: InteractiveCredentialState) {
        credential = nil
        transcriptDigest = nil
        state = next
    }
}
