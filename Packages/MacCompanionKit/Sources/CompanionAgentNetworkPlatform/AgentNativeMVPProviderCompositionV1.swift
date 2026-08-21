import CompanionAgent
import CompanionNativeProviders
import CompanionOperations
import CompanionWire
import Foundation

/// One internally consistent registry/loader pair for the first-party MVP
/// provider set. A product target cannot accidentally advertise the native
/// mute descriptor while loading a different provider identity, or load the
/// provider without advertising its reviewed descriptor.
public struct AgentNativeMVPProviderCompositionV1: Sendable {
    package let registry: CapabilityRegistrySnapshotV1
    package let providerLoader: StaticAgentCapabilityProviderLoaderV1

    public var registryGeneration: UUID { registry.generation }

    public init(
        registryGeneration: UUID,
        audioMuteController: any DefaultOutputMuteControllingV1
    ) throws {
        let descriptor = try NativeAudioMuteCapabilityV1.descriptor()
        registry = try CapabilityRegistrySnapshotV1(
            generation: registryGeneration,
            capabilities: [descriptor]
        )
        providerLoader = StaticAgentCapabilityProviderLoaderV1(
            providers: [
                NativeAudioMuteProviderV1(controller: audioMuteController),
            ]
        )
    }

    #if os(macOS)
    /// Release-shaped construction of the reviewed Core Audio provider. This
    /// only constructs authority; it performs no Core Audio read or mutation
    /// until an admitted operation executes.
    public static func systemDefault(
        registryGeneration: UUID
    ) throws -> AgentNativeMVPProviderCompositionV1 {
        try AgentNativeMVPProviderCompositionV1(
            registryGeneration: registryGeneration,
            audioMuteController: CoreAudioDefaultOutputMuteControllerV1()
        )
    }
    #endif
}
