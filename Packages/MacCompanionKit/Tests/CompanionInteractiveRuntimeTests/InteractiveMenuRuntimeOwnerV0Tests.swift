import CompanionDomain
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private enum RuntimeEffectEvent: Hashable, Sendable {
    case show
    case start
    case prepare
    case release
    case stop
    case blank
    case clear
}

private enum RuntimeProbeError: Error {
    case injected(RuntimeEffectEvent)
}

private actor RuntimeEffectsProbe:
    InteractiveRuntimeIndicatorControllingV0,
    InteractiveRuntimeCaptureControllingV0,
    InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeFrameControllingV0
{
    private var recorded: [RuntimeEffectEvent] = []
    private var captureCommands: [InteractiveRuntimeInstallCommandV0] = []
    private var failOnce: Set<RuntimeEffectEvent>
    private let readyClasses: Set<SurfaceInteractionClass>

    init(
        readyClasses: Set<SurfaceInteractionClass> = [.view, .pointer],
        failOnce: Set<RuntimeEffectEvent> = []
    ) {
        self.readyClasses = readyClasses
        self.failOnce = failOnce
    }

    func events() -> [RuntimeEffectEvent] { recorded }
    func startedCaptureCommands() -> [InteractiveRuntimeInstallCommandV0] {
        captureCommands
    }

    func showInteractiveIndicator(
        deviceDisplayName: DeviceDisplayName,
        interactiveSessionID: UUID
    ) async throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        try await apply(.show)
        return try InteractiveRuntimeIndicatorSnapshotV0(
            menuAppGeneration: UUID(
                uuidString: "018f7000-0000-7000-8000-000000000001"
            )!,
            menuAppRevision: 7
        )
    }

    func clearInteractiveIndicator() async throws {
        try await apply(.clear)
    }

    func startInteractiveCapture(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        captureCommands.append(command)
        try await apply(.start)
        return readyClasses
    }

    func stopInteractiveCapture() async throws {
        try await apply(.stop)
    }

    func prepareInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        try await apply(.prepare)
        return readyClasses
    }

    func releaseAllInteractiveInput() async throws {
        try await apply(.release)
    }

    func blankLastInteractiveFrame() async throws {
        try await apply(.blank)
    }

    private func apply(_ event: RuntimeEffectEvent) async throws {
        recorded.append(event)
        await Task.yield()
        if failOnce.remove(event) != nil {
            throw RuntimeProbeError.injected(event)
        }
    }
}

private final class RuntimeInputPosterProbe:
    InteractiveRuntimeInputPostingV0, @unchecked Sendable
{
    private let lock = NSLock()
    private var posted: [InteractiveInputEnvelope] = []
    private var shouldFail = false

    func setShouldFail(_ value: Bool) {
        lock.withLock { shouldFail = value }
    }

    func postedInputs() -> [InteractiveInputEnvelope] {
        lock.withLock { posted }
    }

    func postInteractiveInput(_ envelope: InteractiveInputEnvelope) throws {
        try lock.withLock {
            if shouldFail { throw RuntimeProbeError.injected(.start) }
            posted.append(envelope)
        }
    }
}

private final class RuntimeMediaQueueProbe:
    InteractiveRuntimeMediaEnqueuingV0, @unchecked Sendable
{
    private let lock = NSLock()
    private var acceptedHeaders: [MediaRecordHeader] = []
    private var accepts = true

    func setAccepts(_ value: Bool) {
        lock.withLock { accepts = value }
    }

    func headers() -> [MediaRecordHeader] {
        lock.withLock { acceptedHeaders }
    }

    func clear() {
        lock.withLock { acceptedHeaders.removeAll() }
    }

    func enqueueInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) -> Bool {
        lock.withLock {
            guard accepts else { return false }
            acceptedHeaders.append(header)
            return true
        }
    }
}

