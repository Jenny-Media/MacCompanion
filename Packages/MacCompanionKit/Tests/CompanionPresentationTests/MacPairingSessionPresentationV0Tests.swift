import CompanionDiscovery
import CompanionIPC
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let macPairingPresentationCreatedAt: Int64 = 1_787_198_400_000
private let macPairingPresentationExpiresAt: Int64 = 1_787_198_700_000

private func macPairingPresentationReceipt(
    correlationID: UUID,
    pairingID: UUID = UUID()
) throws -> LocalPairingSessionCreatedReceiptV0 {
    let payload = try PairingQRCodePayload(
        pairingID: WireUUID(pairingID),
        oneTimeSecret: WireBytes32(Data(repeating: 0x81, count: 32)),
        expiresAtUnixMilliseconds: macPairingPresentationExpiresAt,
        hostFingerprint: WireFingerprint(Data(repeating: 0x92, count: 32)),
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
        createdAtUnixMilliseconds: macPairingPresentationCreatedAt,
        expiresAtUnixMilliseconds: macPairingPresentationExpiresAt
    )
}

@Test func macPairingPresentationCompletesExactCreateAndDismissFlow() throws {
    var presentation = MacPairingSessionPresentationV0()
    let create = try presentation.begin(commandID: UUID())
    let created = try macPairingPresentationReceipt(
        correlationID: create.commandID
    )
    try presentation.receiveCreated(created)
    #expect(presentation.visibleReceipt == created)
    #expect(presentation.interactionEnabled)

    let dismiss = try presentation.requestDismissal(commandID: UUID())
    #expect(dismiss.pairingID == created.pairingID)
    #expect(!presentation.interactionEnabled)
    try presentation.receiveDismissed(
        LocalPairingSessionDismissedReceiptV0(
            correlationID: dismiss.commandID,
            pairingID: dismiss.pairingID,
            completedAtUnixMilliseconds:
                macPairingPresentationCreatedAt + 1
        )
    )
    #expect(presentation.phase == .idle)
    #expect(presentation.visibleReceipt == nil)
}

@Test func macPairingPresentationRetriesExactCreateCommandAfterLoss() throws {
    var presentation = MacPairingSessionPresentationV0()
    let first = try presentation.begin(commandID: UUID())
    try presentation.creationFailed()
    #expect(presentation.interactionEnabled)
    let retry = try presentation.retryCreation()
    #expect(retry == first)
    try presentation.receiveCreated(
        macPairingPresentationReceipt(correlationID: retry.commandID)
    )
    #expect(presentation.visibleReceipt != nil)
}

@Test func macPairingPresentationRetriesExactDismissCommandAfterLoss() throws {
    var presentation = MacPairingSessionPresentationV0()
    let create = try presentation.begin(commandID: UUID())
    try presentation.receiveCreated(
        macPairingPresentationReceipt(correlationID: create.commandID)
    )
    let first = try presentation.requestDismissal(commandID: UUID())
    try presentation.dismissalFailed()
    #expect(presentation.visibleReceipt?.pairingID == first.pairingID)
    #expect(presentation.interactionEnabled)
    #expect(try presentation.retryDismissal() == first)
}

@Test func macPairingPresentationRejectsMismatchedOrRegressedReceipts() throws {
    var presentation = MacPairingSessionPresentationV0()
    _ = try presentation.begin(commandID: UUID())
    #expect(throws: MacPairingSessionPresentationErrorV0.receiptMismatch) {
        try presentation.receiveCreated(
            macPairingPresentationReceipt(correlationID: UUID())
        )
    }

    presentation.invalidate()
    let create = try presentation.begin(commandID: UUID())
    let created = try macPairingPresentationReceipt(
        correlationID: create.commandID
    )
    try presentation.receiveCreated(created)
    let dismiss = try presentation.requestDismissal(commandID: UUID())
    #expect(throws: MacPairingSessionPresentationErrorV0.receiptMismatch) {
        try presentation.receiveDismissed(
            LocalPairingSessionDismissedReceiptV0(
                correlationID: UUID(),
                pairingID: dismiss.pairingID,
                completedAtUnixMilliseconds:
                    macPairingPresentationCreatedAt + 1
            )
        )
    }
    #expect(throws: MacPairingSessionPresentationErrorV0.completionBeforeCreation) {
        try presentation.receiveDismissed(
            LocalPairingSessionDismissedReceiptV0(
                correlationID: dismiss.commandID,
                pairingID: dismiss.pairingID,
                completedAtUnixMilliseconds:
                    macPairingPresentationCreatedAt - 1
            )
        )
    }
}

@Test func macPairingPresentationInvalidationErasesSecretFromEveryPhase() throws {
    var presentation = MacPairingSessionPresentationV0()
    let create = try presentation.begin(commandID: UUID())
    let created = try macPairingPresentationReceipt(
        correlationID: create.commandID
    )
    try presentation.receiveCreated(created)
    _ = try presentation.requestDismissal(commandID: UUID())
    try presentation.dismissalFailed()
    #expect(presentation.visibleReceipt != nil)
    presentation.invalidate()
    #expect(presentation.phase == .idle)
    #expect(presentation.visibleReceipt == nil)
}
