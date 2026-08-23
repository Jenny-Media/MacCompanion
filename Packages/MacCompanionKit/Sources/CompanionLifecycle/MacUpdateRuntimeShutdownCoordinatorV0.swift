public struct MacUpdateRuntimeGateObservationV0: Equatable, Sendable {
    public let monotonicNowMilliseconds: Int64
    public let menuForeground: Bool
    public let controlState: MacUpdateControlStateV0

    public init(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool,
        controlState: MacUpdateControlStateV0
    ) {
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.menuForeground = menuForeground
        self.controlState = controlState
    }
}

public struct MacUpdateRuntimeShutdownDependenciesV0: Sendable {
    public let observeGate:
        @Sendable () async -> MacUpdateRuntimeGateObservationV0
    public let closeNetworkAdmission: @Sendable () async throws -> Void
    public let drainBoundedWork: @Sendable () async throws -> Void
    public let stopAgent: @Sendable () async throws -> Bool
    public let startUpdater: @Sendable () async throws -> Void
    public let reconcileNetworkAdmission:
        @Sendable () async throws -> Void
    public let reconcileAgentAndNetworkAdmission:
        @Sendable () async throws -> Void

    public init(
        observeGate: @escaping @Sendable () async
            -> MacUpdateRuntimeGateObservationV0,
        closeNetworkAdmission:
            @escaping @Sendable () async throws -> Void,
        drainBoundedWork:
            @escaping @Sendable () async throws -> Void,
        stopAgent: @escaping @Sendable () async throws -> Bool,
        startUpdater: @escaping @Sendable () async throws -> Void,
        reconcileNetworkAdmission:
            @escaping @Sendable () async throws -> Void,
        reconcileAgentAndNetworkAdmission:
            @escaping @Sendable () async throws -> Void
    ) {
        self.observeGate = observeGate
        self.closeNetworkAdmission = closeNetworkAdmission
        self.drainBoundedWork = drainBoundedWork
        self.stopAgent = stopAgent
        self.startUpdater = startUpdater
        self.reconcileNetworkAdmission = reconcileNetworkAdmission
        self.reconcileAgentAndNetworkAdmission =
            reconcileAgentAndNetworkAdmission
    }
}

public enum MacUpdateRuntimeShutdownCoordinatorErrorV0:
    Error, Equatable, Sendable
{
    case invalidPhase
    case authority(MacUpdateInstallAuthorityErrorV0)
    case runtimeEffectFailed
    case recoveryFailed
}

public enum MacUpdateRuntimeShutdownCoordinatorPhaseV0:
    String, Equatable, Sendable
{
    case awaitingConfirmation
    case confirming
    case confirmed
    case running
    case finished
}

/// Application-owned executor for one admitted update. It samples foreground,
/// time, and Control at every authority transition, runs only the effect issued
/// by the authority, and reconciles the minimum recorded runtime scope before
/// returning a failure.
public actor MacUpdateRuntimeShutdownCoordinatorV0 {
    private let authority: MacUpdateInstallAuthorityV0
    private let dependencies: MacUpdateRuntimeShutdownDependenciesV0
    private var phase =
        MacUpdateRuntimeShutdownCoordinatorPhaseV0.awaitingConfirmation

    public init(
        admission: MacUpdateInstallAdmissionV0,
        dependencies: MacUpdateRuntimeShutdownDependenciesV0
    ) {
        authority = admission.authority
        self.dependencies = dependencies
    }

    public func currentPhase()
        -> MacUpdateRuntimeShutdownCoordinatorPhaseV0
    {
        phase
    }

    public func authoritySnapshot() async -> MacUpdateInstallSnapshotV0 {
        await authority.snapshot()
    }

    public func confirm() async throws {
        guard phase == .awaitingConfirmation else {
            throw MacUpdateRuntimeShutdownCoordinatorErrorV0.invalidPhase
        }
        phase = .confirming
        let observation = await dependencies.observeGate()
        do {
            try await authority.confirm(
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground
            )
            phase = .confirmed
        } catch let error as MacUpdateInstallAuthorityErrorV0 {
            phase = .finished
            throw MacUpdateRuntimeShutdownCoordinatorErrorV0
                .authority(error)
        }
    }

    public func install() async throws {
        guard phase == .confirmed else {
            throw MacUpdateRuntimeShutdownCoordinatorErrorV0.invalidPhase
        }
        phase = .running

        do {
            var observation = await dependencies.observeGate()
            let first = try await authority.beginRuntimeShutdown(
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground,
                controlState: observation.controlState
            )
            guard first == .closeNetworkAdmission else {
                throw InternalCoordinatorErrorV0.invalidEffect
            }
            try await dependencies.closeNetworkAdmission()

            observation = await dependencies.observeGate()
            let second = try await authority.networkAdmissionDidClose(
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground
            )
            guard second == .drainBoundedWork else {
                throw InternalCoordinatorErrorV0.invalidEffect
            }
            try await dependencies.drainBoundedWork()

            observation = await dependencies.observeGate()
            let third = try await authority.boundedWorkDidDrain(
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground
            )
            guard third == .stopAgent else {
                throw InternalCoordinatorErrorV0.invalidEffect
            }
            let exactVersionMatch = try await dependencies.stopAgent()

            observation = await dependencies.observeGate()
            try await authority.agentDidStop(
                exactVersionMatch: exactVersionMatch,
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground
            )

            observation = await dependencies.observeGate()
            try await authority.handOffToUpdater(
                monotonicNowMilliseconds:
                    observation.monotonicNowMilliseconds,
                menuForeground: observation.menuForeground,
                start: dependencies.startUpdater
            )
            phase = .finished
        } catch {
            let mapped = Self.map(error)
            await authority.runtimeShutdownFailed()
            do {
                try await recoverIfRequired()
            } catch {
                phase = .finished
                throw MacUpdateRuntimeShutdownCoordinatorErrorV0
                    .recoveryFailed
            }
            phase = .finished
            throw mapped
        }
    }

    public func menuForegroundDidChange(_ foreground: Bool) async {
        await authority.menuForegroundDidChange(foreground)
        guard !foreground else { return }
        switch phase {
        case .awaitingConfirmation, .confirming, .confirmed:
            phase = .finished
        case .running, .finished:
            break
        }
    }

    public func cancel() async {
        await authority.finish()
        if phase != .running { phase = .finished }
    }

    private func recoverIfRequired() async throws {
        switch await authority.snapshot().recoveryRequirement {
        case .none:
            return
        case .reconcileNetworkAdmission:
            try await dependencies.reconcileNetworkAdmission()
        case .reconcileAgentAndNetworkAdmission:
            try await dependencies
                .reconcileAgentAndNetworkAdmission()
        }
    }

    private static func map(_ error: Error)
        -> MacUpdateRuntimeShutdownCoordinatorErrorV0
    {
        if let authorityError = error as? MacUpdateInstallAuthorityErrorV0 {
            return .authority(authorityError)
        }
        return .runtimeEffectFailed
    }
}

private enum InternalCoordinatorErrorV0: Error {
    case invalidEffect
}
