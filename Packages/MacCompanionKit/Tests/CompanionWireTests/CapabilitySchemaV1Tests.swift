import CompanionWire
import Foundation
import Testing

private func actionSchema() throws -> CapabilitySchemaV1 {
    try .object(properties: [
        CapabilitySchemaPropertyV1(
            name: "muted",
            required: true,
            schema: .boolean()
        ),
        CapabilitySchemaPropertyV1(
            name: "mode",
            required: false,
            schema: .string(
                maximumUTF8Bytes: 8,
                allowedValues: ["quiet", "normal"]
            )
        ),
        CapabilitySchemaPropertyV1(
            name: "levels",
            required: false,
            schema: .array(
                maximumItems: 3,
                item: .integer(minimum: 0, maximum: 100)
            )
        ),
    ])
}

@Test func closedCapabilitySchemaAcceptsOnlyItsBoundedShape() throws {
    let schema = try actionSchema()
    let valid = try CanonicalJSON.parse(Data(
        "{\"levels\":[0,50,100],\"mode\":\"quiet\",\"muted\":true}".utf8
    ))
    try schema.validate(valid)

    #expect(throws: CapabilitySchemaError.missingRequired(path: "$.muted")) {
        try schema.validate(CanonicalJSON.parse(Data("{}".utf8)))
    }
    #expect(throws: CapabilitySchemaError.unknownProperty(path: "$.extra")) {
        try schema.validate(CanonicalJSON.parse(Data(
            "{\"muted\":true,\"extra\":null}".utf8
        )))
    }
    #expect(throws: CapabilitySchemaError.typeMismatch(path: "$.muted")) {
        try schema.validate(CanonicalJSON.parse(Data("{\"muted\":1}".utf8)))
    }
    #expect(throws: CapabilitySchemaError.constraintViolation(path: "$.levels[1]")) {
        try schema.validate(CanonicalJSON.parse(Data(
            "{\"muted\":true,\"levels\":[0,101]}".utf8
        )))
    }
    #expect(throws: CapabilitySchemaError.constraintViolation(path: "$.mode")) {
        try schema.validate(CanonicalJSON.parse(Data(
            "{\"muted\":true,\"mode\":\"other\"}".utf8
        )))
    }
}

@Test func invalidOrAmbiguousSchemaDefinitionsFailClosed() throws {
    #expect(throws: CapabilitySchemaError.invalidDefinition(field: "integer.range")) {
        try CapabilitySchemaV1.integer(minimum: 2, maximum: 1)
    }
    #expect(throws: CapabilitySchemaError.invalidDefinition(field: "string.allowedValues")) {
        try CapabilitySchemaV1.string(maximumUTF8Bytes: 8, allowedValues: ["same", "same"])
    }
    #expect(throws: CapabilitySchemaError.invalidDefinition(field: "property.name")) {
        try CapabilitySchemaPropertyV1(
            name: "invalid property",
            required: true,
            schema: .boolean()
        )
    }
    let property = try CapabilitySchemaPropertyV1(
        name: "same",
        required: true,
        schema: .boolean()
    )
    #expect(throws: CapabilitySchemaError.invalidDefinition(field: "object.properties")) {
        try CapabilitySchemaV1.object(properties: [property, property])
    }
}

@Test func schemaMatchingDoesNotNormalizeUnicodeEnumValues() throws {
    let schema = try CapabilitySchemaV1.string(
        maximumUTF8Bytes: 8,
        allowedValues: ["é"]
    )
    try schema.validate(.string("é"))
    #expect(throws: CapabilitySchemaError.constraintViolation(path: "$")) {
        try schema.validate(.string("é"))
    }
}
