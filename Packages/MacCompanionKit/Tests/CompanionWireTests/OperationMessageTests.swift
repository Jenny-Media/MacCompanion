import CompanionDomain
import CompanionTestSupport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private func operationFixture(_ name: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent("valid/\(name).json")
    )
}

private func operationFixtureHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func mutatedOperationFixture(
    _ name: String,
    mutate: (inout [String: Any]) -> Void
) throws -> Data {
    var root = try #require(
        JSONSerialization.jsonObject(with: operationFixture(name)) as? [String: Any]
    )
    mutate(&root)
    return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
}

@Test func authoritativeOperationInvokeDecodesNativeParameters() throws {
    let envelope = try WireCodec.decode(
        WireEnvelope<OperationInvokeRequestBody>.self,
        from: operationFixture("operation-invoke")
    )

    #expect(envelope.kind == .operationInvoke)
    #expect(envelope.correlationID == nil)
    #expect(envelope.body.capabilityID == "com.maccompanion.files.list.v1")
    #expect(
        CanonicalJSON.canonicalData(for: envelope.body.parameters)
            == Data(#"{"includeHidden":false,"maxItems":25,"path":"/Users/example/Documents"}"#.utf8)
    )
    #expect(
        operationFixtureHash(try WireCodec.encode(envelope))
            == "c1ea47128f72e0c63ea8b609a88f0d74d11c59a5f3c1c6de42379a80fe6a6aef"
    )
}

@Test func authoritativeOperationApprovalMessagesDecodeCanonically() throws {
    let required = try WireCodec.decode(
        WireEnvelope<OperationApprovalRequiredBody>.self,
        from: operationFixture("operation-approval-required")
    )
    let approve = try WireCodec.decode(
        WireEnvelope<OperationApproveRequestBody>.self,
        from: operationFixture("operation-approve")
    )

    #expect(required.correlationID?.rawValue.uuidString.lowercased()
        == "018f7000-0000-7000-8000-000000000001")
    #expect(required.body.operationDigest.rawValue == Data(0x10...0x2f))
    #expect(required.body.serverChallenge.rawValue == Data(0x30...0x4f))
    #expect(required.body.expiresAtUnixMilliseconds - required.body.issuedAtUnixMilliseconds == 60_000)
    #expect(approve.correlationID == nil)
    #expect(approve.body.signature.rawValue.count == 64)
    #expect(
        operationFixtureHash(try WireCodec.encode(required))
            == "b7ceb5decab271412f2f6c40e27f486513179a8a51f47343b05cccd270fdb383"
    )
    #expect(
        operationFixtureHash(try WireCodec.encode(approve))
            == "3fb24fb4f41703376a197591ed392b52255679d5e08804112bed967eca24462a"
    )
}

@Test func authoritativeOperationObservationMessagesDecodeCanonically() throws {
    let request = try WireCodec.decode(
        WireEnvelope<OperationStatusRequestBody>.self,
        from: operationFixture("operation-status-request")
    )
    let response = try WireCodec.decode(
        WireEnvelope<OperationStatusResponseBody>.self,
        from: operationFixture("operation-status-response")
    )
    let cancel = try WireCodec.decode(
        WireEnvelope<OperationCancelRequestBody>.self,
        from: operationFixture("operation-cancel")
    )

    #expect(request.correlationID == nil)
    #expect(response.body.state == .succeeded)
    #expect(response.body.terminalCode == "operation.succeeded")
    #expect(response.body.result != nil)
    #expect(cancel.correlationID == nil)
    #expect(
        operationFixtureHash(try WireCodec.encode(request))
            == "2f96d53ac8b99fc59da7e07fb921f9c5fabea0d151d5e93cc35dcb7f64a791d1"
    )
    #expect(
        operationFixtureHash(try WireCodec.encode(response))
            == "5866377e23c9229d1202b392eca4abf5558e3f064e1c9960306a71610b696369"
    )
    #expect(
        operationFixtureHash(try WireCodec.encode(cancel))
            == "0848282f52ae66a40fc255a9582809bc23c25301a90eba86d23701e6c28aec4e"
    )
}

