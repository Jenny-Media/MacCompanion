#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import Foundation

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
    private struct DeviceAdministration {
        let generation: UInt64
        let handler: LocalDeviceRevocationHandlerV0
        let capabilityGrants: LocalCapabilityGrantHandlerV1
        var request: LocalDeviceRevocationReviewRequestV1?
        var reply: LocalDeviceRevocationReviewReplyV1?
    }
    private var deviceAdministration: DeviceAdministration?
    private var highestDeviceAdministrationGeneration: UInt64 = 0
    private var deviceAdministrationFactory: (@Sendable () -> LocalDeviceRevocationHandlerV0)?
    private var capabilityGrantFactory: (@Sendable () -> LocalCapabilityGrantHandlerV1)?

    package init() {}

    package func installDeviceAdministrationFactory(_ factory: @escaping @Sendable () -> LocalDeviceRevocationHandlerV0,
        capabilityGrants: @escaping @Sendable () -> LocalCapabilityGrantHandlerV1) throws {
        guard !terminal, deviceAdministrationFactory == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        deviceAdministrationFactory = factory
        capabilityGrantFactory = capabilityGrants
    }

    package func bindDeviceAdministration(generation: UInt64) throws {
        guard !terminal, deviceAdministration == nil, generation > highestDeviceAdministrationGeneration,
              let deviceAdministrationFactory, let capabilityGrantFactory else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
        highestDeviceAdministrationGeneration = generation
        deviceAdministration = .init(generation: generation, handler: deviceAdministrationFactory(), capabilityGrants: capabilityGrantFactory())
    }

    package func invalidateDeviceAdministration(generation: UInt64) async {
        guard let current = deviceAdministration, current.generation == generation else { return }
        deviceAdministration = nil
        // A successor gets its own handler; late withdrawal cannot erase its review.
        await current.handler.invalidateReview()
        await current.capabilityGrants.invalidateReview()
    }

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
        let administration = deviceAdministration
        deviceAdministration = nil
        deviceAdministrationFactory = nil
        capabilityGrantFactory = nil
        Task { await administration?.handler.invalidateReview() }
        Task { await administration?.capabilityGrants.invalidateReview() }
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

    public func makeCapabilityGrantReview(_ request: LocalCapabilityGrantReviewRequestV1) async throws -> LocalCapabilityGrantReviewV1 {
        guard !terminal, let current = deviceAdministration else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
        let review = try await current.capabilityGrants.makeReview(request)
        guard !terminal, deviceAdministration?.generation == current.generation else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return review
    }

    public func decideCapabilityGrant(_ command: LocalGrantDecisionCommandV0) async throws -> LocalGrantDecisionReceiptV0 {
        guard !terminal, let current = deviceAdministration else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
        return try await current.capabilityGrants.decide(command)
    }

    public func makeDeviceRevocationReview(_ request: LocalDeviceRevocationReviewRequestV1) async throws -> LocalDeviceRevocationReviewReplyV1 {
        guard !terminal, let current = deviceAdministration else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        guard now >= request.requestedAtUnixMilliseconds,
              now - request.requestedAtUnixMilliseconds < 300_000 else {
            throw LocalDeviceRevocationHandlerErrorV0.invalidTime
        }
        if current.request?.commandID == request.commandID {
            guard current.request == request, let reply = current.reply,
                  now < reply.review.expiresAtUnixMilliseconds else {
                throw LocalDeviceRevocationHandlerErrorV0.reviewConflict
            }
            return reply
        }
        await current.handler.invalidateReview()
        guard deviceAdministration?.generation == current.generation, !terminal else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        let review = try await current.handler.makeReview(reviewID: UUID(), deviceID: request.deviceID)
        guard deviceAdministration?.generation == current.generation, !terminal else {
            await current.handler.invalidateReview()
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        let reply = try LocalDeviceRevocationReviewReplyV1(correlationID: request.commandID, review: review)
        try reply.validate(against: request)
        deviceAdministration?.request = request
        deviceAdministration?.reply = reply
        return reply
    }

    public func revokeDevice(_ command: LocalDeviceRevocationCommandV0) async throws -> LocalDeviceRevokedReceiptV0 {
        guard !terminal, let current = deviceAdministration else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
        let receipt = try await current.handler.revoke(command)
        if deviceAdministration?.generation == current.generation {
            deviceAdministration?.request = nil
            deviceAdministration?.reply = nil
        }
        return receipt
    }
}
#endif
