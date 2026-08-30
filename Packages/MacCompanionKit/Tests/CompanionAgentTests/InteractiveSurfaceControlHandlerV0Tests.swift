import CompanionAgent
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let handlerHostID = UUID(
    uuidString: "019b1000-0000-7000-8000-000000000001"
)!
private let handlerDeviceID = UUID(
    uuidString: "019b2100-0000-7000-8000-000000000001"
)!
private let handlerClientID = UUID(
    uuidString: "019b2000-0000-7000-8000-000000000001"
)!
private let handlerSessionID = UUID(
    uuidString: "019b6000-0000-7000-8000-000000000001"
)!
private let handlerDisplayID = UUID(
    uuidString: "019b6700-0000-7000-8000-000000000001"
)!
private let handlerInitialSurfaceID = UUID(
    uuidString: "019b6100-0000-7000-8000-000000000001"
)!
private let handlerTargetSurfaceID = UUID(
    uuidString: "019b6100-0000-7000-8000-000000000002"
)!

private struct HandlerClock: InteractiveSurfaceMonotonicClockV0 {
    let value: UInt64
    func nowNanoseconds() -> UInt64 { value }
}

private actor HandlerResolver: InteractiveSurfaceTargetResolvingV0 {
    let target: AdaptiveSurfaceDescriptor
    private(set) var count = 0

    init(target: AdaptiveSurfaceDescriptor) {
        self.target = target
    }

    func resolve(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceDescriptor {
        count += 1
        return target
    }
}

private actor HandlerFocusChurnResolver:
    InteractiveSurfaceTargetResolvingV0
{
    let focused: AdaptiveSurfaceDescriptor
    let desktop: AdaptiveSurfaceDescriptor
    private(set) var requestedKinds: [InteractiveSurfaceKind] = []

    init(
        focused: AdaptiveSurfaceDescriptor,
        desktop: AdaptiveSurfaceDescriptor
    ) {
        self.focused = focused
        self.desktop = desktop
    }

    func resolve(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceDescriptor {
        requestedKinds.append(request.targetKind)
        return request.targetKind == .desktop ? desktop : focused
    }
}

private struct HandlerInventoryProvider:
    InteractiveSurfaceTargetInventoryProvidingV0
{
    var resolutionDelayMilliseconds: Int64 = 0

    func snapshot(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        let token = UUID(
            uuidString: "019b7200-0000-7000-8000-000000000001"
        )!
        return try AdaptiveSurfaceTargetInventorySnapshotV0(
            interactiveSessionID: handlerSessionID,
            authorizationEpoch: .init(rawValue: 4),
            revision: 1,
            createdAtMonotonicMilliseconds:
                Int64(context.monotonicNowMilliseconds)
                    + resolutionDelayMilliseconds,
            expiresAtMonotonicMilliseconds:
                Int64(context.monotonicNowMilliseconds)
                    + resolutionDelayMilliseconds + 10_000,
            candidates: [
                try AdaptiveSurfaceTargetCandidateV0(
                    targetToken: token,
                    kind: .application,
                    applicationToken: token,
                    applicationName: "Notes",
                    windowOrdinal: nil,
                    currentWindowAvailable: true
                ),
            ]
        )
    }
}

private actor HandlerRuntimeRoute: InteractiveSurfaceRuntimeRoutingV0 {
    private(set) var prepareCount = 0
    private(set) var acknowledgementCount = 0
    private(set) var terminationCount = 0

    func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        prepareCount += 1
        return try InteractiveRuntimeSurfaceTransitionReceiptV0(
            correlationID: command.commandID,
            previousLeaseID: command.previousLeaseID,
            replacementLeaseID: command.replacement.leaseID,
            interactiveSessionID: command.replacement.interactiveSessionID,
            surfaceID: command.replacement.surfaceID,
            surfaceRevision: command.replacement.surfaceRevision,
            coordinateRevision: command.replacement.coordinateRevision,
            mediaSequenceBeforeTransition: 4,
            inputReleased: true,
            captureSourcePrepared: true
        )
    }

    func acknowledgeSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        acknowledgementCount += 1
        return try InteractiveRuntimeSurfaceAcknowledgementReceiptV0(
            correlationID: command.commandID,
            transitionCommandID: command.transitionCommandID,
            leaseID: command.leaseID,
            interactiveSessionID: command.interactiveSessionID,
            surfaceID: command.surfaceID,
            surfaceRevision: command.surfaceRevision,
            coordinateRevision: command.coordinateRevision,
            focusToken: command.focusToken,
            focusRevision: command.focusRevision,
            readyMediaSequence: command.readyMediaSequence,
            inputResumed: true
        )
    }

    func terminateSurfaceFailure(
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) async throws -> Bool {
        terminationCount += 1
        return true
    }
}

