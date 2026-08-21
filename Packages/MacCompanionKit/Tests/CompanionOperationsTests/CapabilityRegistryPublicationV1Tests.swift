import CompanionDomain
import CompanionOperations
import CompanionWire
import Foundation
import Testing

private actor PublicationProviderV1: CapabilityProviderV1 {
    nonisolated let identity: CapabilityProviderIdentityV1
    let marker: Int

    init(identity: CapabilityProviderIdentityV1, marker: Int) {
        self.identity = identity
        self.marker = marker
    }

    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        .failed(.unavailable)
    }

    func markerValue() -> Int { marker }
}

private func publicationDescriptorV1(
    providerGeneration: UUID,
    capabilityID: String = "maccompanion.test.publication",
    providerID: String = "maccompanion.test"
) throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: capabilityID,
        schemaVersion: 1,
        providerID: providerID,
        providerVersion: "1.0.0",
        providerGeneration: providerGeneration,
        executionRevision: UUID(
            uuidString: "018f8200-0000-7000-8000-000000000001"
        )!,
        englishTitle: "Publication test",
        englishSummary: "Tests one bounded publication.",
        parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []),
        effects: try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .none,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: true,
            cancellation: .notApplicable
        )
    )
}

@Test func providerFailureCandidateRetainsEveryUnrelatedDescriptorAndReference() throws {
    let failed = try publicationDescriptorV1(
        providerGeneration: UUID(),
        capabilityID: "maccompanion.test.failed",
        providerID: "maccompanion.failed"
    )
    let retained = try publicationDescriptorV1(
        providerGeneration: UUID(),
        capabilityID: "maccompanion.test.retained",
        providerID: "maccompanion.retained"
    )
    let failedProvider = PublicationProviderV1(
        identity: CapabilityProviderIdentityV1(
            providerID: failed.providerID,
            providerVersion: failed.providerVersion,
            providerGeneration: failed.providerGeneration,
            executionRevision: failed.executionRevision
        ),
        marker: 1
    )
    let retainedProvider = PublicationProviderV1(
        identity: CapabilityProviderIdentityV1(
            providerID: retained.providerID,
            providerVersion: retained.providerVersion,
            providerGeneration: retained.providerGeneration,
            executionRevision: retained.executionRevision
        ),
        marker: 2
    )
    let publication = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [failed, retained]
        ),
        providers: [failedProvider, retainedProvider]
    )
    let replacementGeneration = UUID()
    let candidate = try publication.removingProvider(
        failedProvider.identity,
        replacementGeneration: replacementGeneration
    )

    #expect(candidate.registry.generation == replacementGeneration)
    #expect(candidate.registry.capabilities == [retained])
    #expect(candidate.providerIdentities == [retainedProvider.identity])
    #expect(candidate.provider(forCapabilityID: failed.capabilityID) == nil)
    let exactRetained = candidate.provider(
        forCapabilityID: retained.capabilityID
    ) as? PublicationProviderV1
    #expect(exactRetained === retainedProvider)
}

private func publicationV1(
    generation: UUID,
    providerGeneration: UUID,
    marker: Int
) throws -> CapabilityRegistryPublicationV1 {
    let descriptor = try publicationDescriptorV1(
        providerGeneration: providerGeneration
    )
    let registry = try CapabilityRegistrySnapshotV1(
        generation: generation,
        capabilities: [descriptor]
    )
    return try CapabilityRegistryPublicationV1(
        registry: registry,
        providers: [PublicationProviderV1(
            identity: CapabilityProviderIdentityV1(
                providerID: descriptor.providerID,
                providerVersion: descriptor.providerVersion,
                providerGeneration: descriptor.providerGeneration,
                executionRevision: descriptor.executionRevision
            ),
            marker: marker
        )]
    )
}

private enum PublicationConcurrencyObservationV1: Sendable {
    case snapshot(generation: UUID, marker: Int)
    case replacement
}

