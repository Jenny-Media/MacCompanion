#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import CompanionMacApp
import Foundation

@available(macOS 26.0, *)
package protocol MacLocalXPCDashboardClientV1: AnyObject, Sendable {
    func start() throws
    func publishMenuReady()
    func readAgentStatus()
    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0
    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0
    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0
    func closeNetworkAdmissionForUpdate() async throws
    func drainNetworkConnectionsForUpdate() async throws
    func reopenNetworkAdmissionAfterUpdateFailure() async throws
    func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1
    func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) async throws
    func cancel()
    func finishMenuPresentationReceiver() async
}

@available(macOS 26.0, *)
extension MacLocalXPCClientV1: MacLocalXPCDashboardClientV1 {}

@available(macOS 26.0, *)
extension MacLocalXPCDashboardClientV1 {
    package func createPairingSession(
        _: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func dismissPairingSession(
        _: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func resolveLocalApproval(
        _: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func closeNetworkAdmissionForUpdate() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }

    package func drainNetworkConnectionsForUpdate() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }

    package func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }

    package func publishInteractiveAdmission(
        _: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        throw MacLocalXPCInteractiveAdmissionErrorV1.unavailable
    }

    package func publishInteractiveMedia(
        header _: MediaRecordHeader,
        payload _: Data
    ) async throws {
        throw MacLocalXPCInteractiveRoleDataErrorV1.unavailable
    }
}

@available(macOS 26.0, *)
private actor MacLocalXPCDashboardBindingV1 {
    private enum Phase {
        case idle
        case starting
        case authenticated
        case ready
        case invalidated
    }

    private let owner: MacAgentDashboardApplicationOwnerV0
    private let client: any MacLocalXPCDashboardClientV1
    private let agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0
    private let publishesInteractiveAdmission: Bool
    private let menuAppGeneration: UUID
    private let initialSelectedDisplayID: UUID?
    private var token: MacAgentDashboardConnectionTokenV0?
    private var transportGeneration: UInt64?
    private var statusReadOutstanding = false
    private var statusRefreshInProgress = false
    private var statusRetryPermitted = false
    private var phase: Phase = .idle

    init(
        owner: MacAgentDashboardApplicationOwnerV0,
        client: any MacLocalXPCDashboardClientV1,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0,
        publishesInteractiveAdmission: Bool,
        menuAppGeneration: UUID,
        initialSelectedDisplayID: UUID?
    ) {
        self.owner = owner
        self.client = client
        self.agentBuildLifetime = agentBuildLifetime
        self.publishesInteractiveAdmission = publishesInteractiveAdmission
        self.menuAppGeneration = menuAppGeneration
        self.initialSelectedDisplayID = initialSelectedDisplayID
    }

    func begin() async throws {
        guard phase == .idle else {
            throw MacLocalXPCConstructionErrorV1.alreadyStarted
        }
        phase = .starting
        do {
            let preparedToken = try await owner.beginConnection()
            guard phase == .starting else {
                try? await owner.connectionUnavailable(preparedToken)
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }
            token = preparedToken
            transportGeneration = nil
            statusReadOutstanding = false
            statusRefreshInProgress = false
            statusRetryPermitted = false
        } catch {
            if phase == .starting { retire() }
            throw error
        }
    }

    func receive(_ event: MacLocalXPCClientEventV1) async {
        guard let token else {
            retire()
            client.cancel()
            return
        }
        do {
            switch event {
            case let .authenticatedAgent(build):
                guard phase == .starting else { throw BindingError.order }
                try agentBuildLifetime.authenticate(build: build)
                phase = .authenticated
                client.publishMenuReady()

            case .menuReadyAcknowledged:
                guard phase == .authenticated else {
                    throw BindingError.order
                }
                if publishesInteractiveAdmission {
                    let publication = try
                        LocalInteractiveAdmissionPublicationV1(
                            commandID: UUID(),
                            menuAppGeneration: menuAppGeneration,
                            revision: 1,
                            selectedDisplayID: initialSelectedDisplayID
                        )
                    _ = try await client.publishInteractiveAdmission(
                        publication
                    )
                }
                phase = .ready
                statusReadOutstanding = true
                client.readAgentStatus()

            case let .agentStatus(generation, snapshot):
                try requireReadyGeneration(generation)
                guard statusReadOutstanding else { throw BindingError.order }
                statusReadOutstanding = false
                statusRetryPermitted = false
                try await owner.receive(snapshot, from: token)

            case let .agentStatusUnavailable(generation):
                try requireReadyGeneration(generation)
                guard statusReadOutstanding else { throw BindingError.order }
                statusReadOutstanding = false
                statusRetryPermitted = true
                try await owner.statusTemporarilyUnavailable(from: token)

            case .invalidated:
                retire()
                try await owner.connectionUnavailable(token)
            }
        } catch {
            await failClosed(token: token)
        }
    }

    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        guard phase == .ready,
              statusRetryPermitted,
              !statusReadOutstanding,
              !statusRefreshInProgress,
              let token else { return .notCompleted }
        statusRetryPermitted = false
        statusRefreshInProgress = true
        do {
            try await owner.statusRefreshStarted(from: token)
            guard phase == .ready,
                  self.token == token,
                  statusRefreshInProgress else {
                return .notCompleted
            }
            statusRefreshInProgress = false
            statusReadOutstanding = true
            client.readAgentStatus()
            return .completed
        } catch {
            guard self.token == token else { return .notCompleted }
            statusRefreshInProgress = false
            await failClosed(token: token)
            return .notCompleted
        }
    }

    func invalidate() async {
        guard let token else {
            retire()
            return
        }
        retire()
        do {
            try await owner.connectionUnavailable(token)
        } catch {
            await owner.applicationInvalidated()
        }
    }

    private func requireReadyGeneration(_ generation: UInt64) throws {
        guard phase == .ready else { throw BindingError.order }
        if let transportGeneration {
            guard transportGeneration == generation else {
                throw BindingError.staleGeneration
            }
        } else {
            transportGeneration = generation
        }
    }

    private func failClosed(token: MacAgentDashboardConnectionTokenV0) async {
        client.cancel()
        retire()
        do {
            try await owner.connectionUnavailable(token)
        } catch {
            await owner.applicationInvalidated()
        }
    }

    private func retire() {
        agentBuildLifetime.retire()
        token = nil
        transportGeneration = nil
        statusReadOutstanding = false
        statusRefreshInProgress = false
        statusRetryPermitted = false
        phase = .invalidated
    }

    private enum BindingError: Error {
        case order
        case staleGeneration
    }
}

