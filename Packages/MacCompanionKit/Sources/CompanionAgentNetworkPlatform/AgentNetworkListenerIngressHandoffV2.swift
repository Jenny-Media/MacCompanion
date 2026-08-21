import CompanionNetworkPlatform
import Dispatch
import Foundation

public enum AgentNetworkIngressTerminationV2: Equatable, Sendable {
    case classificationFailed
    case primary(NetworkHostPrimaryTerminationReasonV0)
    case pairing(NetworkHostPairingTerminationReasonV0)
}

private final class AgentNetworkIngressTerminationLatchV2:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var reason: AgentNetworkIngressTerminationV2?
    private var activated = false

    func activate() -> AgentNetworkIngressTerminationV2? {
        lock.withLock {
            activated = true
            return reason
        }
    }

    func record(_ reason: AgentNetworkIngressTerminationV2) -> Bool {
        lock.withLock {
            if self.reason == nil { self.reason = reason }
            return activated
        }
    }
}

public protocol AgentNetworkIngressClassifyingV2: Sendable {
    func classify() async throws -> NetworkHostClassifiedConnectionV0
    func cancel() async
}

public protocol AgentNetworkIngressClassifierMakingV2: Sendable {
    func makeClassifier(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) throws -> any AgentNetworkIngressClassifyingV2
}

public protocol AgentNetworkBoundIngressConnectionV2: Sendable {
    func begin() async throws
    func cancel() async
}

public protocol AgentNetworkPrimaryIngressBindingV2: Sendable {
    func bindPrimaryIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2
}

public protocol AgentNetworkPairingIngressBindingV2: Sendable {
    func bindPairingIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2
}

private actor AgentNetworkIngressClassifierAdapterV2:
    AgentNetworkIngressClassifyingV2
{
    let classifier: NetworkHostIngressClassifierV0

    init(classifier: NetworkHostIngressClassifierV0) {
        self.classifier = classifier
    }

    func classify() async throws -> NetworkHostClassifiedConnectionV0 {
        try await classifier.classify()
    }

    func cancel() async {
        await classifier.cancel()
    }
}

