#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

@Test
func interactiveRoleDataGateIsSingleFlightAndGenerationFenced() {
    var gate = MacLocalXPCInteractiveRoleDataTransactionGateV1()
    let rejectedZero = gate.bind(generation: 0)
    #expect(!rejectedZero)
    let bound = gate.bind(generation: 17)
    #expect(bound)
    let duplicateBind = gate.bind(generation: 17)
    #expect(!duplicateBind)
    #expect(gate.begin(generation: 17, permitted: false) == nil)
    #expect(gate.begin(generation: 18, permitted: true) == nil)

    let first = gate.begin(generation: 17, permitted: true)
    #expect(first?.operation == 1)
    #expect(gate.begin(generation: 17, permitted: true) == nil)
    let finished = gate.finish(first!)
    #expect(finished)
    let repeatedFinish = gate.finish(first!)
    #expect(!repeatedFinish)

    let second = gate.begin(generation: 17, permitted: true)
    #expect(second?.operation == 2)
    #expect(gate.invalidate(generation: 18) == nil)
    #expect(gate.invalidate(generation: 17) == second)
    #expect(gate.generation == nil)
    #expect(gate.active == nil)
    let staleFinish = gate.finish(second!)
    #expect(!staleFinish)
}
#endif
