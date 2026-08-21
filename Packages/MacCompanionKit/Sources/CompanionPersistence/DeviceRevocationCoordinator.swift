#if os(macOS)
import CompanionDomain
import Foundation

public enum DeviceRevocationResult: Equatable, Sendable {
    case committed(StoredDeviceRecord)
    case alreadyDurable(StoredDeviceRecord)
}

public enum PendingRevocationRecoveryResult: Equatable, Sendable {
    case noPendingRevocation
    case committed(UUID)
    case alreadyDurable(UUID)
}

public enum ReviewedDeviceRevocationRecoveryResult: Equatable, Sendable {
    case noPendingRevocation
    case convergenceRequired(UUID)
}

public enum DeviceRevocationCoordinatorError: Error, Equatable, Sendable {
    case latchRequiresLocalRepair
    case unrelatedDenyLatchActive
    case deviceNotFound(UUID)
    case staleReview
}

public struct DeviceRevocationExpectation: Equatable, Sendable {
    public let deviceID: UUID
    public let state: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision

    public init(
        deviceID: UUID,
        state: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision
    ) throws {
        guard state == .activeMonitorOnly
                || state == .activeGranted
                || state == .suspended,
              authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1 else {
            throw DeviceRevocationCoordinatorError.staleReview
        }
        self.deviceID = deviceID
        self.state = state
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
    }
}

