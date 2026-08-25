#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionIPC
import CompanionLocalXPCPlatform

/// Stable local-XPC authority whose backing pairing aggregate is installed
/// only after the complete network product has been composed. Before that
/// boundary every command fails closed; the transport never owns or creates
/// pairing business authority.
@available(macOS 26.0, *)
package actor MacAgentLocalPairingCommandAuthorityV1:
    MacLocalXPCMenuPairingCommandHandlingV1
{
    private var product: AgentNetworkPairingProductCompositionV0?
    private var interactiveControlGrants:
        LocalInteractiveControlGrantHandlerV0?
    private var terminal = false

    package init() {}

    package func install(
        _ product: AgentNetworkPairingProductCompositionV0
    ) throws {
        guard !terminal, self.product == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        self.product = product
    }

    package func installInteractiveControlGrantHandler(
        _ handler: LocalInteractiveControlGrantHandlerV0
    ) throws {
        guard !terminal, interactiveControlGrants == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        interactiveControlGrants = handler
    }

    package func finish() {
        terminal = true
        product = nil
        let interactiveControlGrants = self.interactiveControlGrants
        self.interactiveControlGrants = nil
        Task { await interactiveControlGrants?.invalidateReview() }
    }

    public func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        guard !terminal, let product else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.localPairingSessions.create(command)
    }

    public func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        guard !terminal, let product else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.localPairingSessions.dismiss(command)
    }

    public func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        guard !terminal, let product else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.localPairingReviews
            .resolveLocalApproval(command)
    }

    public func makeInteractiveControlGrantReview(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0 {
        guard !terminal, let interactiveControlGrants else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await interactiveControlGrants.makeReview(request)
    }

    public func decideInteractiveControlGrant(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        guard !terminal, let interactiveControlGrants else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await interactiveControlGrants.decide(command)
    }
}
#endif
