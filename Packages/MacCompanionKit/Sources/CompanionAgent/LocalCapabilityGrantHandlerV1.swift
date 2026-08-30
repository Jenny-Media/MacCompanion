#if os(macOS)
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import CompanionWire
import Foundation

public enum LocalCapabilityGrantHandlerErrorV1: Error, Equatable, Sendable {
    case unavailable
    case busy
    case invalidTime
    case requestMismatch
    case deviceUnavailable
    case capabilityUnavailable
    case alreadyGranted
    case reviewUnavailable
}

/// One authenticated menu generation owns this review authority. All grant
/// mutation goes through the same publication owner used by remote operations.
public actor LocalCapabilityGrantHandlerV1 {
    private let store: SQLiteSecurityStore
    private let capabilities: AgentCapabilityAuthorityV1
    private let primary: any AgentDeviceRevocationPrimaryFencingV0
    private let refreshInventory: @Sendable () async -> Void
    private let now: @Sendable () -> Int64
    private var active: (request: LocalCapabilityGrantReviewRequestV1, review: LocalCapabilityGrantReviewV1)?
    private var completions: [UUID: (LocalGrantDecisionCommandV0, LocalGrantDecisionReceiptV0)] = [:]
    private var completionOrder: [UUID] = []
    private var busy = false
    private var invalidated = false

    package init(store: SQLiteSecurityStore, capabilities: AgentCapabilityAuthorityV1,
                 primary: any AgentDeviceRevocationPrimaryFencingV0,
                 refreshInventory: @escaping @Sendable () async -> Void = {},
                 wallNowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
                     Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
                 }) {
        self.store = store
        self.capabilities = capabilities
        self.primary = primary
        self.refreshInventory = refreshInventory
        now = wallNowUnixMilliseconds
    }

    public func makeReview(_ request: LocalCapabilityGrantReviewRequestV1) async throws -> LocalCapabilityGrantReviewV1 {
        try begin()
        defer { busy = false }
        let time = now()
        guard time >= request.requestedAtUnixMilliseconds,
              time - request.requestedAtUnixMilliseconds < LocalCapabilityGrantReviewV1.lifetimeMilliseconds,
              time <= 9_007_199_254_440_991 else { throw LocalCapabilityGrantHandlerErrorV1.invalidTime }
        if let active, active.request.commandID == request.commandID {
            guard active.request == request else { throw LocalCapabilityGrantHandlerErrorV1.requestMismatch }
            guard time < active.review.expiresAtUnixMilliseconds else { throw LocalCapabilityGrantHandlerErrorV1.invalidTime }
            // Retry never publishes changed registry facts under the old review.
            let registry = await capabilities.registrySnapshot()
            let snapshot = try await store.deviceGrantIdentitySnapshot(request.deviceID)
            guard !invalidated, registry.generation == active.review.registryGeneration,
                  registry.capability(request.capabilityID) == (try active.review.descriptor.domainValue()),
                  snapshot.displayName == active.review.deviceDisplayName,
                  snapshot.grants.capabilityIDs == active.review.currentGrantIDs,
                  snapshot.device.authorization.authorizationEpoch == active.review.authorizationEpoch,
                  snapshot.device.authorization.grantRevision == active.review.grantRevision,
                  snapshot.device.policyRevision == active.review.policyRevision,
                  snapshot.device.authorization.state == .activeMonitorOnly || snapshot.device.authorization.state == .activeGranted else {
                throw LocalCapabilityGrantHandlerErrorV1.capabilityUnavailable
            }
            return active.review
        }
        if let previous = active {
            active = nil
            try await capabilities.cancelGrantReview(reviewID: previous.review.reviewID)
        }
        let registry = await capabilities.registrySnapshot()
        guard let descriptor = registry.capability(request.capabilityID),
              descriptor.capabilityID != InteractiveControlDurableGrantV0.identifier else {
            throw LocalCapabilityGrantHandlerErrorV1.capabilityUnavailable
        }
        let snapshot = try await store.deviceGrantIdentitySnapshot(request.deviceID)
        guard let name = snapshot.displayName,
              snapshot.device.authorization.state == .activeMonitorOnly || snapshot.device.authorization.state == .activeGranted else {
            throw LocalCapabilityGrantHandlerErrorV1.deviceUnavailable
        }
        guard !snapshot.grants.capabilityIDs.contains(request.capabilityID) else { throw LocalCapabilityGrantHandlerErrorV1.alreadyGranted }
        guard !invalidated else { throw LocalCapabilityGrantHandlerErrorV1.unavailable }
        let review = try LocalCapabilityGrantReviewV1(correlationID: request.commandID, reviewID: UUID(),
            deviceID: request.deviceID, deviceDisplayName: name,
            authorizationEpoch: snapshot.device.authorization.authorizationEpoch,
            grantRevision: snapshot.device.authorization.grantRevision, policyRevision: snapshot.device.policyRevision,
            currentGrantIDs: snapshot.grants.capabilityIDs, registryGeneration: registry.generation,
            descriptor: LocalCapabilityGrantDescriptorV1(descriptor), createdAtUnixMilliseconds: time,
            expiresAtUnixMilliseconds: time + LocalCapabilityGrantReviewV1.lifetimeMilliseconds)
        try await capabilities.registerGrantReview(PendingLocalGrantExpansionReviewV0(
            reviewID: review.reviewID, deviceID: review.deviceID, deviceDisplayName: review.deviceDisplayName,
            authorizationEpoch: review.authorizationEpoch, grantRevision: review.grantRevision, policyRevision: review.policyRevision,
            currentGrants: snapshot.grants, proposedGrants: CapabilityGrantSet(snapshot.grants.capabilityIDs + [request.capabilityID]),
            registryGeneration: registry.generation, requestedDescriptors: [descriptor]))
        guard !invalidated else {
            try? await capabilities.cancelGrantReview(reviewID: review.reviewID)
            throw LocalCapabilityGrantHandlerErrorV1.unavailable
        }
        active = (request, review)
        return review
    }

    public func decide(_ command: LocalGrantDecisionCommandV0) async throws -> LocalGrantDecisionReceiptV0 {
        try begin()
        defer { busy = false }
        if let (original, receipt) = completions[command.commandID] {
            guard original == command else { throw LocalCapabilityGrantHandlerErrorV1.requestMismatch }
            return receipt
        }
        guard let pending = active, pending.review.reviewID == command.reviewID else { throw LocalCapabilityGrantHandlerErrorV1.reviewUnavailable }
        active = nil
        let time = now()
        guard time >= pending.review.createdAtUnixMilliseconds, time < pending.review.expiresAtUnixMilliseconds,
              command.decidedAtUnixMilliseconds >= pending.review.createdAtUnixMilliseconds,
              command.decidedAtUnixMilliseconds <= time else {
            try? await capabilities.cancelGrantReview(reviewID: pending.review.reviewID)
            throw LocalCapabilityGrantHandlerErrorV1.invalidTime
        }
        // Reject mismatches before causing even a primary-session disruption.
        guard command == (try pending.review.command(commandID: command.commandID, decision: command.decision,
            decidedAtUnixMilliseconds: command.decidedAtUnixMilliseconds)) else {
            try? await capabilities.cancelGrantReview(reviewID: pending.review.reviewID)
            throw LocalCapabilityGrantHandlerErrorV1.requestMismatch
        }
        if command.decision == .approve { await primary.fenceForSecurityAdministration() }
        do {
            // Publication and SQLite fences revalidate here, after the await.
            let receipt = try await capabilities.handleGrantDecision(command)
            completions[command.commandID] = (command, receipt)
            completionOrder.append(command.commandID)
            if completionOrder.count > LocalGrantDecisionHandlerV0.maximumCompletedDecisions {
                completions.removeValue(forKey: completionOrder.removeFirst())
            }
            if command.decision == .approve {
                await refreshInventory()
                await primary.releaseSecurityAdministrationFence()
            }
            return receipt
        } catch {
            try? await capabilities.cancelGrantReview(reviewID: pending.review.reviewID)
            if command.decision == .approve { await primary.releaseSecurityAdministrationFence() }
            throw error
        }
    }

    public func invalidateReview() async {
        invalidated = true
        if let pending = active {
            active = nil
            try? await capabilities.cancelGrantReview(reviewID: pending.review.reviewID)
        }
        completions.removeAll()
        completionOrder.removeAll()
    }

    private func begin() throws {
        guard !invalidated else { throw LocalCapabilityGrantHandlerErrorV1.unavailable }
        guard !busy else { throw LocalCapabilityGrantHandlerErrorV1.busy }
        busy = true
    }
}
#endif
