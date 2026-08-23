#if os(macOS)
import CompanionIPC
import CompanionInteractiveWire
import Foundation

/// Platform-owned endpoint for one exact, already-authenticated menu
/// generation. A conformer must bind every operation to that transport
/// generation and make invalidation terminal, including withdrawal of any
/// presentation retained by the menu process. Invalidation is idempotent
/// because fail-closed transport races may request it more than once.
///
/// An invalidation callback that must fence the router terminally uses only
/// its MacLocalXPCMenuSurfaceTerminalFenceV1 capability. Endpoint code must
/// not retain the owner router, because the router's finish() is the external
/// completion barrier that necessarily includes this endpoint's invalidation.
package protocol MacLocalXPCAuthenticatedMenuSurfaceEndpointV1:
    AnyObject,
    LocalHostIdentityRecoverySurfaceV0,
    LocalPairingReviewSurfaceV0,
    MacLocalXPCInteractiveLeaseSendingV1,
    MacLocalXPCInteractiveInputSendingV1,
    Sendable
{
    func installAuthenticatedMenuTerminalFence(
        _ fence: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) async
    func invalidateAuthenticatedMenuSurface() async
}

package enum MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidGeneration
    case duplicateGeneration(UInt64)
    case endpointReusedAcrossGenerations(UInt64)
    case staleGeneration(UInt64)
    case invalidated
    case authorizationPolicyRejected
}

/// The only router lifecycle operation issued to an authenticated menu
/// endpoint. Requesting termination is deliberately non-waiting: endpoint
/// invalidation may be part of the owner's awaitable finish barrier.
package struct MacLocalXPCMenuSurfaceTerminalFenceV1: Sendable {
    private let request: @Sendable () async -> Void

    fileprivate init(
        router: MacLocalXPCAuthenticatedMenuSurfaceRouterV1,
        generation: UInt64,
        token: UUID
    ) {
        request = { [weak router] in
            await router?.requestFinishFromEndpoint(
                generation: generation,
                token: token
            )
        }
    }

    package func requestFinish() async {
        await request()
    }
}

/// The only presentation capabilities a later Agent product may receive from
/// one exact authenticated menu generation. It deliberately exposes neither
/// the transport endpoint nor an authentication flag.
package struct MacLocalXPCAuthenticatedMenuSurfacesV1: Sendable {
    package let generation: UInt64
    package let pairingReviews: any LocalPairingReviewSurfaceV0
    package let hostIdentityRecovery:
        any LocalHostIdentityRecoverySurfaceV0
    package let interactiveRuntime:
        any MacLocalXPCInteractiveLeaseSendingV1
    package let interactiveInput:
        any MacLocalXPCInteractiveInputSendingV1
}

extension MacLocalXPCAuthenticatedMenuSurfaceEndpointV1 {
    package func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    package func installInteractiveLease(
        _: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    package func renewInteractiveLease(
        _: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    package func revokeInteractiveLease(
        _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }

    package func applyInteractiveInput(
        _: InteractiveInputEnvelope
    ) async throws {
        throw MacLocalXPCInteractiveRoleDataErrorV1.unavailable
    }
}

private struct MacLocalXPCPairingReviewSurfaceFacetV1:
    LocalPairingReviewSurfaceV0
{
    let router: MacLocalXPCAuthenticatedMenuSurfaceRouterV1
    let generation: UInt64
    let token: UUID

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        try await router.presentPairingReview(
            review,
            generation: generation,
            token: token
        )
    }

    func withdrawLocalPairingReview(reviewID: UUID) async {
        await router.withdrawPairingReview(
            reviewID: reviewID,
            generation: generation,
            token: token
        )
    }
}

private struct MacLocalXPCHostIdentityRecoverySurfaceFacetV1:
    LocalHostIdentityRecoverySurfaceV0
{
    let router: MacLocalXPCAuthenticatedMenuSurfaceRouterV1
    let generation: UInt64
    let token: UUID

    func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        try await router.presentRecoveryReview(
            review,
            generation: generation,
            token: token
        )
    }

    func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        try await router.presentRecoveryResume(
            command,
            generation: generation,
            token: token
        )
    }

    func withdrawHostIdentityRecovery(reviewID: UUID) async {
        await router.withdrawRecovery(
            reviewID: reviewID,
            generation: generation,
            token: token
        )
    }
}

