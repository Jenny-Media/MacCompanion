#if os(macOS)
@testable import CompanionLocalXPCPlatform
import Testing

@Test func reviewedDeviceRevocationUsesTheExistingSingleFlightGate() throws {
    var gate = MacLocalXPCMenuPairingCommandTransactionGateV1()
    let bound = gate.bind(generation: 1)
    #expect(bound)
    let denied = gate.begin(generation: 1, kind: .requestDeviceRevocationReview, permitted: false)
    #expect(denied == nil)
    let pendingReview = gate.begin(generation: 1, kind: .requestDeviceRevocationReview, permitted: true)
    let review = try #require(pendingReview)
    let concurrent = gate.begin(generation: 1, kind: .revokeDevice, permitted: true)
    #expect(concurrent == nil)
    let finished = gate.finish(review)
    #expect(finished)
    let pendingRevoke = gate.begin(generation: 1, kind: .revokeDevice, permitted: true)
    let revoke = try #require(pendingRevoke)
    let pairing = gate.begin(generation: 1, kind: .create, permitted: true)
    #expect(pairing == nil)
    let invalidated = gate.invalidate(generation: 1)
    #expect(invalidated == revoke)
    let stale = gate.finish(revoke)
    #expect(!stale)
}

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

    let recovery = gate.begin(
        generation: 7,
        kind: .recoverHostIdentity,
        permitted: true
    )
    #expect(recovery?.operation == 2)
    let finishedRecovery = gate.finish(recovery!)
    #expect(finishedRecovery)

    let acknowledgement = gate.begin(
        generation: 7,
        kind: .acknowledgeHostIdentityRecoveryCompletion,
        permitted: true
    )
    #expect(acknowledgement?.operation == 3)
    let finishedAcknowledgement = gate.finish(acknowledgement!)
    #expect(finishedAcknowledgement)

    let second = gate.begin(
        generation: 7,
        kind: .resolveDecision,
        permitted: true
    )
    #expect(second?.operation == 4)
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
