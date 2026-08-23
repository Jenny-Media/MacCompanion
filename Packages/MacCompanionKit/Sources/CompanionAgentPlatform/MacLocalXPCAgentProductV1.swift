#if os(macOS)
import CompanionAgent
import CompanionLocalXPCPlatform
import Foundation

@available(macOS 26.0, *)
package protocol MacLocalXPCAgentServerV1: AnyObject, Sendable {
    func start() throws
    func cancel()
    func cancelPeer(generation: UInt64)
    func authenticatedMenuPresentationEndpoint(
        generation: UInt64
    ) async -> (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)?
}

@available(macOS 26.0, *)
extension MacLocalXPCServerV1: MacLocalXPCAgentServerV1 {}

@available(macOS 26.0, *)
extension MacLocalXPCAgentServerV1 {
    package func authenticatedMenuPresentationEndpoint(
        generation _: UInt64
    ) async -> (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)? {
        nil
    }
}

@available(macOS 26.0, *)
private actor MacLocalXPCAgentPresentationBindingV1 {
    typealias SurfaceHandler = @Sendable (
        MacLocalXPCAuthenticatedMenuSurfacesV1
    ) async throws -> Void

    private let server: any MacLocalXPCAgentServerV1
    private let router: MacLocalXPCAuthenticatedMenuSurfaceRouterV1
    private let onSurfaces: SurfaceHandler
    private let onInvalidated: @Sendable (UInt64) async -> Void
    private var boundGeneration: UInt64?
    private var terminal = false

    init(
        server: any MacLocalXPCAgentServerV1,
        router: MacLocalXPCAuthenticatedMenuSurfaceRouterV1,
        onSurfaces: @escaping SurfaceHandler,
        onInvalidated: @escaping @Sendable (UInt64) async -> Void
    ) {
        self.server = server
        self.router = router
        self.onSurfaces = onSurfaces
        self.onInvalidated = onInvalidated
    }

    func receive(
        _ disposition: MacLocalXPCLifecycleBindingDispositionV1
    ) async {
        guard !terminal else { return }
        switch disposition {
        case .authenticatedWithoutReadiness(let generation):
            await revokeBoundGeneration(replacedBy: generation)
        case .ignoredStale:
            return
        case .readinessPublished(let generation):
            await revokeBoundGeneration(replacedBy: generation)
            guard let endpoint = await server
                .authenticatedMenuPresentationEndpoint(
                    generation: generation
                ) else {
                server.cancelPeer(generation: generation)
                return
            }
            do {
                let surfaces = try await router.bindAuthenticated(
                    generation: generation,
                    endpointFactory: { endpoint }
                )
                boundGeneration = generation
                try await onSurfaces(surfaces)
            } catch {
                let deliveredGeneration = boundGeneration == generation
                if deliveredGeneration {
                    boundGeneration = nil
                }
                _ = await router.invalidate(generation: generation)
                if deliveredGeneration {
                    await onInvalidated(generation)
                }
                server.cancelPeer(generation: generation)
            }
        case .invalidated, .failedClosed:
            await revokeBoundGeneration()
        }
    }

    func endpointTerminated(generation: UInt64) async {
        guard !terminal, boundGeneration == generation else { return }
        boundGeneration = nil
        // The router has already become terminal. Cancel only the exact peer
        // that owned the endpoint, then synchronously remove the downstream
        // authority before the endpoint's terminal-fence request returns.
        server.cancelPeer(generation: generation)
        await onInvalidated(generation)
    }

    private func revokeBoundGeneration(replacedBy generation: UInt64? = nil)
        async
    {
        guard let boundGeneration,
              boundGeneration != generation else {
            return
        }
        self.boundGeneration = nil
        _ = await router.invalidate(generation: boundGeneration)
        await onInvalidated(boundGeneration)
    }

    func finish() async {
        guard !terminal else {
            await router.finish()
            return
        }
        terminal = true
        boundGeneration = nil
        await router.finish()
    }
}

@available(macOS 26.0, *)
private final class MacLocalXPCAgentPresentationBindingBoxV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var binding: MacLocalXPCAgentPresentationBindingV1?

    func install(_ binding: MacLocalXPCAgentPresentationBindingV1) {
        lock.withLock {
            precondition(self.binding == nil)
            self.binding = binding
        }
    }

    func receive(
        _ disposition: MacLocalXPCLifecycleBindingDispositionV1
    ) async {
        let binding = lock.withLock { self.binding }
        await binding?.receive(disposition)
    }

    func endpointTerminated(generation: UInt64) async {
        let binding = lock.withLock { self.binding }
        await binding?.endpointTerminated(generation: generation)
    }
}

