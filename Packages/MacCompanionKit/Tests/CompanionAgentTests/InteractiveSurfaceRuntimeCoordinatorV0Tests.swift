import CompanionAgent
import CompanionDomain
import CompanionInteractiveShared
import CompanionIPC
import Foundation
import Testing

private let surfaceHostID = UUID(uuidString: "01991000-0000-7000-8000-000000000001")!
private let surfaceDeviceID = UUID(uuidString: "01992100-0000-7000-8000-000000000001")!
private let surfaceSessionID = UUID(uuidString: "01996000-0000-7000-8000-000000000001")!
private let surfaceDisplayID = UUID(uuidString: "01996700-0000-7000-8000-000000000001")!
private let desktopSurfaceID = UUID(uuidString: "01996100-0000-7000-8000-000000000001")!
private let targetSurfaceID = UUID(uuidString: "01996100-0000-7000-8000-000000000002")!

private enum SurfaceRouteError: Error {
    case rejected
}

private actor SurfaceRuntimeRouteProbe: InteractiveSurfaceRuntimeRoutingV0 {
    enum Reply: Sendable {
        case valid
        case mismatched
        case rejected
    }

    private let prepareReply: Reply
    private let acknowledgementReply: Reply
    private let terminationResult: Bool
    private var prepareCommands: [InteractiveRuntimeSurfaceTransitionCommandV0] = []
    private var acknowledgementCommands: [InteractiveRuntimeSurfaceAcknowledgementCommandV0] = []
    private var terminations: [(UUID, InteractiveSessionEndReason)] = []

    init(
        prepareReply: Reply = .valid,
        acknowledgementReply: Reply = .valid,
        terminationResult: Bool = true
    ) {
        self.prepareReply = prepareReply
        self.acknowledgementReply = acknowledgementReply
        self.terminationResult = terminationResult
    }

    func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        prepareCommands.append(command)
        guard prepareReply != .rejected else { throw SurfaceRouteError.rejected }
        return try InteractiveRuntimeSurfaceTransitionReceiptV0(
            correlationID: prepareReply == .mismatched ? UUID() : command.commandID,
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
        acknowledgementCommands.append(command)
        guard acknowledgementReply != .rejected else {
            throw SurfaceRouteError.rejected
        }
        return try InteractiveRuntimeSurfaceAcknowledgementReceiptV0(
            correlationID: acknowledgementReply == .mismatched ? UUID() : command.commandID,
            transitionCommandID: command.transitionCommandID,
            leaseID: command.leaseID,
            interactiveSessionID: command.interactiveSessionID,
            surfaceID: command.surfaceID,
            surfaceRevision: command.surfaceRevision,
            coordinateRevision: command.coordinateRevision,
            readyMediaSequence: command.readyMediaSequence,
            inputResumed: true
        )
    }

    func terminateSurfaceFailure(
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) async throws -> Bool {
        terminations.append((interactiveSessionID, reason))
        return terminationResult
    }

    func counts() -> (prepare: Int, acknowledge: Int, terminate: Int) {
        (prepareCommands.count, acknowledgementCommands.count, terminations.count)
    }

    func lastTermination() -> (UUID, InteractiveSessionEndReason)? {
        terminations.last
    }
}

private func surfaceDescriptor(
    surfaceID: UUID,
    revision: UInt64,
    coordinateRevision: UInt64,
    interactionClasses: Set<SurfaceInteractionClass> = [.view, .pointer, .keyboard]
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: surfaceSessionID,
        authorizationEpoch: .init(rawValue: 3),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: revision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: interactionClasses,
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func initialSurfaceLease() throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: UUID(uuidString: "01996900-0000-7000-8000-000000000001")!,
        hostID: surfaceHostID,
        deviceID: surfaceDeviceID,
        interactiveSessionID: surfaceSessionID,
        authorizationEpoch: .init(rawValue: 3),
        selectedDisplayID: surfaceDisplayID,
        surfaceID: desktopSurfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer, .keyboard],
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000_000_000,
        expiresAtMonotonicNanoseconds: 8_000_000_000
    )
}

private func surfaceCoordinator(
    route: SurfaceRuntimeRouteProbe
) throws -> InteractiveSurfaceRuntimeCoordinatorV0 {
    let descriptor = try surfaceDescriptor(
        surfaceID: desktopSurfaceID,
        revision: 1,
        coordinateRevision: 1
    )
    return try InteractiveSurfaceRuntimeCoordinatorV0(
        surfaceAuthority: AdaptiveSurfaceAuthority(
            desktop: descriptor,
            monotonicNowMilliseconds: 1_000
        ),
        currentLease: initialSurfaceLease(),
        sessionDeadlineMonotonicNanoseconds: 12_000_000_000,
        runtime: route
    )
}

private func targetSurface(
    interactionClasses: Set<SurfaceInteractionClass> = [.view, .pointer]
) throws -> AdaptiveSurfaceDescriptor {
    try surfaceDescriptor(
        surfaceID: targetSurfaceID,
        revision: 2,
        coordinateRevision: 2,
        interactionClasses: interactionClasses
    )
}

private func targetFence() -> SurfaceInputFence {
    SurfaceInputFence(
        interactiveSessionID: surfaceSessionID,
        authorizationEpoch: .init(rawValue: 3),
        surfaceID: targetSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2)
    )
}

