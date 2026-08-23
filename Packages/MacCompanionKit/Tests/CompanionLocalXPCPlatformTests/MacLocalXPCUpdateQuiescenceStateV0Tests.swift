#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

@Test func updateQuiescenceGateIsGenerationBoundSingleFlightAndOrdered()
    throws
{
    var gate = MacLocalXPCUpdateQuiescenceTransactionGateV0()
    let boundZero = gate.bind(generation: 0)
    #expect(!boundZero)
    let bound = gate.bind(generation: 7)
    #expect(bound)
    let rebound = gate.bind(generation: 8)
    #expect(!rebound)

    let closeCandidate = gate.begin(
        generation: 7,
        command: .closeNetworkAdmission,
        permitted: true
    )
    let close = try #require(closeCandidate)
    #expect(gate.admits(close))
    let concurrent = gate.begin(
        generation: 7,
        command: .drainNetworkConnections,
        permitted: true
    )
    #expect(concurrent == nil)
    let staleFinish = gate.finish(.init(
        generation: 7,
        operation: close.operation + 1,
        command: .closeNetworkAdmission
    ))
    #expect(!staleFinish)
    let closeFinished = gate.finish(close)
    #expect(closeFinished)

    let drainCandidate = gate.begin(
        generation: 7,
        command: .drainNetworkConnections,
        permitted: true
    )
    let drain = try #require(drainCandidate)
    #expect(drain.operation == close.operation + 1)
    let staleInvalidation = gate.invalidate(generation: 8)
    #expect(staleInvalidation == nil)
    let invalidated = gate.invalidate(generation: 7)
    #expect(invalidated == drain)
    #expect(!gate.admits(drain))
    let afterInvalidation = gate.begin(
        generation: 7,
        command: .reopenNetworkAdmission,
        permitted: true
    )
    #expect(afterInvalidation == nil)
}

@Test func updateQuiescenceGateRejectsDeniedAndWrongGenerationCommands() {
    var gate = MacLocalXPCUpdateQuiescenceTransactionGateV0()
    let bound = gate.bind(generation: 11)
    #expect(bound)
    let wrongGeneration = gate.begin(
        generation: 10,
        command: .closeNetworkAdmission,
        permitted: true
    )
    #expect(wrongGeneration == nil)
    let denied = gate.begin(
        generation: 11,
        command: .closeNetworkAdmission,
        permitted: false
    )
    #expect(denied == nil)
}
#endif
