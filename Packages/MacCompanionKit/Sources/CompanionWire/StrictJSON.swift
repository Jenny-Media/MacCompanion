import Foundation

public enum StrictJSON {
    public static func validate(_ data: Data) throws {
        guard !data.isEmpty else {
            throw WireError.invalidFrame(reason: "empty JSON payload")
        }
        guard data.count <= WireLimits.maximumFrameBytes else {
            throw WireError.boundsExceeded(
                field: "frame",
                limit: WireLimits.maximumFrameBytes
            )
        }

        var parser = Parser(bytes: Array(data))
        try parser.parseRootObject()
    }
}

public struct CanonicalJSONMember: Equatable, Sendable {
    public let key: String
    public let value: CanonicalJSONValue

    public init(key: String, value: CanonicalJSONValue) {
        self.key = key
        self.value = value
    }
}

public indirect enum CanonicalJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case string(String)
    case array([CanonicalJSONValue])
    case object([CanonicalJSONMember])

    public init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [CanonicalJSONValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(CanonicalJSONValue.self))
            }
            self = .array(values)
            return
        }
        if let object = try? decoder.container(keyedBy: DynamicJSONKey.self) {
            self = .object(try object.allKeys.map { key in
                try CanonicalJSONMember(
                    key: key.stringValue,
                    value: object.decode(CanonicalJSONValue.self, forKey: key)
                )
            })
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let value = try? single.decode(Bool.self) {
            self = .boolean(value); return
        }
        if let value = try? single.decode(Int64.self),
           (-WireLimits.maximumSafeInteger...WireLimits.maximumSafeInteger).contains(value) {
            self = .integer(value); return
        }
        if let value = try? single.decode(String.self) {
            self = .string(value); return
        }
        throw DecodingError.dataCorruptedError(
            in: single,
            debugDescription: "unsupported canonical JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .boolean(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .array(values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case let .object(members):
            var container = encoder.container(keyedBy: DynamicJSONKey.self)
            for member in members {
                try container.encode(
                    member.value,
                    forKey: DynamicJSONKey(member.key)
                )
            }
        }
    }
}

private struct DynamicJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

public enum CanonicalJSON {
    public static func validate(_ value: CanonicalJSONValue) throws {
        try validate(value, depth: 1)
        let encoded = canonicalData(for: value)
        guard encoded.count <= WireLimits.maximumFrameBytes else {
            throw WireError.boundsExceeded(
                field: "canonicalJSONBytes",
                limit: WireLimits.maximumFrameBytes
            )
        }
    }

    public static func parse(_ data: Data) throws -> CanonicalJSONValue {
        guard !data.isEmpty else {
            throw WireError.invalidFrame(reason: "empty JSON payload")
        }
        guard data.count <= WireLimits.maximumFrameBytes else {
            throw WireError.boundsExceeded(
                field: "frame",
                limit: WireLimits.maximumFrameBytes
            )
        }
        var parser = Parser(bytes: Array(data))
        return try parser.parseAnyRoot()
    }

    public static func canonicalize(_ data: Data) throws -> Data {
        canonicalData(for: try parse(data))
    }

    public static func canonicalData(for value: CanonicalJSONValue) -> Data {
        var output = ""
        serialize(value, into: &output)
        return Data(output.utf8)
    }

    private static func validate(
        _ value: CanonicalJSONValue,
        depth: Int
    ) throws {
        switch value {
        case .null, .boolean:
            return
        case let .integer(value):
            guard (-WireLimits.maximumSafeInteger...WireLimits.maximumSafeInteger)
                .contains(value) else {
                throw WireError.boundsExceeded(
                    field: "integer",
                    limit: Int(WireLimits.maximumSafeInteger)
                )
            }
        case let .string(value):
            guard value.utf8.count <= WireLimits.maximumStringBytes else {
                throw WireError.boundsExceeded(
                    field: "stringBytes",
                    limit: WireLimits.maximumStringBytes
                )
            }
        case let .array(values):
            try validateContainerDepth(depth)
            guard values.count <= WireLimits.maximumArrayItems else {
                throw WireError.boundsExceeded(
                    field: "arrayItems",
                    limit: WireLimits.maximumArrayItems
                )
            }
            for value in values {
                try validate(value, depth: depth + 1)
            }
        case let .object(members):
            try validateContainerDepth(depth)
            guard members.count <= WireLimits.maximumObjectMembers else {
                throw WireError.boundsExceeded(
                    field: "objectMembers",
                    limit: WireLimits.maximumObjectMembers
                )
            }
            var keys = Set<[UInt32]>()
            for member in members {
                guard member.key.utf8.count <= WireLimits.maximumStringBytes else {
                    throw WireError.boundsExceeded(
                        field: "stringBytes",
                        limit: WireLimits.maximumStringBytes
                    )
                }
                guard keys.insert(member.key.unicodeScalars.map(\.value)).inserted else {
                    throw WireError.invalidFrame(reason: "duplicate JSON key: \(member.key)")
                }
                try validate(member.value, depth: depth + 1)
            }
        }
    }

