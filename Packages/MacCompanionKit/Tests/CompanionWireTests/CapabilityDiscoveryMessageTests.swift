import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func discoveryFixture(_ name: String) throws -> Data {
    try Data(contentsOf: FixturePaths.authoritativeFixtures()
        .appendingPathComponent("valid/\(name).json"))
}

@Test func authoritativeCapabilityDiscoveryFixturesRoundTripCanonically() throws {
    let requestData = try discoveryFixture("capability-registry-request")
    let request = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryRequestBody>.self,
        from: requestData
    )
    #expect(request.body.expectedRegistryGeneration == nil)
    #expect(request.body.expectedGrantRevision == nil)
    #expect(request.body.afterCapabilityID == nil)
    #expect(try CanonicalJSON.canonicalize(WireCodec.encode(request))
        == CanonicalJSON.canonicalize(requestData))

    let responseData = try discoveryFixture("capability-registry-response")
    let response = try WireCodec.decode(
        WireEnvelope<CapabilityRegistryResponseBody>.self,
        from: responseData
    )
    let descriptor = try #require(response.body.capabilities.first)
    #expect(descriptor.capabilityID == "maccompanion.system.setAudioMuted")
    #expect(try CapabilitySchemaV1(
        wireValue: descriptor.parameterSchema
    ).isObject)
    #expect(descriptor.effects.allowedWhileLocked == false)
    let encoded = try WireCodec.encode(response)
    #expect(try CanonicalJSON.canonicalize(encoded)
        == CanonicalJSON.canonicalize(responseData))
    #expect(!String(decoding: encoded, as: UTF8.self).contains("providerID"))
    #expect(!String(decoding: encoded, as: UTF8.self).contains("executionRevision"))
}

@Test func everyClosedCapabilitySchemaVariantHasOneRoundTripEncoding() throws {
    let schemas: [CapabilitySchemaV1] = [
        .boolean(),
        try .integer(minimum: -5, maximum: 5),
        try .string(maximumUTF8Bytes: 16, allowedValues: ["one", "two"]),
        try .array(maximumItems: 3, item: .boolean()),
        try .object(properties: [
            CapabilitySchemaPropertyV1(
                name: "enabled",
                required: true,
                schema: .boolean()
            ),
        ]),
    ]
    for schema in schemas {
        let value = try schema.wireValue()
        #expect(try CapabilitySchemaV1(wireValue: value) == schema)
    }
}

@Test func capabilityCursorAndPageShapeAreAllOrNothingAndClosed() throws {
    #expect(throws: (any Error).self) {
        _ = try CapabilityRegistryRequestBody(
            expectedRegistryGeneration: WireUUID(UUID())
        )
    }
    #expect(throws: (any Error).self) {
        _ = try CapabilityRegistryResponseBody(
            registryGeneration: WireUUID(UUID()),
            grantRevision: 1,
            policyRevision: 1,
            capabilities: [],
            nextAfterCapabilityID: "maccompanion.system.setAudioMuted"
        )
    }

    let fixture = try discoveryFixture("capability-registry-request")
    let object = String(decoding: fixture, as: UTF8.self)
        .replacingOccurrences(
            of: "\"afterCapabilityID\": null",
            with: "\"afterCapabilityID\": null, \"unknown\": true"
        )
    #expect(throws: (any Error).self) {
        _ = try WireCodec.decode(
            WireEnvelope<CapabilityRegistryRequestBody>.self,
            from: Data(object.utf8)
        )
    }
}

private struct OversizedConstructionBody: WireBody {
    static let kind = WireMessageKind.keepalivePing
    let value: String
    func validate() throws {}
}

@Test func programmaticWireEncodingStillEnforcesTheFrameLimit() throws {
    let envelope = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1,
        body: OversizedConstructionBody(
            value: String(repeating: "x", count: WireLimits.maximumFrameBytes)
        )
    )
    #expect(throws: WireError.boundsExceeded(
        field: "frame",
        limit: WireLimits.maximumFrameBytes
    )) {
        _ = try WireCodec.encode(envelope)
    }
}
