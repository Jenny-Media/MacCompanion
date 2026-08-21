import Foundation

public enum DeviceDisplayNameError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case surroundingWhitespace
    case nonCanonicalUnicode
    case forbiddenScalar
}

/// A locally confirmed, presentation-only name for a paired device. It is
/// never accepted from remote protocol input and carries no authority.
public struct DeviceDisplayName: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 64
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty else { throw DeviceDisplayNameError.empty }
        guard rawValue.utf8.count <= Self.maximumUTF8Bytes else {
            throw DeviceDisplayNameError.tooLong
        }
        guard rawValue == rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) else {
            throw DeviceDisplayNameError.surroundingWhitespace
        }
        let canonical = rawValue.precomposedStringWithCanonicalMapping
        guard rawValue.utf8.elementsEqual(canonical.utf8) else {
            throw DeviceDisplayNameError.nonCanonicalUnicode
        }
        guard rawValue.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.illegalCharacters.contains(scalar)
                && !Self.directionalFormattingScalars.contains(scalar.value)
        }) else {
            throw DeviceDisplayNameError.forbiddenScalar
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let directionalFormattingScalars: Set<UInt32> = [
        0x061c, 0x200e, 0x200f,
        0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]
}
