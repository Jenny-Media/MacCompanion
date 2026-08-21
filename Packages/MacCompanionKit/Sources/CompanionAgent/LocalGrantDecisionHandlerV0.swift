import CompanionDomain
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation

public enum LocalGrantDecisionHandlerErrorV0: Error, Equatable, Sendable {
    case invalidReview
    case duplicateReview(UUID)
    case reviewUnavailable(UUID)
    case commandMismatch
    case commandInFlight(UUID)
    case persistenceMismatch
    case registryMismatch
    case registryReplacementBusy
}

/// An Agent-owned record of exactly what the visible menu app is allowed to
/// present. Registering this record is an in-process Agent operation, not a
/// local IPC method; the authenticated menu app can only decide an existing
/// opaque review identifier.
public struct PendingLocalGrantExpansionReviewV0: Equatable, Sendable {
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let currentGrants: CapabilityGrantSet
    public let proposedGrants: CapabilityGrantSet
    public let registryGeneration: UUID
    public let requestedDescriptors: [CapabilityDescriptorV1]

    public init(
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        currentGrants: CapabilityGrantSet,
        proposedGrants: CapabilityGrantSet,
        registryGeneration: UUID,
        requestedDescriptors: [CapabilityDescriptorV1]
    ) throws {
        let requestedIDs = requestedDescriptors.map(\.capabilityID)
        let expectedRequested = Set(proposedGrants.capabilityIDs)
            .subtracting(currentGrants.capabilityIDs)
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              Set(proposedGrants.capabilityIDs).isStrictSuperset(
                of: Set(currentGrants.capabilityIDs)
              ),
              !requestedDescriptors.isEmpty,
              Set(requestedIDs).count == requestedIDs.count,
              Set(requestedIDs) == expectedRequested else {
            throw LocalGrantDecisionHandlerErrorV0.invalidReview
        }
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.currentGrants = currentGrants
        self.proposedGrants = proposedGrants
        self.registryGeneration = registryGeneration
        self.requestedDescriptors = requestedDescriptors.sorted {
            $0.capabilityID < $1.capabilityID
        }
    }

    fileprivate func matches(_ command: LocalGrantDecisionCommandV0) -> Bool {
        reviewID == command.reviewID
            && deviceID == command.deviceID
            && deviceDisplayName == command.deviceDisplayName
            && authorizationEpoch == command.expectedAuthorizationEpoch
            && grantRevision == command.expectedGrantRevision
            && policyRevision == command.expectedPolicyRevision
            && currentGrants.capabilityIDs == command.expectedCurrentGrantIDs
            && proposedGrants.capabilityIDs == command.proposedGrantIDs
    }
}

public struct LocalGrantDecisionDurableStateV0: Equatable, Sendable {
    public let grants: CapabilityGrantSet
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let completedAtUnixMilliseconds: Int64

    public init(
        grants: CapabilityGrantSet,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds
                <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw LocalGrantDecisionHandlerErrorV0.persistenceMismatch
        }
        self.grants = grants
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }
}

