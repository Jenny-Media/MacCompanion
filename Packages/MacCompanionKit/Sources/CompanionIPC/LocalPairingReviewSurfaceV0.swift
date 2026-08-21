import Foundation

/// Bundle-independent endpoint capability issued only after a platform
/// adapter has authenticated the visible menu-app connection. The review is
/// already strict-decoded and contains no pairing secret.
public protocol LocalPairingReviewSurfaceV0: Sendable {
    /// Returns only after the exact immutable review is retained for visible
    /// local presentation. Throwing means publication was not acknowledged.
    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws

    /// Removes only the exact review. Withdrawal is idempotent and cannot
    /// remove a later review with another identifier.
    func withdrawLocalPairingReview(reviewID: UUID) async
}
