import CompanionClient
import CompanionClientUI
import CompanionDomain
import CompanionWire
import Foundation
import Testing

private func approvedActionDescriptor(
    id: String,
    title: String,
    effects: CapabilityEffectFacts
) throws -> CapabilityDiscoveryDescriptorV1 {
    let schema = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "enabled",
            required: true,
            schema: .boolean()
        ),
    ])
    return try CapabilityDiscoveryDescriptorV1(CapabilityDescriptorV1(
        capabilityID: id,
        schemaVersion: 1,
        providerID: "maccompanion.test",
        providerVersion: "1.0.0",
        providerGeneration: UUID(),
        executionRevision: UUID(),
        englishTitle: title,
        englishSummary: "A bounded approved action.",
        parameterSchema: schema,
        resultSchema: schema,
        effects: effects
    ))
}

private func lowRiskEffects() throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: .none,
        changesLocalState: .reversible,
        mayDisruptUser: false,
        invokesExternalService: false,
        usesCredentials: false,
        destructive: false,
        requiresForegroundSession: false,
        allowedWhileLocked: false,
        cancellation: .notApplicable
    )
}

@Test func approvedActionsProjectionContainsOnlyTheGrantedCatalog() throws {
    let catalog = GrantedCapabilityCatalogV1(
        registryGeneration: WireUUID(UUID()),
        grantRevision: 3,
        policyRevision: 4,
        capabilities: [
            try approvedActionDescriptor(
                id: "maccompanion.test.second",
                title: "Zoom Window",
                effects: lowRiskEffects()
            ),
            try approvedActionDescriptor(
                id: "maccompanion.test.first",
                title: "Set Audio Mute",
                effects: lowRiskEffects()
            ),
        ]
    )
    let projection = ClientApprovedActionsProjectionV1(catalog: catalog)
    #expect(projection.rows.map(\.id) == [
        "maccompanion.test.first", "maccompanion.test.second",
    ])
    #expect(projection.rows.allSatisfy {
        $0.effectSummary.contains("Unavailable while the Mac is locked")
    })
}

@Test func effectProjectionPreservesEveryRiskAndRequiresReview() throws {
    let effects = try CapabilityEffectFacts(
        dataAccess: .credentials,
        changesLocalState: .irreversible,
        mayDisruptUser: true,
        invokesExternalService: true,
        usesCredentials: true,
        destructive: true,
        requiresForegroundSession: true,
        allowedWhileLocked: false,
        cancellation: .bestEffort
    )
    let projection = ClientApprovedActionEffectProjectionV1(
        CapabilityEffectFactsWireV1(effects)
    )
    #expect(projection.requiresExplicitReview)
    #expect(projection.facts == [
        "Reads credential data",
        "Makes an irreversible change",
        "May disrupt the Mac user",
        "Contacts an external service",
        "Uses saved credentials",
        "Can destroy or remove data",
        "Requires an active Mac user session",
        "Unavailable while the Mac is locked",
        "Cancellation is best effort",
    ])
}

@Test func actionStateKeepsUnknownDeliveryOutcomeAndSuccessDistinct() {
    let delivery = ClientApprovedActionStateProjectionV1(.deliveryUnknown)
    #expect(delivery.title == "Delivery Unknown")
    #expect(delivery.canQuery)
    #expect(!delivery.canInvoke)

    let outcome = ClientApprovedActionStateProjectionV1(
        .terminal(.outcomeUnknown)
    )
    #expect(outcome.title == "Outcome Unknown")
    #expect(!outcome.canQuery)

    let result: CanonicalJSONValue = .object([
        .init(key: "isMuted", value: .boolean(true)),
    ])
    let success = ClientApprovedActionStateProjectionV1(
        .terminal(.succeeded(verifiedResult: result))
    )
    #expect(success.title == "Completed")
    #expect(success.verifiedResult == result)
    #expect(ClientVerifiedResultProjectionV1.rows(result) == [
        .init(id: "$.isMuted", label: "Is Muted", value: "Yes"),
    ])
}

@Test func unknownRemoteCodeIsShownOnlyAsBoundedIdentifierAndRetry() throws {
    let remote = ClientOperationRemoteErrorV1(try ProtocolErrorResponseBody(
        code: "provider.unavailable",
        retry: .afterReconnect
    ))
    let projection = ClientApprovedActionStateProjectionV1(
        .remoteRejected(remote)
    )
    #expect(projection.title == "Request Rejected")
    #expect(projection.detail == "Reconnect and reload approved actions. Code: provider.unavailable")
}
