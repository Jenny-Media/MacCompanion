import CompanionDomain
import CompanionIPC
import CompanionPairing
import CompanionWire
import Foundation

public enum AgentLocalPairingDecisionHandlerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidReview
    case duplicateReview(UUID)
    case reviewUnavailable(UUID)
    case commandMismatch
    case commandInFlight(UUID)
    case invalidClock
    case staleReview
    case policyChanged
    case authorityUnavailable
    case persistenceMismatch
}

public enum AgentLocalPairingDecisionOutcomeV0: Equatable, Sendable {
    case approved(CompletedPairing)
    case declined
}

public enum AgentHostPairingOutcomeResolutionV0: Equatable, Sendable {
    case pending
    case decisionInFlight
    case outcome(AgentLocalPairingDecisionOutcomeV0)
    case expired
    case unavailable
}

public protocol AgentLocalPairingDecisionManagingV0: Sendable {
    func decideLocalPairing(
        pairingID: UUID,
        approvedTranscriptDigest: Data,
        approved: Bool,
        deviceID: UUID,
        displayName: DeviceDisplayName?,
        policyRevision: PolicyRevision,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> CompletedPairing

    func cancelLocalPairingDecision(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws
}

extension PairingSessionAuthority: AgentLocalPairingDecisionManagingV0 {
    public func decideLocalPairing(
        pairingID: UUID,
        approvedTranscriptDigest: Data,
        approved: Bool,
        deviceID: UUID,
        displayName: DeviceDisplayName?,
        policyRevision: PolicyRevision,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> CompletedPairing {
        try await decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: approvedTranscriptDigest,
            approved: approved,
            deviceID: deviceID,
            displayName: displayName,
            policyRevision: policyRevision,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func cancelLocalPairingDecision(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) throws {
        try cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }
}

public protocol AgentLocalPairingPolicyReadingV0: Sendable {
    func currentPairingPolicyRevision() async throws -> PolicyRevision
}

public struct StaticAgentLocalPairingPolicySourceV0:
    AgentLocalPairingPolicyReadingV0,
    Sendable
{
    private let revision: PolicyRevision

    public init(_ revision: PolicyRevision) {
        self.revision = revision
    }

    public func currentPairingPolicyRevision() async throws
        -> PolicyRevision
    {
        revision
    }
}

/// Agent-owned local SAS review authority. Remote proof supplies an already
/// validated context; only this actor creates the menu review, binds the local
/// name and policy fence, drives the atomic pairing decision, and publishes a
/// one-use outcome for the waiting remote pairing transport.
public actor AgentLocalPairingDecisionHandlerV0 {
    public static let maximumCompletedDecisions = 32

    private struct Completion: Sendable {
        let command: LocalPairingDecisionCommandV0
        let receipt: LocalPairingDecisionReceiptV0
    }

    private let authority: any AgentLocalPairingDecisionManagingV0
    private let timeSource: any AgentLocalPairingTimeSamplingV0
    private let policySource: any AgentLocalPairingPolicyReadingV0
    private let makeDeviceID: @Sendable () -> UUID
    private var pending: [UUID: LocalPairingReviewV0] = [:]
    private var inFlight: Set<UUID> = []
    private var inFlightReviewIDs: Set<UUID> = []
    private var outcomes: [UUID: AgentLocalPairingDecisionOutcomeV0] = [:]
    private var completions: [UUID: Completion] = [:]
    private var completionOrder: [UUID] = []

    public init(
        authority: any AgentLocalPairingDecisionManagingV0,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        makeDeviceID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.authority = authority
        self.timeSource = timeSource
        self.policySource = policySource
        self.makeDeviceID = makeDeviceID
    }

    public func register(
        _ context: PairingApprovalContext,
        reviewID: UUID,
        policyRevision: PolicyRevision
    ) throws -> LocalPairingReviewV0 {
        guard pending[reviewID] == nil,
              outcomes[reviewID] == nil else {
            throw AgentLocalPairingDecisionHandlerErrorV0
                .duplicateReview(reviewID)
        }
        let review: LocalPairingReviewV0
        do {
            review = try LocalPairingReviewV0(
                reviewID: reviewID,
                pairingID: context.pairingID,
                clientID: context.clientID,
                sessionPublicKeyFingerprint: WireFingerprint(
                    context.sessionPublicKeyFingerprint
                ),
                approvalPublicKeyFingerprint: WireFingerprint(
                    context.approvalPublicKeyFingerprint
                ),
                transcriptDigest: WireBytes32(context.transcriptDigest),
                authenticationString: PairingAuthenticationString(
                    context.authenticationString
                ),
                expectedPolicyRevision: policyRevision,
                expiresAtUnixMilliseconds:
                    context.expiresAtUnixMilliseconds
            )
        } catch {
            throw AgentLocalPairingDecisionHandlerErrorV0.invalidReview
        }
        pending[reviewID] = review
        return review
    }

    public func registerCurrentPolicyReview(
        _ context: PairingApprovalContext,
        reviewID: UUID
    ) async throws -> LocalPairingReviewV0 {
        let policyRevision: PolicyRevision
        do {
            policyRevision = try await policySource
                .currentPairingPolicyRevision()
        } catch {
            throw AgentLocalPairingDecisionHandlerErrorV0
                .authorityUnavailable
        }
        return try register(
            context,
            reviewID: reviewID,
            policyRevision: policyRevision
        )
    }

    public func cancel(reviewID: UUID) async {
        guard let review = pending[reviewID] else {
            return
        }
        guard let time = try? timeSource.currentPairingTime() else { return }
        pending.removeValue(forKey: reviewID)
        try? await authority.cancelLocalPairingDecision(
            pairingID: review.pairingID,
            monotonicNowMilliseconds: time.monotonicNowMilliseconds
        )
    }

    public func cancel(
        reviewID: UUID,
        monotonicNowMilliseconds: Int64
    ) async {
        guard monotonicNowMilliseconds >= 0,
              let review = pending.removeValue(forKey: reviewID) else {
            return
        }
        try? await authority.cancelLocalPairingDecision(
            pairingID: review.pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func takeOutcome(
        reviewID: UUID
    ) -> AgentLocalPairingDecisionOutcomeV0? {
        outcomes.removeValue(forKey: reviewID)
    }

    /// Exact, non-mutating check used by the trusted-local delivery boundary.
    /// It cannot enumerate or disclose any other pending review.
    public func containsPendingReview(
        _ review: LocalPairingReviewV0
    ) -> Bool {
        pending[review.reviewID] == review
    }

    /// Returns only an exact retained post-commit receipt. It never admits a
    /// new decision or reveals whether another command ID exists.
    public func replayReceipt(
        for command: LocalPairingDecisionCommandV0
    ) throws -> LocalPairingDecisionReceiptV0? {
        guard let completion = completions[command.commandID] else {
            return nil
        }
        guard completion.command == command else {
            throw AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
        }
        return completion.receipt
    }

    public func resolveHostPairingOutcome(
        reviewID: UUID,
        expirePendingAtMonotonicMilliseconds: Int64?
    ) async -> AgentHostPairingOutcomeResolutionV0 {
        if inFlightReviewIDs.contains(reviewID) {
            return .decisionInFlight
        }
        if let outcome = outcomes.removeValue(forKey: reviewID) {
            return .outcome(outcome)
        }
        guard let expiry = expirePendingAtMonotonicMilliseconds else {
            return pending[reviewID] == nil ? .unavailable : .pending
        }
        guard expiry >= 0 else { return .unavailable }
        guard let review = pending.removeValue(forKey: reviewID) else {
            return .unavailable
        }
        try? await authority.cancelLocalPairingDecision(
            pairingID: review.pairingID,
            monotonicNowMilliseconds: expiry
        )
        return .expired
    }

    public func handle(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        if let completion = completions[command.commandID] {
            guard completion.command == command else {
                throw AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
            }
            return completion.receipt
        }
        guard !inFlight.contains(command.commandID) else {
            throw AgentLocalPairingDecisionHandlerErrorV0.commandInFlight(
                command.commandID
            )
        }
        guard let review = pending.removeValue(forKey: command.reviewID) else {
            throw AgentLocalPairingDecisionHandlerErrorV0.reviewUnavailable(
                command.reviewID
            )
        }
        let time: AgentLocalPairingTimeSampleV0
        do {
            time = try timeSource.currentPairingTime()
        } catch {
            pending[review.reviewID] = review
            throw AgentLocalPairingDecisionHandlerErrorV0.invalidClock
        }
        guard command.matches(review) else {
            try? await authority.cancelLocalPairingDecision(
                pairingID: review.pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
        }
        guard command.decidedAtUnixMilliseconds
                <= time.wallNowUnixMilliseconds,
              time.wallNowUnixMilliseconds
                < review.expiresAtUnixMilliseconds else {
            try? await authority.cancelLocalPairingDecision(
                pairingID: review.pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingDecisionHandlerErrorV0.staleReview
        }

        inFlight.insert(command.commandID)
        inFlightReviewIDs.insert(review.reviewID)
        defer {
            inFlight.remove(command.commandID)
            inFlightReviewIDs.remove(review.reviewID)
        }
        let currentPolicy: PolicyRevision
        do {
            currentPolicy = try await policySource
                .currentPairingPolicyRevision()
        } catch {
            pending[review.reviewID] = review
            throw AgentLocalPairingDecisionHandlerErrorV0
                .authorityUnavailable
        }
        guard currentPolicy == review.expectedPolicyRevision else {
            try? await authority.cancelLocalPairingDecision(
                pairingID: review.pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingDecisionHandlerErrorV0.policyChanged
        }

        let outcome: AgentLocalPairingDecisionOutcomeV0
        let deviceID: UUID?
        do {
            switch command.decision {
            case .approve:
                guard let displayName = command.deviceDisplayName else {
                    throw AgentLocalPairingDecisionHandlerErrorV0
                        .commandMismatch
                }
                let proposedDeviceID = makeDeviceID()
                let completed = try await authority.decideLocalPairing(
                    pairingID: review.pairingID,
                    approvedTranscriptDigest:
                        review.transcriptDigest.rawValue,
                    approved: true,
                    deviceID: proposedDeviceID,
                    displayName: displayName,
                    policyRevision: currentPolicy,
                    wallNowUnixMilliseconds:
                        time.wallNowUnixMilliseconds,
                    monotonicNowMilliseconds:
                        time.monotonicNowMilliseconds
                )
                guard completed.pairingID == review.pairingID,
                      completed.clientID == review.clientID,
                      completed.deviceID == proposedDeviceID,
                      completed.displayName == displayName,
                      completed.policyRevision == currentPolicy else {
                    throw AgentLocalPairingDecisionHandlerErrorV0
                        .persistenceMismatch
                }
                outcome = .approved(completed)
                deviceID = completed.deviceID
            case .decline:
                do {
                    _ = try await authority.decideLocalPairing(
                        pairingID: review.pairingID,
                        approvedTranscriptDigest:
                            review.transcriptDigest.rawValue,
                        approved: false,
                        deviceID: makeDeviceID(),
                        displayName: nil,
                        policyRevision: currentPolicy,
                        wallNowUnixMilliseconds:
                            time.wallNowUnixMilliseconds,
                        monotonicNowMilliseconds:
                            time.monotonicNowMilliseconds
                    )
                    throw AgentLocalPairingDecisionHandlerErrorV0
                        .persistenceMismatch
                } catch PairingSessionError.approvalRejected {
                    outcome = .declined
                    deviceID = nil
                }
            }
        } catch let error as AgentLocalPairingDecisionHandlerErrorV0 {
            throw error
        } catch let error as PairingSessionError {
            switch error {
            case .expired, .alreadyConsumed, .notFound:
                throw AgentLocalPairingDecisionHandlerErrorV0.staleReview
            default:
                throw AgentLocalPairingDecisionHandlerErrorV0
                    .authorityUnavailable
            }
        } catch {
            pending[review.reviewID] = review
            throw AgentLocalPairingDecisionHandlerErrorV0
                .authorityUnavailable
        }

        let receipt: LocalPairingDecisionReceiptV0
        do {
            receipt = try LocalPairingDecisionReceiptV0(
                correlationID: command.commandID,
                reviewID: command.reviewID,
                pairingID: command.pairingID,
                clientID: command.clientID,
                decision: command.decision,
                deviceID: deviceID,
                storedDisplayName: command.deviceDisplayName,
                completedAtUnixMilliseconds:
                    time.wallNowUnixMilliseconds
            )
            try receipt.validate(against: command)
        } catch {
            throw AgentLocalPairingDecisionHandlerErrorV0
                .persistenceMismatch
        }
        outcomes[review.reviewID] = outcome
        retain(command: command, receipt: receipt)
        return receipt
    }

    private func retain(
        command: LocalPairingDecisionCommandV0,
        receipt: LocalPairingDecisionReceiptV0
    ) {
        completions[command.commandID] = Completion(
            command: command,
            receipt: receipt
        )
        completionOrder.append(command.commandID)
        if completionOrder.count > Self.maximumCompletedDecisions {
            let evicted = completionOrder.removeFirst()
            completions.removeValue(forKey: evicted)
        }
    }
}
