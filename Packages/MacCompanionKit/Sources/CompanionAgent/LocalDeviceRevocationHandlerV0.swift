#if os(macOS)
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import Foundation

public enum LocalDeviceRevocationHandlerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidTime
    case deviceUnavailable
    case displayNameUnavailable
    case reviewConflict
    case reviewNotCurrent
    case commandConflict
    case resultMismatch
    case statusUnavailable
}

package protocol AgentDeviceRevocationPrimaryFencingV0: Sendable {
    func fenceForSecurityAdministration() async
    func releaseSecurityAdministrationFence() async
}

extension AgentPrimarySessionAuthorityV1:
    AgentDeviceRevocationPrimaryFencingV0 {}

package protocol AgentDeviceRevocationStatusRefreshingV0: Sendable {
    func refreshInventory() async throws
    func refreshSecurity() async -> LocalSecurityPosture
}

extension AgentLocalServiceRootV1:
    AgentDeviceRevocationStatusRefreshingV0 {}

/// Agent-owned, bundle-independent admission for one explicitly reviewed
/// local device revocation. A signed platform adapter may issue this actor only
/// after authenticating and authorizing the visible menu-app endpoint.
public actor LocalDeviceRevocationHandlerV0 {
    private let store: SQLiteSecurityStore
    private let coordinator: DeviceRevocationCoordinator
    private let primary: any AgentDeviceRevocationPrimaryFencingV0
    private let status: any AgentDeviceRevocationStatusRefreshingV0
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private var activeReview: LocalDeviceRevocationReviewV0?
    private var securityFencePendingDeviceID: UUID?

    package init(
        store: SQLiteSecurityStore,
        coordinator: DeviceRevocationCoordinator,
        primary: any AgentDeviceRevocationPrimaryFencingV0,
        status: any AgentDeviceRevocationStatusRefreshingV0,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
    ) {
        self.store = store
        self.coordinator = coordinator
        self.primary = primary
        self.status = status
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
    }

    public func makeReview(
        reviewID: UUID,
        deviceID: UUID
    ) async throws -> LocalDeviceRevocationReviewV0 {
        let now = wallNowUnixMilliseconds()
        guard now >= 0, now <= 9_007_199_254_440_991 else {
            throw LocalDeviceRevocationHandlerErrorV0.invalidTime
        }
        guard let record = try await store.device(deviceID),
              record.authorization.state == .activeMonitorOnly
                || record.authorization.state == .activeGranted
                || record.authorization.state == .suspended else {
            throw LocalDeviceRevocationHandlerErrorV0.deviceUnavailable
        }
        guard let displayName = try await store.deviceDisplayName(deviceID)
        else {
            throw LocalDeviceRevocationHandlerErrorV0
                .displayNameUnavailable
        }
        let review = try LocalDeviceRevocationReviewV0(
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: displayName,
            state: record.authorization.state,
            authorizationEpoch:
                record.authorization.authorizationEpoch,
            grantRevision: record.authorization.grantRevision,
            createdAtUnixMilliseconds: now,
            expiresAtUnixMilliseconds: now + 300_000
        )
        if let activeReview {
            guard activeReview == review else {
                throw LocalDeviceRevocationHandlerErrorV0.reviewConflict
            }
            return activeReview
        }
        activeReview = review
        return review
    }

    public func revoke(
        _ command: LocalDeviceRevocationCommandV0
    ) async throws -> LocalDeviceRevokedReceiptV0 {
        let now = wallNowUnixMilliseconds()
        guard now >= 0, now <= 9_007_199_254_740_991 else {
            throw LocalDeviceRevocationHandlerErrorV0.invalidTime
        }
        let intent = try storedIntent(for: command)
        let durable = try await store.deviceRevocationRecord(
            commandID: command.commandID
        )
        if let durable {
            guard durable.intent == intent else {
                throw LocalDeviceRevocationHandlerErrorV0.commandConflict
            }
            if let stored = durable.receipt {
                switch try await coordinator.recoverReviewedRevocation(
                    occurredAtUnixMilliseconds: now
                ) {
                case .noPendingRevocation:
                    if securityFencePendingDeviceID
                        != command.review.deviceID {
                        let receipt = try localReceipt(from: stored)
                        do {
                            try receipt.validate(against: command)
                        } catch {
                            throw LocalDeviceRevocationHandlerErrorV0
                                .resultMismatch
                        }
                        return receipt
                    }
                case let .convergenceRequired(deviceID):
                    guard deviceID == command.review.deviceID else {
                        throw LocalDeviceRevocationHandlerErrorV0
                            .resultMismatch
                    }
                }
            }
        } else {
            guard now >= command.review.createdAtUnixMilliseconds,
                  now < command.review.expiresAtUnixMilliseconds,
                  activeReview == command.review,
                  try await store.deviceDisplayName(
                    command.review.deviceID
                  ) == command.review.deviceDisplayName else {
                throw LocalDeviceRevocationHandlerErrorV0.reviewNotCurrent
            }
        }

        securityFencePendingDeviceID = command.review.deviceID
        await primary.fenceForSecurityAdministration()
        var storedReceipt = durable?.receipt
        if durable == nil {
            do {
                switch try await coordinator.prepare(intent) {
                case .prepared, .alreadyPrepared:
                    break
                case let .alreadyCompleted(receipt):
                    storedReceipt = receipt
                }
            } catch SecurityStoreError.deviceRevocationConflict {
                activeReview = nil
                if await status.refreshSecurity() == .nominal {
                    await primary.releaseSecurityAdministrationFence()
                    securityFencePendingDeviceID = nil
                }
                throw LocalDeviceRevocationHandlerErrorV0.reviewNotCurrent
            }
        }

        if storedReceipt == nil {
            do {
                switch try await coordinator.revoke(
                    intent: intent,
                    occurredAtUnixMilliseconds: now
                ) {
                case let .committed(_, receipt),
                     let .alreadyDurable(_, receipt):
                    storedReceipt = receipt
                }
            } catch DeviceRevocationCoordinatorError.staleReview {
                activeReview = nil
                throw LocalDeviceRevocationHandlerErrorV0.reviewNotCurrent
            }
        }
        guard let storedReceipt else {
            throw LocalDeviceRevocationHandlerErrorV0.resultMismatch
        }

        do {
            try await status.refreshInventory()
        } catch {
            throw LocalDeviceRevocationHandlerErrorV0.statusUnavailable
        }
        do {
            try await coordinator.finishStatusConvergence(
                deviceID: command.review.deviceID,
                occurredAtUnixMilliseconds: now
            )
        } catch {
            throw LocalDeviceRevocationHandlerErrorV0.statusUnavailable
        }
        guard await status.refreshSecurity() == .nominal else {
            throw LocalDeviceRevocationHandlerErrorV0.statusUnavailable
        }

        let receipt = try localReceipt(from: storedReceipt)
        do {
            try receipt.validate(against: command)
        } catch {
            throw LocalDeviceRevocationHandlerErrorV0.resultMismatch
        }
        activeReview = nil
        await primary.releaseSecurityAdministrationFence()
        securityFencePendingDeviceID = nil
        return receipt
    }

    public func invalidateReview() {
        activeReview = nil
    }

    private func storedIntent(
        for command: LocalDeviceRevocationCommandV0
    ) throws -> StoredDeviceRevocationIntent {
        try StoredDeviceRevocationIntent(
            commandID: command.commandID,
            reviewID: command.review.reviewID,
            deviceID: command.review.deviceID,
            deviceDisplayName: command.review.deviceDisplayName,
            reviewedState: command.review.state,
            authorizationEpoch: command.review.authorizationEpoch,
            grantRevision: command.review.grantRevision,
            reviewCreatedAtUnixMilliseconds:
                command.review.createdAtUnixMilliseconds,
            reviewExpiresAtUnixMilliseconds:
                command.review.expiresAtUnixMilliseconds,
            confirmedAtUnixMilliseconds:
                command.confirmedAtUnixMilliseconds
        )
    }

    private func localReceipt(
        from stored: StoredDeviceRevocationReceipt
    ) throws -> LocalDeviceRevokedReceiptV0 {
        try LocalDeviceRevokedReceiptV0(
            correlationID: stored.commandID,
            reviewID: stored.reviewID,
            deviceID: stored.deviceID,
            authorizationEpoch: stored.authorizationEpoch,
            grantRevision: stored.grantRevision,
            completedAtUnixMilliseconds:
                stored.completedAtUnixMilliseconds
        )
    }
}
#endif
