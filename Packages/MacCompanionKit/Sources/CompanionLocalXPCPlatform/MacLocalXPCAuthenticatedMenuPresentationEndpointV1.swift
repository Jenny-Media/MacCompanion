#if os(macOS)
import CompanionIPC
import CompanionInteractiveWire
import Foundation

package enum MacLocalXPCMenuPresentationSendOutcomeV1:
    Equatable,
    Sendable
{
    case acknowledged
    case rejectedWithoutRetainedState
}

package enum MacLocalXPCMenuPresentationSendErrorV1:
    Error,
    Equatable,
    Sendable
{
    case endpointUnavailable
    case admissionOverflow
    case operationExhausted
    case transportFailure
    case replyTimedOut
    case cancelledAfterSend
    case retired

    package var requestsTerminalFence: Bool {
        self != .retired
    }
}

package enum MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1:
    Error,
    Equatable,
    Sendable
{
    case presentationRejected
    case endpointClosed
}

package protocol MacLocalXPCMenuPresentationSendingV1:
    AnyObject,
    Sendable
{
    func sendMenuPresentation(
        generation: UInt64,
        endpointToken: UUID,
        request: MacLocalXPCMenuPresentationRequestV1
    ) async throws -> MacLocalXPCMenuPresentationSendOutcomeV1

    func retireMenuPresentationEndpoint(
        generation: UInt64,
        endpointToken: UUID
    ) async
}