private let runtimeHostID = UUID(
    uuidString: "018f1000-0000-7000-8000-000000000001"
)!
private let runtimeDeviceID = UUID(
    uuidString: "018f2000-0000-7000-8000-000000000001"
)!
private let runtimeSessionID = UUID(
    uuidString: "018f6000-0000-7000-8000-000000000001"
)!
private let runtimeDisplayID = UUID(
    uuidString: "018f6700-0000-7000-8000-000000000001"
)!
private let runtimeSurfaceID = UUID(
    uuidString: "018f6100-0000-7000-8000-000000000001"
)!

private func runtimeOwner(
    probe: RuntimeEffectsProbe,
    poster: RuntimeInputPosterProbe = .init(),
    mediaQueue: RuntimeMediaQueueProbe = .init()
) -> InteractiveMenuRuntimeOwnerV0 {
    InteractiveMenuRuntimeOwnerV0(
        indicator: probe,
        capture: probe,
        input: probe,
        frame: probe,
        inputPoster: poster,
        mediaQueue: mediaQueue
    )
}

private func runtimeFence(
    lease: InteractiveExecutionLease,
    leaseID: UUID? = nil
) -> InteractiveCommandFence {
    InteractiveCommandFence(
        leaseID: leaseID ?? lease.leaseID,
        hostID: lease.hostID,
        deviceID: lease.deviceID,
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        selectedDisplayID: lease.selectedDisplayID,
        surfaceID: lease.surfaceID,
        surfaceRevision: lease.surfaceRevision,
        coordinateRevision: lease.coordinateRevision
    )
}

private func runtimeInput(
    lease: InteractiveExecutionLease,
    payload: InteractiveInputPayload = .pointerMove(x: 1, y: 1)
) throws -> InteractiveInputEnvelope {
    try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(lease.interactiveSessionID),
        authorizationEpoch: lease.authorizationEpoch,
        sequence: 1,
        clientMonotonicMilliseconds: 1,
        surfaceID: WireUUID(lease.surfaceID),
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        input: payload
    )
}

private func runtimeMediaHeader(
    lease: InteractiveExecutionLease,
    sequence: UInt64,
    payloadLength: UInt32 = 6,
    type: MediaRecordType = .videoAccessUnit,
    cleanKeyframe: Bool = false
) throws -> MediaRecordHeader {
    try MediaRecordHeader(
        type: type,
        flags: cleanKeyframe ? [.cleanKeyframe] : [],
        payloadLength: payloadLength,
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        surfaceID: lease.surfaceID,
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        mediaSequence: sequence,
        presentationTimeNanoseconds: sequence * 1_000,
        encodedWidth: type == .discontinuity || type == .end ? 0 : 100,
        encodedHeight: type == .discontinuity || type == .end ? 0 : 100
    )
}

private func runtimeLease(
    leaseID: UUID = UUID(),
    allowedClasses: Set<SurfaceInteractionClass> = [.view, .pointer],
    surfaceID: UUID = runtimeSurfaceID,
    surfaceRevision: UInt64 = 5,
    coordinateRevision: UInt64 = 8,
    renewalCounter: UInt64 = 0,
    issuedAt: UInt64 = 1_000,
    expiresAt: UInt64 = 5_000
) throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: leaseID,
        hostID: runtimeHostID,
        deviceID: runtimeDeviceID,
        interactiveSessionID: runtimeSessionID,
        authorizationEpoch: .init(rawValue: 3),
        selectedDisplayID: runtimeDisplayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateRevision: .init(rawValue: coordinateRevision),
        allowedInteractionClasses: allowedClasses,
        renewalCounter: renewalCounter,
        issuedAtMonotonicNanoseconds: issuedAt,
        expiresAtMonotonicNanoseconds: expiresAt
    )
}

