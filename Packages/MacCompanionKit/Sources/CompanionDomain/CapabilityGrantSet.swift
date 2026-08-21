public enum CapabilityGrantSetError: Error, Equatable, Sendable {
    case tooMany
    case duplicate(String)
    case invalidIdentifier(String)
}

public struct CapabilityGrantSet: Equatable, Sendable {
    public static let maximumCount = 256
    public let capabilityIDs: [String]

    public init(_ capabilityIDs: [String]) throws {
        guard capabilityIDs.count <= Self.maximumCount else {
            throw CapabilityGrantSetError.tooMany
        }
        var seen: Set<String> = []
        for capabilityID in capabilityIDs {
            guard Self.isIdentifier(capabilityID) else {
                throw CapabilityGrantSetError.invalidIdentifier(capabilityID)
            }
            guard seen.insert(capabilityID).inserted else {
                throw CapabilityGrantSetError.duplicate(capabilityID)
            }
        }
        self.capabilityIDs = capabilityIDs.sorted()
    }

    public var isEmpty: Bool { capabilityIDs.isEmpty }

    private static func isIdentifier(_ value: String) -> Bool {
        guard (1...96).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }
}
