#if os(macOS)
import CompanionLocalXPCPlatform
import Foundation

public protocol MacLocalXPCMenuLifecycleConnectionV1: Sendable {
    func publishReady() async -> MacLifecycleProcessObservationReceiptV1
    func invalidate() async -> MacLifecycleProcessObservationReceiptV1
}

extension MacAuthenticatedMenuLifecycleConnectionV1:
    MacLocalXPCMenuLifecycleConnectionV1
{}

fileprivate struct MacLocalXPCLifecycleRetirementV1: Sendable {
    let transportGeneration: UInt64
    let connection: any MacLocalXPCMenuLifecycleConnectionV1
}

/// A successful call must atomically replace any prior menu observation so
/// the old generation is fenced before this method returns. The lifecycle
/// root implementation provides that contract.
public protocol MacLocalXPCMenuLifecycleConnectionFactoryV1: Sendable {
    func makeLocalXPCMenuLifecycleConnection(
        generation: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1
}

extension MacAgentLifecycleObservationRootV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    public func makeLocalXPCMenuLifecycleConnection(
        generation: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        try await makeAuthenticatedMenuConnection(generation: generation)
    }
}

public enum MacLocalXPCLifecycleBindingDispositionV1:
    Equatable, Sendable
{
    case authenticatedWithoutReadiness(generation: UInt64)
    case readinessPublished(generation: UInt64)
    case invalidated(generation: UInt64)
    case ignoredStale(generation: UInt64)
    case failedClosed(generation: UInt64)
}

/// Converts only transport-authenticated, generation-bound XPC events into the
/// existing lifecycle authority. Hello creates a pending observation but never
/// publishes menu readiness. Only the separate exact menu-ready request may do
/// that. Replacement is delegated to the lifecycle root so an old ready
/// generation is retired before the new generation can become ready.
public actor MacLocalXPCLifecycleBindingV1 {
    public typealias GenerationIDSource =
        @Sendable (UInt64) -> UUID

    private struct Current: Sendable {
        let transportGeneration: UInt64
        let connection: any MacLocalXPCMenuLifecycleConnectionV1
        var readinessPublished: Bool
    }

    private let factory: any MacLocalXPCMenuLifecycleConnectionFactoryV1
    private let generationIDSource: GenerationIDSource
    private var current: Current?
    private var pendingAuthenticationGeneration: UInt64?
    private var operationToken = UUID()

    public init(
        factory: any MacLocalXPCMenuLifecycleConnectionFactoryV1,
        generationIDSource: @escaping GenerationIDSource = { _ in UUID() }
    ) {
        self.factory = factory
        self.generationIDSource = generationIDSource
    }

    @discardableResult
    public func receive(
        _ event: MacLocalXPCServerEventV1
    ) async -> MacLocalXPCLifecycleBindingDispositionV1 {
        switch event {
        case let .authenticatedMenu(generation):
            guard current?.transportGeneration != generation,
                  pendingAuthenticationGeneration != generation else {
                return .ignoredStale(generation: generation)
            }
            let operation = beginOperation()
            pendingAuthenticationGeneration = generation
            let replaced = current
            do {
                let connection = try await factory
                    .makeLocalXPCMenuLifecycleConnection(
                        generation: generationIDSource(generation)
                    )
                guard operationToken == operation,
                      pendingAuthenticationGeneration == generation else {
                    _ = await connection.invalidate()
                    return .ignoredStale(generation: generation)
                }
                pendingAuthenticationGeneration = nil
                current = Current(
                    transportGeneration: generation,
                    connection: connection,
                    readinessPublished: false
                )
                return .authenticatedWithoutReadiness(
                    generation: generation
                )
            } catch {
                guard operationToken == operation,
                      pendingAuthenticationGeneration == generation else {
                    return .ignoredStale(generation: generation)
                }
                pendingAuthenticationGeneration = nil
                current = nil
                _ = beginOperation()
                if let replaced {
                    _ = await replaced.connection.invalidate()
                }
                return .failedClosed(generation: generation)
            }

        case let .menuReady(generation):
            guard let active = current,
                  active.transportGeneration == generation,
                  !active.readinessPublished,
                  pendingAuthenticationGeneration == nil else {
                return .ignoredStale(generation: generation)
            }
            let operation = beginOperation()
            let receipt = await active.connection.publishReady()
            guard operationToken == operation,
                  current?.transportGeneration == generation else {
                _ = await active.connection.invalidate()
                return .ignoredStale(generation: generation)
            }
            guard receipt.disposition == .accepted else {
                current = nil
                _ = beginOperation()
                _ = await active.connection.invalidate()
                return .failedClosed(generation: generation)
            }
            current = Current(
                transportGeneration: generation,
                connection: active.connection,
                readinessPublished: true
            )
            return .readinessPublished(generation: generation)

        case let .invalidatedMenu(generation):
            if pendingAuthenticationGeneration == generation {
                pendingAuthenticationGeneration = nil
                let active = current
                current = nil
                _ = beginOperation()
                if let active {
                    _ = await active.connection.invalidate()
                }
                return .invalidated(generation: generation)
            }
            if let pendingAuthenticationGeneration,
               pendingAuthenticationGeneration != generation {
                guard let active = current,
                      active.transportGeneration == generation else {
                    return .ignoredStale(generation: generation)
                }
                current = nil
                _ = await active.connection.invalidate()
                return .invalidated(generation: generation)
            }
            guard let active = current,
                  active.transportGeneration == generation else {
                return .ignoredStale(generation: generation)
            }
            current = nil
            _ = beginOperation()
            _ = await active.connection.invalidate()
            return .invalidated(generation: generation)
        }
    }

    /// Fences every in-flight operation before retiring the current lifecycle
    /// authority. This is used by direct callers that can await full retirement.
    @discardableResult
    public func invalidateCurrent() async -> UInt64? {
        guard let retirement = fenceCurrent() else { return nil }
        _ = await retirement.connection.invalidate()
        return retirement.transportGeneration
    }

    /// Removes all binding authority without waiting behind an underlying
    /// lifecycle operation. Transport shutdown uses this phase before it awaits
    /// serialized lifecycle retirement.
    fileprivate func fenceCurrent() -> MacLocalXPCLifecycleRetirementV1? {
        _ = beginOperation()
        pendingAuthenticationGeneration = nil
        guard let active = current else { return nil }
        current = nil
        return MacLocalXPCLifecycleRetirementV1(
            transportGeneration: active.transportGeneration,
            connection: active.connection
        )
    }

    func isCurrent(generation: UInt64) -> Bool {
        current?.transportGeneration == generation
    }

    private func beginOperation() -> UUID {
        let token = UUID()
        operationToken = token
        return token
    }
}

