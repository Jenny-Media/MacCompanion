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
    case activate
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
    private var renewalCommands: [InteractiveRuntimeLeaseRenewalV0] = []
    private var activationSequences: [UInt64] = []
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
    func activatedAfterSequences() -> [UInt64] { activationSequences }
    func startedCaptureCommands() -> [InteractiveRuntimeInstallCommandV0] {
        captureCommands
    }
    func adoptedRenewals() -> [InteractiveRuntimeLeaseRenewalV0] {
        renewalCommands
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

    func adoptInteractiveLeaseRenewal(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        renewalCommands.append(renewal)
    }

    func prepareInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        try await apply(.prepare)
        return readyClasses
    }

    func activatePreparedInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64
    ) async throws {
        activationSequences.append(mediaSequenceBeforeTransition)
        try await apply(.activate)
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

    func postInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        try lock.withLock {
            if shouldFail { throw RuntimeProbeError.injected(.start) }
            posted.append(envelope)
        }
    }
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        beforeDeadlineNanoseconds: UInt64) async throws {
        try await nativeAuthorization.perform(envelope, beforeDeadlineNanoseconds: beforeDeadlineNanoseconds) {
            try self.lock.withLock {
                if self.shouldFail { throw RuntimeProbeError.injected(.start) }
                self.posted.append(envelope)
            }
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
    payload: InteractiveInputPayload = .pointerMove(x: 1, y: 1),
    sequence: UInt64 = 1,
    focus: SurfaceFocus? = nil
) throws -> InteractiveInputEnvelope {
    try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(lease.interactiveSessionID),
        authorizationEpoch: lease.authorizationEpoch,
        sequence: sequence,
        clientMonotonicMilliseconds: 1,
        surfaceID: WireUUID(lease.surfaceID),
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        focusToken: focus.map { WireUUID($0.token) },
        focusRevision: focus?.revision,
        input: payload
    )
}

private func runtimeMediaHeader(
    lease: InteractiveExecutionLease,
    sequence: UInt64,
    payloadLength: UInt32 = 6,
    type: MediaRecordType = .videoAccessUnit,
    cleanKeyframe: Bool = false,
    encodedWidth: UInt16 = 100, encodedHeight: UInt16 = 100
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
        encodedWidth: type == .discontinuity || type == .end ? 0 : encodedWidth,
        encodedHeight: type == .discontinuity || type == .end ? 0 : encodedHeight
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
    kind: InteractiveSurfaceKind = .desktop,
    encodedWidth: UInt16 = 100, encodedHeight: UInt16 = 100,
    applicationToken: UUID? = nil, windowToken: UUID? = nil,
    rotation: SurfaceRotation = .degrees0
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
        applicationToken: applicationToken,
        windowToken: windowToken,
        encodedWidth: encodedWidth,
        encodedHeight: encodedHeight,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        rotation: rotation,
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
        type: .decoderConfiguration,
        encodedWidth: command.surfaceDescriptor.encodedWidth, encodedHeight: command.surfaceDescriptor.encodedHeight
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
        cleanKeyframe: true,
        encodedWidth: command.surfaceDescriptor.encodedWidth, encodedHeight: command.surfaceDescriptor.encodedHeight
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

@Test func inputEnvelopeDerivesFullFenceInsideActiveRuntimeOwner()
    async throws
{
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

    try await owner.postInputEnvelope(
        envelope,
        nowMonotonicNanoseconds: 2_040
    )
    #expect(poster.postedInputs() == [envelope])

    let stale = try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(UUID()),
        authorizationEpoch: lease.authorizationEpoch,
        sequence: 2,
        clientMonotonicMilliseconds: 2,
        surfaceID: WireUUID(lease.surfaceID),
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        input: .reset
    )
    await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
        try await owner.postInputEnvelope(
            stale,
            nowMonotonicNanoseconds: 2_050
        )
    }
    #expect(poster.postedInputs() == [envelope])
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

    #expect(try await owner.terminateSurfaceFailure(
        interactiveSessionID: UUID()
    ) == false)
    #expect(await probe.events() == [
        .show, .start, .release, .stop, .blank,
    ])

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
    let renewal = try InteractiveRuntimeLeaseRenewalV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement
    )
    try await owner.renew(
        renewal,
        nowMonotonicNanoseconds: 4_000
    )
    #expect(await owner.state() == .active(
        interactiveSessionID: runtimeSessionID,
        leaseID: replacement.leaseID
    ))
    #expect(await probe.events() == [.show, .start])
    #expect(await probe.adoptedRenewals() == [renewal])

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

