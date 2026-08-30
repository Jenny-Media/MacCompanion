#if os(macOS)
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
@testable import CompanionMacApplicationPlatform
import CompanionWire
import CoreGraphics
import Foundation
import Testing

private final class InputPermissionProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var valueStorage: Bool
    private var callsStorage = 0

    init(_ value: Bool) { valueStorage = value }

    func read() -> Bool {
        lock.withLock {
            callsStorage += 1
            return valueStorage
        }
    }

    func set(_ value: Bool) { lock.withLock { valueStorage = value } }
    func calls() -> Int { lock.withLock { callsStorage } }
}

private struct InputEventSnapshotV1: Equatable {
    let type: CGEventType
    let location: CGPoint
    let clickState: Int64
}

private final class InputEventSinkV1:
    CoreGraphicsConstructedEventSinkV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var rejectsStorage = false
    private var snapshotsStorage: [InputEventSnapshotV1] = []

    func setRejects(_ value: Bool) {
        lock.withLock { rejectsStorage = value }
    }

    func receiveConstructedEvent(_ event: CGEvent) throws {
        try lock.withLock {
            if rejectsStorage {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .eventConstructionFailed
            }
            snapshotsStorage.append(.init(
                type: event.type,
                location: event.location,
                clickState: event.getIntegerValueField(
                    .mouseEventClickState
                )
            ))
        }
    }

    func snapshots() -> [InputEventSnapshotV1] {
        lock.withLock { snapshotsStorage }
    }
}

private let inputDisplayBoundsV1 = CGRect(
    x: -100,
    y: 50,
    width: 200,
    height: 100
)

private func inputAdapterV1(
    permission: InputPermissionProbeV1,
    sink: InputEventSinkV1,
    surfaceActivator: MacInteractiveSelectedSurfaceActivatorV1 =
        MacInteractiveSelectedSurfaceActivatorV1()
) -> MacCoreGraphicsInteractiveInputAdapterV1 {
    MacCoreGraphicsInteractiveInputAdapterV1(
        preflightPostEventAccess: { permission.read() },
        displayBounds: { _ in inputDisplayBoundsV1 },
        displayPixels: { _ in (wide: 400, high: 200) },
        cursorPosition: { CGPoint(x: 0, y: 75) },
        sink: sink,
        surfaceActivator: surfaceActivator
    )
}

private func inputInstallCommandV1(
    logicalWidthPoints: UInt32 = 200,
    logicalHeightPoints: UInt32 = 100,
    kind: InteractiveSurfaceKind = .desktop
) throws
    -> InteractiveRuntimeInstallCommandV0
{
    let sessionID = UUID(
        uuidString: "018f6000-0000-7000-8000-000000000001"
    )!
    let surfaceID = UUID(
        uuidString: "018f6100-0000-7000-8000-000000000001"
    )!
    let displayID = UUID(
        uuidString: "018f6200-0000-7000-8000-000000000001"
    )!
    let classes: Set<SurfaceInteractionClass> = [
        .view, .pointer, .keyboard, .text,
    ]
    let lease = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: UUID(),
        deviceID: UUID(),
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: displayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 3),
        allowedInteractionClasses: classes,
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000_000_000,
        expiresAtMonotonicNanoseconds: 5_000_000_000
    )
    return try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(),
        lease: lease,
        deviceDisplayName: try .init("Test iPhone"),
        surfaceDescriptor: AdaptiveSurfaceDescriptor(
            interactiveSessionID: sessionID,
            authorizationEpoch: lease.authorizationEpoch,
            surfaceID: surfaceID,
            kind: kind,
            surfaceRevision: .init(rawValue: 2),
            coordinateSpaceRevision: .init(rawValue: 3),
            applicationToken: kind == .application ? UUID() : nil,
            encodedWidth: 400,
            encodedHeight: 200,
            logicalWidthPoints: logicalWidthPoints,
            logicalHeightPoints: logicalHeightPoints,
            interactionClasses: classes,
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1_000,
            expiresAtMonotonicMilliseconds: 5_000
        ),
        sessionDeadlineMonotonicNanoseconds: 6_000_000_000
    )
}

private func inputEnvelopeV1(
    command: InteractiveRuntimeInstallCommandV0,
    authorizationEpoch: UInt64? = nil,
    sequence: UInt64 = 1,
    clientMonotonicMilliseconds: UInt64 = 1,
    payload: InteractiveInputPayload
) throws -> InteractiveInputEnvelope {
    try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(
            command.lease.interactiveSessionID
        ),
        authorizationEpoch: .init(
            rawValue: authorizationEpoch
                ?? command.lease.authorizationEpoch.rawValue
        ),
        sequence: sequence,
        clientMonotonicMilliseconds: clientMonotonicMilliseconds,
        surfaceID: WireUUID(command.lease.surfaceID),
        surfaceRevision: .init(
            rawValue: command.lease.surfaceRevision.rawValue
        ),
        coordinateSpaceRevision: .init(
            rawValue: command.lease.coordinateRevision.rawValue
        ),
        input: payload
    )
}

