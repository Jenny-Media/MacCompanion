#if os(macOS)
import CompanionDomain
import CompanionIPC
import CompanionMacUI
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private func macPairingReviewViewReviewV0() throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(
        reviewID: UUID(),
        pairingID: UUID(),
        clientID: UUID(),
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x71, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x72, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x73, count: 32)),
        authenticationString: PairingAuthenticationString("C15-B06"),
        expectedPolicyRevision: PolicyRevision(rawValue: 7),
        expiresAtUnixMilliseconds: 1_787_198_401_000
    )
}

@Test func macPairingReviewProjectionShowsExactSASAndEmptyLocalName() throws {
    var presentation = MacPairingReviewPresentationV0()
    try presentation.receive(macPairingReviewViewReviewV0())
    let projection = try #require(
        MacPairingReviewSheetProjectionV0.project(presentation)
    )
    #expect(projection.authenticationString == "C15-B06")
    #expect(projection.deviceNameDraft.isEmpty)
    #expect(projection.draftIssue == .empty)
    #expect(projection.allowsNameEditing)
    #expect(!projection.showsProgress)
    #expect(projection.retryAction == nil)
}

@Test func macPairingReviewProjectionLocksNameDuringDecision() throws {
    var presentation = MacPairingReviewPresentationV0()
    try presentation.receive(macPairingReviewViewReviewV0())
    try presentation.updateDeviceNameDraft("Jenny's iPhone")
    _ = try presentation.approve(
        commandID: UUID(),
        decidedAtUnixMilliseconds: 1_787_198_400_100
    )
    let projection = try #require(
        MacPairingReviewSheetProjectionV0.project(presentation)
    )
    #expect(!projection.allowsNameEditing)
    #expect(projection.showsProgress)
    #expect(projection.retryAction == nil)
}

@Test func macPairingReviewProjectionOffersOnlyExactRetryAfterFailure() throws {
    var presentation = MacPairingReviewPresentationV0()
    try presentation.receive(macPairingReviewViewReviewV0())
    _ = try presentation.decline(
        commandID: UUID(),
        decidedAtUnixMilliseconds: 1_787_198_400_100
    )
    try presentation.decisionFailed()
    let projection = try #require(
        MacPairingReviewSheetProjectionV0.project(presentation)
    )
    #expect(!projection.allowsNameEditing)
    #expect(!projection.showsProgress)
    #expect(projection.retryAction == .retryDecision)
}

@Test func macPairingReviewProjectionHasNoIdleSurface() {
    #expect(MacPairingReviewSheetProjectionV0.project(
        MacPairingReviewPresentationV0()
    ) == nil)
}
#endif