@Test(arguments: [0, 1, 2, 3]) func surfaceTransitionPausesInputUntilOrderedMediaAndExactAck(lateResetAt: Int)
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
    if lateResetAt == 1 {
        // The primary selection overtook the input socket's old-fence reset.
        // Preparation already released input, so draining must post nothing.
        let reset = try runtimeInput(lease: current, payload: .reset)
        await #expect(throws: InteractiveMenuRuntimeErrorV0.invalidTime) {
            try await owner.postInputEnvelope(reset, nowMonotonicNanoseconds: 7_001)
        }
        await #expect(throws: InteractiveMenuRuntimeErrorV0.inputSequenceMismatch(expected: 1, actual: 2)) {
            try await owner.postInputEnvelope(runtimeInput(lease: current, payload: .reset, sequence: 2), nowMonotonicNanoseconds: 4_030)
        }
        await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
            try await owner.postInputEnvelope(runtimeInput(lease: current), nowMonotonicNanoseconds: 4_040)
        }
        try await owner.postInputEnvelope(reset, nowMonotonicNanoseconds: 4_050)
        #expect(poster.postedInputs().isEmpty)
        await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
            try await owner.postInputEnvelope(reset, nowMonotonicNanoseconds: 4_060)
        }
    }
    #expect(await effects.activatedAfterSequences() == [2])
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

    var inputLease = replacement
    if lateResetAt == 3 {
        inputLease = try runtimeLease(leaseID: UUID(), allowedClasses: [.view, .pointer, .keyboard],
            surfaceID: replacement.surfaceID, surfaceRevision: 6, coordinateRevision: 9,
            renewalCounter: 2, issuedAt: 4_600, expiresAt: 7_500)
        try await owner.renew(.init(commandID: UUID(), previousLeaseID: replacement.leaseID, replacement: inputLease),
            nowMonotonicNanoseconds: 4_620)
    }
    if lateResetAt >= 2 {
        try await owner.postInputEnvelope(runtimeInput(lease: current, payload: .reset), nowMonotonicNanoseconds: 4_650)
        #expect(poster.postedInputs().isEmpty)
    }
    let input = try runtimeInput(lease: inputLease, sequence: lateResetAt > 0 ? 2 : 1)
    try await owner.postInput(
        InteractiveRuntimeInputActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: inputLease),
            envelope: input
        ),
        nowMonotonicNanoseconds: 4_700
    )
    #expect(poster.postedInputs() == [input])
    await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
        try await owner.postInputEnvelope(runtimeInput(lease: current, payload: .reset, sequence: input.sequence + 1),
            nowMonotonicNanoseconds: 4_750)
    }
    #expect(queue.headers().map(\.type) == [
        .decoderConfiguration, .videoAccessUnit,
        .discontinuity, .decoderConfiguration, .videoAccessUnit,
    ])
    #expect(await effects.events() == [
        .show, .start, .release, .prepare, .activate,
    ])
}

