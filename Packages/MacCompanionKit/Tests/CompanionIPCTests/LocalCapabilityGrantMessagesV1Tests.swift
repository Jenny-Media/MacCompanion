import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private func actReviewSample() throws -> (LocalCapabilityGrantReviewRequestV1, LocalCapabilityGrantReviewV1) {
    let request = try LocalCapabilityGrantReviewRequestV1(commandID: UUID(), deviceID: UUID(),
        capabilityID: "sample.action", requestedAtUnixMilliseconds: 1_000)
    let descriptor = try CapabilityDescriptorV1(capabilityID: request.capabilityID, schemaVersion: 1,
        providerID: "sample.provider", providerVersion: "1.0", providerGeneration: UUID(), executionRevision: UUID(),
        englishTitle: "Sample", englishSummary: "Changes test-owned state", parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []), effects: CapabilityEffectFacts(dataAccess: .none, changesLocalState: .reversible,
            mayDisruptUser: false, invokesExternalService: false, usesCredentials: false, destructive: false,
            requiresForegroundSession: false, allowedWhileLocked: false, cancellation: .notApplicable))
    return (request, try LocalCapabilityGrantReviewV1(correlationID: request.commandID, reviewID: UUID(),
        deviceID: request.deviceID, deviceDisplayName: DeviceDisplayName("Test phone"),
        authorizationEpoch: .init(rawValue: 1), grantRevision: .init(rawValue: 1), policyRevision: .init(rawValue: 1),
        currentGrantIDs: [], registryGeneration: UUID(), descriptor: .init(descriptor),
        createdAtUnixMilliseconds: 1_000, expiresAtUnixMilliseconds: 301_000))
}

@Test func capabilityGrantWireRoundTripAndDistinctDecisionEnvelope() throws {
    let (request, review) = try actReviewSample()
    typealias Codec = LocalMenuPairingCommandWireCodecV1
    #expect(try Codec.decodeCapabilityGrantReviewRequest(Codec.encodeCapabilityGrantReviewRequest(request)) == request)
    let bytes = try Codec.encodeCapabilityGrantReview(review)
    #expect(bytes.count <= Codec.maximumEncodedBytes)
    // JSONDecoder's keyed-container iteration order varies per decode. Exact
    // review retries must compare identically, regardless of that ordering.
    for _ in 0..<32 {
        #expect(try Codec.decodeCapabilityGrantReview(bytes) == review)
    }
    try review.validate(against: request)
    let command = try review.command(commandID: UUID(), decision: .approve, decidedAtUnixMilliseconds: 1_001)
    let wrapped = LocalCapabilityGrantDecisionCommandV1(decision: command)
    #expect(try Codec.decodeCapabilityGrantDecision(Codec.encodeCapabilityGrantDecision(wrapped)) == wrapped)
    #expect(throws: (any Error).self) { try Codec.decodeGrantDecisionCommand(Codec.encodeCapabilityGrantDecision(wrapped)) }
    #expect(throws: (any Error).self) { try Codec.decodeCapabilityGrantDecision(Codec.encodeGrantDecisionCommand(command)) }
    #expect(throws: (any Error).self) { try Codec.decodeDeviceRevocationReviewRequest(Codec.encodeCapabilityGrantReviewRequest(request)) }
    #expect(throws: (any Error).self) { try LocalCapabilityGrantReviewRequestV1(commandID: UUID(), deviceID: UUID(),
        capabilityID: InteractiveControlDurableGrantV0.identifier, requestedAtUnixMilliseconds: 1_000) }
}

@Test(arguments: ["unknown", "effects", "provider", "expiry", "grants", "version"])
func capabilityGrantWireRejectsMalformedFacts(change: String) throws {
    let (_, review) = try actReviewSample()
    typealias Codec = LocalMenuPairingCommandWireCodecV1
    var value = try #require(JSONSerialization.jsonObject(with: Codec.encodeCapabilityGrantReview(review)) as? [String: Any])
    switch change {
    case "unknown": value["unexpected"] = true
    case "expiry": value["expiresAtUnixMilliseconds"] = 301_001
    case "grants": value["currentGrantIDs"] = ["z", "a"]
    case "version": value["protocolVersion"] = ["major": 99, "minor": 0]
    default:
        var descriptor = try #require(value["descriptor"] as? [String: Any])
        if change == "provider" { descriptor["providerID"] = "invalid provider" }
        else {
            var capability = try #require(descriptor["capability"] as? [String: Any])
            var effects = try #require(capability["effects"] as? [String: Any])
            effects["unexpected"] = false
            capability["effects"] = effects
            descriptor["capability"] = capability
        }
        value["descriptor"] = descriptor
    }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: (any Error).self) { try Codec.decodeCapabilityGrantReview(data) }
}