@available(macOS 26.0, *)
private final class MacLocalXPCDashboardRuntimeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptingEvents = false
    private var client: (any MacLocalXPCDashboardClientV1)?
    private var binding: MacLocalXPCDashboardBindingV1?
    private var agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0?
    private var continuation:
        AsyncStream<MacLocalXPCClientEventV1>.Continuation?
    private var drainTask: Task<Void, Never>?
    private var startTask: Task<Void, Error>?
    private var shutdownTask: Task<Void, Never>?

    func install(
        client: any MacLocalXPCDashboardClientV1,
        binding: MacLocalXPCDashboardBindingV1,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0,
        bufferCapacity: Int
    ) {
        let pair = AsyncStream<MacLocalXPCClientEventV1>.makeStream(
            bufferingPolicy: .bufferingOldest(max(1, bufferCapacity))
        )
        let task = Task { [weak binding] in
            for await event in pair.stream {
                guard !Task.isCancelled, let binding else { break }
                await binding.receive(event)
            }
        }
        lock.lock()
        precondition(self.client == nil && self.binding == nil)
        self.client = client
        self.binding = binding
        self.agentBuildLifetime = agentBuildLifetime
        continuation = pair.continuation
        drainTask = task
        lock.unlock()
    }

    func start() async throws {
        let task = lock.withLock {
            guard let client, let binding,
                  startTask == nil,
                  shutdownTask == nil else {
                return nil as Task<Void, Error>?
            }
            acceptingEvents = true
            let task = Task {
                try await binding.begin()
                try Task.checkCancellation()
                try client.start()
                try Task.checkCancellation()
            }
            startTask = task
            return task
        }
        guard let task else {
            throw MacLocalXPCConstructionErrorV1.alreadyStarted
        }
        do {
            try await task.value
        } catch {
            await beginShutdown().value
            if error is CancellationError {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }
            throw error
        }
        if let shutdownTask = lock.withLock({ self.shutdownTask }) {
            await shutdownTask.value
            throw MacLocalXPCConstructionErrorV1.alreadyStarted
        }
    }

    func consume(_ event: MacLocalXPCClientEventV1) {
        let continuation = lock.withLock {
            acceptingEvents ? self.continuation : nil
        }
        guard let continuation else { return }
        switch continuation.yield(event) {
        case .enqueued:
            if case .invalidated = event {
                _ = beginShutdown()
            }
        case .dropped, .terminated:
            _ = beginShutdown()
        @unknown default:
            _ = beginShutdown()
        }
    }

    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        let binding = lock.withLock {
            acceptingEvents && shutdownTask == nil ? self.binding : nil
        }
        return await binding?.retryStatus() ?? .notCompleted
    }

    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        guard let client = lock.withLock({
            acceptingEvents && shutdownTask == nil ? self.client : nil
        }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await client.createPairingSession(command)
    }

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        guard let client = lock.withLock({
            acceptingEvents && shutdownTask == nil ? self.client : nil
        }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await client.dismissPairingSession(command)
    }

    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        guard let client = lock.withLock({
            acceptingEvents && shutdownTask == nil ? self.client : nil
        }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await client.resolveLocalApproval(command)
    }

    func closeNetworkAdmissionForUpdate() async throws {
        guard let client = updateQuiescenceClient() else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await client.closeNetworkAdmissionForUpdate()
    }

    func drainNetworkConnectionsForUpdate() async throws {
        guard let client = updateQuiescenceClient() else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await client.drainNetworkConnectionsForUpdate()
    }

    func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        guard let client = updateQuiescenceClient() else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await client.reopenNetworkAdmissionAfterUpdateFailure()
    }

    private func updateQuiescenceClient()
        -> (any MacLocalXPCDashboardClientV1)?
    {
        lock.withLock {
            acceptingEvents && shutdownTask == nil ? client : nil
        }
    }

    func finish() async {
        await beginShutdown().value
    }

    private func beginShutdown() -> Task<Void, Never> {
        lock.withLock {
            if let shutdownTask { return shutdownTask }
            acceptingEvents = false
            let startTask = self.startTask
            let continuation = self.continuation
            let client = self.client
            let binding = self.binding
            agentBuildLifetime?.retire()
            let drainTask = self.drainTask
            startTask?.cancel()
            let task = Task {
                if let startTask { _ = await startTask.result }
                continuation?.finish()
                drainTask?.cancel()
                await client?.finishMenuPresentationReceiver()
                await binding?.invalidate()
                if let drainTask { await drainTask.value }
            }
            shutdownTask = task
            return task
        }
    }

    deinit {
        _ = beginShutdown()
    }
}

