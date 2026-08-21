import CompanionClientUI
import CompanionWire
import Testing

@Test func pairingScanFilterAdmitsOnlyBoundedASCIIProductCodes() {
    let admitted = PairingQRCodeCodec.prefix + "abc_123-XYZ"
    #expect(ClientPairingScanFilterV0.admit(admitted) == admitted)
    #expect(ClientPairingScanFilterV0.admit("https://example.com") == nil)
    #expect(ClientPairingScanFilterV0.admit(PairingQRCodeCodec.prefix + "é") == nil)
}

@Test func pairingScanFilterRejectsOversizeBeforePresentationDecoding() {
    let maximum = PairingQRCodeCodec.prefix + String(
        repeating: "a",
        count: PairingQRCodeCodec.maximumTextBytes
            - PairingQRCodeCodec.prefix.utf8.count
    )
    #expect(maximum.utf8.count == PairingQRCodeCodec.maximumTextBytes)
    #expect(ClientPairingScanFilterV0.admit(maximum) == maximum)

    let candidate = PairingQRCodeCodec.prefix + String(
        repeating: "a",
        count: PairingQRCodeCodec.maximumTextBytes
    )
    #expect(candidate.utf8.count > PairingQRCodeCodec.maximumTextBytes)
    #expect(ClientPairingScanFilterV0.admit(candidate) == nil)
}
