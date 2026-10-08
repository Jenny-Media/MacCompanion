import CompanionInteractiveWire
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private func targetFixture(_ path: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent(path)
    )
}

@Test func authoritativeTargetInventoryMessagesAreCanonical() throws {
    let requestSource = try targetFixture(
        "valid/interactive-surface-targets-request.json"
    )
    let request = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceTargetsRequestBodyV0>.self,
        from: requestSource
    )
    #expect(try WireCodec.encode(request) == Data(requestSource.dropLast()))
    #expect(request.correlationID == nil)

    let responseSource = try targetFixture(
        "valid/interactive-surface-targets-response.json"
    )
    let response = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
        from: responseSource
    )
    #expect(try WireCodec.encode(response) == Data(responseSource.dropLast()))
    #expect(response.correlationID == request.messageID)
    #expect(response.body.validForMilliseconds == 120_000)
    #expect(response.body.candidates.map(\.applicationName) == ["Notes", "Notes"])
    #expect(response.body.candidates.map(\.windowOrdinal) == [nil, 1])
    #expect(response.body.candidates.map(\.windowTitle) == [nil, "Example note"])
}

@Test func targetInventoryRejectsContentMetadataAndInvalidOwnership() throws {
    let source = try targetFixture(
        "valid/interactive-surface-targets-response.json"
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: source) as? [String: Any]
    )
    var body = try #require(object["body"] as? [String: Any])
    var candidates = try #require(body["candidates"] as? [[String: Any]])
    candidates[1]["windowTitle"] = "Invalid\nTitle"
    body["candidates"] = candidates
    object["body"] = body
    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    candidates[1]["windowTitle"] = "Example note"
    candidates[1]["applicationToken"] =
        "018f7200-0000-7000-8000-000000000099"
    body["candidates"] = candidates
    object["body"] = body
    #expect(throws: InteractiveSurfaceTargetMessageErrorV0.invalidInventory) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

@Test func targetInventoryRejectsUnsortedCandidatesAndControlNames() throws {
    let source = try targetFixture(
        "valid/interactive-surface-targets-response.json"
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: source) as? [String: Any]
    )
    var body = try #require(object["body"] as? [String: Any])
    var candidates = try #require(body["candidates"] as? [[String: Any]])
    body["candidates"] = Array(candidates.reversed())
    object["body"] = body
    #expect(throws: InteractiveSurfaceTargetMessageErrorV0.invalidInventory) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    candidates[0]["applicationName"] = "Notes\nPrivate"
    body["candidates"] = candidates
    object["body"] = body
    #expect(throws: InteractiveSurfaceTargetMessageErrorV0.invalidName) {
        try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsResponseBodyV0>.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
