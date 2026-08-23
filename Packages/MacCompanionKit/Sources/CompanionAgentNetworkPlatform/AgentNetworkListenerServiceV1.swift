import CompanionAgent
import CompanionInteractiveHost
import CompanionNetworkPlatform
import Dispatch
import Foundation

private final class AgentNetworkListenerReadinessLatchV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var ready = false

    func markReady() {
        lock.withLock { ready = true }
    }

    func isReady() -> Bool {
        lock.withLock { ready }
    }
}

public protocol AgentNetworkListenerStartingV1: Sendable {
    func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable () -> Void,
        advertisementChanged: @escaping @Sendable (Bool) -> Void,
        accepted: @escaping @Sendable (
            NetworkHostAcceptedConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void
    ) throws

    func cancel()
}

extension NetworkHostListenerOwnerV0: AgentNetworkListenerStartingV1 {}

protocol AgentNetworkListenerHandoffServingV1: Sendable {
    func installStateChanged(
        _ stateChanged: @escaping @Sendable (UInt64) -> Void
    ) async
    func admitForService(
        _ accepted: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async throws
    func cancelForService() async
    func snapshotForService() async -> AgentNetworkListenerHandoffSnapshotV1
}

extension AgentNetworkListenerHandoffV1:
    AgentNetworkListenerHandoffServingV1
{
    func installStateChanged(
        _ stateChanged: @escaping @Sendable (UInt64) -> Void
    ) async {
        setStateChanged(stateChanged)
    }

    func admitForService(
        _ accepted: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async throws {
        try admit(
            accepted,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds
        )
    }

    func cancelForService() async {
        await cancel()
    }

    func snapshotForService() async
        -> AgentNetworkListenerHandoffSnapshotV1
    {
        snapshot()
    }
}

extension AgentNetworkListenerIngressHandoffV2:
    AgentNetworkListenerHandoffServingV1
{
    func installStateChanged(
        _ stateChanged: @escaping @Sendable (UInt64) -> Void
    ) async {
        setStateChanged(stateChanged)
    }

    func admitForService(
        _ accepted: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async throws {
        try await admit(
            accepted,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds
        )
    }

    func cancelForService() async {
        await cancel()
    }

    func snapshotForService() async
        -> AgentNetworkListenerHandoffSnapshotV1
    {
        serviceSnapshot()
    }
}

public enum AgentNetworkListenerServiceErrorV1:
    Error,
    Equatable,
    Sendable
{
    case alreadyStarted
}

public enum AgentNetworkListenerAdmissionFailureV1:
    Equatable,
    Sendable
{
    case acceptedConnectionStartFailed
    case ingressClassificationFailed
    case routePublicationFailed
    case pairingContextPublicationFailed
    case statusPublicationFailed
}

public enum AgentNetworkListenerServiceStateV1:
    Equatable,
    Sendable
{
    case idle
    case starting
    case listening
    case terminal
}

public struct AgentNetworkListenerServiceSnapshotV1:
    Equatable,
    Sendable
{
    public let state: AgentNetworkListenerServiceStateV1
    public let handoff: AgentNetworkListenerHandoffSnapshotV1
    public let lastListenerTerminationReason:
        NetworkHostListenerTerminationReasonV0?
    public let hasAcceptedConnectionStartFailure: Bool

    public init(
        state: AgentNetworkListenerServiceStateV1,
        handoff: AgentNetworkListenerHandoffSnapshotV1,
        lastListenerTerminationReason:
            NetworkHostListenerTerminationReasonV0?,
        hasAcceptedConnectionStartFailure: Bool
    ) {
        self.state = state
        self.handoff = handoff
        self.lastListenerTerminationReason = lastListenerTerminationReason
        self.hasAcceptedConnectionStartFailure =
            hasAcceptedConnectionStartFailure
    }
}

/// Sole outer owner for the sealed listener and its Agent handoff. This type
/// does not construct or start a listener by itself; release composition must
/// supply the already identity-bound `NetworkHostListenerOwnerV0`.
public actor AgentNetworkListenerServiceV1 {
    private let listener: any AgentNetworkListenerStartingV1
    private let handoff: any AgentNetworkListenerHandoffServingV1
    private let queue: DispatchQueue
    private let monotonicNowMilliseconds: @Sendable () -> UInt64
    private let listenerTerminal: @Sendable (
        NetworkHostListenerTerminationReasonV0
    ) -> Void
    private let admissionFailure: @Sendable (
        AgentNetworkListenerAdmissionFailureV1
    ) -> Void
    private let reserveStatusGeneration: (@Sendable () async throws -> UInt64)?
    private let statusPublisher: (@Sendable (
        AgentNetworkListenerDiagnosticsV1,
        UInt64
    ) async throws -> Void)?
    private let listenerRoutePublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    private let advertisementRoutePublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    private let pairingListenerPublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    private let pairingAdvertisementPublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    private let pairingContextStop: (@Sendable () async -> Void)?
    private let pairingSessionInvalidator: (@Sendable (
        Bool
    ) async throws -> Void)?
    private nonisolated let readiness = AgentNetworkListenerReadinessLatchV1()
    private var state: AgentNetworkListenerServiceStateV1 = .idle
    private var lastListenerTerminationReason:
        NetworkHostListenerTerminationReasonV0?
    private var hasAcceptedConnectionStartFailure = false
    private var lastHandoffRevision: UInt64 = 0
    private var localStatusGeneration: UInt64 = 0
    private var listenerRouteGeneration: UInt64 = 0
    private var advertisementRouteGeneration: UInt64 = 0
    private var pairingListenerGeneration: UInt64 = 0
    private var pairingAdvertisementGeneration: UInt64 = 0

    package init(
        listener: NetworkHostListenerOwnerV0,
        primarySessions: AgentPrimarySessionAuthorityV1,
        networkStatus: AgentLocalNetworkStatusPublisherV1,
        lanRoutes: AgentLocalLANRouteEvidenceAuthorityV1,
        pairingContext: AgentNetworkPairingContextAuthorityV0? = nil,
        pairingSessions: AgentLocalPairingSessionHandlerV0? = nil,
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in },
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in }
    ) {
        self.listener = listener
        handoff = AgentNetworkListenerHandoffV1(
            binder: AgentNetworkPrimaryConnectionFactoryV1(
                primarySessions: primarySessions
            ),
            queue: queue,
            context: context,
            acceptedTerminal: acceptedTerminal,
            primaryTerminal: primaryTerminal
        )
        self.queue = queue
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.listenerTerminal = listenerTerminal
        self.admissionFailure = admissionFailure
        reserveStatusGeneration = {
            try await networkStatus.reserveGeneration()
        }
        statusPublisher = { diagnostics, generation in
            try await networkStatus.publish(
                diagnostics,
                generation: generation
            )
        }
        listenerRoutePublisher = { ready, generation in
            try await lanRoutes.publishListenerReadiness(
                ready: ready,
                generation: generation
            )
        }
        advertisementRoutePublisher = { ready, generation in
            try await lanRoutes.publishAdvertisementReadiness(
                ready: ready,
                generation: generation
            )
        }
        if let pairingContext {
            pairingListenerPublisher = { ready, generation in
                try await pairingContext.publishListenerReadiness(
                    ready: ready,
                    generation: generation
                )
            }
            pairingAdvertisementPublisher = { ready, generation in
                try await pairingContext.publishAdvertisementReadiness(
                    ready: ready,
                    generation: generation
                )
            }
            pairingContextStop = { await pairingContext.stop() }
        } else {
            pairingListenerPublisher = nil
            pairingAdvertisementPublisher = nil
            pairingContextStop = nil
        }
        if let pairingSessions {
            pairingSessionInvalidator = { terminal in
                try await pairingSessions.invalidateForNetworkLoss(
                    monotonicNowMilliseconds: monotonicNowMilliseconds(),
                    terminal: terminal
                )
            }
        } else {
            pairingSessionInvalidator = nil
        }
    }

    /// Role-safe shared-listener construction. Pairing and authenticated
    /// primary traffic are classified from the exact first frame and retain
    /// independent active generations.
    package init(
        listener: NetworkHostListenerOwnerV0,
        primarySessions: AgentPrimarySessionAuthorityV1,
        pairingConnections: AgentNetworkHostPairingConnectionFactoryV0,
        interactiveBinder: any AgentNetworkInteractiveIngressBindingV2 =
            AgentNetworkRejectingInteractiveIngressBinderV2(),
        networkStatus: AgentLocalNetworkStatusPublisherV1,
        lanRoutes: AgentLocalLANRouteEvidenceAuthorityV1,
        pairingAvailability: AgentNetworkPairingContextAuthorityV0,
        pairingSessions: AgentLocalPairingSessionHandlerV0,
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingRequestContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in },
        pairingTerminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in },
        interactiveTerminal: @escaping @Sendable (
            NetworkHostIngressRoleV0,
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void = { _, _ in },
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in }
    ) {
        self.listener = listener
        handoff = AgentNetworkListenerIngressHandoffV2(
            primaryBinder: AgentNetworkPrimaryConnectionFactoryV1(
                primarySessions: primarySessions
            ),
            pairingBinder: pairingConnections,
            interactiveBinder: interactiveBinder,
            queue: queue,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            primaryContext: primaryContext,
            pairingContext: pairingRequestContext,
            acceptedTerminal: acceptedTerminal,
            ingressTerminal: { reason in
                switch reason {
                case .classificationFailed:
                    admissionFailure(.ingressClassificationFailed)
                case .primary(let value):
                    primaryTerminal(value)
                case .pairing(let value):
                    pairingTerminal(value)
                case let .interactive(role, value):
                    interactiveTerminal(role, value)
                }
            }
        )
        self.queue = queue
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.listenerTerminal = listenerTerminal
        self.admissionFailure = admissionFailure
        reserveStatusGeneration = {
            try await networkStatus.reserveGeneration()
        }
        statusPublisher = { diagnostics, generation in
            try await networkStatus.publish(
                diagnostics,
                generation: generation
            )
        }
        listenerRoutePublisher = { ready, generation in
            try await lanRoutes.publishListenerReadiness(
                ready: ready,
                generation: generation
            )
        }
        advertisementRoutePublisher = { ready, generation in
            try await lanRoutes.publishAdvertisementReadiness(
                ready: ready,
                generation: generation
            )
        }
        pairingListenerPublisher = { ready, generation in
            try await pairingAvailability.publishListenerReadiness(
                ready: ready,
                generation: generation
            )
        }
        pairingAdvertisementPublisher = { ready, generation in
            try await pairingAvailability.publishAdvertisementReadiness(
                ready: ready,
                generation: generation
            )
        }
        pairingContextStop = { await pairingAvailability.stop() }
        pairingSessionInvalidator = { terminal in
            try await pairingSessions.invalidateForNetworkLoss(
                monotonicNowMilliseconds: monotonicNowMilliseconds(),
                terminal: terminal
            )
        }
    }

    init(
        listener: any AgentNetworkListenerStartingV1,
        handoff: any AgentNetworkListenerHandoffServingV1,
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in },
        reserveStatusGeneration: (@Sendable () async throws -> UInt64)? = nil,
        statusPublisher: (@Sendable (
            AgentNetworkListenerDiagnosticsV1,
            UInt64
        ) async throws -> Void)? = nil,
        listenerRoutePublisher: (@Sendable (
            Bool,
            UInt64
        ) async throws -> Void)? = nil,
        advertisementRoutePublisher: (@Sendable (
            Bool,
            UInt64
        ) async throws -> Void)? = nil,
        pairingListenerPublisher: (@Sendable (
            Bool,
            UInt64
        ) async throws -> Void)? = nil,
        pairingAdvertisementPublisher: (@Sendable (
            Bool,
            UInt64
        ) async throws -> Void)? = nil,
        pairingContextStop: (@Sendable () async -> Void)? = nil,
        pairingSessionInvalidator: (@Sendable (
            Bool
        ) async throws -> Void)? = nil
    ) {
        self.listener = listener
        self.handoff = handoff
        self.queue = queue
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.listenerTerminal = listenerTerminal
        self.admissionFailure = admissionFailure
        self.reserveStatusGeneration = reserveStatusGeneration
        self.statusPublisher = statusPublisher
        self.listenerRoutePublisher = listenerRoutePublisher
        self.advertisementRoutePublisher = advertisementRoutePublisher
        self.pairingListenerPublisher = pairingListenerPublisher
        self.pairingAdvertisementPublisher = pairingAdvertisementPublisher
        self.pairingContextStop = pairingContextStop
        self.pairingSessionInvalidator = pairingSessionInvalidator
    }

    public func start() async throws {
        guard state == .idle else {
            throw AgentNetworkListenerServiceErrorV1.alreadyStarted
        }
        state = .starting
        do {
            await handoff.installStateChanged { [weak self] revision in
                Task { await self?.handoffChanged(revision) }
            }
            try Task.checkCancellation()
            guard state == .starting else { throw CancellationError() }
            try listener.start(
                queue: queue,
                ready: { [weak self] in
                    guard let self else { return }
                    self.readiness.markReady()
                    Task { await self.listenerReady() }
                },
                advertisementChanged: { [weak self] ready in
                    Task {
                        await self?.advertisementChanged(ready)
                    }
                },
                accepted: { [weak self] accepted in
                    Task { await self?.accepted(accepted) }
                },
                terminal: { [weak self] reason in
                    Task { await self?.listenerEnded(reason) }
                }
            )
            await publishCurrentStatus()
        } catch {
            if state != .terminal {
                state = .terminal
                listener.cancel()
                await handoff.cancelForService()
                await pairingContextStop?()
                await invalidatePairingSessions(terminal: true)
                await publishListenerRouteReadiness(false)
                await publishAdvertisementRouteReadiness(false)
                await publishCurrentStatus()
            }
            throw error
        }
    }

    public func cancel() async {
        guard state != .terminal else { return }
        state = .terminal
        lastListenerTerminationReason = .localCancel
        listener.cancel()
        await handoff.cancelForService()
        await pairingContextStop?()
        await invalidatePairingSessions(terminal: true)
        await publishListenerRouteReadiness(false)
        await publishAdvertisementRouteReadiness(false)
        await publishCurrentStatus()
        listenerTerminal(.localCancel)
    }

    public func snapshot() async -> AgentNetworkListenerServiceSnapshotV1 {
        AgentNetworkListenerServiceSnapshotV1(
            state: state,
            handoff: await handoff.snapshotForService(),
            lastListenerTerminationReason: lastListenerTerminationReason,
            hasAcceptedConnectionStartFailure:
                hasAcceptedConnectionStartFailure
        )
    }

    private func accepted(_ accepted: NetworkHostAcceptedConnectionV0) async {
        var becameReady = false
        if state == .starting, readiness.isReady() {
            state = .listening
            becameReady = true
        }
        if becameReady {
            await publishListenerRouteReadiness(true)
            await publishPairingListenerReadiness(true)
        }
        guard state == .listening else {
            accepted.cancel()
            return
        }
        do {
            try await handoff.admitForService(
                accepted,
                acceptedAtMonotonicMilliseconds:
                    monotonicNowMilliseconds()
            )
            hasAcceptedConnectionStartFailure = false
            await publishCurrentStatus()
        } catch {
            accepted.cancel()
            hasAcceptedConnectionStartFailure = true
            admissionFailure(.acceptedConnectionStartFailed)
            await publishCurrentStatus()
        }
    }

    private func listenerReady() async {
        guard state == .starting else { return }
        state = .listening
        await publishListenerRouteReadiness(true)
        await publishPairingListenerReadiness(true)
        await publishCurrentStatus()
    }

    private func listenerEnded(
        _ reason: NetworkHostListenerTerminationReasonV0
    ) async {
        guard state == .starting || state == .listening else { return }
        state = .terminal
        lastListenerTerminationReason = reason
        await handoff.cancelForService()
        await pairingContextStop?()
        await invalidatePairingSessions(terminal: true)
        await publishListenerRouteReadiness(false)
        await publishAdvertisementRouteReadiness(false)
        await publishCurrentStatus()
        listenerTerminal(reason)
    }

    private func handoffChanged(_ revision: UInt64) async {
        guard revision > lastHandoffRevision else { return }
        lastHandoffRevision = revision
        await publishCurrentStatus()
    }

    private func advertisementChanged(_ ready: Bool) async {
        guard state == .starting || state == .listening else { return }
        await publishAdvertisementRouteReadiness(ready)
        await publishPairingAdvertisementReadiness(ready)
        if !ready {
            await invalidatePairingSessions(terminal: false)
        }
    }

    private func publishCurrentStatus() async {
        guard let statusPublisher else { return }
        let generation: UInt64
        do {
            if let reserveStatusGeneration {
                generation = try await reserveStatusGeneration()
            } else {
                guard localStatusGeneration < UInt64.max else {
                    admissionFailure(.statusPublicationFailed)
                    return
                }
                localStatusGeneration += 1
                generation = localStatusGeneration
            }
            let diagnostics = AgentNetworkListenerDiagnosticProjectionV1.project(
                await snapshot()
            )
            try await statusPublisher(diagnostics, generation)
        } catch {
            admissionFailure(.statusPublicationFailed)
        }
    }

    private func publishListenerRouteReadiness(_ ready: Bool) async {
        guard let listenerRoutePublisher else { return }
        guard listenerRouteGeneration < UInt64.max else {
            admissionFailure(.routePublicationFailed)
            return
        }
        listenerRouteGeneration += 1
        do {
            try await listenerRoutePublisher(
                ready,
                listenerRouteGeneration
            )
        } catch {
            admissionFailure(.routePublicationFailed)
        }
    }


    private func publishAdvertisementRouteReadiness(_ ready: Bool) async {
        guard let advertisementRoutePublisher else { return }
        guard advertisementRouteGeneration < UInt64.max else {
            admissionFailure(.routePublicationFailed)
            return
        }
        advertisementRouteGeneration += 1
        do {
            try await advertisementRoutePublisher(
                ready,
                advertisementRouteGeneration
            )
        } catch {
            admissionFailure(.routePublicationFailed)
        }
    }

    private func publishPairingListenerReadiness(_ ready: Bool) async {
        guard let pairingListenerPublisher else { return }
        guard pairingListenerGeneration < UInt64.max else {
            admissionFailure(.pairingContextPublicationFailed)
            return
        }
        pairingListenerGeneration += 1
        do {
            try await pairingListenerPublisher(
                ready,
                pairingListenerGeneration
            )
        } catch {
            admissionFailure(.pairingContextPublicationFailed)
        }
    }

    private func publishPairingAdvertisementReadiness(_ ready: Bool) async {
        guard let pairingAdvertisementPublisher else { return }
        guard pairingAdvertisementGeneration < UInt64.max else {
            admissionFailure(.pairingContextPublicationFailed)
            return
        }
        pairingAdvertisementGeneration += 1
        do {
            try await pairingAdvertisementPublisher(
                ready,
                pairingAdvertisementGeneration
            )
        } catch {
            admissionFailure(.pairingContextPublicationFailed)
        }
    }

    private func invalidatePairingSessions(terminal: Bool) async {
        guard let pairingSessionInvalidator else { return }
        do {
            try await pairingSessionInvalidator(terminal)
        } catch {
            admissionFailure(.pairingContextPublicationFailed)
        }
    }
}