@Test func focusChangePauseReleasesOnceAndFeedsOrdinaryTransition()
    async throws
{
    let effects = RuntimeEffectsProbe(
        readyClasses: [.view, .pointer, .keyboard]
    )
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let desktop = try runtimeLease(
        allowedClasses: [.view, .pointer, .keyboard]
    )
    _ = try await installAndActivateInitial(
        owner,
        command: installCommand(lease: desktop)
    )
    let current = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer, .keyboard],
        surfaceID: UUID(),
        surfaceRevision: 6,
        coordinateRevision: 9,
        renewalCounter: 1,
        issuedAt: 3_000,
        expiresAt: 7_000
    )
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 1_000,
            y: 1_000,
            width: 10_000,
            height: 5_000
        ),
        editable: true,
        secure: false
    )
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: current.interactiveSessionID,
        authorizationEpoch: current.authorizationEpoch,
        surfaceID: current.surfaceID,
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: current.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: current.coordinateRevision.rawValue
        ),
        applicationToken: UUID(),
        parentSurfaceID: UUID(),
        fallbackSurfaceID: UUID(),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(current.allowedInteractionClasses),
        privacyProfile: .assistedVisual,
        metadataFields: [.editable, .focusBounds, .focusCategory, .secure],
        focus: focus,
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
    let focusedTransition = try
        InteractiveRuntimeSurfaceTransitionCommandV0(
            commandID: UUID(),
            previousLeaseID: desktop.leaseID,
            replacement: current,
            descriptor: descriptor
        )
    _ = try await owner.prepareSurfaceTransition(
        focusedTransition,
        nowMonotonicNanoseconds: 4_000
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: current),
            header: try runtimeMediaHeader(
                lease: current,
                sequence: 3,
                payloadLength: 0,
                type: .discontinuity
            ),
            payload: Data()
        ),
        nowMonotonicNanoseconds: 4_100
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: current),
            header: try runtimeMediaHeader(
                lease: current,
                sequence: 4,
                payloadLength: UInt32(runtimeDecoderConfiguration.count),
                type: .decoderConfiguration
            ),
            payload: runtimeDecoderConfiguration
        ),
        nowMonotonicNanoseconds: 4_200
    )
    try await owner.publishMedia(
        InteractiveRuntimeMediaActionV0(
            commandID: UUID(),
            fence: runtimeFence(lease: current),
            header: try runtimeMediaHeader(
                lease: current,
                sequence: 5,
                type: .videoAccessUnit,
                cleanKeyframe: true
            ),
            payload: Data([0, 0, 0, 2, 0x65, 0])
        ),
        nowMonotonicNanoseconds: 4_300
    )
    _ = try await owner.acknowledgeSurface(
        InteractiveRuntimeSurfaceAcknowledgementCommandV0(
            commandID: UUID(),
            transitionCommandID: focusedTransition.commandID,
            leaseID: current.leaseID,
            interactiveSessionID: current.interactiveSessionID,
            surfaceID: current.surfaceID,
            surfaceRevision: current.surfaceRevision,
            coordinateRevision: current.coordinateRevision,
            focusToken: focus.token,
            focusRevision: focus.revision,
            readyMediaSequence: 5
        ),
        nowMonotonicNanoseconds: 4_400
    )
    let snapshot = try LocalInteractiveFocusSnapshotCommandV1(
        commandID: UUID(),
        interactiveSessionID: current.interactiveSessionID,
        authorizationEpoch: current.authorizationEpoch,
        currentSurfaceID: current.surfaceID,
        expectedSurfaceRevision: descriptor.surfaceRevision,
        expectedCoordinateSpaceRevision:
            descriptor.coordinateSpaceRevision
    )

    let nativeFence = try InteractiveNativeVideoRequestFenceV0(interactiveSessionID: .init(current.interactiveSessionID),
        authorizationEpoch: current.authorizationEpoch, negotiationID: .init(UUID()), peerGeneration: 1,
        surfaceID: .init(current.surfaceID), surfaceRevision: Int64(current.surfaceRevision.rawValue),
        coordinateSpaceRevision: Int64(current.coordinateRevision.rawValue))
    await #expect(throws: LocalInteractiveNativeSnapshotErrorV1.unavailable) {
        try await owner.currentNativeVideoSnapshot(fence: nativeFence, nowMonotonicNanoseconds: 4_400)
    }
    #expect(try await owner.pauseInputForFocusChange(snapshot))
    #expect(try await owner.pauseInputForFocusChange(snapshot))
    #expect(await owner.surfaceAdmissionState() == .focusPaused)
    #expect(try await owner.currentNativeVideoSnapshot(fence: nativeFence, nowMonotonicNanoseconds: 4_400) == nil)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.bindingMismatch) {
        try await owner.postInput(
            InteractiveRuntimeInputActionV0(
                commandID: UUID(),
                fence: runtimeFence(lease: current),
                envelope: runtimeInput(lease: current)
            ),
            nowMonotonicNanoseconds: 4_500
        )
    }

    // Cross-socket latency permits input already sent before the client learns
    // of the host's focus pause. Drain exact reliable ordering without posting.
    for (index, payload) in [InteractiveInputPayload.pointerMove(x: 1, y: 1),
                            .physicalKey(usage: 0x28, transition: .down, modifiers: []),
                            .reset].enumerated() {
        try await owner.postInputEnvelope(runtimeInput(lease: current, payload: payload,
            sequence: UInt64(index + 1), focus: focus), nowMonotonicNanoseconds: 4_600)
    }
    #expect(poster.postedInputs().isEmpty)
    #expect(await owner.surfaceAdmissionState() == .focusPaused)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.inputSequenceMismatch(expected: 4, actual: 5)) {
        try await owner.postInputEnvelope(runtimeInput(lease: current, sequence: 5, focus: focus),
            nowMonotonicNanoseconds: 4_600)
    }
    await #expect(throws: InteractiveLeaseError.staleLease) {
        try await owner.postInput(.init(commandID: UUID(), fence: runtimeFence(lease: current, leaseID: UUID()),
            envelope: runtimeInput(lease: current, sequence: 4, focus: focus)), nowMonotonicNanoseconds: 4_600)
    }
    await #expect(throws: InteractiveLeaseError.expired) {
        try await owner.postInputEnvelope(runtimeInput(lease: current, sequence: 4, focus: focus),
            nowMonotonicNanoseconds: 7_000)
    }
    await #expect(throws: InteractiveMenuRuntimeErrorV0.interactionClassDenied) {
        try await owner.postInputEnvelope(runtimeInput(lease: current, payload: .text("fixture"), sequence: 4, focus: focus),
            nowMonotonicNanoseconds: 4_600)
    }

    let replacement = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer, .keyboard],
        surfaceID: UUID(),
        surfaceRevision: 7,
        coordinateRevision: 10,
        renewalCounter: 2,
        issuedAt: 5_000,
        expiresAt: 8_000
    )
    let transition = try runtimeSurfaceTransition(
        current: current,
        replacement: replacement
    )
    _ = try await owner.prepareSurfaceTransition(
        transition,
        nowMonotonicNanoseconds: 5_100
    )
    #expect(await effects.events() == [
        .show, .start,
        .release, .prepare, .activate,
        .release, .prepare, .activate,
    ])
    let records: [(MediaRecordType, Data)] = [
        (.discontinuity, Data()), (.decoderConfiguration, runtimeDecoderConfiguration),
        (.videoAccessUnit, Data([0, 0, 0, 2, 0x65, 0])),
    ]
    for (offset, record) in records.enumerated() {
        try await owner.publishMedia(.init(commandID: UUID(), fence: runtimeFence(lease: replacement),
            header: runtimeMediaHeader(lease: replacement, sequence: UInt64(6 + offset),
                payloadLength: UInt32(record.1.count), type: record.0,
                cleanKeyframe: record.0 == .videoAccessUnit), payload: record.1),
            nowMonotonicNanoseconds: 5_200)
    }
    #expect(poster.postedInputs().isEmpty)
    _ = try await owner.acknowledgeSurface(.init(commandID: UUID(), transitionCommandID: transition.commandID,
        leaseID: replacement.leaseID, interactiveSessionID: replacement.interactiveSessionID,
        surfaceID: replacement.surfaceID, surfaceRevision: replacement.surfaceRevision,
        coordinateRevision: replacement.coordinateRevision, readyMediaSequence: 8),
        nowMonotonicNanoseconds: 5_300)
    let resumed = try runtimeInput(lease: replacement, sequence: 4)
    try await owner.postInputEnvelope(resumed, nowMonotonicNanoseconds: 5_400)
    #expect(poster.postedInputs() == [resumed]) // no drained input replayed
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
        .show, .start, .release, .prepare, .activate, .stop, .blank, .clear,
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