@Test func surfaceReplacementCommitsExactLeaseAndResumesOnlyAfterRuntimeAck() async throws {
    let route = SurfaceRuntimeRouteProbe()
    let coordinator = try surfaceCoordinator(route: route)
    let target = try targetSurface()

    let prepared = try await coordinator.prepareSelection(
        target: target,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        monotonicNowMilliseconds: 2_000,
        monotonicNowNanoseconds: 2_000_000_000
    )
    let replay = try await coordinator.prepareSelection(
        target: target,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        monotonicNowMilliseconds: 2_000,
        monotonicNowNanoseconds: 2_000_000_000
    )

    #expect(replay == prepared)
    #expect(prepared.receipt.mediaSequenceBeforeTransition == 4)
    #expect(prepared.command.replacement.surfaceID == targetSurfaceID)
    #expect(prepared.command.replacement.surfaceRevision.rawValue == 2)
    #expect(prepared.command.replacement.coordinateRevision.rawValue == 2)
    #expect(prepared.command.replacement.renewalCounter == 1)
    #expect(prepared.command.replacement.issuedAtMonotonicNanoseconds == 2_000_000_000)
    #expect(prepared.command.replacement.expiresAtMonotonicNanoseconds == 12_000_000_000)
    #expect(prepared.command.replacement.allowedInteractionClasses == [.pointer, .view])
    #expect(prepared.effects == [
        .pauseInput, .releaseAllInput, .applyCaptureSource,
        .emitVideoDiscontinuity, .publishDescriptor, .requestCleanKeyframe,
    ])
    #expect(await coordinator.state() == .awaitingAcknowledgement(
        commandID: prepared.command.commandID
    ))
    #expect(await route.counts().prepare == 1)

    let acknowledged = try await coordinator.acknowledge(
        fence: targetFence(),
        readyMediaSequence: 7,
        monotonicNowMilliseconds: 2_100,
        monotonicNowNanoseconds: 2_100_000_000
    )
    let acknowledgementReplay = try await coordinator.acknowledge(
        fence: targetFence(),
        readyMediaSequence: 7,
        monotonicNowMilliseconds: 2_100,
        monotonicNowNanoseconds: 2_100_000_000
    )

    #expect(acknowledgementReplay == acknowledged)
    #expect(acknowledged.effects == [.resumeInput])
    #expect(acknowledged.command.transitionCommandID == prepared.command.commandID)
    #expect(acknowledged.command.leaseID == prepared.command.replacement.leaseID)
    #expect(acknowledged.command.readyMediaSequence == 7)
    #expect(await coordinator.state() == .active)
    #expect(await route.counts().acknowledge == 1)
    #expect(await route.counts().terminate == 0)
}

@Test func staleSurfaceExpectationIsRejectedBeforeRuntimeIPC() async throws {
    let route = SurfaceRuntimeRouteProbe()
    let coordinator = try surfaceCoordinator(route: route)

    await #expect(throws: AdaptiveSurfaceError.staleSurface) {
        _ = try await coordinator.prepareSelection(
            target: targetSurface(),
            expectedSurfaceRevision: .init(rawValue: 9),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            monotonicNowMilliseconds: 2_000,
            monotonicNowNanoseconds: 2_000_000_000
        )
    }

    #expect(await coordinator.state() == .active)
    #expect(await route.counts().prepare == 0)
    #expect(await route.counts().terminate == 0)
}

@Test func mismatchedRuntimePreparationReceiptTerminatesSession() async throws {
    let route = SurfaceRuntimeRouteProbe(prepareReply: .mismatched)
    let coordinator = try surfaceCoordinator(route: route)

    await #expect(
        throws: InteractiveSurfaceRuntimeCoordinatorErrorV0.runtimeReceiptMismatch
    ) {
        _ = try await coordinator.prepareSelection(
            target: targetSurface(),
            expectedSurfaceRevision: .init(rawValue: 1),
            expectedCoordinateSpaceRevision: .init(rawValue: 1),
            monotonicNowMilliseconds: 2_000,
            monotonicNowNanoseconds: 2_000_000_000
        )
    }

    #expect(await coordinator.state() == .ended)
    #expect(await route.counts().prepare == 1)
    #expect(await route.counts().terminate == 1)
    let termination = await route.lastTermination()
    #expect(termination?.0 == surfaceSessionID)
    #expect(termination?.1 == .protocolViolation)
}

@Test func acknowledgementFailureWithoutTeardownProofRequiresSafetyRecovery() async throws {
    let route = SurfaceRuntimeRouteProbe(
        acknowledgementReply: .rejected,
        terminationResult: false
    )
    let coordinator = try surfaceCoordinator(route: route)
    _ = try await coordinator.prepareSelection(
        target: targetSurface(),
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        monotonicNowMilliseconds: 2_000,
        monotonicNowNanoseconds: 2_000_000_000
    )

    await #expect(
        throws: InteractiveSurfaceRuntimeCoordinatorErrorV0.safetyRecoveryRequired
    ) {
        _ = try await coordinator.acknowledge(
            fence: targetFence(),
            readyMediaSequence: 7,
            monotonicNowMilliseconds: 2_100,
            monotonicNowNanoseconds: 2_100_000_000
        )
    }

    #expect(await coordinator.state() == .safetyRecoveryRequired)
    #expect(await route.counts().acknowledge == 1)
    #expect(await route.counts().terminate == 1)
}
