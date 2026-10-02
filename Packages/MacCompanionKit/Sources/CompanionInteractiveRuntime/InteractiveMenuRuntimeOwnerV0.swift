import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
import CryptoKit
import Foundation

public struct InteractiveRuntimeIndicatorSnapshotV0: Equatable, Sendable {
    public let menuAppGeneration: UUID
    public let menuAppRevision: UInt64

    public init(menuAppGeneration: UUID, menuAppRevision: UInt64) throws {
        guard menuAppRevision > 0,
              menuAppRevision
                <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw InteractiveMenuRuntimeErrorV0.invalidIndicatorSnapshot
        }
        self.menuAppGeneration = menuAppGeneration
        self.menuAppRevision = menuAppRevision
    }
}

public protocol InteractiveRuntimeIndicatorControllingV0: Sendable {
    func showInteractiveIndicator(
        deviceDisplayName: DeviceDisplayName,
        interactiveSessionID: UUID
    ) async throws -> InteractiveRuntimeIndicatorSnapshotV0
    func clearInteractiveIndicator() async throws
}

public protocol InteractiveRuntimeCaptureControllingV0: Sendable {
    func startInteractiveCapture(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> Set<SurfaceInteractionClass>
    /// Advances only the execution-lease fence used by already-running media
    /// publication. It must not restart capture, change source, or emit a
    /// discontinuity.
    func adoptInteractiveLeaseRenewal(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws
    /// Suppresses old-source output and prepares the exact replacement source.
    /// It must not resume capture output or publish media before returning.
    func prepareInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass>
    /// Activates only the exact source prepared by the preceding transition.
    /// The runtime invokes this after replacing its authoritative lease and
    /// surface fence, so the first replacement record can never race the old
    /// admission state. Implementations must reject a missing or mismatched
    /// preparation and must not retain more than one prepared source.
    /// Seed the replacement publisher from this authoritative sequence. Do not
    /// await publication here: media is serialized behind this transition.
    func activatePreparedInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64
    ) async throws
    func stopInteractiveCapture() async throws
}

public protocol InteractiveRuntimeInputControllingV0: Sendable {
    func releaseAllInteractiveInput() async throws
}

public protocol InteractiveRuntimeFrameControllingV0: Sendable {
    func blankLastInteractiveFrame() async throws
}

/// Platform posting may suspend for selected-window activation. Native posting
/// requires its separate final batch authorization after that suspension.
public protocol InteractiveRuntimeInputPostingV0: Sendable {
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope) async throws
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        beforeDeadlineNanoseconds: UInt64) async throws
}

public extension InteractiveRuntimeInputPostingV0 {
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        beforeDeadlineNanoseconds: UInt64) async throws {
        throw InteractiveRuntimeNativeInputPostingErrorV0.unavailable
    }
}

/// A session-bound bounded queue. `true` means the complete record is owned by
/// the queue; `false` means no byte was accepted. The queue is purged by the
/// retained-frame cleanup effect before teardown can succeed.
public protocol InteractiveRuntimeMediaEnqueuingV0: Sendable {
    func enqueueInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) -> Bool

    /// Waits for bounded downstream capacity without accepting a partial
    /// record. Implementations that do not support suspension retain the
    /// immediate all-or-nothing behavior through the default implementation.
    func enqueueInteractiveMediaAwaitingCapacity(
        header: MediaRecordHeader,
        payload: Data
    ) async -> Bool
}

public extension InteractiveRuntimeMediaEnqueuingV0 {
    func enqueueInteractiveMediaAwaitingCapacity(
        header: MediaRecordHeader,
        payload: Data
    ) async -> Bool {
        enqueueInteractiveMedia(header: header, payload: payload)
    }
}

public struct InteractiveRuntimeInputActionV0: Equatable, Sendable {
    public let commandID: UUID
    public let fence: InteractiveCommandFence
    public let envelope: InteractiveInputEnvelope

    public init(
        commandID: UUID,
        fence: InteractiveCommandFence,
        envelope: InteractiveInputEnvelope
    ) throws {
        guard envelope.interactiveSessionID.rawValue
                == fence.interactiveSessionID,
              envelope.authorizationEpoch == fence.authorizationEpoch,
              envelope.surfaceID.rawValue == fence.surfaceID,
              envelope.surfaceRevision.rawValue
                == fence.surfaceRevision.rawValue,
              envelope.coordinateSpaceRevision.rawValue
                == fence.coordinateRevision.rawValue else {
            throw InteractiveMenuRuntimeErrorV0.bindingMismatch
        }
        self.commandID = commandID
        self.fence = fence
        self.envelope = envelope
    }

    public var requiredInteractionClass: SurfaceInteractionClass? {
        switch envelope.input.kind {
        case .pointerMove, .button, .scroll:
            return .pointer
        case .physicalKey, .modifiers:
            return .keyboard
        case .text:
            return .text
        case .reset:
            return nil
        }
    }
}

public struct InteractiveRuntimeMediaActionV0: Equatable, Sendable {
    public let commandID: UUID
    public let fence: InteractiveCommandFence
    public let header: MediaRecordHeader
    public let payload: Data

    public init(
        commandID: UUID,
        fence: InteractiveCommandFence,
        header: MediaRecordHeader,
        payload: Data
    ) throws {
        try header.validate()
        guard payload.count == Int(header.payloadLength),
              header.interactiveSessionID == fence.interactiveSessionID,
              header.authorizationEpoch == fence.authorizationEpoch,
              header.surfaceID == fence.surfaceID,
              header.surfaceRevision.rawValue
                == fence.surfaceRevision.rawValue,
              header.coordinateSpaceRevision.rawValue
                == fence.coordinateRevision.rawValue else {
            throw InteractiveMenuRuntimeErrorV0.bindingMismatch
        }
        switch header.type {
        case .decoderConfiguration:
            try AVCCPayloadValidatorV0.validateDecoderConfiguration(payload)
        case .videoAccessUnit:
            try AVCCPayloadValidatorV0.validateAccessUnit(
                payload,
                cleanKeyframe: header.flags.contains(.cleanKeyframe)
            )
        case .discontinuity, .end:
            break
        }
        self.commandID = commandID
        self.fence = fence
        self.header = header
        self.payload = payload
    }
}

