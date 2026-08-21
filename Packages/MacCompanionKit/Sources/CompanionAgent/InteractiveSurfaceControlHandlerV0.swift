import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionIPC
import CompanionWire
import Foundation

public enum InteractiveSurfaceControlHandlerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case closed
    case transitionInProgress
    case noTransition
    case sequenceMismatch(expected: Int64, actual: Int64)
    case sequenceExhausted
    case principalMismatch
    case transitionMismatch
    case descriptorMismatch
    case invalidTime
}

public protocol InteractiveSurfaceTargetResolvingV0: Sendable {
    /// Resolves only a current session-scoped opaque token. The returned
    /// descriptor is still treated as untrusted input by the Agent's surface
    /// authority and cannot expand the session lease.
    func resolve(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceDescriptor
}

/// Menu-app-owned inventory reached through authenticated local IPC. The
/// implementation sanitizes ScreenCaptureKit state before returning; source
/// objects and OS identifiers never enter the Agent.
public protocol InteractiveSurfaceTargetInventoryProvidingV0: Sendable {
    func snapshot(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0
}

public protocol InteractiveSurfaceMonotonicClockV0: Sendable {
    func nowNanoseconds() -> UInt64
}

/// Agent-side application-primary surface-control owner. It is the only
/// adapter that converts remote selection intent into an Agent-issued runtime
/// lease and the only adapter that converts a clean-media acknowledgement into
/// runtime input resumption.
public actor InteractiveSurfaceControlHandlerV0:
    InteractiveSurfaceControlDispatchingV0
{
    private let coordinator: InteractiveSurfaceRuntimeCoordinatorV0
    private let resolver: any InteractiveSurfaceTargetResolvingV0
    private let inventoryProvider:
        (any InteractiveSurfaceTargetInventoryProvidingV0)?
    private let clock: any InteractiveSurfaceMonotonicClockV0
    private var expectedClientSequence: Int64 = 1
    private var nextServerSequence: Int64 = 1
    private var prepared: InteractiveSurfaceRuntimePreparedV0?
    private var initialWasDescribed = false
    private var initialWasAcknowledged = false
    private var closed = false

    public init(
        coordinator: InteractiveSurfaceRuntimeCoordinatorV0,
        resolver: any InteractiveSurfaceTargetResolvingV0,
        inventoryProvider:
            (any InteractiveSurfaceTargetInventoryProvidingV0)? = nil,
        clock: any InteractiveSurfaceMonotonicClockV0
    ) {
        self.coordinator = coordinator
        self.resolver = resolver
        self.inventoryProvider = inventoryProvider
        self.clock = clock
    }

    public func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0 {
        do {
            guard !closed, !initialWasDescribed, prepared == nil else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionInProgress
            }
            try admitClientSequence(request.sequence)
            let initial = try await coordinator.initialActivation()
            try validatePrincipal(
                sessionID: request.interactiveSessionID.rawValue,
                authorizationEpoch: request.authorizationEpoch,
                context: context,
                lease: initial.lease
            )
            let validity = try wireValidity(
                descriptor: initial.descriptor,
                nowMilliseconds: context.monotonicNowMilliseconds
            )
            let serverSequence = try consumeServerSequence()
            let body = try InteractiveInitialSurfaceDescriptorBodyV0(
                activationID: WireUUID(initial.activationID),
                descriptor: InteractiveSurfaceWireDescriptorV0(
                    descriptor: initial.descriptor,
                    validForMilliseconds: validity
                ),
                mediaSequenceBeforeActivation: 0,
                sequence: serverSequence
            )
            initialWasDescribed = true
            expectedClientSequence += 1
            nextServerSequence += 1
            return body
        } catch {
            closed = true
            throw error
        }
    }

