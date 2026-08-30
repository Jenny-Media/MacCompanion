import CompanionAgent
import CompanionInteractiveShared
import Foundation
import OSLog

private let agentInteractiveRoleBindingLoggerV0 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-role-binding"
)

public enum AgentInteractiveRoleDataBindingAuthorityErrorV0:
    Error, Equatable, Sendable
{
    case unavailable
    case invalidGeneration
    case staleGeneration(UInt64)
    case alreadyBound(UInt64)
    case sessionAlreadyActive
    case runtimeFenceMismatch
    case terminal
}

public enum AgentInteractiveRoleDataBindingAuthorityStateV0:
    Equatable, Sendable
{
    case unavailable
    case bound(generation: UInt64)
    case active(generation: UInt64, interactiveSessionID: UUID)
    case terminal
}

public protocol AgentInteractiveRuntimeFenceOwningV0: Sendable {
    func state() async -> AgentInteractiveRuntimeBindingAuthorityStateV1
    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async
}

extension AgentInteractiveRuntimeBindingAuthorityV1:
    AgentInteractiveRuntimeFenceOwningV0 {}

/// Owns the role-socket data pump for the same authenticated menu generation
/// that owns the Interactive runtime. A role pair cannot start merely because
/// its channel proofs passed: the runtime session and menu data route must also
/// match one exact generation and session fence.
public actor AgentInteractiveRoleDataBindingAuthorityV0 {
    private struct Bound: Sendable {
        let generation: UInt64
        let route: any AgentInteractiveMenuRoleDataRoutingV0
    }

    private struct Active: Sendable {
        let token: UUID
        let generation: UInt64
        let pair: AgentInteractiveReadyRolePairV0
        let pump: AgentInteractiveRoleDataPumpV0
        let task: Task<Void, Never>
    }

    private let runtime: any AgentInteractiveRuntimeFenceOwningV0
    private var bound: Bound?
    private var active: Active?
    private var highestGeneration: UInt64 = 0
    private var terminal = false
    private var sequencingTail = Task<Void, Never> {}

    public init(runtime: any AgentInteractiveRuntimeFenceOwningV0) {
        self.runtime = runtime
    }

    public func state() -> AgentInteractiveRoleDataBindingAuthorityStateV0 {
        if terminal { return .terminal }
        if let active {
            return .active(
                generation: active.generation,
                interactiveSessionID: active.pair.interactiveSessionID
            )
        }
        if let bound { return .bound(generation: bound.generation) }
        return .unavailable
    }

    public func bind(
        route: any AgentInteractiveMenuRoleDataRoutingV0,
        generation: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try performBind(route: route, generation: generation)
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func accept(_ pair: AgentInteractiveReadyRolePairV0) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performAccept(pair)
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    @discardableResult
    public func invalidate(generation: UInt64) async -> Bool {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return await performInvalidate(generation: generation)
        }
        sequencingTail = Task { _ = await operation.value }
        return await operation.value
    }

    public func finish() async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await performFinish()
        }
        sequencingTail = operation
        await operation.value
    }

    private func performBind(
        route: any AgentInteractiveMenuRoleDataRoutingV0,
        generation: UInt64
    ) throws {
        guard !terminal else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0.terminal
        }
        guard generation > 0 else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .invalidGeneration
        }
        guard active == nil else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .sessionAlreadyActive
        }
        guard bound == nil else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .alreadyBound(bound!.generation)
        }
        guard generation > highestGeneration else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .staleGeneration(generation)
        }
        highestGeneration = generation
        bound = Bound(generation: generation, route: route)
    }

    private func performAccept(
        _ pair: AgentInteractiveReadyRolePairV0
    ) async throws {
        guard !terminal, let bound else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0.unavailable
        }
        guard active == nil else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .sessionAlreadyActive
        }
        guard case let .active(generation, interactiveSessionID) =
                await runtime.state(),
              generation == bound.generation,
              interactiveSessionID == pair.interactiveSessionID else {
            throw AgentInteractiveRoleDataBindingAuthorityErrorV0
                .runtimeFenceMismatch
        }
        let token = UUID()
        let pump = AgentInteractiveRoleDataPumpV0(
            pair: pair,
            route: bound.route,
            terminal: { _, _ in }
        )
        let task = Task { [weak self] in
            let reason: AgentInteractiveRoleDataPumpErrorV0
            do {
                try await pump.run()
                reason = .remoteClosed
            } catch let value as AgentInteractiveRoleDataPumpErrorV0 {
                reason = value
            } catch {
                reason = .routeFailed
            }
            await self?.pumpFinished(token: token, reason: reason)
        }
        active = Active(
            token: token,
            generation: bound.generation,
            pair: pair,
            pump: pump,
            task: task
        )
    }

    private func performInvalidate(generation: UInt64) async -> Bool {
        guard !terminal, let bound,
              bound.generation == generation else { return false }
        self.bound = nil
        guard let active, active.generation == generation else { return true }
        self.active = nil
        active.task.cancel()
        await active.pump.cancel()
        await runtime.terminate(
            interactiveSessionID: active.pair.interactiveSessionID,
            primaryConnectionID: active.pair.primaryConnectionID,
            reason: .menuAppUnavailable
        )
        return true
    }

    private func performFinish() async {
        guard !terminal else { return }
        terminal = true
        bound = nil
        guard let active else { return }
        self.active = nil
        active.task.cancel()
        await active.pump.cancel()
        await runtime.terminate(
            interactiveSessionID: active.pair.interactiveSessionID,
            primaryConnectionID: active.pair.primaryConnectionID,
            reason: .menuAppUnavailable
        )
    }

    private func pumpFinished(
        token: UUID,
        reason: AgentInteractiveRoleDataPumpErrorV0
    ) async {
        guard let active, active.token == token else { return }
        agentInteractiveRoleBindingLoggerV0.error(
            "interactive role pair ended reason=\(String(describing: reason), privacy: .public)"
        )
        self.active = nil
        await runtime.terminate(
            interactiveSessionID: active.pair.interactiveSessionID,
            primaryConnectionID: active.pair.primaryConnectionID,
            reason: Self.sessionEndReason(for: reason)
        )
    }

    private static func sessionEndReason(
        for reason: AgentInteractiveRoleDataPumpErrorV0
    ) -> InteractiveSessionEndReason {
        switch reason {
        case .remoteClosed, .invalidInputRead, .cancelled:
            .clientDisconnected
        case .mediaSourceClosed, .routeFailed, .sendFailed:
            .menuAppUnavailable
        case .alreadyStarted, .invalidRolePair, .invalidClock,
             .invalidInputFrameLength, .malformedInput,
             .inputFenceMismatch, .mediaPayloadMismatch,
             .mediaFenceMismatch, .mediaSequenceMismatch:
            .protocolViolation
        }
    }
}
