import CompanionIPC
import CompanionOperations
import CompanionPersistence
import CompanionWire
import Foundation

public enum AgentCapabilityAuthorityErrorV1: Error, Equatable, Sendable {
    case replacementInProgress
    case grantMutationInProgress
}

/// Single product mutation boundary for capability publication and local grant
/// review. Discovery and commands receive this value only as a read authority;
/// provider replacement and grant mutation remain serialized here.
public actor AgentCapabilityAuthorityV1:
    CapabilityRegistryPublicationReadingV1
{
    private let publication: CapabilityRegistryPublicationAuthorityV1
    private let grants: LocalGrantDecisionHandlerV0
    private let registryAuditWriter:
        any CapabilityRegistryPublicationAuditWritingV1
    private let wallClock: any CapabilityRegistryPublicationWallClockV1
    private var replacementInProgress = false
    private var grantMutationInProgress = false

    public init(
        initial: CapabilityRegistryPublicationV1,
        grantPersistence: any LocalGrantDecisionPersistingV0,
        registryAuditWriter:
            BoundedCapabilityRegistryPublicationAuditWriterV1,
        wallClock: any CapabilityRegistryPublicationWallClockV1 =
            SystemCapabilityRegistryPublicationWallClockV1()
    ) {
        publication = CapabilityRegistryPublicationAuthorityV1(initial: initial)
        grants = LocalGrantDecisionHandlerV0(
            persistence: grantPersistence,
            registry: initial.registry
        )
        self.registryAuditWriter = registryAuditWriter
        self.wallClock = wallClock
    }

    public func publicationSnapshot() async
        -> CapabilityRegistryPublicationV1
    {
        await publication.publicationSnapshot()
    }

    public func registrySnapshot() async -> CapabilityRegistrySnapshotV1 {
        await publication.registrySnapshot()
    }

    /// Content-free inventory fact for local diagnostics. Provider names and
    /// identities remain inside the registry authority.
    public func activeProviderCount() async -> Int {
        await publication.publicationSnapshot().providerIdentities.count
    }

    public func registerGrantReview(
        _ review: PendingLocalGrantExpansionReviewV0
    ) async throws {
        try beginGrantMutation()
        defer { grantMutationInProgress = false }
        try await grants.register(review)
    }

    public func cancelGrantReview(reviewID: UUID) async throws {
        try beginGrantMutation()
        defer { grantMutationInProgress = false }
        await grants.cancel(reviewID: reviewID)
    }

    public func handleGrantDecision(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        try beginGrantMutation()
        defer { grantMutationInProgress = false }
        return try await grants.handle(command)
    }

    public func replace(
        with candidate: CapabilityRegistryPublicationV1
    ) async throws -> CapabilityRegistryReplacementResultV1 {
        try beginReplacement()
        defer { replacementInProgress = false }
        return try await commitReplacement(candidate)
    }

    /// Fail-closed supervisor action for a provider that disappeared after
    /// startup. It cannot change unrelated descriptors or provider references.
    public func markProviderUnavailable(
        _ identity: CapabilityProviderIdentityV1,
        replacementGeneration: UUID
    ) async throws -> CapabilityRegistryReplacementResultV1 {
        try beginReplacement()
        defer { replacementInProgress = false }

        let current = await publication.publicationSnapshot()
        if current.registry.generation == replacementGeneration,
           !current.providerIdentities.contains(where: {
               $0.providerID == identity.providerID
           }) {
            return .idempotentReplay(generation: replacementGeneration)
        }
        let candidate = try current.removingProvider(
            identity,
            replacementGeneration: replacementGeneration
        )
        return try await commitReplacement(candidate)
    }

    private func beginReplacement() throws {
        guard !replacementInProgress else {
            throw AgentCapabilityAuthorityErrorV1.replacementInProgress
        }
        guard !grantMutationInProgress else {
            throw AgentCapabilityAuthorityErrorV1.grantMutationInProgress
        }
        replacementInProgress = true
    }

    private func commitReplacement(
        _ candidate: CapabilityRegistryPublicationV1
    ) async throws -> CapabilityRegistryReplacementResultV1 {
        let result = try await publication.replace(with: candidate)
        if case let .replaced(_, currentGeneration) = result {
            // Grant calls remain blocked until pending reviews are invalidated
            // against the exact registry that is already authoritative.
            try await grants.replaceRegistry(candidate.registry)
            // This is the committed multi-consumer fact. Best-effort audit is
            // attempted only after both publication and review invalidation.
            await registryAuditWriter.recordCompletedReplacement(
                currentGeneration: currentGeneration,
                observedAtUnixMilliseconds: wallClock.nowUnixMilliseconds()
            )
        }
        return result
    }

    private func beginGrantMutation() throws {
        guard !replacementInProgress else {
            throw AgentCapabilityAuthorityErrorV1.replacementInProgress
        }
        guard !grantMutationInProgress else {
            throw AgentCapabilityAuthorityErrorV1.grantMutationInProgress
        }
        grantMutationInProgress = true
    }
}
