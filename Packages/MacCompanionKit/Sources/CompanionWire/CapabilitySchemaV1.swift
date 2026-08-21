import Foundation

public enum CapabilitySchemaError: Error, Equatable, Sendable {
    case invalidDefinition(field: String)
    case typeMismatch(path: String)
    case missingRequired(path: String)
    case unknownProperty(path: String)
    case constraintViolation(path: String)
}

public struct CapabilitySchemaPropertyV1: Equatable, Sendable {
    public let name: String
    public let required: Bool
    public let schema: CapabilitySchemaV1

    public init(
        name: String,
        required: Bool,
        schema: CapabilitySchemaV1
    ) throws {
        guard CapabilitySchemaV1.isPropertyName(name) else {
            throw CapabilitySchemaError.invalidDefinition(field: "property.name")
        }
        self.name = name
        self.required = required
        self.schema = schema
    }
}

/// Closed, presentation-safe view of a capability schema. It exposes the
/// registered constraints without exposing mutable implementation state.
public indirect enum CapabilitySchemaNodeV1: Equatable, Sendable {
    case boolean
    case integer(minimum: Int64, maximum: Int64)
    case string(maximumUTF8Bytes: Int, allowedValues: [String]?)
    case array(maximumItems: Int, item: CapabilitySchemaV1)
    case object(properties: [CapabilitySchemaPropertyV1])
}

public struct CapabilitySchemaV1: Equatable, Sendable {
    private indirect enum Node: Equatable, Sendable {
        case boolean
        case integer(minimum: Int64, maximum: Int64)
        case string(maximumUTF8Bytes: Int, allowedValues: [String]?)
        case array(maximumItems: Int, item: CapabilitySchemaV1)
        case object(properties: [CapabilitySchemaPropertyV1])
    }

    private let node: Node

    private init(node: Node) {
        self.node = node
    }

    public var isObject: Bool {
        if case .object = node { return true }
        return false
    }

    public var presentationNode: CapabilitySchemaNodeV1 {
        switch node {
        case .boolean:
            .boolean
        case let .integer(minimum, maximum):
            .integer(minimum: minimum, maximum: maximum)
        case let .string(maximumUTF8Bytes, allowedValues):
            .string(
                maximumUTF8Bytes: maximumUTF8Bytes,
                allowedValues: allowedValues
            )
        case let .array(maximumItems, item):
            .array(maximumItems: maximumItems, item: item)
        case let .object(properties):
            .object(properties: properties)
        }
    }

    public static func boolean() -> Self {
        Self(node: .boolean)
    }

    public static func integer(
        minimum: Int64,
        maximum: Int64
    ) throws -> Self {
        guard minimum >= -WireLimits.maximumSafeInteger,
              maximum <= WireLimits.maximumSafeInteger,
              minimum <= maximum else {
            throw CapabilitySchemaError.invalidDefinition(field: "integer.range")
        }
        return Self(node: .integer(minimum: minimum, maximum: maximum))
    }

    public static func string(
        maximumUTF8Bytes: Int,
        allowedValues: [String]? = nil
    ) throws -> Self {
        guard (1...WireLimits.maximumStringBytes).contains(maximumUTF8Bytes) else {
            throw CapabilitySchemaError.invalidDefinition(field: "string.maximumUTF8Bytes")
        }
        if let allowedValues {
            guard (1...32).contains(allowedValues.count) else {
                throw CapabilitySchemaError.invalidDefinition(field: "string.allowedValues")
            }
            var exactValues = Set<[UInt32]>()
            for value in allowedValues {
                guard value.utf8.count <= maximumUTF8Bytes,
                      exactValues.insert(Self.exactScalars(value)).inserted else {
                    throw CapabilitySchemaError.invalidDefinition(field: "string.allowedValues")
                }
            }
        }
        return Self(node: .string(
            maximumUTF8Bytes: maximumUTF8Bytes,
            allowedValues: allowedValues
        ))
    }

    public static func array(
        maximumItems: Int,
        item: Self
    ) throws -> Self {
        guard (1...WireLimits.maximumArrayItems).contains(maximumItems) else {
            throw CapabilitySchemaError.invalidDefinition(field: "array.maximumItems")
        }
        return Self(node: .array(maximumItems: maximumItems, item: item))
    }