@Test func surfaceActivationFailureRunsFullCleanupAfterFenceCommit()
    async throws
{
    let effects = RuntimeEffectsProbe(failOnce: [.activate])
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
        .show, .start, .release, .prepare, .activate, .stop, .blank, .clear,
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

private func nativeRuntimeCommand(kind: InteractiveSurfaceKind = .desktop, rotation: SurfaceRotation = .degrees0) throws -> InteractiveRuntimeInstallCommandV0 {
    let lease = try runtimeLease()
    return try .init(commandID: UUID(), lease: lease, deviceDisplayName: .init("Native QA"),
        surfaceDescriptor: runtimeSurfaceDescriptor(lease: lease, kind: kind, encodedWidth: 320, encodedHeight: 240, rotation: rotation),
        sessionDeadlineMonotonicNanoseconds: 10_000)
}
private func nativeRuntimeFence(_ command: InteractiveRuntimeInstallCommandV0) throws -> InteractiveNativeVideoRequestFenceV0 {
    try .init(interactiveSessionID: .init(command.lease.interactiveSessionID),
        authorizationEpoch: command.lease.authorizationEpoch, negotiationID: .init(UUID()), peerGeneration: 1, surfaceID: .init(command.lease.surfaceID),
        surfaceRevision: Int64(command.lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: Int64(command.lease.coordinateRevision.rawValue))
}

@Test func nativeInputPauseRejectsEveryPayloadAndSurvivesRenewal() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text])
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let lease = try runtimeLease(allowedClasses: [.view, .pointer, .keyboard, .text])
    let command = try InteractiveRuntimeInstallCommandV0(commandID: UUID(), lease: lease,
        deviceDisplayName: .init("Native QA"),
        surfaceDescriptor: runtimeSurfaceDescriptor(lease: lease, kind: .desktop, encodedWidth: 320, encodedHeight: 240),
        sessionDeadlineMonotonicNanoseconds: 10_000)
    let fence = try nativeRuntimeFence(command)
    _ = try await installAndActivateInitial(owner, command: command)
    let first = try runtimeInput(lease: lease)
    try await owner.postInputEnvelope(first, nowMonotonicNanoseconds: 2_040)
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: 2_050)
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: 2_051)
    #expect(await effects.events().filter { $0 == .release }.count == 1)
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_060) != nil)
    let replacement = try runtimeLease(allowedClasses: [.view, .pointer, .keyboard, .text],
        renewalCounter: 1, issuedAt: 4_000, expiresAt: 8_000)
    try await owner.renew(.init(commandID: UUID(), previousLeaseID: lease.leaseID, replacement: replacement),
        nowMonotonicNanoseconds: 4_000)
    let payloads: [InteractiveInputPayload] = [
        .pointerMove(x: 1, y: 1), .button(button: .primary, transition: .down),
        .scroll(unit: .pixel, deltaX: 1, deltaY: 1),
        .physicalKey(usage: 0x04, transition: .down, modifiers: []),
        .modifiers([]), .text(String(UnicodeScalar(65))), .reset
    ]
    for payload in payloads {
        let envelope = try runtimeInput(lease: replacement, payload: payload, sequence: 2)
        await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
            try await owner.postInputEnvelope(envelope, nowMonotonicNanoseconds: 5_000)
        }
        let action = try InteractiveRuntimeInputActionV0(commandID: UUID(), fence: runtimeFence(lease: replacement), envelope: envelope)
        await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
            try await owner.postInput(action, nowMonotonicNanoseconds: 5_000)
        }
    }
    #expect(poster.postedInputs() == [first])
    _ = try await owner.revoke(revokeCommand(lease: replacement))
    let fresh = try nativeRuntimeCommand()
    _ = try await installAndActivateInitial(owner, command: fresh)
    let next = try runtimeInput(lease: fresh.lease)
    try await owner.postInputEnvelope(next, nowMonotonicNanoseconds: 2_040)
    #expect(poster.postedInputs() == [first, next])
}

