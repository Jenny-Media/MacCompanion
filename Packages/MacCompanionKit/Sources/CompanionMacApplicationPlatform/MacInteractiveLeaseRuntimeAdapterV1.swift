#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionLocalXPCPlatform
import Dispatch
import Foundation

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

    func invalidateAgentAuthority() async throws
    func state() async -> InteractiveMenuRuntimeStateV0
    func nextLeaseDeadlineMonotonicNanoseconds() async -> UInt64?
    func expireLeaseIfRequired(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> Bool
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
    MacLocalXPCInteractiveLeaseHandlingV1
{
    private let runtime: any MacInteractiveMenuRuntimeLeaseOwningV1
    private let desktop: any MacInteractiveInitialDesktopPreparingV1
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
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    public init(
        runtime: InteractiveMenuRuntimeOwnerV0,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1
    ) {
        self.runtime = runtime
        desktop = MacUnavailableInteractiveInitialDesktopPreparerV1()
        expiryScheduler = MacInteractiveSystemLeaseExpirySchedulerV1()
        monotonicClock = MacInteractiveSystemMonotonicClockV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
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
        self.expiryScheduler = expiryScheduler
        self.monotonicClock = monotonicClock
    }

    public func state() -> MacInteractiveLeaseRuntimeAdapterStateV1 {
        stateStorage
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
            try await runtime.renew(
                renewal,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
            try await armExpiry(
                expectedDeadline:
                    renewal.replacement.expiresAtMonotonicNanoseconds
            )
        } catch {
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
            return receipt
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func invalidateAgentAuthority() async {
        guard stateStorage == .available else { return }
        disarmExpiry()
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
