import CompanionNetworkPlatform
import CompanionInteractiveHost
import CompanionInteractiveWire
import Dispatch
import Foundation
import OSLog

private let agentNetworkIngressLoggerV2 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "network-ingress"
)

public enum AgentNetworkIngressTerminationV2: Equatable, Sendable {
    case classificationFailed
    case primary(NetworkHostPrimaryTerminationReasonV0)
    case pairing(NetworkHostPairingTerminationReasonV0)
    case interactive(
        role: NetworkHostIngressRoleV0,
        reason: HostInteractiveRoleHandshakePumpErrorV0
    )
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
    func authenticatedPrimaryConnectionID() async -> Data?
    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws
    func readyInteractiveChannel() async
        -> HostInteractiveReadyRoleChannelV0?
    func readyInteractiveConnection() async
        -> NetworkHostInteractiveReadyRoleConnectionV0?
}

public extension AgentNetworkBoundIngressConnectionV2 {
    func authenticatedPrimaryConnectionID() async -> Data? { nil }

    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
    }

    func readyInteractiveChannel() async
        -> HostInteractiveReadyRoleChannelV0?
    {
        nil
    }

    func readyInteractiveConnection() async
        -> NetworkHostInteractiveReadyRoleConnectionV0?
    {
        nil
    }
}

