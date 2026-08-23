#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionLocalXPCPlatform
import Foundation

public enum MacInteractiveLeaseRuntimeAdapterErrorV1:
    Error,
    Equatable,
    Sendable
{
    case safetyRecoveryRequired
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
    private var stateStorage:
        MacInteractiveLeaseRuntimeAdapterStateV1 = .available

    public init(runtime: InteractiveMenuRuntimeOwnerV0) {
        self.runtime = runtime
        desktop = MacUnavailableInteractiveInitialDesktopPreparerV1()
    }

    public init(
        runtime: InteractiveMenuRuntimeOwnerV0,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1
    ) {
        self.runtime = runtime
        desktop = MacUnavailableInteractiveInitialDesktopPreparerV1()
    }

    package init(
        runtime: any MacInteractiveMenuRuntimeLeaseOwningV1,
        desktop: any MacInteractiveInitialDesktopPreparingV1
    ) {
        self.runtime = runtime
        self.desktop = desktop
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
            return try await runtime.install(
                command,
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
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
            return try await runtime.revoke(command)
        } catch {
            await latchIfRuntimeRequiresSafetyRecovery()
            throw error
        }
    }

    public func invalidateAgentAuthority() async {
        guard stateStorage == .available else { return }
        do {
            try await runtime.invalidateAgentAuthority()
            await latchIfRuntimeRequiresSafetyRecovery()
        } catch {
            stateStorage = .safetyRecoveryRequired
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
        }
    }
}
#endif
