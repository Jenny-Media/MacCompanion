import CompanionClient
import CompanionDiscovery
import CompanionInteractiveClient
import CompanionWire
import Foundation

public struct NetworkClientObservePublicationV0: Sendable {
    public let hostID: UUID
    public let connectionID: Data
    public let event: ClientObserveChannelEventV0
}

public struct NetworkClientActPublicationV0: Sendable {
    public let hostID: UUID
    public let connectionID: Data
    public let event: ClientActChannelEventV1
}

public struct NetworkClientControlPublicationV0: Sendable {
    public let hostID: UUID
    public let connectionID: Data
    public let event: ClientInteractivePrimarySessionEventV0
}

public struct NetworkClientPrimaryProductSelectionV0: Sendable {
    package let endpoint: EndpointCandidate
    public let authenticatedSession: ClientAuthenticatedSessionV0
    public let observeChannel: ClientObserveChannelV0
    public let actChannel: ClientActChannelV1
    public let controlChannel: ClientInteractivePrimaryChannelV0
}

public struct NetworkClientPrimaryProductEventsV0: Sendable {
    public let publishObserve: @Sendable (
        NetworkClientObservePublicationV0
    ) -> Void
    public let publishAct: @Sendable (
        NetworkClientActPublicationV0
    ) -> Void
    public let publishControl: @Sendable (
        NetworkClientControlPublicationV0
    ) -> Void
    public let primarySelected: @Sendable (
        NetworkClientPrimaryProductSelectionV0
    ) -> Void
    public let primaryTerminated: @Sendable (
        UUID,
        Data
    ) -> Void

    public init(
        publishObserve: @escaping @Sendable (
            NetworkClientObservePublicationV0
        ) -> Void = { _ in },
        publishAct: @escaping @Sendable (
            NetworkClientActPublicationV0
        ) -> Void = { _ in },
        publishControl: @escaping @Sendable (
            NetworkClientControlPublicationV0
        ) -> Void = { _ in },
        primarySelected: @escaping @Sendable (
            NetworkClientPrimaryProductSelectionV0
        ) -> Void = { _ in },
        primaryTerminated: @escaping @Sendable (
            UUID,
            Data
        ) -> Void = { _, _ in }
    ) {
        self.publishObserve = publishObserve
        self.publishAct = publishAct
        self.publishControl = publishControl
        self.primarySelected = primarySelected
        self.primaryTerminated = primaryTerminated
    }

    public static let discarding = Self()

    /// Fan-out for two bounded synchronous product consumers. Call order is
    /// deterministic so each consumer may apply its own revision fence.
    public func combined(
        with other: NetworkClientPrimaryProductEventsV0
    ) -> NetworkClientPrimaryProductEventsV0 {
        NetworkClientPrimaryProductEventsV0(
            publishObserve: { value in
                publishObserve(value)
                other.publishObserve(value)
            },
            publishAct: { value in
                publishAct(value)
                other.publishAct(value)
            },
            publishControl: { value in
                publishControl(value)
                other.publishControl(value)
            },
            primarySelected: { value in
                primarySelected(value)
                other.primarySelected(value)
            },
            primaryTerminated: { hostID, connectionID in
                primaryTerminated(hostID, connectionID)
                other.primaryTerminated(hostID, connectionID)
            }
        )
    }
}

package struct NetworkClientPrimaryProductConfigurationV0: Sendable {
    let pairedHost: ClientDurablePairedHostV0
    let approvalSigner: any ClientOperationApprovalSigningV1
    let interactiveApprovalSigner: any ClientInteractiveApprovalSigningV0
    let clock: @Sendable () -> NetworkClientClockSnapshotV0
    let messageID: @Sendable () -> WireUUID
    let events: NetworkClientPrimaryProductEventsV0
}

private final class NetworkClientPrimaryPublicationRelayV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let events: NetworkClientPrimaryProductEventsV0
    private var session: ClientAuthenticatedSessionV0?
    private var selected = false

    init(events: NetworkClientPrimaryProductEventsV0) {
        self.events = events
    }

    func bind(_ session: ClientAuthenticatedSessionV0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.session == nil else { return false }
        self.session = session
        return true
    }

    func select() {
        lock.lock()
        selected = session != nil
        lock.unlock()
    }

    func publishObserve(_ event: ClientObserveChannelEventV0) {
        let session = selectedSession()
        guard let session else { return }
        events.publishObserve(NetworkClientObservePublicationV0(
            hostID: session.hostID,
            connectionID: session.connectionID,
            event: event
        ))
    }

    func publishAct(_ event: ClientActChannelEventV1) {
        let session = selectedSession()
        guard let session else { return }
        events.publishAct(NetworkClientActPublicationV0(
            hostID: session.hostID,
            connectionID: session.connectionID,
            event: event
        ))
    }

    func publishControl(_ event: ClientInteractivePrimarySessionEventV0) {
        let session = selectedSession()
        guard let session else { return }
        events.publishControl(NetworkClientControlPublicationV0(
            hostID: session.hostID,
            connectionID: session.connectionID,
            event: event
        ))
    }

    func terminate() -> ClientAuthenticatedSessionV0? {
        lock.lock()
        defer { lock.unlock() }
        let result = selected ? session : nil
        selected = false
        session = nil
        return result
    }

    private func selectedSession() -> ClientAuthenticatedSessionV0? {
        lock.lock()
        defer { lock.unlock() }
        return selected ? session : nil
    }
}

