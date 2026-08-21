import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionTransport
import CompanionWire
import Foundation

public protocol ClientInteractiveApprovalSigningV0: Sendable {
    /// The implementation obtains fresh OS-backed user presence before using
    /// the approval key and returns fixed-width P-256 `r || s` bytes.
    func signAfterUserPresence(_ input: Data) async throws -> Data
}

public struct ClientInteractivePrimaryBindingV0: Equatable, Sendable {
    public let hostID: UUID
    public let hostFingerprint: Data
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision

    public init(
        hostID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision
    ) throws {
        guard hostFingerprint.count == 32,
              primaryConnectionID.count == 16,
              authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1 else {
            throw ClientInteractiveSessionErrorV0.invalidConfiguration
        }
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
    }
}

public enum ClientInteractiveSessionPhaseV0: String, Equatable, Sendable {
    case readyToRequest
    case awaitingApprovalChallenge
    case awaitingAcceptance
    case accepted
    case closed
}

public enum ClientInteractiveSessionErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case invalidPhase(ClientInteractiveSessionPhaseV0)
    case unexpectedMessage(WireMessageKind)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case primaryBindingMismatch
    case requestBindingMismatch
    case invalidSignatureLength
    case approvalDeadlineExceeded
    case acceptedSessionMismatch
    case remoteError(code: String, retry: ProtocolErrorRetry)
}

public struct ClientInteractiveAcceptedSessionV0: Equatable, Sendable {
    public let primary: ClientInteractivePrimaryBindingV0
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let expiresAtUnixMilliseconds: Int64
    public let inputChannel: InteractiveChannelOffer
    public let mediaChannel: InteractiveChannelOffer
}

