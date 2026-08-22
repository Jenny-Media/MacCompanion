#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

@Test func menuPairingCommandGateIsSingleFlightAndGenerationFenced() {
    var gate = MacLocalXPCMenuPairingCommandTransactionGateV1()
    let rejectedZero = gate.bind(generation: 0)
    #expect(!rejectedZero)
    let bound = gate.bind(generation: 7)
    #expect(bound)
    let duplicateBind = gate.bind(generation: 7)
    #expect(!duplicateBind)
    let denied = gate.begin(
        generation: 7,
        kind: .create,
        permitted: false
    )
    #expect(denied == nil)
    let first = gate.begin(
        generation: 7,
        kind: .create,
        permitted: true
    )
    #expect(first?.operation == 1)
    let concurrent = gate.begin(
        generation: 7,
        kind: .dismiss,
        permitted: true
    )
    #expect(concurrent == nil)
    let staleGeneration = gate.begin(
        generation: 8,
        kind: .dismiss,
        permitted: true
    )
    #expect(staleGeneration == nil)
    let finishedFirst = gate.finish(first!)
    #expect(finishedFirst)
    let repeatedFinish = gate.finish(first!)
    #expect(!repeatedFinish)

    let second = gate.begin(
        generation: 7,
        kind: .resolveDecision,
        permitted: true
    )
    #expect(second?.operation == 2)
    let staleInvalidation = gate.invalidate(generation: 8)
    #expect(staleInvalidation == nil)
    let invalidated = gate.invalidate(generation: 7)
    #expect(invalidated == second)
    #expect(gate.active == nil)
    #expect(gate.generation == nil)
    let staleFinish = gate.finish(second!)
    #expect(!staleFinish)
}
#endif