private func runtimeSurfaceDescriptor(
    lease: InteractiveExecutionLease,
    kind: InteractiveSurfaceKind = .desktop
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        surfaceID: lease.surfaceID,
        kind: kind,
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(lease.allowedInteractionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func runtimeSurfaceTransition(
    current: InteractiveExecutionLease,
    replacement: InteractiveExecutionLease,
    commandID: UUID = UUID()
) throws -> InteractiveRuntimeSurfaceTransitionCommandV0 {
    try InteractiveRuntimeSurfaceTransitionCommandV0(
        commandID: commandID,
        previousLeaseID: current.leaseID,
        replacement: replacement,
        descriptor: runtimeSurfaceDescriptor(lease: replacement)
    )
}

private let runtimeDecoderConfiguration = Data([
    1, 66, 0, 30, 0xff, 0xe1,
    0, 4, 0x67, 66, 0, 30,
    1, 0, 2, 0x68, 0,
])

private func installCommand(
    commandID: UUID = UUID(),
    lease: InteractiveExecutionLease? = nil
) throws -> InteractiveRuntimeInstallCommandV0 {
    let lease = try lease ?? runtimeLease()
    return try InteractiveRuntimeInstallCommandV0(
        commandID: commandID,
        lease: lease,
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        surfaceDescriptor: runtimeSurfaceDescriptor(lease: lease),
        sessionDeadlineMonotonicNanoseconds: 10_000
    )
}

private func revokeCommand(
    commandID: UUID = UUID(),
    lease: InteractiveExecutionLease
) throws -> InteractiveRuntimeRevokeCommandV0 {
    try InteractiveRuntimeRevokeCommandV0(
        commandID: commandID,
        leaseID: lease.leaseID,
        interactiveSessionID: lease.interactiveSessionID,
        reason: .localSuspension
    )
}

@discardableResult
private func installAndActivateInitial(
    _ owner: InteractiveMenuRuntimeOwnerV0,
    command: InteractiveRuntimeInstallCommandV0,
    now: UInt64 = 2_000
) async throws -> InteractiveRuntimeInstallReceiptV0 {
    let receipt = try await owner.install(
        command,
        nowMonotonicNanoseconds: now
    )
    let configuration = try runtimeMediaHeader(
        lease: command.lease,
        sequence: 1,
        payloadLength: UInt32(runtimeDecoderConfiguration.count),
        type: .decoderConfiguration
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: command.lease),
            header: configuration,
            payload: runtimeDecoderConfiguration
        ),
        nowMonotonicNanoseconds: now + 10
    )
    let clean = try runtimeMediaHeader(
        lease: command.lease,
        sequence: 2,
        type: .videoAccessUnit,
        cleanKeyframe: true
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: command.lease),
            header: clean,
            payload: Data([0, 0, 0, 2, 0x65, 0])
        ),
        nowMonotonicNanoseconds: now + 20
    )
    let acknowledgement = try
        InteractiveRuntimeSurfaceAcknowledgementCommandV0(
            commandID: UUID(),
            transitionCommandID: command.commandID,
            leaseID: command.lease.leaseID,
            interactiveSessionID: command.lease.interactiveSessionID,
            surfaceID: command.lease.surfaceID,
            surfaceRevision: command.lease.surfaceRevision,
            coordinateRevision: command.lease.coordinateRevision,
            readyMediaSequence: 2
        )
    _ = try await owner.acknowledgeSurface(
        acknowledgement,
        nowMonotonicNanoseconds: now + 30
    )
    return receipt
}

@Test func installIsVisibleBeforeCaptureAndDuplicateIsIdempotent() async throws {
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let command = try installCommand()

    let first = try await owner.install(
        command,
        nowMonotonicNanoseconds: 2_000
    )
    let duplicate = try await owner.install(
        command,
        nowMonotonicNanoseconds: 2_000
    )

    #expect(first == duplicate)
    #expect(first.indicatorVisible)
    #expect(await probe.events() == [.show, .start])
    #expect(await probe.startedCaptureCommands() == [command])
    #expect(await owner.state() == .active(
        interactiveSessionID: runtimeSessionID,
        leaseID: command.lease.leaseID
    ))
    #expect(await owner.surfaceAdmissionState() == .requiresConfiguration(
        transitionCommandID: command.commandID
    ))
}

