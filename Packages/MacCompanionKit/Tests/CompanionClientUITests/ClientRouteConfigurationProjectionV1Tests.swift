import CompanionClient
import CompanionClientUI
import CompanionDiscovery
import CompanionTransport
import CompanionWire
import Foundation
import Testing

@Test func routeConfigurationProjectionOffersOnlyExplicitValidTypes()
    throws
{
    let privateRecord = try ClientConfiguredRouteRecordV1(
        configuredRouteID: WireBytes16(Data(repeating: 1, count: 16)),
        endpoint: EndpointCandidate(
            kind: .ipv4,
            value: "192.168.1.10",
            port: 47_474
        ),
        provenance: .directPrivateAddress
    )
    let publicPrivateNetworkRecord = try ClientConfiguredRouteRecordV1(
        configuredRouteID: WireBytes16(Data(repeating: 2, count: 16)),
        endpoint: EndpointCandidate(
            kind: .ipv4,
            value: "203.0.113.10",
            port: 443
        ),
        provenance: .privateNetwork
    )
    let projection = ClientRouteConfigurationProjectionV1(
        snapshot: try ClientConfiguredRouteCatalogSnapshotV1(
            hostID: UUID(),
            revision: 3,
            catalog: ClientConfiguredRouteCatalogV1(records: [
                privateRecord,
                publicPrivateNetworkRecord,
            ])
        )
    )

    #expect(projection.revision == 3)
    #expect(projection.rows[0].typeChoices == [.privateNetwork])
    #expect(projection.rows[1].typeChoices.isEmpty)
    #expect(projection.rows[1].endpoint == "203.0.113.10:443")
}

@Test func routeConfigurationDraftProducesOnlyClosedDomainIntents() throws {
    let draft = try ClientRouteConfigurationDraftV1(
        type: .privateDNS,
        endpointKind: .dns,
        value: "studio.example.net",
        portText: "443"
    )
    guard case let .add(endpoint, provenance) = draft.addIntent else {
        Issue.record("draft did not produce an add intent")
        return
    }
    #expect(endpoint.value == "studio.example.net")
    #expect(provenance == .privateDNS)

    #expect(throws: ClientRouteConfigurationDraftErrorV1.invalidEndpoint) {
        _ = try ClientRouteConfigurationDraftV1(
            type: .directPrivateAddress,
            endpointKind: .ipv4,
            value: "203.0.113.11",
            portText: "443"
        )
    }
    #expect(
        throws:
            ClientRouteConfigurationDraftErrorV1.unsupportedEndpointKind
    ) {
        _ = try ClientRouteConfigurationDraftV1(
            type: .privateDNS,
            endpointKind: .ipv4,
            value: "192.168.1.11",
            portText: "443"
        )
    }
}

@Test func routeBootstrapProjectionRequiresEveryAmbiguousExplicitChoice()
    throws
{
    let dns = try EndpointCandidate(
        kind: .dns,
        value: "bootstrap.example.net",
        port: 443
    )
    let publicAddress = try EndpointCandidate(
        kind: .ipv4,
        value: "203.0.113.14",
        port: 443
    )
    let privateAddress = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.14",
        port: 47_474
    )
    let bonjour = try EndpointCandidate(
        kind: .bonjour,
        value: "studio._maccompanion._tcp.local.",
        port: 47_474
    )
    let projection = ClientRouteBootstrapProjectionV1(
        plan: ClientConfiguredRouteBootstrapPlanV1(
            hostID: UUID(),
            endpoints: [dns, publicAddress, privateAddress, bonjour]
        )
    )

    #expect(projection.rows.map(\.endpoint) == [dns, publicAddress])
    #expect(projection.rows[0].choices == [.privateDNS, .privateNetwork])
    #expect(projection.rows[1].choices == [.privateNetwork])
    #expect(!projection.isComplete([dns: .privateDNS]))
    #expect(!projection.isComplete([
        dns: .directPrivateAddress,
        publicAddress: .privateNetwork,
    ]))

    let choices: [EndpointCandidate: ClientRouteConfigurationTypeV1] = [
        dns: .privateDNS,
        publicAddress: .privateNetwork,
    ]
    #expect(projection.isComplete(choices))
    #expect(try projection.domainChoices(choices) == [
        dns: .privateDNS,
        publicAddress: .privateNetwork,
    ])
}

