import CompanionDiscovery
import Foundation

public struct PairingQRCodePayload: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case version, pairingID, oneTimeSecret, expiresAtUnixMilliseconds, hostFingerprint, endpoints
    }

    public let version: WireVersion
    public let pairingID: WireUUID
    public let oneTimeSecret: WireBytes32
    public let expiresAtUnixMilliseconds: Int64
    public let hostFingerprint: WireFingerprint
    public let endpoints: [EndpointCandidate]

    public init(
        version: WireVersion = .init(),
        pairingID: WireUUID,
        oneTimeSecret: WireBytes32,
        expiresAtUnixMilliseconds: Int64,
        hostFingerprint: WireFingerprint,
        endpoints: [EndpointCandidate]
    ) throws {
        self.version = version
        self.pairingID = pairingID
        self.oneTimeSecret = oneTimeSecret
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.hostFingerprint = hostFingerprint
        self.endpoints = endpoints
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["version", "pairingID", "oneTimeSecret", "expiresAtUnixMilliseconds", "hostFingerprint", "endpoints"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(WireVersion.self, forKey: .version)
        pairingID = try container.decode(WireUUID.self, forKey: .pairingID)
        oneTimeSecret = try container.decode(WireBytes32.self, forKey: .oneTimeSecret)
        expiresAtUnixMilliseconds = try container.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        hostFingerprint = try container.decode(WireFingerprint.self, forKey: .hostFingerprint)
        endpoints = try container.decode([EndpointCandidate].self, forKey: .endpoints)
        try validate()
    }

    public func validate() throws {
        guard version == WireVersion() else {
            throw WireError.unsupportedVersion(major: version.major, minor: version.minor)
        }
        guard expiresAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger else {
            throw WireError.boundsExceeded(
                field: "expiresAtUnixMilliseconds",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
        guard (1...8).contains(endpoints.count), Set(endpoints).count == endpoints.count else {
            throw WireError.invalidFrame(reason: "invalid endpoint candidates")
        }
    }
}

public enum PairingQRCodeCodec {
    public static let prefix = "maccompanion://pair/v0.1/"
    public static let maximumTextBytes = 2_953

    public static func encode(_ payload: PairingQRCodePayload) throws -> String {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(payload)
        let text = prefix + base64URL(json)
        guard text.utf8.count <= maximumTextBytes else {
            throw WireError.boundsExceeded(field: "pairingQRCode", limit: maximumTextBytes)
        }
        return text
    }

    public static func decode(
        _ text: String,
        nowUnixMilliseconds: Int64
    ) throws -> PairingQRCodePayload {
        guard text.utf8.count <= maximumTextBytes,
              text.unicodeScalars.allSatisfy(\.isASCII),
              text.hasPrefix(prefix),
              nowUnixMilliseconds >= 0,
              nowUnixMilliseconds <= WireLimits.maximumSafeInteger else {
            throw WireError.invalidFrame(reason: "invalid pairing QR text")
        }
        let encoded = String(text.dropFirst(prefix.count))
        guard let json = decodeBase64URL(encoded), base64URL(json) == encoded else {
            throw WireError.invalidFrame(reason: "non-canonical pairing QR payload")
        }
        try StrictJSON.validate(json)
        let payload = try JSONDecoder().decode(PairingQRCodePayload.self, from: json)
        guard nowUnixMilliseconds < payload.expiresAtUnixMilliseconds else {
            throw WireError.invalidFrame(reason: "expired pairing QR payload")
        }
        guard try encode(payload) == text else {
            throw WireError.invalidFrame(reason: "non-canonical pairing QR JSON")
        }
        return payload
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        guard !text.isEmpty, !text.contains("="), text.utf8.allSatisfy({
            ($0 >= 0x41 && $0 <= 0x5a)
                || ($0 >= 0x61 && $0 <= 0x7a)
                || ($0 >= 0x30 && $0 <= 0x39)
                || $0 == 0x2d || $0 == 0x5f
        }) else { return nil }
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}
