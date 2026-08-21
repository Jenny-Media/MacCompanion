import CompanionDiscovery
import CompanionWire
import Darwin
import Foundation

public enum ClientConfiguredRouteProvenanceV1:
    String, Codable, CaseIterable, Sendable
{
    case localDiscovery
    case directPrivateAddress
    case privateDNS
    case privateNetwork
}

public enum ClientConfiguredRouteCatalogErrorV1:
    Error, Equatable, Sendable
{
    case invalidRecord
    case boundsExceeded
    case duplicateRouteID
    case duplicateEndpoint
    case winnerNotConfigured
}

public struct ClientConfiguredRouteRecordV1:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case configuredRouteID, endpoint, provenance
    }

    public let configuredRouteID: WireBytes16
    public let endpoint: EndpointCandidate
    public let provenance: ClientConfiguredRouteProvenanceV1

    public init(
        configuredRouteID: WireBytes16,
        endpoint: EndpointCandidate,
        provenance: ClientConfiguredRouteProvenanceV1
    ) throws {
        guard Self.matches(provenance, endpoint) else {
            throw ClientConfiguredRouteCatalogErrorV1.invalidRecord
        }
        self.configuredRouteID = configuredRouteID
        self.endpoint = endpoint
        self.provenance = provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw ClientConfiguredRouteCatalogErrorV1.invalidRecord
        }
        try self.init(
            configuredRouteID: container.decode(
                WireBytes16.self,
                forKey: .configuredRouteID
            ),
            endpoint: container.decode(
                EndpointCandidate.self,
                forKey: .endpoint
            ),
            provenance: container.decode(
                ClientConfiguredRouteProvenanceV1.self,
                forKey: .provenance
            )
        )
    }

    public var observedRouteClass: ConfiguredRouteClassV1? {
        switch provenance {
        case .privateDNS: .privateDNS
        case .privateNetwork: .privateNetwork
        case .localDiscovery, .directPrivateAddress: nil
        }
    }

    private static func matches(
        _ provenance: ClientConfiguredRouteProvenanceV1,
        _ endpoint: EndpointCandidate
    ) -> Bool {
        switch provenance {
        case .localDiscovery:
            endpoint.kind == .bonjour
        case .directPrivateAddress:
            isEligibleForDirectPrivateAddress(endpoint)
        case .privateDNS:
            endpoint.kind == .dns
        case .privateNetwork:
            endpoint.kind == .dns
                || endpoint.kind == .ipv4
                || endpoint.kind == .ipv6
        }
    }

    public static func isEligibleForDirectPrivateAddress(
        _ endpoint: EndpointCandidate
    ) -> Bool {
        switch endpoint.kind {
        case .ipv4:
            let octets = endpoint.value.split(separator: ".").compactMap {
                UInt8($0)
            }
            guard octets.count == 4 else { return false }
            return octets[0] == 10
                || (octets[0] == 172 && (16...31).contains(octets[1]))
                || (octets[0] == 192 && octets[1] == 168)
        case .ipv6:
            var address = in6_addr()
            guard endpoint.value.withCString({
                inet_pton(AF_INET6, $0, &address)
            }) == 1 else {
                return false
            }
            return withUnsafeBytes(of: &address) {
                ($0[0] & 0xfe) == 0xfc
            }
        case .bonjour, .dns:
            return false
        }
    }
}

public struct ClientConfiguredRouteCatalogV1:
    Codable, Equatable, Sendable
{
    public static let maximumRecords = 8
    public let records: [ClientConfiguredRouteRecordV1]

    public init(records: [ClientConfiguredRouteRecordV1]) throws {
        guard (1...Self.maximumRecords).contains(records.count) else {
            throw ClientConfiguredRouteCatalogErrorV1.boundsExceeded
        }
        guard Set(records.map(\.configuredRouteID.rawValue)).count
                == records.count
        else {
            throw ClientConfiguredRouteCatalogErrorV1.duplicateRouteID
        }
        guard Set(records.map(\.endpoint)).count == records.count else {
            throw ClientConfiguredRouteCatalogErrorV1.duplicateEndpoint
        }
        self.records = records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(
            records: container.decode([ClientConfiguredRouteRecordV1].self)
        )
    }

    public func exactRecord(
        forWinningEndpoint endpoint: EndpointCandidate
    ) throws -> ClientConfiguredRouteRecordV1 {
        guard let record = records.first(where: { $0.endpoint == endpoint })
        else {
            throw ClientConfiguredRouteCatalogErrorV1.winnerNotConfigured
        }
        return record
    }
}
