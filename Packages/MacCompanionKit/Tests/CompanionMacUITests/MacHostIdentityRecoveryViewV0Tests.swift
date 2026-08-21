#if os(macOS)
import CompanionIPC
import CompanionMacUI
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let recoveryViewCreatedAtV0: Int64 = 1_787_284_800_000

private func recoveryViewReviewV0()
    throws -> LocalHostIdentityRecoveryReviewV0
{
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        hostID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        hostFingerprint: WireFingerprint(Data(repeating: 0x31, count: 32)),
        cause: .keyUnavailable,
        createdAtUnixMilliseconds: recoveryViewCreatedAtV0,
        expiresAtUnixMilliseconds: recoveryViewCreatedAtV0 + 300_000
    )
}

private func recoveryViewRecoveringPresentationV0()
    throws -> MacHostIdentityRecoveryPresentationV0
{
    var presentation = MacHostIdentityRecoveryPresentationV0()
    try presentation.present(recoveryViewReviewV0())
    _ = try presentation.confirm(
        commandID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        recoveryID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        confirmedAtUnixMilliseconds: recoveryViewCreatedAtV0 + 1
    )
    return presentation
}

@Test func recoveryViewReviewShowsIdentityEveryConsequenceAndDestructiveAction()
    throws
{
    var presentation = MacHostIdentityRecoveryPresentationV0()
    let review = try recoveryViewReviewV0()
    try presentation.present(review)
    let projection = try #require(
        MacHostIdentityRecoveryViewProjectionV0.project(presentation)
    )
    #expect(projection.hostID == review.hostID.uuidString.lowercased())
    #expect(projection.fingerprint == String(repeating: "31", count: 32))
    #expect(projection.consequences
        == MacHostIdentityRecoveryPresentationV0.requiredConsequences)
    #expect(projection.consequences.count == 5)
    #expect(projection.primaryAction == .confirmRecovery)
    #expect(projection.primaryIsDestructive)
    #expect(projection.showsCancel)
    #expect(projection.preventsImplicitDismissal)
}

@Test func recoveryViewInFlightCannotCancelOrStartAnotherAction() throws {
    let projection = try #require(
        MacHostIdentityRecoveryViewProjectionV0.project(
            recoveryViewRecoveringPresentationV0()
        )
    )
    #expect(projection.showsProgress)
    #expect(projection.primaryAction == nil)
    #expect(!projection.showsCancel)
}

@Test func recoveryViewFailureOffersOnlyExactRetry() throws {
    var presentation = try recoveryViewRecoveringPresentationV0()
    try presentation.submissionFailed()
    let projection = try #require(
        MacHostIdentityRecoveryViewProjectionV0.project(presentation)
    )
    #expect(!projection.showsProgress)
    #expect(projection.primaryAction == .retryRecovery)
    #expect(projection.primaryIsDestructive)
    #expect(!projection.showsCancel)
}

@Test func recoveryViewAuthorizationLossOffersNoMutation() throws {
    var presentation = try recoveryViewRecoveringPresentationV0()
    presentation.agentInvalidated()
    let projection = try #require(
        MacHostIdentityRecoveryViewProjectionV0.project(presentation)
    )
    #expect(projection.primaryAction == nil)
    #expect(!projection.showsCancel)
    #expect(!projection.showsProgress)
}

@Test func recoveryViewCompletionShowsNewIdentityAndRepairingAction()
    throws
{
    var presentation = try recoveryViewRecoveringPresentationV0()
    guard case let .recovering(command) = presentation.phase else {
        Issue.record("expected recovering")
        return
    }
    let newHostID = UUID(
        uuidString: "55555555-5555-4555-8555-555555555555"
    )!
    try presentation.receive(
        LocalHostIdentityRecoveredReceiptV0(
            correlationID: command.commandID,
            recoveryID: command.recoveryID,
            replacedHostID: command.review.hostID,
            newHostID: newHostID,
            newHostFingerprint: WireFingerprint(
                Data(repeating: 0x52, count: 32)
            ),
            completedAtUnixMilliseconds:
                command.confirmedAtUnixMilliseconds + 1
        )
    )
    let projection = try #require(
        MacHostIdentityRecoveryViewProjectionV0.project(presentation)
    )
    #expect(projection.hostID == newHostID.uuidString.lowercased())
    #expect(projection.fingerprint == String(repeating: "52", count: 32))
    #expect(projection.primaryAction == .done)
    #expect(!projection.primaryIsDestructive)
}

@Test func recoveryViewHasNoIdleSurface() {
    #expect(MacHostIdentityRecoveryViewProjectionV0.project(
        MacHostIdentityRecoveryPresentationV0()
    ) == nil)
}
#endif
