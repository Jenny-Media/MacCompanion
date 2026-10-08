#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Foundation
import Testing

@Test func payloadFreeInteractiveLeaseReplyUsesLiteralNullPointer() {
    let emptyShape = MacLocalXPCReplyPayloadBytesV1.withBytes(Data()) {
        bytes, length in
        (bytes == nil, length)
    }
    #expect(emptyShape.0)
    #expect(emptyShape.1 == 0)

    let payloadShape = MacLocalXPCReplyPayloadBytesV1.withBytes(
        Data([0x7b, 0x7d])
    ) { bytes, length in
        (bytes != nil, length, bytes?.pointee)
    }
    #expect(payloadShape.0)
    #expect(payloadShape.1 == 2)
    #expect(payloadShape.2 == 0x7b)
}

@Test func interactiveLeaseEndpointRequiresExactGenerationAndPrivateToken() {
    let token = UUID()
    let binding = MacLocalXPCInteractiveLeaseEndpointBindingV1(
        generation: 11,
        endpointToken: token
    )

    #expect(binding.admits(generation: 11, issuedEndpointToken: token))
    #expect(!binding.admits(generation: 12, issuedEndpointToken: token))
    #expect(!binding.admits(generation: 11, issuedEndpointToken: UUID()))
    #expect(!binding.admits(generation: 11, issuedEndpointToken: nil))
    #expect(
        !MacLocalXPCInteractiveLeaseEndpointBindingV1(
            generation: 0,
            endpointToken: token
        ).admits(generation: 0, issuedEndpointToken: token)
    )
}

@Test func interactiveLeaseGateIsCrossFamilySingleFlightAndGenerationFenced() {
    var gate = MacLocalXPCInteractiveLeaseTransactionGateV1()
    let rejectedZero = gate.bind(generation: 0)
    #expect(!rejectedZero)
    let bound = gate.bind(generation: 11)
    #expect(bound)
    let duplicateBind = gate.bind(generation: 11)
    #expect(!duplicateBind)
    #expect(
        gate.begin(
            generation: 11,
            kind: .install,
            permitted: false
        ) == nil
    )

    let preparation = gate.begin(
        generation: 11,
        kind: .prepareInitialDesktop,
        permitted: true
    )
    #expect(preparation?.operation == 1)
    #expect(
        gate.begin(
            generation: 11,
            kind: .install,
            permitted: true
        ) == nil
    )
    #expect(
        gate.begin(
            generation: 12,
            kind: .revoke,
            permitted: true
        ) == nil
    )
    let finishedPreparation = gate.finish(preparation!)
    #expect(finishedPreparation)
    let repeatedFinish = gate.finish(preparation!)
    #expect(!repeatedFinish)

    let focusSnapshot = gate.begin(
        generation: 11,
        kind: .focusSnapshot,
        permitted: true
    )
    #expect(focusSnapshot?.operation == 2)
    let finishedFocusSnapshot = gate.finish(focusSnapshot!)
    #expect(finishedFocusSnapshot)

    let renewal = gate.begin(
        generation: 11,
        kind: .renew,
        permitted: true
    )
    #expect(renewal?.operation == 3)
    #expect(gate.invalidate(generation: 12) == nil)
    #expect(gate.invalidate(generation: 11) == renewal)
    #expect(gate.generation == nil)
    #expect(gate.active == nil)
    let staleFinish = gate.finish(renewal!)
    #expect(!staleFinish)

    let rebound = gate.bind(generation: 12)
    #expect(rebound)
    let native = gate.begin(generation: 12, kind: .nativeSnapshot, permitted: true)
    #expect(native != nil)
    #expect(gate.begin(generation: 12, kind: .renew, permitted: true) == nil)
    let finishedNative = gate.finish(native!)
    #expect(finishedNative)
    let offer = gate.begin(
        generation: 12,
        kind: .webRTCOffer,
        permitted: true
    )
    #expect(offer != nil)
    let overlappingAnswer = gate.begin(
        generation: 12,
        kind: .webRTCAnswer,
        permitted: true
    )
    #expect(overlappingAnswer == nil)
    let finishedOffer = gate.finish(offer!)
    #expect(finishedOffer)
    let answer = gate.begin(
        generation: 12,
        kind: .webRTCAnswer,
        permitted: true
    )
    #expect(answer != nil)
    let invalidated = gate.invalidate(generation: 12)
    #expect(invalidated == answer)
    let staleAnswer = gate.finish(answer!)
    #expect(!staleAnswer)
}
#endif
