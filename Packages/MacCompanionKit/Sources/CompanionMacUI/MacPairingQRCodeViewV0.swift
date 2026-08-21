#if os(macOS)
import AppKit
import CompanionWire
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

public enum MacPairingQRCodeRenderErrorV0: Error, Equatable, Sendable {
    case invalidText
    case invalidScale
    case generationFailed
}

public enum MacPairingQRCodeRendererV0 {
    public static func image(
        encodedText: String,
        scale: Int = 8
    ) throws -> NSImage {
        guard encodedText.utf8.count <= PairingQRCodeCodec.maximumTextBytes,
              encodedText.unicodeScalars.allSatisfy(\.isASCII),
              encodedText.hasPrefix(PairingQRCodeCodec.prefix) else {
            throw MacPairingQRCodeRenderErrorV0.invalidText
        }
        guard (1...32).contains(scale) else {
            throw MacPairingQRCodeRenderErrorV0.invalidScale
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encodedText.utf8)
        // L is the only level whose byte-mode capacity reaches the protocol's
        // bounded 2,953-byte maximum. The phone still cryptographically
        // validates the canonical payload after scanning.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else {
            throw MacPairingQRCodeRenderErrorV0.generationFailed
        }
        let scaled = output.transformed(by: CGAffineTransform(
            scaleX: CGFloat(scale),
            y: CGFloat(scale)
        ))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

@available(macOS 14.0, *)
public struct MacPairingQRCodeViewV0: View {
    private let image: NSImage

    public init(encodedText: String) throws {
        image = try MacPairingQRCodeRendererV0.image(encodedText: encodedText)
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Scan with Mac Companion")
                .font(.title2.weight(.semibold))
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 240, minHeight: 240)
                .accessibilityLabel("Temporary pairing code")
            Text("This code expires and can be used only once.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
#endif