@Test func operationInvokeRejectsAmbiguousOrUnboundedParameters() throws {
    let nonObject = try mutatedOperationFixture("operation-invoke") { root in
        var body = root["body"] as! [String: Any]
        body["parameters"] = ["not", "an", "object"]
        root["body"] = body
    }
    let floatingPoint = try mutatedOperationFixture("operation-invoke") { root in
        var body = root["body"] as! [String: Any]
        var parameters = body["parameters"] as! [String: Any]
        parameters["maxItems"] = 1.5
        body["parameters"] = parameters
        root["body"] = body
    }
    let unsafeInteger = try mutatedOperationFixture("operation-invoke") { root in
        var body = root["body"] as! [String: Any]
        var parameters = body["parameters"] as! [String: Any]
        parameters["maxItems"] = 9_007_199_254_740_992 as Int64
        body["parameters"] = parameters
        root["body"] = body
    }
    let unknownField = try mutatedOperationFixture("operation-invoke") { root in
        var body = root["body"] as! [String: Any]
        body["providerHint"] = "unsafe-routing"
        root["body"] = body
    }

    for payload in [nonObject, floatingPoint, unsafeInteger, unknownField] {
        #expect(throws: (any Error).self) {
            try WireCodec.decode(WireEnvelope<OperationInvokeRequestBody>.self, from: payload)
        }
    }
}

@Test func operationApprovalRejectsInvalidLifetimeAndSignatureWidth() throws {
    let excessiveLifetime = try mutatedOperationFixture("operation-approval-required") { root in
        var body = root["body"] as! [String: Any]
        body["expiresAtUnixMilliseconds"] = 1_787_198_560_011 as Int64
        root["body"] = body
    }
    let shortSignature = try mutatedOperationFixture("operation-approve") { root in
        var body = root["body"] as! [String: Any]
        body["signature"] = "AA"
        root["body"] = body
    }

    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<OperationApprovalRequiredBody>.self,
            from: excessiveLifetime
        )
    }
    #expect(throws: (any Error).self) {
        try WireCodec.decode(
            WireEnvelope<OperationApproveRequestBody>.self,
            from: shortSignature
        )
    }
}

@Test func operationStatusEnforcesClosedStateAndResultSemantics() throws {
    let operationID = WireUUID(UUID(uuidString: "018f7100-0000-7000-8000-000000000001")!)
    let resultObject = CanonicalJSONValue.object([
        .init(key: "accepted", value: .boolean(true)),
    ])

    #expect(throws: WireError.self) {
        try OperationStatusResponseBody(
            operationID: operationID,
            state: .running,
            terminalCode: "operation.running",
            result: nil
        )
    }
    #expect(throws: WireError.self) {
        try OperationStatusResponseBody(
            operationID: operationID,
            state: .failed,
            terminalCode: "provider.failed",
            result: resultObject
        )
    }
    #expect(throws: WireError.self) {
        try OperationStatusResponseBody(
            operationID: operationID,
            state: .succeeded,
            terminalCode: "operation.succeeded",
            result: .array([])
        )
    }

    let queued = try OperationStatusResponseBody(
        operationID: operationID,
        state: .queued,
        terminalCode: nil,
        result: nil
    )
    let envelope = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1,
        body: queued
    )
    let encoded = String(decoding: try WireCodec.encode(envelope), as: UTF8.self)
    #expect(encoded.contains(#""terminalCode":null"#))
    #expect(encoded.contains(#""result":null"#))
}

@Test func operationConstructionRejectsUnsafeCanonicalValues() throws {
    let operationID = WireUUID(UUID())
    let unsafeInteger = CanonicalJSONValue.object([
        .init(
            key: "value",
            value: .integer(WireLimits.maximumSafeInteger + 1)
        ),
    ])
    let duplicateKeys = CanonicalJSONValue.object([
        .init(key: "same", value: .boolean(true)),
        .init(key: "same", value: .boolean(false)),
    ])

    for parameters in [unsafeInteger, duplicateKeys] {
        #expect(throws: WireError.self) {
            try OperationInvokeRequestBody(
                operationID: operationID,
                capabilityID: "com.maccompanion.test.v1",
                parameters: parameters
            )
        }
    }
}

@Test func operationEnvelopeCorrelationDirectionIsEnforced() throws {
    let invoke = try WireCodec.decode(
        WireEnvelope<OperationInvokeRequestBody>.self,
        from: operationFixture("operation-invoke")
    )
    let response = try WireCodec.decode(
        WireEnvelope<OperationStatusResponseBody>.self,
        from: operationFixture("operation-status-response")
    )

    #expect(throws: WireError.self) {
        try WireEnvelope(
            messageID: invoke.messageID,
            correlationID: invoke.messageID,
            sentAtUnixMilliseconds: invoke.sentAtUnixMilliseconds,
            body: invoke.body
        )
    }
    #expect(throws: WireError.self) {
        try WireEnvelope(
            messageID: response.messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: response.sentAtUnixMilliseconds,
            body: response.body
        )
    }
}