public actor ClientInteractiveSessionAuthorityV0 {
    public static let maximumApprovalLifetimeMilliseconds: UInt64 = 60_000

    public let primary: ClientInteractivePrimaryBindingV0
    public private(set) var phase: ClientInteractiveSessionPhaseV0 = .readyToRequest
    public private(set) var acceptedSession: ClientInteractiveAcceptedSessionV0?

    private let signer: any ClientInteractiveApprovalSigningV0
    private var replay = ConnectionReplayWindow()
    private var requestMessageID: WireUUID?
    private var approvalProofMessageID: WireUUID?
    private var requestedEffects: [InteractiveControlEffect]?
    private var challengeAuthorizationEpoch: AuthorizationEpoch?
    private var approvalDeadlineMonotonicMilliseconds: UInt64?

    public init(
        primary: ClientInteractivePrimaryBindingV0,
        signer: any ClientInteractiveApprovalSigningV0
    ) {
        self.primary = primary
        self.signer = signer
    }

    public func beginRequest(
        effects: Set<InteractiveControlEffect>,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        do {
            try requirePhase(.readyToRequest)
            try admitReplay(messageID)
            let body = try InteractiveSessionRequestBody(effects: effects)
            let request = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            )
            requestMessageID = messageID
            requestedEffects = body.effects
            phase = .awaitingApprovalChallenge
            return try WireCodec.encode(request)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveApprovalChallenge(
        _ responseJSON: Data,
        approvalProofMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) async throws -> Data {
        do {
            try requirePhase(.awaitingApprovalChallenge)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(
                    responseJSON,
                    expectedCorrelation: requestMessageID
                )
            }
            guard kind == .interactiveSessionApprovalRequired else {
                throw ClientInteractiveSessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveApprovalChallengeBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == requestMessageID,
                  response.body.requestID == requestMessageID else {
                throw ClientInteractiveSessionErrorV0.invalidCorrelation
            }
            guard response.body.hostID.rawValue == primary.hostID,
                  response.body.hostFingerprint.rawValue
                    == primary.hostFingerprint,
                  response.body.clientID.rawValue == primary.clientID,
                  response.body.primaryConnectionID.rawValue
                    == primary.primaryConnectionID,
                  response.body.authorizationEpoch
                    == primary.authorizationEpoch,
                  response.body.grantRevision == primary.grantRevision,
                  response.body.policyRevision == primary.policyRevision else {
                throw ClientInteractiveSessionErrorV0.primaryBindingMismatch
            }
            guard response.body.initialSurface == .desktop,
                  response.body.effects == requestedEffects else {
                throw ClientInteractiveSessionErrorV0.requestBindingMismatch
            }
            try admitReplay(approvalProofMessageID)
            let (deadline, overflow) = monotonicNowMilliseconds
                .addingReportingOverflow(
                    Self.maximumApprovalLifetimeMilliseconds
                )
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientInteractiveSessionErrorV0.invalidClock
            }
            let signature = try await signer.signAfterUserPresence(
                response.body.signingInput(version: response.version)
            )
            guard signature.count == 64 else {
                throw ClientInteractiveSessionErrorV0.invalidSignatureLength
            }
            let proof = try WireEnvelope(
                messageID: approvalProofMessageID,
                correlationID: response.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: InteractiveApprovalProofBody(
                    approvalID: response.body.approvalID,
                    signature: try WireBytes64(signature)
                )
            )
            self.approvalProofMessageID = approvalProofMessageID
            challengeAuthorizationEpoch = response.body.authorizationEpoch
            approvalDeadlineMonotonicMilliseconds = deadline
            phase = .awaitingAcceptance
            return try WireCodec.encode(proof)
        } catch {
            terminate()
            throw error
        }
    }

    @discardableResult
    public func receiveAcceptedSession(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws -> ClientInteractiveAcceptedSessionV0 {
        do {
            try requirePhase(.awaitingAcceptance)
            try enforceApprovalDeadline(monotonicNowMilliseconds)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(
                    responseJSON,
                    expectedCorrelation: approvalProofMessageID
                )
            }
            guard kind == .interactiveSessionAccepted else {
                throw ClientInteractiveSessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSessionAcceptedBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == approvalProofMessageID,
                  response.body.authorizationEpoch
                    == challengeAuthorizationEpoch,
                  response.body.authorizationEpoch
                    == primary.authorizationEpoch else {
                throw ClientInteractiveSessionErrorV0.acceptedSessionMismatch
            }
            let result = ClientInteractiveAcceptedSessionV0(
                primary: primary,
                interactiveSessionID: response.body.interactiveSessionID.rawValue,
                authorizationEpoch: response.body.authorizationEpoch,
                expiresAtUnixMilliseconds: response.body.expiresAtUnixMilliseconds,
                inputChannel: response.body.inputChannel,
                mediaChannel: response.body.mediaChannel
            )
            acceptedSession = result
            phase = .accepted
            clearTransientApproval()
            return result
        } catch {
            terminate()
            throw error
        }
    }

    public func nextApprovalDeadlineMonotonicMilliseconds() -> UInt64? {
        phase == .awaitingAcceptance
            ? approvalDeadlineMonotonicMilliseconds
            : nil
    }

    @discardableResult
    public func expireApprovalIfRequired(
        at monotonicNowMilliseconds: UInt64
    ) -> Bool {
        guard phase == .awaitingAcceptance else { return false }
        do {
            try enforceApprovalDeadline(monotonicNowMilliseconds)
            return false
        } catch {
            terminate()
            return true
        }
    }

    public func close() {
        terminate()
    }

    private func enforceApprovalDeadline(_ value: UInt64) throws {
        guard value <= UInt64(Int64.max) else {
            throw ClientInteractiveSessionErrorV0.invalidClock
        }
        guard let deadline = approvalDeadlineMonotonicMilliseconds,
              value < deadline else {
            throw ClientInteractiveSessionErrorV0.approvalDeadlineExceeded
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
            throw ClientInteractiveSessionErrorV0.invalidCorrelation
        }
        throw ClientInteractiveSessionErrorV0.remoteError(
            code: response.body.code,
            retry: response.body.retry
        )
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientInteractiveSessionErrorV0.duplicateMessage(messageID)
        }
    }

    private func requirePhase(_ expected: ClientInteractiveSessionPhaseV0) throws {
        guard phase == expected else {
            throw ClientInteractiveSessionErrorV0.invalidPhase(phase)
        }
    }

    private func terminate() {
        phase = .closed
        acceptedSession = nil
        clearTransientApproval()
    }

    private func clearTransientApproval() {
        requestMessageID = nil
        approvalProofMessageID = nil
        requestedEffects = nil
        challengeAuthorizationEpoch = nil
        approvalDeadlineMonotonicMilliseconds = nil
    }
}