public struct AgentNetworkIngressClassifierFactoryV2:
    AgentNetworkIngressClassifierMakingV2,
    Sendable
{
    public init() {}

    public func makeClassifier(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) throws -> any AgentNetworkIngressClassifyingV2 {
        AgentNetworkIngressClassifierAdapterV2(classifier:
            try NetworkHostIngressClassifierV0(
                verifiedReadyConnection: verifiedReadyConnection,
                acceptedAtMonotonicMilliseconds:
                    acceptedAtMonotonicMilliseconds,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        )
    }
}

extension AgentNetworkPrimaryConnectionV1:
    AgentNetworkBoundIngressConnectionV2 {}

extension AgentNetworkPrimaryConnectionFactoryV1:
    AgentNetworkPrimaryIngressBindingV2
{
    public func bindPrimaryIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2 {
        try await bind(
            classifiedConnection: classifiedConnection,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds,
            context: context,
            terminal: terminal
        )
    }
}

extension AgentNetworkHostPairingConnectionV0:
    AgentNetworkBoundIngressConnectionV2 {}

extension AgentNetworkHostPairingConnectionFactoryV0:
    AgentNetworkPairingIngressBindingV2
{
    public func bindPairingIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2 {
        try await bind(
            classifiedConnection: classifiedConnection,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds,
            context: context,
            terminal: terminal
        )
    }
}

public struct AgentNetworkListenerIngressSnapshotV2:
    Equatable,
    Sendable
{
    public let isCancelled: Bool
    public let hasPendingTLS: Bool
    public let isClassifying: Bool
    public let bindingRole: NetworkHostIngressRoleV0?
    public let hasActivePrimary: Bool
    public let hasActivePairing: Bool

    public init(
        isCancelled: Bool,
        hasPendingTLS: Bool,
        isClassifying: Bool,
        bindingRole: NetworkHostIngressRoleV0?,
        hasActivePrimary: Bool,
        hasActivePairing: Bool
    ) {
        self.isCancelled = isCancelled
        self.hasPendingTLS = hasPendingTLS
        self.isClassifying = isClassifying
        self.bindingRole = bindingRole
        self.hasActivePrimary = hasActivePrimary
        self.hasActivePairing = hasActivePairing
    }
}

/// Role-safe listener handoff. One newest unclassified candidate may progress,
/// while primary and pairing generations remain independently owned. Pairing
/// never replaces primary, and an active pairing connection cannot be displaced
/// by a second pairing candidate.
public actor AgentNetworkListenerIngressHandoffV2 {
    private struct Pending {
        let token: UUID
        let accepted: any AgentNetworkAcceptedConnectionStartingV1
        let acceptedAtMonotonicMilliseconds: UInt64
    }

    private struct Classifying {
        let token: UUID
        let classifier: any AgentNetworkIngressClassifyingV2
        let acceptedAtMonotonicMilliseconds: UInt64
    }

    private struct Active {
        let token: UUID
        let connection: any AgentNetworkBoundIngressConnectionV2
    }

    private let classifierFactory: any AgentNetworkIngressClassifierMakingV2
    private let primaryBinder: any AgentNetworkPrimaryIngressBindingV2
    private let pairingBinder: any AgentNetworkPairingIngressBindingV2
    private let queue: DispatchQueue
    private let monotonicNowMilliseconds: @Sendable () -> UInt64
    private let primaryContext: @Sendable () -> NetworkHostRequestContextV0
    private let pairingContext: @Sendable () ->
        NetworkHostPairingRequestContextV0
    private let acceptedTerminal: @Sendable (
        NetworkHostAcceptedConnectionTerminationReasonV0
    ) -> Void
    private let ingressTerminal: @Sendable (
        AgentNetworkIngressTerminationV2
    ) -> Void
    private var cancelled = false
    private var pending: Pending?
    private var classifying: Classifying?
    private var bindingToken: UUID?
    private var bindingRole: NetworkHostIngressRoleV0?
    private var bindingConnection: Active?
    private var activePrimary: Active?
    private var activePairing: Active?
    private var stateRevision: UInt64 = 0
    private var stateChanged: @Sendable (UInt64) -> Void = { _ in }

    public init(
        classifierFactory: any AgentNetworkIngressClassifierMakingV2 =
            AgentNetworkIngressClassifierFactoryV2(),
        primaryBinder: any AgentNetworkPrimaryIngressBindingV2,
        pairingBinder: any AgentNetworkPairingIngressBindingV2,
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        ingressTerminal: @escaping @Sendable (
            AgentNetworkIngressTerminationV2
        ) -> Void = { _ in }
    ) {
        self.classifierFactory = classifierFactory
        self.primaryBinder = primaryBinder
        self.pairingBinder = pairingBinder
        self.queue = queue
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.primaryContext = primaryContext
        self.pairingContext = pairingContext
        self.acceptedTerminal = acceptedTerminal
        self.ingressTerminal = ingressTerminal
    }

    package func setStateChanged(
        _ stateChanged: @escaping @Sendable (UInt64) -> Void
    ) {
        self.stateChanged = stateChanged
    }

    public func admit(
        _ accepted: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async throws {
        guard !cancelled else {
            accepted.cancel()
            return
        }
        pending?.accepted.cancel()
        pending = nil
        if let classifying {
            self.classifying = nil
            await classifying.classifier.cancel()
        }
        if let bindingConnection {
            self.bindingConnection = nil
            bindingToken = nil
            bindingRole = nil
            await bindingConnection.connection.cancel()
        }
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
                    Task { await self?.acceptedEnded(reason, token: token) }
                }
            )
        } catch {
            if pending?.token == token { pending = nil }
            accepted.cancel()
            notifyStateChanged()
            throw error
        }
    }

    public func cancel() async {
        guard !cancelled else { return }
        cancelled = true
        let pending = self.pending
        let classifying = self.classifying
        let primary = activePrimary
        let pairing = activePairing
        let binding = bindingConnection
        self.pending = nil
        self.classifying = nil
        bindingToken = nil
        bindingRole = nil
        bindingConnection = nil
        activePrimary = nil
        activePairing = nil
        pending?.accepted.cancel()
        if let classifying { await classifying.classifier.cancel() }
        if let binding { await binding.connection.cancel() }
        if let primary { await primary.connection.cancel() }
        if let pairing { await pairing.connection.cancel() }
        notifyStateChanged()
    }

    public func snapshot() -> AgentNetworkListenerIngressSnapshotV2 {
        AgentNetworkListenerIngressSnapshotV2(
            isCancelled: cancelled,
            hasPendingTLS: pending != nil,
            isClassifying: classifying != nil,
            bindingRole: bindingRole,
            hasActivePrimary: activePrimary != nil,
            hasActivePairing: activePairing != nil
        )
    }

    private func ready(
        _ verified: NetworkHostVerifiedReadyConnectionV0,
        token: UUID
    ) async {
        guard !cancelled, let pending, pending.token == token else {
            verified.cancel()
            return
        }
        self.pending = nil
        let classifier: any AgentNetworkIngressClassifyingV2
        do {
            classifier = try classifierFactory.makeClassifier(
                verifiedReadyConnection: verified,
                acceptedAtMonotonicMilliseconds:
                    pending.acceptedAtMonotonicMilliseconds,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            verified.cancel()
            notifyStateChanged()
            ingressTerminal(.classificationFailed)
            return
        }
        classifying = Classifying(
            token: token,
            classifier: classifier,
            acceptedAtMonotonicMilliseconds:
                pending.acceptedAtMonotonicMilliseconds
        )
        notifyStateChanged()
        let classified: NetworkHostClassifiedConnectionV0
        do {
            classified = try await classifier.classify()
        } catch {
            if classifying?.token == token {
                classifying = nil
                notifyStateChanged()
                ingressTerminal(.classificationFailed)
            }
            return
        }
        guard !cancelled, classifying?.token == token else {
            classified.cancel()
            return
        }
        classifying = nil
        notifyStateChanged()
        await bind(
            classified,
            token: token,
            acceptedAtMonotonicMilliseconds:
                pending.acceptedAtMonotonicMilliseconds
        )
    }

    private func bind(
        _ classified: NetworkHostClassifiedConnectionV0,
        token: UUID,
        acceptedAtMonotonicMilliseconds: UInt64
    ) async {
        if classified.role == .pairing, activePairing != nil {
            classified.cancel()
            return
        }
        bindingToken = token
        bindingRole = classified.role
        notifyStateChanged()
        let latch = AgentNetworkIngressTerminationLatchV2()
        let bound: any AgentNetworkBoundIngressConnectionV2
        do {
            switch classified.role {
            case .applicationPrimary:
                bound = try await primaryBinder.bindPrimaryIngress(
                    classifiedConnection: classified,
                    acceptedAtMonotonicMilliseconds:
                        acceptedAtMonotonicMilliseconds,
                    context: primaryContext,
                    terminal: { [weak self] reason in
                        let value = AgentNetworkIngressTerminationV2
                            .primary(reason)
                        if latch.record(value) {
                            Task {
                                await self?.roleEnded(
                                    value,
                                    role: .applicationPrimary,
                                    token: token
                                )
                            }
                        }
                    }
                )
            case .pairing:
                bound = try await pairingBinder.bindPairingIngress(
                    classifiedConnection: classified,
                    acceptedAtMonotonicMilliseconds:
                        acceptedAtMonotonicMilliseconds,
                    context: pairingContext,
                    terminal: { [weak self] reason in
                        let value = AgentNetworkIngressTerminationV2
                            .pairing(reason)
                        if latch.record(value) {
                            Task {
                                await self?.roleEnded(
                                    value,
                                    role: .pairing,
                                    token: token
                                )
                            }
                        }
                    }
                )
            }
        } catch {
            if bindingToken == token {
                bindingToken = nil
                bindingRole = nil
                notifyStateChanged()
            }
            classified.cancel()
            return
        }
        guard !cancelled, bindingToken == token else {
            await bound.cancel()
            return
        }
        bindingConnection = Active(token: token, connection: bound)
        do {
            try await bound.begin()
        } catch {
            let stillOwned = bindingToken == token
                || bindingConnection?.token == token
            if stillOwned {
                bindingToken = nil
                bindingRole = nil
                bindingConnection = nil
                await bound.cancel()
            }
            notifyStateChanged()
            return
        }
        guard !cancelled, bindingToken == token,
              bindingConnection?.token == token else {
            if bindingConnection?.token == token {
                bindingConnection = nil
                await bound.cancel()
            }
            return
        }
        if let reason = latch.activate() {
            bindingToken = nil
            bindingRole = nil
            bindingConnection = nil
            await bound.cancel()
            notifyStateChanged()
            ingressTerminal(reason)
            return
        }
        bindingToken = nil
        bindingRole = nil
        bindingConnection = nil
        let active = Active(token: token, connection: bound)
        switch classified.role {
        case .applicationPrimary:
            let previous = activePrimary
            activePrimary = active
            if let previous { await previous.connection.cancel() }
        case .pairing:
            activePairing = active
        }
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

    private func roleEnded(
        _ reason: AgentNetworkIngressTerminationV2,
        role: NetworkHostIngressRoleV0,
        token: UUID
    ) async {
        if bindingToken == token {
            bindingToken = nil
            bindingRole = nil
            let binding = bindingConnection
            bindingConnection = nil
            if let binding { await binding.connection.cancel() }
            notifyStateChanged()
            ingressTerminal(reason)
            return
        }
        switch role {
        case .applicationPrimary:
            guard activePrimary?.token == token else { return }
            activePrimary = nil
        case .pairing:
            guard activePairing?.token == token else { return }
            activePairing = nil
        }
        notifyStateChanged()
        ingressTerminal(reason)
    }

    package func serviceSnapshot() -> AgentNetworkListenerHandoffSnapshotV1 {
        AgentNetworkListenerHandoffSnapshotV1(
            isCancelled: cancelled,
            hasPendingTLS: pending != nil || classifying != nil,
            isBinding: bindingToken != nil,
            hasActivePrimary: activePrimary != nil
        )
    }

    private func notifyStateChanged() {
        guard stateRevision < UInt64.max else { return }
        stateRevision += 1
        stateChanged(stateRevision)
    }
}
