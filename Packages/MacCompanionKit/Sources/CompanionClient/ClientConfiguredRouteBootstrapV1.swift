import CompanionDiscovery
import CompanionWire
import Foundation

public enum ClientConfiguredRouteBootstrapErrorV1:
    Error, Equatable, Sendable
{
    case invalidChoices
    case invalidPhase
}

public enum ClientConfiguredRouteBootstrapPhaseV1:
    String, Equatable, Sendable
{
    case pending
    case publishing
    case published
    case cancelled
}

public struct ClientConfiguredRouteBootstrapEntryV1:
    Equatable, Sendable
{
    public let endpoint: EndpointCandidate
    /// Non-nil only when the pairing route itself supplies an unambiguous
    /// source: Bonjour, RFC1918 IPv4, or IPv6 ULA.
    public let automaticProvenance: ClientConfiguredRouteProvenanceV1?
}

/// First-pairing plan. DNS and public-address candidates remain unresolved and
/// cannot enter the catalog until a local surface supplies explicit provenance.
public struct ClientConfiguredRouteBootstrapPlanV1:
    Equatable, Sendable
{
    public typealias RouteID = @Sendable (
        EndpointCandidate
    ) throws -> WireBytes16

    public let hostID: UUID
    public let entries: [ClientConfiguredRouteBootstrapEntryV1]

    public init(pairedHost: ClientDurablePairedHostV0) {
        self.init(hostID: pairedHost.hostID, endpoints: pairedHost.endpoints)
    }

    package init(hostID: UUID, endpoints: [EndpointCandidate]) {
        self.hostID = hostID
        entries = endpoints.map { endpoint in
            let provenance: ClientConfiguredRouteProvenanceV1? =
                switch endpoint.kind {
                case .bonjour:
                    .localDiscovery
                case .ipv4, .ipv6:
                    ClientConfiguredRouteRecordV1
                        .isEligibleForDirectPrivateAddress(endpoint)
                        ? .directPrivateAddress
                        : nil
                case .dns:
                    nil
                }
            return ClientConfiguredRouteBootstrapEntryV1(
                endpoint: endpoint,
                automaticProvenance: provenance
            )
        }
    }

    public var endpointsRequiringExplicitChoice: [EndpointCandidate] {
        entries.compactMap {
            $0.automaticProvenance == nil ? $0.endpoint : nil
        }
    }

    public func complete(
        explicitChoices: [
            EndpointCandidate: ClientConfiguredRouteProvenanceV1
        ],
        routeID: RouteID
    ) throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        let required = Set(endpointsRequiringExplicitChoice)
        guard Set(explicitChoices.keys) == required else {
            throw ClientConfiguredRouteBootstrapErrorV1.invalidChoices
        }
        let records = try entries.map { entry in
            guard let provenance = entry.automaticProvenance
                    ?? explicitChoices[entry.endpoint] else {
                throw ClientConfiguredRouteBootstrapErrorV1.invalidChoices
            }
            return try ClientConfiguredRouteRecordV1(
                configuredRouteID: routeID(entry.endpoint),
                endpoint: entry.endpoint,
                provenance: provenance
            )
        }
        return try ClientConfiguredRouteCatalogSnapshotV1(
            hostID: hostID,
            revision: 1,
            catalog: ClientConfiguredRouteCatalogV1(records: records)
        )
    }
}

/// One-shot first-pairing publication authority. Its only effect is the
/// injected durable catalog commit; it has no reconnect or network authority.
/// Cancellation changes only local phase and cannot publish a catalog.
public actor ClientConfiguredRouteBootstrapAuthorityV1 {
    public typealias RouteID = ClientConfiguredRouteBootstrapPlanV1.RouteID
    public typealias Publish = @Sendable (
        ClientConfiguredRouteCatalogSnapshotV1
    ) async throws -> Void

    public private(set) var phase:
        ClientConfiguredRouteBootstrapPhaseV1 = .pending

    private let plan: ClientConfiguredRouteBootstrapPlanV1
    private let routeID: RouteID
    private let publish: Publish

    public init(
        plan: ClientConfiguredRouteBootstrapPlanV1,
        routeID: @escaping RouteID,
        publish: @escaping Publish
    ) {
        self.plan = plan
        self.routeID = routeID
        self.publish = publish
    }

    @discardableResult
    public func complete(
        explicitChoices: [
            EndpointCandidate: ClientConfiguredRouteProvenanceV1
        ]
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        guard phase == .pending else {
            throw ClientConfiguredRouteBootstrapErrorV1.invalidPhase
        }
        let snapshot = try plan.complete(
            explicitChoices: explicitChoices,
            routeID: routeID
        )
        phase = .publishing
        do {
            try await publish(snapshot)
            phase = .published
            return snapshot
        } catch {
            phase = .pending
            throw error
        }
    }

    public func cancel() throws {
        guard phase == .pending else {
            throw ClientConfiguredRouteBootstrapErrorV1.invalidPhase
        }
        phase = .cancelled
    }
}
