#if os(iOS)
import CompanionClient
import Foundation

public enum UIKitClientConfiguredRouteNetworkApplicationOwnerPhaseV1:
    String, Equatable, Sendable
{
    case idle
    case running
    case closed
}

public enum UIKitClientConfiguredRouteNetworkApplicationOwnerErrorV1:
    Error, Equatable, Sendable
{
    case invalidPhase
}

/// One application-global owner for coarse reachability and the configured
/// route UIKit lifecycle bridge. It always begins pessimistically unreachable;
/// only the Boolean source can later make the binding dial-eligible. The owner
/// has no endpoint, route catalog, interface, DNS, or provenance API.
@available(iOS 17.0, *)
@MainActor
public final class UIKitClientConfiguredRouteNetworkApplicationOwnerV1 {
    public typealias Failure =
        UIKitClientConfiguredRouteApplicationBridgeV1.Failure
    public typealias StateChanged =
        UIKitClientConfiguredRouteApplicationBridgeV1.StateChanged

    public private(set) var phase =
        UIKitClientConfiguredRouteNetworkApplicationOwnerPhaseV1.idle

    private let source: any ClientCoarseReachabilitySourceV1
    private let bridge: UIKitClientConfiguredRouteApplicationBridgeV1
    private let failure: Failure
    private let failureRelay: UIKitApplicationOwnerFailureRelayV1
    private var terminalFailure: (any Error)?

    public init(
        binding: ClientConfiguredRouteApplicationBindingV1,
        source: any ClientCoarseReachabilitySourceV1,
        failure: @escaping Failure,
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        let relay = UIKitApplicationOwnerFailureRelayV1()
        self.source = source
        self.failure = failure
        failureRelay = relay
        bridge = UIKitClientConfiguredRouteApplicationBridgeV1(
            binding: binding,
            reachabilityEvents: source.events,
            failure: { error in relay.emit(error) },
            stateChanged: stateChanged
        )
        relay.handler = { [weak self] error in
            self?.handleFailure(error)
        }
    }

    public convenience init(
        binding: ClientConfiguredRouteApplicationBindingV1,
        failure: @escaping Failure,
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.init(
            binding: binding,
            source: NetworkClientCoarseReachabilitySourceV1(),
            failure: failure,
            stateChanged: stateChanged
        )
    }

    public func start() async throws {
        guard phase == .idle else {
            throw UIKitClientConfiguredRouteNetworkApplicationOwnerErrorV1
                .invalidPhase
        }
        // Install the binding and its reachability-stream consumer before the
        // monitor can emit its one initial path snapshot. NWPathMonitor is
        // allowed to deliver that snapshot immediately from start(); starting
        // it first can leave the reconnect owner permanently pessimistic even
        // though the network is already satisfied.
        phase = .running
        await bridge.start(initialNetworkReachable: false)
        if let terminalFailure { throw terminalFailure }
        do {
            try source.start()
        } catch {
            handleFailure(error)
            await bridge.stop()
            throw error
        }
        if let terminalFailure { throw terminalFailure }
    }

    public func stop() async {
        guard phase != .closed else { return }
        source.stop()
        await bridge.stop()
        phase = .closed
        failureRelay.handler = nil
    }

    private func handleFailure(_ error: any Error) {
        guard terminalFailure == nil else { return }
        terminalFailure = error
        phase = .closed
        source.stop()
        failure(error)
    }
}

@available(iOS 17.0, *)
@MainActor
private final class UIKitApplicationOwnerFailureRelayV1 {
    var handler: (@MainActor (any Error) -> Void)?

    func emit(_ error: any Error) {
        handler?(error)
    }
}
#endif
