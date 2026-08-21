import Foundation

public protocol FixedWireByteCount: Sendable {
    static var byteCount: Int { get }
}

public enum WireBytes16Tag: FixedWireByteCount {
    public static let byteCount = 16
}

public enum WireBytes32Tag: FixedWireByteCount {
    public static let byteCount = 32
}

public enum WireBytes64Tag: FixedWireByteCount {
    public static let byteCount = 64
}

public enum WireBytes65Tag: FixedWireByteCount {
    public static let byteCount = 65
}

public struct Base64URLBytes<Tag: FixedWireByteCount>: Codable, Equatable, Sendable {
    public let rawValue: Data

    public init(_ rawValue: Data) throws {
        guard rawValue.count == Tag.byteCount else {
            throw WireError.boundsExceeded(
                field: "base64urlBytes",
                limit: Tag.byteCount
            )
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard !text.contains("="),
              text.utf8.allSatisfy({
                  ($0 >= 0x41 && $0 <= 0x5a)
                      || ($0 >= 0x61 && $0 <= 0x7a)
                      || ($0 >= 0x30 && $0 <= 0x39)
                      || $0 == 0x2d || $0 == 0x5f
              }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected unpadded base64url"
            )
        }
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        guard let data = Data(base64Encoded: base64),
              data.count == Tag.byteCount,
              Self.text(data) == text else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "non-canonical or wrong-length base64url"
            )
        }
        rawValue = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.text(rawValue))
    }

    private static func text(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public typealias WireBytes16 = Base64URLBytes<WireBytes16Tag>
public typealias WireBytes32 = Base64URLBytes<WireBytes32Tag>
public typealias WireBytes64 = Base64URLBytes<WireBytes64Tag>
public typealias WireBytes65 = Base64URLBytes<WireBytes65Tag>

public struct WireFingerprint: Codable, Equatable, Sendable {
    public let rawValue: Data

    public init(_ rawValue: Data) throws {
        guard rawValue.count == 32 else {
            throw WireError.boundsExceeded(field: "fingerprint", limit: 32)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard text.utf8.count == 64,
              text == text.lowercased(),
              text.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected lowercase 32-byte hexadecimal fingerprint"
            )
        }
        var data = Data()
        data.reserveCapacity(32)
        var index = text.startIndex
        for _ in 0..<32 {
            let next = text.index(index, offsetBy: 2)
            data.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        rawValue = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.map { String(format: "%02x", $0) }.joined())
    }
}

public struct PairingAuthenticationString: Codable, Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw WireError.invalidFrame(reason: "invalid pairing authentication string")
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard Self.isValid(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected XXX-XXX uppercase hexadecimal authentication string"
            )
        }
        rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 7
            && bytes[3] == 0x2d
            && bytes.enumerated().allSatisfy { index, byte in
                index == 3 || (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46)
            }
    }
}
