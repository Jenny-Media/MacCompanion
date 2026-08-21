import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionTransport
import CompanionWire
import Foundation

public protocol ClientPairingSessionSigningV0: Sendable {
    /// Returns the fixed-width 64-byte P-256 `r || s` signature. The signer
    /// retains private-key custody and receives only the normative input.
    func signPairingInput(_ input: Data) async throws -> Data
}

public enum ClientPairingSessionPhaseV0: String, Equatable, Sendable {
    case awaitingTCP
    case awaitingPinnedTLS
    case readyToBegin
    case awaitingChallenge
    case awaitingPendingApproval
    case awaitingCompletion
    case paired
    case closed
}

public enum ClientPairingSessionErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case expired
    case invalidPhase(ClientPairingSessionPhaseV0)
    case unexpectedMessage(WireMessageKind)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case hostFingerprintMismatch
    case transcriptMismatch
    case authenticationStringMismatch
    case expiryMismatch
    case invalidSignatureLength
    case remoteError(code: String, retry: ProtocolErrorRetry)
}

public struct ClientPairingApprovalV0: Equatable, Sendable {
    public let pairingID: UUID
    public let transcriptDigest: Data
    public let authenticationString: String
    public let expiresAtUnixMilliseconds: Int64
}

public struct ClientPairedHostV0: Equatable, Sendable {
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
}

