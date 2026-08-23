import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

public enum AgentInteractiveRuntimeBindingAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case invalidGeneration
    case staleGeneration(UInt64)
    case alreadyBound(UInt64)
    case sessionAlreadyActive
    case terminal
}

public enum AgentInteractiveRuntimeBindingAuthorityStateV1:
    Equatable,
    Sendable
{
    case unavailable
    case bound(generation: UInt64)
    case active(generation: UInt64, interactiveSessionID: UUID)
    case terminal
}

/// Stable fail-closed runtime authority installed in the primary dispatcher
/// before local XPC exists. One exact authenticated-and-ready menu generation
/// later binds the sole concrete runtime. Binding, session operations,
/// invalidation, and terminal teardown share one serialization chain.
public actor AgentInteractiveRuntimeBindingAuthorityV1:
    InteractiveSessionRuntimeOwningV0,
    HostInteractiveChannelAuthenticatingV0
{
    private struct Bound: Sendable {
        let generation: UInt64
        let runtime: any InteractiveSessionRuntimeOwningV0
        let channelAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)?
    }

    private struct Active: Sendable {
        let generation: UInt64
        let interactiveSessionID: UUID
        let primaryConnectionID: Data
    }

    private var bound: Bound?
    private var active: Active?
    private var highestGeneration: UInt64 = 0
    private var terminal = false
    private var sequencingTail = Task<Void, Never> {}

    public init() {}

    public func state() -> AgentInteractiveRuntimeBindingAuthorityStateV1 {
        if terminal { return .terminal }
        if let active {
            return .active(
                generation: active.generation,
                interactiveSessionID: active.interactiveSessionID
            )
        }
        if let bound { return .bound(generation: bound.generation) }
        return .unavailable
    }

    public func bind(
        runtime: any InteractiveSessionRuntimeOwningV0,
        generation: UInt64
    ) async throws {
        try await bind(
            runtime: runtime,
            channelAuthenticator: nil,
            generation: generation
        )
    }

    public func bind(
        runtime: any InteractiveSessionRuntimeOwningV0,
        channelAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)?,
        generation: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try performBind(
                runtime: runtime,
                channelAuthenticator: channelAuthenticator,
                generation: generation
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func beginInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        hostNonce: WireBytes32,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelChallengeBody {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let authenticator = bound?.channelAuthenticator else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await authenticator.beginInteractiveChannel(
                hello: hello,
                hostNonce: hostNonce,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func consumeInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        proof: InteractiveChannelProofBody,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelAcceptedBody {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let authenticator = bound?.channelAuthenticator else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await authenticator.consumeInteractiveChannel(
                hello: hello,
                proof: proof,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func invalidateInteractiveChannel(
        channelID: UUID,
        role: InteractiveChannelRoleName
    ) async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let authenticator = bound?.channelAuthenticator else {
                return
            }
            await authenticator.invalidateInteractiveChannel(
                channelID: channelID,
                role: role
            )
        }
        sequencingTail = operation
        await operation.value
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

    public func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInstall(bootstrap, requirement: requirement)
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await performTerminate(
                interactiveSessionID: interactiveSessionID,
                primaryConnectionID: primaryConnectionID,
                reason: reason
            )
        }
        sequencingTail = operation
        await operation.value
    }

    private func performBind(
        runtime: any InteractiveSessionRuntimeOwningV0,
        channelAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)?,
        generation: UInt64
    ) throws {
        guard !terminal else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.terminal
        }
        guard generation > 0 else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                .invalidGeneration
        }
        guard active == nil else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                .sessionAlreadyActive
        }
        guard bound == nil else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                .alreadyBound(bound!.generation)
        }
        guard generation > highestGeneration else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                .staleGeneration(generation)
        }
        highestGeneration = generation
        bound = Bound(
            generation: generation,
            runtime: runtime,
            channelAuthenticator: channelAuthenticator
        )
    }

    private func performInstall(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard !terminal, let selected = bound else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        guard active == nil else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                .sessionAlreadyActive
        }
        let sessionID = bootstrap.acceptedBody.interactiveSessionID.rawValue
        try await selected.runtime.install(
            bootstrap,
            requirement: requirement
        )
        active = Active(
            generation: selected.generation,
            interactiveSessionID: sessionID,
            primaryConnectionID: requirement.command.primaryConnectionID
        )
    }

    private func performTerminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        guard let selected = bound,
              let installed = active,
              installed.generation == selected.generation,
              installed.interactiveSessionID == interactiveSessionID,
              installed.primaryConnectionID == primaryConnectionID else {
            return
        }
        await selected.runtime.terminate(
            interactiveSessionID: interactiveSessionID,
            primaryConnectionID: primaryConnectionID,
            reason: reason
        )
        active = nil
    }

    private func performInvalidate(generation: UInt64) async -> Bool {
        guard !terminal,
              let selected = bound,
              selected.generation == generation else {
            return false
        }
        bound = nil
        if let installed = active,
           installed.generation == generation {
            active = nil
            await selected.runtime.terminate(
                interactiveSessionID: installed.interactiveSessionID,
                primaryConnectionID: installed.primaryConnectionID,
                reason: .menuAppUnavailable
            )
        }
        return true
    }

    private func performFinish() async {
        guard !terminal else { return }
        terminal = true
        let selected = bound
        let installed = active
        bound = nil
        active = nil
        if let selected, let installed,
           installed.generation == selected.generation {
            await selected.runtime.terminate(
                interactiveSessionID: installed.interactiveSessionID,
                primaryConnectionID: installed.primaryConnectionID,
                reason: .menuAppUnavailable
            )
        }
    }
}
