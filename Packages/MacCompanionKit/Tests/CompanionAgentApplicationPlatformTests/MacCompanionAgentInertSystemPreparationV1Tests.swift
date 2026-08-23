#if os(macOS)
import CompanionAgent
@testable import CompanionAgentApplicationPlatform
import CompanionAgentProductPlatform
import CompanionHostPlatform
import CompanionInteractiveHost
import CompanionMacApp
import Foundation
import Testing

@available(macOS 26.0, *)
@Test func systemPreparationInputsBindMaterialsButEffectsStayClosed()
    async throws
{
    let registryGeneration = UUID(
        uuidString: "018f6000-0000-7000-8000-000000000001"
    )!
    let wallNow: Int64 = 1_724_200_000_000
    let inputs = try MacCompanionAgentInertSystemPreparationV1.makeInputs(
        registryGeneration: registryGeneration,
        wallNowUnixMilliseconds: wallNow
    )

    #expect(
        MacCompanionAgentInertSystemPreparationV1
            .hostIdentityApplicationTagPrefix
            == "media.jenny.maccompanion.agent.identity.v1"
    )
    #expect(
        inputs.hostIdentityConfiguration.applicationTagPrefix
            == MacCompanionAgentInertSystemPreparationV1
                .hostIdentityApplicationTagPrefix
    )
    #expect(inputs.hostIdentityConfiguration.requireSecureEnclave)
    #expect(inputs.nativeMVPProviders.registryGeneration == registryGeneration)
    #expect(inputs.wallNowUnixMilliseconds == wallNow)
    #expect(inputs.interactivePlatform.surfaceControl == nil)
    #expect(
        await inputs.processStarter.requestStarts([
            .requestAgentStart,
            .requestMenuStart,
        ]) == .notCompleted
    )
    await #expect(
        throws: AgentInertInteractivePlatformErrorV1.unavailable
    ) {
        try await inputs.interactivePlatform.visibleAdmission.snapshot()
    }
    let approval = try await inputs.interactivePlatform.materials
        .approvalMaterials()
    #expect(approval.serverChallenge.count == 32)

    let bootstrap = try await inputs.interactivePlatform.materials
        .bootstrapMaterials()
    #expect(bootstrap.inputCredential.count == 32)
    #expect(bootstrap.mediaCredential.count == 32)
    #expect(bootstrap.inputCredential != bootstrap.mediaCredential)
    #expect(bootstrap.interactiveSessionID != bootstrap.inputChannelID)
    #expect(bootstrap.interactiveSessionID != bootstrap.mediaChannelID)
    #expect(bootstrap.inputChannelID != bootstrap.mediaChannelID)
}
#endif
