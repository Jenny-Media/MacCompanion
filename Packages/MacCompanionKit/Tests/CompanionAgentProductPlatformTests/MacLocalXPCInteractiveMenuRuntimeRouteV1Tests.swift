#if os(macOS)
import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
@testable import CompanionAgentProductPlatform
import CompanionLocalXPCPlatform
import Foundation
import Testing

private enum InteractiveMenuRouteProbeErrorV1: Error {
    case unavailable
}

private actor InteractiveMenuRouteSenderV1:
    MacLocalXPCInteractiveLeaseSendingV1
{
    let receipt: LocalInteractiveInitialDesktopPreparedReceiptV1
    let focusReceipt: LocalInteractiveFocusSnapshotReceiptV1?
    let nativeSnapshot: LocalInteractiveNativeRuntimeSnapshotV1?
    private var commandsStorage:
        [LocalInteractiveInitialDesktopPreparationCommandV1] = []
    private var focusCommandsStorage:
        [LocalInteractiveFocusSnapshotCommandV1] = []

    init(
        receipt: LocalInteractiveInitialDesktopPreparedReceiptV1,
        focusReceipt: LocalInteractiveFocusSnapshotReceiptV1? = nil,
        nativeSnapshot: LocalInteractiveNativeRuntimeSnapshotV1? = nil
    ) {
        self.receipt = receipt
        self.focusReceipt = focusReceipt
        self.nativeSnapshot = nativeSnapshot
    }

    func nativeRuntimeSnapshot(_ command: LocalInteractiveNativeSnapshotCommandV1) throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        guard let nativeSnapshot else { throw InteractiveMenuRouteProbeErrorV1.unavailable }
        return try .init(correlationID: command.commandID, snapshot: nativeSnapshot)
    }

    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        commandsStorage.append(command)
        return receipt
    }

    func installInteractiveLease(
        _: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func renewInteractiveLease(
        _: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func revokeInteractiveLease(
        _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        focusCommandsStorage.append(command)
        guard let focusReceipt else {
            throw InteractiveMenuRouteProbeErrorV1.unavailable
        }
        return focusReceipt
    }

    func commands()
        -> [LocalInteractiveInitialDesktopPreparationCommandV1] {
        commandsStorage
    }

    func focusCommands() -> [LocalInteractiveFocusSnapshotCommandV1] {
        focusCommandsStorage
    }
}

private actor SerializingInteractiveMenuRouteSenderV1:
    MacLocalXPCInteractiveLeaseSendingV1
{
    private var focusStarted = false
    private var focusStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var focusRelease: CheckedContinuation<Void, Never>?
    private var renewalStarted = false

    func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func installInteractiveLease(
        _: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func renewInteractiveLease(
        _: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        renewalStarted = true
    }

    func revokeInteractiveLease(
        _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        throw InteractiveMenuRouteProbeErrorV1.unavailable
    }

    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        focusStarted = true
        let waiters = focusStartWaiters
        focusStartWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { focusRelease = $0 }
        return LocalInteractiveFocusSnapshotReceiptV1(
            correlationID: command.commandID,
            command: command,
            candidate: try LocalInteractiveFocusCandidateV1(
                recommendedTargetKind: .desktop,
                focus: nil,
                inputPaused: false,
                reason: .accessibilityUnavailable,
                validForMilliseconds: 1_000
            )
        )
    }

    func waitUntilFocusStarted() async {
        if focusStarted { return }
        await withCheckedContinuation { focusStartWaiters.append($0) }
    }

    func releaseFocus() {
        focusRelease?.resume()
        focusRelease = nil
    }

    func didStartRenewal() -> Bool { renewalStarted }
}

@available(macOS 26.0, *)
@Test func interactiveMenuRouteBindsInitialDesktopCommandAndReceipt()
    async throws
{
    let commandID = UUID()
    let sessionID = UUID()
    let displayID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 2_000,
        expiresAtMonotonicMilliseconds: 12_000
    )
    let receipt = try LocalInteractiveInitialDesktopPreparedReceiptV1(
        correlationID: commandID,
        descriptor: descriptor
    )
    let sender = InteractiveMenuRouteSenderV1(receipt: receipt)
    let route = MacLocalXPCInteractiveMenuRuntimeRouteV1(
        sender: sender,
        identifier: { commandID }
    )

    let result = try await route.prepareInitialDesktop(
        AgentInteractiveInitialDesktopRequestV1(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 4),
            selectedDisplayID: displayID,
            interactionClasses: [.view, .pointer],
            nowMonotonicNanoseconds: 2_000_000_000
        )
    )

    #expect(result == descriptor)
    let sent = try #require(await sender.commands().first)
    #expect(sent.commandID == commandID)
    #expect(sent.interactiveSessionID == sessionID)
    #expect(sent.authorizationEpoch.rawValue == 4)
    #expect(sent.selectedDisplayID == displayID)
    #expect(sent.interactionClasses == [.pointer, .view])
}