    public func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0 {
        do {
            guard !closed, initialWasDescribed, prepared == nil else {
                throw InteractiveSurfaceControlHandlerErrorV0.noTransition
            }
            try admitClientSequence(request.sequence)
            let initial = try await coordinator.initialActivation()
            try validatePrincipal(
                sessionID: request.interactiveSessionID.rawValue,
                authorizationEpoch: request.authorizationEpoch,
                context: context,
                lease: initial.lease
            )
            guard request.activationID.rawValue == initial.activationID,
                  request.surfaceID.rawValue == initial.descriptor.surfaceID,
                  request.surfaceRevision == initial.descriptor.surfaceRevision,
                  request.coordinateSpaceRevision
                    == initial.descriptor.coordinateSpaceRevision else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionMismatch
            }
            _ = try await coordinator.acknowledgeInitial(
                fence: request.fence(),
                readyMediaSequence: UInt64(request.readyMediaSequence),
                monotonicNowMilliseconds: Int64(
                    context.monotonicNowMilliseconds
                ),
                monotonicNowNanoseconds: clock.nowNanoseconds()
            )
            let serverSequence = try consumeServerSequence()
            let body = try InteractiveInitialSurfaceAcknowledgedBodyV0(
                acknowledgement: request,
                inputResumed: true,
                sequence: serverSequence
            )
            initialWasAcknowledged = true
            expectedClientSequence += 1
            nextServerSequence += 1
            return body
        } catch {
            closed = true
            throw error
        }
    }

