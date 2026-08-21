import CompanionDiscovery
import CompanionDomain
import CompanionWire
import Foundation

public enum ClientConfiguredRouteEditErrorV1:
    Error, Equatable, Sendable
{
    case routeNotFound
    case noChange
    case revisionExhausted
}

/// Closed local intent. Every add or replacement carries an explicit
/// provenance selected by the local configuration surface; the editor has no
/// DNS, interface, process, installed-app, or resolved-address inference API.
public enum ClientConfiguredRouteEditIntentV1: Equatable, Sendable {
    case add(
        endpoint: EndpointCandidate,
        provenance: ClientConfiguredRouteProvenanceV1
    )
    case replace(
        configuredRouteID: WireBytes16,
        endpoint: EndpointCandidate,
        provenance: ClientConfiguredRouteProvenanceV1
    )
    case remove(configuredRouteID: WireBytes16)
}

public enum ClientConfiguredRouteEditorV1 {
    public typealias RouteID = @Sendable () throws -> WireBytes16

    public static func apply(
        _ intent: ClientConfiguredRouteEditIntentV1,
        to snapshot: ClientConfiguredRouteCatalogSnapshotV1,
        newRouteID: RouteID = {
            let bytes = UUID().uuid
            return try withUnsafeBytes(of: bytes) {
                try WireBytes16(Data($0))
            }
        }
    ) throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        guard snapshot.revision
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw ClientConfiguredRouteEditErrorV1.revisionExhausted
        }
        var records = snapshot.catalog.records
        switch intent {
        case let .add(endpoint, provenance):
            records.append(try ClientConfiguredRouteRecordV1(
                configuredRouteID: newRouteID(),
                endpoint: endpoint,
                provenance: provenance
            ))
        case let .replace(configuredRouteID, endpoint, provenance):
            guard let index = records.firstIndex(where: {
                $0.configuredRouteID == configuredRouteID
            }) else {
                throw ClientConfiguredRouteEditErrorV1.routeNotFound
            }
            let replacement = try ClientConfiguredRouteRecordV1(
                configuredRouteID: configuredRouteID,
                endpoint: endpoint,
                provenance: provenance
            )
            guard replacement != records[index] else {
                throw ClientConfiguredRouteEditErrorV1.noChange
            }
            records[index] = replacement
        case let .remove(configuredRouteID):
            guard let index = records.firstIndex(where: {
                $0.configuredRouteID == configuredRouteID
            }) else {
                throw ClientConfiguredRouteEditErrorV1.routeNotFound
            }
            records.remove(at: index)
        }
        return try ClientConfiguredRouteCatalogSnapshotV1(
            hostID: snapshot.hostID,
            revision: snapshot.revision + 1,
            catalog: ClientConfiguredRouteCatalogV1(records: records)
        )
    }
}