@available(macOS 26.0, *)
private final class MacLocalXPCAgentRuntimeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var server: (any MacLocalXPCAgentServerV1)?
    private var pump: MacLocalXPCLifecycleEventPumpV1?
    private var presentationBinding:
        MacLocalXPCAgentPresentationBindingV1?
    private var startTask: Task<Void, Error>?
    private var shutdownTask: Task<Void, Never>?

    func install(
        server: any MacLocalXPCAgentServerV1,
        pump: MacLocalXPCLifecycleEventPumpV1,
        presentationBinding:
            MacLocalXPCAgentPresentationBindingV1? = nil
    ) {
        lock.lock()
        precondition(self.server == nil && self.pump == nil)
        self.server = server
        self.pump = pump
        self.presentationBinding = presentationBinding
        lock.unlock()
    }

    func start() async throws {
        let task = lock.withLock {
            guard let server,
                  startTask == nil,
                  shutdownTask == nil else {
                return nil as Task<Void, Error>?
            }
            let task = Task {
                try Task.checkCancellation()
                try server.start()
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

    func consume(_ event: MacLocalXPCServerEventV1) {
        let pump = lock.withLock { self.pump }
        pump?.consume(event)
    }

    func cancelPeer(generation: UInt64) {
        let server = lock.withLock { self.server }
        server?.cancelPeer(generation: generation)
    }

    func cancelServer() {
        let server = lock.withLock { self.server }
        server?.cancel()
    }

    func finish() async {
        await beginShutdown().value
    }

    private func beginShutdown() -> Task<Void, Never> {
        lock.withLock {
            if let shutdownTask { return shutdownTask }
            let startTask = self.startTask
            let pump = self.pump
            let presentationBinding = self.presentationBinding
            let server = self.server
            startTask?.cancel()
            let task = Task {
                if let startTask { _ = await startTask.result }
                if let pump {
                    await pump.finish()
                } else {
                    server?.cancel()
                }
                await presentationBinding?.finish()
            }
            shutdownTask = task
            return task
        }
    }

    deinit {
        lock.withLock { startTask?.cancel() }
        cancelServer()
    }
}

/// Owns the authenticated menu XPC server, lifecycle event pump, and typed
/// status reader as one fail-closed product. The public constructor accepts
/// only the complete startup-reconciled Agent service graph, so a partial
/// bootstrap cannot publish menu readiness or status authority.
@available(macOS 26.0, *)
public final class MacLocalXPCAgentProductV1: @unchecked Sendable {
    package typealias ServerFactory = @Sendable (
        MacLocalXPCServerProfileV1,
        any MacLocalXPCStatusReadingV1,
        @escaping MacLocalXPCServerV1.EventHandler
    ) -> any MacLocalXPCAgentServerV1
    package typealias PresentationServerFactory = @Sendable (
        MacLocalXPCServerProfileV1,
        any MacLocalXPCStatusReadingV1,
        any MacLocalXPCMenuPairingCommandHandlingV1,
        any MacLocalXPCInteractiveAdmissionHandlingV1,
        (any MacLocalXPCInteractiveMediaHandlingV1)?,
        @escaping MacLocalXPCServerV1.EventHandler
    ) -> any MacLocalXPCAgentServerV1

    private let runtime: MacLocalXPCAgentRuntimeV1

    public static func afterAgentBootstrap(
        services: AgentPrimaryServicesV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        agentGeneration: UUID = UUID(),
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        transitionIDSource: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> MacLocalXPCAgentProductV1 {
        let observations = try await MacAgentLifecycleObservationRootV1
            .afterAgentBootstrap(
                services: services,
                processStarter: processStarter,
                agentGeneration: agentGeneration,
                wallClock: wallClock,
                transitionIDSource: transitionIDSource
            )
        return compose(
            lifecycleFactory: observations,
            statusReader: MacLocalXPCStatusReaderV1(
                statusReader: services.localServices.statusReader
            )
        )
    }

    package static func afterAgentBootstrapWithMenuPresentation(
        services: AgentPrimaryServicesV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        agentGeneration: UUID = UUID(),
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        transitionIDSource: @escaping @Sendable () -> UUID = { UUID() },
        menuPairingCommandHandler:
            any MacLocalXPCMenuPairingCommandHandlingV1,
        interactiveAdmissionHandler:
            any MacLocalXPCInteractiveAdmissionHandlingV1,
        interactiveMediaHandler:
            (any MacLocalXPCInteractiveMediaHandlingV1)? = nil,
        onSurfaces: @escaping @Sendable (
            MacLocalXPCAuthenticatedMenuSurfacesV1
        ) async throws -> Void,
        onSurfaceInvalidated: @escaping @Sendable (UInt64) async -> Void
    ) async throws -> MacLocalXPCAgentProductV1 {
        let observations = try await MacAgentLifecycleObservationRootV1
            .afterAgentBootstrap(
                services: services,
                processStarter: processStarter,
                agentGeneration: agentGeneration,
                wallClock: wallClock,
                transitionIDSource: transitionIDSource
            )
        return composeWithMenuPresentation(
            lifecycleFactory: observations,
            statusReader: MacLocalXPCStatusReaderV1(
                statusReader: services.localServices.statusReader
            ),
            menuPairingCommandHandler: menuPairingCommandHandler,
            interactiveAdmissionHandler: interactiveAdmissionHandler,
            interactiveMediaHandler: interactiveMediaHandler,
            onSurfaces: onSurfaces,
            onSurfaceInvalidated: onSurfaceInvalidated
        )
    }

    package static func compose(
        lifecycleFactory:
            any MacLocalXPCMenuLifecycleConnectionFactoryV1,
        statusReader: any MacLocalXPCStatusReadingV1,
        serverFactory: @escaping ServerFactory = {
            profile, statusReader, onEvent in
            MacLocalXPCServerV1(
                profile: profile,
                statusReader: statusReader,
                onEvent: onEvent
            )
        }
    ) -> MacLocalXPCAgentProductV1 {
        let runtime = MacLocalXPCAgentRuntimeV1()
        let binding = MacLocalXPCLifecycleBindingV1(
            factory: lifecycleFactory
        )
        let pump = MacLocalXPCLifecycleEventPumpV1(
            binding: binding,
            onFailedClosed: { [weak runtime] generation in
                runtime?.cancelPeer(generation: generation)
            },
            onShutdown: { [weak runtime] in
                runtime?.cancelServer()
            }
        )
        let server = serverFactory(
            .menuLifecycleReadinessAndStatus,
            statusReader,
            { [weak runtime] event in
                runtime?.consume(event)
            }
        )
        runtime.install(server: server, pump: pump)
        return MacLocalXPCAgentProductV1(runtime: runtime)
    }

    /// Package construction seam that additionally binds the exact current
    /// authenticated-and-ready menu generation to the five closed
    /// presentation capabilities. Permanent targets remain unable to select
    /// this profile directly.
    package static func composeWithMenuPresentation(
        lifecycleFactory:
            any MacLocalXPCMenuLifecycleConnectionFactoryV1,
        statusReader: any MacLocalXPCStatusReadingV1,
        menuPairingCommandHandler:
            any MacLocalXPCMenuPairingCommandHandlingV1,
        interactiveAdmissionHandler:
            any MacLocalXPCInteractiveAdmissionHandlingV1,
        interactiveMediaHandler:
            (any MacLocalXPCInteractiveMediaHandlingV1)? = nil,
        onSurfaces: @escaping @Sendable (
            MacLocalXPCAuthenticatedMenuSurfacesV1
        ) async throws -> Void,
        onSurfaceInvalidated: @escaping @Sendable (UInt64) async -> Void = {
            _ in
        },
        serverFactory: @escaping PresentationServerFactory = {
            profile, statusReader, commandHandler, admissionHandler,
            mediaHandler, onEvent in
            MacLocalXPCServerV1(
                profile: profile,
                statusReader: statusReader,
                menuPairingCommandHandler: commandHandler,
                interactiveAdmissionHandler: admissionHandler,
                interactiveMediaHandler: mediaHandler,
                onEvent: onEvent
            )
        }
    ) -> MacLocalXPCAgentProductV1 {
        let runtime = MacLocalXPCAgentRuntimeV1()
        let binding = MacLocalXPCLifecycleBindingV1(
            factory: lifecycleFactory
        )
        let presentationBox =
            MacLocalXPCAgentPresentationBindingBoxV1()
        let pump = MacLocalXPCLifecycleEventPumpV1(
            binding: binding,
            onFailedClosed: { [weak runtime] generation in
                runtime?.cancelPeer(generation: generation)
            },
            onDisposition: { disposition in
                await presentationBox.receive(disposition)
            },
            onShutdown: { [weak runtime] in
                runtime?.cancelServer()
            }
        )
        let server = serverFactory(
            .menuLifecycleReadinessStatusAndPresentation,
            statusReader,
            menuPairingCommandHandler,
            interactiveAdmissionHandler,
            interactiveMediaHandler,
            { [weak runtime] event in
                runtime?.consume(event)
            }
        )
        let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1(
            onEndpointTerminal: { generation in
                await presentationBox.endpointTerminated(
                    generation: generation
                )
            }
        )
        let presentationBinding = MacLocalXPCAgentPresentationBindingV1(
            server: server,
            router: router,
            onSurfaces: onSurfaces,
            onInvalidated: onSurfaceInvalidated
        )
        presentationBox.install(presentationBinding)
        runtime.install(
            server: server,
            pump: pump,
            presentationBinding: presentationBinding
        )
        return MacLocalXPCAgentProductV1(runtime: runtime)
    }

    private init(runtime: MacLocalXPCAgentRuntimeV1) {
        self.runtime = runtime
    }

    public func start() async throws {
        try await runtime.start()
    }

    /// Fences event admission, waits for any admitted start transaction,
    /// cancels the XPC server, and awaits exact lifecycle retirement. Repeated
    /// calls await the same terminal cleanup task.
    public func finish() async {
        await runtime.finish()
    }
}
#endif
