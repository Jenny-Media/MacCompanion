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
    var surfaceTransitionResult:
        Result<InteractiveRuntimeSurfaceTransitionReceiptV0, Error>?
    var invalidationError: Error?
    var invalidations = 0
    var deadline: UInt64?
    var expiryTimes: [UInt64] = []
    var publishesDeadline = true

    func install(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        let receipt = try installResult!.get()
        if publishesDeadline {
            deadline = command.lease.expiresAtMonotonicNanoseconds
        }
        return receipt
    }

    func renew(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws {
        if let renewalError { throw renewalError }
        deadline = renewal.replacement.expiresAtMonotonicNanoseconds
    }

    func revoke(
        _: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        let receipt = try revokeResult!.get()
        deadline = nil
        stateStorage = .idle
        return receipt
    }

    func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        let receipt = try surfaceTransitionResult!.get()
        deadline = command.replacement.expiresAtMonotonicNanoseconds
        return receipt
    }

    func invalidateAgentAuthority() async throws {
        invalidations += 1
        if let invalidationError { throw invalidationError }
        deadline = nil
        stateStorage = .idle
    }

    func state() async -> InteractiveMenuRuntimeStateV0 { stateStorage }

    func nextLeaseDeadlineMonotonicNanoseconds() async -> UInt64? {
        deadline
    }

    func expireLeaseIfRequired(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> Bool {
        expiryTimes.append(nowMonotonicNanoseconds)
        guard let deadline,
              nowMonotonicNanoseconds >= deadline else { return false }
        self.deadline = nil
        stateStorage = .idle
        return true
    }

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

    func configureSurfaceTransition(
        _ result: Result<InteractiveRuntimeSurfaceTransitionReceiptV0, Error>
    ) {
        surfaceTransitionResult = result
    }

    func configureDeadlinePublication(_ value: Bool) {
        publishesDeadline = value
    }

    func invalidationCount() -> Int { invalidations }
    func recordedExpiryTimes() -> [UInt64] { expiryTimes }
}

@available(macOS 26.0, *)
private final class AdapterMonotonicClockV1:
    MacInteractiveMonotonicClockV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) { self.value = value }

    func nowMonotonicNanoseconds() -> UInt64 {
        lock.withLock { value }
    }

    func set(_ value: UInt64) {
        lock.withLock { self.value = value }
    }
}

@available(macOS 26.0, *)
private final class AdapterExpiryCancellationV1:
    MacInteractiveLeaseExpiryCancellationV1,
    @unchecked Sendable
{
    private let cancelAction: @Sendable () -> Void
    init(_ cancelAction: @escaping @Sendable () -> Void) {
        self.cancelAction = cancelAction
    }
    func cancel() { cancelAction() }
}