@Test func installRejectsNonDesktopDescriptorBeforePlatformEffects()
    async throws
{
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        surfaceID: lease.surfaceID,
        kind: .application,
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        applicationToken: UUID(),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(lease.allowedInteractionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
    let command = try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(),
        lease: lease,
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        surfaceDescriptor: descriptor,
        sessionDeadlineMonotonicNanoseconds: 10_000
    )

    await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
        try await owner.install(command, nowMonotonicNanoseconds: 2_000)
    }
    #expect(await probe.events().isEmpty)
    #expect(await probe.startedCaptureCommands().isEmpty)
    #expect(await owner.state() == .idle)
}

@Test func installRejectsExpiredDesktopDescriptorBeforePlatformEffects()
    async throws
{
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease(
        issuedAt: 1_000_000,
        expiresAt: 10_000_000
    )
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        surfaceID: lease.surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(lease.allowedInteractionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 2
    )
    let command = try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(),
        lease: lease,
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        surfaceDescriptor: descriptor,
        sessionDeadlineMonotonicNanoseconds: 20_000_000
    )

    await #expect(throws: InteractiveMenuRuntimeErrorV0.invalidTime) {
        try await owner.install(
            command,
            nowMonotonicNanoseconds: 3_000_000
        )
    }
    #expect(await probe.events().isEmpty)
    #expect(await probe.startedCaptureCommands().isEmpty)
    #expect(await owner.state() == .idle)
}

@Test func failedInstallAttemptsEverySafetyEffectBeforeReturning() async throws {
    let probe = RuntimeEffectsProbe(readyClasses: [.view])
    let owner = runtimeOwner(probe: probe)

    await #expect(throws: InteractiveMenuRuntimeErrorV0.installFailed) {
        try await owner.install(
            installCommand(
                lease: runtimeLease(allowedClasses: [.view, .pointer])
            ),
            nowMonotonicNanoseconds: 2_000
        )
    }
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank, .clear,
    ])
    #expect(await owner.state() == .idle)
}

@Test func revokeCompletesInSafetyOrderAndExactReplayHasNoEffects() async throws {
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease()
    let install = try installCommand(lease: lease)
    _ = try await owner.install(install, nowMonotonicNanoseconds: 2_000)
    let revoke = try revokeCommand(lease: lease)

    let first = try await owner.revoke(revoke)
    let duplicate = try await owner.revoke(revoke)

    #expect(first == duplicate)
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank, .clear,
    ])
    #expect(await owner.state() == .idle)
}

@Test func incompleteCleanupRetriesOnlyTheFailedSafetyEffect() async throws {
    let probe = RuntimeEffectsProbe(failOnce: [.blank])
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease()
    _ = try await owner.install(
        installCommand(lease: lease),
        nowMonotonicNanoseconds: 2_000
    )
    let revoke = try revokeCommand(lease: lease)

    await #expect(
        throws: InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
    ) {
        try await owner.revoke(revoke)
    }
    #expect(await owner.state() == .safetyRecoveryRequired(
        interactiveSessionID: runtimeSessionID,
        leaseID: lease.leaseID
    ))

    _ = try await owner.revoke(revoke)
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank, .blank, .clear,
    ])
    #expect(await owner.state() == .idle)
}

@Test func uncertainCaptureStopKeepsIndicatorVisibleUntilRetrySucceeds()
    async throws
{
    let probe = RuntimeEffectsProbe(failOnce: [.stop])
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease()
    _ = try await owner.install(
        installCommand(lease: lease),
        nowMonotonicNanoseconds: 2_000
    )
    let revoke = try revokeCommand(lease: lease)

    await #expect(
        throws: InteractiveMenuRuntimeErrorV0.safetyRecoveryRequired
    ) {
        try await owner.revoke(revoke)
    }
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank,
    ])

    _ = try await owner.revoke(revoke)
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank, .stop, .clear,
    ])
    #expect(await owner.state() == .idle)
}