/// Converts a transport-authenticated menu lifetime into two narrow
/// Agent-to-menu presentation facets. Replacement fences the old generation
/// before returning the new facets. Every suspended acknowledgement is checked
/// again after resumption, so a late success cannot authorize stale state.
package actor MacLocalXPCAuthenticatedMenuSurfaceRouterV1 {
    package typealias EndpointTerminalHandler = @Sendable (
        UInt64
    ) async -> Void

    private final class EndpointIdentityRecord {
        weak var endpoint: AnyObject?

        init(
            _ endpoint:
                any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
        ) {
            self.endpoint = endpoint
        }
    }

    private struct Current: Sendable {
        let generation: UInt64
        let token: UUID
        let endpoint:
            any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
    }

    private var current: Current?
    private var terminal = false
    private var highestGeneration: UInt64 = 0
    private var cleanupBarrier:
        (token: UUID, task: Task<Void, Never>)?
    private var activationBarrier:
        (token: UUID, task: Task<Void, Never>)?
    private var finishTask: Task<Void, Never>?
    private var acceptedEndpointIdentities: [EndpointIdentityRecord] = []
    private let onEndpointTerminal: EndpointTerminalHandler

    package init(
        onEndpointTerminal: @escaping EndpointTerminalHandler = { _ in }
    ) {
        self.onEndpointTerminal = onEndpointTerminal
    }

    /// Constructs a candidate endpoint only after numeric/policy pre-admission.
    /// A newly accepted endpoint receives its exact terminal fence after
    /// duplicate identity is resolved; an exact retry keeps its original.
    package func bindAuthenticated(
        generation: UInt64,
        endpointFactory: @Sendable ()
            -> any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
    ) async throws -> MacLocalXPCAuthenticatedMenuSurfacesV1 {
        guard !terminal else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1.invalidated
        }
        guard generation > 0 else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .invalidGeneration
        }
        if current?.generation != generation {
            guard generation > highestGeneration else {
                throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                    .staleGeneration(generation)
            }
        }
        guard Self.authorizesPresentationMethods else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .authorizationPolicyRejected
        }
        let candidateToken = UUID()
        let endpoint = endpointFactory()
        return try await bindEndpoint(
            generation: generation,
            candidateToken: candidateToken,
            endpoint: endpoint
        )
    }

    private func bindEndpoint(
        generation: UInt64,
        candidateToken: UUID,
        endpoint:
            any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
    ) async throws -> MacLocalXPCAuthenticatedMenuSurfacesV1 {
        if let active = current,
           active.generation == generation,
           active.endpoint === endpoint {
            if let activationBarrier,
               activationBarrier.token == active.token {
                await activationBarrier.task.value
            }
            guard isCurrent(
                generation: generation,
                token: active.token
            ) else {
                throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                    .staleGeneration(generation)
            }
            return surfaces(
                generation: generation,
                token: active.token
            )
        }
        if let active = current,
           active.endpoint === endpoint {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .endpointReusedAcrossGenerations(generation)
        }
        acceptedEndpointIdentities.removeAll { $0.endpoint == nil }
        guard !acceptedEndpointIdentities.contains(where: {
            $0.endpoint === endpoint
        }) else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .endpointReusedAcrossGenerations(generation)
        }
        guard current?.generation != generation else {
            await endpoint.invalidateAuthenticatedMenuSurface()
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .duplicateGeneration(generation)
        }
        let replaced = current
        let token = candidateToken
        let priorCleanup = cleanupBarrier?.task
        acceptedEndpointIdentities.append(
            EndpointIdentityRecord(endpoint)
        )
        current = Current(
            generation: generation,
            token: token,
            endpoint: endpoint
        )
        highestGeneration = generation
        let barrier = Task {
            await endpoint.installAuthenticatedMenuTerminalFence(
                MacLocalXPCMenuSurfaceTerminalFenceV1(
                    router: self,
                    generation: generation,
                    token: token
                )
            )
            if let priorCleanup {
                await priorCleanup.value
            }
            if let replaced {
                await replaced.endpoint
                    .invalidateAuthenticatedMenuSurface()
            }
        }
        let cleanupToken = UUID()
        cleanupBarrier = (cleanupToken, barrier)
        activationBarrier = (token, barrier)
        await barrier.value
        if cleanupBarrier?.token == cleanupToken {
            cleanupBarrier = nil
        }
        if activationBarrier?.token == token {
            activationBarrier = nil
        }
        guard isCurrent(generation: generation, token: token) else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(generation)
        }
        return surfaces(generation: generation, token: token)
    }

    private func surfaces(
        generation: UInt64,
        token: UUID
    ) -> MacLocalXPCAuthenticatedMenuSurfacesV1 {
        precondition(
            current?.generation == generation && current?.token == token
        )
        return MacLocalXPCAuthenticatedMenuSurfacesV1(
            generation: generation,
            pairingReviews: MacLocalXPCPairingReviewSurfaceFacetV1(
                router: self,
                generation: generation,
                token: token
            ),
            hostIdentityRecovery:
                MacLocalXPCHostIdentityRecoverySurfaceFacetV1(
                    router: self,
                    generation: generation,
                    token: token
                ),
            interactiveRuntime: current!.endpoint,
            interactiveInput: current!.endpoint
        )
    }

    @discardableResult
    package func invalidate(generation: UInt64) async -> Bool {
        guard let active = current,
              active.generation == generation else {
            return false
        }
        current = nil
        activationBarrier = nil
        let priorCleanup = cleanupBarrier?.task
        let task = Task {
            if let priorCleanup {
                await priorCleanup.value
            }
            await active.endpoint
                .invalidateAuthenticatedMenuSurface()
        }
        let cleanupToken = UUID()
        cleanupBarrier = (cleanupToken, task)
        await task.value
        if cleanupBarrier?.token == cleanupToken {
            cleanupBarrier = nil
        }
        return true
    }

    fileprivate func requestFinishFromEndpoint(
        generation: UInt64,
        token: UUID
    ) async {
        guard current?.generation == generation,
              current?.token == token else {
            return
        }
        _ = beginFinish()
        // Do not await the endpoint cleanup task here: the endpoint is waiting
        // for this callback and cleanup calls back into that same endpoint.
        // The product-level revocation callback is independent of the endpoint
        // actor and must complete before terminal-fence admission returns.
        await onEndpointTerminal(generation)
    }

    /// Marks the router terminal and waits for all endpoint retirement.
    /// Only an external lifecycle owner may await this completion barrier.
    package func finish() async {
        await beginFinish().value
    }

    private func beginFinish() -> Task<Void, Never> {
        if let finishTask { return finishTask }
        terminal = true
        let active = current
        current = nil
        activationBarrier = nil
        let priorCleanup = cleanupBarrier?.task
        let task = Task {
            if let priorCleanup {
                await priorCleanup.value
            }
            if let active {
                await active.endpoint
                    .invalidateAuthenticatedMenuSurface()
            }
        }
        cleanupBarrier = (UUID(), task)
        finishTask = task
        return task
    }

    package func currentGeneration() -> UInt64? {
        current?.generation
    }

    fileprivate func presentPairingReview(
        _ review: LocalPairingReviewV0,
        generation: UInt64,
        token: UUID
    ) async throws {
        let active = try requireCurrent(
            generation: generation,
            token: token
        )
        try await active.endpoint.presentLocalPairingReview(review)
        guard isCurrent(
            generation: generation,
            token: active.token
        ) else {
            await active.endpoint.withdrawLocalPairingReview(
                reviewID: review.reviewID
            )
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(generation)
        }
    }

    fileprivate func withdrawPairingReview(
        reviewID: UUID,
        generation: UInt64,
        token: UUID
    ) async {
        guard let active = current,
              active.generation == generation,
              active.token == token else {
            return
        }
        await active.endpoint.withdrawLocalPairingReview(
            reviewID: reviewID
        )
    }

    fileprivate func presentRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0,
        generation: UInt64,
        token: UUID
    ) async throws {
        let active = try requireCurrent(
            generation: generation,
            token: token
        )
        try await active.endpoint.presentHostIdentityRecoveryReview(review)
        guard isCurrent(
            generation: generation,
            token: active.token
        ) else {
            await active.endpoint.withdrawHostIdentityRecovery(
                reviewID: review.reviewID
            )
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(generation)
        }
    }

    fileprivate func presentRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0,
        generation: UInt64,
        token: UUID
    ) async throws {
        let active = try requireCurrent(
            generation: generation,
            token: token
        )
        try await active.endpoint.presentHostIdentityRecoveryResume(command)
        guard isCurrent(
            generation: generation,
            token: active.token
        ) else {
            await active.endpoint.withdrawHostIdentityRecovery(
                reviewID: command.review.reviewID
            )
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(generation)
        }
    }

    fileprivate func withdrawRecovery(
        reviewID: UUID,
        generation: UInt64,
        token: UUID
    ) async {
        guard let active = current,
              active.generation == generation,
              active.token == token else {
            return
        }
        await active.endpoint.withdrawHostIdentityRecovery(
            reviewID: reviewID
        )
    }

    private func requireCurrent(
        generation: UInt64,
        token: UUID
    ) throws -> Current {
        guard !terminal else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1.invalidated
        }
        guard let active = current,
              active.generation == generation,
              active.token == token else {
            throw MacLocalXPCAuthenticatedMenuSurfaceRouterErrorV1
                .staleGeneration(generation)
        }
        return active
    }

    private func isCurrent(
        generation: UInt64,
        token: UUID
    ) -> Bool {
        !terminal
            && current?.generation == generation
            && current?.token == token
    }

    private static let authorizesPresentationMethods: Bool = {
        for method in [
            LocalIPCMethod.publishPairingReview,
            .withdrawPairingReview,
            .publishHostIdentityRecoveryReview,
            .publishHostIdentityRecoveryResume,
            .withdrawHostIdentityRecovery,
        ] {
            do {
                try LocalIPCAuthorizationPolicy.authorize(
                    authenticatedCaller: .agent,
                    endpoint: .menuApp,
                    method: method,
                    version: .init()
                )
            } catch {
                return false
            }
        }
        return true
    }()
}
#endif