@available(macOS 26.0, *)
private final class AdapterExpirySchedulerV1:
    MacInteractiveLeaseExpirySchedulingV1,
    @unchecked Sendable
{
    private struct Entry: Sendable {
        let id: UUID
        let delay: UInt64
        let action: @Sendable () async -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var cancelled: Set<UUID> = []

    func schedule(
        afterNanoseconds: UInt64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacInteractiveLeaseExpiryCancellationV1 {
        let entry = Entry(id: UUID(), delay: afterNanoseconds, action: action)
        lock.withLock { entries.append(entry) }
        return AdapterExpiryCancellationV1 { [weak self] in
            guard let self else { return }
            self.lock.withLock { _ = self.cancelled.insert(entry.id) }
        }
    }

    func delays() -> [UInt64] {
        lock.withLock { entries.map(\.delay) }
    }

    func isCancelled(_ index: Int) -> Bool {
        lock.withLock { cancelled.contains(entries[index].id) }
    }

    func fire(_ index: Int, includingCancelled: Bool = false) async {
        let entry = lock.withLock { entries[index] }
        guard includingCancelled || !isCancelled(index) else { return }
        await entry.action()
    }
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
private struct AdapterUnavailableDesktopPreparerV1:
    MacInteractiveInitialDesktopPreparingV1
{
    func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw AdapterRuntimeFailureV1.rejected
    }
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
    let scheduler = AdapterExpirySchedulerV1()
    let clock = AdapterMonotonicClockV1(2_000_000_000)
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: clock
    )

    let receipt = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    #expect(receipt == fixture.receipt)
    #expect(await adapter.state() == .available)
    #expect(scheduler.delays() == [3_000_000_000])
}

@available(macOS 26.0, *)
@Test func interactiveAdapterReschedulesRenewalAndFencesStaleExpiry()
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
    let scheduler = AdapterExpirySchedulerV1()
    let clock = AdapterMonotonicClockV1(2_000_000_000)
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: clock
    )
    _ = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )
    let current = fixture.command.lease
    let replacement = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: current.hostID,
        deviceID: current.deviceID,
        interactiveSessionID: current.interactiveSessionID,
        authorizationEpoch: current.authorizationEpoch,
        selectedDisplayID: current.selectedDisplayID,
        surfaceID: current.surfaceID,
        surfaceRevision: current.surfaceRevision,
        coordinateRevision: current.coordinateRevision,
        allowedInteractionClasses: Set(current.allowedInteractionClasses),
        renewalCounter: 1,
        issuedAtMonotonicNanoseconds: 3_000_000_000,
        expiresAtMonotonicNanoseconds: 8_000_000_000
    )
    let renewal = try InteractiveRuntimeLeaseRenewalV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement
    )
    clock.set(3_000_000_000)
    try await adapter.renewInteractiveLease(
        renewal,
        nowMonotonicNanoseconds: 3_000_000_000
    )

    #expect(scheduler.delays() == [3_000_000_000, 5_000_000_000])
    #expect(scheduler.isCancelled(0))
    await scheduler.fire(0, includingCancelled: true)
    #expect(await runtime.recordedExpiryTimes().isEmpty)

    clock.set(7_000_000_000)
    await scheduler.fire(1)
    #expect(await runtime.recordedExpiryTimes().isEmpty)
    #expect(scheduler.delays() == [
        3_000_000_000, 5_000_000_000, 1_000_000_000,
    ])

    clock.set(8_000_000_000)
    await scheduler.fire(2)
    #expect(await runtime.recordedExpiryTimes() == [8_000_000_000])
    #expect(await runtime.state() == .idle)
    #expect(await adapter.state() == .available)
}

@available(macOS 26.0, *)
@Test func interactiveAdapterAcceptsTwoConsecutiveLeaseRenewals()
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
    let scheduler = AdapterExpirySchedulerV1()
    let clock = AdapterMonotonicClockV1(2_000_000_000)
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: clock
    )
    _ = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    let initial = fixture.command.lease
    let first = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: initial.hostID,
        deviceID: initial.deviceID,
        interactiveSessionID: initial.interactiveSessionID,
        authorizationEpoch: initial.authorizationEpoch,
        selectedDisplayID: initial.selectedDisplayID,
        surfaceID: initial.surfaceID,
        surfaceRevision: initial.surfaceRevision,
        coordinateRevision: initial.coordinateRevision,
        allowedInteractionClasses: Set(initial.allowedInteractionClasses),
        renewalCounter: 1,
        issuedAtMonotonicNanoseconds: 3_000_000_000,
        expiresAtMonotonicNanoseconds: 9_000_000_000
    )
    clock.set(3_000_000_000)
    try await adapter.renewInteractiveLease(
        InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: initial.leaseID,
            replacement: first
        ),
        nowMonotonicNanoseconds: 3_000_000_000
    )

    let second = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: first.hostID,
        deviceID: first.deviceID,
        interactiveSessionID: first.interactiveSessionID,
        authorizationEpoch: first.authorizationEpoch,
        selectedDisplayID: first.selectedDisplayID,
        surfaceID: first.surfaceID,
        surfaceRevision: first.surfaceRevision,
        coordinateRevision: first.coordinateRevision,
        allowedInteractionClasses: Set(first.allowedInteractionClasses),
        renewalCounter: 2,
        issuedAtMonotonicNanoseconds: 7_000_000_000,
        expiresAtMonotonicNanoseconds: 15_000_000_000
    )
    clock.set(7_000_000_000)
    try await adapter.renewInteractiveLease(
        InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: first.leaseID,
            replacement: second
        ),
        nowMonotonicNanoseconds: 7_000_000_000
    )

    #expect(scheduler.delays() == [
        3_000_000_000, 6_000_000_000, 8_000_000_000,
    ])
    #expect(scheduler.isCancelled(0))
    #expect(scheduler.isCancelled(1))
    #expect(await runtime.recordedExpiryTimes().isEmpty)
    #expect(await runtime.nextLeaseDeadlineMonotonicNanoseconds()
        == 15_000_000_000)
    #expect(await adapter.state() == .available)
}