/// Client-side owner for one QR-pinned pairing connection. The QR secret and
/// transcript state never leave this authority except as the exact HMAC proof,
/// SAS display facts, or the final paired record.
public actor ClientPairingSessionV0 {
    public static let maximumLifetimeMilliseconds: UInt64 = 5 * 60 * 1_000

    public let pairingID: UUID
    public let clientID: UUID
    public let hostFingerprint: Data
    public let endpoints: [EndpointCandidate]
    public let expiresAtUnixMilliseconds: Int64
    public private(set) var phase: ClientPairingSessionPhaseV0 = .awaitingTCP
    public private(set) var approval: ClientPairingApprovalV0?
    public private(set) var pairedHost: ClientPairedHostV0?

    private let sessionPublicKeyX963: Data
    private let approvalPublicKeyX963: Data
    private let signer: any ClientPairingSessionSigningV0
    private var oneTimeSecret: Data?
    private var transport: PinnedTLSConnectionAuthority
    private var replay = ConnectionReplayWindow()
    private var lastMonotonicMilliseconds: UInt64?
    private var deadlineMonotonicMilliseconds: UInt64?
    private var clientNonce: Data?
    private var beginMessageID: WireUUID?
    private var proofMessageID: WireUUID?
    private var transcriptDigest: Data?
    private var expectedAuthenticationString: String?
    private var proofSigningInFlight = false

    public init(
        qr: PairingQRCodePayload,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        signer: any ClientPairingSessionSigningV0
    ) throws {
        do {
            try qr.validate()
            try CompanionSecurityV0.validateSigningPublicKey(sessionPublicKeyX963)
            try CompanionSecurityV0.validateSigningPublicKey(approvalPublicKeyX963)
        } catch {
            throw ClientPairingSessionErrorV0.invalidConfiguration
        }
        pairingID = qr.pairingID.rawValue
        self.clientID = clientID
        hostFingerprint = qr.hostFingerprint.rawValue
        endpoints = qr.endpoints
        expiresAtUnixMilliseconds = qr.expiresAtUnixMilliseconds
        oneTimeSecret = qr.oneTimeSecret.rawValue
        self.sessionPublicKeyX963 = sessionPublicKeyX963
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.signer = signer
        transport = try PinnedTLSConnectionAuthority(
            role: .pairingPrimary,
            requiredHostFingerprint: qr.hostFingerprint.rawValue
        )
    }

    public var pinnedTLSPhase: PinnedTLSConnectionPhase {
        transport.phase
    }

    public func didConnectTCP(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        do {
            try requirePhase(.awaitingTCP)
            try observe(monotonicNowMilliseconds)
            guard wallNowUnixMilliseconds >= 0,
                  wallNowUnixMilliseconds < expiresAtUnixMilliseconds else {
                throw ClientPairingSessionErrorV0.expired
            }
            let wallRemaining = UInt64(
                expiresAtUnixMilliseconds - wallNowUnixMilliseconds
            )
            let lifetime = min(wallRemaining, Self.maximumLifetimeMilliseconds)
            let (deadline, overflow) = monotonicNowMilliseconds
                .addingReportingOverflow(lifetime)
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientPairingSessionErrorV0.invalidClock
            }
            try transport.didConnectTCP()
            deadlineMonotonicMilliseconds = deadline
            phase = .awaitingPinnedTLS
        } catch {
            terminate()
            throw error
        }
    }

    public func acceptPinnedPeer(
        _ evidence: TLSPeerEvidence,
        at monotonicNowMilliseconds: UInt64
    ) throws {
        do {
            try requirePhase(.awaitingPinnedTLS)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.acceptPeer(evidence)
            phase = .readyToBegin
        } catch {
            terminate()
            throw error
        }
    }

    public func begin(
        clientNonce: WireBytes32,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data {
        do {
            try requirePhase(.readyToBegin)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.pairingHandshake)
            try admitReplay(messageID)
            let request = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: PairingBeginBody(
                    pairingID: WireUUID(pairingID),
                    clientID: WireUUID(clientID),
                    sessionPublicKey: try WireBytes65(sessionPublicKeyX963),
                    approvalPublicKey: try WireBytes65(approvalPublicKeyX963),
                    clientNonce: clientNonce
                )
            )
            self.clientNonce = clientNonce.rawValue
            beginMessageID = messageID
            phase = .awaitingChallenge
            return try WireCodec.encode(request)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveChallenge(
        _ responseJSON: Data,
        proofMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) async throws -> Data {
        do {
            try requirePhase(.awaitingChallenge)
            guard !proofSigningInFlight else {
                throw ClientPairingSessionErrorV0.invalidPhase(phase)
            }
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.pairingHandshake)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(responseJSON, expectedCorrelation: beginMessageID)
            }
            guard kind == .pairingChallenge else {
                throw ClientPairingSessionErrorV0.unexpectedMessage(kind)
            }
            let challenge = try WireCodec.decode(
                WireEnvelope<PairingChallengeBody>.self,
                from: responseJSON
            )
            try admitReplay(challenge.messageID)
            guard challenge.correlationID == beginMessageID,
                  let clientNonce,
                  let oneTimeSecret else {
                throw ClientPairingSessionErrorV0.invalidCorrelation
            }
            guard challenge.body.hostFingerprint.rawValue == hostFingerprint else {
                throw ClientPairingSessionErrorV0.hostFingerprintMismatch
            }
            try admitReplay(proofMessageID)
            let transcript = try CompanionSecurityV0.pairingTranscriptInput(
                pairingID: pairingID,
                hostFingerprint: hostFingerprint,
                clientID: clientID,
                sessionPublicKeyX963: sessionPublicKeyX963,
                approvalPublicKeyX963: approvalPublicKeyX963,
                clientNonce: clientNonce,
                hostNonce: challenge.body.hostNonce.rawValue,
                selectedMajor: challenge.body.selectedVersion.major,
                selectedMinor: challenge.body.selectedVersion.minor
            )
            let digest = CompanionSecurityV0.pairingTranscriptDigest(transcript)
            let secretProof = try CompanionSecurityV0.pairingSecretProof(
                oneTimeSecret: oneTimeSecret,
                transcriptDigest: digest
            )
            let signingInput = try CompanionSecurityV0.pairingSignatureInput(
                transcriptDigest: digest
            )
            proofSigningInFlight = true
            let signature: Data
            do {
                signature = try await signer.signPairingInput(signingInput)
            } catch {
                proofSigningInFlight = false
                throw error
            }
            guard proofSigningInFlight, phase == .awaitingChallenge else {
                throw ClientPairingSessionErrorV0.invalidPhase(phase)
            }
            proofSigningInFlight = false
            guard signature.count == 64 else {
                throw ClientPairingSessionErrorV0.invalidSignatureLength
            }
            let prove = try WireEnvelope(
                messageID: proofMessageID,
                correlationID: challenge.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: PairingProveBody(
                    secretProof: try WireBytes32(secretProof),
                    signature: try WireBytes64(signature)
                )
            )
            self.proofMessageID = proofMessageID
            transcriptDigest = digest
            expectedAuthenticationString = try CompanionSecurityV0
                .authenticationString(
                    oneTimeSecret: oneTimeSecret,
                    transcriptDigest: digest
                )
            phase = .awaitingPendingApproval
            return try WireCodec.encode(prove)
        } catch {
            terminate()
            throw error
        }
    }

    @discardableResult
    public func receivePendingApproval(
        _ responseJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> ClientPairingApprovalV0 {
        do {
            try requirePhase(.awaitingPendingApproval)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.pairingHandshake)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(responseJSON, expectedCorrelation: proofMessageID)
            }
            guard kind == .pairingPendingApproval else {
                throw ClientPairingSessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<PairingPendingApprovalBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == proofMessageID else {
                throw ClientPairingSessionErrorV0.invalidCorrelation
            }
            guard response.body.transcriptDigest.rawValue == transcriptDigest else {
                throw ClientPairingSessionErrorV0.transcriptMismatch
            }
            guard response.body.authenticationString.rawValue
                    == expectedAuthenticationString else {
                throw ClientPairingSessionErrorV0.authenticationStringMismatch
            }
            guard response.body.expiresAtUnixMilliseconds
                    == expiresAtUnixMilliseconds else {
                throw ClientPairingSessionErrorV0.expiryMismatch
            }
            guard wallNowUnixMilliseconds >= 0,
                  wallNowUnixMilliseconds < expiresAtUnixMilliseconds else {
                throw ClientPairingSessionErrorV0.expired
            }
            let result = ClientPairingApprovalV0(
                pairingID: pairingID,
                transcriptDigest: response.body.transcriptDigest.rawValue,
                authenticationString: response.body.authenticationString.rawValue,
                expiresAtUnixMilliseconds: response.body.expiresAtUnixMilliseconds
            )
            approval = result
            oneTimeSecret = nil
            clientNonce = nil
            beginMessageID = nil
            phase = .awaitingCompletion
            return result
        } catch {
            terminate()
            throw error
        }
    }

    @discardableResult
    public func receiveCompletion(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws -> ClientPairedHostV0 {
        do {
            try requirePhase(.awaitingCompletion)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.pairingHandshake)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(responseJSON, expectedCorrelation: proofMessageID)
            }
            guard kind == .pairingComplete else {
                throw ClientPairingSessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<PairingCompleteBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == proofMessageID else {
                throw ClientPairingSessionErrorV0.invalidCorrelation
            }
            guard response.body.hostFingerprint.rawValue == hostFingerprint else {
                throw ClientPairingSessionErrorV0.hostFingerprintMismatch
            }
            let result = ClientPairedHostV0(
                pairingID: pairingID,
                clientID: clientID,
                hostID: response.body.hostID.rawValue,
                deviceID: response.body.deviceID.rawValue,
                hostFingerprint: hostFingerprint,
                endpoints: endpoints,
                deviceState: response.body.deviceState,
                authorizationEpoch: response.body.authorizationEpoch,
                grantRevision: response.body.grantRevision,
                policyRevision: response.body.policyRevision
            )
            try transport.roleAuthenticationSucceeded()
            pairedHost = result
            phase = .paired
            clearTransientState()
            return result
        } catch {
            terminate()
            throw error
        }
    }

    public func nextDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingPinnedTLS, .readyToBegin, .awaitingChallenge,
             .awaitingPendingApproval, .awaitingCompletion:
            return deadlineMonotonicMilliseconds
        case .awaitingTCP, .paired, .closed:
            return nil
        }
    }

    @discardableResult
    public func expireIfRequired(at monotonicNowMilliseconds: UInt64) -> Bool {
        guard phase != .paired, phase != .closed else { return false }
        do {
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            return false
        } catch {
            terminate()
            return true
        }
    }

    public func close() {
        terminate()
    }

    private func receiveRemoteError(
        _ responseJSON: Data,
        expectedCorrelation: WireUUID?
    ) throws -> Never {
        let response = try WireCodec.decode(
            WireEnvelope<ProtocolErrorResponseBody>.self,
            from: responseJSON
        )
        try admitReplay(response.messageID)
        guard response.correlationID == expectedCorrelation else {
            throw ClientPairingSessionErrorV0.invalidCorrelation
        }
        throw ClientPairingSessionErrorV0.remoteError(
            code: response.body.code,
            retry: response.body.retry
        )
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientPairingSessionErrorV0.duplicateMessage(messageID)
        }
    }

    private func requirePhase(_ expected: ClientPairingSessionPhaseV0) throws {
        guard phase == expected else {
            throw ClientPairingSessionErrorV0.invalidPhase(phase)
        }
    }

    private func observeAndEnforceDeadline(_ value: UInt64) throws {
        try observe(value)
        guard let deadline = deadlineMonotonicMilliseconds else {
            throw ClientPairingSessionErrorV0.invalidClock
        }
        guard value < deadline else {
            throw ClientPairingSessionErrorV0.expired
        }
    }

    private func observe(_ value: UInt64) throws {
        guard value <= UInt64(Int64.max),
              lastMonotonicMilliseconds.map({ value >= $0 }) ?? true else {
            throw ClientPairingSessionErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = value
    }

    private func terminate() {
        transport.close()
        phase = .closed
        proofSigningInFlight = false
        approval = nil
        pairedHost = nil
        deadlineMonotonicMilliseconds = nil
        clearTransientState()
    }

    private func clearTransientState() {
        oneTimeSecret = nil
        clientNonce = nil
        beginMessageID = nil
        proofMessageID = nil
        transcriptDigest = nil
        expectedAuthenticationString = nil
    }
}
