import CompanionIPC
import CompanionPresentation
import Foundation

public protocol MacPairingReviewLocalIPCClientV0: Sendable {
    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0
}

public enum MacPairingReviewApplicationOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case invalidClock
    case expiredReview
    case commandIDReuse
    case revisionExhausted
}

/// Bundle-independent trusted-menu owner for a secret-free local pairing
/// review. It is both the already-authorized Agent-to-menu surface and the
/// menu-to-Agent decision coordinator, but never a pairing authority.
public actor MacPairingReviewApplicationOwnerV0:
    LocalPairingReviewSurfaceV0
{
    public typealias CommandIDSource = @Sendable () -> UUID
    public typealias StateChanged = @Sendable (
        MacPairingReviewPresentationV0
    ) async -> Void
    public typealias DecisionCompleted = @Sendable (
        LocalPairingDecisionReceiptV0
    ) async -> Void

    private let client: any MacPairingReviewLocalIPCClientV0
    private let clock: any MacPairingWallClockV0
    private let expiryScheduler: any MacPairingExpirySchedulingV0
    private let commandIDSource: CommandIDSource
    private let stateChanged: StateChanged
    private let decisionCompleted: DecisionCompleted

    private var presentation = MacPairingReviewPresentationV0()
    private var revision: UInt64 = 0
    private var inFlightRevision: UInt64?
    private var issuedCommandIDs: Set<UUID> = []
    private var expiryCancellation: (any MacPairingExpiryCancellationV0)?

    public init(
        client: any MacPairingReviewLocalIPCClientV0,
        clock: any MacPairingWallClockV0 = SystemMacPairingWallClockV0(),
        expiryScheduler: any MacPairingExpirySchedulingV0 =
            SystemMacPairingExpirySchedulerV0(),
        commandIDSource: @escaping CommandIDSource = { UUID() },
        stateChanged: @escaping StateChanged = { _ in },
        decisionCompleted: @escaping DecisionCompleted = { _ in }
    ) {
        self.client = client
        self.clock = clock
        self.expiryScheduler = expiryScheduler
        self.commandIDSource = commandIDSource
        self.stateChanged = stateChanged
        self.decisionCompleted = decisionCompleted
    }

    public func snapshot() -> MacPairingReviewPresentationV0 {
        presentation
    }

    public func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        let now = try validatedNow()
        guard now < review.expiresAtUnixMilliseconds else {
            throw MacPairingReviewApplicationOwnerErrorV0.expiredReview
        }
        let wasAlreadyVisible = presentation.review == review
        do {
            try presentation.receive(review)
        } catch {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        if !wasAlreadyVisible {
            _ = try advanceRevision()
            armExpiry(for: review)
            await publish()
        }
    }

    public func withdrawLocalPairingReview(reviewID: UUID) async {
        guard presentation.withdraw(reviewID: reviewID) else { return }
        cancelExpiry()
        invalidateCurrentRevision()
        await publish()
    }

    public func updateDeviceNameDraft(_ value: String) async throws {
        do {
            try presentation.updateDeviceNameDraft(value)
        } catch {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        await publish()
    }

    public func approve() async throws {
        try await beginDecision(.approve)
    }

    public func decline() async throws {
        try await beginDecision(.decline)
    }

    public func retryDecision() async throws {
        guard inFlightRevision == nil else {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        let command: LocalPairingDecisionCommandV0
        do {
            command = try presentation.retryDecision()
        } catch {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await perform(command, operationRevision: operationRevision)
    }

    public func agentInvalidated() async {
        cancelExpiry()
        invalidateCurrentRevision()
        presentation.invalidate()
        await publish()
    }

    private func beginDecision(
        _ decision: LocalPairingDecisionV0
    ) async throws {
        guard inFlightRevision == nil else {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        guard case .reviewing = presentation.phase else {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        let now = try validatedNow()
        guard let review = presentation.review,
              now < review.expiresAtUnixMilliseconds else {
            throw MacPairingReviewApplicationOwnerErrorV0.expiredReview
        }
        if decision == .approve,
           let issue = presentation.deviceNameDraftIssue() {
            throw MacPairingReviewPresentationErrorV0.invalidDraft(issue)
        }
        let commandID = try issueCommandID()
        let command: LocalPairingDecisionCommandV0
        do {
            command = switch decision {
            case .approve:
                try presentation.approve(
                    commandID: commandID,
                    decidedAtUnixMilliseconds: now
                )
            case .decline:
                try presentation.decline(
                    commandID: commandID,
                    decidedAtUnixMilliseconds: now
                )
            }
        } catch let error as MacPairingReviewPresentationErrorV0 {
            throw error
        } catch {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidPhase
        }
        cancelExpiry()
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await perform(command, operationRevision: operationRevision)
    }

    private func perform(
        _ command: LocalPairingDecisionCommandV0,
        operationRevision: UInt64
    ) async {
        do {
            let receipt = try await client.resolveLocalApproval(command)
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            do {
                try presentation.receiveDecisionReceipt(receipt)
                cancelExpiry()
                await decisionCompleted(receipt)
            } catch {
                try? presentation.decisionFailed()
            }
            await publish()
        } catch {
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            try? presentation.decisionFailed()
            await publish()
        }
    }

    private func armExpiry(for review: LocalPairingReviewV0) {
        cancelExpiry()
        let now = clock.nowUnixMilliseconds()
        let remaining: Int64
        if now < 0 || now > 9_007_199_254_740_991 {
            remaining = 0
        } else {
            remaining = max(0, review.expiresAtUnixMilliseconds - now)
        }
        let expectedRevision = revision
        expiryCancellation = expiryScheduler.schedule(
            afterMilliseconds: remaining
        ) { [weak self] in
            await self?.expire(
                reviewID: review.reviewID,
                expectedRevision: expectedRevision
            )
        }
    }

    private func expire(
        reviewID: UUID,
        expectedRevision: UInt64
    ) async {
        guard revision == expectedRevision,
              presentation.review?.reviewID == reviewID else { return }
        expiryCancellation = nil
        invalidateCurrentRevision()
        _ = presentation.withdraw(reviewID: reviewID)
        await publish()
    }

    private func validatedNow() throws -> Int64 {
        let now = clock.nowUnixMilliseconds()
        guard (0...9_007_199_254_740_991).contains(now) else {
            throw MacPairingReviewApplicationOwnerErrorV0.invalidClock
        }
        return now
    }

    private func issueCommandID() throws -> UUID {
        let value = commandIDSource()
        guard issuedCommandIDs.insert(value).inserted else {
            throw MacPairingReviewApplicationOwnerErrorV0.commandIDReuse
        }
        return value
    }

    private func startOperation() throws -> UInt64 {
        let value = try advanceRevision()
        inFlightRevision = value
        return value
    }

    @discardableResult
    private func advanceRevision() throws -> UInt64 {
        guard revision < UInt64.max else {
            presentation.invalidate()
            throw MacPairingReviewApplicationOwnerErrorV0.revisionExhausted
        }
        revision += 1
        return revision
    }

    private func invalidateCurrentRevision() {
        if revision < UInt64.max { revision += 1 }
        inFlightRevision = nil
    }

    private func cancelExpiry() {
        expiryCancellation?.cancel()
        expiryCancellation = nil
    }

    private func publish() async {
        await stateChanged(presentation)
    }
}
