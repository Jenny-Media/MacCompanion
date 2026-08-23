#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

@Test
func interactiveAdmissionGateIsIndependentSingleFlightAndGenerationFenced() {
    var gate = MacLocalXPCInteractiveAdmissionTransactionGateV1()
    let rejectedZero = gate.bind(generation: 0)
    #expect(!rejectedZero)
    let bound = gate.bind(generation: 41)
    #expect(bound)
    let duplicateBind = gate.bind(generation: 41)
    #expect(!duplicateBind)
    let denied = gate.begin(generation: 41, permitted: false)
    #expect(denied == nil)

    let first = gate.begin(generation: 41, permitted: true)
    #expect(first?.operation == 1)
    let concurrent = gate.begin(generation: 41, permitted: true)
    #expect(concurrent == nil)
    let staleGeneration = gate.begin(generation: 42, permitted: true)
    #expect(staleGeneration == nil)
    let finished = gate.finish(first!)
    #expect(finished)
    let repeatedFinish = gate.finish(first!)
    #expect(!repeatedFinish)

    let second = gate.begin(generation: 41, permitted: true)
    #expect(second?.operation == 2)
    let staleInvalidation = gate.invalidate(generation: 42)
    #expect(staleInvalidation == nil)
    let invalidated = gate.invalidate(generation: 41)
    #expect(invalidated == second)
    #expect(gate.generation == nil)
    #expect(gate.active == nil)
    let staleFinish = gate.finish(second!)
    #expect(!staleFinish)
}
#endif
