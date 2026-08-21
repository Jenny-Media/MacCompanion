public enum RevisionError: Error, Equatable, Sendable {
    case exhausted
}

public struct MonotonicRevision<Tag>: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public static var maximumWireValue: UInt64 { 9_007_199_254_740_991 }

    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public func advanced() throws -> Self {
        guard rawValue < Self.maximumWireValue else {
            throw RevisionError.exhausted
        }
        return Self(rawValue: rawValue + 1)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(UInt64.self)
        guard value <= Self.maximumWireValue else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "revision exceeds v0.1 safe-integer domain"
            )
        }
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AuthorizationEpochTag: Sendable {}
public enum GrantRevisionTag: Sendable {}
public enum PolicyRevisionTag: Sendable {}

public typealias AuthorizationEpoch = MonotonicRevision<AuthorizationEpochTag>
public typealias GrantRevision = MonotonicRevision<GrantRevisionTag>
public typealias PolicyRevision = MonotonicRevision<PolicyRevisionTag>