private final class MacLocalXPCLifecyclePumpShutdownStateV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var acceptingEvents = true
    private var drainTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    func install(drainTask: Task<Void, Never>) {
        lock.lock()
        self.drainTask = drainTask
        lock.unlock()
    }

    func acceptsEvents() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return acceptingEvents
    }

    func beginShutdown(
        operation: @escaping @Sendable (
            Task<Void, Never>?
        ) async -> Void
    ) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let shutdownTask {
            return shutdownTask
        }
        acceptingEvents = false
        let drainTask = self.drainTask
        let task = Task {
            await operation(drainTask)
        }
        shutdownTask = task
        return task
    }
}

/// Preserves the serial order of callbacks emitted by the XPC listener queue
/// while allowing lifecycle authority calls to suspend without blocking XPC.
/// Its bounded queue fails the entire local transport closed on overflow.
@available(macOS 26.0, *)
public final class MacLocalXPCLifecycleEventPumpV1: @unchecked Sendable {
    public typealias FailureHandler = @Sendable (UInt64) async -> Void
    public typealias ShutdownHandler = @Sendable () async -> Void
    public typealias DispositionHandler = @Sendable (
        MacLocalXPCLifecycleBindingDispositionV1
    ) async -> Void

    private let binding: MacLocalXPCLifecycleBindingV1
    private let onShutdown: ShutdownHandler
    private let continuation:
        AsyncStream<MacLocalXPCServerEventV1>.Continuation
    private let shutdownState =
        MacLocalXPCLifecyclePumpShutdownStateV1()

    public init(
        binding: MacLocalXPCLifecycleBindingV1,
        bufferCapacity: Int = 32,
        onFailedClosed: @escaping FailureHandler,
        onDisposition: @escaping DispositionHandler = { _ in },
        onShutdown: @escaping ShutdownHandler
    ) {
        self.binding = binding
        self.onShutdown = onShutdown
        let pair = AsyncStream<MacLocalXPCServerEventV1>.makeStream(
            bufferingPolicy: .bufferingOldest(max(1, bufferCapacity))
        )
        continuation = pair.continuation
        let drainTask = Task {
            for await event in pair.stream {
                guard !Task.isCancelled else { break }
                let disposition = await binding.receive(event)
                guard !Task.isCancelled else { break }
                if case let .failedClosed(generation) = disposition {
                    await onFailedClosed(generation)
                }
                guard !Task.isCancelled else { break }
                await onDisposition(disposition)
            }
        }
        shutdownState.install(drainTask: drainTask)
    }

    public func consume(_ event: MacLocalXPCServerEventV1) {
        guard shutdownState.acceptsEvents() else { return }
        switch continuation.yield(event) {
        case .enqueued:
            break
        case .dropped, .terminated:
            _ = beginShutdown()
        @unknown default:
            _ = beginShutdown()
        }
    }

    public func finish() async {
        await beginShutdown().value
    }

    deinit {
        _ = beginShutdown()
    }

    private func beginShutdown() -> Task<Void, Never> {
        let continuation = self.continuation
        let binding = self.binding
        let onShutdown = self.onShutdown
        return shutdownState.beginShutdown { drainTask in
            continuation.finish()
            drainTask?.cancel()
            let retirement = await binding.fenceCurrent()
            await onShutdown()
            if let retirement {
                _ = await retirement.connection.invalidate()
            }
            if let drainTask {
                await drainTask.value
            }
        }
    }
}
#endif