@Test func registryPublicationRejectsIncompleteOrMismatchedProviderSets() throws {
    let providerGeneration = UUID()
    let descriptor = try publicationDescriptorV1(
        providerGeneration: providerGeneration
    )
    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [descriptor]
    )
    #expect(throws: CapabilityRegistryPublicationErrorV1.missingProvider(
        descriptor.providerID
    )) {
        try CapabilityRegistryPublicationV1(registry: registry, providers: [])
    }
    let mismatched = PublicationProviderV1(
        identity: CapabilityProviderIdentityV1(
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: UUID(),
            executionRevision: descriptor.executionRevision
        ),
        marker: 0
    )
    #expect(throws: CapabilityRegistryPublicationErrorV1
        .providerIdentityMismatch(descriptor.providerID)) {
        try CapabilityRegistryPublicationV1(
            registry: registry,
            providers: [mismatched]
        )
    }
    let empty = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: []
    )
    #expect(throws: CapabilityRegistryPublicationErrorV1
        .unexpectedProvider(descriptor.providerID)) {
        try CapabilityRegistryPublicationV1(
            registry: empty,
            providers: [mismatched]
        )
    }
    #expect(throws: CapabilityRegistryPublicationErrorV1
        .duplicateProvider(descriptor.providerID)) {
        try CapabilityRegistryPublicationV1(
            registry: registry,
            providers: [mismatched, mismatched]
        )
    }
}

@Test func registryReplacementPublishesOneSnapshotAndRetainsOldProvider() async throws {
    let firstGeneration = UUID()
    let firstProviderGeneration = UUID()
    let first = try publicationV1(
        generation: firstGeneration,
        providerGeneration: firstProviderGeneration,
        marker: 1
    )
    let authority = CapabilityRegistryPublicationAuthorityV1(initial: first)
    let retained = await authority.snapshot()
    let second = try publicationV1(
        generation: UUID(),
        providerGeneration: UUID(),
        marker: 2
    )

    #expect(try await authority.replace(with: second) == .replaced(
        previousGeneration: firstGeneration,
        currentGeneration: second.registry.generation
    ))
    let current = await authority.snapshot()
    let retainedProvider = retained.provider(
        forCapabilityID: "maccompanion.test.publication"
    ) as? PublicationProviderV1
    let currentProvider = current.provider(
        forCapabilityID: "maccompanion.test.publication"
    ) as? PublicationProviderV1
    #expect(await retainedProvider?.markerValue() == 1)
    #expect(await currentProvider?.markerValue() == 2)
    #expect(current.registry == second.registry)
    #expect(try await authority.replace(with: second)
        == .idempotentReplay(generation: second.registry.generation))

    let collision = try publicationV1(
        generation: second.registry.generation,
        providerGeneration: UUID(),
        marker: 3
    )
    await #expect(throws: CapabilityRegistryPublicationErrorV1
        .generationCollision(second.registry.generation)) {
        try await authority.replace(with: collision)
    }
    #expect(await authority.snapshot().registry == second.registry)
}

@Test func concurrentRegistryReadersObserveOnlyCompletePublications() async throws {
    let first = try publicationV1(
        generation: UUID(),
        providerGeneration: UUID(),
        marker: 1
    )
    let second = try publicationV1(
        generation: UUID(),
        providerGeneration: UUID(),
        marker: 2
    )
    let authority = CapabilityRegistryPublicationAuthorityV1(initial: first)

    let observations = try await withThrowingTaskGroup(
        of: PublicationConcurrencyObservationV1.self
    ) { group in
        for _ in 0..<200 {
            group.addTask {
                let snapshot = await authority.snapshot()
                let provider = try #require(snapshot.provider(
                    forCapabilityID: "maccompanion.test.publication"
                ) as? PublicationProviderV1)
                return .snapshot(
                    generation: snapshot.registry.generation,
                    marker: await provider.markerValue()
                )
            }
        }
        group.addTask {
            _ = try await authority.replace(with: second)
            return .replacement
        }
        var values: [PublicationConcurrencyObservationV1] = []
        for try await value in group { values.append(value) }
        return values
    }

    var replacementCount = 0
    for observation in observations {
        switch observation {
        case let .snapshot(generation, marker):
            #expect(
                (generation == first.registry.generation && marker == 1)
                    || (generation == second.registry.generation && marker == 2)
            )
        case .replacement:
            replacementCount += 1
        }
    }
    #expect(replacementCount == 1)
    let final = await authority.snapshot()
    #expect(final.registry.generation == second.registry.generation)
}
