import CompanionDiscovery
import CompanionTransport
import Foundation

public enum ClientConfiguredReconnectErrorV1:
    Error, Equatable, Sendable
{
    case identityMismatch
    case staleRevision
    case invalidController
    case transitionInProgress
    case closed
}

/// One immutable reconnect input assembled from the durable paired identity
/// and exactly one configured-route catalog revision. Candidate ordering and
/// route provenance therefore cannot come from different reads.
public struct ClientReconnectConfigurationV1: Equatable, Sendable {
    public let pairedHost: ClientDurablePairedHostV0
    public let routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1

    public init(
        pairedHost: ClientDurablePairedHostV0,
        routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1
    ) throws {
        guard pairedHost.hostID == routeSnapshot.hostID else {
            throw ClientConfiguredReconnectErrorV1.identityMismatch
        }
        self.pairedHost = pairedHost
        self.routeSnapshot = routeSnapshot
    }

    public var hostID: UUID { pairedHost.hostID }
    public var revision: UInt64 { routeSnapshot.revision }
    public var candidates: [EndpointCandidate] {
        routeSnapshot.catalog.records.map(\.endpoint)
    }
    public var catalog: ClientConfiguredRouteCatalogV1 {
        routeSnapshot.catalog
    }

    public func makeReconnectState(
        foreground: Bool,
        networkReachable: Bool
    ) throws -> ReconnectStateMachine {
        try ReconnectStateMachine(
            candidates: candidates,
            requiredHostFingerprint: pairedHost.hostFingerprint,
            foreground: foreground,
            networkReachable: networkReachable
        )
    }

    fileprivate func hasSameIdentity(
        as other: ClientReconnectConfigurationV1
    ) -> Bool {
        pairedHost == other.pairedHost
    }
}

public struct ClientConfiguredReconnectSnapshotV1: Equatable, Sendable {
    public let hostID: UUID
    public let configurationRevision: UInt64
    public let foreground: Bool
    public let networkReachable: Bool
    public let isTransitioning: Bool
    public let isClosed: Bool
    public let reconnect: ReconnectControllerSnapshotV0
}

/// App-facing owner that replaces the complete reconnect controller whenever
/// configured-route revision changes. The factory must close over an attempter
/// built from `configuration.catalog`; validation proves its controller uses
/// the same ordered candidates and immutable host pin.
public actor ClientConfiguredReconnectOwnerV1 {
    public typealias ControllerFactory = @Sendable (
        _ configuration: ClientReconnectConfigurationV1,
        _ foreground: Bool,
        _ networkReachable: Bool
    ) throws -> ReconnectControllerV0

    /// Content-free wakeups from controller-internal transitions. Consumers
    /// re-read the complete owner/lifecycle snapshot before presentation.
    public nonisolated let stateChanges: AsyncStream<Void>

    private var configuration: ClientReconnectConfigurationV1
    private var controller: ReconnectControllerV0
    private let makeController: ControllerFactory
    private var foreground: Bool
    private var networkReachable: Bool
    private var transitionInProgress = false
    private var closed = false
    private let stateChangesContinuation: AsyncStream<Void>.Continuation

    public init(
        configuration: ClientReconnectConfigurationV1,
        foreground: Bool,
        networkReachable: Bool,
        makeController: @escaping ControllerFactory
    ) async throws {
        var capturedContinuation: AsyncStream<Void>.Continuation?
        let stateChanges = AsyncStream<Void>(
            bufferingPolicy: .bufferingNewest(1)
        ) { capturedContinuation = $0 }
        guard let stateChangesContinuation = capturedContinuation else {
            throw ClientConfiguredReconnectErrorV1.invalidController
        }
        let controller = try makeController(
            configuration,
            foreground,
            networkReachable
        )
        self.configuration = configuration
        self.controller = controller
        self.makeController = makeController
        self.foreground = foreground
        self.networkReachable = networkReachable
        self.stateChanges = stateChanges
        self.stateChangesContinuation = stateChangesContinuation
        guard Self.controllerSnapshot(
            await controller.snapshot(),
            matches: configuration
        ) else {
            await controller.shutdown()
            throw ClientConfiguredReconnectErrorV1.invalidController
        }
        await controller.setStateChanged {
            stateChangesContinuation.yield()
        }
    }

    public func snapshot() async -> ClientConfiguredReconnectSnapshotV1 {
        ClientConfiguredReconnectSnapshotV1(
            hostID: configuration.hostID,
            configurationRevision: configuration.revision,
            foreground: foreground,
            networkReachable: networkReachable,
            isTransitioning: transitionInProgress,
            isClosed: closed,
            reconnect: await controller.snapshot()
        )
    }

    public func replaceConfiguration(
        _ replacement: ClientReconnectConfigurationV1
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        guard replacement.hasSameIdentity(as: configuration) else {
            throw ClientConfiguredReconnectErrorV1.identityMismatch
        }
        guard replacement.revision > configuration.revision else {
            throw ClientConfiguredReconnectErrorV1.staleRevision
        }

        let candidate = try makeController(
            replacement,
            foreground,
            networkReachable
        )
        guard Self.controllerSnapshot(
            await candidate.snapshot(),
            matches: replacement
        ) else {
            await candidate.shutdown()
            throw ClientConfiguredReconnectErrorV1.invalidController
        }
        await candidate.setStateChanged { [stateChangesContinuation] in
            stateChangesContinuation.yield()
        }

        let retired = controller
        await retired.shutdown()
        configuration = replacement
        controller = candidate
    }

    public func setForeground(
        _ value: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        try await controller.setForeground(
            value,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        foreground = value
    }

    public func setNetworkReachable(
        _ value: Bool,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        try await controller.setNetworkReachable(
            value,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        networkReachable = value
    }

    public func startRound(
        roundID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try beginTransition()
        defer { transitionInProgress = false }
        try await controller.startRound(
            roundID: roundID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func close() async throws {
        if closed { return }
        try beginTransition()
        defer { transitionInProgress = false }
        await controller.shutdown()
        closed = true
        stateChangesContinuation.finish()
    }

    private func beginTransition() throws {
        guard !closed else {
            throw ClientConfiguredReconnectErrorV1.closed
        }
        guard !transitionInProgress else {
            throw ClientConfiguredReconnectErrorV1.transitionInProgress
        }
        transitionInProgress = true
    }

    private static func controllerSnapshot(
        _ snapshot: ReconnectControllerSnapshotV0,
        matches configuration: ClientReconnectConfigurationV1
    ) -> Bool {
        !snapshot.isShutdown
            && snapshot.candidates == configuration.candidates
            && snapshot.requiredHostFingerprint
                == configuration.pairedHost.hostFingerprint
    }
}