private func handlerDescriptor(
    surfaceID: UUID,
    revision: UInt64,
    coordinateRevision: UInt64,
    createdAt: Int64 = 0,
    expiresAt: Int64 = 10_000
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: handlerSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: revision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: createdAt,
        expiresAtMonotonicMilliseconds: expiresAt
    )
}

private func handlerFocusedDescriptor(
    focus: SurfaceFocus,
    createdAt: Int64 = 2_000
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: handlerSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: handlerTargetSurfaceID,
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: UUID(),
        parentSurfaceID: handlerInitialSurfaceID,
        fallbackSurfaceID: handlerInitialSurfaceID,
        encodedWidth: 1_000,
        encodedHeight: 500,
        logicalWidthPoints: 1_000,
        logicalHeightPoints: 500,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .assistedVisual,
        metadataFields: [.focusCategory, .focusBounds, .editable, .secure],
        focus: focus,
        createdAtMonotonicMilliseconds: createdAt,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func handlerContext(
    monotonicNowMilliseconds: UInt64 = 2_000
) throws -> InteractiveSessionCommandContextV0 {
    try InteractiveSessionCommandContextV0(
        deviceID: handlerDeviceID,
        clientID: handlerClientID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6),
        primaryConnectionID: Data(repeating: 0x11, count: 16),
        hostID: handlerHostID,
        hostFingerprint: Data(repeating: 0x22, count: 32),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 1_720_000_000_000,
        monotonicNowMilliseconds: monotonicNowMilliseconds
    )
}

private func handlerLease() throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: handlerHostID,
        deviceID: handlerDeviceID,
        interactiveSessionID: handlerSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: handlerDisplayID,
        surfaceID: handlerInitialSurfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer, .keyboard],
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000_000_000,
        expiresAtMonotonicNanoseconds: 8_000_000_000
    )
}

private let handlerActivationID = UUID(
    uuidString: "019b6900-0000-7000-8000-000000000001"
)!