public protocol LocalGrantDecisionPersistingV0: Sendable {
    /// The implementation must compare every command fence and either commit
    /// the approved expansion or return the declined unchanged snapshot in one
    /// serialized durable boundary.
    func resolve(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionDurableStateV0
}

public struct SQLiteLocalGrantDecisionPersistenceV0:
    LocalGrantDecisionPersistingV0,
    Sendable
{
    private let store: SQLiteSecurityStore

    public init(store: SQLiteSecurityStore) {
        self.store = store
    }

    public func resolve(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionDurableStateV0 {
        let expected = try StoredGrantExpansionExpectation(
            deviceID: command.deviceID,
            displayName: command.deviceDisplayName,
            authorizationEpoch: command.expectedAuthorizationEpoch,
            grantRevision: command.expectedGrantRevision,
            policyRevision: command.expectedPolicyRevision,
            currentGrants: command.expectedCurrentGrantSet(),
            proposedGrants: command.proposedGrantSet()
        )
        let snapshot = try await store.decideGrantExpansion(
            expected: expected,
            approve: command.decision == .approve,
            occurredAtUnixMilliseconds: command.decidedAtUnixMilliseconds
        )
        return try LocalGrantDecisionDurableStateV0(
            grants: snapshot.grants,
            authorizationEpoch:
                snapshot.device.authorization.authorizationEpoch,
            grantRevision: snapshot.device.authorization.grantRevision,
            policyRevision: snapshot.device.policyRevision,
            completedAtUnixMilliseconds: command.decidedAtUnixMilliseconds
        )
    }
}

/// Serializes local grant decisions, rejects menu-authored review identifiers,
/// consumes failed reviews, and retains a bounded idempotency window for a
/// response lost after a successful durable commit.
public actor LocalGrantDecisionHandlerV0 {
    public static let maximumCompletedDecisions = 128

    private struct Completion: Sendable {
        let command: LocalGrantDecisionCommandV0
        let receipt: LocalGrantDecisionReceiptV0
    }

    private let persistence: any LocalGrantDecisionPersistingV0
    private var registry: CapabilityRegistrySnapshotV1
    private var pending: [UUID: PendingLocalGrantExpansionReviewV0] = [:]
    private var inFlight: Set<UUID> = []
    private var completions: [UUID: Completion] = [:]
    private var completionOrder: [UUID] = []

    public init(
        persistence: any LocalGrantDecisionPersistingV0,
        registry: CapabilityRegistrySnapshotV1
    ) {
        self.persistence = persistence
        self.registry = registry
    }

    public func register(
        _ review: PendingLocalGrantExpansionReviewV0
    ) throws {
        guard pending[review.reviewID] == nil else {
            throw LocalGrantDecisionHandlerErrorV0.duplicateReview(review.reviewID)
        }
        try requireCurrentRegistry(review)
        pending[review.reviewID] = review
    }

    /// Provider replacement and grant decisions share this actor boundary.
    /// Replacement never interleaves with a durable decision and invalidates
    /// every still-visible review, even when capability identifiers are reused.
    public func replaceRegistry(
        _ replacement: CapabilityRegistrySnapshotV1
    ) throws {
        guard inFlight.isEmpty else {
            throw LocalGrantDecisionHandlerErrorV0.registryReplacementBusy
        }
        registry = replacement
        pending.removeAll()
    }

    public func cancel(reviewID: UUID) {
        pending.removeValue(forKey: reviewID)
    }

    public func handle(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        if let completion = completions[command.commandID] {
            guard completion.command == command else {
                throw LocalGrantDecisionHandlerErrorV0.commandMismatch
            }
            return completion.receipt
        }
        guard !inFlight.contains(command.commandID) else {
            throw LocalGrantDecisionHandlerErrorV0.commandInFlight(
                command.commandID
            )
        }
        guard let review = pending.removeValue(forKey: command.reviewID) else {
            throw LocalGrantDecisionHandlerErrorV0.reviewUnavailable(
                command.reviewID
            )
        }
        guard review.matches(command) else {
            throw LocalGrantDecisionHandlerErrorV0.commandMismatch
        }
        try requireCurrentRegistry(review)

        inFlight.insert(command.commandID)
        defer { inFlight.remove(command.commandID) }
        let durable = try await persistence.resolve(command)
        let receipt = try LocalGrantDecisionReceiptV0(
            correlationID: command.commandID,
            reviewID: command.reviewID,
            deviceID: command.deviceID,
            decision: command.decision,
            storedGrants: durable.grants,
            authorizationEpoch: durable.authorizationEpoch,
            grantRevision: durable.grantRevision,
            policyRevision: durable.policyRevision,
            completedAtUnixMilliseconds:
                durable.completedAtUnixMilliseconds
        )
        do {
            try receipt.validate(against: command)
        } catch {
            throw LocalGrantDecisionHandlerErrorV0.persistenceMismatch
        }
        retain(command: command, receipt: receipt)
        return receipt
    }

    private func requireCurrentRegistry(
        _ review: PendingLocalGrantExpansionReviewV0
    ) throws {
        guard review.registryGeneration == registry.generation,
              review.requestedDescriptors.allSatisfy({ descriptor in
                registry.capability(descriptor.capabilityID) == descriptor
              }) else {
            throw LocalGrantDecisionHandlerErrorV0.registryMismatch
        }
    }

    private func retain(
        command: LocalGrantDecisionCommandV0,
        receipt: LocalGrantDecisionReceiptV0
    ) {
        completions[command.commandID] = Completion(
            command: command,
            receipt: receipt
        )
        completionOrder.append(command.commandID)
        if completionOrder.count > Self.maximumCompletedDecisions {
            let evicted = completionOrder.removeFirst()
            completions.removeValue(forKey: evicted)
        }
    }
}
