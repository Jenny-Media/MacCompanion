import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CompanionTransport
import CompanionWire
import Foundation

public enum ClientPairingRecoveryPhaseV0: String, Equatable, Sendable {
    case awaitingTCP
    case awaitingPinnedTLS
    case readyToResume
    case awaitingChallenge
    case awaitingCompletion
    case paired
    case closed
}

public enum ClientPairingRecoveryErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case invalidPhase(ClientPairingRecoveryPhaseV0)
    case unexpectedMessage(WireMessageKind)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case hostFingerprintMismatch
    case invalidSignatureLength
    case remoteError(code: String, retry: ProtocolErrorRetry)
}

/// Owns one exact-key recovery connection after initial pairing may have
/// committed on the Mac. It has no QR secret and cannot request local approval.
public actor ClientPairingRecoverySessionV0 {
    public static let maximumLifetimeMilliseconds: UInt64 = 60_000

    public let pairingID: UUID
    public let clientID: UUID
    public let hostFingerprint: Data
    public let endpoints: [EndpointCandidate]
    public private(set) var phase: ClientPairingRecoveryPhaseV0 = .awaitingTCP
    public private(set) var pairedHost: ClientPairedHostV0?

    private let identity: ClientPreparedIdentityV0
    private let signer: any ClientPairingSessionSigningV0
    private var transport: PinnedTLSConnectionAuthority
    private var replay = ConnectionReplayWindow()
    private var lastMonotonicMilliseconds: UInt64?
    private var deadlineMonotonicMilliseconds: UInt64?
    private var clientNonce: Data?
    private var resumeMessageID: WireUUID?
    private var proveMessageID: WireUUID?
    private var signingInFlight = false

    public init(
        identity: ClientPreparedIdentityV0,
        hostFingerprint: Data,
        endpoints: [EndpointCandidate],
        signer: any ClientPairingSessionSigningV0
    ) throws {
        guard hostFingerprint.count == 32,
              (1...8).contains(endpoints.count),
              Set(endpoints).count == endpoints.count else {
            throw ClientPairingRecoveryErrorV0.invalidConfiguration
        }
        self.identity = identity
        pairingID = identity.pairingID
        clientID = identity.clientID
        self.hostFingerprint = hostFingerprint
        self.endpoints = endpoints
        self.signer = signer
        transport = try PinnedTLSConnectionAuthority(
            role: .pairingPrimary,
            requiredHostFingerprint: hostFingerprint
        )
    }

    public func didConnectTCP(monotonicNowMilliseconds: UInt64) throws {
        do {
            try requirePhase(.awaitingTCP)
            try observe(monotonicNowMilliseconds)
            let (deadline, overflow) = monotonicNowMilliseconds
                .addingReportingOverflow(Self.maximumLifetimeMilliseconds)
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientPairingRecoveryErrorV0.invalidClock
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
            phase = .readyToResume
        } catch {
            terminate()
            throw error
        }
    }

    public func resume(
        clientNonce: WireBytes32,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data {
        do {
            try requirePhase(.readyToResume)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.pairingHandshake)
            try admitReplay(messageID)
            let request = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: PairingResumeBody(
                    pairingID: WireUUID(pairingID),
                    clientID: WireUUID(clientID),
                    sessionPublicKey: try WireBytes65(
                        identity.sessionKey.publicKeyX963
                    ),
                    approvalPublicKey: try WireBytes65(
                        identity.approvalKey.publicKeyX963
                    ),
                    clientNonce: clientNonce
                )
            )
            self.clientNonce = clientNonce.rawValue
            resumeMessageID = messageID
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
            guard !signingInFlight else {
                throw ClientPairingRecoveryErrorV0.invalidPhase(phase)
            }
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(
                    responseJSON,
                    expectedCorrelation: resumeMessageID
                )
            }
            guard kind == .pairingResumeChallenge else {
                throw ClientPairingRecoveryErrorV0.unexpectedMessage(kind)
            }
            let challenge = try WireCodec.decode(
                WireEnvelope<PairingResumeChallengeBody>.self,
                from: responseJSON
            )
            guard challenge.correlationID == resumeMessageID,
                  let clientNonce else {
                throw ClientPairingRecoveryErrorV0.invalidCorrelation
            }
            try admitReplay(challenge.messageID)
            try admitReplay(proofMessageID)
            guard challenge.body.hostFingerprint.rawValue == hostFingerprint else {
                throw ClientPairingRecoveryErrorV0.hostFingerprintMismatch
            }
            let transcript = try CompanionSecurityV0.pairingRecoveryTranscriptInput(
                pairingID: pairingID,
                hostFingerprint: hostFingerprint,
                clientID: clientID,
                sessionPublicKeyX963: identity.sessionKey.publicKeyX963,
                approvalPublicKeyX963: identity.approvalKey.publicKeyX963,
                clientNonce: clientNonce,
                hostNonce: challenge.body.hostNonce.rawValue,
                selectedMajor: challenge.body.selectedVersion.major,
                selectedMinor: challenge.body.selectedVersion.minor
            )
            let signingInput = try CompanionSecurityV0.pairingRecoverySignatureInput(
                transcriptDigest: CompanionSecurityV0.pairingRecoveryTranscriptDigest(
                    transcript
                )
            )
            signingInFlight = true
            let signature: Data
            do {
                signature = try await signer.signPairingInput(signingInput)
            } catch {
                signingInFlight = false
                throw error
            }
            signingInFlight = false
            guard signature.count == 64 else {
                throw ClientPairingRecoveryErrorV0.invalidSignatureLength
            }
            self.proveMessageID = proofMessageID
            phase = .awaitingCompletion
            return try WireCodec.encode(WireEnvelope(
                messageID: proofMessageID,
                correlationID: challenge.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: PairingResumeProveBody(
                    signature: try WireBytes64(signature)
                )
            ))
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveCompletion(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws -> ClientPairedHostV0 {
        do {
            try requirePhase(.awaitingCompletion)
            try observeAndEnforceDeadline(monotonicNowMilliseconds)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(
                    responseJSON,
                    expectedCorrelation: proveMessageID
                )
            }
            guard kind == .pairingComplete else {
                throw ClientPairingRecoveryErrorV0.unexpectedMessage(kind)
            }
            let completion = try WireCodec.decode(
                WireEnvelope<PairingCompleteBody>.self,
                from: responseJSON
            )
            guard completion.correlationID == proveMessageID else {
                throw ClientPairingRecoveryErrorV0.invalidCorrelation
            }
            try admitReplay(completion.messageID)
            guard completion.body.hostFingerprint.rawValue == hostFingerprint else {
                throw ClientPairingRecoveryErrorV0.hostFingerprintMismatch
            }
            let host = ClientPairedHostV0(
                pairingID: pairingID,
                clientID: clientID,
                hostID: completion.body.hostID.rawValue,
                deviceID: completion.body.deviceID.rawValue,
                hostFingerprint: hostFingerprint,
                endpoints: endpoints,
                deviceState: completion.body.deviceState,
                authorizationEpoch: completion.body.authorizationEpoch,
                grantRevision: completion.body.grantRevision,
                policyRevision: completion.body.policyRevision
            )
            pairedHost = host
            phase = .paired
            return host
        } catch {
            terminate()
            throw error
        }
    }

    public func cancel() {
        terminate()
    }

    public func nextDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingTCP, .paired, .closed:
            nil
        case .awaitingPinnedTLS, .readyToResume, .awaitingChallenge,
             .awaitingCompletion:
            deadlineMonotonicMilliseconds
        }
    }

    private func observe(_ now: UInt64) throws {
        guard now <= UInt64(Int64.max),
              lastMonotonicMilliseconds.map({ now >= $0 }) ?? true else {
            throw ClientPairingRecoveryErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = now
    }

    private func observeAndEnforceDeadline(_ now: UInt64) throws {
        try observe(now)
        guard let deadlineMonotonicMilliseconds,
              now < deadlineMonotonicMilliseconds else {
            throw ClientPairingRecoveryErrorV0.invalidClock
        }
    }

    private func requirePhase(_ expected: ClientPairingRecoveryPhaseV0) throws {
        guard phase == expected else {
            throw ClientPairingRecoveryErrorV0.invalidPhase(phase)
        }
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientPairingRecoveryErrorV0.duplicateMessage(messageID)
        } catch {
            throw ClientPairingRecoveryErrorV0.invalidConfiguration
        }
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
            throw ClientPairingRecoveryErrorV0.invalidCorrelation
        }
        throw ClientPairingRecoveryErrorV0.remoteError(
            code: response.body.code,
            retry: response.body.retry
        )
    }

    private func terminate() {
        transport.close()
        phase = .closed
        clientNonce = nil
        resumeMessageID = nil
        proveMessageID = nil
        signingInFlight = false
    }
}