    private static func validateContainerDepth(_ depth: Int) throws {
        guard depth <= WireLimits.maximumNestingDepth else {
            throw WireError.boundsExceeded(
                field: "nestingDepth",
                limit: WireLimits.maximumNestingDepth
            )
        }
    }

    private static func serialize(
        _ value: CanonicalJSONValue,
        into output: inout String
    ) {
        switch value {
        case .null:
            output += "null"
        case let .boolean(value):
            output += value ? "true" : "false"
        case let .integer(value):
            output += String(value)
        case let .string(value):
            appendJSONString(value, into: &output)
        case let .array(values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                serialize(value, into: &output)
            }
            output += "]"
        case let .object(members):
            output += "{"
            let sortedMembers = members.sorted {
                utf16Precedes($0.key, $1.key)
            }
            for (index, member) in sortedMembers.enumerated() {
                if index > 0 { output += "," }
                appendJSONString(member.key, into: &output)
                output += ":"
                serialize(member.value, into: &output)
            }
            output += "}"
        }
    }

    private static func appendJSONString(
        _ value: String,
        into output: inout String
    ) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0A: output += "\\n"
            case 0x0C: output += "\\f"
            case 0x0D: output += "\\r"
            case 0x00...0x1F:
                output += String(format: "\\u%04x", scalar.value)
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            default: output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }

    private static func utf16Precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func parseRootObject() throws {
        skipWhitespace()
        guard peek == UInt8(ascii: "{") else {
            throw WireError.invalidFrame(reason: "JSON root must be an object")
        }
        _ = try parseObject(depth: 1)
        skipWhitespace()
        guard index == bytes.count else {
            throw WireError.invalidFrame(reason: "trailing JSON bytes")
        }
    }

    mutating func parseAnyRoot() throws -> CanonicalJSONValue {
        let value = try parseValue(depth: 1)
        skipWhitespace()
        guard index == bytes.count else {
            throw WireError.invalidFrame(reason: "trailing JSON bytes")
        }
        return value
    }

    mutating func parseValue(depth: Int) throws -> CanonicalJSONValue {
        skipWhitespace()
        guard let byte = peek else {
            throw WireError.invalidFrame(reason: "truncated JSON value")
        }

        switch byte {
        case UInt8(ascii: "{"):
            return try parseObject(depth: depth)
        case UInt8(ascii: "["):
            return try parseArray(depth: depth)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try consumeLiteral("true")
            return .boolean(true)
        case UInt8(ascii: "f"):
            try consumeLiteral("false")
            return .boolean(false)
        case UInt8(ascii: "n"):
            try consumeLiteral("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .integer(try parseInteger())
        default:
            throw WireError.invalidFrame(reason: "invalid JSON token")
        }
    }

    mutating func parseObject(depth: Int) throws -> CanonicalJSONValue {
        try checkDepth(depth)
        try consume(UInt8(ascii: "{"))
        skipWhitespace()
        if consumeIf(UInt8(ascii: "}")) { return .object([]) }

        var keys = Set<[UInt32]>()
        var members: [CanonicalJSONMember] = []
        var memberCount = 0
        while true {
            skipWhitespace()
            let key = try parseString()
            let exactKey = key.unicodeScalars.map(\.value)
            guard keys.insert(exactKey).inserted else {
                throw WireError.invalidFrame(reason: "duplicate JSON key: \(key)")
            }

            memberCount += 1
            guard memberCount <= WireLimits.maximumObjectMembers else {
                throw WireError.boundsExceeded(
                    field: "objectMembers",
                    limit: WireLimits.maximumObjectMembers
                )
            }

            skipWhitespace()
            try consume(UInt8(ascii: ":"))
            members.append(CanonicalJSONMember(
                key: key,
                value: try parseValue(depth: depth + 1)
            ))
            skipWhitespace()

            if consumeIf(UInt8(ascii: "}")) { return .object(members) }
            try consume(UInt8(ascii: ","))
        }
    }

    mutating func parseArray(depth: Int) throws -> CanonicalJSONValue {
        try checkDepth(depth)
        try consume(UInt8(ascii: "["))
        skipWhitespace()
        if consumeIf(UInt8(ascii: "]")) { return .array([]) }

        var itemCount = 0
        var values: [CanonicalJSONValue] = []
        while true {
            itemCount += 1
            guard itemCount <= WireLimits.maximumArrayItems else {
                throw WireError.boundsExceeded(
                    field: "arrayItems",
                    limit: WireLimits.maximumArrayItems
                )
            }

            values.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if consumeIf(UInt8(ascii: "]")) { return .array(values) }
            try consume(UInt8(ascii: ","))
        }
    }

    mutating func parseString() throws -> String {
        try consume(UInt8(ascii: "\""))
        var result = ""
        var segmentStart = index

        while let byte = peek {
            if byte == UInt8(ascii: "\"") {
                try appendUTF8Segment(from: segmentStart, to: index, into: &result)
                index += 1
                try checkStringBound(result)
                return result
            }

            if byte == UInt8(ascii: "\\") {
                try appendUTF8Segment(from: segmentStart, to: index, into: &result)
                index += 1
                guard let escaped = peek else {
                    throw WireError.invalidFrame(reason: "truncated JSON escape")
                }
                index += 1

                switch escaped {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
                    result.unicodeScalars.append(UnicodeScalar(escaped))
                case UInt8(ascii: "b"):
                    result.append("\u{0008}")
                case UInt8(ascii: "f"):
                    result.append("\u{000C}")
                case UInt8(ascii: "n"):
                    result.append("\n")
                case UInt8(ascii: "r"):
                    result.append("\r")
                case UInt8(ascii: "t"):
                    result.append("\t")
                case UInt8(ascii: "u"):
                    try appendUnicodeEscape(into: &result)
                default:
                    throw WireError.invalidFrame(reason: "invalid JSON escape")
                }
                segmentStart = index
                continue
            }

            guard byte >= 0x20 else {
                throw WireError.invalidFrame(reason: "unescaped control in JSON string")
            }
            index += 1
        }

        throw WireError.invalidFrame(reason: "unterminated JSON string")
    }

    mutating func appendUnicodeEscape(into result: inout String) throws {
        let first = try parseHexQuad()
        let scalarValue: UInt32

        if (0xD800...0xDBFF).contains(first) {
            guard consumeIf(UInt8(ascii: "\\")), consumeIf(UInt8(ascii: "u")) else {
                throw WireError.invalidFrame(reason: "missing low surrogate")
            }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw WireError.invalidFrame(reason: "invalid low surrogate")
            }
            scalarValue = 0x10000
                + (UInt32(first - 0xD800) << 10)
                + UInt32(second - 0xDC00)
        } else {
            guard !(0xDC00...0xDFFF).contains(first) else {
                throw WireError.invalidFrame(reason: "unpaired low surrogate")
            }
            scalarValue = UInt32(first)
        }

        guard let scalar = UnicodeScalar(scalarValue) else {
            throw WireError.invalidFrame(reason: "invalid Unicode scalar")
        }
        result.unicodeScalars.append(scalar)
    }

    mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = peek, let nibble = hexNibble(byte) else {
                throw WireError.invalidFrame(reason: "invalid Unicode escape")
            }
            index += 1
            value = (value << 4) | UInt16(nibble)
        }
        return value
    }

    mutating func parseInteger() throws -> Int64 {
        let start = index
        _ = consumeIf(UInt8(ascii: "-"))

        guard let first = peek else {
            throw WireError.invalidFrame(reason: "truncated JSON number")
        }
        if first == UInt8(ascii: "0") {
            index += 1
            if let next = peek, next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") {
                throw WireError.invalidFrame(reason: "leading zero in JSON number")
            }
        } else if first >= UInt8(ascii: "1"), first <= UInt8(ascii: "9") {
            repeat { index += 1 } while peek.map {
                $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")
            } == true
        } else {
            throw WireError.invalidFrame(reason: "invalid JSON number")
        }

        if let next = peek, next == UInt8(ascii: ".") || next == UInt8(ascii: "e") || next == UInt8(ascii: "E") {
            throw WireError.invalidFrame(reason: "floating-point JSON is not allowed")
        }

        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let value = Int64(text),
              value >= -WireLimits.maximumSafeInteger,
              value <= WireLimits.maximumSafeInteger else {
            throw WireError.boundsExceeded(
                field: "integer",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
        return value
    }

    mutating func consumeLiteral(_ literal: StaticString) throws {
        for expected in "\(literal)".utf8 {
            try consume(expected)
        }
    }

    mutating func appendUTF8Segment(
        from start: Int,
        to end: Int,
        into result: inout String
    ) throws {
        guard start < end else { return }
        guard let segment = String(bytes: bytes[start..<end], encoding: .utf8) else {
            throw WireError.invalidFrame(reason: "invalid UTF-8 in JSON string")
        }
        result.append(segment)
    }

    func checkDepth(_ depth: Int) throws {
        guard depth <= WireLimits.maximumNestingDepth else {
            throw WireError.boundsExceeded(
                field: "nestingDepth",
                limit: WireLimits.maximumNestingDepth
            )
        }
    }

    func checkStringBound(_ value: String) throws {
        guard value.utf8.count <= WireLimits.maximumStringBytes else {
            throw WireError.boundsExceeded(
                field: "stringBytes",
                limit: WireLimits.maximumStringBytes
            )
        }
    }

    mutating func consume(_ expected: UInt8) throws {
        guard consumeIf(expected) else {
            throw WireError.invalidFrame(reason: "unexpected JSON byte")
        }
    }

    mutating func consumeIf(_ expected: UInt8) -> Bool {
        guard peek == expected else { return false }
        index += 1
        return true
    }

    mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