private func makeHandler(
    initialPending: Bool = false,
    targetCreatedAt: Int64 = 0,
    targetExpiresAt: Int64 = 10_000,
    clockNanoseconds: UInt64? = nil,
    inventoryDelayMilliseconds: Int64 = 0
) throws -> (
    InteractiveSurfaceControlHandlerV0,
    HandlerResolver,
    HandlerRuntimeRoute
) {
    let initial = try handlerDescriptor(
        surfaceID: handlerInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let target = try handlerDescriptor(
        surfaceID: handlerTargetSurfaceID,
        revision: 2,
        coordinateRevision: 2,
        createdAt: targetCreatedAt,
        expiresAt: targetExpiresAt
    )
    let route = HandlerRuntimeRoute()
    let coordinator = try InteractiveSurfaceRuntimeCoordinatorV0(
        surfaceAuthority: AdaptiveSurfaceAuthority(
            desktop: initial,
            monotonicNowMilliseconds: 1_000
        ),
        currentLease: handlerLease(),
        sessionDeadlineMonotonicNanoseconds: 12_000_000_000,
        runtime: route,
        initialActivationCommandID:
            initialPending ? handlerActivationID : nil
    )
    let resolver = HandlerResolver(target: target)
    return (
        InteractiveSurfaceControlHandlerV0(
            coordinator: coordinator,
            resolver: resolver,
            inventoryProvider: HandlerInventoryProvider(
                resolutionDelayMilliseconds: inventoryDelayMilliseconds
            ),
            clock: HandlerClock(value: clockNanoseconds
                ?? (initialPending ? 2_200_000_000 : 2_000_000_000))
        ),
        resolver,
        route
    )
}

@Test(arguments: [Int64(0), Int64(20)])
func agentSurfaceHandlerGatesInitialDescriptorAndAck(
    inventoryDelayMilliseconds: Int64
) async throws {
    let (handler, resolver, route) = try makeHandler(
        initialPending: true,
        inventoryDelayMilliseconds: inventoryDelayMilliseconds
    )
    let request = try InteractiveInitialSurfaceRequestBodyV0(
        interactiveSessionID: WireUUID(handlerSessionID),
        authorizationEpoch: .init(rawValue: 4),
        sequence: 1
    )
    let described = try await handler.requestInitial(
        request,
        context: handlerContext()
    )
    #expect(described.activationID.rawValue == handlerActivationID)
    #expect(described.sequence == 1)
    #expect(described.mediaSequenceBeforeActivation == 0)
    #expect(described.descriptor.kind == .desktop)
    #expect(await resolver.count == 0)
    #expect(await route.acknowledgementCount == 0)

    let ack = try InteractiveInitialSurfaceAcknowledgementBodyV0(
        interactiveSessionID: described.descriptor.interactiveSessionID,
        authorizationEpoch: described.descriptor.authorizationEpoch,
        activationID: described.activationID,
        surfaceID: described.descriptor.surfaceID,
        surfaceRevision: described.descriptor.surfaceRevision,
        coordinateSpaceRevision:
            described.descriptor.coordinateSpaceRevision,
        readyMediaSequence: 2,
        sequence: 2
    )
    let acknowledged = try await handler.acknowledgeInitial(
        ack,
        context: handlerContext(monotonicNowMilliseconds: 2_100)
    )
    #expect(acknowledged.sequence == 2)
    #expect(acknowledged.inputResumed)
    #expect(await route.acknowledgementCount == 1)
    #expect(await route.terminationCount == 0)

    let targets = try await handler.targets(
        try InteractiveSurfaceTargetsRequestBodyV0(
            interactiveSessionID: described.descriptor.interactiveSessionID,
            authorizationEpoch: described.descriptor.authorizationEpoch,
            sequence: 3
        ),
        context: handlerContext(monotonicNowMilliseconds: 2_150)
    )
    #expect(targets.sequence == 3)
    #expect(targets.validForMilliseconds == 9_950 + inventoryDelayMilliseconds)
    #expect(targets.candidates.map(\.applicationName) == ["Notes"])

    let selected = try await handler.select(
        handlerSelection(sequence: 4),
        context: handlerContext(monotonicNowMilliseconds: 2_200)
    )
    #expect(selected.sequence == 4)
    let replacementAck = try InteractiveSurfaceAcknowledgementBodyV0(
        interactiveSessionID: selected.descriptor.interactiveSessionID,
        authorizationEpoch: selected.descriptor.authorizationEpoch,
        transitionID: selected.transitionID,
        surfaceID: selected.descriptor.surfaceID,
        surfaceRevision: selected.descriptor.surfaceRevision,
        coordinateSpaceRevision:
            selected.descriptor.coordinateSpaceRevision,
        readyMediaSequence: 9,
        sequence: 5
    )
    let replacementAcknowledged = try await handler.acknowledge(
        replacementAck,
        context: handlerContext(monotonicNowMilliseconds: 2_300)
    )
    #expect(replacementAcknowledged.sequence == 5)
    #expect(await resolver.count == 1)
    #expect(await route.acknowledgementCount == 2)
}

@Test(arguments: [Int64(0), Int64(20)])
func agentSurfaceHandlerBindsFocusEventToExactResolvedDescriptor(
    resolutionDelayMilliseconds: Int64
)
    async throws
{
    let initial = try handlerDescriptor(
        surfaceID: handlerInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 12_000,
            y: 20_000,
            width: 30_000,
            height: 8_000
        ),
        editable: true,
        secure: false
    )
    let targetToken = UUID()
    let route = HandlerRuntimeRoute()
    let coordinator = try InteractiveSurfaceRuntimeCoordinatorV0(
        surfaceAuthority: AdaptiveSurfaceAuthority(
            desktop: initial,
            monotonicNowMilliseconds: 1_000
        ),
        currentLease: handlerLease(),
        sessionDeadlineMonotonicNanoseconds: 12_000_000_000,
        runtime: route,
        initialActivationCommandID: handlerActivationID
    )
    let resolver = HandlerResolver(
        target: try handlerFocusedDescriptor(
            focus: focus,
            createdAt: 2_200 + resolutionDelayMilliseconds
        )
    )
    let handler = InteractiveSurfaceControlHandlerV0(
        coordinator: coordinator,
        resolver: resolver,
        clock: HandlerClock(value:
            UInt64(2_200 + resolutionDelayMilliseconds) * 1_000_000),
        focusIdentifier: { targetToken }
    )
    let described = try await handler.requestInitial(
        try InteractiveInitialSurfaceRequestBodyV0(
            interactiveSessionID: WireUUID(handlerSessionID),
            authorizationEpoch: .init(rawValue: 4),
            sequence: 1
        ),
        context: handlerContext()
    )
    _ = try await handler.acknowledgeInitial(
        try InteractiveInitialSurfaceAcknowledgementBodyV0(
            interactiveSessionID: described.descriptor.interactiveSessionID,
            authorizationEpoch: described.descriptor.authorizationEpoch,
            activationID: described.activationID,
            surfaceID: described.descriptor.surfaceID,
            surfaceRevision: described.descriptor.surfaceRevision,
            coordinateSpaceRevision:
                described.descriptor.coordinateSpaceRevision,
            readyMediaSequence: 2,
            sequence: 2
        ),
        context: handlerContext(monotonicNowMilliseconds: 2_100)
    )
    let readiness = try #require(
        await handler.currentFocusEventReadiness()
    )
    #expect(readiness.descriptor == initial)
    #expect(readiness.primaryConnectionID == Data(repeating: 0x11, count: 16))
    let preparedEvent = try await handler.prepareFocusEvent(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .focusedRegion,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus
        ),
        hostContext: try InteractiveFocusEventHostContextV0(
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 1_720_000_000_100,
            monotonicNowMilliseconds: 2_150,
            eventMessageID: WireUUID(UUID())
        )
    )
    #expect(preparedEvent.targetToken == WireUUID(targetToken))

    let selected = try await handler.select(
        try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: WireUUID(handlerSessionID),
            authorizationEpoch: .init(rawValue: 4),
            currentSurfaceID: WireUUID(handlerInitialSurfaceID),
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .focusedRegion,
            targetToken: WireUUID(targetToken),
            sequence: 3
        ),
        context: handlerContext(monotonicNowMilliseconds: 2_200)
    )
    #expect(try selected.descriptor.materialize(
        clientMonotonicNowMilliseconds: 2_200
    ).focus == focus)
    #expect(await resolver.count == 1)
    #expect(await route.prepareCount == 1)
}

