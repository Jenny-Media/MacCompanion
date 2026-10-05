import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import OSLog

private let nativeBindingSnapshotLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.agent", category: "native-binding-snapshot"
)

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
/// invalidation, and terminal teardown share one serialization chain. Exact
/// pending-install fences are forwarded before joining that chain.
public actor AgentInteractiveRuntimeBindingAuthorityV1:
    InteractiveSessionRuntimeOwningV0,
    InteractiveWebRTCNegotiatingV0,
    InteractiveNativeVideoRuntimeProvidingV0,
    HostInteractiveChannelAuthenticatingV0,
    InteractiveSurfaceControlDispatchingV0,
    InteractiveDisplaySelectionDispatchingV1
{
    private struct Bound: Sendable {
        let generation: UInt64
        let runtime: any InteractiveSessionRuntimeOwningV0
        let channelAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)?
        let surfaceControl:
            (any InteractiveSurfaceControlDispatchingV0)?
        let displayControl:
            (any InteractiveDisplaySelectionDispatchingV1)?
        let mediaNegotiation:
            (any InteractiveWebRTCNegotiatingV0)?
        let nativeRuntime: (any InteractiveNativeVideoRuntimeProvidingV0)?
    }

    private struct Active: Equatable, Sendable {
        let generation: UInt64
        let interactiveSessionID: UUID
        let primaryConnectionID: Data
    }

    private var bound: Bound?
    private var active: Active?
    private var nativeRetiring: Active?
    private var nativeSnapshot: (generation: UInt64, value: InteractiveNativeVideoRuntimeSnapshotV0)?
    private var nativeControlBinding: (generation: UInt64, value: InteractiveNativeVideoBindingV0)?
    private struct PendingInstall {
        let token: UUID
        let binding: Active
        let runtime: any InteractiveSessionRuntimeOwningV0
        var fenceTask: Task<Void, Never>?
    }
    private var pendingInstall: PendingInstall?
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

    public func snapshot(fence: InteractiveNativeVideoRequestFenceV0,
        context: InteractiveSessionCommandContextV0) async throws -> InteractiveNativeVideoRuntimeSnapshotV0? {
        nativeSnapshot = nil
        guard !terminal, let selected = bound, let installed = active,
              installed.generation == selected.generation, nativeRetiring != installed,
              installed.interactiveSessionID == fence.interactiveSessionID.rawValue,
              installed.primaryConnectionID == context.primaryConnectionID,
              let runtime = selected.nativeRuntime else {
            nativeBindingSnapshotLoggerV1.error("native snapshot rejected reason=installed-binding-unavailable")
            return nil
        }
        guard let value = try await runtime.snapshot(fence: fence, context: context) else {
            nativeBindingSnapshotLoggerV1.error("native snapshot rejected reason=menu-snapshot-unavailable")
            return nil
        }
        guard !Task.isCancelled,
              !terminal, bound?.generation == selected.generation, active == installed, nativeRetiring != installed,
              value.binding.primaryConnectionID == installed.primaryConnectionID,
              value.binding.interactiveSessionID == installed.interactiveSessionID else {
            nativeBindingSnapshotLoggerV1.error("native snapshot rejected reason=installed-binding-changed")
            return nil
        }
        nativeSnapshot = (selected.generation, value)
        return value
    }

    public func makeBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0) async throws -> any InteractiveNativeVideoEnrollmentBackendV0 {
        guard !terminal, let selected = bound, let installed = active,
              installed.generation == selected.generation, nativeRetiring != installed,
              installed.primaryConnectionID == snapshot.binding.primaryConnectionID,
              installed.interactiveSessionID == snapshot.binding.interactiveSessionID,
              nativeSnapshot?.generation == selected.generation, nativeSnapshot?.value == snapshot,
              let runtime = selected.nativeRuntime else { throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable }
        let backend = try await runtime.makeBackend(snapshot: snapshot)
        guard !Task.isCancelled, !terminal, bound?.generation == selected.generation, active == installed, nativeRetiring != installed,
              nativeSnapshot?.generation == selected.generation, nativeSnapshot?.value == snapshot else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        nativeControlBinding = (selected.generation, snapshot.binding)
        return backend
    }

    public func retainedControlIsCurrent(binding: InteractiveNativeVideoBindingV0,
        context: InteractiveSessionCommandContextV0) async -> Bool {
        guard !terminal, let selected = bound, let installed = active,
              installed.generation == selected.generation, nativeRetiring != installed,
              installed.interactiveSessionID == binding.interactiveSessionID,
              installed.primaryConnectionID == binding.primaryConnectionID,
              nativeControlBinding?.generation == selected.generation, nativeControlBinding?.value == binding,
              binding.hostID == context.hostID, binding.hostFingerprint == context.hostFingerprint,
              binding.clientID == context.clientID, binding.primaryConnectionID == context.primaryConnectionID,
              binding.authorizationEpoch == Int64(context.authorizationEpoch.rawValue),
              binding.grantRevision == Int64(context.grantRevision.rawValue),
              binding.policyRevision == Int64(context.policyRevision.rawValue),
              DispatchTime.now().uptimeNanoseconds / 1_000_000 < binding.expiresAtMonotonicMilliseconds else { return false }
        return true
    }

    public func makeReplacementBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0,
        retained: InteractiveNativeVideoRetainedEnrollmentV1) async throws -> any InteractiveNativeVideoEnrollmentBackendV0 {
        guard !terminal, let selected = bound, let installed = active,
              installed.generation == selected.generation, nativeRetiring != installed,
              installed.primaryConnectionID == snapshot.binding.primaryConnectionID,
              installed.interactiveSessionID == snapshot.binding.interactiveSessionID,
              nativeControlBinding?.generation == selected.generation,
              nativeControlBinding?.value == retained.authority.binding,
              snapshot.binding == retained.authority.binding,
              nativeSnapshot?.generation == selected.generation, nativeSnapshot?.value == snapshot,
              let runtime = selected.nativeRuntime else { throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable }
        let backend = try await runtime.makeReplacementBackend(snapshot: snapshot, retained: retained)
        guard !Task.isCancelled, !terminal, bound?.generation == selected.generation, active == installed, nativeRetiring != installed,
              nativeControlBinding?.generation == selected.generation, nativeControlBinding?.value == snapshot.binding,
              nativeSnapshot?.generation == selected.generation, nativeSnapshot?.value == snapshot else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        return backend
    }

    public func makeOffer(
        fence: InteractiveWebRTCNegotiationFenceV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveWebRTCOfferBodyV0 {
        guard !terminal,
              let selected = bound,
              let installed = active,
              installed.generation == selected.generation,
              installed.interactiveSessionID
                == fence.interactiveSessionID.rawValue,
              installed.primaryConnectionID == context.primaryConnectionID,
              let media = selected.mediaNegotiation else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        let offer = try await media.makeOffer(
            fence: fence, context: context
        )
        guard !terminal,
              bound?.generation == selected.generation,
              active == installed,
              offer.fence == fence else {
            await media.close(
                interactiveSessionID: fence.interactiveSessionID.rawValue
            )
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        return offer
    }

    public func acceptAnswer(
        _ answer: InteractiveWebRTCAnswerBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws {
        guard !terminal,
              let selected = bound,
              let installed = active,
              installed.generation == selected.generation,
              installed.interactiveSessionID
                == answer.fence.interactiveSessionID.rawValue,
              installed.primaryConnectionID == context.primaryConnectionID,
              let media = selected.mediaNegotiation else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        try await media.acceptAnswer(answer, context: context)
        guard !terminal,
              bound?.generation == selected.generation,
              active == installed else {
            await media.close(
                interactiveSessionID:
                    answer.fence.interactiveSessionID.rawValue
            )
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
    }

    public func close(interactiveSessionID: UUID) async {
        await bound?.mediaNegotiation?.close(
            interactiveSessionID: interactiveSessionID
        )
    }

    public func bind(
        runtime: any InteractiveSessionRuntimeOwningV0,
        generation: UInt64
    ) async throws {
        try await bind(
            runtime: runtime,
            channelAuthenticator: nil,
            surfaceControl: nil,
            displayControl: nil,
            mediaNegotiation: nil,
            generation: generation
        )
    }

    public func bind(
        runtime: any InteractiveSessionRuntimeOwningV0,
        channelAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)?,
        surfaceControl:
            (any InteractiveSurfaceControlDispatchingV0)? = nil,
        displayControl:
            (any InteractiveDisplaySelectionDispatchingV1)? = nil,
        mediaNegotiation:
            (any InteractiveWebRTCNegotiatingV0)? = nil,
        nativeRuntime: (any InteractiveNativeVideoRuntimeProvidingV0)? = nil,
        generation: UInt64
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try performBind(
                runtime: runtime,
                channelAuthenticator: channelAuthenticator,
                surfaceControl: surfaceControl,
                displayControl: displayControl,
                mediaNegotiation: mediaNegotiation,
                nativeRuntime: nativeRuntime,
                generation: generation
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func displayCatalog(
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplayCatalogResponseBodyV1 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal,
                  let display = bound?.displayControl,
                  active?.primaryConnectionID == nil
                    || active?.primaryConnectionID
                        == context.primaryConnectionID else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await display.displayCatalog(context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func selectDisplay(
        _ request: InteractiveDisplaySelectBodyV1,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplaySelectedBodyV1 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active == nil,
                  let display = bound?.displayControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await display.selectDisplay(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
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

    public func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.requestInitial(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.acknowledgeInitial(
                request,
                context: context
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.targets(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.select(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.acknowledge(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func primarySessionClosed() async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else { return }
            await control.primarySessionClosed()
        }
        sequencingTail = operation
        await operation.value
    }

    public func currentFocusEventReadiness() async
        -> InteractiveFocusEventReadinessV0?
    {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                return Optional<InteractiveFocusEventReadinessV0>.none
            }
            return await control.currentFocusEventReadiness()
        }
        sequencingTail = Task { _ = await operation.value }
        return await operation.value
    }

    public func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) async throws -> InteractivePreparedFocusEventV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else {
                throw AgentInteractiveRuntimeBindingAuthorityErrorV1
                    .unavailable
            }
            return try await control.prepareFocusEvent(
                candidate: candidate,
                hostContext: hostContext
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func revokePreparedFocusEvent() async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard !terminal, active != nil,
                  let control = bound?.surfaceControl else { return }
            await control.revokePreparedFocusEvent()
        }
        sequencingTail = operation
        await operation.value
    }

    @discardableResult
    public func invalidate(generation: UInt64) async -> Bool {
        if active?.generation == generation { nativeRetiring = active; nativeSnapshot = nil }
        let fence = pendingInstall?.binding.generation == generation
            ? fencePendingInstall(reason: .menuAppUnavailable) : nil
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await fence?.value
            return await performInvalidate(generation: generation)
        }
        sequencingTail = Task { _ = await operation.value }
        return await operation.value
    }

    public func finish() async {
        nativeRetiring = active
        nativeSnapshot = nil
        let fence = fencePendingInstall(reason: .menuAppUnavailable)
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await fence?.value
            await performFinish()
        }
        sequencingTail = operation
        await operation.value
    }

    public func desktopAccessCurrent(sessionID: UUID, primaryConnectionID: Data) async -> Bool {
        guard !terminal, let selected = bound, let installed = active,
              installed.generation == selected.generation, nativeRetiring != installed,
              installed.interactiveSessionID == sessionID, installed.primaryConnectionID == primaryConnectionID else { return false }
        let allowed = await selected.runtime.desktopAccessCurrent(sessionID: sessionID, primaryConnectionID: primaryConnectionID)
        return allowed && !terminal && bound?.generation == selected.generation && active == installed && nativeRetiring != installed
    }

    public func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard !terminal, let selected = bound else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        guard active == nil, pendingInstall == nil else {
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.sessionAlreadyActive
        }
        let pending = PendingInstall(token: UUID(), binding: Active(
            generation: selected.generation,
            interactiveSessionID: bootstrap.acceptedBody.interactiveSessionID.rawValue,
            primaryConnectionID: requirement.command.primaryConnectionID), runtime: selected.runtime)
        pendingInstall = pending
        defer {
            if pendingInstall?.token == pending.token { pendingInstall = nil }
        }
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInstall(bootstrap, requirement: requirement, pending: pending)
        }
        sequencingTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        if let installed = active, installed.interactiveSessionID == interactiveSessionID,
           installed.primaryConnectionID == primaryConnectionID {
            // Native admission fences before queued or platform cleanup waits.
            nativeRetiring = installed
            nativeSnapshot = nil
        }
        let matchesPending = pendingInstall?.binding.interactiveSessionID == interactiveSessionID
            && pendingInstall?.binding.primaryConnectionID == primaryConnectionID
        let fence = matchesPending ? fencePendingInstall(reason: reason) : nil
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await fence?.value
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
        surfaceControl:
            (any InteractiveSurfaceControlDispatchingV0)?,
        displayControl:
            (any InteractiveDisplaySelectionDispatchingV1)?,
        mediaNegotiation:
            (any InteractiveWebRTCNegotiatingV0)?,
        nativeRuntime: (any InteractiveNativeVideoRuntimeProvidingV0)?,
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
            channelAuthenticator: channelAuthenticator,
            surfaceControl: surfaceControl,
            displayControl: displayControl,
            mediaNegotiation: mediaNegotiation,
            nativeRuntime: nativeRuntime
        )
    }

    private func performInstall(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0,
        pending: PendingInstall
    ) async throws {
        guard !terminal, let selected = bound,
              selected.generation == pending.binding.generation,
              pendingInstall?.token == pending.token,
              pendingInstall?.fenceTask == nil else {
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
        if let fence = pendingInstall?.fenceTask {
            await fence.value
            throw AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
        }
        nativeRetiring = nil
        nativeSnapshot = nil
        active = Active(
            generation: selected.generation,
            interactiveSessionID: sessionID,
            primaryConnectionID: requirement.command.primaryConnectionID
        )
    }

    /// Starts exact pending termination outside the serialization tail. The
    /// lower runtime fences synchronously before it waits for that install;
    /// putting this call behind the install would defeat the fence.
    private func fencePendingInstall(
        reason: InteractiveSessionEndReason
    ) -> Task<Void, Never>? {
        guard let pending = pendingInstall else { return nil }
        if let task = pending.fenceTask { return task }
        let task = Task {
            await pending.runtime.terminate(
                interactiveSessionID: pending.binding.interactiveSessionID,
                primaryConnectionID: pending.binding.primaryConnectionID,
                reason: reason)
        }
        pendingInstall?.fenceTask = task
        return task
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
