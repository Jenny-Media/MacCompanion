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
    private var commandsStorage:
        [LocalInteractiveInitialDesktopPreparationCommandV1] = []

    init(receipt: LocalInteractiveInitialDesktopPreparedReceiptV1) {
        self.receipt = receipt
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

    func commands()
        -> [LocalInteractiveInitialDesktopPreparationCommandV1] {
        commandsStorage
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
#endif
