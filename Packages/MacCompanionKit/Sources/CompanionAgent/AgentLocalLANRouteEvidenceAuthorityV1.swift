import Foundation

public enum AgentLocalLANRouteEvidenceErrorV1:
    Error,
    Equatable,
    Sendable
{
    case generationExhausted
    case sourceStopped
    case staleAdvertisementGeneration
    case staleListenerGeneration
}

public struct AgentLocalLANRouteEvidenceSnapshotV1: Equatable, Sendable {
    public let listenerReady: Bool
    public let advertisementReady: Bool
    public let lanPublished: Bool
    public let listenerGeneration: UInt64
    public let advertisementGeneration: UInt64
    public let stopped: Bool
}

/// The only production facet that may publish the local `lan` route kind.
/// `lan` means this exact listener is ready and its product-owned Bonjour
/// advertisement is ready. It is never inferred from path, interface, DNS,
/// address, process, or installed-application facts.
public actor AgentLocalLANRouteEvidenceAuthorityV1 {
    private let routes: AgentLocalRouteMonitorAuthorityV1
    private let monotonicNowMilliseconds: @Sendable () -> Int64
    private var listenerReady = false
    private var advertisementReady = false
    private var lanPublished = false
    private var listenerGeneration: UInt64 = 0
    private var advertisementGeneration: UInt64 = 0
    private var transitionRevision: UInt64 = 0
    private var stopped = false

    package init(
        routes: AgentLocalRouteMonitorAuthorityV1,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.routes = routes
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    package func publishListenerReadiness(
        ready: Bool,
        generation: UInt64
    ) async throws {
        guard !stopped else {
            throw AgentLocalLANRouteEvidenceErrorV1.sourceStopped
        }
        guard generation > listenerGeneration else {
            throw AgentLocalLANRouteEvidenceErrorV1
                .staleListenerGeneration
        }
        let previousReady = listenerReady
        let previousGeneration = listenerGeneration
        let revision = try beginTransition()
        listenerReady = ready
        listenerGeneration = generation
        do {
            try await publishCurrentReadiness()
        } catch {
            if transitionRevision == revision {
                listenerReady = previousReady
                listenerGeneration = previousGeneration
            }
            throw error
        }
    }

    package func publishAdvertisementReadiness(
        ready: Bool,
        generation: UInt64
    ) async throws {
        guard !stopped else {
            throw AgentLocalLANRouteEvidenceErrorV1.sourceStopped
        }
        guard generation > advertisementGeneration else {
            throw AgentLocalLANRouteEvidenceErrorV1
                .staleAdvertisementGeneration
        }
        let previousReady = advertisementReady
        let previousGeneration = advertisementGeneration
        let revision = try beginTransition()
        advertisementReady = ready
        advertisementGeneration = generation
        do {
            try await publishCurrentReadiness()
        } catch {
            if transitionRevision == revision {
                advertisementReady = previousReady
                advertisementGeneration = previousGeneration
            }
            throw error
        }
    }

    package func stop(
        observedAtMonotonicMilliseconds: Int64
    ) async throws {
        guard !stopped else { return }
        _ = try beginTransition()
        stopped = true
        listenerReady = false
        advertisementReady = false
        lanPublished = false
        _ = try await routes.stop(
            observedAtMonotonicMilliseconds:
                observedAtMonotonicMilliseconds
        )
    }

    public func snapshot() -> AgentLocalLANRouteEvidenceSnapshotV1 {
        AgentLocalLANRouteEvidenceSnapshotV1(
            listenerReady: listenerReady,
            advertisementReady: advertisementReady,
            lanPublished: lanPublished,
            listenerGeneration: listenerGeneration,
            advertisementGeneration: advertisementGeneration,
            stopped: stopped
        )
    }

    private func beginTransition() throws -> UInt64 {
        guard transitionRevision < UInt64.max else {
            throw AgentLocalLANRouteEvidenceErrorV1.generationExhausted
        }
        transitionRevision += 1
        return transitionRevision
    }

    private func publishCurrentReadiness() async throws {
        let shouldPublish = listenerReady && advertisementReady
        _ = try await routes.publishLANAvailability(
            available: shouldPublish,
            observedAtMonotonicMilliseconds:
                monotonicNowMilliseconds()
        )
        lanPublished = shouldPublish
    }
}
