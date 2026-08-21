import CompanionClient
import CompanionDiscovery
import CompanionWire
import Foundation

public enum ClientRouteConfigurationTypeV1:
    String, CaseIterable, Equatable, Identifiable, Sendable
{
    case localDiscovery
    case directPrivateAddress
    case privateDNS
    case privateNetwork

    public var id: String { rawValue }

    public var provenance: ClientConfiguredRouteProvenanceV1 {
        switch self {
        case .localDiscovery: .localDiscovery
        case .directPrivateAddress: .directPrivateAddress
        case .privateDNS: .privateDNS
        case .privateNetwork: .privateNetwork
        }
    }

    public var title: String {
        switch self {
        case .localDiscovery: "Local Discovery"
        case .directPrivateAddress: "Private Address"
        case .privateDNS: "Private DNS"
        case .privateNetwork: "Private Network"
        }
    }

    public var allowedEndpointKinds: [EndpointKind] {
        switch self {
        case .localDiscovery: [.bonjour]
        case .directPrivateAddress: [.ipv4, .ipv6]
        case .privateDNS: [.dns]
        case .privateNetwork: [.dns, .ipv4, .ipv6]
        }
    }

    public static func validChoices(
        for endpoint: EndpointCandidate
    ) -> [ClientRouteConfigurationTypeV1] {
        allCases.filter { choice in
            choice.allowedEndpointKinds.contains(endpoint.kind)
                && (choice != .directPrivateAddress
                    || ClientConfiguredRouteRecordV1
                        .isEligibleForDirectPrivateAddress(endpoint))
        }
    }
}

public enum ClientRouteConfigurationDraftErrorV1:
    Error, Equatable, Sendable
{
    case unsupportedEndpointKind
    case invalidPort
    case invalidEndpoint
}

public struct ClientRouteConfigurationDraftV1: Equatable, Sendable {
    public let type: ClientRouteConfigurationTypeV1
    public let endpoint: EndpointCandidate

    public init(
        type: ClientRouteConfigurationTypeV1,
        endpointKind: EndpointKind,
        value: String,
        portText: String
    ) throws {
        guard type.allowedEndpointKinds.contains(endpointKind) else {
            throw ClientRouteConfigurationDraftErrorV1
                .unsupportedEndpointKind
        }
        guard let port = UInt16(portText), port > 0 else {
            throw ClientRouteConfigurationDraftErrorV1.invalidPort
        }
        do {
            let endpoint = try EndpointCandidate(
                kind: endpointKind,
                value: value,
                port: port
            )
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(Data(repeating: 0, count: 16)),
                endpoint: endpoint,
                provenance: type.provenance
            )
            self.type = type
            self.endpoint = endpoint
        } catch {
            throw ClientRouteConfigurationDraftErrorV1.invalidEndpoint
        }
    }

    public var addIntent: ClientConfiguredRouteEditIntentV1 {
        .add(endpoint: endpoint, provenance: type.provenance)
    }

    public static func replacementIntent(
        record: ClientConfiguredRouteRecordV1,
        type: ClientRouteConfigurationTypeV1
    ) throws -> ClientConfiguredRouteEditIntentV1 {
        do {
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: record.configuredRouteID,
                endpoint: record.endpoint,
                provenance: type.provenance
            )
        } catch {
            throw ClientRouteConfigurationDraftErrorV1.invalidEndpoint
        }
        return .replace(
            configuredRouteID: record.configuredRouteID,
            endpoint: record.endpoint,
            provenance: type.provenance
        )
    }
}

public struct ClientRouteConfigurationRowV1: Equatable, Sendable {
    public let record: ClientConfiguredRouteRecordV1
    public let title: String
    public let endpoint: String
    public let typeChoices: [ClientRouteConfigurationTypeV1]
}

public struct ClientRouteConfigurationProjectionV1: Equatable, Sendable {
    public let revision: UInt64
    public let rows: [ClientRouteConfigurationRowV1]

    public init(snapshot: ClientConfiguredRouteCatalogSnapshotV1) {
        revision = snapshot.revision
        rows = snapshot.catalog.records.map { record in
            ClientRouteConfigurationRowV1(
                record: record,
                title: ClientRouteConfigurationTypeV1(
                    rawValue: record.provenance.rawValue
                )!.title,
                endpoint: "\(record.endpoint.value):\(record.endpoint.port)",
                typeChoices:
                    ClientRouteConfigurationTypeV1.validChoices(
                        for: record.endpoint
                    ).filter { $0.provenance != record.provenance }
            )
        }
    }
}
