import CompanionClient
import CompanionDiscovery
import Foundation

public struct ClientRouteBootstrapChoiceRowV1:
    Equatable, Sendable
{
    public let endpoint: EndpointCandidate
    public let endpointText: String
    public let choices: [ClientRouteConfigurationTypeV1]
}

public struct ClientRouteBootstrapProjectionV1:
    Equatable, Sendable
{
    public let hostID: UUID
    public let rows: [ClientRouteBootstrapChoiceRowV1]

    public init(plan: ClientConfiguredRouteBootstrapPlanV1) {
        hostID = plan.hostID
        rows = plan.endpointsRequiringExplicitChoice.map { endpoint in
            ClientRouteBootstrapChoiceRowV1(
                endpoint: endpoint,
                endpointText: "\(endpoint.value):\(endpoint.port)",
                choices: ClientRouteConfigurationTypeV1.validChoices(
                    for: endpoint
                )
            )
        }
    }

    public func isComplete(
        _ choices: [
            EndpointCandidate: ClientRouteConfigurationTypeV1
        ]
    ) -> Bool {
        Set(choices.keys) == Set(rows.map(\.endpoint))
            && rows.allSatisfy { row in
                choices[row.endpoint].map(row.choices.contains) == true
            }
    }

    public func domainChoices(
        _ choices: [
            EndpointCandidate: ClientRouteConfigurationTypeV1
        ]
    ) throws -> [
        EndpointCandidate: ClientConfiguredRouteProvenanceV1
    ] {
        guard isComplete(choices) else {
            throw ClientConfiguredRouteBootstrapErrorV1.invalidChoices
        }
        return choices.mapValues(\.provenance)
    }
}