    public func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0 {
        do {
            guard !closed, initialWasAcknowledged, prepared == nil,
                  let inventoryProvider else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionInProgress
            }
            try admitClientSequence(request.sequence)
            let lease = await coordinator.lease()
            try validatePrincipal(
                sessionID: request.interactiveSessionID.rawValue,
                authorizationEpoch: request.authorizationEpoch,
                context: context,
                lease: lease
            )
            let snapshot = try await inventoryProvider.snapshot(
                request,
                context: context
            )
            let now = Int64(context.monotonicNowMilliseconds)
            guard snapshot.interactiveSessionID
                    == request.interactiveSessionID.rawValue,
                  snapshot.authorizationEpoch == request.authorizationEpoch,
                  snapshot.revision <= UInt64(WireLimits.maximumSafeInteger),
                  snapshot.createdAtMonotonicMilliseconds <= now,
                  snapshot.expiresAtMonotonicMilliseconds > now else {
                throw InteractiveSurfaceControlHandlerErrorV0.invalidTime
            }
            let candidates = try snapshot.candidates.map { candidate in
                try InteractiveSurfaceTargetCandidateV0(
                    targetToken: WireUUID(candidate.targetToken),
                    kind: candidate.kind,
                    applicationToken: WireUUID(candidate.applicationToken),
                    applicationName: candidate.applicationName,
                    windowOrdinal: candidate.windowOrdinal.map(Int64.init),
                    currentWindowAvailable:
                        candidate.currentWindowAvailable
                )
            }
            let serverSequence = try consumeServerSequence()
            let body = try InteractiveSurfaceTargetsResponseBodyV0(
                interactiveSessionID: request.interactiveSessionID,
                authorizationEpoch: request.authorizationEpoch,
                inventoryRevision: Int64(snapshot.revision),
                validForMilliseconds:
                    snapshot.expiresAtMonotonicMilliseconds - now,
                candidates: candidates,
                sequence: serverSequence
            )
            expectedClientSequence += 1
            nextServerSequence += 1
            return body
        } catch {
            closed = true
            throw error
        }
    }

    public func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0 {
        do {
            guard !closed else {
                throw InteractiveSurfaceControlHandlerErrorV0.closed
            }
            guard prepared == nil else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionInProgress
            }
            try admitClientSequence(request.sequence)
            let lease = await coordinator.lease()
            try validatePrincipal(
                sessionID: request.interactiveSessionID.rawValue,
                authorizationEpoch: request.authorizationEpoch,
                context: context,
                lease: lease
            )
            guard request.currentSurfaceID.rawValue == lease.surfaceID,
                  request.expectedSurfaceRevision.rawValue
                    == lease.surfaceRevision.rawValue,
                  request.expectedCoordinateSpaceRevision.rawValue
                    == lease.coordinateRevision.rawValue else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .descriptorMismatch
            }
            let target = try await resolver.resolve(request, context: context)
            let nowNanoseconds = clock.nowNanoseconds()
            let result = try await coordinator.prepareSelection(
                target: target,
                expectedSurfaceRevision:
                    request.expectedSurfaceRevision,
                expectedCoordinateSpaceRevision:
                    request.expectedCoordinateSpaceRevision,
                monotonicNowMilliseconds: Int64(
                    context.monotonicNowMilliseconds
                ),
                monotonicNowNanoseconds: nowNanoseconds
            )
            guard result.receipt.mediaSequenceBeforeTransition
                    <= UInt64(WireLimits.maximumSafeInteger) else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .invalidTime
            }
            let validity = try wireValidity(
                descriptor: result.descriptor,
                nowMilliseconds: context.monotonicNowMilliseconds
            )
            let serverSequence = try consumeServerSequence()
            let body = try InteractiveSurfaceSelectedBodyV0(
                transitionID: WireUUID(result.command.commandID),
                descriptor: InteractiveSurfaceWireDescriptorV0(
                    descriptor: result.descriptor,
                    validForMilliseconds: validity
                ),
                mediaSequenceBeforeTransition: Int64(
                    result.receipt.mediaSequenceBeforeTransition
                ),
                sequence: serverSequence
            )
            prepared = result
            expectedClientSequence += 1
            nextServerSequence += 1
            return body
        } catch {
            closed = true
            throw error
        }
    }

    public func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0 {
        do {
            guard !closed else {
                throw InteractiveSurfaceControlHandlerErrorV0.closed
            }
            guard let prepared else {
                throw InteractiveSurfaceControlHandlerErrorV0.noTransition
            }
            try admitClientSequence(request.sequence)
            let lease = await coordinator.lease()
            try validatePrincipal(
                sessionID: request.interactiveSessionID.rawValue,
                authorizationEpoch: request.authorizationEpoch,
                context: context,
                lease: lease
            )
            let descriptor = prepared.descriptor
            guard request.transitionID.rawValue
                    == prepared.command.commandID,
                  request.surfaceID.rawValue == descriptor.surfaceID,
                  request.surfaceRevision == descriptor.surfaceRevision,
                  request.coordinateSpaceRevision
                    == descriptor.coordinateSpaceRevision,
                  request.focusToken?.rawValue
                    == descriptor.focus?.token,
                  request.focusRevision
                    == descriptor.focus?.revision else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionMismatch
            }
            guard request.readyMediaSequence > 0 else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .transitionMismatch
            }
            let nowNanoseconds = clock.nowNanoseconds()
            _ = try await coordinator.acknowledge(
                fence: request.fence(),
                readyMediaSequence: UInt64(request.readyMediaSequence),
                monotonicNowMilliseconds: Int64(
                    context.monotonicNowMilliseconds
                ),
                monotonicNowNanoseconds: nowNanoseconds
            )
            let serverSequence = try consumeServerSequence()
            let body = try InteractiveSurfaceAcknowledgedBodyV0(
                acknowledgement: request,
                inputResumed: true,
                sequence: serverSequence
            )
            self.prepared = nil
            expectedClientSequence += 1
            nextServerSequence += 1
            return body
        } catch {
            closed = true
            throw error
        }
    }

    public func primarySessionClosed() async {
        closed = true
        prepared = nil
    }

    private func admitClientSequence(_ actual: Int64) throws {
        guard expectedClientSequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceControlHandlerErrorV0
                .sequenceExhausted
        }
        guard actual == expectedClientSequence else {
            throw InteractiveSurfaceControlHandlerErrorV0.sequenceMismatch(
                expected: expectedClientSequence,
                actual: actual
            )
        }
    }

    private func consumeServerSequence() throws -> Int64 {
        guard nextServerSequence >= 1,
              nextServerSequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceControlHandlerErrorV0
                .sequenceExhausted
        }
        return nextServerSequence
    }

    private func validatePrincipal(
        sessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        context: InteractiveSessionCommandContextV0,
        lease: InteractiveExecutionLease
    ) throws {
        guard lease.deviceID == context.deviceID,
              lease.hostID == context.hostID,
              lease.interactiveSessionID == sessionID,
              lease.authorizationEpoch == authorizationEpoch,
              context.authorizationEpoch == authorizationEpoch else {
            throw InteractiveSurfaceControlHandlerErrorV0
                .principalMismatch
        }
    }

    private func wireValidity(
        descriptor: AdaptiveSurfaceDescriptor,
        nowMilliseconds: UInt64
    ) throws -> Int64 {
        guard nowMilliseconds <= UInt64(Int64.max) else {
            throw InteractiveSurfaceControlHandlerErrorV0.invalidTime
        }
        let now = Int64(nowMilliseconds)
        guard descriptor.createdAtMonotonicMilliseconds <= now,
              descriptor.expiresAtMonotonicMilliseconds > now else {
            throw InteractiveSurfaceControlHandlerErrorV0.invalidTime
        }
        return min(
            descriptor.expiresAtMonotonicMilliseconds - now,
            InteractiveSurfaceWireDescriptorV0
                .maximumValidityMilliseconds
        )
    }
}
