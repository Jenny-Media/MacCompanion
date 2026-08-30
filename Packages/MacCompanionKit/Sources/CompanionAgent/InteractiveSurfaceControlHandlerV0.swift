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
    private let displaySelector:
        (any AgentInteractiveDisplayMenuRoutingV1)?
    private let clock: any InteractiveSurfaceMonotonicClockV0
    private let focusIdentifier: @Sendable () -> UUID
    private var expectedClientSequence: Int64 = 1
    private var nextServerSequence: Int64 = 1
    private var prepared: InteractiveSurfaceRuntimePreparedV0?
    private var initialWasDescribed = false
    private var initialWasAcknowledged = false
    private var focusEvents: InteractiveFocusEventAuthorityV0?
    private var lastAuthenticatedContext: InteractiveSessionCommandContextV0?
    private var closed = false

    public init(
        coordinator: InteractiveSurfaceRuntimeCoordinatorV0,
        resolver: any InteractiveSurfaceTargetResolvingV0,
        inventoryProvider:
            (any InteractiveSurfaceTargetInventoryProvidingV0)? = nil,
        displaySelector:
            (any AgentInteractiveDisplayMenuRoutingV1)? = nil,
        clock: any InteractiveSurfaceMonotonicClockV0,
        focusIdentifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.coordinator = coordinator
        self.resolver = resolver
        self.inventoryProvider = inventoryProvider
        self.displaySelector = displaySelector
        self.clock = clock
        self.focusIdentifier = focusIdentifier
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
            focusEvents = try InteractiveFocusEventAuthorityV0(
                interactiveSessionID:
                    initial.descriptor.interactiveSessionID,
                authorizationEpoch:
                    initial.descriptor.authorizationEpoch,
                targetIdentifier: focusIdentifier
            )
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
            lastAuthenticatedContext = context
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
            let now = Int64(try currentTime(
                notBeforeMilliseconds: context.monotonicNowMilliseconds
            ).milliseconds)
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
            let currentDescriptor = try await coordinator
                .currentDescriptor()
            var expectedFocus: SurfaceFocus?
            var selectedTargetKind = request.targetKind
            if request.targetKind == .focusedRegion {
                guard var focusEvents else {
                    throw InteractiveSurfaceControlHandlerErrorV0
                        .descriptorMismatch
                }
                do {
                    expectedFocus = try focusEvents.consume(
                        request,
                        current: currentDescriptor,
                        hostMonotonicNowMilliseconds: Int64(
                            context.monotonicNowMilliseconds
                        )
                    )
                    self.focusEvents = focusEvents
                } catch let error as
                    InteractiveFocusEventAuthorityErrorV0
                {
                    switch error {
                    case .unavailable, .expired, .tokenMismatch:
                        // Accessibility focus is advisory and can legitimately
                        // be superseded while this authenticated request is in
                        // flight. Fall back to the already-authorized Desktop
                        // surface instead of treating normal app switching as
                        // a fatal primary-session protocol violation.
                        expectedFocus = nil
                        selectedTargetKind = .desktop
                        self.focusEvents?.revokeCurrent()
                    case .invalidConfiguration, .invalidCandidate,
                         .sequenceExhausted, .fenceMismatch:
                        throw error
                    }
                }
            } else {
                expectedFocus = nil
                focusEvents?.revokeCurrent()
            }
            var target: AdaptiveSurfaceDescriptor
            var selectedDisplayID: UUID?
            if let requestedDisplayID = request.targetDisplayID?.rawValue {
                guard selectedTargetKind == .desktop,
                      let displaySelector else {
                    throw InteractiveSurfaceControlHandlerErrorV0
                        .descriptorMismatch
                }
                let selected = try await displaySelector
                    .selectInteractiveDisplay(requestedDisplayID)
                guard selected.selectedDisplayID == requestedDisplayID else {
                    throw InteractiveSurfaceControlHandlerErrorV0
                        .descriptorMismatch
                }
                selectedDisplayID = requestedDisplayID
            }
            if selectedTargetKind == .desktop {
                target = try await resolver.resolve(
                    try desktopFallbackRequest(for: request),
                    context: context
                )
            } else {
                do {
                    target = try await resolver.resolve(
                        request,
                        context: context
                    )
                } catch {
                    guard request.targetKind == .focusedRegion else {
                        throw error
                    }
                    target = try await resolver.resolve(
                        try desktopFallbackRequest(for: request),
                        context: context
                    )
                    expectedFocus = nil
                    selectedTargetKind = .desktop
                    focusEvents?.revokeCurrent()
                }
                if let resolvedFocus = expectedFocus,
                   (target.kind != .focusedRegion
                    || target.focus != resolvedFocus) {
                    target = try await resolver.resolve(
                        try desktopFallbackRequest(for: request),
                        context: context
                    )
                    self.focusEvents?.revokeCurrent()
                    expectedFocus = nil
                    selectedTargetKind = .desktop
                }
            }
            guard target.kind == selectedTargetKind else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .descriptorMismatch
            }
            // Resolution crosses local IPC and may create the descriptor
            // after the network request arrived. Validate it at completion,
            // using one host-clock sample for both time units.
            let resolvedAt = try currentTime(
                notBeforeMilliseconds: context.monotonicNowMilliseconds
            )
            let result = try await coordinator.prepareSelection(
                target: target,
                expectedSurfaceRevision:
                    request.expectedSurfaceRevision,
                expectedCoordinateSpaceRevision:
                    request.expectedCoordinateSpaceRevision,
                selectedDisplayID: selectedDisplayID,
                monotonicNowMilliseconds: Int64(resolvedAt.milliseconds),
                monotonicNowNanoseconds: resolvedAt.nanoseconds
            )
            guard result.receipt.mediaSequenceBeforeTransition
                    <= UInt64(WireLimits.maximumSafeInteger) else {
                throw InteractiveSurfaceControlHandlerErrorV0
                    .invalidTime
            }
            let validity = try wireValidity(
                descriptor: result.descriptor,
                nowMilliseconds: try currentTime(
                    notBeforeMilliseconds: resolvedAt.milliseconds
                ).milliseconds
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
        lastAuthenticatedContext = nil
        focusEvents?.invalidate()
    }

    public func currentFocusEventReadiness() async
        -> InteractiveFocusEventReadinessV0?
    {
        guard !closed, initialWasAcknowledged, prepared == nil,
              focusEvents != nil, let lastAuthenticatedContext else {
            return nil
        }
        guard let descriptor = try? await coordinator.currentDescriptor()
        else { return nil }
        return try? InteractiveFocusEventReadinessV0(
            descriptor: descriptor,
            primaryConnectionID:
                lastAuthenticatedContext.primaryConnectionID
        )
    }

    public func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) async throws -> InteractivePreparedFocusEventV0 {
        guard let previous = lastAuthenticatedContext else {
            throw InteractiveFocusEventAuthorityErrorV0.unavailable
        }
        guard hostContext.hostState == .userSessionActive,
              hostContext.wallNowUnixMilliseconds
                >= previous.wallNowUnixMilliseconds,
              hostContext.monotonicNowMilliseconds
                >= previous.monotonicNowMilliseconds else {
            throw InteractiveFocusEventAuthorityErrorV0.unavailable
        }
        let context = try InteractiveSessionCommandContextV0(
            deviceID: previous.deviceID,
            clientID: previous.clientID,
            deviceState: previous.deviceState,
            authorizationEpoch: previous.authorizationEpoch,
            grantRevision: previous.grantRevision,
            policyRevision: previous.policyRevision,
            primaryConnectionID: previous.primaryConnectionID,
            hostID: previous.hostID,
            hostFingerprint: previous.hostFingerprint,
            hostState: hostContext.hostState,
            wallNowUnixMilliseconds: hostContext.wallNowUnixMilliseconds,
            monotonicNowMilliseconds: hostContext.monotonicNowMilliseconds
        )
        return try await prepareFocusEvent(
            candidate: candidate,
            context: context,
            eventMessageID: hostContext.eventMessageID
        )
    }

    public func revokePreparedFocusEvent() async {
        focusEvents?.revokeCurrent()
    }

    public func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        context: InteractiveSessionCommandContextV0,
        eventMessageID: WireUUID
    ) async throws -> InteractivePreparedFocusEventV0 {
        do {
            guard !closed, initialWasAcknowledged, prepared == nil,
                  var focusEvents else {
                throw InteractiveSurfaceControlHandlerErrorV0.closed
            }
            let lease = await coordinator.lease()
            let nowNanoseconds = clock.nowNanoseconds()
            guard nowNanoseconds
                    >= lease.issuedAtMonotonicNanoseconds,
                  nowNanoseconds
                    < lease.expiresAtMonotonicNanoseconds else {
                throw InteractiveSurfaceControlHandlerErrorV0.invalidTime
            }
            try validatePrincipal(
                sessionID: lease.interactiveSessionID,
                authorizationEpoch: lease.authorizationEpoch,
                context: context,
                lease: lease
            )
            let descriptor = try await coordinator.currentDescriptor()
            let event = try focusEvents.prepare(
                candidate: candidate,
                current: descriptor,
                eventMessageID: eventMessageID,
                sentAtUnixMilliseconds:
                    context.wallNowUnixMilliseconds,
                hostMonotonicNowMilliseconds: Int64(
                    context.monotonicNowMilliseconds
                )
            )
            self.focusEvents = focusEvents
            return event
        } catch {
            // Focus publication is advisory. No event bytes or wider authority
            // escaped when preparation failed, so a stale async snapshot or
            // transient local preparation failure must not tear down the
            // otherwise current Control session. Delivery failure after a
            // successful preparation is handled separately by the observer.
            throw error
        }
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

    private func desktopFallbackRequest(
        for request: InteractiveSurfaceSelectBodyV0
    ) throws -> InteractiveSurfaceSelectBodyV0 {
        try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: request.interactiveSessionID,
            authorizationEpoch: request.authorizationEpoch,
            currentSurfaceID: request.currentSurfaceID,
            expectedSurfaceRevision: request.expectedSurfaceRevision,
            expectedCoordinateSpaceRevision:
                request.expectedCoordinateSpaceRevision,
            targetKind: .desktop,
            targetToken: nil,
            targetDisplayID: request.targetDisplayID,
            sequence: request.sequence
        )
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

    private func currentTime(
        notBeforeMilliseconds lowerBound: UInt64
    ) throws -> (milliseconds: UInt64, nanoseconds: UInt64) {
        let nanoseconds = clock.nowNanoseconds()
        let milliseconds = nanoseconds / 1_000_000
        guard milliseconds >= lowerBound,
              milliseconds <= UInt64(Int64.max) else {
            throw InteractiveSurfaceControlHandlerErrorV0.invalidTime
        }
        return (milliseconds, nanoseconds)
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
