import CompanionWire

public enum ClientPairingScanFilterV0 {
    /// Performs only the content-free checks needed before handing an untrusted
    /// camera result to `PairingClientPresentation`. It intentionally does not
    /// decode, display, persist, or log the one-time secret.
    public static func admit(_ candidate: String) -> String? {
        guard candidate.utf8.count <= PairingQRCodeCodec.maximumTextBytes,
              candidate.unicodeScalars.allSatisfy(\.isASCII),
              candidate.hasPrefix(PairingQRCodeCodec.prefix) else {
            return nil
        }
        return candidate
    }
}
