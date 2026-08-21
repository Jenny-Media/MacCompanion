#if os(macOS)
import CompanionMacUI
import CompanionWire
import Testing

@Test func macPairingRendererProducesAnIntegralNonemptyImage() throws {
    let image = try MacPairingQRCodeRendererV0.image(
        encodedText: PairingQRCodeCodec.prefix + "abc_123-XYZ"
    )
    #expect(image.size.width > 0)
    #expect(image.size.height == image.size.width)
    #expect(image.representations.count == 1)

    let maximum = PairingQRCodeCodec.prefix + String(
        repeating: "a",
        count: PairingQRCodeCodec.maximumTextBytes
            - PairingQRCodeCodec.prefix.utf8.count
    )
    let maximumImage = try MacPairingQRCodeRendererV0.image(encodedText: maximum)
    #expect(maximumImage.size.width > image.size.width)
    #expect(maximumImage.size.height == maximumImage.size.width)
}

@Test func macPairingRendererRejectsUntrustedOrUnrenderableInputs() {
    #expect(throws: MacPairingQRCodeRenderErrorV0.invalidText) {
        _ = try MacPairingQRCodeRendererV0.image(encodedText: "https://example.com")
    }
    #expect(throws: MacPairingQRCodeRenderErrorV0.invalidText) {
        _ = try MacPairingQRCodeRendererV0.image(
            encodedText: PairingQRCodeCodec.prefix + "é"
        )
    }
    #expect(throws: MacPairingQRCodeRenderErrorV0.invalidScale) {
        _ = try MacPairingQRCodeRendererV0.image(
            encodedText: PairingQRCodeCodec.prefix + "abc",
            scale: 0
        )
    }
}
#endif
