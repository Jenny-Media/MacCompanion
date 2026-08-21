import Foundation

/// Already-authorized Agent-to-menu delivery surface. Peer authentication and
/// method authorization are platform-adapter responsibilities outside this
/// bundle-independent boundary.
public protocol LocalHostIdentityRecoverySurfaceV0: Sendable {
    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws

    func withdrawHostIdentityRecovery(reviewID: UUID) async
}