@Test func renewalPreservesAuthorityAndCannotOutliveSession() async throws {
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let current = try runtimeLease()
    let initialInstall = try installCommand(lease: current)
    _ = try await installAndActivateInitial(
        owner,
        command: initialInstall
    )
    let replacement = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 1,
        issuedAt: 4_000,
        expiresAt: 8_000
    )
    try await owner.renew(
        InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: replacement
        ),
        nowMonotonicNanoseconds: 4_000
    )
    #expect(await owner.state() == .active(
        interactiveSessionID: runtimeSessionID,
        leaseID: replacement.leaseID
    ))
    #expect(await probe.events() == [.show, .start])

    let tooLate = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 2,
        issuedAt: 7_000,
        expiresAt: 10_001
    )
    await #expect(throws: InteractiveMenuRuntimeErrorV0.invalidTime) {
        try await owner.renew(
            InteractiveRuntimeLeaseRenewalV0(
                commandID: UUID(),
                previousLeaseID: replacement.leaseID,
                replacement: tooLate
            ),
            nowMonotonicNanoseconds: 7_000
        )
    }
}

@Test func surfaceTransitionPausesInputUntilOrderedMediaAndExactAck()
    async throws
{
    let effects = RuntimeEffectsProbe(
        readyClasses: [.view, .pointer, .keyboard]
    )
    let poster = RuntimeInputPosterProbe()
    let queue = RuntimeMediaQueueProbe()
    let owner = runtimeOwner(
        probe: effects,
        poster: poster,
        mediaQueue: queue
    )
    let current = try runtimeLease(
        allowedClasses: [.view, .pointer, .keyboard]
    )
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: current)
    )
    let replacement = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer, .keyboard],
        surfaceID: UUID(),
        surfaceRevision: 6,
        coordinateRevision: 9,
        renewalCounter: 1,
        issuedAt: 3_000,
        expiresAt: 7_000
    )
    let transition = try runtimeSurfaceTransition(
        current: current,
        replacement: replacement
    )

    let prepared = try await owner.prepareSurfaceTransition(
        transition,
        nowMonotonicNanoseconds: 4_000
    )
    let replayedPrepared = try await owner.prepareSurfaceTransition(
        transition,
        nowMonotonicNanoseconds: 4_100
    )
    #expect(prepared == replayedPrepared)
    #expect(prepared.mediaSequenceBeforeTransition == 2)
    #expect(await owner.surfaceAdmissionState()
        == .requiresDiscontinuity(
            transitionCommandID: transition.commandID
        ))
    await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: replacement),
                envelope: runtimeInput(lease: replacement)
            ),
            nowMonotonicNanoseconds: 4_100
        )
    }

    let discontinuity = try runtimeMediaHeader(
        lease: replacement,
        sequence: 3,
        payloadLength: 0,
        type: .discontinuity
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            header: discontinuity,
            payload: Data()
        ),
        nowMonotonicNanoseconds: 4_200
    )
    #expect(await owner.surfaceAdmissionState()
        == .requiresConfiguration(
            transitionCommandID: transition.commandID
        ))

    let configuration = try runtimeMediaHeader(
        lease: replacement,
        sequence: 4,
        payloadLength: UInt32(runtimeDecoderConfiguration.count),
        type: .decoderConfiguration
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            header: configuration,
            payload: runtimeDecoderConfiguration
        ),
        nowMonotonicNanoseconds: 4_300
    )
    let clean = try runtimeMediaHeader(
        lease: replacement,
        sequence: 5,
        type: .videoAccessUnit,
        cleanKeyframe: true
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            header: clean,
            payload: Data([0, 0, 0, 2, 0x65, 0])
        ),
        nowMonotonicNanoseconds: 4_400
    )
    #expect(await owner.surfaceAdmissionState()
        == .awaitingAcknowledgement(
            transitionCommandID: transition.commandID,
            readyMediaSequence: 5
        ))

    let acknowledgement = try
        InteractiveRuntimeSurfaceAcknowledgementCommandV0(
            commandID: UUID(),
            transitionCommandID: transition.commandID,
            leaseID: replacement.leaseID,
            interactiveSessionID: replacement.interactiveSessionID,
            surfaceID: replacement.surfaceID,
            surfaceRevision: replacement.surfaceRevision,
            coordinateRevision: replacement.coordinateRevision,
            readyMediaSequence: 5
        )
    let acknowledged = try await owner.acknowledgeSurface(
        acknowledgement,
        nowMonotonicNanoseconds: 4_500
    )
    let replayedAcknowledgement = try await owner.acknowledgeSurface(
        acknowledgement,
        nowMonotonicNanoseconds: 4_600
    )
    #expect(acknowledged == replayedAcknowledgement)
    #expect(await owner.surfaceAdmissionState() == .ready)

    let input = try runtimeInput(lease: replacement)
    try await owner.postInput(
        InteractiveRuntimeInputActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            envelope: input
        ),
        nowMonotonicNanoseconds: 4_700
    )
    #expect(poster.postedInputs() == [input])
    #expect(queue.headers().map(\.type) == [
        .decoderConfiguration, .videoAccessUnit,
        .discontinuity, .decoderConfiguration, .videoAccessUnit,
    ])
    #expect(await effects.events() == [
        .show, .start, .release, .prepare,
    ])
}