@Test func agentSurfaceHandlerFallsBackToDesktopWhenFocusChangesInFlight()
    async throws
{
    let initial = try handlerDescriptor(
        surfaceID: handlerInitialSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    let offeredFocus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 12_000,
            y: 20_000,
            width: 30_000,
            height: 8_000
        ),
        editable: true,
        secure: false
    )
    let changedFocus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 2),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 20_000,
            y: 25_000,
            width: 25_000,
            height: 8_000
        ),
        editable: true,
        secure: false
    )
    let targetToken = UUID()
    let route = HandlerRuntimeRoute()
    let coordinator = try InteractiveSurfaceRuntimeCoordinatorV0(
        surfaceAuthority: AdaptiveSurfaceAuthority(
            desktop: initial,
            monotonicNowMilliseconds: 1_000
        ),
        currentLease: handlerLease(),
        sessionDeadlineMonotonicNanoseconds: 12_000_000_000,
        runtime: route,
        initialActivationCommandID: handlerActivationID
    )
    let desktopFallback = try handlerDescriptor(
        surfaceID: handlerTargetSurfaceID,
        revision: 2,
        coordinateRevision: 2,
        createdAt: 2_200
    )
    let resolver = HandlerFocusChurnResolver(
        focused: try handlerFocusedDescriptor(
            focus: changedFocus,
            createdAt: 2_200
        ),
        desktop: desktopFallback
    )
    let handler = InteractiveSurfaceControlHandlerV0(
        coordinator: coordinator,
        resolver: resolver,
        clock: HandlerClock(value: 2_200_000_000),
        focusIdentifier: { targetToken }
    )
    let described = try await handler.requestInitial(
        try InteractiveInitialSurfaceRequestBodyV0(
            interactiveSessionID: WireUUID(handlerSessionID),
            authorizationEpoch: .init(rawValue: 4),
            sequence: 1
        ),
        context: handlerContext()
    )
    _ = try await handler.acknowledgeInitial(
        try InteractiveInitialSurfaceAcknowledgementBodyV0(
            interactiveSessionID: described.descriptor.interactiveSessionID,
            authorizationEpoch: described.descriptor.authorizationEpoch,
            activationID: described.activationID,
            surfaceID: described.descriptor.surfaceID,
            surfaceRevision: described.descriptor.surfaceRevision,
            coordinateSpaceRevision:
                described.descriptor.coordinateSpaceRevision,
            readyMediaSequence: 2,
            sequence: 2
        ),
        context: handlerContext(monotonicNowMilliseconds: 2_100)
    )
    _ = try await handler.prepareFocusEvent(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .focusedRegion,
            focus: offeredFocus,
            inputPaused: false,
            reason: .verifiedFocus
        ),
        hostContext: try InteractiveFocusEventHostContextV0(
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 1_720_000_000_100,
            monotonicNowMilliseconds: 2_150,
            eventMessageID: WireUUID(UUID())
        )
    )

    let selected = try await handler.select(
        try InteractiveSurfaceSelectBodyV0(
            interactiveSessionID: WireUUID(handlerSessionID),
            authorizationEpoch: .init(rawValue: 4),
            currentSurfaceID: WireUUID(handlerInitialSurfaceID),
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            targetKind: .focusedRegion,
            targetToken: WireUUID(targetToken),
            sequence: 3
        ),
        context: handlerContext(monotonicNowMilliseconds: 2_200)
    )
    let materialized = try selected.descriptor.materialize(
        clientMonotonicNowMilliseconds: 2_200
    )
    #expect(materialized.kind == .desktop)
    #expect(materialized.focus == nil)
    #expect(await resolver.requestedKinds == [.focusedRegion, .desktop])
    #expect(await route.prepareCount == 1)
}

