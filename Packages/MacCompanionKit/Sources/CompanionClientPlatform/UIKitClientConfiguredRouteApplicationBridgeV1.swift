#if os(iOS)
import CompanionClient
import Foundation
import UIKit

/// UIKit boundary for the configured-route application binding. True
/// foreground/background transitions are scheduling facts; temporary
/// `inactive` states caused by LocalAuthentication, Control Center, or other
/// system UI do not tear down an authenticated route. Reachability is an
/// injected Boolean stream so this type has no DNS, interface, route, VPN, or
/// installed-app classification authority.
@available(iOS 17.0, *)
@MainActor
public final class UIKitClientConfiguredRouteApplicationBridgeV1: NSObject {
    public typealias Failure = @MainActor (any Error) -> Void
    public typealias StateChanged = @MainActor (
        ClientConfiguredRouteApplicationBindingSnapshotV1
    ) -> Void

    private let binding: ClientConfiguredRouteApplicationBindingV1
    private let reachabilityEvents: AsyncStream<Bool>
    private let failure: Failure
    private let stateChanged: StateChanged
    private var eventTail: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?
    private var reconnectStateTask: Task<Void, Never>?
    private var started = false

    public init(
        binding: ClientConfiguredRouteApplicationBindingV1,
        reachabilityEvents: AsyncStream<Bool>,
        failure: @escaping Failure,
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.binding = binding
        self.reachabilityEvents = reachabilityEvents
        self.failure = failure
        self.stateChanged = stateChanged
        super.init()
    }

    public func start(initialNetworkReachable: Bool) async {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        let foreground = UIApplication.shared.applicationState != .background
        enqueue { binding in
            try await binding.setForeground(foreground)
        }
        enqueue { binding in
            try await binding.setNetworkReachable(
                initialNetworkReachable
            )
        }
        enqueue { binding in try await binding.start() }
        await eventTail?.value
        guard started else { return }

        reconnectStateTask = Task {
            [weak self, reconnectStateChanges = binding.reconnectStateChanges]
            in
            for await _ in reconnectStateChanges {
                guard !Task.isCancelled else { return }
                self?.enqueueReconnectStateRefresh()
            }
        }
        reachabilityTask = Task { [weak self, reachabilityEvents] in
            for await value in reachabilityEvents {
                guard !Task.isCancelled else { return }
                self?.enqueueReachability(value)
            }
        }
    }

    public func stop() async {
        guard started else { return }
        NotificationCenter.default.removeObserver(self)
        reachabilityTask?.cancel()
        reachabilityTask = nil
        reconnectStateTask?.cancel()
        reconnectStateTask = nil
        enqueue { binding in await binding.close() }
        await eventTail?.value
        started = false
        eventTail = nil
    }

    @objc private func willEnterForeground() {
        enqueue { binding in try await binding.setForeground(true) }
    }

    /// SwiftUI can construct and start the release application after
    /// `willEnterForeground` has already fired. Reconcile again at the later
    /// active notification so a launch-time lifecycle race cannot leave an
    /// onscreen workspace permanently classified as background. Temporary
    /// inactive states still do not publish a false transition.
    @objc private func didBecomeActive() {
        enqueue { binding in try await binding.setForeground(true) }
    }

    @objc private func didEnterBackground() {
        enqueue { binding in try await binding.setForeground(false) }
    }

    private func enqueueReachability(_ value: Bool) {
        guard started else { return }
        enqueue { binding in
            try await binding.setNetworkReachable(value)
        }
    }

    private func enqueueReconnectStateRefresh() {
        guard started else { return }
        enqueue { binding in
            await binding.reconnectStateDidChange()
        }
    }

    private func enqueue(
        _ operation: @escaping @Sendable (
            ClientConfiguredRouteApplicationBindingV1
        ) async throws -> Void
    ) {
        let previous = eventTail
        eventTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled,
                  let self,
                  self.started else { return }
            do {
                try await operation(self.binding)
                let snapshot = await self.binding.snapshot()
#if DEBUG
                print(
                    "[Mac Companion reconnect] binding phase=\(snapshot.phase.rawValue) foreground=\(snapshot.foreground) reachable=\(snapshot.networkReachable) roundStarted=\(snapshot.hasStartedEligibleRound) reconnect=\(String(describing: snapshot.lifecycle.reconnect.reconnect.phase))"
                )
#endif
                self.stateChanged(snapshot)
            } catch {
                self.fail(error)
            }
        }
    }

    private func fail(_ error: any Error) {
        guard started else { return }
#if DEBUG
        print(
            "[Mac Companion reconnect] bridge failed: \(String(describing: error))"
        )
#endif
        started = false
        NotificationCenter.default.removeObserver(self)
        reachabilityTask?.cancel()
        reachabilityTask = nil
        reconnectStateTask?.cancel()
        reconnectStateTask = nil
        failure(error)
    }

    deinit {
        reachabilityTask?.cancel()
        reconnectStateTask?.cancel()
        eventTail?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