/// One opaque capability for one exact ready peer. It contains no raw XPC
/// session and can only submit the five closed presentation request values to
/// its weak transport authority.
package actor MacLocalXPCAuthenticatedMenuPresentationEndpointV1:
    MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
{
    private let generation: UInt64
    private let endpointToken: UUID
    private weak var sender: (any MacLocalXPCMenuPresentationSendingV1)?
    private weak var interactiveSender:
        (any MacLocalXPCGenerationBoundInteractiveLeaseSendingV1)?
    private weak var interactiveInputSender:
        (any MacLocalXPCGenerationBoundInteractiveInputSendingV1)?
    private var terminalFence: MacLocalXPCMenuSurfaceTerminalFenceV1?
    private var terminalFailureLatched = false
    private var terminalFenceRequested = false
    private var retired = false

    package init(
        generation: UInt64,
        endpointToken: UUID,
        sender: any MacLocalXPCMenuPresentationSendingV1
    ) {
        precondition(generation > 0)
        self.generation = generation
        self.endpointToken = endpointToken
        self.sender = sender
        interactiveSender = sender as?
            any MacLocalXPCGenerationBoundInteractiveLeaseSendingV1
        interactiveInputSender = sender as?
            any MacLocalXPCGenerationBoundInteractiveInputSendingV1
    }

    package func installAuthenticatedMenuTerminalFence(
        _ fence: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) async {
        guard terminalFence == nil else { return }
        terminalFence = fence
        await requestTerminalFenceIfNeeded()
    }

    package func invalidateAuthenticatedMenuSurface() async {
        guard !retired else { return }
        retired = true
        let sender = self.sender
        self.sender = nil
        interactiveSender = nil
        interactiveInputSender = nil
        // Owner-driven retirement is deliberately not a transport-failure
        // callback and therefore never recursively requests the router fence.
        await sender?.retireMenuPresentationEndpoint(
            generation: generation,
            endpointToken: endpointToken
        )
    }

    package func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        let payload = try LocalMenuPresentationWireCodecV1
            .encodePairingReview(review)
        try await publish(.pairingReview(payload))
    }

    package func withdrawLocalPairingReview(reviewID: UUID) async {
        guard (try? LocalMenuPresentationWireCodecV1.validateWithdrawal(
            reviewID: reviewID
        )) != nil else {
            await latchTerminalFailure()
            return
        }
        await withdraw(.pairingWithdrawal(reviewID))
    }

    package func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        let payload = try LocalMenuPresentationWireCodecV1
            .encodeHostIdentityRecoveryReview(review)
        try await publish(.hostRecoveryReview(payload))
    }

    package func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        let payload = try LocalMenuPresentationWireCodecV1
            .encodeHostIdentityRecoveryResume(command)
        try await publish(.hostRecoveryResume(payload))
    }

    package func withdrawHostIdentityRecovery(reviewID: UUID) async {
        guard (try? LocalMenuPresentationWireCodecV1.validateWithdrawal(
            reviewID: reviewID
        )) != nil else {
            await latchTerminalFailure()
            return
        }
        await withdraw(.hostRecoveryWithdrawal(reviewID))
    }

    package func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await submitInteractive { sender in
            try await sender.prepareInitialInteractiveDesktop(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await submitInteractive { sender in
            try await sender.installInteractiveLease(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await submitInteractive { sender in
            try await sender.renewInteractiveLease(
                generation: generation,
                endpointToken: endpointToken,
                renewal: renewal
            )
        }
    }

    package func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await submitInteractive { sender in
            try await sender.revokeInteractiveLease(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try await submitInteractive { sender in
            try await sender.interactiveSurfaceTargets(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try await submitInteractive { sender in
            try await sender.resolveInteractiveSurface(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await submitInteractive { sender in
            try await sender.prepareInteractiveSurfaceTransition(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try await submitInteractive { sender in
            try await sender.acknowledgeInteractiveSurface(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await submitInteractive { sender in
            try await sender.terminateInteractiveSurfaceFailure(
                generation: generation,
                endpointToken: endpointToken,
                command: command
            )
        }
    }

    package func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        try await submitInteractiveInput { sender in
            try await sender.applyInteractiveInput(
                generation: generation,
                endpointToken: endpointToken,
                envelope: envelope
            )
        }
    }

    private func publish(
        _ request: MacLocalXPCMenuPresentationRequestV1
    ) async throws {
        let outcome = try await submit(request)
        switch outcome {
        case .acknowledged:
            return
        case .rejectedWithoutRetainedState:
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .presentationRejected
        }
    }

    private func withdraw(
        _ request: MacLocalXPCMenuPresentationRequestV1
    ) async {
        do {
            let outcome = try await submit(request)
            guard outcome == .acknowledged else {
                await latchTerminalFailure()
                return
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func submit(
        _ request: MacLocalXPCMenuPresentationRequestV1
    ) async throws -> MacLocalXPCMenuPresentationSendOutcomeV1 {
        guard !retired, !terminalFailureLatched else {
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
        guard let sender else {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
        do {
            return try await sender.sendMenuPresentation(
                generation: generation,
                endpointToken: endpointToken,
                request: request
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MacLocalXPCMenuPresentationSendErrorV1 {
            if error.requestsTerminalFence {
                await latchTerminalFailure()
            }
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        } catch {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
    }

    private func submitInteractive<Value: Sendable>(
        _ operation: @Sendable (
            any MacLocalXPCGenerationBoundInteractiveLeaseSendingV1
        ) async throws -> Value
    ) async throws -> Value {
        guard !retired, !terminalFailureLatched else {
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
        guard let interactiveSender else {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
        do {
            return try await operation(interactiveSender)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
    }

    private func submitInteractiveInput(
        _ operation: @Sendable (
            any MacLocalXPCGenerationBoundInteractiveInputSendingV1
        ) async throws -> Void
    ) async throws {
        guard !retired, !terminalFailureLatched,
              let interactiveInputSender else {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
        do {
            try await operation(interactiveInputSender)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await latchTerminalFailure()
            throw MacLocalXPCAuthenticatedMenuPresentationEndpointErrorV1
                .endpointClosed
        }
    }

    private func latchTerminalFailure() async {
        terminalFailureLatched = true
        await requestTerminalFenceIfNeeded()
    }

    private func requestTerminalFenceIfNeeded() async {
        guard terminalFailureLatched,
              !retired,
              !terminalFenceRequested,
              let terminalFence else {
            return
        }
        terminalFenceRequested = true
        await terminalFence.requestFinish()
    }
}

/// Pure readiness/issuance state used by the peer owner. A numeric generation
/// is insufficient: only the private cached token can identify the endpoint.
package struct MacLocalXPCMenuPresentationEndpointIssuanceGateV1: Sendable {
    private let generation: UInt64
    private var ready = false
    private var terminal = false
    package private(set) var token: UUID?

    package init(generation: UInt64) {
        precondition(generation > 0)
        self.generation = generation
    }

    @discardableResult
    package mutating func publishReadiness(generation: UInt64) -> Bool {
        guard generation == self.generation, !terminal else { return false }
        ready = true
        return true
    }

    package mutating func issue(
        generation: UInt64,
        permitted: Bool,
        makeToken: () -> UUID = UUID.init
    ) -> UUID? {
        guard generation == self.generation,
              ready,
              permitted,
              !terminal else {
            return nil
        }
        if let token { return token }
        let candidate = makeToken()
        guard candidate != Self.zeroUUID else { return nil }
        token = candidate
        return candidate
    }

    package mutating func invalidate(generation: UInt64) {
        guard generation == self.generation else { return }
        terminal = true
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}
#endif
