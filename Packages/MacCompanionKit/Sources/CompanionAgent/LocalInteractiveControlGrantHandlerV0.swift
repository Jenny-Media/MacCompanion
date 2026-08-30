#if os(macOS)
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation
import OSLog

private let interactiveControlGrantAgentLoggerV0 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-control-grant"
)

public enum LocalInteractiveControlGrantHandlerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidTime
    case deviceUnavailable
    case displayNameUnavailable
    case alreadyGranted
    case reviewUnavailable
    case authorityUnavailable
}

/// Agent-owned authority for the fixed durable Control grant. It selects the
/// newest active paired device that still lacks Control and reuses the exact
/// revision-fenced expansion persistence without publishing Control as an Act
/// provider. The menu and remote peer never supply a target device identifier.
public actor LocalInteractiveControlGrantHandlerV0 {
    private let store: SQLiteSecurityStore
    private let decisions: LocalGrantDecisionHandlerV0
    private let registry: CapabilityRegistrySnapshotV1
    private let primary: any AgentDeviceRevocationPrimaryFencingV0
    private let refreshInventory: @Sendable () async -> Void
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private var activeReview: LocalInteractiveControlGrantReviewV0?

    package init(
        store: SQLiteSecurityStore,
        primary: any AgentDeviceRevocationPrimaryFencingV0,
        refreshInventory: @escaping @Sendable () async -> Void = {},
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
    ) throws {
        let registry = try InteractiveControlDurableGrantV0.registry()
        self.store = store
        self.registry = registry
        self.primary = primary
        self.refreshInventory = refreshInventory
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        decisions = LocalGrantDecisionHandlerV0(
            persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
            registry: registry
        )
    }

    public func makeReview(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0 {
        let now = wallNowUnixMilliseconds()
        guard now >= request.requestedAtUnixMilliseconds,
              now >= 0,
              now <= 9_007_199_254_440_991 else {
            throw LocalInteractiveControlGrantHandlerErrorV0.invalidTime
        }
        let candidates = try await store.activeDeviceGrantIdentitySnapshots()
            .filter {
                ($0.device.authorization.state == .activeMonitorOnly
                    || $0.device.authorization.state == .activeGranted)
                    && !$0.grants.capabilityIDs.contains(
                        InteractiveControlDurableGrantV0.identifier
                    )
            }
            .sorted {
                if $0.device.createdAtUnixMilliseconds
                    != $1.device.createdAtUnixMilliseconds {
                    return $0.device.createdAtUnixMilliseconds
                        > $1.device.createdAtUnixMilliseconds
                }
                return $0.device.deviceID.uuidString
                    > $1.device.deviceID.uuidString
            }
        guard let snapshot = candidates.first else {
            throw LocalInteractiveControlGrantHandlerErrorV0.deviceUnavailable
        }
        guard let displayName = snapshot.displayName else {
            throw LocalInteractiveControlGrantHandlerErrorV0
                .displayNameUnavailable
        }
        if let activeReview {
            await decisions.cancel(reviewID: activeReview.reviewID)
        }
        let review = try LocalInteractiveControlGrantReviewV0(
            correlationID: request.commandID,
            reviewID: UUID(),
            deviceID: snapshot.device.deviceID,
            deviceDisplayName: displayName,
            authorizationEpoch:
                snapshot.device.authorization.authorizationEpoch,
            grantRevision: snapshot.device.authorization.grantRevision,
            policyRevision: snapshot.device.policyRevision,
            currentGrants: snapshot.grants,
            createdAtUnixMilliseconds: now,
            expiresAtUnixMilliseconds:
                now + InteractiveControlDurableGrantV0
                    .reviewLifetimeMilliseconds
        )
        let pending = try PendingLocalGrantExpansionReviewV0(
            reviewID: review.reviewID,
            deviceID: review.deviceID,
            deviceDisplayName: review.deviceDisplayName,
            authorizationEpoch: review.authorizationEpoch,
            grantRevision: review.grantRevision,
            policyRevision: review.policyRevision,
            currentGrants: review.currentGrantSet(),
            proposedGrants: review.proposedGrantSet(),
            registryGeneration: registry.generation,
            requestedDescriptors: [
                try InteractiveControlDurableGrantV0.descriptor(),
            ]
        )
        try await decisions.register(pending)
        activeReview = review
        return review
    }

    public func decide(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        do {
            return try await decideWithoutLogging(command)
        } catch {
            interactiveControlGrantAgentLoggerV0.error(
                "Decision failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    private func decideWithoutLogging(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        guard let review = activeReview,
              review.reviewID == command.reviewID else {
            throw LocalInteractiveControlGrantHandlerErrorV0.reviewUnavailable
        }
        let now = wallNowUnixMilliseconds()
        guard now >= review.createdAtUnixMilliseconds,
              now < review.expiresAtUnixMilliseconds,
              command.decidedAtUnixMilliseconds >= review.createdAtUnixMilliseconds,
              command.decidedAtUnixMilliseconds < review.expiresAtUnixMilliseconds
        else {
            await decisions.cancel(reviewID: review.reviewID)
            activeReview = nil
            throw LocalInteractiveControlGrantHandlerErrorV0.invalidTime
        }

        if command.decision == .approve {
            await primary.fenceForSecurityAdministration()
        }
        do {
            let receipt = try await decisions.handle(command)
            activeReview = nil
            if command.decision == .approve {
                await refreshInventory()
                await primary.releaseSecurityAdministrationFence()
            }
            return receipt
        } catch {
            activeReview = nil
            if command.decision == .approve {
                await primary.releaseSecurityAdministrationFence()
            }
            throw error
        }
    }

    public func invalidateReview() async {
        if let activeReview {
            await decisions.cancel(reviewID: activeReview.reviewID)
        }
        activeReview = nil
    }
}
#endif
