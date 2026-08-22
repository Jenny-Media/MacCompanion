@testable import CompanionLocalXPCPlatform
import CompanionIPC
import Foundation
import Testing

private let transactionCreatedAtV1: Int64 = 1_787_198_400_000

private func transactionOfferV1(
    id: String = "018f7300-0000-7000-8000-000000000001",
    revision: Int64 = 4
) throws -> LocalRemoteAccessBootstrapOfferV0 {
    try LocalRemoteAccessBootstrapOfferV0(
        offerID: UUID(uuidString: id)!,
        expectedIntentRevision: revision,
        createdAtUnixMilliseconds: transactionCreatedAtV1,
        expiresAtUnixMilliseconds: transactionCreatedAtV1 + 300_000
    )
}

private func transactionCommandV1(
    offer: LocalRemoteAccessBootstrapOfferV0,
    id: String = "018f7300-0000-7000-8000-000000000002"
) throws -> LocalRemoteAccessEnableCommandV0 {
    try LocalRemoteAccessEnableCommandV0(
        commandID: UUID(uuidString: id)!,
        offer: offer,
        confirmedAtUnixMilliseconds: transactionCreatedAtV1 + 1
    )
}

private func transactionReceiptV1(
    command: LocalRemoteAccessEnableCommandV0
) throws -> LocalRemoteAccessEnabledReceiptV0 {
    try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: command.offer.offerID,
        intentRevision: command.offer.expectedIntentRevision + 1,
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
}

@Test
func bootstrapTransactionRequiresOneOrderedAuthorizedExchange() throws {
    var gate = MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
    let bound = gate.bind(generation: 7)
    #expect(bound)
    let deniedRead = gate.beginOfferRead(
        generation: 7,
        permitted: false
    )
    #expect(deniedRead == nil)

    let readCandidate = gate.beginOfferRead(
        generation: 7,
        permitted: true
    )
    let read = try #require(readCandidate)
    let concurrentRead = gate.beginOfferRead(
        generation: 7,
        permitted: true
    )
    #expect(concurrentRead == nil)

    let offer = try transactionOfferV1()
    let finishedRead = gate.finishOfferRead(
        generation: 7,
        operation: read,
        offer: offer
    )
    #expect(finishedRead)
    #expect(gate.currentOffer == offer)
    let repeatedRead = gate.beginOfferRead(
        generation: 7,
        permitted: true
    )
    #expect(repeatedRead == nil)

    let command = try transactionCommandV1(offer: offer)
    let enableCandidate = gate.beginEnable(
        generation: 7,
        permitted: true,
        command: command
    )
    let enable = try #require(enableCandidate)
    let concurrentEnable = gate.beginEnable(
        generation: 7,
        permitted: true,
        command: command
    )
    #expect(concurrentEnable == nil)

    let receipt = try transactionReceiptV1(command: command)
    let finishedEnable = gate.finishEnable(
        generation: 7,
        operation: enable,
        receipt: receipt
    )
    #expect(finishedEnable)
    #expect(gate.enabledReceipt == receipt)
    let postSuccessRead = gate.beginOfferRead(
        generation: 7,
        permitted: true
    )
    #expect(postSuccessRead == nil)
    let postSuccessEnable = gate.beginEnable(
        generation: 7,
        permitted: true,
        command: command
    )
    #expect(postSuccessEnable == nil)
}

@Test
func bootstrapTransactionRejectsSubstitutedOffer() throws {
    var gate = MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
    let bound = gate.bind(generation: 8)
    #expect(bound)
    let readCandidate = gate.beginOfferRead(
        generation: 8,
        permitted: true
    )
    let read = try #require(readCandidate)
    let offer = try transactionOfferV1()
    let finishedRead = gate.finishOfferRead(
        generation: 8,
        operation: read,
        offer: offer
    )
    #expect(finishedRead)

    let substituted = try transactionOfferV1(
        id: "018f7300-0000-7000-8000-000000000003"
    )
    let command = try transactionCommandV1(offer: substituted)
    let substitutedEnable = gate.beginEnable(
        generation: 8,
        permitted: true,
        command: command
    )
    #expect(substitutedEnable == nil)
    #expect(gate.currentOffer == offer)
}

@Test
func bootstrapTransactionFencesTimeoutAndReplacementCallbacks() throws {
    var gate = MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
    let boundOld = gate.bind(generation: 9)
    #expect(boundOld)
    let oldReadCandidate = gate.beginOfferRead(
        generation: 9,
        permitted: true
    )
    let oldRead = try #require(oldReadCandidate)
    let failedOld = gate.fail(generation: 9, operation: oldRead)
    #expect(failedOld)

    let boundReplacement = gate.bind(generation: 10)
    #expect(boundReplacement)
    let replacementReadCandidate = gate.beginOfferRead(
        generation: 10,
        permitted: true
    )
    let replacementRead = try #require(replacementReadCandidate)
    let offer = try transactionOfferV1()
    let staleCompletion = gate.finishOfferRead(
        generation: 9,
        operation: oldRead,
        offer: offer
    )
    #expect(!staleCompletion)
    let staleFailure = gate.fail(generation: 9, operation: oldRead)
    #expect(!staleFailure)
    let replacementCompletion = gate.finishOfferRead(
        generation: 10,
        operation: replacementRead,
        offer: offer
    )
    #expect(replacementCompletion)
}

@Test
func bootstrapTransactionInvalidatesExactMalformedReceiptOnly() throws {
    var gate = MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
    let bound = gate.bind(generation: 11)
    #expect(bound)
    let readCandidate = gate.beginOfferRead(
        generation: 11,
        permitted: true
    )
    let read = try #require(readCandidate)
    let offer = try transactionOfferV1()
    let finishedRead = gate.finishOfferRead(
        generation: 11,
        operation: read,
        offer: offer
    )
    #expect(finishedRead)
    let command = try transactionCommandV1(offer: offer)
    let enableCandidate = gate.beginEnable(
        generation: 11,
        permitted: true,
        command: command
    )
    let enable = try #require(enableCandidate)
    let wrongCommand = try transactionCommandV1(
        offer: offer,
        id: "018f7300-0000-7000-8000-000000000004"
    )
    let malformed = try transactionReceiptV1(command: wrongCommand)
    let malformedCompletion = gate.finishEnable(
        generation: 11,
        operation: enable,
        receipt: malformed
    )
    #expect(!malformedCompletion)
    #expect(gate.currentGeneration == nil)
    #expect(gate.enabledReceipt == nil)

    let boundReplacement = gate.bind(generation: 12)
    #expect(boundReplacement)
    let staleInvalidation = gate.invalidate(generation: 11)
    #expect(!staleInvalidation)
    #expect(gate.currentGeneration == 12)
}

@Test
@available(macOS 26.0, *)
func bootstrapClientHasAClosedOneUseEventAndDeadlineSurface() throws {
    let offer = try transactionOfferV1()
    let command = try transactionCommandV1(offer: offer)
    let receipt = try transactionReceiptV1(command: command)

    #expect(
        MacLocalXPCRemoteAccessBootstrapClientV1
            .handshakeTimeoutSeconds == 10
    )
    #expect(
        MacLocalXPCRemoteAccessBootstrapClientV1
            .operationTimeoutSeconds == 6
    )
    #expect(
        MacLocalXPCRemoteAccessBootstrapClientEventV1.offer(
            generation: 2,
            offer: offer
        ) != .enabled(generation: 2, receipt: receipt)
    )

    let client = MacLocalXPCRemoteAccessBootstrapClientV1 { _ in }
    client.cancel()
}
