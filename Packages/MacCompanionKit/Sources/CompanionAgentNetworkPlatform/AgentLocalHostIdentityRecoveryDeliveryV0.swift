import CompanionIPC
import Foundation

public enum AgentLocalHostIdentityRecoveryDeliveryErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidated
    case unavailable
    case alreadyVisible(UUID)
    case transitionInProgress
}

/// Connection-scoped delivery and admission for an already-authenticated,
/// already-authorized menu endpoint. Durable recovery semantics remain owned
/// by `AgentLocalHostIdentityRecoveryServiceV0`.
public actor AgentLocalHostIdentityRecoveryDeliveryV0 {
    private enum State: Sendable {
        case idle
        case preparing(UInt64)
        case publishingReview(
            LocalHostIdentityRecoveryReviewV0,
            UInt64
        )
        case visibleReview(LocalHostIdentityRecoveryReviewV0, UInt64)
        case publishingResume(
            LocalHostIdentityRecoveryCommandV0,
            UInt64
        )
        case visibleResume(LocalHostIdentityRecoveryCommandV0, UInt64)
        case resolving(LocalHostIdentityRecoveryCommandV0, UInt64)
        case completed(LocalHostIdentityRecoveredReceiptV0, UInt64)
        case acknowledging(LocalHostIdentityRecoveredReceiptV0, UInt64)
        case acknowledged(LocalHostIdentityRecoveredReceiptV0)
        case invalidated

        var reviewID: UUID? {
            switch self {
            case let .publishingReview(review, _),
                 let .visibleReview(review, _):
                review.reviewID
            case let .publishingResume(command, _),
                 let .visibleResume(command, _),
                 let .resolving(command, _):
                command.review.reviewID
            case .idle, .preparing, .completed, .acknowledging,
                    .acknowledged, .invalidated:
                nil
            }
        }
    }

    private let recovery: AgentLocalHostIdentityRecoveryServiceV0
    private let surface: any LocalHostIdentityRecoverySurfaceV0
    private var state: State = .idle
    private var generation: UInt64 = 0

    public init(
        recovery: AgentLocalHostIdentityRecoveryServiceV0,
        alreadyAuthorizedSurface: any LocalHostIdentityRecoverySurfaceV0
    ) {
        self.recovery = recovery
        surface = alreadyAuthorizedSurface
    }

    public func publishReview(
        reviewID: UUID,
        cause: LocalHostIdentityRecoveryCauseV0
    ) async throws -> LocalHostIdentityRecoveryReviewV0 {
        let operationGeneration = try beginPreparation()
        let review: LocalHostIdentityRecoveryReviewV0
        do {
            review = try await recovery.makeReview(
                reviewID: reviewID,
                cause: cause
            )
        } catch {
            clearIfPreparing(operationGeneration)
            throw error
        }
        guard isPreparing(operationGeneration) else {
            await recovery.invalidateReview()
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        }
        state = .publishingReview(review, operationGeneration)
        do {
            try await surface.presentHostIdentityRecoveryReview(review)
        } catch {
            clearIfCurrent(operationGeneration)
            await recovery.invalidateReview()
            await surface.withdrawHostIdentityRecovery(
                reviewID: review.reviewID
            )
            throw error
        }
        guard isPublishingReview(review, generation: operationGeneration)
        else {
            await surface.withdrawHostIdentityRecovery(
                reviewID: review.reviewID
            )
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        }
        state = .visibleReview(review, operationGeneration)
        return review
    }

    public func publishResumable()
        async throws -> LocalHostIdentityRecoveryCommandV0
    {
        let operationGeneration = try beginPreparation()
        guard let command = try await recovery.resumableCommand() else {
            clearIfPreparing(operationGeneration)
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.unavailable
        }
        guard isPreparing(operationGeneration) else {
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        }
        state = .publishingResume(command, operationGeneration)
        do {
            try await surface.presentHostIdentityRecoveryResume(command)
        } catch {
            clearIfCurrent(operationGeneration)
            await surface.withdrawHostIdentityRecovery(
                reviewID: command.review.reviewID
            )
            throw error
        }
        guard isPublishingResume(command, generation: operationGeneration)
        else {
            await surface.withdrawHostIdentityRecovery(
                reviewID: command.review.reviewID
            )
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        }
        state = .visibleResume(command, operationGeneration)
        return command
    }

    public func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        switch state {
        case let .visibleReview(review, _) where review == command.review:
            break
        case let .visibleResume(current, _) where current == command:
            break
        case .invalidated:
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        case .preparing, .publishingReview, .publishingResume, .resolving,
                .acknowledging:
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0
                .transitionInProgress
        case .idle, .visibleReview, .visibleResume, .completed, .acknowledged:
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.unavailable
        }

        let operationGeneration = try advanceGeneration()
        state = .resolving(command, operationGeneration)
        do {
            let receipt = try await recovery.recoverHostIdentity(command)
            guard isResolving(command, generation: operationGeneration) else {
                throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
            }
            state = .completed(receipt, operationGeneration)
            return receipt
        } catch {
            let resumable = try? await recovery.resumableCommand()
            guard isResolving(command, generation: operationGeneration) else {
                throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
            }
            if resumable == command {
                state = .visibleResume(command, operationGeneration)
            } else {
                state = .visibleReview(command.review, operationGeneration)
            }
            throw error
        }
    }

    public func acknowledgeCompletion(
        _ receipt: LocalHostIdentityRecoveredReceiptV0
    ) async throws {
        guard case let .completed(current, _) = state,
              current == receipt else {
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.unavailable
        }
        let operationGeneration = try advanceGeneration()
        state = .acknowledging(receipt, operationGeneration)
        do {
            try await recovery.acknowledgeCompletion(receipt)
            if case let .acknowledging(current, generation) = state,
               current == receipt,
               generation == operationGeneration {
                state = .acknowledged(receipt)
            }
        } catch {
            guard case let .acknowledging(current, generation) = state,
                  current == receipt,
                  generation == operationGeneration else {
                throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
            }
            state = .completed(receipt, operationGeneration)
            throw error
        }
    }

    public func invalidate() async {
        guard case .invalidated = state else {
            let reviewID = state.reviewID
            _ = try? advanceGeneration()
            state = .invalidated
            await recovery.invalidateReview()
            if let reviewID {
                await surface.withdrawHostIdentityRecovery(
                    reviewID: reviewID
                )
            }
            return
        }
    }

    private func beginPreparation() throws -> UInt64 {
        switch state {
        case .idle:
            let next = try advanceGeneration()
            state = .preparing(next)
            return next
        case let .visibleReview(review, _):
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0
                .alreadyVisible(review.reviewID)
        case let .visibleResume(command, _):
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0
                .alreadyVisible(command.review.reviewID)
        case .invalidated:
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        case .preparing, .publishingReview, .publishingResume, .resolving,
                .completed, .acknowledging, .acknowledged:
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0
                .transitionInProgress
        }
    }

    private func advanceGeneration() throws -> UInt64 {
        guard generation < UInt64.max else {
            state = .invalidated
            throw AgentLocalHostIdentityRecoveryDeliveryErrorV0.invalidated
        }
        generation += 1
        return generation
    }

    private func isPreparing(_ operationGeneration: UInt64) -> Bool {
        guard case let .preparing(current) = state else { return false }
        return current == operationGeneration
    }

    private func isPublishingReview(
        _ review: LocalHostIdentityRecoveryReviewV0,
        generation: UInt64
    ) -> Bool {
        guard case let .publishingReview(current, currentGeneration) = state
        else { return false }
        return current == review && currentGeneration == generation
    }

    private func isPublishingResume(
        _ command: LocalHostIdentityRecoveryCommandV0,
        generation: UInt64
    ) -> Bool {
        guard case let .publishingResume(current, currentGeneration) = state
        else { return false }
        return current == command && currentGeneration == generation
    }

    private func isResolving(
        _ command: LocalHostIdentityRecoveryCommandV0,
        generation: UInt64
    ) -> Bool {
        guard case let .resolving(current, currentGeneration) = state
        else { return false }
        return current == command && currentGeneration == generation
    }

    private func clearIfPreparing(_ operationGeneration: UInt64) {
        guard isPreparing(operationGeneration) else { return }
        state = .idle
    }

    private func clearIfCurrent(_ operationGeneration: UInt64) {
        switch state {
        case let .preparing(current) where current == operationGeneration,
             let .publishingReview(_, current)
                where current == operationGeneration,
             let .publishingResume(_, current)
                where current == operationGeneration,
             let .visibleReview(_, current)
                where current == operationGeneration,
             let .visibleResume(_, current)
                where current == operationGeneration,
             let .resolving(_, current)
                where current == operationGeneration:
            state = .idle
        case let .completed(_, current)
            where current == operationGeneration,
             let .acknowledging(_, current)
            where current == operationGeneration:
            state = .idle
        default:
            break
        }
    }
}
