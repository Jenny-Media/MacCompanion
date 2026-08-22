#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatform
import Foundation

package enum MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case staleGeneration(UInt64)
    case terminal
}

/// Stable, narrow Agent-side authority above replaceable authenticated menu
/// generations. It lets the one-use primary Agent graph retain only pairing
/// and recovery presentation capabilities while menu-process generations are
/// replaced independently. It never exposes an endpoint, transport, caller
/// role, status reader, or Control capability.
@available(macOS 26.0, *)
package actor MacAgentAuthenticatedMenuSurfaceAuthorityV1:
    LocalPairingReviewSurfaceV0,
    LocalHostIdentityRecoverySurfaceV0
{
    private var current: MacLocalXPCAuthenticatedMenuSurfacesV1?
    private var highestGeneration: UInt64 = 0
    private var terminal = false
    private var availabilityWaiters: [
        UUID: CheckedContinuation<UInt64, Error>
    ] = [:]

    package init() {}

    package func install(
        _ surfaces: MacLocalXPCAuthenticatedMenuSurfacesV1
    ) throws {
        guard !terminal else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.terminal
        }
        guard surfaces.generation > highestGeneration else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .staleGeneration(surfaces.generation)
        }
        highestGeneration = surfaces.generation
        current = surfaces
        let waiters = availabilityWaiters.values
        availabilityWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: surfaces.generation)
        }
    }

    @discardableResult
    package func invalidate(generation: UInt64) -> Bool {
        guard current?.generation == generation else { return false }
        current = nil
        return true
    }

    package func finish() {
        terminal = true
        current = nil
        let waiters = availabilityWaiters.values
        availabilityWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(
                throwing:
                    MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.terminal
            )
        }
    }

    package func currentGeneration() -> UInt64? { current?.generation }

    package func waitForAvailableGeneration() async throws -> UInt64 {
        try Task.checkCancellation()
        guard !terminal else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1.terminal
        }
        if let generation = current?.generation { return generation }
        let waiterID = UUID()
        let generation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                availabilityWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task { await self.cancelAvailabilityWaiter(waiterID) }
        }
        try Task.checkCancellation()
        return generation
    }

    private func cancelAvailabilityWaiter(_ waiterID: UUID) {
        availabilityWaiters.removeValue(forKey: waiterID)?.resume(
            throwing: CancellationError()
        )
    }

    package func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        guard let selected = current else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .unavailable
        }
        try await selected.pairingReviews.presentLocalPairingReview(review)
        guard current?.generation == selected.generation else {
            await selected.pairingReviews.withdrawLocalPairingReview(
                reviewID: review.reviewID
            )
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .staleGeneration(selected.generation)
        }
    }

    package func withdrawLocalPairingReview(reviewID: UUID) async {
        guard let selected = current else { return }
        await selected.pairingReviews.withdrawLocalPairingReview(
            reviewID: reviewID
        )
    }

    package func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        guard let selected = current else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .unavailable
        }
        try await selected.hostIdentityRecovery
            .presentHostIdentityRecoveryReview(review)
        guard current?.generation == selected.generation else {
            await selected.hostIdentityRecovery.withdrawHostIdentityRecovery(
                reviewID: review.reviewID
            )
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .staleGeneration(selected.generation)
        }
    }

    package func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        guard let selected = current else {
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .unavailable
        }
        try await selected.hostIdentityRecovery
            .presentHostIdentityRecoveryResume(command)
        guard current?.generation == selected.generation else {
            await selected.hostIdentityRecovery.withdrawHostIdentityRecovery(
                reviewID: command.review.reviewID
            )
            throw MacAgentAuthenticatedMenuSurfaceAuthorityErrorV1
                .staleGeneration(selected.generation)
        }
    }

    package func withdrawHostIdentityRecovery(reviewID: UUID) async {
        guard let selected = current else { return }
        await selected.hostIdentityRecovery.withdrawHostIdentityRecovery(
            reviewID: reviewID
        )
    }
}
#endif
