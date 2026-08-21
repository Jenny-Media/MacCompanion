#if os(macOS)
import CompanionDiscovery
import CompanionIPC
import CompanionMacUI
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private func macPairingViewReceipt(
    correlationID: UUID,
    pairingID: UUID = UUID()
) throws -> LocalPairingSessionCreatedReceiptV0 {
    let createdAt: Int64 = 1_787_198_400_000
    let expiresAt: Int64 = 1_787_198_700_000
    let payload = try PairingQRCodePayload(
        pairingID: WireUUID(pairingID),
        oneTimeSecret: WireBytes32(Data(repeating: 0xa1, count: 32)),
        expiresAtUnixMilliseconds: expiresAt,
        hostFingerprint: WireFingerprint(Data(repeating: 0xb2, count: 32)),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
    return try LocalPairingSessionCreatedReceiptV0(
        correlationID: correlationID,
        pairingID: pairingID,
        encodedQRCode: PairingQRCodeCodec.encode(payload),
        createdAtUnixMilliseconds: createdAt,
        expiresAtUnixMilliseconds: expiresAt
    )
}

@Test func macPairingSheetProjectsCreationAndRetryWithoutQRCode() throws {
    var presentation = MacPairingSessionPresentationV0()
    _ = try presentation.begin(commandID: UUID())
    var projection = try #require(
        MacPairingSessionSheetProjectionV0.project(presentation.phase)
    )
    #expect(projection.showsProgress)
    #expect(!projection.showsQRCode)
    #expect(projection.action == nil)
    #expect(projection.preventsImplicitDismissal)

    try presentation.creationFailed()
    projection = try #require(
        MacPairingSessionSheetProjectionV0.project(presentation.phase)
    )
    #expect(!projection.showsProgress)
    #expect(projection.action == .retryCreation)
    #expect(projection.actionTitle == "Try Again")
}

@Test func macPairingSheetOffersOnlyExplicitCancellationForVisibleCode() throws {
    var presentation = MacPairingSessionPresentationV0()
    let create = try presentation.begin(commandID: UUID())
    try presentation.receiveCreated(
        macPairingViewReceipt(correlationID: create.commandID)
    )
    let projection = try #require(
        MacPairingSessionSheetProjectionV0.project(presentation.phase)
    )
    #expect(projection.showsQRCode)
    #expect(!projection.showsProgress)
    #expect(projection.action == .dismissPairing)
    #expect(projection.actionTitle == "Cancel Pairing")
    #expect(projection.preventsImplicitDismissal)
}

@Test func macPairingSheetKeepsCodeVisibleUntilCancellationConfirmed() throws {
    var presentation = MacPairingSessionPresentationV0()
    let create = try presentation.begin(commandID: UUID())
    try presentation.receiveCreated(
        macPairingViewReceipt(correlationID: create.commandID)
    )
    _ = try presentation.requestDismissal(commandID: UUID())
    var projection = try #require(
        MacPairingSessionSheetProjectionV0.project(presentation.phase)
    )
    #expect(projection.showsQRCode)
    #expect(projection.showsProgress)
    #expect(projection.action == nil)

    try presentation.dismissalFailed()
    projection = try #require(
        MacPairingSessionSheetProjectionV0.project(presentation.phase)
    )
    #expect(projection.showsQRCode)
    #expect(projection.action == .retryDismissal)
    #expect(projection.detail.contains("may still be active"))
    #expect(projection.preventsImplicitDismissal)
}

@Test func macPairingSheetHasNoIdleSurface() {
    let presentation = MacPairingSessionPresentationV0()
    #expect(MacPairingSessionSheetProjectionV0.project(
        presentation.phase
    ) == nil)
}
#endif
