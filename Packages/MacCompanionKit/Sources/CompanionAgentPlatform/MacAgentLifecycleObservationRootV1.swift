import CompanionAgent
import CompanionMacApp
import Foundation

public enum MacAgentLifecycleObservationRootErrorV1:
    Error, Equatable, Sendable
{
    case agentBootstrapRejected(
        MacLifecycleProcessObservationDispositionV1
    )
    case menuConnectionRejected(
        MacLifecycleProcessObservationDispositionV1
    )
}

/// Sealed lifecycle-observation composition created only after the complete
/// required-audit Agent service graph exists. Constructing this root is the
/// Agent self-readiness source; it does not inspect a PID, login registration,
/// or `SMAppService` status.
public struct MacAgentLifecycleObservationRootV1: Sendable {
    private let observations: MacLifecycleProcessObservationOwnerV1
    private let recoveries: MacLifecycleProcessRecoverySchedulerV1

    public static func afterAgentBootstrap(
        services: AgentPrimaryServicesV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        agentGeneration: UUID = UUID(),
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        transitionIDSource: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> MacAgentLifecycleObservationRootV1 {
        try await afterAgentBootstrap(
            lifecycle: services.lifecycle,
            processStarter: processStarter,
            agentGeneration: agentGeneration,
            wallClock: wallClock,
            transitionIDSource: transitionIDSource
        )
    }

    package static func afterAgentBootstrap(
        lifecycle: any AgentRemoteLifecycleCommandingV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        agentGeneration: UUID,
        wallClock: any MacDashboardLifecycleWallClockV1,
        transitionIDSource: @escaping @Sendable () -> UUID,
        recoveryRetryDelaysNanoseconds: [UInt64] =
            MacLifecycleProcessRecoverySchedulerV1.standardDelaysNanoseconds,
        recoverySleep: @escaping MacLifecycleProcessRecoverySchedulerV1.Sleep = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) async throws -> MacAgentLifecycleObservationRootV1 {
        let observations = MacLifecycleProcessObservationOwnerV1(
            lifecycle: lifecycle,
            processStarter: processStarter,
            wallClock: wallClock,
            transitionIDSource: transitionIDSource
        )
        let recoveries = MacLifecycleProcessRecoverySchedulerV1(
            observations: observations,
            delaysNanoseconds: recoveryRetryDelaysNanoseconds,
            sleep: recoverySleep
        )
        let activation = await observations.activateObservation(
            role: .agent,
            generation: agentGeneration
        )
        guard activation.disposition == .accepted,
              let token = activation.token else {
            throw MacAgentLifecycleObservationRootErrorV1
                .agentBootstrapRejected(activation.disposition)
        }
        let ready = await observations.observeReady(token)
        guard ready.disposition == .accepted else {
            throw MacAgentLifecycleObservationRootErrorV1
                .agentBootstrapRejected(ready.disposition)
        }
        return MacAgentLifecycleObservationRootV1(
            observations: observations,
            recoveries: recoveries
        )
    }

    /// Issues one connection-scoped capability only after the final platform
    /// adapter has authenticated the visible menu endpoint and authorized its
    /// protocol negotiation. Caller role, PID, path, and signing claims are
    /// intentionally absent from this boundary.
    public func makeAuthenticatedMenuConnection(
        generation: UUID
    ) async throws -> MacAuthenticatedMenuLifecycleConnectionV1 {
        let activation = await observations.activateObservation(
            role: .menuApp,
            generation: generation
        )
        guard activation.disposition == .accepted,
              let token = activation.token else {
            throw MacAgentLifecycleObservationRootErrorV1
                .menuConnectionRejected(activation.disposition)
        }
        return MacAuthenticatedMenuLifecycleConnectionV1(
            observations: observations,
            recoveries: recoveries,
            token: token
        )
    }
}

/// Exact-generation menu lifecycle capability owned by one already-
/// authenticated local connection. Calls serialize even while the underlying
/// lifecycle or recovery request suspends, so invalidation cannot race past a
/// ready publication. Repeated invalidation replays its exact terminal receipt.
public actor MacAuthenticatedMenuLifecycleConnectionV1 {
    private let observations: MacLifecycleProcessObservationOwnerV1
    private let recoveries: MacLifecycleProcessRecoverySchedulerV1
    private let token: MacLifecycleProcessObservationTokenV1
    private var terminalReceipt: MacLifecycleProcessObservationReceiptV1?
    private var operationLocked = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []

    package init(
        observations: MacLifecycleProcessObservationOwnerV1,
        recoveries: MacLifecycleProcessRecoverySchedulerV1,
        token: MacLifecycleProcessObservationTokenV1
    ) {
        self.observations = observations
        self.recoveries = recoveries
        self.token = token
    }

    public func publishReady()
        async -> MacLifecycleProcessObservationReceiptV1
    {
        await acquireOperation()
        let result: MacLifecycleProcessObservationReceiptV1
        if terminalReceipt != nil {
            result = MacLifecycleProcessObservationReceiptV1(
                token: token,
                disposition: .ignoredStale,
                transition: nil
            )
        } else {
            result = await observations.observeReady(token)
        }
        releaseOperation()
        return result
    }

    public func invalidate()
        async -> MacLifecycleProcessObservationReceiptV1
    {
        await acquireOperation()
        if let terminalReceipt {
            releaseOperation()
            return terminalReceipt
        }
        let result = await observations.observeTermination(token)
        terminalReceipt = result
        if result.disposition == .recoveryNotCompleted
            || result.disposition == .recoveryOutcomeUnknown {
            await recoveries.schedule(role: .menuApp)
        }
        releaseOperation()
        return result
    }

    package func waitForScheduledRecovery() async {
        await recoveries.waitUntilIdle(role: .menuApp)
    }

    private func acquireOperation() async {
        if !operationLocked {
            operationLocked = true
            return
        }
        await withCheckedContinuation { lockWaiters.append($0) }
    }

    private func releaseOperation() {
        if lockWaiters.isEmpty {
            operationLocked = false
            return
        }
        lockWaiters.removeFirst().resume()
    }
}
