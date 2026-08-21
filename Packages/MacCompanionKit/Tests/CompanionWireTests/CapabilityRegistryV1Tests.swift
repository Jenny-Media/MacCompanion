import CompanionDomain
import CompanionWire
import Foundation
import Testing

private let registryProviderGeneration = UUID(
    uuidString: "018f8100-0000-7000-8000-000000000001"
)!
private let registryExecutionRevision = UUID(
    uuidString: "018f8200-0000-7000-8000-000000000001"
)!

private func registryEffects() throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: .none,
        changesLocalState: .reversible,
        mayDisruptUser: false,
        invokesExternalService: false,
        usesCredentials: false,
        destructive: false,
        requiresForegroundSession: false,
        allowedWhileLocked: true,
        cancellation: .notApplicable
    )
}

private func registryDescriptor(
    capabilityID: String = "maccompanion.system.setAudioMuted",
    providerGeneration: UUID = registryProviderGeneration,
    executionRevision: UUID = registryExecutionRevision
) throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: capabilityID,
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: providerGeneration,
        executionRevision: executionRevision,
        englishTitle: "Set audio mute",
        englishSummary: "Set the default output mute state.",
        parameterSchema: .object(properties: [
            CapabilitySchemaPropertyV1(
                name: "muted",
                required: true,
                schema: .boolean()
            ),
        ]),
        resultSchema: .object(properties: [
            CapabilitySchemaPropertyV1(
                name: "muted",
                required: true,
                schema: .boolean()
            ),
        ]),
        effects: registryEffects()
    )
}

@Test func registrySnapshotIsCanonicalAndValidatesNativeParameters() throws {
    let secondary = try registryDescriptor(
        capabilityID: "maccompanion.test.secondaryAction"
    )
    let audio = try registryDescriptor()
    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [audio, secondary]
    )
    #expect(registry.capabilities.map(\.capabilityID) == [
        "maccompanion.system.setAudioMuted",
        "maccompanion.test.secondaryAction",
    ])
    let selected = try #require(registry.capability(audio.capabilityID))
    try selected.parameterSchema.validate(
        CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
    )
}

@Test func registryRejectsDuplicateCapabilityAndInconsistentProviderIdentity() throws {
    let audio = try registryDescriptor()
    #expect(throws: CapabilityRegistryError.duplicateCapabilityID(audio.capabilityID)) {
        try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [audio, audio]
        )
    }
    let changed = try registryDescriptor(
        capabilityID: "maccompanion.test.secondaryAction",
        providerGeneration: UUID()
    )
    #expect(throws: CapabilityRegistryError.inconsistentProvider("maccompanion.native")) {
        try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [audio, changed]
        )
    }
}

@Test func descriptorRejectsUnboundedPresentationAndNonObjectParameters() throws {
    #expect(throws: CapabilityRegistryError.invalidDescriptor(field: "englishTitle")) {
        try CapabilityDescriptorV1(
            capabilityID: "maccompanion.system.setAudioMuted",
            schemaVersion: 1,
            providerID: "maccompanion.native",
            providerVersion: "1.0.0",
            providerGeneration: UUID(),
            executionRevision: UUID(),
            englishTitle: "",
            englishSummary: "summary",
            parameterSchema: .boolean(),
            resultSchema: .object(properties: []),
            effects: registryEffects()
        )
    }
}
