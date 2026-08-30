import CompanionInteractiveShared
import CompanionIPC
import CompanionDomain
import Foundation

public enum InteractiveSurfaceRuntimeCoordinatorStateV0:
    Equatable,
    Sendable
{
    case awaitingInitialAcknowledgement(commandID: UUID)
    case active
    case transitioning(commandID: UUID)
    case awaitingAcknowledgement(commandID: UUID)
    case ended
    case safetyRecoveryRequired
}

public enum InteractiveSurfaceRuntimeCoordinatorErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidInitialBinding
    case invalidState(InteractiveSurfaceRuntimeCoordinatorStateV0)
    case invalidTime
    case runtimeRejected
    case runtimeReceiptMismatch
    case safetyRecoveryRequired
}

public protocol InteractiveSurfaceRuntimeRoutingV0: Sendable {
    func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0

    func acknowledgeSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0

    /// Converges the exact session to complete menu-runtime teardown even when
    /// the preceding IPC result was ambiguous. `true` is an authoritative
    /// no-runtime-remains result; `false` is safety-recovery-required.
    func terminateSurfaceFailure(
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) async throws -> Bool
}

public struct InteractiveSurfaceRuntimePreparedV0: Equatable, Sendable {
    public let command: InteractiveRuntimeSurfaceTransitionCommandV0
    public let receipt: InteractiveRuntimeSurfaceTransitionReceiptV0
    public let descriptor: AdaptiveSurfaceDescriptor
    public let effects: [AdaptiveSurfaceEffect]

    public init(
        command: InteractiveRuntimeSurfaceTransitionCommandV0,
        receipt: InteractiveRuntimeSurfaceTransitionReceiptV0,
        descriptor: AdaptiveSurfaceDescriptor,
        effects: [AdaptiveSurfaceEffect]
    ) {
        self.command = command
        self.receipt = receipt
        self.descriptor = descriptor
        self.effects = effects
    }
}

public struct InteractiveSurfaceRuntimeAcknowledgedV0:
    Equatable,
    Sendable
{
    public let command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    public let receipt: InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    public let effects: [AdaptiveSurfaceEffect]

    public init(
        command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        receipt: InteractiveRuntimeSurfaceAcknowledgementReceiptV0,
        effects: [AdaptiveSurfaceEffect]
    ) {
        self.command = command
        self.receipt = receipt
        self.effects = effects
    }
}

public struct InteractiveInitialSurfaceRuntimeV0: Equatable, Sendable {
    public let activationID: UUID
    public let descriptor: AdaptiveSurfaceDescriptor
    public let lease: InteractiveExecutionLease

    public init(
        activationID: UUID,
        descriptor: AdaptiveSurfaceDescriptor,
        lease: InteractiveExecutionLease
    ) {
        self.activationID = activationID
        self.descriptor = descriptor
        self.lease = lease
    }
}

