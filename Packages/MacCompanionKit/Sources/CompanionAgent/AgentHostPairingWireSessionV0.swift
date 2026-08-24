import CompanionDomain
import CompanionIPC
import CompanionPairing
import CompanionTransport
import CompanionWire
import Foundation

public enum AgentHostPairingWirePhaseV0: String, Equatable, Sendable {
    case awaitingBegin
    case processingBegin
    case processingResume
    case awaitingProve
    case awaitingResumeProve
    case publishingReview
    case awaitingLocalDecision
    case resolvingLocalDecision
    case completed
    case closed
}

public enum AgentHostPairingWireErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case expired
    case invalidPhase(AgentHostPairingWirePhaseV0)
    case unexpectedMessage(WireMessageKind)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case authorityMismatch
    case localReviewUnavailable
}

public protocol AgentHostPairingAuthorityV0: Sendable {
    func beginHostPairing(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingChallenge

    func proveHostPairing(
        pairingID: UUID,
        secretProof: Data,
        signature: Data,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingApprovalContext

    func cancelHostPairing(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws
}

extension PairingSessionAuthority: AgentHostPairingAuthorityV0 {
    public func beginHostPairing(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        monotonicNowMilliseconds: Int64
    ) throws -> PairingChallenge {
        try begin(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKeyX963,
            approvalPublicKeyX963: approvalPublicKeyX963,
            clientNonce: clientNonce,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func proveHostPairing(
        pairingID: UUID,
        secretProof: Data,
        signature: Data,
        monotonicNowMilliseconds: Int64
    ) throws -> PairingApprovalContext {
        try prove(
            pairingID: pairingID,
            secretProof: secretProof,
            signature: signature,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func cancelHostPairing(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) throws {
        try cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }
}

public protocol AgentHostPairingDecisionHandlingV0: Sendable {
    func registerHostPairingReview(
        _ context: PairingApprovalContext,
        reviewID: UUID
    ) async throws -> LocalPairingReviewV0

    func resolveHostPairingOutcome(
        reviewID: UUID,
        expirePendingAtMonotonicMilliseconds: Int64?
    ) async -> AgentHostPairingOutcomeResolutionV0

    func cancelHostPairingReview(
        reviewID: UUID,
        monotonicNowMilliseconds: Int64
    ) async
}

extension AgentLocalPairingDecisionHandlerV0:
    AgentHostPairingDecisionHandlingV0
{
    public func registerHostPairingReview(
        _ context: PairingApprovalContext,
        reviewID: UUID
    ) async throws -> LocalPairingReviewV0 {
        try await registerCurrentPolicyReview(
            context,
            reviewID: reviewID
        )
    }

    public func cancelHostPairingReview(
        reviewID: UUID,
        monotonicNowMilliseconds: Int64
    ) async {
        await cancel(
            reviewID: reviewID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }
}

public protocol AgentHostPairingReviewPublishingV0: Sendable {
    /// Returns only after the exact review has been accepted for delivery to
    /// the trusted visible local approval surface.
    func publishHostPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws

    /// Removes only the exact previously published review. This is best-effort
    /// presentation teardown and cannot undo an in-flight durable decision.
    func withdrawHostPairingReview(reviewID: UUID) async
}

/// Owns one unpaired, already-verified host TLS connection from the first
/// `pairing.begin` through a server-initiated durable completion or closed
/// error. Sockets and local peer authentication remain outside this actor.
public actor AgentHostPairingWireSessionV0 {
    public static let maximumLifetimeMilliseconds: UInt64 = 5 * 60 * 1_000

    public let hostID: UUID
    public let tlsBinding: HostApplicationTLSBinding
    public private(set) var phase: AgentHostPairingWirePhaseV0 = .awaitingBegin

    private let authority: any AgentHostPairingAuthorityV0
    private let recovery: any AgentHostPairingRecoveryAuthorityV0
    private let decisions: any AgentHostPairingDecisionHandlingV0
    private let reviewPublisher: any AgentHostPairingReviewPublishingV0
    private let makeReviewID: @Sendable () -> UUID
    private let connectionDeadlineMonotonicMilliseconds: UInt64
    private var replay = ConnectionReplayWindow()
    private var lastMonotonicMilliseconds: UInt64
    private var pairingID: UUID?
    private var clientID: UUID?
    private var challengeMessageID: WireUUID?
    private var proofMessageID: WireUUID?
    private var reviewID: UUID?
    private var pairingDeadlineMonotonicMilliseconds: UInt64?
    private var recoveryRequest: PairingResumeBody?
    private var recoveryHostNonce: Data?
    private var recoverySelectedVersion: WireVersion?
    private var isRecovery = false

    public init(
        hostID: UUID,
        tlsBinding: HostApplicationTLSBinding,
        acceptedAtMonotonicMilliseconds: UInt64,
        authority: any AgentHostPairingAuthorityV0,
        recovery: any AgentHostPairingRecoveryAuthorityV0 =
            UnavailableAgentHostPairingRecoveryAuthorityV0(),
        decisions: any AgentHostPairingDecisionHandlingV0,
        reviewPublisher: any AgentHostPairingReviewPublishingV0,
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        let (deadline, overflow) = acceptedAtMonotonicMilliseconds
            .addingReportingOverflow(Self.maximumLifetimeMilliseconds)
        guard tlsBinding.hostFingerprint.count == 32,
              acceptedAtMonotonicMilliseconds <= UInt64(Int64.max),
              !overflow,
              deadline <= UInt64(Int64.max) else {
            throw AgentHostPairingWireErrorV0.invalidConfiguration
        }
        self.hostID = hostID
        self.tlsBinding = tlsBinding
        self.authority = authority
        self.recovery = recovery
        self.decisions = decisions
        self.reviewPublisher = reviewPublisher
        self.makeReviewID = makeReviewID
        connectionDeadlineMonotonicMilliseconds = deadline
        lastMonotonicMilliseconds = acceptedAtMonotonicMilliseconds
    }

    public func receive(
        requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        do {
            try observe(
                wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            let kind = try WireCodec.messageKind(from: requestJSON)
            switch phase {
            case .awaitingBegin:
                switch kind {
                case .pairingBegin:
                    return try await receiveBegin(
                        requestJSON,
                        wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                        monotonicNowMilliseconds: monotonicNowMilliseconds,
                        responseMessageID: responseMessageID
                    )
                case .pairingResume:
                    return try await receiveResume(
                        requestJSON,
                        wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                        monotonicNowMilliseconds: monotonicNowMilliseconds,
                        responseMessageID: responseMessageID
                    )
                default:
                    throw AgentHostPairingWireErrorV0.unexpectedMessage(kind)
                }
            case .awaitingProve:
                guard kind == .pairingProve else {
                    throw AgentHostPairingWireErrorV0
                        .unexpectedMessage(kind)
                }
                return try await receiveProve(
                    requestJSON,
                    wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                    monotonicNowMilliseconds: monotonicNowMilliseconds,
                    responseMessageID: responseMessageID
                )
            case .awaitingResumeProve:
                guard kind == .pairingResumeProve else {
                    throw AgentHostPairingWireErrorV0.unexpectedMessage(kind)
                }
                return try await receiveResumeProve(
                    requestJSON,
                    wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                    monotonicNowMilliseconds: monotonicNowMilliseconds,
                    responseMessageID: responseMessageID
                )
            default:
                throw AgentHostPairingWireErrorV0.invalidPhase(phase)
            }
        } catch {
            await terminate(
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            throw error
        }
    }

    /// Returns a completion/error frame only after a local outcome exists or
    /// the original pairing deadline is reached. A nil result mutates no
    /// outbound replay state.
    public func takeCompletionIfAvailable(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data? {
        guard phase == .awaitingLocalDecision,
              let reviewID,
              let proofMessageID,
              let pairingID,
              let clientID,
              let deadline = pairingDeadlineMonotonicMilliseconds else {
            throw AgentHostPairingWireErrorV0.invalidPhase(phase)
        }
        try observeWithoutDeadline(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        phase = .resolvingLocalDecision
        let resolution = await decisions.resolveHostPairingOutcome(
            reviewID: reviewID,
            expirePendingAtMonotonicMilliseconds:
                monotonicNowMilliseconds >= deadline
                    ? Int64(monotonicNowMilliseconds)
                    : nil
        )
        guard phase == .resolvingLocalDecision else {
            throw AgentHostPairingWireErrorV0.invalidPhase(phase)
        }

        switch resolution {
        case let .outcome(outcome):
            try admitReplay(responseMessageID)
            await reviewPublisher.withdrawHostPairingReview(
                reviewID: reviewID
            )
            switch outcome {
            case let .approved(completed):
                guard completed.pairingID == pairingID,
                      completed.clientID == clientID else {
                    await terminate(
                        monotonicNowMilliseconds: monotonicNowMilliseconds
                    )
                    throw AgentHostPairingWireErrorV0.authorityMismatch
                }
                let response = try WireEnvelope(
                    messageID: responseMessageID,
                    correlationID: proofMessageID,
                    sentAtUnixMilliseconds: wallNowUnixMilliseconds,
                    body: PairingCompleteBody(
                        hostID: WireUUID(hostID),
                        deviceID: WireUUID(completed.deviceID),
                        policyRevision: completed.policyRevision,
                        hostFingerprint: WireFingerprint(
                            tlsBinding.hostFingerprint
                        )
                    )
                )
                phase = .completed
                clearTransientState()
                return try WireCodec.encode(response)
            case .declined:
                phase = .closed
                clearTransientState()
                return try errorResponse(
                    code: "pairing.alreadyConsumed",
                    retry: .never,
                    correlationID: proofMessageID,
                    messageID: responseMessageID,
                    sentAtUnixMilliseconds: wallNowUnixMilliseconds
                )
            }
        case .pending, .decisionInFlight:
            phase = .awaitingLocalDecision
            return nil
        case .unavailable:
            break
        case .expired:
            break
        }

        await reviewPublisher.withdrawHostPairingReview(reviewID: reviewID)
        try admitReplay(responseMessageID)
        phase = .closed
        clearTransientState()
        return try errorResponse(
            code: "pairing.expired",
            retry: .never,
            correlationID: proofMessageID,
            messageID: responseMessageID,
            sentAtUnixMilliseconds: wallNowUnixMilliseconds
        )
    }

    public func nextDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingBegin, .processingBegin, .processingResume,
             .awaitingProve, .awaitingResumeProve,
             .publishingReview:
            return pairingDeadlineMonotonicMilliseconds
                ?? connectionDeadlineMonotonicMilliseconds
        case .awaitingLocalDecision, .resolvingLocalDecision:
            return pairingDeadlineMonotonicMilliseconds
        case .completed, .closed:
            return nil
        }
    }

    public func cancel(at monotonicNowMilliseconds: UInt64) async {
        guard phase != .completed, phase != .closed else { return }
        let bounded = min(monotonicNowMilliseconds, UInt64(Int64.max))
        let cancellationTime = max(lastMonotonicMilliseconds, bounded)
        await terminate(monotonicNowMilliseconds: cancellationTime)
    }

    private func receiveBegin(
        _ requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<PairingBeginBody>.self,
            from: requestJSON
        )
        try admitReplay(request.messageID)
        try admitReplay(responseMessageID)
        pairingID = request.body.pairingID.rawValue
        clientID = request.body.clientID.rawValue
        phase = .processingBegin
        let challenge: PairingChallenge
        do {
            challenge = try await authority.beginHostPairing(
                pairingID: request.body.pairingID.rawValue,
                clientID: request.body.clientID.rawValue,
                sessionPublicKeyX963: request.body.sessionPublicKey.rawValue,
                approvalPublicKeyX963:
                    request.body.approvalPublicKey.rawValue,
                clientNonce: request.body.clientNonce.rawValue,
                monotonicNowMilliseconds: Int64(monotonicNowMilliseconds)
            )
        } catch let error as PairingSessionError {
            phase = .closed
            clearTransientState()
            return try pairingErrorResponse(
                error,
                correlationID: request.messageID,
                messageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        }
        guard phase == .processingBegin,
              challenge.hostFingerprint == tlsBinding.hostFingerprint else {
            await terminate(monotonicNowMilliseconds: monotonicNowMilliseconds)
            throw AgentHostPairingWireErrorV0.authorityMismatch
        }
        challengeMessageID = responseMessageID
        phase = .awaitingProve
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: wallNowUnixMilliseconds,
            body: PairingChallengeBody(
                hostNonce: try WireBytes32(challenge.hostNonce),
                selectedVersion: WireVersion(
                    major: challenge.selectedMajor,
                    minor: challenge.selectedMinor
                ),
                hostFingerprint: WireFingerprint(challenge.hostFingerprint)
            )
        ))
    }

    private func receiveProve(
        _ requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<PairingProveBody>.self,
            from: requestJSON
        )
        guard request.correlationID == challengeMessageID,
              let pairingID,
              let clientID else {
            throw AgentHostPairingWireErrorV0.invalidCorrelation
        }
        try admitReplay(request.messageID)
        try admitReplay(responseMessageID)
        phase = .publishingReview
        let context: PairingApprovalContext
        do {
            context = try await authority.proveHostPairing(
                pairingID: pairingID,
                secretProof: request.body.secretProof.rawValue,
                signature: request.body.signature.rawValue,
                monotonicNowMilliseconds: Int64(monotonicNowMilliseconds)
            )
        } catch let error as PairingSessionError {
            if case let .invalidProof(remainingAttempts) = error,
               remainingAttempts > 0 {
                phase = .awaitingProve
            } else {
                await terminate(
                    monotonicNowMilliseconds: monotonicNowMilliseconds
                )
            }
            return try pairingErrorResponse(
                error,
                correlationID: request.messageID,
                messageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        }
        guard phase == .publishingReview,
              context.pairingID == pairingID,
              context.clientID == clientID,
              context.deadlineMonotonicMilliseconds > 0,
              UInt64(context.deadlineMonotonicMilliseconds)
                <= connectionDeadlineMonotonicMilliseconds else {
            await terminate(monotonicNowMilliseconds: monotonicNowMilliseconds)
            throw AgentHostPairingWireErrorV0.authorityMismatch
        }
        let newReviewID = makeReviewID()
        let review: LocalPairingReviewV0
        do {
            review = try await decisions.registerHostPairingReview(
                context,
                reviewID: newReviewID
            )
            guard phase == .publishingReview else {
                await decisions.cancelHostPairingReview(
                    reviewID: newReviewID,
                    monotonicNowMilliseconds: Int64(
                        monotonicNowMilliseconds
                    )
                )
                throw AgentHostPairingWireErrorV0.invalidPhase(phase)
            }
            self.reviewID = newReviewID
            try await reviewPublisher.publishHostPairingReview(review)
        } catch {
            await terminate(monotonicNowMilliseconds: monotonicNowMilliseconds)
            phase = .closed
            return try errorResponse(
                code: "pairing.alreadyConsumed",
                retry: .afterUserAction,
                correlationID: request.messageID,
                messageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        }
        guard phase == .publishingReview else {
            await terminate(monotonicNowMilliseconds: monotonicNowMilliseconds)
            throw AgentHostPairingWireErrorV0.invalidPhase(phase)
        }
        proofMessageID = request.messageID
        pairingDeadlineMonotonicMilliseconds = UInt64(
            context.deadlineMonotonicMilliseconds
        )
        phase = .awaitingLocalDecision
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: wallNowUnixMilliseconds,
            body: PairingPendingApprovalBody(
                transcriptDigest: WireBytes32(context.transcriptDigest),
                authenticationString: PairingAuthenticationString(
                    context.authenticationString
                ),
                expiresAtUnixMilliseconds:
                    context.expiresAtUnixMilliseconds
            )
        ))
    }

    private func receiveResume(
        _ requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<PairingResumeBody>.self,
            from: requestJSON
        )
        try admitReplay(request.messageID)
        try admitReplay(responseMessageID)
        pairingID = request.body.pairingID.rawValue
        clientID = request.body.clientID.rawValue
        isRecovery = true
        phase = .processingResume
        do {
            let challenge = try await recovery.beginPairingRecovery(
                pairingID: request.body.pairingID.rawValue,
                clientID: request.body.clientID.rawValue,
                sessionPublicKeyX963: request.body.sessionPublicKey.rawValue,
                approvalPublicKeyX963: request.body.approvalPublicKey.rawValue
            )
            guard phase == .processingResume else {
                throw AgentHostPairingWireErrorV0.invalidPhase(phase)
            }
            let version = WireVersion(
                major: challenge.selectedMajor,
                minor: challenge.selectedMinor
            )
            recoveryRequest = request.body
            recoveryHostNonce = challenge.hostNonce
            recoverySelectedVersion = version
            challengeMessageID = responseMessageID
            phase = .awaitingResumeProve
            return try WireCodec.encode(WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds,
                body: PairingResumeChallengeBody(
                    hostNonce: try WireBytes32(challenge.hostNonce),
                    selectedVersion: version,
                    hostFingerprint: WireFingerprint(
                        tlsBinding.hostFingerprint
                    )
                )
            ))
        } catch {
            phase = .closed
            clearTransientState()
            return try errorResponse(
                code: "pairing.alreadyConsumed",
                retry: .afterUserAction,
                correlationID: request.messageID,
                messageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        }
    }

    private func receiveResumeProve(
        _ requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<PairingResumeProveBody>.self,
            from: requestJSON
        )
        guard request.correlationID == challengeMessageID,
              let resume = recoveryRequest,
              let hostNonce = recoveryHostNonce,
              let version = recoverySelectedVersion else {
            throw AgentHostPairingWireErrorV0.invalidCorrelation
        }
        try admitReplay(request.messageID)
        try admitReplay(responseMessageID)
        do {
            let completed = try await recovery.provePairingRecovery(
                pairingID: resume.pairingID.rawValue,
                clientID: resume.clientID.rawValue,
                sessionPublicKeyX963: resume.sessionPublicKey.rawValue,
                approvalPublicKeyX963: resume.approvalPublicKey.rawValue,
                clientNonce: resume.clientNonce.rawValue,
                hostNonce: hostNonce,
                hostFingerprint: tlsBinding.hostFingerprint,
                selectedMajor: version.major,
                selectedMinor: version.minor,
                signature: request.body.signature.rawValue
            )
            let response = try WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds,
                body: PairingCompleteBody(
                    hostID: WireUUID(hostID),
                    deviceID: WireUUID(completed.deviceID),
                    policyRevision: completed.policyRevision,
                    hostFingerprint: WireFingerprint(
                        tlsBinding.hostFingerprint
                    )
                )
            )
            phase = .completed
            clearTransientState()
            return try WireCodec.encode(response)
        } catch {
            phase = .closed
            clearTransientState()
            return try errorResponse(
                code: "pairing.invalidProof",
                retry: .never,
                correlationID: request.messageID,
                messageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        }
    }

    private func observe(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        try observeWithoutDeadline(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        let deadline = pairingDeadlineMonotonicMilliseconds
            ?? connectionDeadlineMonotonicMilliseconds
        guard monotonicNowMilliseconds < deadline else {
            throw AgentHostPairingWireErrorV0.expired
        }
    }

    private func observeWithoutDeadline(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger,
              monotonicNowMilliseconds <= UInt64(Int64.max),
              monotonicNowMilliseconds >= lastMonotonicMilliseconds else {
            throw AgentHostPairingWireErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = monotonicNowMilliseconds
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw AgentHostPairingWireErrorV0.duplicateMessage(messageID)
        } catch {
            throw AgentHostPairingWireErrorV0.invalidConfiguration
        }
    }

    private func pairingErrorResponse(
        _ error: PairingSessionError,
        correlationID: WireUUID,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        let code: String
        switch error {
        case .expired, .notFound:
            code = "pairing.expired"
        case .invalidProof:
            code = "pairing.invalidProof"
        case .alreadyConsumed:
            code = "pairing.alreadyConsumed"
        default:
            code = "protocol.invalidFrame"
        }
        if code == "protocol.invalidFrame" {
            return try errorResponse(
                code: code,
                retry: .never,
                arguments: .object([
                    .init(
                        key: "reasonCode",
                        value: .string("invalidBody")
                    ),
                ]),
                correlationID: correlationID,
                messageID: messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds
            )
        }
        return try errorResponse(
            code: code,
            retry: .never,
            correlationID: correlationID,
            messageID: messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds
        )
    }

    private func errorResponse(
        code: String,
        retry: ProtocolErrorRetry,
        arguments: CanonicalJSONValue = .object([]),
        correlationID: WireUUID,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: correlationID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: ProtocolErrorResponseBody(
                code: code,
                retry: retry,
                safeArguments: arguments
            )
        ))
    }

    private func terminate(monotonicNowMilliseconds: UInt64) async {
        guard phase != .completed else { return }
        phase = .closed
        if let reviewID {
            await reviewPublisher.withdrawHostPairingReview(
                reviewID: reviewID
            )
            await decisions.cancelHostPairingReview(
                reviewID: reviewID,
                monotonicNowMilliseconds: Int64(
                    min(monotonicNowMilliseconds, UInt64(Int64.max))
                )
            )
        } else if let pairingID, !isRecovery {
            try? await authority.cancelHostPairing(
                pairingID: pairingID,
                monotonicNowMilliseconds: Int64(
                    min(monotonicNowMilliseconds, UInt64(Int64.max))
                )
            )
        }
        clearTransientState()
    }

    private func clearTransientState() {
        pairingID = nil
        clientID = nil
        challengeMessageID = nil
        proofMessageID = nil
        reviewID = nil
        pairingDeadlineMonotonicMilliseconds = nil
        recoveryRequest = nil
        recoveryHostNonce = nil
        recoverySelectedVersion = nil
        isRecovery = false
    }

}
