#if os(macOS)
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveRuntime
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import Dispatch
import Foundation
import OSLog

private let macInteractiveLeaseRuntimeLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion",
    category: "interactive-lease-runtime"
)

public enum MacInteractiveLeaseRuntimeAdapterErrorV1:
    Error,
    Equatable,
    Sendable
{
    case safetyRecoveryRequired
    case missingExactLeaseDeadline
}

public enum MacInteractiveLeaseRuntimeAdapterStateV1:
    Equatable,
    Sendable
{
    case available
    case safetyRecoveryRequired
}

public protocol MacInteractiveInitialDesktopPreparingV1: Sendable {
    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1
}

public protocol MacInteractiveLeaseExpiryCancellationV1: Sendable {
    func cancel()
}

public protocol MacInteractiveLeaseExpirySchedulingV1: Sendable {
    func schedule(
        afterNanoseconds: UInt64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacInteractiveLeaseExpiryCancellationV1
}

public protocol MacInteractiveMonotonicClockV1: Sendable {
    func nowMonotonicNanoseconds() -> UInt64
}

private final class MacInteractiveSystemLeaseExpiryCancellationV1:
    MacInteractiveLeaseExpiryCancellationV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        let task = lock.withLock {
            defer { self.task = nil }
            return self.task
        }
        task?.cancel()
    }
}

