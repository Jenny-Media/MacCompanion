@testable import CompanionAgentNetworkPlatform
import CompanionNativeProviders
import CompanionOperations
import CompanionWire
import Foundation
import Testing

private struct EchoNativeMVPMuteControllerV1:
    DefaultOutputMuteControllingV1
{
    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool { desired }
}

@Test func nativeMVPCompositionBindsExactDescriptorAndProviderIdentity()
    async throws
{
    let generation = UUID()
    let composition = try AgentNativeMVPProviderCompositionV1(
        registryGeneration: generation,
        audioMuteController: EchoNativeMVPMuteControllerV1()
    )
    let providers = try await composition.providerLoader.loadProviders()
    let publication = try CapabilityRegistryPublicationV1(
        registry: composition.registry,
        providers: providers
    )

    #expect(composition.registryGeneration == generation)
    #expect(composition.registry.capabilities.map(\.capabilityID) == [
        NativeAudioMuteCapabilityV1.capabilityID,
    ])
    #expect(publication.providerIdentities == [
        CapabilityProviderIdentityV1(
            providerID: NativeAudioMuteCapabilityV1.providerID,
            providerVersion: NativeAudioMuteCapabilityV1.providerVersion,
            providerGeneration: NativeAudioMuteCapabilityV1.providerGeneration,
            executionRevision: NativeAudioMuteCapabilityV1.executionRevision
        ),
    ])
}

@Test func nativeMVPCompositionExecutesOnlyTheBoundDesiredStateProvider()
    async throws
{
    let composition = try AgentNativeMVPProviderCompositionV1(
        registryGeneration: UUID(),
        audioMuteController: EchoNativeMVPMuteControllerV1()
    )
    let publication = try CapabilityRegistryPublicationV1(
        registry: composition.registry,
        providers: try await composition.providerLoader.loadProviders()
    )
    let provider = try #require(publication.provider(
        forCapabilityID: NativeAudioMuteCapabilityV1.capabilityID
    ))
    let result = await provider.execute(CapabilityProviderRequestV1(
        operationID: UUID(),
        capabilityID: NativeAudioMuteCapabilityV1.capabilityID,
        parameters: .object([
            .init(key: "muted", value: .boolean(true)),
        ]),
        expiresAtUnixMilliseconds: 30_000
    ))

    #expect(result == .succeeded(
        resultJSON: Data("{\"muted\":true}".utf8)
    ))
}

#if os(macOS)
@Test func systemNativeMVPCompositionIsConstructionOnly() async throws {
    let composition = try AgentNativeMVPProviderCompositionV1.systemDefault(
        registryGeneration: UUID()
    )
    let providers = try await composition.providerLoader.loadProviders()

    // Loading returns the inert provider reference. No Core Audio API is
    // called until the operation authority invokes execute.
    #expect(providers.count == 1)
    #expect(providers[0].identity.providerID
        == NativeAudioMuteCapabilityV1.providerID)
}
#endif