@Test func nativeInputPauseRejectsWrongFenceAndReleaseFailureDrains() async throws {
    let effects = RuntimeEffectsProbe(failOnce: [.release])
    let owner = runtimeOwner(probe: effects)
    let command = try nativeRuntimeCommand()
    _ = try await installAndActivateInitial(owner, command: command)
    let valid = try nativeRuntimeFence(command)
    let wrong = try InteractiveNativeVideoRequestFenceV0(interactiveSessionID: valid.interactiveSessionID,
        authorizationEpoch: valid.authorizationEpoch, negotiationID: valid.negotiationID,
        peerGeneration: valid.peerGeneration, surfaceID: .init(UUID()),
        surfaceRevision: valid.surfaceRevision, coordinateSpaceRevision: valid.coordinateSpaceRevision)
    await #expect(throws: LocalInteractiveNativeSnapshotErrorV1.bindingMismatch) {
        try await owner.pauseInputForNativePresentation(fence: wrong, nowMonotonicNanoseconds: 2_050)
    }
    #expect(await effects.events() == [.show, .start])
    await #expect(throws: InteractiveMenuRuntimeErrorV0.platformActionFailed) {
        try await owner.pauseInputForNativePresentation(fence: valid, nowMonotonicNanoseconds: 2_050)
    }
    #expect(await owner.state() == .idle)
    #expect(await effects.events() == [.show, .start, .release, .release, .stop, .blank, .clear])
}

@Test(arguments: SurfaceRotation.allCases) func nativeSnapshotRequiresAcknowledgedDesktopAndExactFence(rotation: SurfaceRotation) async throws {
    let owner = runtimeOwner(probe: RuntimeEffectsProbe())
    let command = try nativeRuntimeCommand(rotation: rotation)
    let fence = try nativeRuntimeFence(command)
    _ = try await owner.install(command, nowMonotonicNanoseconds: 2_000)
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_000) == nil)
    _ = try await installAndActivateInitial(owner, command: command)
    let value = try #require(await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_050))
    #expect(value.controlGeneration == command.commandID)
    #expect(value.selectedDisplayID == command.lease.selectedDisplayID)
    #expect(value.surfaceKind == .desktop)
    #expect(value.encodedWidth == 320 && value.encodedHeight == 240)
    #expect(value.logicalWidthPoints == command.surfaceDescriptor.logicalWidthPoints)
    #expect(value.logicalHeightPoints == command.surfaceDescriptor.logicalHeightPoints)
    #expect(value.rotation == command.surfaceDescriptor.rotation)
    #expect(value.logicalWidthPoints != value.encodedWidth)
    let wrong = try InteractiveNativeVideoRequestFenceV0(interactiveSessionID: fence.interactiveSessionID, authorizationEpoch: fence.authorizationEpoch,
        negotiationID: fence.negotiationID, peerGeneration: fence.peerGeneration,
        surfaceID: .init(UUID()), surfaceRevision: fence.surfaceRevision,
        coordinateSpaceRevision: fence.coordinateSpaceRevision)
    await #expect(throws: LocalInteractiveNativeSnapshotErrorV1.bindingMismatch) {
        try await owner.currentNativeVideoSnapshot(fence: wrong, nowMonotonicNanoseconds: 2_050)
    }
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 5_000) == nil)
    _ = try await owner.revoke(revokeCommand(lease: command.lease))
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_050) == nil)
}

@Test func nativeSnapshotRenewalKeepsOriginalDeadlineAndGeneration() async throws {
    let owner = runtimeOwner(probe: RuntimeEffectsProbe())
    let command = try nativeRuntimeCommand()
    let fence = try nativeRuntimeFence(command)
    _ = try await installAndActivateInitial(owner, command: command)
    let before = try #require(await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_050))
    let replacement = try runtimeLease(renewalCounter: 1, issuedAt: 4_000, expiresAt: 8_000)
    try await owner.renew(.init(commandID: UUID(), previousLeaseID: command.lease.leaseID, replacement: replacement), nowMonotonicNanoseconds: 4_000)
    let after = try #require(await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 5_000))
    #expect(after.leaseExpiresAtMonotonicNanoseconds == 8_000)
    #expect(after.sessionDeadlineMonotonicNanoseconds == before.sessionDeadlineMonotonicNanoseconds)
    #expect(after.controlGeneration == before.controlGeneration)
    #expect(after.menuAppGeneration == before.menuAppGeneration)
    #expect(after.menuAppRevision == before.menuAppRevision)
    #expect(after.logicalWidthPoints == before.logicalWidthPoints)
    #expect(after.logicalHeightPoints == before.logicalHeightPoints)
    #expect(after.rotation == before.rotation)
    #expect(after.surfaceKind == before.surfaceKind)
}

