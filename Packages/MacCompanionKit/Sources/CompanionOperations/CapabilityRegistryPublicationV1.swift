import CompanionWire
import Foundation

public enum CapabilityRegistryPublicationErrorV1:
    Error, Equatable, Sendable
{
    case duplicateProvider(String)
    case missingProvider(String)
    case unexpectedProvider(String)
    case providerNotPublished(String)
    case providerIdentityMismatch(String)
    case generationCollision(UUID)
}

/// One immutable, internally consistent registry and live-provider view.
/// Commands retain this value for their entire admission/discovery/execution
/// path so a later publication cannot retarget an in-flight effect.
public struct CapabilityRegistryPublicationV1: Sendable {
    public let registry: CapabilityRegistrySnapshotV1
    public let providerIdentities: [CapabilityProviderIdentityV1]
    private let providersByID: [String: any CapabilityProviderV1]

    public init(
        registry: CapabilityRegistrySnapshotV1,
        providers: [any CapabilityProviderV1]
    ) throws {
        var supplied: [String: any CapabilityProviderV1] = [:]
        for provider in providers {
            let providerID = provider.identity.providerID
            guard supplied[providerID] == nil else {
                throw CapabilityRegistryPublicationErrorV1
                    .duplicateProvider(providerID)
            }
            supplied[providerID] = provider
        }

        var expected: [String: CapabilityProviderIdentityV1] = [:]
        for descriptor in registry.capabilities {
            expected[descriptor.providerID] = CapabilityProviderIdentityV1(
                providerID: descriptor.providerID,
                providerVersion: descriptor.providerVersion,
                providerGeneration: descriptor.providerGeneration,
                executionRevision: descriptor.executionRevision
            )
        }
        for providerID in expected.keys where supplied[providerID] == nil {
            throw CapabilityRegistryPublicationErrorV1
                .missingProvider(providerID)
        }
        for providerID in supplied.keys where expected[providerID] == nil {
            throw CapabilityRegistryPublicationErrorV1
                .unexpectedProvider(providerID)
        }
        for (providerID, identity) in expected {
            guard supplied[providerID]?.identity == identity else {
                throw CapabilityRegistryPublicationErrorV1
                    .providerIdentityMismatch(providerID)
            }
        }

        self.registry = registry
        providersByID = supplied
        providerIdentities = expected.values.sorted {
            $0.providerID < $1.providerID
        }
    }

    public func provider(
        forCapabilityID capabilityID: String
    ) -> (any CapabilityProviderV1)? {
        guard let descriptor = registry.capability(capabilityID),
              let provider = providersByID[descriptor.providerID],
              provider.identity == CapabilityProviderIdentityV1(
                providerID: descriptor.providerID,
                providerVersion: descriptor.providerVersion,
                providerGeneration: descriptor.providerGeneration,
                executionRevision: descriptor.executionRevision
              ) else {
            return nil
        }
        return provider
    }

    /// Constructs the only publication change permitted for an exact
    /// provider-unavailability event: remove every capability owned by that
    /// provider while retaining all other descriptors and live references.
    public func removingProvider(
        _ identity: CapabilityProviderIdentityV1,
        replacementGeneration: UUID
    ) throws -> CapabilityRegistryPublicationV1 {
        guard let provider = providersByID[identity.providerID] else {
            throw CapabilityRegistryPublicationErrorV1.providerNotPublished(
                identity.providerID
            )
        }
        guard provider.identity == identity else {
            throw CapabilityRegistryPublicationErrorV1
                .providerIdentityMismatch(identity.providerID)
        }
        let registry = try CapabilityRegistrySnapshotV1(
            generation: replacementGeneration,
            capabilities: self.registry.capabilities.filter {
                $0.providerID != identity.providerID
            }
        )
        let providers = providersByID.values.filter {
            $0.identity.providerID != identity.providerID
        }
        return try CapabilityRegistryPublicationV1(
            registry: registry,
            providers: Array(providers)
        )
    }
}

public enum CapabilityRegistryReplacementResultV1: Equatable, Sendable {
    case replaced(previousGeneration: UUID, currentGeneration: UUID)
    case idempotentReplay(generation: UUID)
}

/// Read-only authority shared by discovery, admission, and other command
/// consumers. A command retains the returned value rather than rereading while
/// it awaits persistence or platform work.
public protocol CapabilityRegistrySnapshotReadingV1: Sendable {
    func registrySnapshot() async -> CapabilityRegistrySnapshotV1
}

/// Read-only authority for consumers that also need the provider reference
/// bound to the same immutable registry snapshot.
public protocol CapabilityRegistryPublicationReadingV1:
    CapabilityRegistrySnapshotReadingV1
{
    func publicationSnapshot() async -> CapabilityRegistryPublicationV1
}

/// Compatibility source for focused tests and consumers whose registry is
/// intentionally immutable for their complete lifetime. Product replacement
/// composition uses `CapabilityRegistryPublicationAuthorityV1` instead.
public struct FixedCapabilityRegistrySnapshotReaderV1:
    CapabilityRegistrySnapshotReadingV1
{
    private let registry: CapabilityRegistrySnapshotV1

    public init(_ registry: CapabilityRegistrySnapshotV1) {
        self.registry = registry
    }

    public func registrySnapshot() async -> CapabilityRegistrySnapshotV1 {
        registry
    }
}

public actor CapabilityRegistryPublicationAuthorityV1:
    CapabilityRegistryPublicationReadingV1
{
    private var current: CapabilityRegistryPublicationV1

    public init(initial: CapabilityRegistryPublicationV1) {
        current = initial
    }

    public func snapshot() -> CapabilityRegistryPublicationV1 { current }

    public func publicationSnapshot() -> CapabilityRegistryPublicationV1 {
        current
    }

    public func registrySnapshot() -> CapabilityRegistrySnapshotV1 {
        current.registry
    }

    public func replace(
        with candidate: CapabilityRegistryPublicationV1
    ) throws -> CapabilityRegistryReplacementResultV1 {
        let previous = current
        if candidate.registry.generation == previous.registry.generation {
            guard candidate.registry == previous.registry,
                  candidate.providerIdentities == previous.providerIdentities else {
                throw CapabilityRegistryPublicationErrorV1.generationCollision(
                    candidate.registry.generation
                )
            }
            return .idempotentReplay(generation: previous.registry.generation)
        }
        current = candidate
        return .replaced(
            previousGeneration: previous.registry.generation,
            currentGeneration: candidate.registry.generation
        )
    }
}