public struct MacInteractiveSystemLeaseExpirySchedulerV1:
    MacInteractiveLeaseExpirySchedulingV1
{
    public init() {}

    public func schedule(
        afterNanoseconds: UInt64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacInteractiveLeaseExpiryCancellationV1 {
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: afterNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
        return MacInteractiveSystemLeaseExpiryCancellationV1(task: task)
    }
}

public struct MacInteractiveSystemMonotonicClockV1:
    MacInteractiveMonotonicClockV1
{
    public init() {}

    public func nowMonotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

private struct MacUnavailableInteractiveInitialDesktopPreparerV1:
    MacInteractiveInitialDesktopPreparingV1
{
    func prepareInitialInteractiveDesktop(
        _: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
}

package protocol MacInteractiveMenuRuntimeLeaseOwningV1: Sendable {
    func install(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renew(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws

    func revoke(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0

    func prepareSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0
    func pauseInputForFocusChange(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> Bool
    func acknowledgeSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    func terminateSurfaceFailure(
        interactiveSessionID: UUID
    ) async throws -> Bool

    func invalidateAgentAuthority() async throws
    func postInputEnvelope(
        _ envelope: InteractiveInputEnvelope,
        nowMonotonicNanoseconds: UInt64
    ) async throws
    func state() async -> InteractiveMenuRuntimeStateV0
    func nextLeaseDeadlineMonotonicNanoseconds() async -> UInt64?
    func expireLeaseIfRequired(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> Bool
}

extension MacInteractiveMenuRuntimeLeaseOwningV1 {
    package func postInputEnvelope(
        _: InteractiveInputEnvelope,
        nowMonotonicNanoseconds _: UInt64
    ) async throws {
        throw MacLocalXPCInteractiveRoleDataErrorV1.unavailable
    }

    package func prepareSurfaceTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func pauseInputForFocusChange(
        _: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> Bool {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func acknowledgeSurface(
        _: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
    package func terminateSurfaceFailure(
        interactiveSessionID _: UUID
    ) async throws -> Bool {
        throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
    }
}

extension InteractiveMenuRuntimeOwnerV0:
    MacInteractiveMenuRuntimeLeaseOwningV1
{}

/// Narrow menu-process bridge from the authenticated local-XPC receiver into
/// the single serialized Interactive runtime owner. It owns no endpoint and
/// no capture/input authority itself. If connection-loss cleanup cannot prove
/// completion, this adapter latches closed for the rest of its lifetime.
@available(macOS 26.0, *)
public actor MacInteractiveLeaseRuntimeAdapterV1:
    MacLocalXPCInteractiveLeaseHandlingV1,
    MacLocalXPCInteractiveInputHandlingV1
{
    private let runtime: any MacInteractiveMenuRuntimeLeaseOwningV1
    private let desktop: any MacInteractiveInitialDesktopPreparingV1
    private let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1?
    private let displaySelection: MacInteractiveOpaqueDisplaySelectionV1?
    private let updateSelectedDisplay:
        (@Sendable (UUID?) async throws -> Void)?
    private let expiryScheduler:
        any MacInteractiveLeaseExpirySchedulingV1
    private let monotonicClock: any MacInteractiveMonotonicClockV1
    private var stateStorage:
        MacInteractiveLeaseRuntimeAdapterStateV1 = .available
    private var expiryCancellation:
        (any MacInteractiveLeaseExpiryCancellationV1)?
    private var expiryToken: UUID?

    public init(runtime: InteractiveMenuRuntimeOwnerV0) {
        self.runtime = runtime
        desktop = MacUnavailableInteractiveInitialDesktopPreparerV1()
        surfaceTargets = nil
        displaySelection = nil
        updateSelectedDisplay = nil
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    public init(
        runtime: InteractiveMenuRuntimeOwnerV0,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
        surfaceTargets = nil
        displaySelection = nil
        updateSelectedDisplay = nil
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    public init(
        runtime: InteractiveMenuRuntimeOwnerV0,
        desktop: any MacInteractiveInitialDesktopPreparingV1,
        surfaceTargets: MacInteractiveSurfaceTargetOwnerV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
        self.surfaceTargets = surfaceTargets
        displaySelection = nil
        updateSelectedDisplay = nil
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1
    ) {
        self.runtime = runtime
        desktop = MacUnavailableInteractiveInitialDesktopPreparerV1()
        surfaceTargets = nil
        displaySelection = nil
        updateSelectedDisplay = nil
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
        surfaceTargets = nil
        displaySelection = nil
        updateSelectedDisplay = nil
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1,
        desktop: any MacInteractiveInitialDesktopPreparingV1,
        expiryScheduler: any MacInteractiveLeaseExpirySchedulingV1,
        monotonicClock: any MacInteractiveMonotonicClockV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
        surfaceTargets = nil
        displaySelection = nil
        updateSelectedDisplay = nil
        self.expiryScheduler = expiryScheduler
        self.monotonicClock = monotonicClock
    }

    public init(
        runtime: InteractiveMenuRuntimeOwnerV0,
        desktop: any MacInteractiveInitialDesktopPreparingV1,
        surfaceTargets: MacInteractiveSurfaceTargetOwnerV1?,
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1,
        updateSelectedDisplay:
            @escaping @Sendable (UUID?) async throws -> Void
    ) {
        self.runtime = runtime
        self.desktop = desktop
        self.surfaceTargets = surfaceTargets
        self.displaySelection = displaySelection
        self.updateSelectedDisplay = updateSelectedDisplay
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    public func state() -> MacInteractiveLeaseRuntimeAdapterStateV1 {
        stateStorage
    }

    public func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        try requireAvailable()
        try await runtime.postInputEnvelope(
            envelope,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
    }

    public func interactiveDisplayCatalog(
        _ command: LocalInteractiveDisplayCatalogCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try requireAvailable()
        let runtimeState = await runtime.state()
        guard Self.allowsDisplayCatalog(runtimeState),
              let displaySelection,
              let selectedDisplayID =
                displaySelection.opaqueSelectedDisplayID() else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let choices = displaySelection.availableDisplays()
        let candidates = try choices.enumerated().map { index, choice in
            guard index < Int(UInt8.max),
                  choice.pixelWidth <= Int(UInt16.max),
                  choice.pixelHeight <= Int(UInt16.max) else {
                throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
            }
            return try LocalInteractiveDisplayCandidateV1(
                displayID: choice.id,
                ordinal: UInt8(index + 1),
                pixelWidth: UInt16(choice.pixelWidth),
                pixelHeight: UInt16(choice.pixelHeight),
                isMain: choice.isMain
            )
        }
        return try LocalInteractiveDisplayCatalogReceiptV1(
            correlationID: command.commandID,
            selectedDisplayID: selectedDisplayID,
            candidates: candidates
        )
    }

    public func selectInteractiveDisplay(
        _ command: LocalInteractiveDisplaySelectCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try requireAvailable()
        let runtimeState = await runtime.state()
        guard Self.allowsDisplaySelection(runtimeState),
              let displaySelection,
              let updateSelectedDisplay,
              let previous = displaySelection.opaqueSelectedDisplayID()
        else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        if previous != command.displayID {
            do {
                try displaySelection.selectDisplay(id: command.displayID)
                if case .active = runtimeState, let surfaceTargets {
                    try await surfaceTargets.retargetDesktop(
                        physicalDisplayID: displaySelection
                            .resolvePhysicalDisplayID(
                                selectedDisplayID: command.displayID
                            )
                    )
                }
                try await updateSelectedDisplay(command.displayID)
            } catch {
                try? displaySelection.selectDisplay(id: previous)
                if case .active = runtimeState, let surfaceTargets,
                   let previousPhysical = try? displaySelection
                    .resolvePhysicalDisplayID(selectedDisplayID: previous) {
                    try? await surfaceTargets.retargetDesktop(
                        physicalDisplayID: previousPhysical
                    )
                }
                throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
            }
        }
        guard displaySelection.opaqueSelectedDisplayID()
                == command.displayID else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        return LocalInteractiveDisplaySelectedReceiptV1(
            correlationID: command.commandID,
            selectedDisplayID: command.displayID
        )
    }

    private static func allowsDisplayCatalog(
        _ state: InteractiveMenuRuntimeStateV0
    ) -> Bool {
        switch state {
        case .idle, .active: true
        case .installing, .terminating, .safetyRecoveryRequired: false
        }
    }

    private static func allowsDisplaySelection(
        _ state: InteractiveMenuRuntimeStateV0
    ) -> Bool {
        switch state {
        case .idle, .active: true
        case .installing, .terminating, .safetyRecoveryRequired: false
        }
    }

    public func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try requireAvailable()
        return try await desktop.prepareInitialInteractiveDesktop(
            command,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
    }

    public func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try requireAvailable()
        do {
            let receipt = try await runtime.install(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
            try await armExpiry(
                expectedDeadline:
                    command.lease.expiresAtMonotonicNanoseconds
            )
            return receipt
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        try requireAvailable()
        do {
            macInteractiveLeaseRuntimeLoggerV1.notice(
                "menu renewal runtime started counter=\(renewal.replacement.renewalCounter, privacy: .public)"
            )
            try await runtime.renew(
                renewal,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
            try await armExpiry(
                expectedDeadline:
                    renewal.replacement.expiresAtMonotonicNanoseconds
            )
            macInteractiveLeaseRuntimeLoggerV1.notice(
                "menu renewal expiry armed counter=\(renewal.replacement.renewalCounter, privacy: .public)"
            )
        } catch {
            macInteractiveLeaseRuntimeLoggerV1.error(
                "menu renewal failed counter=\(renewal.replacement.renewalCounter, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try requireAvailable()
        do {
            let receipt = try await runtime.revoke(command)
            disarmExpiry()
            await surfaceTargets?.invalidate()
            return receipt
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try requireAvailable()
        guard let surfaceTargets,
              nowMonotonicNanoseconds / 1_000_000 <= UInt64(Int64.max) else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let snapshot = try await surfaceTargets.snapshot(
            interactiveSessionID: command.interactiveSessionID,
            authorizationEpoch: command.authorizationEpoch,
            nowMonotonicMilliseconds: Int64(
                nowMonotonicNanoseconds / 1_000_000
            )
        )
        let receipt = try LocalInteractiveSurfaceTargetsReceiptV1(
            correlationID: command.commandID,
            snapshot: snapshot
        )
        try receipt.validate(against: command)
        return receipt
    }

    public func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try requireAvailable()
        guard let surfaceTargets,
              nowMonotonicNanoseconds / 1_000_000 <= UInt64(Int64.max) else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        let descriptor = try await surfaceTargets.resolve(
            command,
            nowMonotonicMilliseconds: Int64(
                nowMonotonicNanoseconds / 1_000_000
            )
        )
        let receipt = try LocalInteractiveSurfaceResolvedReceiptV1(
            correlationID: command.commandID,
            descriptor: descriptor
        )
        try receipt.validate(against: command)
        return receipt
    }

    public func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try requireAvailable()
        do {
            let receipt = try await runtime.prepareSurfaceTransition(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
            try await armExpiry(
                expectedDeadline:
                    command.replacement.expiresAtMonotonicNanoseconds
            )
            return receipt
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try requireAvailable()
        do {
            return try await runtime.acknowledgeSurface(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try requireAvailable()
        let terminated = try await runtime.terminateSurfaceFailure(
            interactiveSessionID: command.interactiveSessionID
        )
        if terminated {
            disarmExpiry()
            await surfaceTargets?.invalidate()
        }
        return try LocalInteractiveSurfaceFailureReceiptV1(
            correlationID: command.commandID,
            interactiveSessionID: command.interactiveSessionID,
            terminated: terminated
        )
    }

    public func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        try requireAvailable()
        guard let surfaceTargets else {
            throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
        }
        var projection = try await surfaceTargets.focusCandidate(
            command,
            inputPaused: false
        )
        if projection.requiresInputPause {
            guard try await runtime.pauseInputForFocusChange(command) else {
                throw MacLocalXPCInteractiveLeaseErrorV1.unavailable
            }
            let value = projection.candidate
            let paused = try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: value.recommendedTargetKind,
                focus: value.focus,
                inputPaused: true,
                reason: value.reason,
                validForMilliseconds: value.validForMilliseconds
            )
            projection = MacInteractiveFocusCandidateProjectionV1(
                candidate: paused,
                requiresInputPause: true
            )
        }
        let value = projection.candidate
        let candidate = try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: value.recommendedTargetKind,
            focus: value.focus,
            inputPaused: value.inputPaused,
            reason: value.reason,
            validForMilliseconds: value.validForMilliseconds
        )
        let receipt = LocalInteractiveFocusSnapshotReceiptV1(
            correlationID: command.commandID,
            command: command,
            candidate: candidate
        )
        try receipt.validate(against: command)
        return receipt
    }

    public func invalidateAgentAuthority() async {
        guard stateStorage == .available else { return }
        disarmExpiry()
        await surfaceTargets?.invalidate()
        do {
            try await runtime.invalidateAgentAuthority()
            await latchIfRuntimeRequiresSafetyRecovery()
        } catch {
            stateStorage = .safetyRecoveryRequired
        }
    }

    public func stopInteractiveControlLocally() async throws {
        try requireAvailable()
        disarmExpiry()
        await surfaceTargets?.invalidate()
        do {
            try await runtime.invalidateAgentAuthority()
            await latchIfRuntimeRequiresSafetyRecovery()
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    private func requireAvailable() throws {
        guard stateStorage == .available else {
            throw MacInteractiveLeaseRuntimeAdapterErrorV1
                .safetyRecoveryRequired
        }
    }

    private func latchIfRuntimeRequiresSafetyRecovery() async {
        if case .safetyRecoveryRequired = await runtime.state() {
            stateStorage = .safetyRecoveryRequired
            disarmExpiry()
        }
    }

    private func armExpiry(expectedDeadline: UInt64) async throws {
        guard await runtime.nextLeaseDeadlineMonotonicNanoseconds()
                == expectedDeadline else {
            disarmExpiry()
            stateStorage = .safetyRecoveryRequired
            try? await runtime.invalidateAgentAuthority()
            throw MacInteractiveLeaseRuntimeAdapterErrorV1
                .missingExactLeaseDeadline
        }
        disarmExpiry()
        let token = UUID()
        expiryToken = token
        let now = monotonicClock.nowMonotonicNanoseconds()
        let delay = expectedDeadline > now ? expectedDeadline - now : 0
        expiryCancellation = expiryScheduler.schedule(
            afterNanoseconds: delay
        ) { [weak self] in
            await self?.expire(
                token: token,
                expectedDeadline: expectedDeadline
            )
        }
    }

    private func expire(token: UUID, expectedDeadline: UInt64) async {
        guard stateStorage == .available,
              expiryToken == token,
              await runtime.nextLeaseDeadlineMonotonicNanoseconds()
                == expectedDeadline else { return }
        expiryCancellation = nil
        let now = monotonicClock.nowMonotonicNanoseconds()
        if now < expectedDeadline {
            expiryCancellation = expiryScheduler.schedule(
                afterNanoseconds: expectedDeadline - now
            ) { [weak self] in
                await self?.expire(
                    token: token,
                    expectedDeadline: expectedDeadline
                )
            }
            return
        }
        expiryToken = nil
        do {
            _ = try await runtime.expireLeaseIfRequired(
                nowMonotonicNanoseconds: now
            )
            await latchIfRuntimeRequiresSafetyRecovery()
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
        }
    }

    private func disarmExpiry() {
        expiryToken = nil
        expiryCancellation?.cancel()
        expiryCancellation = nil
    }
}
#endif