@Test(arguments: [InteractiveSurfaceKind.application, .window])
func nativeSnapshotRequiresAcknowledgedSelectedReplacement(kind: InteractiveSurfaceKind) async throws {
    let owner = runtimeOwner(probe: RuntimeEffectsProbe(readyClasses: [.view, .pointer]))
    let initial = try nativeRuntimeCommand()
    _ = try await installAndActivateInitial(owner, command: initial)
    let replacement = try runtimeLease(leaseID: UUID(), surfaceID: UUID(), surfaceRevision: 6,
        coordinateRevision: 9, renewalCounter: 1, issuedAt: 3_000, expiresAt: 7_000)
    let descriptor = try runtimeSurfaceDescriptor(lease: replacement, kind: kind,
        encodedWidth: 320, encodedHeight: 240, applicationToken: UUID(),
        windowToken: kind == .window ? UUID() : nil)
    let transition = try InteractiveRuntimeSurfaceTransitionCommandV0(commandID: UUID(),
        previousLeaseID: initial.lease.leaseID, replacement: replacement, descriptor: descriptor)
    _ = try await owner.prepareSurfaceTransition(transition, nowMonotonicNanoseconds: 4_000)
    let replacementCommand = try InteractiveRuntimeInstallCommandV0(commandID: initial.commandID,
        lease: replacement, deviceDisplayName: initial.deviceDisplayName,
        surfaceDescriptor: descriptor, sessionDeadlineMonotonicNanoseconds: initial.sessionDeadlineMonotonicNanoseconds)
    let fence = try nativeRuntimeFence(replacementCommand)
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 4_001) == nil)
    let discontinuity = try runtimeMediaHeader(lease: replacement, sequence: 3,
        payloadLength: 0, type: .discontinuity)
    try await owner.publishMedia(.init(commandID: UUID(), fence: runtimeFence(lease: replacement),
        header: discontinuity, payload: Data()), nowMonotonicNanoseconds: 4_100)
    let configuration = try runtimeMediaHeader(lease: replacement, sequence: 4,
        payloadLength: UInt32(runtimeDecoderConfiguration.count), type: .decoderConfiguration,
        encodedWidth: 320, encodedHeight: 240)
    try await owner.publishMedia(.init(commandID: UUID(), fence: runtimeFence(lease: replacement),
        header: configuration, payload: runtimeDecoderConfiguration), nowMonotonicNanoseconds: 4_200)
    let clean = try runtimeMediaHeader(lease: replacement, sequence: 5,
        type: .videoAccessUnit, cleanKeyframe: true, encodedWidth: 320, encodedHeight: 240)
    try await owner.publishMedia(.init(commandID: UUID(), fence: runtimeFence(lease: replacement),
        header: clean, payload: Data([0, 0, 0, 2, 0x65, 0])), nowMonotonicNanoseconds: 4_300)
    #expect(try await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 4_301) == nil)
    _ = try await owner.acknowledgeSurface(.init(commandID: UUID(), transitionCommandID: transition.commandID,
        leaseID: replacement.leaseID, interactiveSessionID: replacement.interactiveSessionID,
        surfaceID: replacement.surfaceID, surfaceRevision: replacement.surfaceRevision,
        coordinateRevision: replacement.coordinateRevision, readyMediaSequence: 5),
        nowMonotonicNanoseconds: 4_400)
    let snapshot = try #require(await owner.currentNativeVideoSnapshot(fence: fence,
        nowMonotonicNanoseconds: 4_401))
    #expect(snapshot.surfaceKind == kind)
    #expect(snapshot.fence.surfaceID.rawValue == replacement.surfaceID)
    #expect(snapshot.controlGeneration == initial.commandID)
    #expect(snapshot.sessionDeadlineMonotonicNanoseconds == initial.sessionDeadlineMonotonicNanoseconds)
}

@Test func nativeSnapshotCodecRejectsCrossCorrelationAndUnknownFields() async throws {
    let owner = runtimeOwner(probe: RuntimeEffectsProbe())
    let command = try nativeRuntimeCommand()
    let fence = try nativeRuntimeFence(command)
    _ = try await installAndActivateInitial(owner, command: command)
    let value = try #require(await owner.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: 2_050))
    let request = try LocalInteractiveNativeSnapshotCommandV1(commandID: UUID(), fence: fence)
    let receipt = try LocalInteractiveNativeSnapshotReceiptV1(correlationID: request.commandID, snapshot: value)
    let encoded = try LocalInteractiveLeaseWireCodecV1.encodeNativeSnapshotReceipt(receipt)
    #expect(encoded.count <= 4096)
    let decoded = try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(encoded)
    try decoded.validate(against: request)
    #expect(decoded == receipt)
    let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for field in ["logicalWidthPoints", "logicalHeightPoints", "rotation", "surfaceKind"] {
        var object = original
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot.removeValue(forKey: field)
        object["snapshot"] = snapshot
        let missing = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.invalidPayload) {
            try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(missing)
        }
    }
    for (field, bad) in [("logicalWidthPoints", 0), ("logicalHeightPoints", 0)] {
        var object = original
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot[field] = bad
        object["snapshot"] = snapshot
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalInteractiveNativeSnapshotErrorV1.bindingMismatch) {
            try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(invalid)
        }
    }
    for (field, bad) in [("rotation", 45), ("logicalWidthPoints", 4294967296), ("logicalHeightPoints", -1)] {
        var object = original
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot[field] = bad
        object["snapshot"] = snapshot
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.invalidPayload) {
            try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(invalid)
        }
    }
    for kind in ["application", "window"] {
        var object = original
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot["surfaceKind"] = kind
        object["snapshot"] = snapshot
        let replacement = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let admitted = try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(replacement)
        #expect(admitted.snapshot.surfaceKind.rawValue == kind)
    }
    for kind in ["focusedRegion"] {
        var object = original
        var snapshot = try #require(object["snapshot"] as? [String: Any])
        snapshot["surfaceKind"] = kind
        object["snapshot"] = snapshot
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalInteractiveNativeSnapshotErrorV1.bindingMismatch) {
            try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(invalid)
        }
    }
    var unknown = original
    var snapshot = try #require(unknown["snapshot"] as? [String: Any])
    snapshot["surfaceKind"] = "other"
    unknown["snapshot"] = snapshot
    let invalidKind = try JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.invalidPayload) {
        try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(invalidKind)
    }
    #expect(throws: LocalInteractiveNativeSnapshotErrorV1.bindingMismatch) {
        try decoded.validate(against: .init(commandID: UUID(), fence: fence))
    }
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["physicalDisplayID"] = 1
    let ambiguous = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.self) {
        try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(ambiguous)
    }
}