@available(macOS 26.0, *)
@Test func interactiveAdapterReschedulesSurfaceReplacementLeaseExpiry()
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
    let scheduler = AdapterExpirySchedulerV1()
    let clock = AdapterMonotonicClockV1(2_000_000_000)
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: clock
    )
    _ = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    let current = fixture.command.lease
    let nextSurfaceID = UUID()
    let replacement = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: current.hostID,
        deviceID: current.deviceID,
        interactiveSessionID: current.interactiveSessionID,
        authorizationEpoch: current.authorizationEpoch,
        selectedDisplayID: current.selectedDisplayID,
        surfaceID: nextSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 2),
        allowedInteractionClasses: Set(current.allowedInteractionClasses),
        renewalCounter: 1,
        issuedAtMonotonicNanoseconds: 3_000_000_000,
        expiresAtMonotonicNanoseconds: 5_500_000_000
    )
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: current.interactiveSessionID,
        authorizationEpoch: current.authorizationEpoch,
        surfaceID: nextSurfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(current.allowedInteractionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 3_000,
        expiresAtMonotonicMilliseconds: 5_500
    )
    let transition = try InteractiveRuntimeSurfaceTransitionCommandV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement,
        descriptor: descriptor
    )
    let receipt = try InteractiveRuntimeSurfaceTransitionReceiptV0(
        correlationID: transition.commandID,
        previousLeaseID: current.leaseID,
        replacementLeaseID: replacement.leaseID,
        interactiveSessionID: current.interactiveSessionID,
        surfaceID: nextSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 2),
        mediaSequenceBeforeTransition: 4,
        inputReleased: true,
        captureSourcePrepared: true
    )
    await runtime.configureSurfaceTransition(.success(receipt))
    clock.set(3_000_000_000)

    #expect(try await adapter.prepareInteractiveSurfaceTransition(
        transition,
        nowMonotonicNanoseconds: 3_000_000_000
    ) == receipt)
    #expect(scheduler.delays() == [3_000_000_000, 2_500_000_000])
    #expect(scheduler.isCancelled(0))
    await scheduler.fire(0, includingCancelled: true)
    #expect(await runtime.recordedExpiryTimes().isEmpty)

    clock.set(5_500_000_000)
    await scheduler.fire(1)
    #expect(await runtime.recordedExpiryTimes() == [5_500_000_000])
}

@available(macOS 26.0, *)
@Test func interactiveAdapterRejectsSuccessWithoutExactRuntimeDeadline()
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
    await runtime.configureDeadlinePublication(false)
    let scheduler = AdapterExpirySchedulerV1()
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: AdapterMonotonicClockV1(2_000_000_000)
    )

    await #expect(
        throws: MacInteractiveLeaseRuntimeAdapterErrorV1
            .missingExactLeaseDeadline
    ) {
        try await adapter.installInteractiveLease(
            fixture.command,
            nowMonotonicNanoseconds: 2_000_000_000
        )
    }
    #expect(scheduler.delays().isEmpty)
    #expect(await runtime.invalidationCount() == 1)
    #expect(await adapter.state() == .safetyRecoveryRequired)
}

@available(macOS 26.0, *)
@Test func interactiveAdapterLocalStopDisarmsBeforeRuntimeTeardown()
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
    let scheduler = AdapterExpirySchedulerV1()
    let adapter = MacInteractiveLeaseRuntimeAdapterV1(
        runtime: runtime,
        desktop: AdapterUnavailableDesktopPreparerV1(),
        expiryScheduler: scheduler,
        monotonicClock: AdapterMonotonicClockV1(2_000_000_000)
    )
    _ = try await adapter.installInteractiveLease(
        fixture.command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    try await adapter.stopInteractiveControlLocally()
    #expect(scheduler.isCancelled(0))
    #expect(await runtime.invalidationCount() == 1)
    #expect(await runtime.state() == .idle)
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