@Test func agentSurfaceHandlerValidatesResolvedSurfaceAtCurrentHostTime()
    async throws
{
    let (handler, _, route) = try makeHandler(
        targetCreatedAt: 2_020,
        clockNanoseconds: 2_050_000_000
    )
    let selected = try await handler.select(
        handlerSelection(),
        context: handlerContext(monotonicNowMilliseconds: 2_000)
    )
    #expect(selected.descriptor.validForMilliseconds == 7_950)
    #expect(await route.prepareCount == 1)
    #expect(await route.terminationCount == 0)
}

@Test(arguments: [(Int64(2_060), Int64(10_000)), (Int64(2_010), Int64(2_050))])
func agentSurfaceHandlerStillRejectsFutureOrExpiredResolvedSurface(
    lifetime: (Int64, Int64)
) async throws {
    let (handler, _, route) = try makeHandler(
        targetCreatedAt: lifetime.0,
        targetExpiresAt: lifetime.1,
        clockNanoseconds: 2_050_000_000
    )
    await #expect(throws: AdaptiveSurfaceError.expired) {
        _ = try await handler.select(
            handlerSelection(),
            context: handlerContext(monotonicNowMilliseconds: 2_000)
        )
    }
    #expect(await route.prepareCount == 0)
}

@Test func agentSurfaceHandlerRejectsClockRollbackAfterResolution()
    async throws
{
    let (handler, _, route) = try makeHandler(clockNanoseconds: 1_999_000_000)
    await #expect(throws: InteractiveSurfaceControlHandlerErrorV0.invalidTime) {
        _ = try await handler.select(
            handlerSelection(),
            context: handlerContext(monotonicNowMilliseconds: 2_000)
        )
    }
    #expect(await route.prepareCount == 0)
}

