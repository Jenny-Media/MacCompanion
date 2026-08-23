import CompanionNetworkPlatform
import Dispatch
import Foundation

private final class AgentNetworkPrimaryTerminationLatchV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var reason: NetworkHostPrimaryTerminationReasonV0?
    private var activated = false

    /// Returns a terminal event that won the race with activation. Once this
    /// call succeeds without a reason, later terminal events belong to the
    /// active generation and are delivered through the actor callback.
    func activate() -> NetworkHostPrimaryTerminationReasonV0? {
        lock.withLock {
            activated = true
            return reason
        }
    }

    /// Returns `true` only when the generation was already activated and the
    /// actor must retire it. Pre-activation events are consumed by `activate`.
    func record(_ reason: NetworkHostPrimaryTerminationReasonV0) -> Bool {
        lock.withLock {
            if self.reason == nil { self.reason = reason }
            return activated
        }
    }
}

public protocol AgentNetworkAcceptedConnectionStartingV1: Sendable {
    func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable (
            NetworkHostVerifiedReadyConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void
    ) throws

    func cancel()
}

public protocol AgentNetworkBoundPrimaryConnectionV1: Sendable {
    func begin() async throws
    func cancel() async
}

public protocol AgentNetworkPrimaryConnectionBindingV1: Sendable {
    func bindPrimaryConnection(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundPrimaryConnectionV1
}

public struct AgentNetworkListenerHandoffSnapshotV1:
    Equatable, Sendable
{
    public let isCancelled: Bool
    public let hasPendingTLS: Bool
    public let isBinding: Bool
    public let hasActivePrimary: Bool

    public init(
        isCancelled: Bool,
        hasPendingTLS: Bool,
        isBinding: Bool,
        hasActivePrimary: Bool
    ) {
        self.isCancelled = isCancelled
        self.hasPendingTLS = hasPendingTLS
        self.isBinding = isBinding
        self.hasActivePrimary = hasActivePrimary
    }
}

/// Owns one newest accepted TLS candidate and one active primary connection.
/// Every callback is generation-bound so late readiness or termination cannot
/// replace or close a newer owner.
public actor AgentNetworkListenerHandoffV1 {
    private struct Pending {
        let token: UUID
        let accepted: any AgentNetworkAcceptedConnectionStartingV1
        let acceptedAtMonotonicMilliseconds: UInt64
    }

    private struct Active {
        let token: UUID
        let connection: any AgentNetworkBoundPrimaryConnectionV1
    }

    private let binder: any AgentNetworkPrimaryConnectionBindingV1
    private let queue: DispatchQueue
    private let context: @Sendable () -> NetworkHostRequestContextV0
    private let acceptedTerminal: @Sendable (
        NetworkHostAcceptedConnectionTerminationReasonV0
    ) -> Void
    private let primaryTerminal: @Sendable (
        NetworkHostPrimaryTerminationReasonV0
    ) -> Void
    private var cancelled = false
    private var admissionOpen = true
    private var pending: Pending?
    private var bindingToken: UUID?
    private var active: Active?
    private var stateRevision: UInt64 = 0
    private var stateChanged: @Sendable (UInt64) -> Void = { _ in }

    public init(
        binder: any AgentNetworkPrimaryConnectionBindingV1,
        queue: DispatchQueue,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) {
        self.binder = binder
        self.queue = queue
        self.context = context
        self.acceptedTerminal = acceptedTerminal
        self.primaryTerminal = primaryTerminal
    }

    package func setStateChanged(
        _ stateChanged: @escaping @Sendable (UInt64) -> Void
    ) {
        self.stateChanged = stateChanged
    }

    public func admit(
        _ accepted: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds: UInt64
    ) throws {
        guard !cancelled, admissionOpen else {
            accepted.cancel()
            return
        }
        pending?.accepted.cancel()
        pending = nil
        bindingToken = nil

        let token = UUID()
        pending = Pending(
            token: token,
            accepted: accepted,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds
        )
        notifyStateChanged()
        do {
            try accepted.start(
                queue: queue,
                ready: { [weak self] verified in
                    Task { await self?.ready(verified, token: token) }
                },
                terminal: { [weak self] reason in
                    Task {
                        await self?.acceptedEnded(reason, token: token)
                    }
                }
            )
        } catch {
            if pending?.token == token {
                pending = nil
                notifyStateChanged()
            }
            accepted.cancel()
            throw error
        }
    }

    public func cancel() async {
        guard !cancelled else { return }
        cancelled = true
        admissionOpen = false
        let pending = self.pending
        let active = self.active
        self.pending = nil
        bindingToken = nil
        self.active = nil
        pending?.accepted.cancel()
        if let active { await active.connection.cancel() }
        notifyStateChanged()
    }

    /// Stops new transport admission without retiring the active generation.
    /// Pending and in-flight candidates are invalidated before this returns;
    /// a suspended bind can only return into a stale token and is cancelled.
    package func closeAdmission() async {
        guard !cancelled, admissionOpen else { return }
        admissionOpen = false
        let pending = self.pending
        self.pending = nil
        bindingToken = nil
        pending?.accepted.cancel()
        notifyStateChanged()
    }

    /// Retires established work after admission has been closed while keeping
    /// the handoff reusable for an updater recovery path.
    package func drainConnections() async {
        guard !cancelled, !admissionOpen else { return }
        let active = self.active
        self.active = nil
        if let active { await active.connection.cancel() }
        notifyStateChanged()
    }

    package func reopenAdmission() {
        guard !cancelled, !admissionOpen else { return }
        admissionOpen = true
        notifyStateChanged()
    }

    public func snapshot() -> AgentNetworkListenerHandoffSnapshotV1 {
        AgentNetworkListenerHandoffSnapshotV1(
            isCancelled: cancelled,
            hasPendingTLS: pending != nil,
            isBinding: bindingToken != nil,
            hasActivePrimary: active != nil
        )
    }

    private func ready(
        _ verified: NetworkHostVerifiedReadyConnectionV0,
        token: UUID
    ) async {
        guard !cancelled, admissionOpen,
              let pending, pending.token == token else {
            verified.cancel()
            return
        }
        self.pending = nil
        bindingToken = token
        notifyStateChanged()
        let termination = AgentNetworkPrimaryTerminationLatchV1()

        let bound: any AgentNetworkBoundPrimaryConnectionV1
        do {
            bound = try await binder.bindPrimaryConnection(
                verifiedReadyConnection: verified,
                acceptedAtMonotonicMilliseconds:
                    pending.acceptedAtMonotonicMilliseconds,
                context: context,
                terminal: { [weak self] reason in
                    if termination.record(reason) {
                        Task {
                            await self?.primaryEnded(reason, token: token)
                        }
                    }
                }
            )
        } catch {
            if bindingToken == token {
                bindingToken = nil
                notifyStateChanged()
            }
            verified.cancel()
            return
        }

        guard !cancelled, admissionOpen, bindingToken == token else {
            await bound.cancel()
            return
        }
        do {
            try await bound.begin()
        } catch {
            bindingToken = nil
            await bound.cancel()
            notifyStateChanged()
            return
        }
        guard !cancelled, admissionOpen, bindingToken == token else {
            await bound.cancel()
            return
        }
        if let reason = termination.activate() {
            bindingToken = nil
            await bound.cancel()
            notifyStateChanged()
            primaryTerminal(reason)
            return
        }
        let previous = active
        active = Active(token: token, connection: bound)
        bindingToken = nil
        if let previous { await previous.connection.cancel() }
        notifyStateChanged()
    }

    private func acceptedEnded(
        _ reason: NetworkHostAcceptedConnectionTerminationReasonV0,
        token: UUID
    ) {
        guard pending?.token == token else { return }
        pending = nil
        notifyStateChanged()
        acceptedTerminal(reason)
    }

    private func primaryEnded(
        _ reason: NetworkHostPrimaryTerminationReasonV0,
        token: UUID
    ) {
        if bindingToken == token {
            bindingToken = nil
            notifyStateChanged()
            primaryTerminal(reason)
            return
        }
        guard active?.token == token else { return }
        active = nil
        notifyStateChanged()
        primaryTerminal(reason)
    }

    private func notifyStateChanged() {
        guard stateRevision < UInt64.max else { return }
        stateRevision += 1
        stateChanged(stateRevision)
    }
}
