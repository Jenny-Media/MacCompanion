import CompanionHostPlatform
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation

public enum AgentLocalHostIdentityRecoveryServiceErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidTime
    case identityUnavailable
    case reviewConflict
    case reviewNotCurrent
    case recoveryResultMismatch
}

package protocol AgentHostIdentityRecoveryExecutingV0: Sendable {
    func recover(
        intent: StoredHostIdentityRecoveryIntent
    ) async throws -> StoredHostIdentityRecord
}

package struct SecurityAgentHostIdentityRecoveryExecutorV0:
    AgentHostIdentityRecoveryExecutingV0
{
    let coordinator: SecurityHostIdentityRecoveryCoordinatorV0

    package func recover(
        intent: StoredHostIdentityRecoveryIntent
    ) async throws -> StoredHostIdentityRecord {
        try await coordinator.recover(
            intent: intent
        ).record
    }
}

/// Bundle-independent local recovery admission issued only to the platform
/// adapter that has already authenticated and authorized the menu-app peer.
/// Caller identity is deliberately absent here; final signed XPC owns it.
public actor AgentLocalHostIdentityRecoveryServiceV0 {
    private let store: SQLiteSecurityStore
    private let executor: any AgentHostIdentityRecoveryExecutingV0
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private var activeReview: LocalHostIdentityRecoveryReviewV0?

    package init(
        store: SQLiteSecurityStore,
        executor: any AgentHostIdentityRecoveryExecutingV0,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
    ) {
        self.store = store
        self.executor = executor
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
    }

    /// Creates one immutable review from current durable public identity facts.
    /// Platform peer authentication and review delivery happen before and after
    /// this boundary respectively.
    public func makeReview(
        reviewID: UUID,
        cause: LocalHostIdentityRecoveryCauseV0
    ) async throws -> LocalHostIdentityRecoveryReviewV0 {
        let now = wallNowUnixMilliseconds()
        guard now >= 0, now <= 9_007_199_254_440_991 else {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0.invalidTime
        }
        guard let identity = try await store.hostIdentity(),
              identity.state == .ready,
              identity.recoveryID == nil else {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .identityUnavailable
        }
        let review = try LocalHostIdentityRecoveryReviewV0(
            reviewID: reviewID,
            hostID: identity.hostID,
            hostFingerprint: WireFingerprint(identity.hostFingerprint),
            cause: cause,
            createdAtUnixMilliseconds: now,
            expiresAtUnixMilliseconds: now + 300_000
        )
        if let activeReview {
            guard activeReview == review else {
                throw AgentLocalHostIdentityRecoveryServiceErrorV0
                    .reviewConflict
            }
            return activeReview
        }
        activeReview = review
        return review
    }

    /// Accepts only the exact active review before fencing. Once a matching
    /// durable fence or completion exists, the exact command may resume after
    /// process/response loss without opening a second recovery.
    public func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        let intent = try storedIntent(command)
        if let persisted = try await store.hostIdentityRecoveryReceipt(),
           persisted.recoveryID == command.recoveryID {
            guard try await store.hostIdentityRecoveryIntent() == intent else {
                throw AgentLocalHostIdentityRecoveryServiceErrorV0
                    .reviewNotCurrent
            }
            return try receipt(
                persisted: persisted,
                command: command
            )
        }

        guard let identity = try await store.hostIdentity(),
              identity.hostID == command.review.hostID,
              identity.hostFingerprint
                == command.review.hostFingerprint.rawValue else {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .reviewNotCurrent
        }
        switch identity.state {
        case .ready:
            let now = wallNowUnixMilliseconds()
            guard now >= command.review.createdAtUnixMilliseconds,
                  now < command.review.expiresAtUnixMilliseconds,
                  activeReview == command.review else {
                throw AgentLocalHostIdentityRecoveryServiceErrorV0
                    .reviewNotCurrent
            }
        case .fencedForReplacement:
            guard identity.recoveryID == command.recoveryID,
                  try await store.hostIdentityRecoveryIntent() == intent else {
                throw AgentLocalHostIdentityRecoveryServiceErrorV0
                    .reviewNotCurrent
            }
        }

        let replacement = try await executor.recover(
            intent: intent
        )
        guard replacement.state == .ready,
              replacement.recoveryID == nil,
              replacement.hostID != command.review.hostID,
              replacement.hostFingerprint
                != command.review.hostFingerprint.rawValue else {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .recoveryResultMismatch
        }
        activeReview = nil
        let receipt = try LocalHostIdentityRecoveredReceiptV0(
            correlationID: command.commandID,
            recoveryID: command.recoveryID,
            replacedHostID: command.review.hostID,
            newHostID: replacement.hostID,
            newHostFingerprint: WireFingerprint(
                replacement.hostFingerprint
            ),
            completedAtUnixMilliseconds:
                replacement.updatedAtUnixMilliseconds
        )
        do {
            try receipt.validate(against: command)
        } catch {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .recoveryResultMismatch
        }
        return receipt
    }

    public func invalidateReview() {
        activeReview = nil
    }

    /// Reconstructs only the exact review durably accepted before the fence.
    /// A ready identity without a completed matching receipt has no resumable
    /// review, and a legacy fence without an intent remains unavailable.
    public func resumableReview()
        async throws -> LocalHostIdentityRecoveryReviewV0?
    {
        try await resumableCommand()?.review
    }

    /// Returns the exact durably accepted command for the distinct
    /// Agent-to-menu resume delivery after either process restarts.
    public func resumableCommand()
        async throws -> LocalHostIdentityRecoveryCommandV0?
    {
        guard let intent = try await store.hostIdentityRecoveryIntent(),
              let identity = try await store.hostIdentity() else {
            return nil
        }
        let completed = try await store.hostIdentityRecoveryReceipt()
        guard (identity.state == .fencedForReplacement
                && identity.recoveryID == intent.recoveryID)
                || (identity.state == .ready
                    && completed?.recoveryID == intent.recoveryID) else {
            return nil
        }
        return try LocalHostIdentityRecoveryCommandV0(
            commandID: intent.commandID,
            recoveryID: intent.recoveryID,
            review: review(intent),
            confirmedAtUnixMilliseconds:
                intent.confirmedAtUnixMilliseconds
        )
    }

    private func receipt(
        persisted: StoredHostIdentityRecoveryReceipt,
        command: LocalHostIdentityRecoveryCommandV0
    ) throws -> LocalHostIdentityRecoveredReceiptV0 {
        guard persisted.replacedHostID == command.review.hostID,
              persisted.replacedHostFingerprint
                == command.review.hostFingerprint.rawValue else {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .reviewNotCurrent
        }
        let receipt = try LocalHostIdentityRecoveredReceiptV0(
            correlationID: command.commandID,
            recoveryID: persisted.recoveryID,
            replacedHostID: persisted.replacedHostID,
            newHostID: persisted.newHostID,
            newHostFingerprint: WireFingerprint(
                persisted.newHostFingerprint
            ),
            completedAtUnixMilliseconds:
                persisted.completedAtUnixMilliseconds
        )
        do {
            try receipt.validate(against: command)
        } catch {
            throw AgentLocalHostIdentityRecoveryServiceErrorV0
                .recoveryResultMismatch
        }
        return receipt
    }

    private func storedIntent(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) throws -> StoredHostIdentityRecoveryIntent {
        try StoredHostIdentityRecoveryIntent(
            commandID: command.commandID,
            recoveryID: command.recoveryID,
            reviewID: command.review.reviewID,
            expectedHostID: command.review.hostID,
            expectedHostFingerprint:
                command.review.hostFingerprint.rawValue,
            cause: storedCause(command.review.cause),
            reviewCreatedAtUnixMilliseconds:
                command.review.createdAtUnixMilliseconds,
            reviewExpiresAtUnixMilliseconds:
                command.review.expiresAtUnixMilliseconds,
            confirmedAtUnixMilliseconds:
                command.confirmedAtUnixMilliseconds
        )
    }

    private func review(
        _ intent: StoredHostIdentityRecoveryIntent
    ) throws -> LocalHostIdentityRecoveryReviewV0 {
        try LocalHostIdentityRecoveryReviewV0(
            reviewID: intent.reviewID,
            hostID: intent.expectedHostID,
            hostFingerprint: WireFingerprint(
                intent.expectedHostFingerprint
            ),
            cause: localCause(intent.cause),
            createdAtUnixMilliseconds:
                intent.reviewCreatedAtUnixMilliseconds,
            expiresAtUnixMilliseconds:
                intent.reviewExpiresAtUnixMilliseconds
        )
    }

    private func storedCause(
        _ cause: LocalHostIdentityRecoveryCauseV0
    ) -> StoredHostIdentityRecoveryCause {
        switch cause {
        case .keyUnavailable: .keyUnavailable
        case .suspectedCompromise: .suspectedCompromise
        case .userRequestedReset: .userRequestedReset
        }
    }

    private func localCause(
        _ cause: StoredHostIdentityRecoveryCause
    ) -> LocalHostIdentityRecoveryCauseV0 {
        switch cause {
        case .keyUnavailable: .keyUnavailable
        case .suspectedCompromise: .suspectedCompromise
        case .userRequestedReset: .userRequestedReset
        }
    }
}