/// Menu-app product that preserves callback order, drives the exact hello to
/// readiness to status sequence, and publishes only validated typed snapshots
/// into the existing dashboard owner. Temporary source failure remains
/// retryable on the same authenticated generation; transport loss retires it.
@available(macOS 26.0, *)
public final class MacLocalXPCDashboardProductV1:
    MacAgentDashboardStatusRetryingV0,
    MacPairingLocalIPCClientV0,
    MacPairingReviewLocalIPCClientV0,
    @unchecked Sendable
{
    package typealias ClientFactory = @Sendable (
        @escaping MacLocalXPCClientV1.EventHandler
    ) -> any MacLocalXPCDashboardClientV1

    private let runtime: MacLocalXPCDashboardRuntimeV1

    public init(
        owner: MacAgentDashboardApplicationOwnerV0,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0 = .init(),
        bufferCapacity: Int = 32
    ) {
        self.runtime = Self.makeRuntime(
            owner: owner,
            agentBuildLifetime: agentBuildLifetime,
            bufferCapacity: bufferCapacity,
            clientFactory: { MacLocalXPCClientV1(onEvent: $0) },
            publishesInteractiveAdmission: false
        )
    }

    /// Release-shaped construction seam for the exact menu-owned pairing and
    /// recovery presenters. The transport still does not start until start()
    /// is called, and finish() awaits exact receiver withdrawal.
    public init(
        owner: MacAgentDashboardApplicationOwnerV0,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0 = .init(),
        pairingReviews: any LocalPairingReviewSurfaceV0,
        hostIdentityRecovery:
            any LocalHostIdentityRecoverySurfaceV0,
        interactiveLeaseHandler:
            (any MacLocalXPCInteractiveLeaseHandlingV1)? = nil,
        interactiveInputHandler:
            (any MacLocalXPCInteractiveInputHandlingV1)? = nil,
        interactiveMediaQueue: BoundedInteractiveMediaQueueV0? = nil,
        selectedDisplayID: UUID? = nil,
        bufferCapacity: Int = 32
    ) {
        let surfaces = MacLocalXPCMenuPresentationReceiverSurfacesV1(
            pairingReviews: pairingReviews,
            hostIdentityRecovery: hostIdentityRecovery
        )
        runtime = Self.makeRuntime(
            owner: owner,
            agentBuildLifetime: agentBuildLifetime,
            bufferCapacity: bufferCapacity,
            clientFactory: {
                let client = MacLocalXPCClientV1(
                    presentationSurfaces: surfaces,
                    interactiveLeaseHandler: interactiveLeaseHandler,
                    interactiveInputHandler: interactiveInputHandler,
                    onEvent: $0
                )
                guard let interactiveMediaQueue else { return client }
                return MacLocalXPCInteractiveMediaDrainClientV1(
                    client: client,
                    mediaQueue: interactiveMediaQueue
                )
            },
            publishesInteractiveAdmission: true,
            initialSelectedDisplayID: selectedDisplayID
        )
    }

    package init(
        owner: MacAgentDashboardApplicationOwnerV0,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0 = .init(),
        bufferCapacity: Int = 32,
        publishesInteractiveAdmission: Bool = false,
        initialSelectedDisplayID: UUID? = nil,
        clientFactory: @escaping ClientFactory
    ) {
        runtime = Self.makeRuntime(
            owner: owner,
            agentBuildLifetime: agentBuildLifetime,
            bufferCapacity: bufferCapacity,
            clientFactory: clientFactory,
            publishesInteractiveAdmission: publishesInteractiveAdmission,
            initialSelectedDisplayID: initialSelectedDisplayID
        )
    }

    private static func makeRuntime(
        owner: MacAgentDashboardApplicationOwnerV0,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0,
        bufferCapacity: Int,
        clientFactory: @escaping ClientFactory,
        publishesInteractiveAdmission: Bool,
        initialSelectedDisplayID: UUID? = nil
    ) -> MacLocalXPCDashboardRuntimeV1 {
        let runtime = MacLocalXPCDashboardRuntimeV1()
        let client = clientFactory { [weak runtime] event in
            runtime?.consume(event)
        }
        let binding = MacLocalXPCDashboardBindingV1(
            owner: owner,
            client: client,
            agentBuildLifetime: agentBuildLifetime,
            publishesInteractiveAdmission: publishesInteractiveAdmission,
            menuAppGeneration: UUID(),
            initialSelectedDisplayID: initialSelectedDisplayID
        )
        runtime.install(
            client: client,
            binding: binding,
            agentBuildLifetime: agentBuildLifetime,
            bufferCapacity: bufferCapacity
        )
        return runtime
    }

    public func start() async throws {
        try await runtime.start()
    }

    public func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        await runtime.retryStatus()
    }

    public func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        try await runtime.createPairingSession(command)
    }

    public func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        try await runtime.dismissPairingSession(command)
    }

    public func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        try await runtime.resolveLocalApproval(command)
    }

    public func closeNetworkAdmissionForUpdate() async throws {
        try await runtime.closeNetworkAdmissionForUpdate()
    }

    public func drainNetworkConnectionsForUpdate() async throws {
        try await runtime.drainNetworkConnectionsForUpdate()
    }

    public func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        try await runtime.reopenNetworkAdmissionAfterUpdateFailure()
    }

    public func finish() async {
        await runtime.finish()
    }
}
#endif