public enum AgentNetworkAuthenticatedEventSinkErrorV2:
    Error, Equatable, Sendable
{
    case unavailable
    case primaryReplaced
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

public protocol AgentNetworkInteractiveIngressBindingV2: Sendable {
    func bindInteractiveIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2
}

public enum AgentNetworkInteractiveIngressBindingErrorV2:
    Error, Equatable, Sendable
{
    case unavailable
}

public struct AgentNetworkRejectingInteractiveIngressBinderV2:
    AgentNetworkInteractiveIngressBindingV2,
    Sendable
{
    public init() {}

    public func bindInteractiveIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2 {
        classifiedConnection.cancel()
        throw AgentNetworkInteractiveIngressBindingErrorV2.unavailable
    }
}

private actor AgentNetworkBoundInteractiveIngressConnectionV2:
    AgentNetworkBoundIngressConnectionV2
{
    private let connection: NetworkHostInteractiveRoleConnectionV0
    private var ready: NetworkHostInteractiveReadyRoleConnectionV0?

    init(connection: NetworkHostInteractiveRoleConnectionV0) {
        self.connection = connection
    }

    func begin() async throws {
        ready = try await connection.beginOnClassifiedConnection()
    }

    func cancel() async {
        ready = nil
        await connection.cancel()
    }

    func readyInteractiveChannel() async
        -> HostInteractiveReadyRoleChannelV0?
    {
        ready?.channel
    }

    func readyInteractiveConnection() async
        -> NetworkHostInteractiveReadyRoleConnectionV0?
    {
        ready
    }
}

public struct AgentNetworkInteractiveIngressFactoryV2:
    AgentNetworkInteractiveIngressBindingV2,
    Sendable
{
    private let authenticator: any HostInteractiveChannelAuthenticatingV0
    private let monotonicNowMilliseconds: @Sendable () -> UInt64

    public init(
        authenticator: any HostInteractiveChannelAuthenticatingV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) {
        self.authenticator = authenticator
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    public func bindInteractiveIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundIngressConnectionV2 {
        let connection = try NetworkHostInteractiveRoleConnectionV0(
            classifiedConnection: classifiedConnection,
            authenticator: authenticator,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            terminal: terminal
        )
        return AgentNetworkBoundInteractiveIngressConnectionV2(
            connection: connection
        )
    }
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
    public let hasActiveInteractiveInput: Bool
    public let hasActiveInteractiveMedia: Bool

    public init(
        isCancelled: Bool,
        hasPendingTLS: Bool,
        isClassifying: Bool,
        bindingRole: NetworkHostIngressRoleV0?,
        hasActivePrimary: Bool,
        hasActivePairing: Bool,
        hasActiveInteractiveInput: Bool = false,
        hasActiveInteractiveMedia: Bool = false
    ) {
        self.isCancelled = isCancelled
        self.hasPendingTLS = hasPendingTLS
        self.isClassifying = isClassifying
        self.bindingRole = bindingRole
        self.hasActivePrimary = hasActivePrimary
        self.hasActivePairing = hasActivePairing
        self.hasActiveInteractiveInput = hasActiveInteractiveInput
        self.hasActiveInteractiveMedia = hasActiveInteractiveMedia
    }
}

/// Role-safe listener handoff. One unclassified candidate progresses at a
/// time while a bounded FIFO lets the client's parallel input/media dials wait
/// without permitting concurrent unauthenticated framing work. Primary,
/// pairing, and Interactive-role generations remain independently owned.
public actor AgentNetworkListenerIngressHandoffV2 {
    private static let maximumQueuedCandidates = 3

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
        let interactiveChannel: HostInteractiveReadyRoleChannelV0?
        let interactiveConnection:
            NetworkHostInteractiveReadyRoleConnectionV0?
    }

    private let classifierFactory: any AgentNetworkIngressClassifierMakingV2
    private let primaryBinder: any AgentNetworkPrimaryIngressBindingV2
    private let pairingBinder: any AgentNetworkPairingIngressBindingV2
    private let interactiveBinder: any AgentNetworkInteractiveIngressBindingV2
    private let interactivePairReady: (@Sendable (
        AgentInteractiveReadyRolePairV0
    ) async throws -> Void)?
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
    private var admissionOpen = true
    private var queued: [Pending] = []
    private var pending: Pending?
    private var classifying: Classifying?
    private var bindingToken: UUID?
    private var bindingRole: NetworkHostIngressRoleV0?
    private var bindingConnection: Active?
    private var activePrimary: Active?
    private var activePairing: Active?
    private var activeInteractiveInput: Active?
    private var activeInteractiveMedia: Active?
    private var stateRevision: UInt64 = 0
    private var stateChanged: @Sendable (UInt64) -> Void = { _ in }

    public init(
        classifierFactory: any AgentNetworkIngressClassifierMakingV2 =
            AgentNetworkIngressClassifierFactoryV2(),
        primaryBinder: any AgentNetworkPrimaryIngressBindingV2,
        pairingBinder: any AgentNetworkPairingIngressBindingV2,
        interactiveBinder: any AgentNetworkInteractiveIngressBindingV2 =
            AgentNetworkRejectingInteractiveIngressBinderV2(),
        interactivePairReady: (@Sendable (
            AgentInteractiveReadyRolePairV0
        ) async throws -> Void)? = nil,
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
        self.interactiveBinder = interactiveBinder
        self.interactivePairReady = interactivePairReady
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
        guard !cancelled, admissionOpen else {
            accepted.cancel()
            return
        }
        let candidate = Pending(
            token: UUID(),
            accepted: accepted,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds
        )
        if pending != nil || classifying != nil || bindingToken != nil {
            guard queued.count < Self.maximumQueuedCandidates else {
                accepted.cancel()
                return
            }
            queued.append(candidate)
            notifyStateChanged()
            return
        }
        try start(candidate)
    }

    private func start(_ candidate: Pending) throws {
        pending = candidate
        notifyStateChanged()
        do {
            try candidate.accepted.start(
                queue: queue,
                ready: { [weak self] verified in
                    Task {
                        await self?.ready(
                            verified,
                            token: candidate.token
                        )
                    }
                },
                terminal: { [weak self] reason in
                    Task {
                        await self?.acceptedEnded(
                            reason,
                            token: candidate.token
                        )
                    }
                }
            )
        } catch {
            if pending?.token == candidate.token { pending = nil }
            candidate.accepted.cancel()
            notifyStateChanged()
            throw error
        }
    }

    public func cancel() async {
        guard !cancelled else { return }
        cancelled = true
        admissionOpen = false
        let pending = self.pending
        let queued = self.queued
        let classifying = self.classifying
        let primary = activePrimary
        let pairing = activePairing
        let interactiveInput = activeInteractiveInput
        let interactiveMedia = activeInteractiveMedia
        let binding = bindingConnection
        self.pending = nil
        self.queued = []
        self.classifying = nil
        bindingToken = nil
        bindingRole = nil
        bindingConnection = nil
        activePrimary = nil
        activePairing = nil
        activeInteractiveInput = nil
        activeInteractiveMedia = nil
        pending?.accepted.cancel()
        for candidate in queued { candidate.accepted.cancel() }
        if let classifying { await classifying.classifier.cancel() }
        if let binding { await binding.connection.cancel() }
        if let primary { await primary.connection.cancel() }
        if let pairing { await pairing.connection.cancel() }
        if let interactiveInput {
            await interactiveInput.connection.cancel()
        }
        if let interactiveMedia {
            await interactiveMedia.connection.cancel()
        }
        notifyStateChanged()
    }

    /// Closes only ingress admission. Established role generations remain
    /// usable until `drainConnections()` so updater shutdown can be ordered
    /// and reversed independently from terminal Agent cancellation.
    package func closeAdmission() async {
        guard !cancelled, admissionOpen else { return }
        admissionOpen = false
        let pending = self.pending
        let queued = self.queued
        let classifying = self.classifying
        let binding = bindingConnection
        self.pending = nil
        self.queued = []
        self.classifying = nil
        bindingToken = nil
        bindingRole = nil
        bindingConnection = nil
        pending?.accepted.cancel()
        for candidate in queued { candidate.accepted.cancel() }
        if let classifying { await classifying.classifier.cancel() }
        if let binding { await binding.connection.cancel() }
        notifyStateChanged()
    }

    package func drainConnections() async {
        guard !cancelled, !admissionOpen else { return }
        let primary = activePrimary
        let pairing = activePairing
        let interactiveInput = activeInteractiveInput
        let interactiveMedia = activeInteractiveMedia
        activePrimary = nil
        activePairing = nil
        activeInteractiveInput = nil
        activeInteractiveMedia = nil
        if let primary { await primary.connection.cancel() }
        if let pairing { await pairing.connection.cancel() }
        if let interactiveInput {
            await interactiveInput.connection.cancel()
        }
        if let interactiveMedia {
            await interactiveMedia.connection.cancel()
        }
        notifyStateChanged()
    }

    package func reopenAdmission() {
        guard !cancelled, !admissionOpen else { return }
        admissionOpen = true
        notifyStateChanged()
    }

    public func snapshot() -> AgentNetworkListenerIngressSnapshotV2 {
        AgentNetworkListenerIngressSnapshotV2(
            isCancelled: cancelled,
            hasPendingTLS: pending != nil || !queued.isEmpty,
            isClassifying: classifying != nil,
            bindingRole: bindingRole,
            hasActivePrimary: activePrimary != nil,
            hasActivePairing: activePairing != nil,
            hasActiveInteractiveInput: activeInteractiveInput != nil,
            hasActiveInteractiveMedia: activeInteractiveMedia != nil
        )
    }

    /// Sends only through the exact authenticated primary generation that is
    /// active at both ends of the suspension. The connection owns wire-lane
    /// validation and serialized framing; this authority owns replacement.
    public func hasAuthenticatedPrimaryEventSink(
        primaryConnectionID: Data
    ) async -> Bool {
        guard !cancelled, primaryConnectionID.count == 16,
              let primary = activePrimary else { return false }
        let authenticatedID = await primary.connection
            .authenticatedPrimaryConnectionID()
        let matches = authenticatedID == primaryConnectionID
        guard !cancelled, activePrimary?.token == primary.token else {
            return false
        }
        return matches
    }

    public func sendAuthenticatedPrimaryEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        guard !cancelled, let primary = activePrimary else {
            throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
        }
        let authenticatedID = await primary.connection
            .authenticatedPrimaryConnectionID()
        guard !cancelled, activePrimary?.token == primary.token,
              primaryConnectionID.count == 16,
              authenticatedID == primaryConnectionID else {
            throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
        }
        try await primary.connection.sendAuthenticatedEvent(
            eventJSON,
            primaryConnectionID: primaryConnectionID
        )
        guard !cancelled, activePrimary?.token == primary.token else {
            throw AgentNetworkAuthenticatedEventSinkErrorV2.primaryReplaced
        }
    }

    private func ready(
        _ verified: NetworkHostVerifiedReadyConnectionV0,
        token: UUID
    ) async {
        guard !cancelled, admissionOpen,
              let pending, pending.token == token else {
            verified.cancel()
            advanceQueue()
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
            advanceQueue()
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
            agentNetworkIngressLoggerV2.error(
                "connection classification failed: \(String(describing: error), privacy: .public)"
            )
            if classifying?.token == token {
                classifying = nil
                notifyStateChanged()
                ingressTerminal(.classificationFailed)
                advanceQueue()
            }
            return
        }
        guard !cancelled, admissionOpen,
              classifying?.token == token else {
            classified.cancel()
            advanceQueue()
            return
        }
        classifying = nil
        agentNetworkIngressLoggerV2.notice(
            "connection classified role=\(classified.role.rawValue, privacy: .public)"
        )
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
        guard !cancelled, admissionOpen else {
            classified.cancel()
            return
        }
        if classified.role == .pairing, activePairing != nil {
            classified.cancel()
            advanceQueue()
            return
        }
        if classified.role == .interactiveInput,
           activeInteractiveInput != nil {
            classified.cancel()
            advanceQueue()
            return
        }
        if classified.role == .interactiveMedia,
           activeInteractiveMedia != nil {
            classified.cancel()
            advanceQueue()
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
            case .interactiveInput, .interactiveMedia:
                let role = classified.role
                bound = try await interactiveBinder.bindInteractiveIngress(
                    classifiedConnection: classified,
                    terminal: { [weak self] reason in
                        let value = AgentNetworkIngressTerminationV2
                            .interactive(role: role, reason: reason)
                        if latch.record(value) {
                            Task {
                                await self?.roleEnded(
                                    value,
                                    role: role,
                                    token: token
                                )
                            }
                        }
                    }
                )
            }
        } catch {
            agentNetworkIngressLoggerV2.error(
                "connection bind failed role=\(classified.role.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            if bindingToken == token {
                bindingToken = nil
                bindingRole = nil
                notifyStateChanged()
            }
            classified.cancel()
            advanceQueue()
            return
        }
        guard !cancelled, admissionOpen, bindingToken == token else {
            await bound.cancel()
            advanceQueue()
            return
        }
        bindingConnection = Active(
            token: token,
            connection: bound,
            interactiveChannel: nil,
            interactiveConnection: nil
        )
        do {
            try await bound.begin()
        } catch {
            agentNetworkIngressLoggerV2.error(
                "connection begin failed role=\(classified.role.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            let stillOwned = bindingToken == token
                || bindingConnection?.token == token
            if stillOwned {
                bindingToken = nil
                bindingRole = nil
                bindingConnection = nil
                await bound.cancel()
            }
            notifyStateChanged()
            advanceQueue()
            return
        }
        guard !cancelled, admissionOpen, bindingToken == token,
              bindingConnection?.token == token else {
            if bindingConnection?.token == token {
                bindingConnection = nil
                await bound.cancel()
            }
            advanceQueue()
            return
        }
        if let reason = latch.activate() {
            bindingToken = nil
            bindingRole = nil
            bindingConnection = nil
            await bound.cancel()
            notifyStateChanged()
            ingressTerminal(reason)
            advanceQueue()
            return
        }
        bindingToken = nil
        bindingRole = nil
        bindingConnection = nil
        let readyChannel = await bound.readyInteractiveChannel()
        let readyConnection = await bound.readyInteractiveConnection()
        if classified.role == .interactiveInput
            || classified.role == .interactiveMedia {
            guard let readyChannel,
                  ingressRole(for: readyChannel.role) == classified.role else {
                await bound.cancel()
                notifyStateChanged()
                ingressTerminal(.interactive(
                    role: classified.role,
                    reason: .authorityRejected
                ))
                advanceQueue()
                return
            }
            let peer = classified.role == .interactiveInput
                ? activeInteractiveMedia : activeInteractiveInput
            if let peerChannel = peer?.interactiveChannel,
               !sameInteractiveSession(readyChannel, peerChannel) {
                await bound.cancel()
                if let peer { await peer.connection.cancel() }
                activeInteractiveInput = nil
                activeInteractiveMedia = nil
                notifyStateChanged()
                ingressTerminal(.interactive(
                    role: classified.role,
                    reason: .authorityRejected
                ))
                advanceQueue()
                return
            }
        }
        let active = Active(
            token: token,
            connection: bound,
            interactiveChannel: readyChannel,
            interactiveConnection: readyConnection
        )
        switch classified.role {
        case .applicationPrimary:
            let previous = activePrimary
            activePrimary = active
            if let previous { await previous.connection.cancel() }
        case .pairing:
            activePairing = active
        case .interactiveInput:
            activeInteractiveInput = active
        case .interactiveMedia:
            activeInteractiveMedia = active
        }
        agentNetworkIngressLoggerV2.notice(
            "connection active role=\(classified.role.rawValue, privacy: .public)"
        )
        notifyStateChanged()
        if classified.role == .interactiveInput
            || classified.role == .interactiveMedia {
            await activateInteractivePairIfReady(
                triggeringRole: classified.role
            )
        }
        advanceQueue()
    }

    private func acceptedEnded(
        _ reason: NetworkHostAcceptedConnectionTerminationReasonV0,
        token: UUID
    ) {
        guard pending?.token == token else { return }
        pending = nil
        notifyStateChanged()
        acceptedTerminal(reason)
        advanceQueue()
    }

    private func roleEnded(
        _ reason: AgentNetworkIngressTerminationV2,
        role: NetworkHostIngressRoleV0,
        token: UUID
    ) async {
        agentNetworkIngressLoggerV2.notice(
            "connection ended role=\(role.rawValue, privacy: .public) reason=\(String(describing: reason), privacy: .public)"
        )
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
        case .interactiveInput:
            guard activeInteractiveInput?.token == token else { return }
            activeInteractiveInput = nil
            let peer = activeInteractiveMedia
            activeInteractiveMedia = nil
            if let peer { await peer.connection.cancel() }
        case .interactiveMedia:
            guard activeInteractiveMedia?.token == token else { return }
            activeInteractiveMedia = nil
            let peer = activeInteractiveInput
            activeInteractiveInput = nil
            if let peer { await peer.connection.cancel() }
        }
        notifyStateChanged()
        ingressTerminal(reason)
    }

    package func serviceSnapshot() -> AgentNetworkListenerHandoffSnapshotV1 {
        AgentNetworkListenerHandoffSnapshotV1(
            isCancelled: cancelled,
            hasPendingTLS: pending != nil || !queued.isEmpty
                || classifying != nil,
            isBinding: bindingToken != nil,
            hasActivePrimary: activePrimary != nil
        )
    }

    private func notifyStateChanged() {
        guard stateRevision < UInt64.max else { return }
        stateRevision += 1
        stateChanged(stateRevision)
    }

    private func advanceQueue() {
        guard !cancelled, admissionOpen,
              pending == nil, classifying == nil,
              bindingToken == nil, !queued.isEmpty else { return }
        let candidate = queued.removeFirst()
        do {
            try start(candidate)
        } catch {
            acceptedTerminal(.connectionFailed)
            advanceQueue()
        }
    }

    private func ingressRole(
        for role: InteractiveChannelRoleName
    ) -> NetworkHostIngressRoleV0 {
        switch role {
        case .input: .interactiveInput
        case .media: .interactiveMedia
        }
    }

    private func sameInteractiveSession(
        _ lhs: HostInteractiveReadyRoleChannelV0,
        _ rhs: HostInteractiveReadyRoleChannelV0
    ) -> Bool {
        lhs.clientID == rhs.clientID
            && lhs.primaryConnectionID == rhs.primaryConnectionID
            && lhs.interactiveSessionID == rhs.interactiveSessionID
            && lhs.authorizationEpoch == rhs.authorizationEpoch
    }

    private func activateInteractivePairIfReady(
        triggeringRole: NetworkHostIngressRoleV0
    ) async {
        guard let interactivePairReady,
              let input = activeInteractiveInput,
              let media = activeInteractiveMedia else { return }
        guard let inputConnection = input.interactiveConnection,
              let mediaConnection = media.interactiveConnection else {
            await rejectInteractivePair(
                input: input,
                media: media,
                triggeringRole: triggeringRole
            )
            return
        }
        do {
            let pair = try AgentInteractiveReadyRolePairV0(
                input: inputConnection,
                media: mediaConnection
            )
            try await interactivePairReady(pair)
        } catch {
            guard activeInteractiveInput?.token == input.token,
                  activeInteractiveMedia?.token == media.token else {
                return
            }
            await rejectInteractivePair(
                input: input,
                media: media,
                triggeringRole: triggeringRole
            )
        }
    }

    private func rejectInteractivePair(
        input: Active,
        media: Active,
        triggeringRole: NetworkHostIngressRoleV0
    ) async {
        guard activeInteractiveInput?.token == input.token,
              activeInteractiveMedia?.token == media.token else { return }
        activeInteractiveInput = nil
        activeInteractiveMedia = nil
        await input.connection.cancel()
        await media.connection.cancel()
        notifyStateChanged()
        ingressTerminal(.interactive(
            role: triggeringRole,
            reason: .authorityRejected
        ))
    }
}