@Test func surfaceTransitionMediaOrderFailureTerminatesRuntime()
    async throws
{
    let effects = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: effects)
    let current = try runtimeLease()
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: current)
    )
    let replacement = try runtimeLease(
        leaseID: UUID(),
        surfaceID: UUID(),
        surfaceRevision: 6,
        coordinateRevision: 9,
        renewalCounter: 1,
        issuedAt: 3_000,
        expiresAt: 7_000
    )
    let transition = try runtimeSurfaceTransition(
        current: current,
        replacement: replacement
    )
    _ = try await owner.prepareSurfaceTransition(
        transition,
        nowMonotonicNanoseconds: 4_000
    )

    let configuration = try runtimeMediaHeader(
        lease: replacement,
        sequence: 3,
        payloadLength: UInt32(runtimeDecoderConfiguration.count),
        type: .decoderConfiguration
    )
    await #expect(
        throws:
            InteractiveMenuRuntimeErrorV0
                .invalidSurfaceMediaTransition
    ) {
        try await owner.publishMedia(
            InteractiveRuntimeMediaActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: replacement),
                header: configuration,
                payload: runtimeDecoderConfiguration
            ),
            nowMonotonicNanoseconds: 4_100
        )
    }
    #expect(await owner.state() == .idle)
    let events = await effects.events()
    #expect(events == [
        .show, .start, .release, .prepare, .stop, .blank, .clear,
    ])
}

@Test func surfacePreparationFailureRunsFullCleanupWithoutDoubleRelease()
    async throws
{
    let effects = RuntimeEffectsProbe(failOnce: [.prepare])
    let owner = runtimeOwner(probe: effects)
    let current = try runtimeLease()
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: current)
    )
    let replacement = try runtimeLease(
        leaseID: UUID(),
        surfaceID: UUID(),
        surfaceRevision: 6,
        coordinateRevision: 9,
        renewalCounter: 1,
        issuedAt: 3_000,
        expiresAt: 7_000
    )
    await #expect(
        throws: InteractiveMenuRuntimeErrorV0.surfaceTransitionFailed
    ) {
        try await owner.prepareSurfaceTransition(
            runtimeSurfaceTransition(
                current: current,
                replacement: replacement
            ),
            nowMonotonicNanoseconds: 4_000
        )
    }
    #expect(await owner.state() == .idle)
    #expect(await effects.events() == [
        .show, .start, .release, .prepare, .stop, .blank, .clear,
    ])
}

