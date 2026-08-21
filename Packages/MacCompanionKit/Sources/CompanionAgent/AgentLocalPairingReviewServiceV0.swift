import CompanionIPC
import Foundation

public enum AgentLocalPairingReviewServiceErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidated
    case reviewUnavailable(UUID)
    case reviewAlreadyVisible(UUID)
    case transitionInProgress
}

/// Connection-scoped, already-authorized local pairing service. It owns only
/// delivery state; `AgentLocalPairingDecisionHandlerV0` remains the sole
/// semantic and replay authority.
public actor AgentLocalPairingReviewServiceV0:
    AgentHostPairingReviewPublishingV0
{
    private enum State: Sendable {
        case idle
        case publishing(LocalPairingReviewV0, UInt64)
        case visible(LocalPairingReviewV0, UInt64)
        case resolving(
            LocalPairingReviewV0,
            LocalPairingDecisionCommandV0,
            UInt64
        )
        case invalidated

        var review: LocalPairingReviewV0? {
            switch self {
            case let .publishing(review, _), let .visible(review, _),
                 let .resolving(review, _, _):
                review
            case .idle, .invalidated:
                nil
            }
        }
    }

    private let decisions: AgentLocalPairingDecisionHandlerV0
    private let surface: any LocalPairingReviewSurfaceV0
    private var state: State = .idle
    private var generation: UInt64 = 0

    public init(
        decisions: AgentLocalPairingDecisionHandlerV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0
    ) {
        self.decisions = decisions
        surface = alreadyAuthorizedSurface
    }

    public func visibleReview() -> LocalPairingReviewV0? {
        if case let .visible(review, _) = state { return review }
        return nil
    }

    public func publishHostPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        switch state {
        case let .visible(current, _) where current == review:
            return
        case let .visible(current, _), let .publishing(current, _),
             let .resolving(current, _, _):
            throw AgentLocalPairingReviewServiceErrorV0
                .reviewAlreadyVisible(current.reviewID)
        case .invalidated:
            throw AgentLocalPairingReviewServiceErrorV0.invalidated
        case .idle:
            break
        }

        let operationGeneration = try advanceGeneration()
        state = .publishing(review, operationGeneration)
        guard await decisions.containsPendingReview(review),
              isPublishing(review, generation: operationGeneration) else {
            clearIfCurrent(operationGeneration)
            throw AgentLocalPairingReviewServiceErrorV0
                .reviewUnavailable(review.reviewID)
        }

        do {
            try await surface.presentLocalPairingReview(review)
        } catch {
            clearIfCurrent(operationGeneration)
            await surface.withdrawLocalPairingReview(
                reviewID: review.reviewID
            )
            throw error
        }

        guard isPublishing(review, generation: operationGeneration),
              await decisions.containsPendingReview(review),
              isPublishing(review, generation: operationGeneration) else {
            clearIfCurrent(operationGeneration)
            await surface.withdrawLocalPairingReview(
                reviewID: review.reviewID
            )
            throw AgentLocalPairingReviewServiceErrorV0
                .reviewUnavailable(review.reviewID)
        }
        state = .visible(review, operationGeneration)
    }

    public func withdrawHostPairingReview(reviewID: UUID) async {
        guard state.review?.reviewID == reviewID else { return }
        _ = try? advanceGeneration()
        state = .idle
        await surface.withdrawLocalPairingReview(reviewID: reviewID)
    }

    /// Already-authorized implementation of `resolveLocalApproval`. The
    /// command is forwarded unchanged and only exact post-commit replay is
    /// available after the visible review has cleared.
    public func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        switch state {
        case .invalidated:
            throw AgentLocalPairingReviewServiceErrorV0.invalidated
        case .idle:
            if let receipt = try await decisions.replayReceipt(for: command) {
                return receipt
            }
            throw AgentLocalPairingReviewServiceErrorV0
                .reviewUnavailable(command.reviewID)
        case .publishing:
            throw AgentLocalPairingReviewServiceErrorV0.transitionInProgress
        case .resolving:
            if let receipt = try await decisions.replayReceipt(for: command) {
                return receipt
            }
            throw AgentLocalPairingReviewServiceErrorV0.transitionInProgress
        case let .visible(review, _):
            guard command.reviewID == review.reviewID else {
                if let receipt = try await decisions.replayReceipt(
                    for: command
                ) {
                    return receipt
                }
                throw AgentLocalPairingReviewServiceErrorV0
                    .reviewUnavailable(command.reviewID)
            }
            return try await resolve(command, against: review)
        }
    }

    /// Terminal authenticated endpoint loss. A pending review is cancelled;
    /// an already in-flight durable decision is allowed to converge.
    public func invalidate() async {
        guard case .invalidated = state else {
            let review = state.review
            _ = try? advanceGeneration()
            state = .invalidated
            if let review {
                await surface.withdrawLocalPairingReview(
                    reviewID: review.reviewID
                )
                await decisions.cancel(reviewID: review.reviewID)
            }
            return
        }
    }

    private func resolve(
        _ command: LocalPairingDecisionCommandV0,
        against review: LocalPairingReviewV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        let operationGeneration = try advanceGeneration()
        state = .resolving(review, command, operationGeneration)
        do {
            let receipt = try await decisions.handle(command)
            if isResolving(command, generation: operationGeneration) {
                state = .idle
                await surface.withdrawLocalPairingReview(
                    reviewID: review.reviewID
                )
            }
            return receipt
        } catch {
            if isResolving(command, generation: operationGeneration) {
                if isRetryableDecisionError(error) {
                    state = .visible(review, operationGeneration)
                } else {
                    state = .idle
                    await surface.withdrawLocalPairingReview(
                        reviewID: review.reviewID
                    )
                }
            }
            throw error
        }
    }

    private func isRetryableDecisionError(_ error: any Error) -> Bool {
        guard let error = error as?
                AgentLocalPairingDecisionHandlerErrorV0 else {
            return false
        }
        switch error {
        case .invalidClock, .authorityUnavailable, .commandInFlight:
            return true
        case .invalidReview, .duplicateReview, .reviewUnavailable,
             .commandMismatch, .staleReview, .policyChanged,
             .persistenceMismatch:
            return false
        }
    }

    private func advanceGeneration() throws -> UInt64 {
        guard generation < UInt64.max else {
            state = .invalidated
            throw AgentLocalPairingReviewServiceErrorV0.invalidated
        }
        generation += 1
        return generation
    }

    private func isPublishing(
        _ review: LocalPairingReviewV0,
        generation: UInt64
    ) -> Bool {
        guard case let .publishing(current, currentGeneration) = state else {
            return false
        }
        return current == review && currentGeneration == generation
    }

    private func isResolving(
        _ command: LocalPairingDecisionCommandV0,
        generation: UInt64
    ) -> Bool {
        guard case let .resolving(_, current, currentGeneration) = state else {
            return false
        }
        return current == command && currentGeneration == generation
    }

    private func clearIfCurrent(_ operationGeneration: UInt64) {
        switch state {
        case let .publishing(_, current) where current == operationGeneration:
            state = .idle
        case let .visible(_, current) where current == operationGeneration:
            state = .idle
        case let .resolving(_, _, current)
            where current == operationGeneration:
            state = .idle
        default:
            break
        }
    }
}