public enum InteractiveMenuRuntimeStateV0: Equatable, Sendable {
    case idle
    case installing(interactiveSessionID: UUID)
    case active(interactiveSessionID: UUID, leaseID: UUID)
    case terminating(interactiveSessionID: UUID, leaseID: UUID)
    case safetyRecoveryRequired(interactiveSessionID: UUID, leaseID: UUID)
}

public enum InteractiveMenuRuntimeErrorV0: Error, Equatable, Sendable {
    case invalidIndicatorSnapshot
    case alreadyActive
    case noActiveSession
    case bindingMismatch
    case invalidTime
    case installFailed
    case safetyRecoveryRequired
    case interactionClassDenied
    case platformActionFailed
    case inputSequenceMismatch(expected: UInt64, actual: UInt64)
    case mediaSequenceMismatch(expected: UInt64, actual: UInt64)
    case mediaQueueRejected
    case surfaceTransitionInProgress
    case surfaceTransitionFailed
    case surfaceNotAcknowledged
    case invalidSurfaceMediaTransition
}

private struct InteractiveCleanupProgressV0: Sendable {
    var inputReleased = false
    var captureStopped = false
    var lastFrameBlanked = false
    var indicatorCleared = false

    var complete: Bool {
        inputReleased && captureStopped && lastFrameBlanked && indicatorCleared
    }
}

private struct InteractiveCleanupContextV0: Sendable {
    let leaseID: UUID
    let interactiveSessionID: UUID
    var progress = InteractiveCleanupProgressV0()
    var revokeCommand: InteractiveRuntimeRevokeCommandV0?
}

public enum InteractiveRuntimeSurfaceAdmissionStateV0:
    Equatable,
    Sendable
{
    case ready
    case focusPaused
    case preparing(transitionCommandID: UUID)
    case requiresDiscontinuity(transitionCommandID: UUID)
    case requiresConfiguration(transitionCommandID: UUID)
    case requiresCleanKeyframe(transitionCommandID: UUID)
    case awaitingAcknowledgement(
        transitionCommandID: UUID,
        readyMediaSequence: UInt64
    )
}

private struct ActiveInteractiveRuntimeV0: Sendable {
    var command: InteractiveRuntimeInstallCommandV0
    var receipt: InteractiveRuntimeInstallReceiptV0
    let sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    var surfaceAdmission: InteractiveRuntimeSurfaceAdmissionStateV0
    var lastSurfaceTransitionCommand:
        InteractiveRuntimeSurfaceTransitionCommandV0?
    var lastSurfaceTransitionReceipt:
        InteractiveRuntimeSurfaceTransitionReceiptV0?
    var lastSurfaceAcknowledgementCommand:
        InteractiveRuntimeSurfaceAcknowledgementCommandV0?
    var lastSurfaceAcknowledgementReceipt:
        InteractiveRuntimeSurfaceAcknowledgementReceiptV0?
    var inputReleasedForSurfaceTransition: Bool
    var lastInputAction: InteractiveRuntimeInputActionV0?
    var lastMediaSequence: UInt64
    var lastMediaCommandID: UUID?
    var lastMediaDigest: Data?
    var retiredResetCommand: InteractiveRuntimeInstallCommandV0? = nil
    var nativeInputPause: InteractiveNativeVideoRequestFenceV0? = nil
    var nativeInputAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0? = nil
}

