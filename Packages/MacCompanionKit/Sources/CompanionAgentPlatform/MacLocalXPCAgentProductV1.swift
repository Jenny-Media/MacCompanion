#if os(macOS)
import CompanionAgent
import CompanionLocalXPCPlatform
import Foundation

@available(macOS 26.0, *)
package protocol MacLocalXPCAgentServerV1: AnyObject, Sendable {
    func start() throws
    func cancel()
    func cancelPeer(generation: UInt64)
}

@available(macOS 26.0, *)
extension MacLocalXPCServerV1: MacLocalXPCAgentServerV1 {}

@available(macOS 26.0, *)
private final class MacLocalXPCAgentRuntimeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var server: (any MacLocalXPCAgentServerV1)?
    private var pump: MacLocalXPCLifecycleEventPumpV1?
    private var startTask: Task<Void, Error>?
    private var shutdownTask: Task<Void, Never>?

    func install(
        server: any MacLocalXPCAgentServerV1,
        pump: MacLocalXPCLifecycleEventPumpV1
    ) {
        lock.lock()
        precondition(self.server == nil && self.pump == nil)
        self.server = server
        self.pump = pump
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
            let server = self.server
            startTask?.cancel()
            let task = Task {
                if let startTask { _ = await startTask.result }
                if let pump {
                    await pump.finish()
                } else {
                    server?.cancel()
                }
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