private func handlerSelection(sequence: Int64 = 1) throws
    -> InteractiveSurfaceSelectBodyV0
{
    try InteractiveSurfaceSelectBodyV0(
        interactiveSessionID: WireUUID(handlerSessionID),
        authorizationEpoch: .init(rawValue: 4),
        currentSurfaceID: WireUUID(handlerInitialSurfaceID),
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        targetKind: .desktop,
        targetToken: nil,
        sequence: sequence
    )
}

@Test func agentSurfaceHandlerBridgesSelectionAndAckWithExactSequences() async throws {
    let (handler, resolver, route) = try makeHandler()
    let selected = try await handler.select(
        handlerSelection(),
        context: handlerContext()
    )
    #expect(selected.sequence == 1)
    #expect(selected.mediaSequenceBeforeTransition == 4)
    #expect(selected.descriptor.validForMilliseconds == 8_000)
    #expect(selected.descriptor.surfaceID.rawValue == handlerTargetSurfaceID)
    #expect(await resolver.count == 1)
    #expect(await route.prepareCount == 1)

    let acknowledgement = try InteractiveSurfaceAcknowledgementBodyV0(
        interactiveSessionID: selected.descriptor.interactiveSessionID,
        authorizationEpoch: selected.descriptor.authorizationEpoch,
        transitionID: selected.transitionID,
        surfaceID: selected.descriptor.surfaceID,
        surfaceRevision: selected.descriptor.surfaceRevision,
        coordinateSpaceRevision:
            selected.descriptor.coordinateSpaceRevision,
        readyMediaSequence: 9,
        sequence: 2
    )
    let acknowledged = try await handler.acknowledge(
        acknowledgement,
        context: handlerContext(monotonicNowMilliseconds: 2_100)
    )
    #expect(acknowledged.sequence == 2)
    #expect(acknowledged.readyMediaSequence == 9)
    #expect(acknowledged.inputResumed)
    #expect(await route.acknowledgementCount == 1)
    #expect(await route.terminationCount == 0)
}

@Test func agentSurfaceHandlerRejectsSequenceGapBeforeResolution() async throws {
    let (handler, resolver, route) = try makeHandler()

    await #expect(
        throws: InteractiveSurfaceControlHandlerErrorV0
            .sequenceMismatch(expected: 1, actual: 2)
    ) {
        _ = try await handler.select(
            handlerSelection(sequence: 2),
            context: handlerContext()
        )
    }
    #expect(await resolver.count == 0)
    #expect(await route.prepareCount == 0)
    await #expect(throws: InteractiveSurfaceControlHandlerErrorV0.closed) {
        _ = try await handler.select(
            handlerSelection(),
            context: handlerContext()
        )
    }
}

@Test func agentSurfaceHandlerRejectsChangedTransitionBeforeRuntimeAck() async throws {
    let (handler, _, route) = try makeHandler()
    let selected = try await handler.select(
        handlerSelection(),
        context: handlerContext()
    )
    let acknowledgement = try InteractiveSurfaceAcknowledgementBodyV0(
        interactiveSessionID: selected.descriptor.interactiveSessionID,
        authorizationEpoch: selected.descriptor.authorizationEpoch,
        transitionID: WireUUID(UUID()),
        surfaceID: selected.descriptor.surfaceID,
        surfaceRevision: selected.descriptor.surfaceRevision,
        coordinateSpaceRevision:
            selected.descriptor.coordinateSpaceRevision,
        readyMediaSequence: 9,
        sequence: 2
    )

    await #expect(
        throws: InteractiveSurfaceControlHandlerErrorV0.transitionMismatch
    ) {
        _ = try await handler.acknowledge(
            acknowledgement,
            context: handlerContext(monotonicNowMilliseconds: 2_100)
        )
    }
    #expect(await route.acknowledgementCount == 0)
}
