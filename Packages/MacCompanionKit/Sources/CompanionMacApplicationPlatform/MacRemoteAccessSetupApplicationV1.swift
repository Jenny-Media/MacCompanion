#if os(macOS)
import CompanionAgent
import CompanionLocalXPCPlatform
import Foundation
import Observation

@available(macOS 26.0, *)
private final class MacRemoteAccessSetupEventRelayV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let continuation:
        AsyncStream<MacLocalXPCRemoteAccessBootstrapClientEventV1>
            .Continuation
    private let stream:
        AsyncStream<MacLocalXPCRemoteAccessBootstrapClientEventV1>
    private var coordinator: MacRemoteAccessSetupCoordinatorV1?
    private var drainTask: Task<Void, Never>?
    private var finished = false

    init(bufferCapacity: Int) {
        let pair = AsyncStream<
            MacLocalXPCRemoteAccessBootstrapClientEventV1
        >.makeStream(
            bufferingPolicy: .bufferingOldest(max(1, bufferCapacity))
        )
        continuation = pair.continuation
        stream = pair.stream
    }

    func bind(_ coordinator: MacRemoteAccessSetupCoordinatorV1) {
        let task = lock.withLock { () -> Task<Void, Never> in
            precondition(self.coordinator == nil && drainTask == nil)
            self.coordinator = coordinator
            let stream = self.stream
            return Task { [weak self, weak coordinator] in
                for await event in stream {
                    guard !Task.isCancelled, let coordinator else { break }
                    await coordinator.receive(event)
                }
                self?.lock.withLock { self?.finished = true }
            }
        }
        lock.withLock { drainTask = task }
    }

    func receive(
        _ event: MacLocalXPCRemoteAccessBootstrapClientEventV1
    ) {
        let result = lock.withLock {
            finished ? nil : continuation.yield(event)
        }
        guard let result else { return }
        switch result {
        case .enqueued:
            return
        case .dropped, .terminated:
            beginBestEffortFailure()
        @unknown default:
            beginBestEffortFailure()
        }
    }

    func finish() async {
        let values = lock.withLock { () -> (
            MacRemoteAccessSetupCoordinatorV1?, Task<Void, Never>?
        ) in
            guard !finished else { return (coordinator, drainTask) }
            finished = true
            continuation.finish()
            return (coordinator, drainTask)
        }
        await values.0?.finish()
        values.1?.cancel()
        if let task = values.1 { await task.value }
    }

    private func beginBestEffortFailure() {
        let coordinator = lock.withLock { () ->
            MacRemoteAccessSetupCoordinatorV1? in
            guard !finished else { return nil }
            finished = true
            continuation.finish()
            return self.coordinator
        }
        guard let coordinator else { return }
        Task { await coordinator.finish() }
    }

    deinit {
        continuation.finish()
        drainTask?.cancel()
        guard let coordinator else { return }
        Task { await coordinator.finish() }
    }
}

@available(macOS 26.0, *)
private final class MacRemoteAccessSetupStateRelayV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var pending: [MacRemoteAccessSetupStateV1] = []
    private var drainScheduled = false
    weak var application: MacRemoteAccessSetupApplicationV1?

    nonisolated func receive(_ state: MacRemoteAccessSetupStateV1) {
        let shouldSchedule = lock.withLock {
            pending.append(state)
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in self?.drain() }
    }

    @MainActor
    private func drain() {
        while true {
            let value = lock.withLock { () ->
                MacRemoteAccessSetupStateV1? in
                guard !pending.isEmpty else {
                    drainScheduled = false
                    return nil
                }
                return pending.removeFirst()
            }
            guard let value else { return }
            application?.receive(value)
        }
    }
}

/// Main-actor application facade for the explicit first-enable transaction.
/// It owns the concrete callback relay and publishes only the coordinator's
/// ordered typed state. Construction registers no login role and starts no
/// XPC session.
@available(macOS 26.0, *)
@MainActor
@Observable
public final class MacRemoteAccessSetupApplicationV1 {
    package typealias ClientFactory = @Sendable (
        @escaping MacLocalXPCRemoteAccessBootstrapClientV1.EventHandler
    ) -> any MacRemoteAccessBootstrapClientV1

    public private(set) var state: MacRemoteAccessSetupStateV1 = .idle

    @ObservationIgnored
    private let coordinator: MacRemoteAccessSetupCoordinatorV1
    @ObservationIgnored
    private let eventRelay: MacRemoteAccessSetupEventRelayV1
    @ObservationIgnored
    private let stateRelay: MacRemoteAccessSetupStateRelayV1
    @ObservationIgnored
    private var finishTask: Task<Void, Never>?
    @ObservationIgnored
    private var stateObserver:
        (@MainActor @Sendable (MacRemoteAccessSetupStateV1) -> Void)?

    public convenience init(
        agent: any AgentBootstrapLoginRoleServiceV1,
        menuApp: any AgentLoginRoleServiceV1
    ) {
        self.init(
            agent: agent,
            menuApp: menuApp,
            clientFactory: {
                MacLocalXPCRemoteAccessBootstrapClientV1(onEvent: $0)
            }
        )
    }

    package init(
        agent: any AgentBootstrapLoginRoleServiceV1,
        menuApp: any AgentLoginRoleServiceV1,
        bufferCapacity: Int = 8,
        milliseconds: @escaping MacRemoteAccessSetupCoordinatorV1
            .Milliseconds = {
                let value = Date().timeIntervalSince1970 * 1_000
                guard value.isFinite,
                      value >= 0,
                      value <= Double(9_007_199_254_740_991) else {
                    return nil
                }
                return Int64(value.rounded(.down))
            },
        commandID: @escaping MacRemoteAccessSetupCoordinatorV1.CommandID =
            UUID.init,
        clientFactory: @escaping ClientFactory
    ) {
        let eventRelay = MacRemoteAccessSetupEventRelayV1(
            bufferCapacity: bufferCapacity
        )
        let stateRelay = MacRemoteAccessSetupStateRelayV1()
        let client = clientFactory { [weak eventRelay] event in
            eventRelay?.receive(event)
        }
        let coordinator = MacRemoteAccessSetupCoordinatorV1(
            agent: agent,
            menuApp: menuApp,
            client: client,
            milliseconds: milliseconds,
            commandID: commandID,
            stateChanged: { [weak stateRelay] state in
                stateRelay?.receive(state)
            }
        )
        self.eventRelay = eventRelay
        self.stateRelay = stateRelay
        self.coordinator = coordinator
        stateRelay.application = self
        eventRelay.bind(coordinator)
    }

    public func begin() async throws { try await coordinator.begin() }
    public func confirm() async throws { try await coordinator.confirm() }
    public func decline() async throws { try await coordinator.decline() }

    public func retryMenuConvergence() async throws {
        try await coordinator.retryMenuConvergence()
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let relay = eventRelay
        let task = Task { await relay.finish() }
        finishTask = task
        await task.value
    }

    package func installStateObserver(
        _ observer: @escaping @MainActor @Sendable (
            MacRemoteAccessSetupStateV1
        ) -> Void
    ) {
        precondition(stateObserver == nil)
        stateObserver = observer
        observer(state)
    }

    fileprivate func receive(_ value: MacRemoteAccessSetupStateV1) {
        state = value
        stateObserver?(value)
    }

    deinit {
        guard finishTask == nil else { return }
        let relay = eventRelay
        Task { await relay.finish() }
    }
}
#endif
