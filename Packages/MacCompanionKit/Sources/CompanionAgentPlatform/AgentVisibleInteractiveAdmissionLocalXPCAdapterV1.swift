#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionLocalXPCPlatform

extension AgentVisibleInteractiveAdmissionAuthorityV1:
    MacLocalXPCInteractiveAdmissionHandlingV1
{
    public func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1,
        transportGeneration: UInt64
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        try publish(
            publication,
            transportGeneration: transportGeneration
        )
    }

    public func invalidateInteractiveAdmission(
        transportGeneration: UInt64
    ) async {
        _ = invalidate(transportGeneration: transportGeneration)
    }
}
#endif
