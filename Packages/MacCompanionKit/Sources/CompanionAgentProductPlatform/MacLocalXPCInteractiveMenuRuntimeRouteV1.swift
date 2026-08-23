#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionInteractiveShared
import CompanionLocalXPCPlatform
import Foundation

/// Product-layer type adapter that gives the pure Agent runtime owner only the
/// initial Desktop preparation plus the three lease lifecycle operations. It does not expose the local-XPC server,
/// peer generation, presentation surfaces, or status authority.
@available(macOS 26.0, *)
package struct MacLocalXPCInteractiveMenuRuntimeRouteV1:
    AgentInteractiveInitialDesktopPreparingV1,
    AgentInteractiveMenuRuntimeRoutingV1
{
    private let sender: any MacLocalXPCInteractiveLeaseSendingV1
    private let identifier: @Sendable () -> UUID

    package init(
        sender: any MacLocalXPCInteractiveLeaseSendingV1,
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.sender = sender
        self.identifier = identifier
    }

    package func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor {
        let command = try
            LocalInteractiveInitialDesktopPreparationCommandV1(
                commandID: identifier(),
                interactiveSessionID: request.interactiveSessionID,
                authorizationEpoch: request.authorizationEpoch,
                selectedDisplayID: request.selectedDisplayID,
                interactionClasses: request.interactionClasses
            )
        let receipt = try await sender.prepareInitialInteractiveDesktop(
            command
        )
        try receipt.validate(against: command)
        return receipt.descriptor
    }

    package func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await sender.installInteractiveLease(command)
    }

    package func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await sender.renewInteractiveLease(renewal)
    }

    package func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await sender.revokeInteractiveLease(command)
    }
}
#endif