@available(macOS 26.0, *)
@Test func coreGraphicsAdapterPostsARealDoubleClickState() async throws {
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    let command = try inputInstallCommandV1()
    _ = try adapter.configure(command: command, physicalDisplayID: 7)

    let transitions: [(UInt64, UInt64, InteractiveInputTransition)] = [
        (1, 1_000, .down),
        (2, 1_001, .up),
        (3, 1_100, .down),
        (4, 1_101, .up),
    ]
    for (sequence, timestamp, transition) in transitions {
        try await adapter.postInteractiveInput(inputEnvelopeV1(
            command: command,
            sequence: sequence,
            clientMonotonicMilliseconds: timestamp,
            payload: .button(button: .primary, transition: transition)
        ))
    }

    #expect(sink.snapshots().map(\.type) == [
        .leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp,
    ])
    #expect(sink.snapshots().map(\.clickState) == [1, 1, 2, 2])
}

@MainActor
private final class InputActivationProbeV1 {
    var performed: [ScreenCaptureKitLocalActivationTargetV0] = []
    var verified: [ScreenCaptureKitLocalActivationTargetV0] = []
    var performResult = true

    func perform(_ target: ScreenCaptureKitLocalActivationTargetV0) -> Bool {
        performed.append(target)
        return performResult
    }

    func verify(_ target: ScreenCaptureKitLocalActivationTargetV0) -> Bool {
        verified.append(target)
        return true
    }
}

@available(macOS 26.0, *)
@Test func coreGraphicsAdapterConstructionIsInertAndPermissionDeniesSetup()
    throws
{
    let permission = InputPermissionProbeV1(false)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    #expect(permission.calls() == 0)

    #expect(
        throws: MacCoreGraphicsInteractiveInputAdapterErrorV1
            .permissionDenied
    ) {
        try adapter.configure(
            command: inputInstallCommandV1(),
            physicalDisplayID: 7
        )
    }
    #expect(permission.calls() == 1)
    #expect(sink.snapshots().isEmpty)
}

@available(macOS 26.0, *)
@MainActor
@Test func concreteInteractiveCompositionConstructionIsEffectInert()
    async throws
{
    let displaySelection = try MacInteractiveOpaqueDisplaySelectionV1(
        physicalDisplayID: 7,
        opaqueID: UUID(),
        isDisplayOnline: { $0 == 7 }
    )
    let indicator = MacInteractiveActivityIndicatorV1()
    let composition = try MacInteractiveControlRuntimeCompositionV1.make(
        indicator: indicator,
        displaySelection: displaySelection
    )

    #expect(await composition.runtime.state() == .idle)
    #expect(composition.mediaQueue.status().recordCount == 0)
    #expect(indicator.phase == .inactive)
}

@available(macOS 26.0, *)
@Test func coreGraphicsAdapterPostsOnlyAnExactlyBoundEnvelope() async throws {
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    let command = try inputInstallCommandV1()
    #expect(try adapter.configure(
        command: command,
        physicalDisplayID: 7
    ) == Set(command.lease.allowedInteractionClasses))

    try await adapter.postInteractiveInput(inputEnvelopeV1(
        command: command,
        payload: .pointerMove(x: 0, y: UInt16.max)
    ))
    let first = try #require(sink.snapshots().first)
    #expect(first.type == .mouseMoved)
    #expect(first.location.x == inputDisplayBoundsV1.minX)
    #expect(first.location.y < inputDisplayBoundsV1.maxY)

    await #expect(
        throws: MacCoreGraphicsInteractiveInputAdapterErrorV1
            .bindingMismatch
    ) {
        try await adapter.postInteractiveInput(inputEnvelopeV1(
            command: command,
            authorizationEpoch: 5,
            payload: .pointerMove(x: 1, y: 1)
        ))
    }
    #expect(sink.snapshots().count == 1)
}

@available(macOS 26.0, *)
@MainActor
@Test func selectedApplicationIsVerifiedBeforeClickButNotPointerMovement()
    async throws
{
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let probe = InputActivationProbeV1()
    let target = ScreenCaptureKitLocalActivationTargetV0.application(
        processID: 42,
        bundleIdentifier: "example.target"
    )
    let activator = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { probe.perform($0) },
        verifyActivation: { probe.verify($0) },
        wait: {}
    )
    let adapter = inputAdapterV1(
        permission: permission,
        sink: sink,
        surfaceActivator: activator
    )
    let command = try inputInstallCommandV1(kind: .application)
    _ = try adapter.configure(
        command: command,
        physicalDisplayID: 7,
        activationTarget: target
    )

    try await adapter.postInteractiveInput(inputEnvelopeV1(
        command: command,
        payload: .pointerMove(x: 100, y: 100)
    ))
    #expect(probe.performed.isEmpty)
    #expect(probe.verified.isEmpty)

    try await adapter.postInteractiveInput(inputEnvelopeV1(
        command: command,
        sequence: 2,
        payload: .button(button: .primary, transition: .down)
    ))
    #expect(probe.performed == [target])
    #expect(probe.verified == [target])

    try await adapter.releaseAllInteractiveInput()
    #expect(sink.snapshots().map(\.type) == [
        .mouseMoved, .leftMouseDown, .leftMouseUp,
    ])
    #expect(probe.performed == [target])
}