private final class RuntimeNativeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 2_000_000_000
    func read() -> UInt64 { lock.withLock { value } }
    func set(_ value: UInt64) { lock.withLock { self.value = value } }
}
private func runtimeNativePostingCommand() throws -> InteractiveRuntimeInstallCommandV0 {
    let lease = try runtimeLease(allowedClasses: [.view, .pointer, .keyboard, .text],
        issuedAt: 1_000_000_000, expiresAt: 5_000_000_000)
    return try .init(commandID: UUID(), lease: lease, deviceDisplayName: .init("Native QA"),
        surfaceDescriptor: runtimeSurfaceDescriptor(lease: lease, kind: .desktop, encodedWidth: 320, encodedHeight: 240),
        sessionDeadlineMonotonicNanoseconds: 10_000_000_000)
}
private func runtimeNativePostingAuthorization(_ command: InteractiveRuntimeInstallCommandV0,
    clock: RuntimeNativeClock, generation: UUID? = nil, width: Int = 320) throws -> InteractiveRuntimeNativeInputPostingAuthorizationV0 {
    let lease = command.lease
    let binding = try InteractiveNativeVideoBindingV0(hostID: lease.hostID, hostFingerprint: Data(repeating: 1, count: 32),
        clientID: lease.deviceID, primaryConnectionID: Data(repeating: 2, count: 16),
        interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: Int64(lease.authorizationEpoch.rawValue),
        grantRevision: 1, policyRevision: 1, controlGeneration: generation ?? command.commandID,
        expiresAtMonotonicMilliseconds: command.sessionDeadlineMonotonicNanoseconds / 1_000_000)
    let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: lease.surfaceID,
        surfaceRevision: Int64(lease.surfaceRevision.rawValue), coordinateSpaceRevision: Int64(lease.coordinateRevision.rawValue),
        encodedWidth: width, encodedHeight: 240)
    return .init(binding: binding, surface: surface, monotonicNanoseconds: { clock.read() }) { _, batch in try batch() }
}

@Test func nativeRuntimeInstallationRequiresExactPauseAndOriginalControlGeometry() async throws {
    for mismatch in ["pause", "fence", "generation", "geometry", "revoked"] {
        let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text]), poster = RuntimeInputPosterProbe()
        let owner = runtimeOwner(probe: effects, poster: poster), command = try runtimeNativePostingCommand()
        let fence = try nativeRuntimeFence(command), clock = RuntimeNativeClock()
        _ = try await installAndActivateInitial(owner, command: command, now: 2_000_000_000)
        if mismatch != "pause" { try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read()) }
        let authorization = try runtimeNativePostingAuthorization(command, clock: clock,
            generation: mismatch == "generation" ? UUID() : nil, width: mismatch == "geometry" ? 640 : 320)
        if mismatch == "revoked" { authorization.revoke() }
        await #expect(throws: (any Error).self) {
            try await owner.installNativeInputAuthorization(authorization,
                fence: mismatch == "fence" ? nativeRuntimeFence(command) : fence, nowMonotonicNanoseconds: clock.read())
        }
        #expect(poster.postedInputs().isEmpty)
    }
}