@available(macOS 26.0, *)
@Test func interactiveMenuRouteReturnsOnlyValidatedFocusCandidate()
    async throws
{
    let commandID = UUID()
    let sessionID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 3),
        coordinateSpaceRevision: .init(rawValue: 5),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 2_000,
        expiresAtMonotonicMilliseconds: 12_000
    )
    let initialReceipt = try LocalInteractiveInitialDesktopPreparedReceiptV1(
        correlationID: UUID(),
        descriptor: descriptor
    )
    let localCommand = try LocalInteractiveFocusSnapshotCommandV1(
        commandID: commandID,
        interactiveSessionID: sessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        currentSurfaceID: descriptor.surfaceID,
        expectedSurfaceRevision: descriptor.surfaceRevision,
        expectedCoordinateSpaceRevision:
            descriptor.coordinateSpaceRevision
    )
    let localReceipt = LocalInteractiveFocusSnapshotReceiptV1(
        correlationID: commandID,
        command: localCommand,
        candidate: try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: .desktop,
            focus: nil,
            inputPaused: false,
            reason: .accessibilityUnavailable,
            validForMilliseconds: 1_000
        )
    )
    let sender = InteractiveMenuRouteSenderV1(
        receipt: initialReceipt,
        focusReceipt: localReceipt
    )
    let route = MacLocalXPCInteractiveMenuRuntimeRouteV1(
        sender: sender,
        identifier: { commandID }
    )

    let candidate = try await route.focusCandidate(current: descriptor)

    #expect(candidate.recommendedTargetKind == .desktop)
    #expect(candidate.focus == nil)
    #expect(candidate.reason == .accessibilityUnavailable)
    #expect(candidate.inputPaused == false)
    #expect(await sender.focusCommands() == [localCommand])
}

@available(macOS 26.0, *)
@Test func interactiveMenuRouteSerializesRenewalBehindFocusSnapshot()
    async throws
{
    let sessionID = UUID()
    let surfaceID = UUID()
    let hostID = UUID()
    let deviceID = UUID()
    let displayID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 2_000,
        expiresAtMonotonicMilliseconds: 12_000
    )
    let previousLeaseID = UUID()
    let current = try InteractiveExecutionLease(
        leaseID: previousLeaseID,
        hostID: hostID,
        deviceID: deviceID,
        interactiveSessionID: sessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        selectedDisplayID: displayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer],
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 2_000_000_000,
        expiresAtMonotonicNanoseconds: 12_000_000_000
    )
    let replacement = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: hostID,
        deviceID: deviceID,
        interactiveSessionID: sessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        selectedDisplayID: displayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer],
        renewalCounter: 1,
        issuedAtMonotonicNanoseconds: 10_000_000_000,
        expiresAtMonotonicNanoseconds: 20_000_000_000
    )
    let renewal = try InteractiveRuntimeLeaseRenewalV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement
    )
    let sender = SerializingInteractiveMenuRouteSenderV1()
    let route = MacLocalXPCInteractiveMenuRuntimeRouteV1(sender: sender)

    let focus = Task { try await route.focusCandidate(current: descriptor) }
    await sender.waitUntilFocusStarted()
    let renew = Task { try await route.renewInteractiveLease(renewal) }
    for _ in 0..<20 { await Task.yield() }
    #expect(!(await sender.didStartRenewal()))

    await sender.releaseFocus()
    _ = try await focus.value
    try await renew.value
    #expect(await sender.didStartRenewal())
}

