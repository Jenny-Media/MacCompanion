import CompanionIPC
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private enum WebRTCFixtureLookupError: Error { case missingRoot }

private func webRTCFixture(_ name: String) throws -> Data {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path
    ) {
        let parent = root.deletingLastPathComponent()
        guard parent != root else { throw WebRTCFixtureLookupError.missingRoot }
        root = parent
    }
    return try Data(contentsOf: root.appendingPathComponent(
        "spec/fixtures/valid/\(name)"
    ))
}

@Test func localWebRTCCommandsPreserveAuthenticatedFenceAndRejectWrongReply()
    throws
{
    let offer = try WireCodec.decode(
        WireEnvelope<InteractiveWebRTCOfferBodyV0>.self,
        from: webRTCFixture("interactive-media-offer.json")
    )
    let answer = try WireCodec.decode(
        WireEnvelope<InteractiveWebRTCAnswerBodyV0>.self,
        from: webRTCFixture("interactive-media-answer.json")
    )
    let request = try LocalInteractiveWebRTCOfferCommandV1(
        commandID: UUID(), fence: offer.body.fence
    )
    let encodedRequest = try LocalInteractiveLeaseWireCodecV1
        .encodeWebRTCOfferCommand(request)
    #expect(encodedRequest.count <= LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes)
    #expect(try LocalInteractiveLeaseWireCodecV1
        .decodeWebRTCOfferCommand(encodedRequest) == request)

    let receipt = try LocalInteractiveWebRTCOfferReceiptV1(
        correlationID: request.commandID, offer: offer.body
    )
    let encodedReceipt = try LocalInteractiveLeaseWireCodecV1
        .encodeWebRTCOfferReceipt(receipt)
    #expect(encodedReceipt.count <= LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes)
    try LocalInteractiveLeaseWireCodecV1
        .decodeWebRTCOfferReceipt(encodedReceipt).validate(against: request)
    let wrongRequest = try LocalInteractiveWebRTCOfferCommandV1(
        commandID: UUID(), fence: offer.body.fence
    )
    #expect(throws: LocalInteractiveWebRTCNegotiationErrorV1.invalidBinding) {
        try receipt.validate(against: wrongRequest)
    }

    let answerCommand = try LocalInteractiveWebRTCAnswerCommandV1(
        commandID: UUID(), answer: answer.body
    )
    let encodedAnswer = try LocalInteractiveLeaseWireCodecV1
        .encodeWebRTCAnswerCommand(answerCommand)
    #expect(try LocalInteractiveLeaseWireCodecV1
        .decodeWebRTCAnswerCommand(encodedAnswer) == answerCommand)
    #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.invalidPayload) {
        _ = try LocalInteractiveLeaseWireCodecV1
            .decodeWebRTCOfferCommand(encodedAnswer)
    }

    let close = LocalInteractiveWebRTCCloseCommandV1(
        commandID: UUID(),
        interactiveSessionID: offer.body.fence.interactiveSessionID.rawValue
    )
    #expect(try LocalInteractiveLeaseWireCodecV1
        .decodeWebRTCCloseCommand(
            LocalInteractiveLeaseWireCodecV1.encodeWebRTCCloseCommand(close)
        ) == close)
}
