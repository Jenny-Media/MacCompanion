#if canImport(Network)
import Dispatch
import Foundation
@preconcurrency import Network

public enum NetworkClientCoarseReachabilityPhaseV1:
    String, Equatable, Sendable
{
    case idle
    case running
    case stopped
}

public enum NetworkClientCoarseReachabilityErrorV1:
    Error, Equatable, Sendable
{
    case invalidPhase
}

package enum NetworkClientPathStatusV1: Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

/// Main-actor source contract consumed by the application-global UIKit owner.
/// The deliberately Boolean-only surface prevents composition code from
/// acquiring route-classification authority.
@MainActor
public protocol ClientCoarseReachabilitySourceV1: AnyObject {
    var events: AsyncStream<Bool> { get }
    func start() throws
    func stop()
}

/// Application-global scheduling input backed by `NWPathMonitor`. This source
/// intentionally emits only a Boolean. It accepts no endpoint and exposes no
/// interface, DNS, VPN, installed-app, or route-provenance information.
/// Consumers must begin pessimistically unreachable and wait for the first
/// event before allowing a dial.
@MainActor
public final class NetworkClientCoarseReachabilitySourceV1:
    ClientCoarseReachabilitySourceV1
{
    package typealias StartMonitor = @Sendable (
        @escaping @Sendable (NetworkClientPathStatusV1) -> Void
    ) -> Void
    package typealias CancelMonitor = @Sendable () -> Void

    public let events: AsyncStream<Bool>
    public private(set) var phase =
        NetworkClientCoarseReachabilityPhaseV1.idle

    private let continuation: AsyncStream<Bool>.Continuation
    private let startMonitor: StartMonitor
    private let cancelMonitor: CancelMonitor

    public convenience init(
        queue: DispatchQueue = DispatchQueue(
            label: "dev.maccompanion.client.reachability"
        )
    ) {
        let owner = NetworkClientPathMonitorOwnerV1(
            monitor: NWPathMonitor(),
            queue: queue
        )
        self.init(
            startMonitor: { handler in owner.start(handler: handler) },
            cancelMonitor: { owner.cancel() }
        )
    }

    package init(
        startMonitor: @escaping StartMonitor,
        cancelMonitor: @escaping CancelMonitor
    ) {
        var captured: AsyncStream<Bool>.Continuation?
        events = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            captured = $0
        }
        continuation = captured!
        self.startMonitor = startMonitor
        self.cancelMonitor = cancelMonitor
    }

    public func start() throws {
        guard phase == .idle else {
            throw NetworkClientCoarseReachabilityErrorV1.invalidPhase
        }
        phase = .running
        startMonitor { [weak self] status in
            Task { @MainActor [weak self] in
                self?.publish(status)
            }
        }
    }

    public func stop() {
        guard phase != .stopped else { return }
        phase = .stopped
        cancelMonitor()
        continuation.finish()
    }

    private func publish(_ status: NetworkClientPathStatusV1) {
        guard phase == .running else { return }
        continuation.yield(status == .satisfied)
    }

    deinit {
        if phase != .stopped { cancelMonitor() }
        continuation.finish()
    }
}

private final class NetworkClientPathMonitorOwnerV1: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init(monitor: NWPathMonitor, queue: DispatchQueue) {
        self.monitor = monitor
        self.queue = queue
    }

    func start(
        handler: @escaping @Sendable (NetworkClientPathStatusV1) -> Void
    ) {
        monitor.pathUpdateHandler = { path in
            switch path.status {
            case .satisfied:
                handler(.satisfied)
            case .unsatisfied:
                handler(.unsatisfied)
            case .requiresConnection:
                handler(.requiresConnection)
            @unknown default:
                handler(.unsatisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
#endif