@available(macOS 26.0, *)
@Test func nativeMenuRouteUsesAcknowledgedOriginalDeadlineAndTrustedPrimaryContext() async throws {
    let now = DispatchTime.now().uptimeNanoseconds
    let hostID = UUID(), deviceID = UUID(), sessionID = UUID(), displayID = UUID(), surfaceID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(interactiveSessionID: sessionID, authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID, kind: .desktop, surfaceRevision: .init(rawValue: 1), coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1280, encodedHeight: 720, logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees90,
        interactionClasses: [.view, .pointer], privacyProfile: .visualOnly, metadataFields: [],
        createdAtMonotonicMilliseconds: 1, expiresAtMonotonicMilliseconds: 12_000)
    let lease = try InteractiveExecutionLease(leaseID: UUID(), hostID: hostID, deviceID: deviceID, interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 4), selectedDisplayID: displayID, surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: 1), coordinateRevision: .init(rawValue: 1), allowedInteractionClasses: [.view, .pointer],
        renewalCounter: 0, issuedAtMonotonicNanoseconds: now, expiresAtMonotonicNanoseconds: now + 5_000_000_000)
    let install = try InteractiveRuntimeInstallCommandV0(commandID: UUID(), lease: lease, deviceDisplayName: .init("Native QA"),
        surfaceDescriptor: descriptor, sessionDeadlineMonotonicNanoseconds: now + 60_000_000_000)
    let installed = try InteractiveRuntimeInstallReceiptV0(correlationID: install.commandID, leaseID: lease.leaseID,
        interactiveSessionID: sessionID, selectedDisplayID: displayID, menuAppGeneration: UUID(), menuAppRevision: 9,
        readyInteractionClasses: [.view, .pointer], indicatorVisible: true)
    let fence = try InteractiveNativeVideoRequestFenceV0(interactiveSessionID: .init(sessionID), authorizationEpoch: .init(rawValue: 4),
        negotiationID: .init(UUID()), peerGeneration: 1, surfaceID: .init(surfaceID), surfaceRevision: 1, coordinateSpaceRevision: 1)
    let projection = try LocalInteractiveNativeRuntimeSnapshotV1(command: install, receipt: installed, fence: fence)
    let prepared = try LocalInteractiveInitialDesktopPreparedReceiptV1(correlationID: UUID(), descriptor: descriptor)
    let sender = InteractiveMenuRouteSenderV1(receipt: prepared, nativeSnapshot: projection)
    let route = MacLocalXPCInteractiveMenuRuntimeRouteV1(sender: sender)
    let context = try InteractiveSessionCommandContextV0(deviceID: deviceID, clientID: UUID(), deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4), grantRevision: .init(rawValue: 5), policyRevision: .init(rawValue: 6),
        primaryConnectionID: Data(repeating: 2, count: 16), hostID: hostID, hostFingerprint: Data(repeating: 3, count: 32),
        hostState: .userSessionActive, wallNowUnixMilliseconds: 1_724_000_000_000, monotonicNowMilliseconds: now / 1_000_000)
    let value = try #require(await route.snapshot(fence: fence, context: context))
    #expect(value.logicalWidthPoints == 2560 && value.logicalHeightPoints == 1440)
    #expect(value.rotation == .degrees90)
    #expect(Int(value.logicalWidthPoints) != value.surface.encodedWidth)
    #expect(value.binding.controlGeneration == install.commandID)
    #expect(value.binding.expiresAtMonotonicMilliseconds == install.sessionDeadlineMonotonicNanoseconds / 1_000_000)
    #expect(value.binding.expiresAtMonotonicMilliseconds > lease.expiresAtMonotonicNanoseconds / 1_000_000)
    #expect(value.binding.clientID == context.clientID && value.binding.primaryConnectionID == context.primaryConnectionID)
    #expect(value.binding.hostFingerprint == context.hostFingerprint)
    #expect(value.selectedDisplayID == displayID && value.visibleMenuAppGeneration == installed.menuAppGeneration)
    let backend = try await route.makeBackend(snapshot: value)
    #expect(await backend.isActive(operationID: UUID()) == false)
}
#endif
