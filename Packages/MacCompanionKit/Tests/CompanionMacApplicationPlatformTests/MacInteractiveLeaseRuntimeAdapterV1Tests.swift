#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

@available(macOS 26.0, *)
private actor AdapterRuntimeV1:
    MacInteractiveMenuRuntimeLeaseOwningV1
{
    var stateStorage: InteractiveMenuRuntimeStateV0 = .idle
    var installResult: Result<InteractiveRuntimeInstallReceiptV0, Error>?
    var renewalError: Error?
    var revokeResult: Result<InteractiveRuntimeRevokedReceiptV0, Error>?
    var invalidationError: Error?
    var invalidations = 0

    func install(
        _: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try installResult!.get()
    }

    func renew(
        _: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws {
        if let renewalError { throw renewalError }
    }

    func revoke(
        _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try revokeResult!.get()
    }

    func invalidateAgentAuthority() async throws {
        invalidations += 1
        if let invalidationError { throw invalidationError }
        stateStorage = .idle
    }

    func state() async -> InteractiveMenuRuntimeStateV0 { stateStorage }

    func configureInstall(
        _ result: Result<InteractiveRuntimeInstallReceiptV0, Error>,
        state: InteractiveMenuRuntimeStateV0
    ) {
        installResult = result
        stateStorage = state
    }

    func configureInvalidation(error: Error?) {
        invalidationError = error
    }

    func invalidationCount() -> Int { invalidations }
}

@available(macOS 26.0, *)
private enum AdapterRuntimeFailureV1: Error {
    case rejected
    case cleanupFailed
}

@available(macOS 26.0, *)
private actor AdapterDesktopPreparerV1:
    MacInteractiveInitialDesktopPreparingV1
{
    let receipt: LocalInteractiveInitialDesktopPreparedReceiptV1
    private var commandsStorage:
        [LocalInteractiveInitialDesktopPreparationCommandV1] = []
    private var timesStorage: [UInt64] = []

    init(receipt: LocalInteractiveInitialDesktopPreparedReceiptV1) {
        self.receipt = receipt
    }

    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        commandsStorage.append(command)
        timesStorage.append(nowMonotonicNanoseconds)
        return receipt
    }

    func commands()
        -> [LocalInteractiveInitialDesktopPreparationCommandV1] {
        commandsStorage
    }

    func times() -> [UInt64] { timesStorage }
}

@available(macOS 26.0, *)
@Test func interactiveAdapterForwardsInitialDesktopToExactPreparer()
    async throws
{
    let fixture = try interactiveAdapterFixtureV1()
    let command = try LocalInteractiveInitialDesktopPreparationCommandV1(
        commandID: UUID(),
        interactiveSessionID: fixture.command.lease.interactiveSessionID,
        authorizationEpoch: fixture.command.lease.authorizationEpoch,
        selectedDisplayID: fixture.command.lease.selectedDisplayID,
        interactionClasses:
            Set(fixture.command.lease.allowedInteractionClasses)
    )
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: command.interactiveSessionID,
        authorizationEpoch: command.authorizationEpoch,
        surfaceID: fixture.command.lease.surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(command.interactionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000
    )
    let expected = try LocalInteractiveInitialDesktopPreparedReceiptV1(
        correlationID: command.commandID,
        descriptor: descriptor
    )
    let desktop = AdapterDesktopPreparerV1(receipt: expected)
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: AdapterRuntimeV1(),
        desktop: desktop
    )

    let receipt = try await adapter.prepareInitialInteractiveDesktop(
        command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    #expect(receipt == expected)
    #expect(await desktop.commands() == [command])
    #expect(await desktop.times() == [2_000_000_000])
}

@available(macOS 26.0, *)
@Test func interactiveAdapterForwardsInstallWithoutInventingRecovery()
    async throws
{
    let fixture = try interactiveAdapterFixtureV1()
    let runtime = AdapterRuntimeV1()
    await runtime.configureInstall(
        .success(fixture.receipt),
        state: .active(
            interactiveSessionID:
                fixture.command.lease.interactiveSessionID,
            leaseID: fixture.command.lease.leaseID
        )
    )
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime)

    let receipt = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    #expect(receipt == fixture.receipt)
    #expect(await adapter.state() == .available)
}

@available(macOS 26.0, *)
@Test func interactiveAdapterLatchesRuntimeSafetyRecovery() async throws {
    let fixture = try interactiveAdapterFixtureV1()
    let runtime = AdapterRuntimeV1()
    await runtime.configureInstall(
        .failure(AdapterRuntimeFailureV1.rejected),
        state: .safetyRecoveryRequired(
            interactiveSessionID:
                fixture.command.lease.interactiveSessionID,
            leaseID: fixture.command.lease.leaseID
        )
    )
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime)

    await #expect(throws: AdapterRuntimeFailureV1.self) {
        try await adapter.installInteractiveLease(
            fixture.command,
            nowMonotonicNanoseconds: 2_000_000_000
        )
    }
    #expect(await adapter.state() == .safetyRecoveryRequired)
    await #expect(
        throws: MacInteractiveLeaseRuntimeAdapterErrorV1
            .safetyRecoveryRequired
    ) {
        try await adapter.installInteractiveLease(
            fixture.command,
            nowMonotonicNanoseconds: 2_000_000_000
        )
    }
}

@available(macOS 26.0, *)
@Test func interactiveAdapterLatchesAmbiguousConnectionLossCleanup()
    async throws
{
    let runtime = AdapterRuntimeV1()
    await runtime.configureInvalidation(
        error: AdapterRuntimeFailureV1.cleanupFailed
    )
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime)

    await adapter.invalidateAgentAuthority()
    await adapter.invalidateAgentAuthority()

    #expect(await adapter.state() == .safetyRecoveryRequired)
    #expect(await runtime.invalidationCount() == 1)
}

@available(macOS 26.0, *)
private func interactiveAdapterFixtureV1() throws -> (
    command: InteractiveRuntimeInstallCommandV0,
    receipt: InteractiveRuntimeInstallReceiptV0
) {
    let sessionID = UUID()
    let displayID = UUID()
    let lease = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: UUID(),
        deviceID: UUID(),
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        selectedDisplayID: displayID,
        surfaceID: UUID(),
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view],
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000_000_000,
        expiresAtMonotonicNanoseconds: 5_000_000_000
    )
    let command = try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(),
        lease: lease,
        deviceDisplayName: try .init("Test iPhone"),
        surfaceDescriptor: AdaptiveSurfaceDescriptor(
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1),
            surfaceID: lease.surfaceID,
            kind: .desktop,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: 100,
            encodedHeight: 100,
            logicalWidthPoints: 100,
            logicalHeightPoints: 100,
            interactionClasses: [.view],
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1_000,
            expiresAtMonotonicMilliseconds: 5_000
        ),
        sessionDeadlineMonotonicNanoseconds: 6_000_000_000
    )
    let receipt = try InteractiveRuntimeInstallReceiptV0(
        correlationID: command.commandID,
        leaseID: lease.leaseID,
        interactiveSessionID: sessionID,
        selectedDisplayID: displayID,
        menuAppGeneration: UUID(),
        menuAppRevision: 1,
        readyInteractionClasses: [.view],
        indicatorVisible: true
    )
    return (command, receipt)
}
#endif
