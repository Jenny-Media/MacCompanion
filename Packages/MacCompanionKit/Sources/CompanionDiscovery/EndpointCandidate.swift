import Darwin
import Foundation

public enum EndpointValidationError: Error, Equatable, Sendable {
    case invalidValue
    case invalidPort
    case invalidTXTRecord
}

public enum EndpointKind: String, Codable, CaseIterable, Sendable {
    case bonjour
    case ipv4
    case ipv6
    case dns
}

public struct EndpointCandidate: Codable, Equatable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, value, port
    }

    public let kind: EndpointKind
    public let value: String
    public let port: UInt16

    public init(kind: EndpointKind, value: String, port: UInt16) throws {
        guard port > 0 else { throw EndpointValidationError.invalidPort }
        guard Self.isCanonical(kind: kind, value: value) else {
            throw EndpointValidationError.invalidValue
        }
        self.kind = kind
        self.value = value
        self.port = port
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw EndpointValidationError.invalidValue
        }
        let kind = try container.decode(EndpointKind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        let port = try container.decode(UInt16.self, forKey: .port)
        try self.init(kind: kind, value: value, port: port)
    }

    private static func isCanonical(kind: EndpointKind, value: String) -> Bool {
        guard (1...253).contains(value.utf8.count), value.unicodeScalars.allSatisfy({
            $0.isASCII && $0.value >= 0x21 && $0.value <= 0x7e
                && !"/?#".unicodeScalars.contains($0)
        }) else { return false }

        switch kind {
        case .bonjour:
            let suffix = ".\(BonjourDiscoveryProfile.serviceType).\(BonjourDiscoveryProfile.domain)"
            guard value.hasSuffix(suffix) else { return false }
            let instance = String(value.dropLast(suffix.count))
            return canonicalDNSLabel(instance)
        case .ipv4:
            return canonicalIPAddress(value, family: AF_INET)
        case .ipv6:
            return canonicalIPAddress(value, family: AF_INET6)
        case .dns:
            guard value == value.lowercased(), !value.hasSuffix(".") else { return false }
            let labels = value.split(separator: ".", omittingEmptySubsequences: false)
            return !labels.isEmpty && labels.allSatisfy { canonicalDNSLabel(String($0)) }
        }
    }

    private static func canonicalDNSLabel(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...63).contains(bytes.count), value == value.lowercased() else { return false }
        func alphanumeric(_ byte: UInt8) -> Bool {
            (byte >= 0x61 && byte <= 0x7a) || (byte >= 0x30 && byte <= 0x39)
        }
        guard let first = bytes.first, let last = bytes.last,
              alphanumeric(first), alphanumeric(last) else { return false }
        return bytes.allSatisfy { alphanumeric($0) || $0 == 0x2d }
    }

    private static func canonicalIPAddress(_ value: String, family: Int32) -> Bool {
        var storage = in6_addr()
        let parsed = value.withCString { inet_pton(family, $0, &storage) }
        guard parsed == 1 else { return false }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, &storage, &buffer, socklen_t(buffer.count)) != nil else {
            return false
        }
        let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let canonical = String(decoding: buffer[..<terminator].map {
            UInt8(bitPattern: $0)
        }, as: UTF8.self)
        return canonical == value
    }
}

public enum BonjourDiscoveryProfile {
    public static let serviceType = "_maccompanion._tcp"
    public static let domain = "local."
    public static let protocolMajorKey = "v"
    public static let hostHintKey = "h"

    public static func txtRecord(hostFingerprint: Data) throws -> [String: Data] {
        guard hostFingerprint.count == 32 else {
            throw EndpointValidationError.invalidTXTRecord
        }
        let hint = hostFingerprint.prefix(8).map { String(format: "%02x", $0) }.joined()
        return [
            protocolMajorKey: Data("0".utf8),
            hostHintKey: Data(hint.utf8),
        ]
    }

    public static func validateTXTRecord(_ record: [String: Data]) throws {
        guard Set(record.keys) == [protocolMajorKey, hostHintKey],
              record[protocolMajorKey] == Data("0".utf8),
              let hintData = record[hostHintKey],
              let hint = String(data: hintData, encoding: .ascii),
              hint.utf8.count == 16,
              hint.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }) else {
            throw EndpointValidationError.invalidTXTRecord
        }
    }
}