@available(macOS 26.0, *)
@MainActor
@Test func failedSelectedApplicationVerificationPostsNoClick() async throws {
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let probe = InputActivationProbeV1()
    probe.performResult = false
    let target = ScreenCaptureKitLocalActivationTargetV0.application(
        processID: 42,
        bundleIdentifier: "example.target"
    )
    let activator = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { probe.perform($0) },
        verifyActivation: { probe.verify($0) },
        wait: {}
    )
    let adapter = inputAdapterV1(
        permission: permission,
        sink: sink,
        surfaceActivator: activator
    )
    let command = try inputInstallCommandV1(kind: .application)
    _ = try adapter.configure(
        command: command,
        physicalDisplayID: 7,
        activationTarget: target
    )

    await #expect(
        throws: MacCoreGraphicsInteractiveInputAdapterErrorV1.bindingMismatch
    ) {
        try await adapter.postInteractiveInput(inputEnvelopeV1(
            command: command,
            payload: .button(button: .primary, transition: .down)
        ))
    }
    #expect(probe.performed == [target])
    #expect(probe.verified.isEmpty)
    #expect(sink.snapshots().isEmpty)
}

@available(macOS 26.0, *)
@Test func coreGraphicsAdapterUsesMenuRetainedWindowGeometry() async throws {
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    let command = try inputInstallCommandV1(
        logicalWidthPoints: 75,
        logicalHeightPoints: 40
    )
    let windowBounds = CGRect(x: 500, y: -200, width: 75, height: 40)
    _ = try adapter.configure(
        command: command,
        physicalDisplayID: 7,
        inputBounds: windowBounds,
        inputBackingScaleFactor: 2.5
    )

    try await adapter.postInteractiveInput(inputEnvelopeV1(
        command: command,
        payload: .pointerMove(x: UInt16.max, y: 0)
    ))
    let event = try #require(sink.snapshots().first)
    #expect(event.location.x < windowBounds.maxX)
    #expect(event.location.x > windowBounds.maxX - 1)
    #expect(event.location.y == windowBounds.minY)

    let rejected = inputAdapterV1(
        permission: permission,
        sink: InputEventSinkV1()
    )
    #expect(
        throws: MacCoreGraphicsInteractiveInputAdapterErrorV1.bindingMismatch
    ) {
        try rejected.configure(
            command: command,
            physicalDisplayID: 7,
            inputBounds: windowBounds,
            inputBackingScaleFactor: .nan
        )
    }
}

@available(macOS 26.0, *)
@Test func failedConstructionDoesNotCommitPressedInputState() async throws {
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    let command = try inputInstallCommandV1()
    _ = try adapter.configure(command: command, physicalDisplayID: 7)
    let buttonDown = try inputEnvelopeV1(
        command: command,
        payload: .button(button: .primary, transition: .down)
    )

    sink.setRejects(true)
    await #expect(
        throws: MacCoreGraphicsInteractiveInputAdapterErrorV1
            .eventConstructionFailed
    ) {
        try await adapter.postInteractiveInput(buttonDown)
    }
    sink.setRejects(false)
    try await adapter.postInteractiveInput(buttonDown)
    try await adapter.releaseAllInteractiveInput()
    #expect(sink.snapshots().map(\.type) == [.leftMouseDown, .leftMouseUp])

    adapter.retireConfiguration()
    await #expect(throws: MacCoreGraphicsInteractiveInputAdapterErrorV1.unavailable) {
        try await adapter.postInteractiveInput(buttonDown)
    }
}

@available(macOS 26.0, *)
@Test func emptyInputCleanupDoesNotRequirePermissionThatMayBeRevoked()
    async throws
{
    let permission = InputPermissionProbeV1(true)
    let sink = InputEventSinkV1()
    let adapter = inputAdapterV1(permission: permission, sink: sink)
    _ = try adapter.configure(
        command: inputInstallCommandV1(),
        physicalDisplayID: 7
    )
    permission.set(false)

    try await adapter.releaseAllInteractiveInput()
    #expect(sink.snapshots().isEmpty)
    #expect(permission.calls() == 1)
    adapter.retireConfiguration()
}
#endif