@Test func installAndQueuedRevokeNeverOverlapPlatformEffects() async throws {
    let probe = RuntimeEffectsProbe()
    let owner = runtimeOwner(probe: probe)
    let lease = try runtimeLease()
    let install = try installCommand(lease: lease)
    let revoke = try revokeCommand(lease: lease)

    async let installed = owner.install(
        install,
        nowMonotonicNanoseconds: 2_000
    )
    await Task.yield()
    async let revoked = owner.revoke(revoke)
    _ = try await (installed, revoked)

    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank, .clear,
    ])
    #expect(await owner.state() == .idle)
}

@Test func leaseDeadlineAndAgentInvalidationTerminateWithoutAcknowledgement() async throws {
    let deadlineProbe = RuntimeEffectsProbe()
    let deadlineOwner = runtimeOwner(probe: deadlineProbe)
    let firstLease = try runtimeLease()
    _ = try await deadlineOwner.install(
        installCommand(lease: firstLease),
        nowMonotonicNanoseconds: 2_000
    )
    #expect(
        await deadlineOwner.nextLeaseDeadlineMonotonicNanoseconds() == 5_000
    )
    #expect(try await !deadlineOwner.expireLeaseIfRequired(
        nowMonotonicNanoseconds: 4_999
    ))
    #expect(try await deadlineOwner.expireLeaseIfRequired(
        nowMonotonicNanoseconds: 5_000
    ))
    #expect(await deadlineOwner.state() == .idle)

    let invalidationProbe = RuntimeEffectsProbe()
    let invalidationOwner = runtimeOwner(probe: invalidationProbe)
    _ = try await invalidationOwner.install(
        installCommand(),
        nowMonotonicNanoseconds: 2_000
    )
    try await invalidationOwner.invalidateAgentAuthority()
    #expect(await invalidationOwner.state() == .idle)
    #expect(await invalidationProbe.events() == [
        .show, .start, .release, .stop, .blank, .clear,
    ])
}

@Test func inputIsLeaseFencedAndPostedInsideTheSerializedOwner() async throws {
    let effects = RuntimeEffectsProbe(
        readyClasses: [.view, .pointer, .keyboard]
    )
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let lease = try runtimeLease(
        allowedClasses: [.view, .pointer, .keyboard]
    )
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: lease)
    )
    let envelope = try runtimeInput(lease: lease)
    let action = try InteractiveRuntimeInputActionV0(
        commandID: UUID(),
        fence: runtimeFence(lease: lease),
        envelope: envelope
    )
    try await owner.postInput(action, nowMonotonicNanoseconds: 2_100)
    try await owner.postInput(action, nowMonotonicNanoseconds: 2_150)
    #expect(poster.postedInputs() == [envelope])

    let staleAction = try InteractiveRuntimeInputActionV0(
        commandID: UUID(),
        fence: runtimeFence(lease: lease, leaseID: UUID()),
        envelope: envelope
    )
    await #expect(throws: InteractiveLeaseError.staleLease) {
        try await owner.postInput(
            staleAction,
            nowMonotonicNanoseconds: 2_200
        )
    }
    #expect(poster.postedInputs() == [envelope])
}

@Test func leaseClassesAndPlatformFailureDenyInputWithoutFalseSuccess() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer])
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let lease = try runtimeLease(allowedClasses: [.view, .pointer])
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: lease)
    )
    let keyboard = try runtimeInput(
        lease: lease,
        payload: .physicalKey(
            usage: 0x04,
            transition: .down,
            modifiers: []
        )
    )
    await #expect(
        throws: InteractiveMenuRuntimeErrorV0.interactionClassDenied
    ) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: lease),
                envelope: keyboard
            ),
            nowMonotonicNanoseconds: 2_100
        )
    }

    poster.setShouldFail(true)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.platformActionFailed) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: lease),
                envelope: runtimeInput(lease: lease)
            ),
            nowMonotonicNanoseconds: 2_200
        )
    }
    #expect(poster.postedInputs().isEmpty)
}