    public static func object(
        properties: [CapabilitySchemaPropertyV1]
    ) throws -> Self {
        guard properties.count <= 32 else {
            throw CapabilitySchemaError.invalidDefinition(field: "object.properties")
        }
        var exactNames = Set<[UInt32]>()
        for property in properties {
            guard exactNames.insert(exactScalars(property.name)).inserted else {
                throw CapabilitySchemaError.invalidDefinition(field: "object.properties")
            }
        }
        return Self(node: .object(properties: properties))
    }

    public func validate(
        _ value: CanonicalJSONValue,
        path: String = "$"
    ) throws {
        switch (node, value) {
        case (.boolean, .boolean):
            return
        case let (.integer(minimum, maximum), .integer(value)):
            guard (minimum...maximum).contains(value) else {
                throw CapabilitySchemaError.constraintViolation(path: path)
            }
        case let (.string(maximumUTF8Bytes, allowedValues), .string(value)):
            guard value.utf8.count <= maximumUTF8Bytes else {
                throw CapabilitySchemaError.constraintViolation(path: path)
            }
            if let allowedValues,
               !allowedValues.contains(where: { Self.exactlyEqual($0, value) }) {
                throw CapabilitySchemaError.constraintViolation(path: path)
            }
        case let (.array(maximumItems, item), .array(values)):
            guard values.count <= maximumItems else {
                throw CapabilitySchemaError.constraintViolation(path: path)
            }
            for (index, value) in values.enumerated() {
                try item.validate(value, path: "\(path)[\(index)]")
            }
        case let (.object(properties), .object(members)):
            for member in members {
                guard let property = properties.first(where: {
                    Self.exactlyEqual($0.name, member.key)
                }) else {
                    throw CapabilitySchemaError.unknownProperty(
                        path: "\(path).\(member.key)"
                    )
                }
                try property.schema.validate(
                    member.value,
                    path: "\(path).\(property.name)"
                )
            }
            for property in properties where property.required {
                guard members.contains(where: {
                    Self.exactlyEqual($0.key, property.name)
                }) else {
                    throw CapabilitySchemaError.missingRequired(
                        path: "\(path).\(property.name)"
                    )
                }
            }
        default:
            throw CapabilitySchemaError.typeMismatch(path: path)
        }
    }

    public func wireValue() throws -> CanonicalJSONValue {
        let value: CanonicalJSONValue
        switch node {
        case .boolean:
            value = .object([
                .init(key: "type", value: .string("boolean")),
            ])
        case let .integer(minimum, maximum):
            value = .object([
                .init(key: "maximum", value: .integer(maximum)),
                .init(key: "minimum", value: .integer(minimum)),
                .init(key: "type", value: .string("integer")),
            ])
        case let .string(maximumUTF8Bytes, allowedValues):
            value = .object([
                .init(
                    key: "allowedValues",
                    value: allowedValues.map {
                        .array($0.map(CanonicalJSONValue.string))
                    } ?? .null
                ),
                .init(
                    key: "maximumUTF8Bytes",
                    value: .integer(Int64(maximumUTF8Bytes))
                ),
                .init(key: "type", value: .string("string")),
            ])
        case let .array(maximumItems, item):
            value = .object([
                .init(key: "item", value: try item.wireValue()),
                .init(
                    key: "maximumItems",
                    value: .integer(Int64(maximumItems))
                ),
                .init(key: "type", value: .string("array")),
            ])
        case let .object(properties):
            value = .object([
                .init(
                    key: "properties",
                    value: .array(try properties.map { property in
                        .object([
                            .init(key: "name", value: .string(property.name)),
                            .init(key: "required", value: .boolean(property.required)),
                            .init(key: "schema", value: try property.schema.wireValue()),
                        ])
                    })
                ),
                .init(key: "type", value: .string("object")),
            ])
        }
        try CanonicalJSON.validate(value)
        return value
    }

    public init(wireValue: CanonicalJSONValue) throws {
        try CanonicalJSON.validate(wireValue)
        self = try Self.decodeWireValue(wireValue)
    }

    static func isPropertyName(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    private static func exactScalars(_ value: String) -> [UInt32] {
        value.unicodeScalars.map(\.value)
    }

    private static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
        exactScalars(lhs) == exactScalars(rhs)
    }