/// Owns the crash-safe ordering between the preallocated deny latch and the
/// SQLite device transaction. Callers must close remote work as soon as this
/// coordinator begins and must keep it closed whenever an error is returned.
public actor DeviceRevocationCoordinator {
    private let securityStore: SQLiteSecurityStore
    private let denyLatch: EmergencyDenyLatch

    public init(
        securityStore: SQLiteSecurityStore,
        denyLatch: EmergencyDenyLatch
    ) {
        self.securityStore = securityStore
        self.denyLatch = denyLatch
    }

    public func prepare(
        _ intent: StoredDeviceRevocationIntent
    ) async throws -> DeviceRevocationPrepareResult {
        try await securityStore.beginDeviceRevocation(intent)
    }

    /// Completes an already durable local command but intentionally retains
    /// the latch. The caller must refresh inventory, clear the matching latch,
    /// publish nominal security posture, and only then reopen primary ingress.
    public func revoke(
        intent: StoredDeviceRevocationIntent,
        occurredAtUnixMilliseconds: Int64
    ) async throws -> DeviceRevocationCommitResult {
        let latch = try await denyLatch.snapshot()
        switch latch.health {
        case .corrupt:
            throw DeviceRevocationCoordinatorError.latchRequiresLocalRepair
        case .active:
            guard latch.reason == .revocationInProgress,
                  latch.pendingDeviceID == intent.deviceID else {
                throw DeviceRevocationCoordinatorError
                    .unrelatedDenyLatchActive
            }
        case .clear:
            _ = try await denyLatch.activate(
                pendingDeviceID: intent.deviceID,
                reason: .revocationInProgress,
                recordedAtUnixMilliseconds:
                    occurredAtUnixMilliseconds
            )
        }
        do {
            return try await securityStore.completeDeviceRevocation(
                intent,
                occurredAtUnixMilliseconds:
                    occurredAtUnixMilliseconds
            )
        } catch SecurityStoreError.deviceRevocationConflict {
            throw DeviceRevocationCoordinatorError.staleReview
        }
    }

    public func finishStatusConvergence(
        deviceID: UUID,
        occurredAtUnixMilliseconds: Int64
    ) async throws {
        let latch = try await denyLatch.snapshot()
        switch latch.health {
        case .corrupt:
            throw DeviceRevocationCoordinatorError.latchRequiresLocalRepair
        case .active:
            guard latch.reason == .revocationInProgress,
                  latch.pendingDeviceID == deviceID else {
                throw DeviceRevocationCoordinatorError
                    .unrelatedDenyLatchActive
            }
            _ = try await denyLatch.clear(
                recordedAtUnixMilliseconds:
                    occurredAtUnixMilliseconds
            )
        case .clear:
            return
        }
    }

    /// Reconciles both schema-v8 accepted commands and the legacy v7 latch.
    /// A convergence result always leaves or installs the matching latch so
    /// product bootstrap can project inventory/security before ingress opens.
    public func recoverReviewedRevocation(
        occurredAtUnixMilliseconds: Int64
    ) async throws -> ReviewedDeviceRevocationRecoveryResult {
        if let pending = try await securityStore
            .pendingDeviceRevocationIntent() {
            _ = try await revoke(
                intent: pending,
                occurredAtUnixMilliseconds:
                    occurredAtUnixMilliseconds
            )
            return .convergenceRequired(pending.deviceID)
        }

        let latch = try await denyLatch.snapshot()
        switch latch.health {
        case .clear:
            return .noPendingRevocation
        case .corrupt:
            throw DeviceRevocationCoordinatorError.latchRequiresLocalRepair
        case .active:
            guard latch.reason == .revocationInProgress,
                  let deviceID = latch.pendingDeviceID else {
                throw DeviceRevocationCoordinatorError
                    .unrelatedDenyLatchActive
            }
            if let durable = try await securityStore
                .deviceRevocationRecord(deviceID: deviceID) {
                guard durable.receipt != nil else {
                    throw DeviceRevocationCoordinatorError.staleReview
                }
                return .convergenceRequired(deviceID)
            }
            guard let current = try await securityStore.device(deviceID)
            else {
                throw DeviceRevocationCoordinatorError.deviceNotFound(
                    deviceID
                )
            }
            if current.authorization.state != .revoked {
                _ = try await securityStore.transitionDevice(
                    deviceID,
                    event: .revoke,
                    occurredAtUnixMilliseconds:
                        occurredAtUnixMilliseconds
                )
            }
            return .convergenceRequired(deviceID)
        }
    }

    public func revoke(
        deviceID: UUID,
        occurredAtUnixMilliseconds: Int64
    ) async throws -> DeviceRevocationResult {
        try await revoke(
            deviceID: deviceID,
            expected: nil,
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
        )
    }

    public func revoke(
        expected: DeviceRevocationExpectation,
        occurredAtUnixMilliseconds: Int64
    ) async throws -> DeviceRevocationResult {
        try await revoke(
            deviceID: expected.deviceID,
            expected: expected,
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
        )
    }

    private func revoke(
        deviceID: UUID,
        expected: DeviceRevocationExpectation?,
        occurredAtUnixMilliseconds: Int64
    ) async throws -> DeviceRevocationResult {
        let latch = try await denyLatch.snapshot()
        let activatedHere: Bool
        switch latch.health {
        case .corrupt:
            throw DeviceRevocationCoordinatorError.latchRequiresLocalRepair
        case .active:
            guard latch.reason == .revocationInProgress,
                  latch.pendingDeviceID == deviceID else {
                throw DeviceRevocationCoordinatorError.unrelatedDenyLatchActive
            }
            activatedHere = false
        case .clear:
            _ = try await denyLatch.activate(
                pendingDeviceID: deviceID,
                reason: .revocationInProgress,
                recordedAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            activatedHere = true
        }

        guard let current = try await securityStore.device(deviceID) else {
            throw DeviceRevocationCoordinatorError.deviceNotFound(deviceID)
        }
        if current.authorization.state == .revoked {
            if let expected {
                guard current.authorization.authorizationEpoch
                        == (try expected.authorizationEpoch.advanced()),
                      current.authorization.grantRevision
                        == (try expected.grantRevision.advanced()) else {
                    if activatedHere {
                        _ = try await denyLatch.clear(
                            recordedAtUnixMilliseconds:
                                occurredAtUnixMilliseconds
                        )
                    }
                    throw DeviceRevocationCoordinatorError.staleReview
                }
            }
            _ = try await denyLatch.clear(
                recordedAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            return .alreadyDurable(current)
        }
        if let expected,
           current.deviceID != expected.deviceID
                || current.authorization.state != expected.state
                || current.authorization.authorizationEpoch
                    != expected.authorizationEpoch
                || current.authorization.grantRevision
                    != expected.grantRevision {
            if activatedHere {
                _ = try await denyLatch.clear(
                    recordedAtUnixMilliseconds:
                        occurredAtUnixMilliseconds
                )
            }
            throw DeviceRevocationCoordinatorError.staleReview
        }

        guard let revoked = try await securityStore.transitionDevice(
            deviceID,
            event: .revoke,
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
        ) else {
            throw DeviceRevocationCoordinatorError.deviceNotFound(deviceID)
        }
        _ = try await denyLatch.clear(
            recordedAtUnixMilliseconds: occurredAtUnixMilliseconds
        )
        return .committed(revoked)
    }

    public func recoverPendingRevocation(
        occurredAtUnixMilliseconds: Int64
    ) async throws -> PendingRevocationRecoveryResult {
        let latch = try await denyLatch.snapshot()
        switch latch.health {
        case .clear:
            return .noPendingRevocation
        case .corrupt:
            throw DeviceRevocationCoordinatorError.latchRequiresLocalRepair
        case .active:
            guard latch.reason == .revocationInProgress,
                  let deviceID = latch.pendingDeviceID else {
                throw DeviceRevocationCoordinatorError.unrelatedDenyLatchActive
            }
            let result = try await revoke(
                deviceID: deviceID,
                occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
            )
            switch result {
            case .committed:
                return .committed(deviceID)
            case .alreadyDurable:
                return .alreadyDurable(deviceID)
            }
        }
    }
}
#endif