/// The bundle-independent, single-owner execution seam for the visible menu
/// app. Public mutations are placed on one private queue before any platform
/// effect begins, preventing actor reentrancy from overlapping installs,
/// renewals, and teardown.
public actor InteractiveMenuRuntimeOwnerV0 {
    private enum Storage: Sendable {
        case idle
        case installing(InteractiveRuntimeInstallCommandV0)
        case active(ActiveInteractiveRuntimeV0)
        case terminating(InteractiveCleanupContextV0)
        case safetyRecoveryRequired(InteractiveCleanupContextV0)
    }

    private let indicator: any InteractiveRuntimeIndicatorControllingV0
    private let capture: any InteractiveRuntimeCaptureControllingV0
    private let input: any InteractiveRuntimeInputControllingV0
    private let frame: any InteractiveRuntimeFrameControllingV0
    private let inputPoster: any InteractiveRuntimeInputPostingV0
    private let mediaQueue: any InteractiveRuntimeMediaEnqueuingV0
    private var storage: Storage = .idle
    private var lastRevokedReceipt: InteractiveRuntimeRevokedReceiptV0?
    private var sequencingTail = Task<Void, Never> {}

    public init(
        indicator: any InteractiveRuntimeIndicatorControllingV0,
        capture: any InteractiveRuntimeCaptureControllingV0,
        input: any InteractiveRuntimeInputControllingV0,
        frame: any InteractiveRuntimeFrameControllingV0,
        inputPoster: any InteractiveRuntimeInputPostingV0,
        mediaQueue: any InteractiveRuntimeMediaEnqueuingV0
    ) {
        self.indicator = indicator
        self.capture = capture
        self.input = input
        self.frame = frame
        self.inputPoster = inputPoster
        self.mediaQueue = mediaQueue
    }

    public func state() -> InteractiveMenuRuntimeStateV0 {
        switch storage {
        case .idle:
            return .idle
        case let .installing(command):
            return .installing(
                interactiveSessionID: command.lease.interactiveSessionID
            )
        case let .active(active):
            return .active(
                interactiveSessionID:
                    active.command.lease.interactiveSessionID,
                leaseID: active.command.lease.leaseID
            )
        case let .terminating(context):
            return .terminating(
                interactiveSessionID: context.interactiveSessionID,
                leaseID: context.leaseID
            )
        case let .safetyRecoveryRequired(context):
            return .safetyRecoveryRequired(
                interactiveSessionID: context.interactiveSessionID,
                leaseID: context.leaseID
            )
        }
    }

    public func nextLeaseDeadlineMonotonicNanoseconds() -> UInt64? {
        guard case let .active(active) = storage else { return nil }
        return active.command.lease.expiresAtMonotonicNanoseconds
    }

    /// Menu-local snapshot only. Callers must recheck after every suspension;
    /// this value never crosses XPC or grants capture authority on its own.
    public func currentWebRTCInstallCommand() -> InteractiveRuntimeInstallCommandV0? {
        guard case let .active(active) = storage else { return nil }
        return active.command
    }

    /// One actor read joins the acknowledged surface, active lease and visible
    /// receipt. The original session deadline survives renewable short leases.
    public func currentNativeVideoSnapshot(fence: InteractiveNativeVideoRequestFenceV0, nowMonotonicNanoseconds: UInt64) throws -> LocalInteractiveNativeRuntimeSnapshotV1? {
        guard case let .active(active) = storage, active.surfaceAdmission == .ready else { return nil }
        let snapshot = try LocalInteractiveNativeRuntimeSnapshotV1(command: active.command, receipt: active.receipt, fence: fence)
        guard snapshot.isCurrent(nowMonotonicNanoseconds: nowMonotonicNanoseconds) else { return nil }
        return snapshot
    }

    public func surfaceAdmissionState()
        -> InteractiveRuntimeSurfaceAdmissionStateV0?
    {
        guard case let .active(active) = storage else { return nil }
        return active.surfaceAdmission
    }

    /// The native engine cannot inherit input authority from the legacy
    /// bootstrap. This latch is independent of media ownership/readiness.
    public func pauseInputForNativePresentation(
        fence: InteractiveNativeVideoRequestFenceV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard try currentNativeVideoSnapshot(fence: fence,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds) != nil,
                  case var .active(active) = storage else {
                throw InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged
            }
            if active.nativeInputPause == fence, active.nativeInputAuthorization == nil { return }
            active.nativeInputAuthorization?.revoke()
            active.nativeInputAuthorization = nil
            active.nativeInputPause = fence
            storage = .active(active)
            do {
                try await input.releaseAllInteractiveInput()
            } catch {
                _ = try await performUnacknowledgedTermination(force: true)
                throw InteractiveMenuRuntimeErrorV0.platformActionFailed
            }
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// Internal handoff from the trusted native backend owner after correlated
    /// presentation admission. The pause marker is retained, so native input
    /// can never silently inherit the legacy posting path.
    public func installNativeInputAuthorization(
        _ authorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        fence: InteractiveNativeVideoRequestFenceV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !Task.isCancelled,
                  let snapshot = try currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: nowMonotonicNanoseconds),
                  case var .active(active) = storage,
                  active.nativeInputPause == fence,
                  active.nativeInputAuthorization == nil,
                  !authorization.isRevoked else {
                throw InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged
            }
            let binding = authorization.binding, surface = authorization.surface
            guard binding.hostID == snapshot.hostID,
                  binding.interactiveSessionID == snapshot.fence.interactiveSessionID.rawValue,
                  UInt64(binding.authorizationEpoch) == snapshot.fence.authorizationEpoch.rawValue,
                  binding.controlGeneration == snapshot.controlGeneration,
                  binding.expiresAtMonotonicMilliseconds == snapshot.sessionDeadlineMonotonicNanoseconds / 1_000_000,
                  surface.surfaceID == snapshot.fence.surfaceID.rawValue,
                  surface.surfaceRevision == snapshot.fence.surfaceRevision,
                  surface.coordinateSpaceRevision == snapshot.fence.coordinateSpaceRevision,
                  surface.encodedWidth == snapshot.encodedWidth,
                  surface.encodedHeight == snapshot.encodedHeight else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            active.nativeInputAuthorization = authorization
            storage = .active(active)
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await withTaskCancellationHandler(operation: { try await operation.value }, onCancel: { operation.cancel(); authorization.revoke() })
    }

    public func install(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performInstall(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func renew(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performRenewal(
                renewal,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performSurfaceTransition(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// Releases all currently posted input and keeps new input closed while a
    /// focus-driven replacement is offered to the client.
    public func pauseInputForFocusChange(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> Bool {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performPauseInputForFocusChange(command)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func acknowledgeSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try performSurfaceAcknowledgement(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func revoke(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performRevoke(command)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func postInput(
        _ action: InteractiveRuntimeInputActionV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInput(
                action,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// Accepts only the wire envelope; the full command fence is derived from
    /// the currently active lease inside this actor turn so no transport or
    /// adapter can manufacture stale host, display, or lease authority.
    public func postInputEnvelope(
        _ envelope: InteractiveInputEnvelope,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInputEnvelope(
                envelope,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func publishMedia(
        _ action: InteractiveRuntimeMediaActionV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performMedia(
                action,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// Called by the menu app when the authenticated Agent IPC connection is
    /// invalidated. This never waits for a remote or Agent-issued receipt.
    public func invalidateAgentAuthority() async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            _ = try await performUnacknowledgedTermination(force: true)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// Exact Agent-requested convergence after an ambiguous surface-control
    /// result. A matching active session is torn down with the same ordered
    /// safety effects as connection loss; an already-idle owner is an
    /// authoritative success, while another active session is never touched.
    public func terminateSurfaceFailure(
        interactiveSessionID: UUID
    ) async throws -> Bool {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            switch storage {
            case .idle:
                return true
            case let .active(active):
                guard active.command.lease.interactiveSessionID
                        == interactiveSessionID else { return false }
                _ = try await performUnacknowledgedTermination(force: true)
                if case .idle = storage { return true }
                return false
            case let .terminating(context),
                    let .safetyRecoveryRequired(context):
                guard context.interactiveSessionID
                        == interactiveSessionID else { return false }
                _ = try await performUnacknowledgedTermination(force: true)
                if case .idle = storage { return true }
                return false
            case .installing:
                return false
            }
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    /// The platform composition root schedules this at the exact deadline
    /// returned by `nextLeaseDeadlineMonotonicNanoseconds()`.
    @discardableResult
    public func expireLeaseIfRequired(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> Bool {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performUnacknowledgedTermination(
                force: false,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    private func performInstall(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try command.validate()
        guard command.surfaceDescriptor.kind == .desktop else {
            throw InteractiveMenuRuntimeErrorV0.bindingMismatch
        }
        let monotonicMilliseconds = nowMonotonicNanoseconds / 1_000_000
        guard nowMonotonicNanoseconds >= command.lease.issuedAtMonotonicNanoseconds,
              nowMonotonicNanoseconds < command.lease.expiresAtMonotonicNanoseconds,
              nowMonotonicNanoseconds
                < command.sessionDeadlineMonotonicNanoseconds,
              monotonicMilliseconds <= UInt64(Int64.max),
              Int64(monotonicMilliseconds)
                >= command.surfaceDescriptor.createdAtMonotonicMilliseconds,
              Int64(monotonicMilliseconds)
                < command.surfaceDescriptor.expiresAtMonotonicMilliseconds else {
            throw InteractiveMenuRuntimeErrorV0.invalidTime
        }

        switch storage {
        case let .active(active) where active.command == command:
            return active.receipt
        case .idle:
            break
        case .safetyRecoveryRequired:
            throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
        default:
            throw InteractiveMenuRuntimeErrorV0.alreadyActive
        }

        storage = .installing(command)
        do {
            // The visible indicator precedes capture so Control is never
            // usable before its local identity is visible.
            let indicatorSnapshot = try await indicator.showInteractiveIndicator(
                deviceDisplayName: command.deviceDisplayName,
                interactiveSessionID: command.lease.interactiveSessionID
            )
            let readyClasses = try await capture.startInteractiveCapture(
                command
            )
            let receipt = try InteractiveRuntimeInstallReceiptV0(
                correlationID: command.commandID,
                leaseID: command.lease.leaseID,
                interactiveSessionID: command.lease.interactiveSessionID,
                selectedDisplayID: command.lease.selectedDisplayID,
                menuAppGeneration: indicatorSnapshot.menuAppGeneration,
                menuAppRevision: indicatorSnapshot.menuAppRevision,
                readyInteractionClasses: readyClasses,
                indicatorVisible: true
            )
            try receipt.validate(against: command)
            storage = .active(.init(
                command: command,
                receipt: receipt,
                sessionAllowedInteractionClasses:
                    Set(command.lease.allowedInteractionClasses),
                // Installation proves only that the visible indicator and
                // capture source are ready. Initial input remains denied until
                // configuration, a clean keyframe, and the exact install-ID
                // acknowledgement have all crossed this owner.
                surfaceAdmission: .requiresConfiguration(
                    transitionCommandID: command.commandID
                ),
                lastSurfaceTransitionCommand: nil,
                lastSurfaceTransitionReceipt: nil,
                lastSurfaceAcknowledgementCommand: nil,
                lastSurfaceAcknowledgementReceipt: nil,
                inputReleasedForSurfaceTransition: false,
                lastInputAction: nil,
                lastMediaSequence: 0,
                lastMediaCommandID: nil,
                lastMediaDigest: nil
            ))
            lastRevokedReceipt = nil
            return receipt
        } catch {
            var context = InteractiveCleanupContextV0(
                leaseID: command.lease.leaseID,
                interactiveSessionID: command.lease.interactiveSessionID
            )
            storage = .terminating(context)
            await applyCleanup(&context)
            if context.progress.complete {
                storage = .idle
                throw InteractiveMenuRuntimeErrorV0.installFailed
            }
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
        }
    }

    private func performRenewal(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        guard case let .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        let command = active.command
        let receipt = active.receipt
        try renewal.validate(current: command.lease)
        guard nowMonotonicNanoseconds
                >= renewal.replacement.issuedAtMonotonicNanoseconds,
              nowMonotonicNanoseconds
                < renewal.replacement.expiresAtMonotonicNanoseconds,
              renewal.replacement.expiresAtMonotonicNanoseconds
                <= command.sessionDeadlineMonotonicNanoseconds else {
            throw InteractiveMenuRuntimeErrorV0.invalidTime
        }
        let replacement = try InteractiveRuntimeInstallCommandV0(
            protocolVersion: command.protocolVersion,
            commandID: command.commandID,
            lease: renewal.replacement,
            deviceDisplayName: command.deviceDisplayName,
            surfaceDescriptor: command.surfaceDescriptor,
            sessionDeadlineMonotonicNanoseconds:
                command.sessionDeadlineMonotonicNanoseconds
        )
        let replacementReceipt = try InteractiveRuntimeInstallReceiptV0(
            protocolVersion: receipt.protocolVersion,
            correlationID: receipt.correlationID,
            leaseID: replacement.lease.leaseID,
            interactiveSessionID: receipt.interactiveSessionID,
            selectedDisplayID: receipt.selectedDisplayID,
            menuAppGeneration: receipt.menuAppGeneration,
            menuAppRevision: receipt.menuAppRevision,
            readyInteractionClasses: Set(receipt.readyInteractionClasses),
            indicatorVisible: receipt.indicatorVisible
        )
        try replacementReceipt.validate(against: replacement)
        // Capture callbacks construct their local media action from a retained
        // lease fence. Advance that fence before publishing the renewal reply;
        // otherwise the first post-renewal frame is rejected as stale and can
        // terminate the encoder despite a valid same-surface renewal.
        try await capture.adoptInteractiveLeaseRenewal(renewal)
        storage = .active(.init(
            command: replacement,
            receipt: replacementReceipt,
            sessionAllowedInteractionClasses:
                active.sessionAllowedInteractionClasses,
            surfaceAdmission: active.surfaceAdmission,
            lastSurfaceTransitionCommand:
                active.lastSurfaceTransitionCommand,
            lastSurfaceTransitionReceipt:
                active.lastSurfaceTransitionReceipt,
            lastSurfaceAcknowledgementCommand:
                active.lastSurfaceAcknowledgementCommand,
            lastSurfaceAcknowledgementReceipt:
                active.lastSurfaceAcknowledgementReceipt,
            inputReleasedForSurfaceTransition:
                active.inputReleasedForSurfaceTransition,
            lastInputAction: active.lastInputAction,
            lastMediaSequence: active.lastMediaSequence,
            lastMediaCommandID: active.lastMediaCommandID,
            lastMediaDigest: active.lastMediaDigest,
            retiredResetCommand: active.retiredResetCommand,
            nativeInputPause: active.nativeInputPause,
            nativeInputAuthorization: active.nativeInputAuthorization
        ))
    }

    private func performSurfaceTransition(
        _ transition: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        if active.lastSurfaceTransitionCommand == transition,
           let receipt = active.lastSurfaceTransitionReceipt {
            try receipt.validate(against: transition)
            return receipt
        }
        let inputWasAlreadyReleased =
            active.surfaceAdmission == .focusPaused
        guard active.surfaceAdmission == .ready
                || inputWasAlreadyReleased else {
            throw InteractiveMenuRuntimeErrorV0
                .surfaceTransitionInProgress
        }
        try transition.validate(
            current: active.command.lease,
            sessionAllowedInteractionClasses:
                active.sessionAllowedInteractionClasses
        )
        let replacement = transition.replacement
        let monotonicMilliseconds = nowMonotonicNanoseconds
            / 1_000_000
        guard monotonicMilliseconds <= UInt64(Int64.max),
              nowMonotonicNanoseconds
                >= replacement.issuedAtMonotonicNanoseconds,
              nowMonotonicNanoseconds
                < replacement.expiresAtMonotonicNanoseconds,
              replacement.expiresAtMonotonicNanoseconds
                <= active.command
                    .sessionDeadlineMonotonicNanoseconds,
              Int64(monotonicMilliseconds)
                >= transition.descriptor
                    .createdAtMonotonicMilliseconds,
              Int64(monotonicMilliseconds)
                < transition.descriptor
                    .expiresAtMonotonicMilliseconds else {
            throw InteractiveMenuRuntimeErrorV0.invalidTime
        }

        let priorLeaseID = active.command.lease.leaseID
        active.nativeInputAuthorization?.revoke()
        active.nativeInputAuthorization = nil
        active.surfaceAdmission = .preparing(
            transitionCommandID: transition.commandID
        )
        storage = .active(active)
        var inputReleased = inputWasAlreadyReleased
        do {
            if !inputReleased {
                try await input.releaseAllInteractiveInput()
                inputReleased = true
            }
            let readyClasses = try await capture
                .prepareInteractiveCaptureTransition(transition)
            guard readyClasses.isSuperset(
                of: Set(replacement.allowedInteractionClasses)
            ) else {
                throw InteractiveMenuRuntimeErrorV0
                    .surfaceTransitionFailed
            }
            let replacementCommand = try InteractiveRuntimeInstallCommandV0(
                protocolVersion: active.command.protocolVersion,
                commandID: active.command.commandID,
                lease: replacement,
                deviceDisplayName: active.command.deviceDisplayName,
                surfaceDescriptor: transition.descriptor,
                sessionDeadlineMonotonicNanoseconds:
                    active.command.sessionDeadlineMonotonicNanoseconds
            )
            let replacementReceipt = try InteractiveRuntimeInstallReceiptV0(
                protocolVersion: active.receipt.protocolVersion,
                correlationID: active.receipt.correlationID,
                leaseID: replacement.leaseID,
                interactiveSessionID: replacement.interactiveSessionID,
                selectedDisplayID: replacement.selectedDisplayID,
                menuAppGeneration: active.receipt.menuAppGeneration,
                menuAppRevision: active.receipt.menuAppRevision,
                readyInteractionClasses: readyClasses,
                indicatorVisible: active.receipt.indicatorVisible
            )
            try replacementReceipt.validate(against: replacementCommand)
            let transitionReceipt = try
                InteractiveRuntimeSurfaceTransitionReceiptV0(
                    correlationID: transition.commandID,
                    previousLeaseID: transition.previousLeaseID,
                    replacementLeaseID: replacement.leaseID,
                    interactiveSessionID:
                        replacement.interactiveSessionID,
                    surfaceID: replacement.surfaceID,
                    surfaceRevision: replacement.surfaceRevision,
                    coordinateRevision: replacement.coordinateRevision,
                    mediaSequenceBeforeTransition:
                        active.lastMediaSequence,
                    inputReleased: true,
                    captureSourcePrepared: true
                )
            try transitionReceipt.validate(against: transition)
            active.retiredResetCommand = active.command
            active.command = replacementCommand
            active.receipt = replacementReceipt
            active.surfaceAdmission = .requiresDiscontinuity(
                transitionCommandID: transition.commandID
            )
            active.lastSurfaceTransitionCommand = transition
            active.lastSurfaceTransitionReceipt = transitionReceipt
            active.lastSurfaceAcknowledgementCommand = nil
            active.lastSurfaceAcknowledgementReceipt = nil
            active.inputReleasedForSurfaceTransition = true
            storage = .active(active)
            try await capture
                .activatePreparedInteractiveCaptureTransition(
                    transition,
                    mediaSequenceBeforeTransition:
                        transitionReceipt.mediaSequenceBeforeTransition
                )
            return transitionReceipt
        } catch {
            var context = InteractiveCleanupContextV0(
                leaseID: priorLeaseID,
                interactiveSessionID:
                    active.command.lease.interactiveSessionID
            )
            context.progress.inputReleased = inputReleased
            storage = .terminating(context)
            await applyCleanup(&context)
            if context.progress.complete {
                storage = .idle
                throw InteractiveMenuRuntimeErrorV0
                    .surfaceTransitionFailed
            }
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0
                .safetyRecoveryRequired
        }
    }

    private func performSurfaceAcknowledgement(
        _ acknowledgement:
            InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        if active.lastSurfaceAcknowledgementCommand == acknowledgement,
           let receipt = active.lastSurfaceAcknowledgementReceipt {
            try receipt.validate(against: acknowledgement)
            return receipt
        }
        guard case let .awaitingAcknowledgement(
            transitionCommandID,
            readyMediaSequence
        ) = active.surfaceAdmission else {
            throw InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged
        }
        try acknowledgement.validate(
            current: active.command.lease,
            expectedTransitionCommandID: transitionCommandID,
            expectedReadyMediaSequence: readyMediaSequence,
            expectedFocusToken:
                active.lastSurfaceTransitionCommand?.descriptor.focus?.token,
            expectedFocusRevision:
                active.lastSurfaceTransitionCommand?.descriptor.focus?.revision
        )
        guard nowMonotonicNanoseconds
                >= active.command.lease.issuedAtMonotonicNanoseconds,
              nowMonotonicNanoseconds
                < active.command.lease.expiresAtMonotonicNanoseconds else {
            throw InteractiveMenuRuntimeErrorV0.invalidTime
        }
        let receipt = try
            InteractiveRuntimeSurfaceAcknowledgementReceiptV0(
                correlationID: acknowledgement.commandID,
                transitionCommandID:
                    acknowledgement.transitionCommandID,
                leaseID: acknowledgement.leaseID,
                interactiveSessionID:
                    acknowledgement.interactiveSessionID,
                surfaceID: acknowledgement.surfaceID,
                surfaceRevision: acknowledgement.surfaceRevision,
                coordinateRevision: acknowledgement.coordinateRevision,
                focusToken: acknowledgement.focusToken,
                focusRevision: acknowledgement.focusRevision,
                readyMediaSequence: acknowledgement.readyMediaSequence,
                inputResumed: true
            )
        try receipt.validate(against: acknowledgement)
        active.surfaceAdmission = .ready
        active.inputReleasedForSurfaceTransition = false
        active.lastSurfaceAcknowledgementCommand = acknowledgement
        active.lastSurfaceAcknowledgementReceipt = receipt
        storage = .active(active)
        return receipt
    }

    private func performRevoke(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        if let receipt = lastRevokedReceipt,
           receipt.correlationID == command.commandID {
            try receipt.validate(against: command)
            return receipt
        }

        var context: InteractiveCleanupContextV0
        switch storage {
        case let .active(active):
            let activeCommand = active.command
            guard activeCommand.lease.leaseID == command.leaseID,
                  activeCommand.lease.interactiveSessionID
                    == command.interactiveSessionID else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            active.nativeInputAuthorization?.revoke()
            context = InteractiveCleanupContextV0(
                leaseID: command.leaseID,
                interactiveSessionID: command.interactiveSessionID,
                revokeCommand: command
            )
            context.progress.inputReleased
                = active.inputReleasedForSurfaceTransition
        case let .safetyRecoveryRequired(existing):
            guard existing.leaseID == command.leaseID,
                  existing.interactiveSessionID == command.interactiveSessionID,
                  existing.revokeCommand == nil
                    || existing.revokeCommand == command else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            context = existing
            context.revokeCommand = command
        case .idle:
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        default:
            throw InteractiveMenuRuntimeErrorV0.alreadyActive
        }

        storage = .terminating(context)
        await applyCleanup(&context)
        guard context.progress.complete else {
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
        }
        let receipt = try InteractiveRuntimeRevokedReceiptV0(
            correlationID: command.commandID,
            leaseID: command.leaseID,
            interactiveSessionID: command.interactiveSessionID,
            inputReleased: true,
            captureStopped: true,
            lastFrameBlanked: true,
            indicatorCleared: true
        )
        try receipt.validate(against: command)
        storage = .idle
        lastRevokedReceipt = receipt
        return receipt
    }

    private func performInput(
        _ action: InteractiveRuntimeInputActionV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        let command = active.command
        let drainingPausedNativeReset = action.envelope.input == .reset
            && active.surfaceAdmission == .ready
            && active.nativeInputPause != nil
            && active.nativeInputAuthorization?.isRevoked != false
        let replayingNativeReset = action.envelope.input == .reset
            && active.nativeInputPause != nil
            && active.lastInputAction == action
        guard drainingPausedNativeReset
                || replayingNativeReset
                || active.nativeInputPause == nil
                || active.nativeInputAuthorization?.isRevoked == false else {
            throw InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged
        }
        let drainingFocusPause = active.surfaceAdmission == .focusPaused
            && active.inputReleasedForSurfaceTransition
        guard active.surfaceAdmission == .ready || drainingFocusPause else {
            throw InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged
        }
        try command.lease.validate(
            fence: action.fence,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
        if let previous = active.lastInputAction {
            if previous == action { return }
            if previous.commandID == action.commandID {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
        }
        let expected = (active.lastInputAction?.envelope.sequence ?? 0) + 1
        guard action.envelope.sequence == expected else {
            throw InteractiveMenuRuntimeErrorV0.inputSequenceMismatch(
                expected: expected,
                actual: action.envelope.sequence
            )
        }
        if let required = action.requiredInteractionClass,
           !command.lease.admits(required) {
            throw InteractiveMenuRuntimeErrorV0.interactionClassDenied
        }
        if drainingFocusPause {
            guard action.envelope.focusToken?.rawValue == command.surfaceDescriptor.focus?.token,
                  action.envelope.focusRevision == command.surfaceDescriptor.focus?.revision else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            // The phone cannot observe a host focus pause synchronously across
            // sockets. Consume reliability state only; no old-target input is
            // posted or buffered for replay, and the surface remains paused.
            active.lastInputAction = action
            storage = .active(active)
            return
        }
        if drainingPausedNativeReset {
            guard action.envelope.focusToken?.rawValue
                    == command.surfaceDescriptor.focus?.token,
                  action.envelope.focusRevision
                    == command.surfaceDescriptor.focus?.revision else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            active.nativeInputAuthorization = nil
            active.lastInputAction = action
            active.retiredResetCommand = nil
            storage = .active(active)
            do {
                try await input.releaseAllInteractiveInput()
            } catch {
                _ = try await performUnacknowledgedTermination(force: true)
                throw InteractiveMenuRuntimeErrorV0.platformActionFailed
            }
            return
        }
        do {
            if let native = active.nativeInputAuthorization, active.nativeInputPause != nil {
                try await inputPoster.postInteractiveInput(action.envelope, nativeAuthorization: native,
                    beforeDeadlineNanoseconds: command.lease.expiresAtMonotonicNanoseconds)
            } else {
                try await inputPoster.postInteractiveInput(action.envelope)
            }
        } catch {
            throw InteractiveMenuRuntimeErrorV0.platformActionFailed
        }
        active.lastInputAction = action
        active.retiredResetCommand = nil
        storage = .active(active)
    }

    private func performPauseInputForFocusChange(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> Bool {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        let descriptor = active.command.surfaceDescriptor
        guard descriptor.kind == .focusedRegion,
              command.interactiveSessionID
                == descriptor.interactiveSessionID,
              command.authorizationEpoch == descriptor.authorizationEpoch,
              command.currentSurfaceID == descriptor.surfaceID,
              command.expectedSurfaceRevision == descriptor.surfaceRevision,
              command.expectedCoordinateSpaceRevision
                == descriptor.coordinateSpaceRevision else {
            throw InteractiveMenuRuntimeErrorV0.bindingMismatch
        }
        if active.surfaceAdmission == .focusPaused { return true }
        guard active.surfaceAdmission == .ready else {
            throw InteractiveMenuRuntimeErrorV0
                .surfaceTransitionInProgress
        }
        active.nativeInputAuthorization?.revoke()
        active.nativeInputAuthorization = nil
        active.surfaceAdmission = .focusPaused
        storage = .active(active)
        try await input.releaseAllInteractiveInput()
        active.inputReleasedForSurfaceTransition = true
        storage = .active(active)
        return true
    }

    private func performInputEnvelope(
        _ envelope: InteractiveInputEnvelope,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        let lease = active.command.lease
        if envelope.input == .reset,
           let retired = active.retiredResetCommand,
           envelope.interactiveSessionID.rawValue == retired.lease.interactiveSessionID,
           envelope.authorizationEpoch == retired.lease.authorizationEpoch,
           envelope.surfaceID.rawValue == retired.lease.surfaceID,
           envelope.surfaceRevision.rawValue == retired.lease.surfaceRevision.rawValue,
           envelope.coordinateSpaceRevision.rawValue == retired.lease.coordinateRevision.rawValue,
           envelope.focusToken?.rawValue == retired.surfaceDescriptor.focus?.token,
           envelope.focusRevision == retired.surfaceDescriptor.focus?.revision {
            // Preparation already released all old input. Drain reliability
            // bookkeeping only; never post or release replacement input here.
            guard nowMonotonicNanoseconds >= retired.lease.issuedAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds < lease.expiresAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds < active.command.sessionDeadlineMonotonicNanoseconds else {
                throw InteractiveMenuRuntimeErrorV0.invalidTime
            }
            let expected = (active.lastInputAction?.envelope.sequence ?? 0) + 1
            guard active.lastInputAction?.commandID != envelope.messageID.rawValue else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            guard envelope.sequence == expected else {
                throw InteractiveMenuRuntimeErrorV0.inputSequenceMismatch(expected: expected, actual: envelope.sequence)
            }
            let old = retired.lease
            active.lastInputAction = try InteractiveRuntimeInputActionV0(
                commandID: envelope.messageID.rawValue,
                fence: .init(leaseID: old.leaseID, hostID: old.hostID, deviceID: old.deviceID,
                    interactiveSessionID: old.interactiveSessionID, authorizationEpoch: old.authorizationEpoch,
                    selectedDisplayID: old.selectedDisplayID, surfaceID: old.surfaceID,
                    surfaceRevision: old.surfaceRevision, coordinateRevision: old.coordinateRevision),
                envelope: envelope)
            active.retiredResetCommand = nil
            storage = .active(active)
            return
        }
        let action = try InteractiveRuntimeInputActionV0(
            commandID: envelope.messageID.rawValue,
            fence: .init(
                leaseID: lease.leaseID,
                hostID: lease.hostID,
                deviceID: lease.deviceID,
                interactiveSessionID: lease.interactiveSessionID,
                authorizationEpoch: lease.authorizationEpoch,
                selectedDisplayID: lease.selectedDisplayID,
                surfaceID: lease.surfaceID,
                surfaceRevision: lease.surfaceRevision,
                coordinateRevision: lease.coordinateRevision
            ),
            envelope: envelope
        )
        try await performInput(
            action,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
    }

    private func performMedia(
        _ action: InteractiveRuntimeMediaActionV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
            }
            throw InteractiveMenuRuntimeErrorV0.noActiveSession
        }
        try active.command.lease.validate(
            fence: action.fence,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
        guard active.command.lease.admits(.view) else {
            throw InteractiveMenuRuntimeErrorV0.interactionClassDenied
        }
        let expected = active.lastMediaSequence + 1
        var digestInput = action.header.encode()
        digestInput.append(action.payload)
        let digest = Data(SHA256.hash(data: digestInput))
        if active.lastMediaCommandID == action.commandID {
            guard active.lastMediaSequence == action.header.mediaSequence,
                  active.lastMediaDigest == digest else {
                throw InteractiveMenuRuntimeErrorV0.bindingMismatch
            }
            return
        }
        guard action.header.mediaSequence == expected else {
            throw InteractiveMenuRuntimeErrorV0.mediaSequenceMismatch(
                expected: expected,
                actual: action.header.mediaSequence
            )
        }
        let nextSurfaceAdmission:
            InteractiveRuntimeSurfaceAdmissionStateV0
        do {
            nextSurfaceAdmission = try surfaceAdmission(
                after: action,
                current: active.surfaceAdmission
            )
        } catch {
            active.nativeInputAuthorization?.revoke()
            var context = InteractiveCleanupContextV0(
                leaseID: active.command.lease.leaseID,
                interactiveSessionID:
                    active.command.lease.interactiveSessionID
            )
            context.progress.inputReleased
                = active.inputReleasedForSurfaceTransition
            storage = .terminating(context)
            await applyCleanup(&context)
            if context.progress.complete {
                storage = .idle
                throw InteractiveMenuRuntimeErrorV0
                    .invalidSurfaceMediaTransition
            }
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0
                .safetyRecoveryRequired
        }
        // Commit the exact sequence/fence before the bounded queue may
        // suspend. The queue owns the complete pending record while waiting,
        // and actor reentrancy must never allow a late continuation to
        // restore state retired by revoke, reset, or Agent invalidation.
        active.lastMediaSequence = action.header.mediaSequence
        active.lastMediaCommandID = action.commandID
        active.lastMediaDigest = digest
        active.surfaceAdmission = nextSurfaceAdmission
        storage = .active(active)
        guard await mediaQueue.enqueueInteractiveMediaAwaitingCapacity(
            header: action.header,
            payload: action.payload
        ) else {
            guard case let .active(current) = storage,
                  current.command.lease.interactiveSessionID
                    == active.command.lease.interactiveSessionID,
                  current.lastMediaCommandID == action.commandID,
                  current.lastMediaSequence == action.header.mediaSequence
            else {
                if case .safetyRecoveryRequired = storage {
                    throw InteractiveMenuRuntimeErrorV0
                        .safetyRecoveryRequired
                }
                throw InteractiveMenuRuntimeErrorV0.noActiveSession
            }
            current.nativeInputAuthorization?.revoke()
            var context = InteractiveCleanupContextV0(
                leaseID: current.command.lease.leaseID,
                interactiveSessionID:
                    current.command.lease.interactiveSessionID
            )
            context.progress.inputReleased
                = current.inputReleasedForSurfaceTransition
            storage = .terminating(context)
            await applyCleanup(&context)
            if context.progress.complete {
                storage = .idle
                throw InteractiveMenuRuntimeErrorV0.mediaQueueRejected
            }
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
        }
    }

    private func surfaceAdmission(
        after action: InteractiveRuntimeMediaActionV0,
        current: InteractiveRuntimeSurfaceAdmissionStateV0
    ) throws -> InteractiveRuntimeSurfaceAdmissionStateV0 {
        switch current {
        case .ready:
            return .ready
        case .focusPaused:
            return .focusPaused
        case .preparing:
            throw InteractiveMenuRuntimeErrorV0
                .invalidSurfaceMediaTransition
        case .requiresDiscontinuity(let transitionCommandID):
            guard action.header.type == .discontinuity else {
                throw InteractiveMenuRuntimeErrorV0
                    .invalidSurfaceMediaTransition
            }
            return .requiresConfiguration(
                transitionCommandID: transitionCommandID
            )
        case .requiresConfiguration(let transitionCommandID):
            guard action.header.type == .decoderConfiguration else {
                throw InteractiveMenuRuntimeErrorV0
                    .invalidSurfaceMediaTransition
            }
            return .requiresCleanKeyframe(
                transitionCommandID: transitionCommandID
            )
        case .requiresCleanKeyframe(let transitionCommandID):
            guard action.header.type == .videoAccessUnit,
                  action.header.flags.contains(.cleanKeyframe) else {
                throw InteractiveMenuRuntimeErrorV0
                    .invalidSurfaceMediaTransition
            }
            return .awaitingAcknowledgement(
                transitionCommandID: transitionCommandID,
                readyMediaSequence: action.header.mediaSequence
            )
        case .awaitingAcknowledgement:
            guard action.header.type == .videoAccessUnit else {
                throw InteractiveMenuRuntimeErrorV0
                    .invalidSurfaceMediaTransition
            }
            return current
        }
    }

    private func performUnacknowledgedTermination(
        force: Bool,
        nowMonotonicNanoseconds: UInt64? = nil
    ) async throws -> Bool {
        var context: InteractiveCleanupContextV0
        switch storage {
        case let .active(active):
            let command = active.command
            if !force {
                guard let nowMonotonicNanoseconds,
                      nowMonotonicNanoseconds
                        >= command.lease.expiresAtMonotonicNanoseconds else {
                    return false
                }
            }
            active.nativeInputAuthorization?.revoke()
            context = InteractiveCleanupContextV0(
                leaseID: command.lease.leaseID,
                interactiveSessionID: command.lease.interactiveSessionID
            )
            context.progress.inputReleased
                = active.inputReleasedForSurfaceTransition
        case let .safetyRecoveryRequired(existing):
            context = existing
        case .idle:
            return false
        default:
            throw InteractiveMenuRuntimeErrorV0.alreadyActive
        }

        storage = .terminating(context)
        await applyCleanup(&context)
        guard context.progress.complete else {
            storage = .safetyRecoveryRequired(context)
            throw InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
        }
        storage = .idle
        return true
    }

    private func applyCleanup(
        _ context: inout InteractiveCleanupContextV0
    ) async {
        if !context.progress.inputReleased {
            do {
                try await input.releaseAllInteractiveInput()
                context.progress.inputReleased = true
            } catch {}
        }
        if !context.progress.captureStopped {
            do {
                try await capture.stopInteractiveCapture()
                context.progress.captureStopped = true
            } catch {}
        }
        if !context.progress.lastFrameBlanked {
            do {
                try await frame.blankLastInteractiveFrame()
                context.progress.lastFrameBlanked = true
            } catch {}
        }
        if context.progress.inputReleased,
           context.progress.captureStopped,
           context.progress.lastFrameBlanked,
           !context.progress.indicatorCleared {
            do {
                try await indicator.clearInteractiveIndicator()
                context.progress.indicatorCleared = true
            } catch {}
        }
    }
}
