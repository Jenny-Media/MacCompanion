import CompanionIPC
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let presentationRecoveryCreatedAtV0: Int64 = 1_787_284_800_000

private func presentationRecoveryReviewV0(
    reviewID: UUID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
) throws -> LocalHostIdentityRecoveryReviewV0 {
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: reviewID,
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        hostFingerprint: WireFingerprint(Data(repeating: 0x21, count: 32)),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: presentationRecoveryCreatedAtV0,
        expiresAtUnixMilliseconds: presentationRecoveryCreatedAtV0 + 300_000
    )
}

private func presentationRecoveryCommandV0() throws
    -> LocalHostIdentityRecoveryCommandV0
{
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        review: presentationRecoveryReviewV0(),
        confirmedAtUnixMilliseconds: presentationRecoveryCreatedAtV0 + 1
    )
}

@Test func macRecoveryPresentationRequiresEveryDestructiveConsequence() {
    #expect(MacHostIdentityRecoveryPresentationV0.requiredConsequences == [
        .stopRemoteAccess,
        .invalidateAllPairedPhones,
        .removeAllCapabilityGrants,
        .fenceQueuedAndActiveRemoteWork,
        .requireRepairingEveryPhone,
    ])
}

@Test func macRecoveryPresentationRetainsExactFailedCommandForRetry()
    throws
{
    let review = try presentationRecoveryReviewV0()
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.present(review)
    let command = try presentation.confirm(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        confirmedAtUnixMilliseconds: presentationRecoveryCreatedAtV0 + 1
    )
    try presentation.submissionFailed()
    #expect(presentation.exactRetryCommand == command)
    #expect(try presentation.retry() == command)

    let receipt = try LocalHostIdentityRecoveredReceiptV0(
        correlationID: command.commandID,
        recoveryID: command.recoveryID,
        replacedHostID: command.review.hostID,
        newHostID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
        newHostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    try presentation.receive(receipt)
    guard case let .completed(completedCommand, completedReceipt) =
        presentation.phase else {
        Issue.record("expected completed recovery")
        return
    }
    #expect(completedCommand == command)
    #expect(completedReceipt == receipt)
}

@Test func macRecoveryPresentationFencesSubmittedCommandAcrossAgentLoss()
    throws
{
    let review = try presentationRecoveryReviewV0()
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.present(review)
    let command = try presentation.confirm(
        commandID: UUID(),
        recoveryID: UUID(),
        confirmedAtUnixMilliseconds: presentationRecoveryCreatedAtV0 + 1
    )
    presentation.agentInvalidated()
    #expect(presentation.exactRetryCommand == command)
    #expect(!presentation.interactionEnabled)
    #expect(throws: MacHostIdentityRecoveryPresentationErrorV0
        .reviewMismatch) {
        try presentation.present(
            presentationRecoveryReviewV0(reviewID: UUID())
        )
    }
    try presentation.present(review)
    #expect(presentation.interactionEnabled)
    #expect(try presentation.retry() == command)
}

@Test func macRecoveryPresentationRejectsMismatchedReceiptWithoutSuccess()
    throws
{
    let review = try presentationRecoveryReviewV0()
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.present(review)
    let command = try presentation.confirm(
        commandID: UUID(),
        recoveryID: UUID(),
        confirmedAtUnixMilliseconds: presentationRecoveryCreatedAtV0 + 1
    )
    let mismatched = try LocalHostIdentityRecoveredReceiptV0(
        correlationID: UUID(),
        recoveryID: command.recoveryID,
        replacedHostID: command.review.hostID,
        newHostID: UUID(),
        newHostFingerprint: WireFingerprint(Data(repeating: 0x52, count: 32)),
        completedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1
    )
    #expect(throws: MacHostIdentityRecoveryPresentationErrorV0
        .receiptMismatch) {
        try presentation.receive(mismatched)
    }
    #expect({
        if case .recovering = presentation.phase { true } else { false }
    }())
}

@Test func macRecoveryPresentationDiscardsUnsubmittedReviewOnAgentLoss()
    throws
{
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.present(presentationRecoveryReviewV0())
    presentation.agentInvalidated()
    #expect(presentation.phase == .idle)
}

@Test func macRecoveryPresentationAdoptsOnlyExactDurableResumeCommand()
    throws
{
    let command = try presentationRecoveryCommandV0()
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.resume(command)
    #expect(presentation.exactRetryCommand == command)

    let changed = try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(),
        recoveryID: command.recoveryID,
        review: command.review,
        confirmedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds
    )
    #expect(throws: MacHostIdentityRecoveryPresentationErrorV0
        .reviewMismatch) {
        try presentation.resume(changed)
    }
    #expect(presentation.exactRetryCommand == command)
}