@Test func privateRouteGuidanceKeepsProvidersOutsideAuthorization() throws {
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "studio.example.net",
        port: 47_474
    )
    let snapshot = try ClientConfiguredRouteCatalogSnapshotV1(
        hostID: UUID(),
        revision: 4,
        catalog: ClientConfiguredRouteCatalogV1(records: [
            try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: 8, count: 16)
                ),
                endpoint: endpoint,
                provenance: .privateNetwork
            ),
        ])
    )

    let setup = ClientPrivateRouteGuidanceProjectionV1(snapshot: snapshot)
    #expect(setup.status.title == "Choose how to reach this Mac")
    #expect(setup.status.tone == .neutral)
    #expect(setup.methods.map(\.id) == [
        .sameLocalNetwork,
        .userManagedPrivateNetwork,
    ])
    #expect(setup.methods[1].summary.contains("Tailscale"))
    #expect(setup.securityBoundary.contains("operates no relay"))
    #expect(setup.securityBoundary.contains("grants"))

    let connected = ClientPrivateRouteGuidanceProjectionV1(
        snapshot: snapshot,
        connection: .authenticated(endpoint: endpoint)
    )
    #expect(connected.status.title == "Connected through Private Network")
    #expect(connected.status.tone == .success)
    #expect(connected.status.detail.contains("grants no capability"))

    let changed = ClientPrivateRouteGuidanceProjectionV1(
        snapshot: snapshot,
        connection: .authenticated(endpoint: try EndpointCandidate(
            kind: .dns,
            value: "other.example.net",
            port: 47_474
        ))
    )
    #expect(changed.status.title == "Route configuration changed")
    #expect(changed.status.tone == .needsAttention)
}

@Test func privateRouteGuidanceSeparatesRouteFailureFromAuthorization()
    throws
{
    let snapshot = try ClientConfiguredRouteCatalogSnapshotV1(
        hostID: UUID(),
        revision: 1,
        catalog: ClientConfiguredRouteCatalogV1(records: [
            try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: 9, count: 16)
                ),
                endpoint: EndpointCandidate(
                    kind: .ipv4,
                    value: "192.168.1.9",
                    port: 47_474
                ),
                provenance: .directPrivateAddress
            ),
        ])
    )
    let cases: [(
        ClientPrivateRouteGuidanceConnectionV1,
        String,
        ClientPrivateRouteGuidanceToneV1
    )] = [
        (.waitingForForeground, "Waiting for Mac Companion", .neutral),
        (.waitingForNetwork, "No usable network path", .needsAttention),
        (.ready, "Ready to try saved routes", .progress),
        (.connecting, "Trying saved routes", .progress),
        (.retrying(failedRounds: 1), "Saved routes have not answered", .needsAttention),
        (.requiresUserAction, "Mac Companion authorization needs attention", .needsAttention),
        (.manuallyDisconnected, "Disconnected by you", .neutral),
        (.closed, "Connection owner stopped", .needsAttention),
        (.statusUnavailable, "Connection status unavailable", .needsAttention),
    ]

    for (connection, title, tone) in cases {
        let projection = ClientPrivateRouteGuidanceProjectionV1(
            snapshot: snapshot,
            connection: connection
        )
        #expect(projection.status.title == title)
        #expect(projection.status.tone == tone)
    }
    let denied = ClientPrivateRouteGuidanceProjectionV1(
        snapshot: snapshot,
        connection: .requiresUserAction
    )
    #expect(denied.status.detail.contains("network route answered"))
    #expect(denied.status.detail.contains("pairing and device access"))
}

@Test func privateRouteGuidanceMapsEveryReconnectPhaseWithoutInference()
    throws
{
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "studio.example.test",
        port: 47_474
    )
    let roundID = UUID()
    let cases: [(
        ReconnectPhase,
        Int,
        ClientPrivateRouteGuidanceConnectionV1
    )] = [
        (.waitingForForeground, 0, .waitingForForeground),
        (.waitingForNetwork, 0, .waitingForNetwork),
        (.ready, 0, .ready),
        (.dialing(roundID), 0, .connecting),
        (.backoff(untilMonotonicMilliseconds: 2_000), 2, .retrying(failedRounds: 2)),
        (.connected(endpoint), 0, .authenticated(endpoint: endpoint)),
        (.requiresUserAction, 0, .requiresUserAction),
        (.manuallyDisconnected, 0, .manuallyDisconnected),
    ]

    for (phase, failedRounds, expected) in cases {
        #expect(ClientPrivateRouteGuidanceProjectionV1.connection(
            reconnectPhase: phase,
            failedRounds: failedRounds
        ) == expected)
    }
    #expect(ClientPrivateRouteGuidanceProjectionV1.connection(
        reconnectPhase: .backoff(untilMonotonicMilliseconds: 2_000),
        failedRounds: 0
    ) == .statusUnavailable)
}
