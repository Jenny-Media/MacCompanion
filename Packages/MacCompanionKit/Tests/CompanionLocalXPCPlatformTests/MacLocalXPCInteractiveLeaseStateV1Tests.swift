#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

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

    let renewal = gate.begin(
        generation: 11,
        kind: .renew,
        permitted: true
    )
    #expect(renewal?.operation == 2)
    #expect(gate.invalidate(generation: 12) == nil)
    #expect(gate.invalidate(generation: 11) == renewal)
    #expect(gate.generation == nil)
    #expect(gate.active == nil)
    let staleFinish = gate.finish(renewal!)
    #expect(!staleFinish)
}
#endif