public enum ClientInteractiveChannelPhaseV0: String, Equatable, Sendable {
    case awaitingTCP
    case awaitingPinnedTLS
    case readyToAuthenticate
    case awaitingChallenge
    case awaitingAcceptance
    case ready
    case closed
}

public enum ClientInteractiveChannelErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case deadlineExceeded
    case invalidPhase(ClientInteractiveChannelPhaseV0)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case challengeBindingMismatch
    case serverProofMismatch
}

public actor ClientInteractiveChannelAuthorityV0 {
    public static let maximumUnusedLifetimeMilliseconds: UInt64 = 30_000

    public let session: ClientInteractiveAcceptedSessionV0
    public let offer: InteractiveChannelOffer
    public private(set) var phase: ClientInteractiveChannelPhaseV0 = .awaitingTCP

    private var credential: Data?
    private var transport: PinnedTLSConnectionAuthority
    private var replay = ConnectionReplayWindow()
    private var deadlineMonotonicMilliseconds: UInt64?
    private var hello: InteractiveChannelEnvelope<InteractiveChannelHelloBody>?
    private var proofMessageID: WireUUID?
    private var transcriptDigest: Data?

    public init(
        session: ClientInteractiveAcceptedSessionV0,
        role: InteractiveChannelRoleName
    ) throws {
        let offer = role == .input ? session.inputChannel : session.mediaChannel
        guard offer.role == role else {
            throw ClientInteractiveChannelErrorV0.invalidConfiguration
        }
        self.session = session
        self.offer = offer
        credential = offer.credential.rawValue
        transport = try PinnedTLSConnectionAuthority(
            role: role == .input ? .interactiveInput : .interactiveMedia,
            requiredHostFingerprint: session.primary.hostFingerprint
        )
    }

    public var pinnedTLSPhase: PinnedTLSConnectionPhase {
        transport.phase
    }

    public func didConnectTCP(at monotonicNowMilliseconds: UInt64) throws {
        do {
            try requirePhase(.awaitingTCP)
            let (deadline, overflow) = monotonicNowMilliseconds
                .addingReportingOverflow(
                    Self.maximumUnusedLifetimeMilliseconds
                )
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientInteractiveChannelErrorV0.invalidClock
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
            try enforceDeadline(monotonicNowMilliseconds)
            try transport.acceptPeer(evidence)
            phase = .readyToAuthenticate
        } catch {
            terminate()
            throw error
        }
    }

    public func begin(
        clientNonce: WireBytes32,
        messageID: WireUUID,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data {
        do {
            try requirePhase(.readyToAuthenticate)
            try enforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.interactiveChannelAuthentication)
            try admitReplay(messageID)
            let value = try InteractiveChannelEnvelope(
                messageID: messageID,
                correlationID: nil,
                body: InteractiveChannelHelloBody(
                    channelID: offer.channelID,
                    role: offer.role,
                    clientID: WireUUID(session.primary.clientID),
                    primaryConnectionID: try WireBytes16(
                        session.primary.primaryConnectionID
                    ),
                    interactiveSessionID: WireUUID(
                        session.interactiveSessionID
                    ),
                    authorizationEpoch: session.authorizationEpoch,
                    clientNonce: clientNonce
                )
            )
            hello = value
            phase = .awaitingChallenge
            return try InteractiveChannelCodec.encode(value)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveChallenge(
        _ responseJSON: Data,
        proofMessageID: WireUUID,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data {
        do {
            try requirePhase(.awaitingChallenge)
            try enforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.interactiveChannelAuthentication)
            guard let hello, let credential else {
                throw ClientInteractiveChannelErrorV0.invalidConfiguration
            }
            let response = try InteractiveChannelCodec.decode(
                InteractiveChannelEnvelope<InteractiveChannelChallengeBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == hello.messageID else {
                throw ClientInteractiveChannelErrorV0.invalidCorrelation
            }
            guard response.body.channelID == offer.channelID,
                  response.body.role == offer.role,
                  response.body.hostID.rawValue == session.primary.hostID,
                  response.body.hostFingerprint.rawValue
                    == session.primary.hostFingerprint else {
                throw ClientInteractiveChannelErrorV0.challengeBindingMismatch
            }
            try admitReplay(proofMessageID)
            let transcript = try hello.body.transcriptInput(
                challenge: response.body,
                version: response.version
            )
            let digest = CompanionSecurityV0
                .interactiveChannelTranscriptDigest(transcript)
            let clientProof = try CompanionSecurityV0
                .interactiveChannelClientProof(
                    credential: credential,
                    transcriptDigest: digest
                )
            let proof = try InteractiveChannelEnvelope(
                messageID: proofMessageID,
                correlationID: response.messageID,
                body: InteractiveChannelProofBody(
                    channelID: offer.channelID,
                    clientProof: try WireBytes32(clientProof)
                )
            )
            self.proofMessageID = proofMessageID
            transcriptDigest = digest
            phase = .awaitingAcceptance
            return try InteractiveChannelCodec.encode(proof)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveAcceptance(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws {
        do {
            try requirePhase(.awaitingAcceptance)
            try enforceDeadline(monotonicNowMilliseconds)
            try transport.admit(.interactiveChannelAuthentication)
            guard let credential, let transcriptDigest else {
                throw ClientInteractiveChannelErrorV0.invalidConfiguration
            }
            let response = try InteractiveChannelCodec.decode(
                InteractiveChannelEnvelope<InteractiveChannelAcceptedBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == proofMessageID else {
                throw ClientInteractiveChannelErrorV0.invalidCorrelation
            }
            guard response.body.channelID == offer.channelID,
                  response.body.role == offer.role else {
                throw ClientInteractiveChannelErrorV0.challengeBindingMismatch
            }
            let expected = try CompanionSecurityV0
                .interactiveChannelServerProof(
                    credential: credential,
                    transcriptDigest: transcriptDigest
                )
            guard response.body.serverProof.rawValue == expected else {
                throw ClientInteractiveChannelErrorV0.serverProofMismatch
            }
            try transport.roleAuthenticationSucceeded()
            phase = .ready
            clearCredential()
        } catch {
            terminate()
            throw error
        }
    }

    public func admitRoleTraffic() throws {
        do {
            try requirePhase(.ready)
            try transport.admit(
                offer.role == .input ? .inputFrame : .mediaRecord
            )
        } catch {
            terminate()
            throw error
        }
    }

    public func nextDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingPinnedTLS, .readyToAuthenticate, .awaitingChallenge,
             .awaitingAcceptance:
            return deadlineMonotonicMilliseconds
        case .awaitingTCP, .ready, .closed:
            return nil
        }
    }

    @discardableResult
    public func expireIfRequired(at monotonicNowMilliseconds: UInt64) -> Bool {
        guard phase != .ready, phase != .closed else { return false }
        do {
            try enforceDeadline(monotonicNowMilliseconds)
            return false
        } catch {
            terminate()
            return true
        }
    }

    public func close() {
        terminate()
    }

    private func enforceDeadline(_ value: UInt64) throws {
        guard value <= UInt64(Int64.max) else {
            throw ClientInteractiveChannelErrorV0.invalidClock
        }
        guard let deadline = deadlineMonotonicMilliseconds,
              value < deadline else {
            throw ClientInteractiveChannelErrorV0.deadlineExceeded
        }
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientInteractiveChannelErrorV0.duplicateMessage(messageID)
        }
    }

    private func requirePhase(_ expected: ClientInteractiveChannelPhaseV0) throws {
        guard phase == expected else {
            throw ClientInteractiveChannelErrorV0.invalidPhase(phase)
        }
    }

    private func terminate() {
        transport.close()
        phase = .closed
        clearCredential()
    }

    private func clearCredential() {
        credential = nil
        deadlineMonotonicMilliseconds = nil
        hello = nil
        proofMessageID = nil
        transcriptDigest = nil
    }
}
