#if os(macOS)
import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
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
    private var commandsStorage:
        [LocalInteractiveInitialDesktopPreparationCommandV1] = []
    private var focusCommandsStorage:
        [LocalInteractiveFocusSnapshotCommandV1] = []

    init(
        receipt: LocalInteractiveInitialDesktopPreparedReceiptV1,
        focusReceipt: LocalInteractiveFocusSnapshotReceiptV1? = nil
    ) {
        self.receipt = receipt
        self.focusReceipt = focusReceipt
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
#endif
