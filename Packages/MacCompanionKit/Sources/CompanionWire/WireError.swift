public enum WireError: Error, Equatable, Sendable {
    case invalidFrame(reason: String)
    case boundsExceeded(field: String, limit: Int)
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case unknownKind(String)
    case kindMismatch(expected: String, actual: String)
}

public enum WireLimits {
    public static let maximumFrameBytes = 65_536
    public static let maximumNestingDepth = 12
    public static let maximumObjectMembers = 64
    public static let maximumArrayItems = 128
    public static let maximumStringBytes = 4_096
    public static let maximumSafeInteger: Int64 = 9_007_199_254_740_991
}