@Test func renewalAndRevokeFenceInputWithoutATimeOfCheckGap() async throws {
    let effects = RuntimeEffectsProbe()
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let current = try runtimeLease()
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: current)
    )
    let replacement = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 1,
        issuedAt: 4_000,
        expiresAt: 8_000
    )
    try await owner.renew(
        InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: replacement
        ),
        nowMonotonicNanoseconds: 4_000
    )

    await #expect(throws: InteractiveLeaseError.staleLease) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: current),
                envelope: runtimeInput(lease: current)
            ),
            nowMonotonicNanoseconds: 4_100
        )
    }
    let currentEnvelope = try runtimeInput(lease: replacement)
    try await owner.postInput(
        InteractiveRuntimeInputActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            envelope: currentEnvelope
        ),
        nowMonotonicNanoseconds: 4_200
    )
    _ = try await owner.revoke(revokeCommand(lease: replacement))
    await #expect(throws: InteractiveMenuRuntimeErrorV0.noActiveSession) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: replacement),
                envelope: currentEnvelope
            ),
            nowMonotonicNanoseconds: 4_300
        )
    }
    #expect(poster.postedInputs() == [currentEnvelope])
}

@Test func mediaQueueAdmissionOwnsSequenceAcrossLeaseRenewal() async throws {
    let effects = RuntimeEffectsProbe()
    let queue = RuntimeMediaQueueProbe()
    let owner = runtimeOwner(probe: effects, mediaQueue: queue)
    let current = try runtimeLease()
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: current)
    )
    queue.clear()
    let first = try runtimeMediaHeader(lease: current, sequence: 3)
    let firstAction = try InteractiveRuntimeMediaActionV0(
        commandID: UUID(),
        fence: runtimeFence(lease: current),
        header: first,
        payload: Data([0, 0, 0, 2, 0x41, 0])
    )
    try await owner.publishMedia(
        firstAction,
        nowMonotonicNanoseconds: 2_100
    )
    try await owner.publishMedia(
        firstAction,
        nowMonotonicNanoseconds: 2_150
    )
    await #expect(
        throws: InteractiveMenuRuntimeErrorV0.mediaSequenceMismatch(
            expected: 4,
            actual: 3
        )
    ) {
        try await owner.publishMedia(
            InteractiveRuntimeMediaActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: current),
                header: first,
                payload: Data([0, 0, 0, 2, 0x41, 0])
            ),
            nowMonotonicNanoseconds: 2_200
        )
    }

    let replacement = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 1,
        issuedAt: 4_000,
        expiresAt: 8_000
    )
    try await owner.renew(
        InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: replacement
        ),
        nowMonotonicNanoseconds: 4_000
    )
    let second = try runtimeMediaHeader(lease: replacement, sequence: 4)
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: replacement),
            header: second,
            payload: Data([0, 0, 0, 2, 0x41, 1])
        ),
        nowMonotonicNanoseconds: 4_100
    )
    #expect(queue.headers() == [first, second])
}

@Test func mediaQueueBackpressureTerminatesInsteadOfRetrying() async throws {
    let effects = RuntimeEffectsProbe()
    let queue = RuntimeMediaQueueProbe()
    let owner = runtimeOwner(probe: effects, mediaQueue: queue)
    let lease = try runtimeLease()
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: lease)
    )
    queue.clear()
    queue.setAccepts(false)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.mediaQueueRejected) {
        try await owner.publishMedia(
            InteractiveRuntimeMediaActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: lease),
                header: runtimeMediaHeader(lease: lease, sequence: 3),
                payload: Data([0, 0, 0, 2, 0x41, 0])
            ),
            nowMonotonicNanoseconds: 2_100
        )
    }
    #expect(queue.headers().isEmpty)
    #expect(await owner.state() == .idle)
    #expect(await effects.events() == [
        .show, .start, .release, .stop, .blank, .clear,
    ])
}

@Test func mediaActionRejectsMismatchedPayloadBeforeRuntimeMutation() throws {
    let lease = try runtimeLease()
    #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
        try InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: lease),
            header: runtimeMediaHeader(lease: lease, sequence: 1),
            payload: Data([0, 0, 0, 2, 0x41])
        )
    }
}