/// The Agent-owned serialized authority spanning the pure surface state machine
/// and authenticated menu-runtime IPC. It never publishes a descriptor before
/// the runtime has suppressed old input/output and accepted the replacement
/// lease, and it never reactivates Agent input before the runtime accepts the
/// exact clean-media acknowledgement.
public actor InteractiveSurfaceRuntimeCoordinatorV0 {
    private struct SelectionRequest: Equatable, Sendable {
        let target: AdaptiveSurfaceDescriptor
        let expectedSurfaceRevision:
            CompanionInteractiveShared.SurfaceRevision
        let expectedCoordinateSpaceRevision:
            CoordinateSpaceRevision
        let selectedDisplayID: UUID?
        let monotonicNowMilliseconds: Int64
        let monotonicNowNanoseconds: UInt64
    }

    private struct AcknowledgementRequest: Equatable, Sendable {
        let fence: SurfaceInputFence
        let readyMediaSequence: UInt64
        let monotonicNowMilliseconds: Int64
        let monotonicNowNanoseconds: UInt64
    }

    private let runtime: any InteractiveSurfaceRuntimeRoutingV0
    private let identifier: @Sendable () -> UUID
    private let sessionDeadlineMonotonicNanoseconds: UInt64
    private let sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    private var surfaceAuthority: AdaptiveSurfaceAuthority
    private var currentLease: InteractiveExecutionLease
    private var stateStorage:
        InteractiveSurfaceRuntimeCoordinatorStateV0 = .active
    private var lastSelectionRequest: SelectionRequest?
    private var lastPrepared: InteractiveSurfaceRuntimePreparedV0?
    private var lastAcknowledgementRequest: AcknowledgementRequest?
    private var lastAcknowledged: InteractiveSurfaceRuntimeAcknowledgedV0?

    public init(
        surfaceAuthority: AdaptiveSurfaceAuthority,
        currentLease: InteractiveExecutionLease,
        sessionDeadlineMonotonicNanoseconds: UInt64,
        runtime: any InteractiveSurfaceRuntimeRoutingV0,
        initialActivationCommandID: UUID? = nil,
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        guard case let .active(descriptor) = surfaceAuthority.phase,
              Self.matches(descriptor, lease: currentLease),
              sessionDeadlineMonotonicNanoseconds
                >= currentLease.expiresAtMonotonicNanoseconds else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidInitialBinding
        }
        self.surfaceAuthority = surfaceAuthority
        self.currentLease = currentLease
        self.sessionDeadlineMonotonicNanoseconds
            = sessionDeadlineMonotonicNanoseconds
        sessionAllowedInteractionClasses
            = Set(currentLease.allowedInteractionClasses)
        self.runtime = runtime
        self.identifier = identifier
        if let initialActivationCommandID {
            stateStorage = .awaitingInitialAcknowledgement(
                commandID: initialActivationCommandID
            )
        }
    }

    public func state() -> InteractiveSurfaceRuntimeCoordinatorStateV0 {
        stateStorage
    }

    public func lease() -> InteractiveExecutionLease { currentLease }

    public func currentDescriptor() throws -> AdaptiveSurfaceDescriptor {
        guard stateStorage == .active,
              case let .active(descriptor) = surfaceAuthority.phase else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidState(stateStorage)
        }
        return descriptor
    }

    /// Mirrors an already accepted same-surface runtime renewal into the
    /// surface authority. Surface selection remains the only operation that
    /// can change surface or coordinate revisions.
    public func adoptRenewedLease(
        _ replacement: InteractiveExecutionLease
    ) throws {
        guard replacement.hostID == currentLease.hostID,
              replacement.deviceID == currentLease.deviceID,
              replacement.interactiveSessionID
                == currentLease.interactiveSessionID,
              replacement.authorizationEpoch
                == currentLease.authorizationEpoch,
              replacement.selectedDisplayID
                == currentLease.selectedDisplayID,
              replacement.surfaceID == currentLease.surfaceID,
              replacement.surfaceRevision == currentLease.surfaceRevision,
              replacement.coordinateRevision
                == currentLease.coordinateRevision,
              replacement.allowedInteractionClasses
                == currentLease.allowedInteractionClasses,
              replacement.renewalCounter
                == currentLease.renewalCounter + 1,
              replacement.issuedAtMonotonicNanoseconds
                >= currentLease.issuedAtMonotonicNanoseconds,
              replacement.expiresAtMonotonicNanoseconds
                > replacement.issuedAtMonotonicNanoseconds,
              replacement.expiresAtMonotonicNanoseconds
                <= sessionDeadlineMonotonicNanoseconds,
              stateStorage != .ended,
              stateStorage != .safetyRecoveryRequired else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.invalidTime
        }
        currentLease = replacement
    }

    public func initialActivation() throws -> InteractiveInitialSurfaceRuntimeV0 {
        guard case let .awaitingInitialAcknowledgement(commandID) = stateStorage,
              case let .active(descriptor) = surfaceAuthority.phase else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidState(stateStorage)
        }
        return InteractiveInitialSurfaceRuntimeV0(
            activationID: commandID,
            descriptor: descriptor,
            lease: currentLease
        )
    }

    public func acknowledgeInitial(
        fence: SurfaceInputFence,
        readyMediaSequence: UInt64,
        monotonicNowMilliseconds: Int64,
        monotonicNowNanoseconds: UInt64
    ) async throws -> InteractiveSurfaceRuntimeAcknowledgedV0 {
        guard case let .awaitingInitialAcknowledgement(commandID) = stateStorage,
              case let .active(descriptor) = surfaceAuthority.phase,
              readyMediaSequence > 0,
              monotonicNowNanoseconds >= currentLease.issuedAtMonotonicNanoseconds,
              monotonicNowNanoseconds < currentLease.expiresAtMonotonicNanoseconds else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidState(stateStorage)
        }
        do {
            try surfaceAuthority.validateInput(
                fence,
                requiresFocusBinding: false,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidInitialBinding
        }
        let command = try InteractiveRuntimeSurfaceAcknowledgementCommandV0(
            commandID: identifier(),
            transitionCommandID: commandID,
            leaseID: currentLease.leaseID,
            interactiveSessionID: descriptor.interactiveSessionID,
            surfaceID: descriptor.surfaceID,
            surfaceRevision: currentLease.surfaceRevision,
            coordinateRevision: currentLease.coordinateRevision,
            readyMediaSequence: readyMediaSequence
        )
        let receipt: InteractiveRuntimeSurfaceAcknowledgementReceiptV0
        do {
            receipt = try await runtime.acknowledgeSurface(
                command,
                nowMonotonicNanoseconds: monotonicNowNanoseconds
            )
            try receipt.validate(against: command)
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.runtimeRejected
        }
        stateStorage = .active
        return InteractiveSurfaceRuntimeAcknowledgedV0(
            command: command,
            receipt: receipt,
            effects: [.resumeInput]
        )
    }

    public func prepareSelection(
        target: AdaptiveSurfaceDescriptor,
        expectedSurfaceRevision:
            CompanionInteractiveShared.SurfaceRevision,
        expectedCoordinateSpaceRevision: CoordinateSpaceRevision,
        selectedDisplayID: UUID? = nil,
        monotonicNowMilliseconds: Int64,
        monotonicNowNanoseconds: UInt64
    ) async throws -> InteractiveSurfaceRuntimePreparedV0 {
        let request = SelectionRequest(
            target: target,
            expectedSurfaceRevision: expectedSurfaceRevision,
            expectedCoordinateSpaceRevision:
                expectedCoordinateSpaceRevision,
            selectedDisplayID: selectedDisplayID,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            monotonicNowNanoseconds: monotonicNowNanoseconds
        )
        if request == lastSelectionRequest, let lastPrepared {
            return lastPrepared
        }
        guard stateStorage == .active else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidState(stateStorage)
        }
        guard Set(target.interactionClasses)
                .isSubset(of: sessionAllowedInteractionClasses),
              monotonicNowNanoseconds
                >= currentLease.issuedAtMonotonicNanoseconds,
              monotonicNowNanoseconds
                < currentLease.expiresAtMonotonicNanoseconds else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.invalidTime
        }

        let originalAuthority = surfaceAuthority
        var candidateAuthority = surfaceAuthority
        let requestEffects: [AdaptiveSurfaceEffect]
        do {
            requestEffects = try candidateAuthority.requestSelection(
                target: target,
                expectedSurfaceRevision: expectedSurfaceRevision,
                expectedCoordinateSpaceRevision:
                    expectedCoordinateSpaceRevision,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            throw error
        }

        let lease: InteractiveExecutionLease
        let command: InteractiveRuntimeSurfaceTransitionCommandV0
        do {
            lease = try makeReplacementLease(
                target: target,
                selectedDisplayID: selectedDisplayID,
                monotonicNowNanoseconds: monotonicNowNanoseconds
            )
            command = try InteractiveRuntimeSurfaceTransitionCommandV0(
                commandID: identifier(),
                previousLeaseID: currentLease.leaseID,
                replacement: lease,
                descriptor: target
            )
            try command.validate(
                current: currentLease,
                sessionAllowedInteractionClasses:
                    sessionAllowedInteractionClasses
            )
        } catch {
            surfaceAuthority = originalAuthority
            throw error
        }

        surfaceAuthority = candidateAuthority
        stateStorage = .transitioning(commandID: command.commandID)
        let receipt: InteractiveRuntimeSurfaceTransitionReceiptV0
        do {
            receipt = try await runtime.prepareSurfaceTransition(
                command,
                nowMonotonicNanoseconds: monotonicNowNanoseconds
            )
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .runtimeRejected
        }
        do {
            try receipt.validate(against: command)
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .runtimeReceiptMismatch
        }

        do {
            let committedEffects = try candidateAuthority.executorCommitted(
                descriptor: target,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            currentLease = lease
            surfaceAuthority = candidateAuthority
            stateStorage = .awaitingAcknowledgement(
                commandID: command.commandID
            )
            let result = InteractiveSurfaceRuntimePreparedV0(
                command: command,
                receipt: receipt,
                descriptor: target,
                effects: requestEffects + committedEffects
            )
            lastSelectionRequest = request
            lastPrepared = result
            lastAcknowledgementRequest = nil
            lastAcknowledged = nil
            return result
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw error
        }
    }

    public func acknowledge(
        fence: SurfaceInputFence,
        readyMediaSequence: UInt64,
        monotonicNowMilliseconds: Int64,
        monotonicNowNanoseconds: UInt64
    ) async throws -> InteractiveSurfaceRuntimeAcknowledgedV0 {
        let request = AcknowledgementRequest(
            fence: fence,
            readyMediaSequence: readyMediaSequence,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            monotonicNowNanoseconds: monotonicNowNanoseconds
        )
        if request == lastAcknowledgementRequest, let lastAcknowledged {
            return lastAcknowledged
        }
        guard case let .awaitingAcknowledgement(transitionCommandID)
                = stateStorage else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .invalidState(stateStorage)
        }
        guard monotonicNowNanoseconds
                >= currentLease.issuedAtMonotonicNanoseconds,
              monotonicNowNanoseconds
                < currentLease.expiresAtMonotonicNanoseconds,
              readyMediaSequence > 0 else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.invalidTime
        }

        var candidateAuthority = surfaceAuthority
        let effects = try candidateAuthority.acknowledge(
            fence,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        let command = try
            InteractiveRuntimeSurfaceAcknowledgementCommandV0(
                commandID: identifier(),
                transitionCommandID: transitionCommandID,
                leaseID: currentLease.leaseID,
                interactiveSessionID:
                    currentLease.interactiveSessionID,
                surfaceID: currentLease.surfaceID,
                surfaceRevision: currentLease.surfaceRevision,
                coordinateRevision: currentLease.coordinateRevision,
                focusToken: fence.focusToken,
                focusRevision: fence.focusRevision,
                readyMediaSequence: readyMediaSequence
            )
        let receipt: InteractiveRuntimeSurfaceAcknowledgementReceiptV0
        do {
            receipt = try await runtime.acknowledgeSurface(
                command,
                nowMonotonicNanoseconds: monotonicNowNanoseconds
            )
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .runtimeRejected
        }
        do {
            try receipt.validate(against: command)
        } catch {
            try await failClosedAfterAmbiguousRuntimeResult()
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .runtimeReceiptMismatch
        }

        surfaceAuthority = candidateAuthority
        stateStorage = .active
        let result = InteractiveSurfaceRuntimeAcknowledgedV0(
            command: command,
            receipt: receipt,
            effects: effects
        )
        lastAcknowledgementRequest = request
        lastAcknowledged = result
        return result
    }

    private func makeReplacementLease(
        target: AdaptiveSurfaceDescriptor,
        selectedDisplayID: UUID?,
        monotonicNowNanoseconds: UInt64
    ) throws -> InteractiveExecutionLease {
        let (maximumExpiry, overflow) = monotonicNowNanoseconds
            .addingReportingOverflow(
                InteractiveExecutionLease.maximumLifetimeNanoseconds
            )
        guard !overflow else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.invalidTime
        }
        let expiry = min(
            maximumExpiry,
            sessionDeadlineMonotonicNanoseconds
        )
        guard expiry > monotonicNowNanoseconds else {
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0.invalidTime
        }
        return try InteractiveExecutionLease(
            leaseID: identifier(),
            hostID: currentLease.hostID,
            deviceID: currentLease.deviceID,
            interactiveSessionID: currentLease.interactiveSessionID,
            authorizationEpoch: currentLease.authorizationEpoch,
            selectedDisplayID:
                selectedDisplayID ?? currentLease.selectedDisplayID,
            surfaceID: target.surfaceID,
            surfaceRevision: .init(
                rawValue: target.surfaceRevision.rawValue
            ),
            coordinateRevision: .init(
                rawValue: target.coordinateSpaceRevision.rawValue
            ),
            allowedInteractionClasses:
                Set(target.interactionClasses),
            renewalCounter: currentLease.renewalCounter + 1,
            issuedAtMonotonicNanoseconds: monotonicNowNanoseconds,
            expiresAtMonotonicNanoseconds: expiry
        )
    }

    private func failClosedAfterAmbiguousRuntimeResult() async throws {
        let terminated: Bool
        do {
            terminated = try await runtime.terminateSurfaceFailure(
                interactiveSessionID: currentLease.interactiveSessionID,
                reason: .protocolViolation
            )
        } catch {
            stateStorage = .safetyRecoveryRequired
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .safetyRecoveryRequired
        }
        guard terminated else {
            stateStorage = .safetyRecoveryRequired
            throw InteractiveSurfaceRuntimeCoordinatorErrorV0
                .safetyRecoveryRequired
        }
        _ = try? surfaceAuthority.end()
        stateStorage = .ended
    }

    private static func matches(
        _ descriptor: AdaptiveSurfaceDescriptor,
        lease: InteractiveExecutionLease
    ) -> Bool {
        descriptor.interactiveSessionID == lease.interactiveSessionID
            && descriptor.authorizationEpoch == lease.authorizationEpoch
            && descriptor.surfaceID == lease.surfaceID
            && descriptor.surfaceRevision.rawValue
                == lease.surfaceRevision.rawValue
            && descriptor.coordinateSpaceRevision.rawValue
                == lease.coordinateRevision.rawValue
            && descriptor.interactionClasses
                == lease.allowedInteractionClasses
    }
}