    private static func decodeWireValue(
        _ value: CanonicalJSONValue
    ) throws -> Self {
        guard case let .object(members) = value,
              let type = string("type", in: members) else {
            throw CapabilitySchemaError.invalidDefinition(field: "wire.type")
        }
        switch type {
        case "boolean":
            try requireKeys(members, ["type"])
            return .boolean()
        case "integer":
            try requireKeys(members, ["maximum", "minimum", "type"])
            guard let minimum = integer("minimum", in: members),
                  let maximum = integer("maximum", in: members) else {
                throw CapabilitySchemaError.invalidDefinition(field: "wire.integer")
            }
            return try .integer(minimum: minimum, maximum: maximum)
        case "string":
            try requireKeys(
                members,
                ["allowedValues", "maximumUTF8Bytes", "type"]
            )
            guard let maximum = integer("maximumUTF8Bytes", in: members),
                  maximum >= 1,
                  maximum <= Int64(Int.max),
                  let allowed = member("allowedValues", in: members) else {
                throw CapabilitySchemaError.invalidDefinition(field: "wire.string")
            }
            let allowedValues: [String]?
            switch allowed {
            case .null:
                allowedValues = nil
            case let .array(values):
                allowedValues = try values.map { value in
                    guard case let .string(text) = value else {
                        throw CapabilitySchemaError.invalidDefinition(
                            field: "wire.string.allowedValues"
                        )
                    }
                    return text
                }
            default:
                throw CapabilitySchemaError.invalidDefinition(
                    field: "wire.string.allowedValues"
                )
            }
            return try .string(
                maximumUTF8Bytes: Int(maximum),
                allowedValues: allowedValues
            )
        case "array":
            try requireKeys(members, ["item", "maximumItems", "type"])
            guard let maximum = integer("maximumItems", in: members),
                  maximum >= 1,
                  maximum <= Int64(Int.max),
                  let item = member("item", in: members) else {
                throw CapabilitySchemaError.invalidDefinition(field: "wire.array")
            }
            return try .array(
                maximumItems: Int(maximum),
                item: decodeWireValue(item)
            )
        case "object":
            try requireKeys(members, ["properties", "type"])
            guard let rawProperties = member("properties", in: members),
                  case let .array(values) = rawProperties else {
                throw CapabilitySchemaError.invalidDefinition(field: "wire.object")
            }
            let properties = try values.map { value in
                guard case let .object(propertyMembers) = value else {
                    throw CapabilitySchemaError.invalidDefinition(
                        field: "wire.object.property"
                    )
                }
                try requireKeys(
                    propertyMembers,
                    ["name", "required", "schema"]
                )
                guard let name = string("name", in: propertyMembers),
                      let requiredValue = member("required", in: propertyMembers),
                      case let .boolean(required) = requiredValue,
                      let schema = member("schema", in: propertyMembers) else {
                    throw CapabilitySchemaError.invalidDefinition(
                        field: "wire.object.property"
                    )
                }
                return try CapabilitySchemaPropertyV1(
                    name: name,
                    required: required,
                    schema: decodeWireValue(schema)
                )
            }
            return try .object(properties: properties)
        default:
            throw CapabilitySchemaError.invalidDefinition(field: "wire.type")
        }
    }

    private static func requireKeys(
        _ members: [CanonicalJSONMember],
        _ keys: Set<String>
    ) throws {
        guard Set(members.map(\.key)) == keys,
              members.count == keys.count else {
            throw CapabilitySchemaError.invalidDefinition(field: "wire.keys")
        }
    }

    private static func member(
        _ key: String,
        in members: [CanonicalJSONMember]
    ) -> CanonicalJSONValue? {
        members.first { $0.key == key }?.value
    }

    private static func string(
        _ key: String,
        in members: [CanonicalJSONMember]
    ) -> String? {
        guard let value = member(key, in: members),
              case let .string(text) = value else { return nil }
        return text
    }

    private static func integer(
        _ key: String,
        in members: [CanonicalJSONMember]
    ) -> Int64? {
        guard let value = member(key, in: members),
              case let .integer(number) = value else { return nil }
        return number
    }
}