/// One authenticated dial candidate. It constructs the real product bridge
/// before authentication can become ready, but withholds every outward product
/// publication until the reconnect owner selects this exact route as primary.
package actor NetworkClientPrimaryProductCandidateV0 {
    private let endpoint: EndpointCandidate
    private let configuration: NetworkClientPrimaryProductConfigurationV0
    private let relay: NetworkClientPrimaryPublicationRelayV0
    private let bridge: NetworkClientPrimaryRouterBridgeV0
    private var session: ClientAuthenticatedSessionV0?
    private var selected = false
    private var terminated = false

    init(
        endpoint: EndpointCandidate,
        configuration: NetworkClientPrimaryProductConfigurationV0
    ) {
        self.endpoint = endpoint
        self.configuration = configuration
        let relay = NetworkClientPrimaryPublicationRelayV0(
            events: configuration.events
        )
        self.relay = relay
        bridge = NetworkClientPrimaryRouterBridgeV0(
            pairedHost: configuration.pairedHost,
            approvalSigner: configuration.approvalSigner,
            interactiveApprovalSigner:
                configuration.interactiveApprovalSigner,
            interactiveEnvironment: ClientInteractivePrimaryEnvironmentV0(
                makeMessageID: configuration.messageID,
                wallNowUnixMilliseconds: {
                    configuration.clock().wallNowUnixMilliseconds
                },
                monotonicNowMilliseconds: {
                    configuration.clock().monotonicNowMilliseconds
                }
            ),
            monotonicNowNanoseconds: {
                let milliseconds = configuration.clock()
                    .monotonicNowMilliseconds
                let (value, overflow) = milliseconds
                    .multipliedReportingOverflow(by: 1_000_000)
                return overflow ? UInt64.max : value
            },
            observeEnvironment: ClientObserveChannelEnvironmentV0(
                makeMessageID: configuration.messageID,
                wallNowUnixMilliseconds: {
                    configuration.clock().wallNowUnixMilliseconds
                },
                monotonicNowMilliseconds: {
                    let value = configuration.clock()
                        .monotonicNowMilliseconds
                    return value <= UInt64(Int64.max)
                        ? Int64(value) : -1
                }
            ),
            actEnvironment: ClientActChannelEnvironmentV1(
                makeMessageID: configuration.messageID,
                wallNowUnixMilliseconds: {
                    configuration.clock().wallNowUnixMilliseconds
                }
            ),
            publishObserve: { relay.publishObserve($0) },
            publishAct: { relay.publishAct($0) },
            publishControl: { relay.publishControl($0) }
        )
    }

    func bind(_ pump: NetworkClientPrimaryFramePumpV0) async throws {
        try await bridge.bind(pump: pump)
    }

    func authenticated(_ session: ClientAuthenticatedSessionV0) async throws {
        guard !terminated, self.session == nil else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
        }
        guard relay.bind(session) else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
        }
        self.session = session
        try await bridge.authenticated(session)
    }

    func receive(_ frame: Data) async throws {
        try await bridge.receive(frame)
    }

    func selectedAsPrimary() async {
        guard !selected, !terminated, let session,
              let observe = await bridge.currentObserveChannel(),
              let act = await bridge.currentActChannel(),
              let control = await bridge.currentControlChannel() else { return }
        selected = true
        relay.select()
        configuration.events.primarySelected(
            NetworkClientPrimaryProductSelectionV0(
                endpoint: endpoint,
                authenticatedSession: session,
                observeChannel: observe,
                actChannel: act,
                controlChannel: control
            )
        )
    }

    func primaryTerminated() async {
        guard !terminated else { return }
        terminated = true
        await bridge.primaryTerminated()
        if let session = relay.terminate() {
            configuration.events.primaryTerminated(
                session.hostID,
                session.connectionID
            )
        }
        self.session = nil
    }
}
