import CompanionTestSupport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private func errorFixture() throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent("valid/error-operation-not-found.json")
    )
}

@Test func authoritativeOperationErrorIsClosedCorrelatedAndCanonical() throws {
    let envelope = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: errorFixture()
    )
    #expect(envelope.kind == .error)
    #expect(envelope.correlationID != nil)
    #expect(envelope.body.code == "operation.notFound")
    #expect(envelope.body.retry == .never)
    let encoded = try WireCodec.encode(envelope)
    #expect(SHA256.hash(data: encoded).map {
        String(format: "%02x", $0)
    }.joined() == "6701c6cd762a46d0f89c4d39e9387ad5e6071eb9f73d50c749a01887dd33f80b")
}

@Test func protocolErrorRejectsProviderTextNestedValuesAndUnknownArguments() {
    #expect(throws: WireError.self) {
        try ProtocolErrorResponseBody(
            code: "provider.unavailable",
            retry: .afterReconnect,
            safeArguments: .object([
                .init(key: "rawProviderText", value: .string("secret path")),
            ])
        )
    }
    #expect(throws: WireError.self) {
        try ProtocolErrorResponseBody(
            code: "operation.notFound",
            retry: .never,
            safeArguments: .object([
                .init(key: "operationID", value: .object([])),
            ])
        )
    }
    #expect(throws: WireError.self) {
        try ProtocolErrorResponseBody(
            code: "unregistered.secretFailure",
            retry: .never
        )
    }
}

@Test func connectionLevelProtocolErrorMayUseNullCorrelation() throws {
    let body = try ProtocolErrorResponseBody(
        code: "protocol.invalidFrame",
        retry: .never,
        safeArguments: .object([
            .init(key: "reasonCode", value: .string("invalidJSON")),
        ])
    )
    let envelope = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1,
        body: body
    )
    #expect(envelope.correlationID == nil)
}
