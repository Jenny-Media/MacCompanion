#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionLocalXPCPlatform
import Foundation

/// Product-layer type adapter that gives the pure Agent runtime owner only the
/// three lease lifecycle operations. It does not expose the local-XPC server,
/// peer generation, presentation surfaces, or status authority.
@available(macOS 26.0, *)
package struct MacLocalXPCInteractiveMenuRuntimeRouteV1:
    AgentInteractiveMenuRuntimeRoutingV1
{
    private let sender: any MacLocalXPCInteractiveLeaseSendingV1

    package init(sender: any MacLocalXPCInteractiveLeaseSendingV1) {
        self.sender = sender
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
