import CompanionWire
import Foundation
import Testing

private let routingMessageID = WireUUID(UUID(
    uuidString: "018fa500-0000-7000-8000-000000000001"
)!)
private let routingCorrelationID = WireUUID(UUID(
    uuidString: "018fa500-0000-7000-8000-000000000002"
)!)

@Test func routingMetadataAdmitsClosedOriginalAndReplyEnvelopes()
    throws
{
    let request = try WireCodec.encode(WireEnvelope(
        messageID: routingMessageID,
        correlationID: nil,
        sentAtUnixMilliseconds: 4_000,
        body: StatusSnapshotRequestBody()
    ))
    let requestMetadata = try WireCodec.routingMetadata(from: request)
    #expect(requestMetadata.messageID == routingMessageID)
    #expect(requestMetadata.correlationID == nil)
    #expect(requestMetadata.kind == .statusSnapshotRequest)

    let reply = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: routingCorrelationID,
        sentAtUnixMilliseconds: 4_001,
        body: try ProtocolErrorResponseBody(
            code: "capability.registryChanged",
            retry: .afterReconnect
        )
    ))
    let replyMetadata = try WireCodec.routingMetadata(from: reply)
    #expect(replyMetadata.correlationID == routingCorrelationID)
    #expect(replyMetadata.kind == .error)
}

@Test func routingMetadataRejectsExtraEnvelopeFieldsAndNonObjectBodies()
    throws
{
    let extra = Data(#"{"body":{},"channel":"command","correlationID":null,"extra":true,"kind":"status.snapshot.request","messageID":"018fa500-0000-7000-8000-000000000001","sentAtUnixMilliseconds":4000,"version":{"major":0,"minor":1}}"#.utf8)
    #expect(throws: (any Error).self) {
        _ = try WireCodec.routingMetadata(from: extra)
    }
    let scalarBody = Data(#"{"body":true,"channel":"command","correlationID":null,"kind":"status.snapshot.request","messageID":"018fa500-0000-7000-8000-000000000001","sentAtUnixMilliseconds":4000,"version":{"major":0,"minor":1}}"#.utf8)
    #expect(throws: (any Error).self) {
        _ = try WireCodec.routingMetadata(from: scalarBody)
    }
}

@Test func routingMetadataEnforcesCorrelationDirectionBeforeDispatch()
    throws
{
    let requestWithCorrelation = Data(#"{"body":{},"channel":"command","correlationID":"018fa500-0000-7000-8000-000000000002","kind":"status.snapshot.request","messageID":"018fa500-0000-7000-8000-000000000001","sentAtUnixMilliseconds":4000,"version":{"major":0,"minor":1}}"#.utf8)
    #expect(throws: (any Error).self) {
        _ = try WireCodec.routingMetadata(from: requestWithCorrelation)
    }
    let replyWithoutCorrelation = Data(#"{"body":{"code":"capability.registryChanged","retry":"afterReconnect","safeArguments":{}},"channel":"command","correlationID":null,"kind":"error","messageID":"018fa500-0000-7000-8000-000000000001","sentAtUnixMilliseconds":4000,"version":{"major":0,"minor":1}}"#.utf8)
    let metadata = try WireCodec.routingMetadata(from: replyWithoutCorrelation)
    #expect(metadata.kind == .error)
    #expect(metadata.correlationID == nil)
}
