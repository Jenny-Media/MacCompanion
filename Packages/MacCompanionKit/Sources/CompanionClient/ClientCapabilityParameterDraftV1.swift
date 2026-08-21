import CompanionWire
import Foundation

public enum ClientCapabilityParameterDraftErrorV1: Error, Equatable, Sendable {
    case rootMustBeObject
    case invalidPath
    case requiredProperty
    case arrayLimitReached
    case schemaViolation
}

/// Schema-owned parameter draft. The value remains native restricted JSON;
/// callers never edit or transport arbitrary JSON text.
public struct ClientCapabilityParameterDraftV1: Equatable, Sendable {
    public let schema: CapabilitySchemaV1
    public private(set) var value: CanonicalJSONValue

    public init(schema: CapabilitySchemaV1) throws {
        guard schema.isObject else {
            throw ClientCapabilityParameterDraftErrorV1.rootMustBeObject
        }
        self.schema = schema
        value = Self.defaultValue(for: schema)
        try validate()
    }

    public init(
        schema: CapabilitySchemaV1,
        value: CanonicalJSONValue
    ) throws {
        guard schema.isObject else {
            throw ClientCapabilityParameterDraftErrorV1.rootMustBeObject
        }
        self.schema = schema
        self.value = value
        try validate()
    }

    public func validatedParameters() throws -> CanonicalJSONValue {
        try validate()
        return value
    }

    public mutating func setValue(
        _ replacement: CanonicalJSONValue,
        at path: [ClientCapabilityParameterPathComponentV1]
    ) throws {
        guard !path.isEmpty else {
            guard case .object = replacement else {
                throw ClientCapabilityParameterDraftErrorV1.rootMustBeObject
            }
            value = replacement
            try validate()
            return
        }
        let original = value
        do {
            value = try Self.replacing(value, at: path, with: replacement)
            try validate()
        } catch {
            value = original
            throw error
        }
    }

    public mutating func includeOptionalProperty(
        _ name: String,
        inObjectAt path: [ClientCapabilityParameterPathComponentV1] = []
    ) throws {
        guard let objectSchema = Self.schema(at: path, in: schema),
              case let .object(properties) = objectSchema.presentationNode,
              let property = properties.first(where: { $0.name == name }),
              !property.required else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        let object = try Self.value(at: path, in: value)
        guard case var .object(members) = object else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        guard !members.contains(where: { $0.key == name }) else { return }
        members.append(.init(
            key: name,
            value: Self.defaultValue(for: property.schema)
        ))
        try setValue(.object(members), at: path)
    }

    public mutating func removeOptionalProperty(
        _ name: String,
        inObjectAt path: [ClientCapabilityParameterPathComponentV1] = []
    ) throws {
        guard let objectSchema = Self.schema(at: path, in: schema),
              case let .object(properties) = objectSchema.presentationNode,
              let property = properties.first(where: { $0.name == name }) else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        guard !property.required else {
            throw ClientCapabilityParameterDraftErrorV1.requiredProperty
        }
        let object = try Self.value(at: path, in: value)
        guard case var .object(members) = object else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        members.removeAll { $0.key == name }
        try setValue(.object(members), at: path)
    }

    public mutating func appendArrayItem(
        at path: [ClientCapabilityParameterPathComponentV1]
    ) throws {
        guard let arraySchema = Self.schema(at: path, in: schema),
              case let .array(maximumItems, item) = arraySchema.presentationNode else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        let current = try Self.value(at: path, in: value)
        guard case var .array(items) = current else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        guard items.count < maximumItems else {
            throw ClientCapabilityParameterDraftErrorV1.arrayLimitReached
        }
        items.append(Self.defaultValue(for: item))
        try setValue(.array(items), at: path)
    }

    public mutating func removeArrayItem(
        at index: Int,
        inArrayAt path: [ClientCapabilityParameterPathComponentV1]
    ) throws {
        let current = try Self.value(at: path, in: value)
        guard case var .array(items) = current,
              items.indices.contains(index) else {
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
        items.remove(at: index)
        try setValue(.array(items), at: path)
    }

    public static func defaultValue(
        for schema: CapabilitySchemaV1
    ) -> CanonicalJSONValue {
        switch schema.presentationNode {
        case .boolean:
            .boolean(false)
        case let .integer(minimum, maximum):
            .integer(minimum <= 0 && maximum >= 0 ? 0 : minimum)
        case let .string(_, allowedValues):
            .string(allowedValues?.first ?? "")
        case .array:
            .array([])
        case let .object(properties):
            .object(properties.compactMap { property in
                guard property.required else { return nil }
                return CanonicalJSONMember(
                    key: property.name,
                    value: defaultValue(for: property.schema)
                )
            })
        }
    }

    public static func value(
        at path: [ClientCapabilityParameterPathComponentV1],
        in root: CanonicalJSONValue
    ) throws -> CanonicalJSONValue {
        var current = root
        for component in path {
            switch (component, current) {
            case let (.property(name), .object(members)):
                guard let next = members.first(where: { $0.key == name })?.value else {
                    throw ClientCapabilityParameterDraftErrorV1.invalidPath
                }
                current = next
            case let (.index(index), .array(items)):
                guard items.indices.contains(index) else {
                    throw ClientCapabilityParameterDraftErrorV1.invalidPath
                }
                current = items[index]
            default:
                throw ClientCapabilityParameterDraftErrorV1.invalidPath
            }
        }
        return current
    }

    public static func schema(
        at path: [ClientCapabilityParameterPathComponentV1],
        in root: CapabilitySchemaV1
    ) -> CapabilitySchemaV1? {
        var current = root
        for component in path {
            switch (component, current.presentationNode) {
            case let (.property(name), .object(properties)):
                guard let next = properties.first(where: { $0.name == name })?.schema else {
                    return nil
                }
                current = next
            case let (.index, .array(_, item)):
                current = item
            default:
                return nil
            }
        }
        return current
    }

    private func validate() throws {
        guard case .object = value else {
            throw ClientCapabilityParameterDraftErrorV1.rootMustBeObject
        }
        do {
            try schema.validate(value)
            try CanonicalJSON.validate(value)
        } catch {
            throw ClientCapabilityParameterDraftErrorV1.schemaViolation
        }
    }

    private static func replacing(
        _ current: CanonicalJSONValue,
        at path: [ClientCapabilityParameterPathComponentV1],
        with replacement: CanonicalJSONValue
    ) throws -> CanonicalJSONValue {
        guard let head = path.first else { return replacement }
        let tail = Array(path.dropFirst())
        switch (head, current) {
        case let (.property(name), .object(members)):
            guard let index = members.firstIndex(where: { $0.key == name }) else {
                throw ClientCapabilityParameterDraftErrorV1.invalidPath
            }
            var updated = members
            updated[index] = .init(
                key: name,
                value: try replacing(
                    members[index].value,
                    at: tail,
                    with: replacement
                )
            )
            return .object(updated)
        case let (.index(index), .array(items)):
            guard items.indices.contains(index) else {
                throw ClientCapabilityParameterDraftErrorV1.invalidPath
            }
            var updated = items
            updated[index] = try replacing(
                items[index],
                at: tail,
                with: replacement
            )
            return .array(updated)
        default:
            throw ClientCapabilityParameterDraftErrorV1.invalidPath
        }
    }
}

public enum ClientCapabilityParameterPathComponentV1: Equatable, Hashable, Sendable {
    case property(String)
    case index(Int)
}