@Test func nativeRuntimePermitPostsControlsThroughRenewalAndRepauseRevokesCopies() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text]), poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster), command = try runtimeNativePostingCommand()
    let fence = try nativeRuntimeFence(command), clock = RuntimeNativeClock()
    _ = try await installAndActivateInitial(owner, command: command, now: clock.read())
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read())
    let authorization = try runtimeNativePostingAuthorization(command, clock: clock)
    try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
        try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    }
    let payloads: [InteractiveInputPayload] = [.pointerMove(x: 1, y: 1), .modifiers([]),
        .physicalKey(usage: 0x04, transition: .down, modifiers: []), .text("A"), .reset]
    for (index, payload) in payloads.enumerated() {
        try await owner.postInputEnvelope(runtimeInput(lease: command.lease, payload: payload, sequence: UInt64(index + 1)),
            nowMonotonicNanoseconds: clock.read())
    }
    let replacement = try runtimeLease(allowedClasses: [.view, .pointer, .keyboard, .text], renewalCounter: 1,
        issuedAt: 4_000_000_000, expiresAt: 8_000_000_000)
    clock.set(4_000_000_000)
    try await owner.renew(.init(commandID: UUID(), previousLeaseID: command.lease.leaseID, replacement: replacement),
        nowMonotonicNanoseconds: clock.read())
    clock.set(6_000_000_000)
    let renewedInput = try runtimeInput(lease: replacement, sequence: 6)
    try await owner.postInputEnvelope(renewedInput, nowMonotonicNanoseconds: clock.read())
    #expect(poster.postedInputs().count == 6)
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read())
    #expect(authorization.isRevoked)
    await #expect(throws: (any Error).self) {
        try await authorization.perform(renewedInput, beforeDeadlineNanoseconds: 8_000_000_000) {
            Issue.record("Revoked retained permit posted input")
        }
    }
    await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
        try await owner.postInputEnvelope(runtimeInput(lease: replacement, sequence: 7), nowMonotonicNanoseconds: clock.read())
    }
    #expect(await effects.events().filter { $0 == .release }.count == 2)
}

@Test func nativeRuntimeTerminationRevokesRetainedPostingAuthorization() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text])
    let owner = runtimeOwner(probe: effects), command = try runtimeNativePostingCommand(), clock = RuntimeNativeClock()
    let fence = try nativeRuntimeFence(command), authorization = try runtimeNativePostingAuthorization(command, clock: clock)
    _ = try await installAndActivateInitial(owner, command: command, now: clock.read())
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read())
    try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    _ = try await owner.revoke(revokeCommand(lease: command.lease))
    #expect(authorization.isRevoked)
    await #expect(throws: (any Error).self) {
        try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    }
}

@Test func revokedNativePermitDrainsOnlyExactCurrentReset() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text])
    let poster = RuntimeInputPosterProbe()
    let owner = runtimeOwner(probe: effects, poster: poster)
    let command = try runtimeNativePostingCommand(), clock = RuntimeNativeClock()
    let fence = try nativeRuntimeFence(command)
    let authorization = try runtimeNativePostingAuthorization(command, clock: clock)
    _ = try await installAndActivateInitial(owner, command: command, now: clock.read())
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read())
    try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    authorization.revoke()

    let reset = try runtimeInput(lease: command.lease, payload: .reset)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
        try await owner.postInputEnvelope(try runtimeInput(lease: command.lease),
            nowMonotonicNanoseconds: clock.read())
    }
    try await owner.postInputEnvelope(reset, nowMonotonicNanoseconds: clock.read())
    try await owner.postInputEnvelope(reset, nowMonotonicNanoseconds: clock.read())
    #expect(poster.postedInputs().isEmpty)
    #expect(await effects.events().filter { $0 == .release }.count == 2)
    await #expect(throws: InteractiveMenuRuntimeErrorV0.surfaceNotAcknowledged) {
        try await owner.postInputEnvelope(try runtimeInput(lease: command.lease, sequence: 2),
            nowMonotonicNanoseconds: clock.read())
    }
}

@Test func nativeRuntimeSurfaceTransitionRevokesOldPermitBeforeCapturePreparation() async throws {
    let effects = RuntimeEffectsProbe(readyClasses: [.view, .pointer, .keyboard, .text])
    let poster = RuntimeInputPosterProbe(), owner = runtimeOwner(probe: effects, poster: poster)
    let command = try runtimeNativePostingCommand(), clock = RuntimeNativeClock(), fence = try nativeRuntimeFence(command)
    let authorization = try runtimeNativePostingAuthorization(command, clock: clock)
    _ = try await installAndActivateInitial(owner, command: command, now: clock.read())
    try await owner.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: clock.read())
    try await owner.installNativeInputAuthorization(authorization, fence: fence, nowMonotonicNanoseconds: clock.read())
    let replacement = try runtimeLease(allowedClasses: [.view, .pointer, .keyboard, .text], surfaceID: UUID(),
        surfaceRevision: 6, coordinateRevision: 9, renewalCounter: 1, issuedAt: 3_000_000_000, expiresAt: 7_000_000_000)
    _ = try await owner.prepareSurfaceTransition(runtimeSurfaceTransition(current: command.lease, replacement: replacement),
        nowMonotonicNanoseconds: 3_000_000_000)
    #expect(authorization.isRevoked)
    try await owner.postInputEnvelope(
        try runtimeInput(lease: command.lease, payload: .reset),
        nowMonotonicNanoseconds: 3_000_000_001
    )
    #expect(await effects.events().contains(.prepare))
    #expect(poster.postedInputs().isEmpty)
}
