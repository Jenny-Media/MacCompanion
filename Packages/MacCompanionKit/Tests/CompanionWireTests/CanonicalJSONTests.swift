import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private struct CanonicalJSONFixture: Decodable {
    struct Vector: Decodable {
        let name: String
        let inputUTF8: String
        let canonicalUTF8: String
    }

    let vectors: [Vector]
    let invalidInputs: [String]
}

private func canonicalJSONFixture() throws -> CanonicalJSONFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("canonical-json-v0.1.json")
    return try JSONDecoder().decode(
        CanonicalJSONFixture.self,
        from: Data(contentsOf: url)
    )
}

@Test func restrictedJCSMatchesEveryAuthoritativeVector() throws {
    let fixture = try canonicalJSONFixture()
    #expect(fixture.vectors.count == 2)
    for vector in fixture.vectors {
        let canonical = try CanonicalJSON.canonicalize(Data(vector.inputUTF8.utf8))
        #expect(
            canonical == Data(vector.canonicalUTF8.utf8),
            "canonical mismatch for \(vector.name)"
        )
        #expect(try CanonicalJSON.canonicalize(canonical) == canonical)
    }
}

@Test func restrictedJCSRejectsEveryAmbiguousOrUnsupportedFixture() throws {
    for input in try canonicalJSONFixture().invalidInputs {
        #expect(throws: WireError.self) {
            try CanonicalJSON.canonicalize(Data(input.utf8))
        }
    }
}

@Test func restrictedJCSPreservesUnicodeWithoutNormalization() throws {
    let input = Data("{\"é\":1,\"é\":2}".utf8)
    let canonical = try CanonicalJSON.canonicalize(input)
    #expect(String(decoding: canonical, as: UTF8.self) == "{\"é\":2,\"é\":1}")
    #expect(try CanonicalJSON.parse(canonical) == .object([
        CanonicalJSONMember(key: "é", value: .integer(2)),
        CanonicalJSONMember(key: "é", value: .integer(1)),
    ]))
}

@Test func restrictedJCSProducesTheOperationFixtureParameterBytes() throws {
    struct OperationFixture: Decodable {
        struct Inputs: Decodable { let canonicalParametersUTF8: String }
        let inputs: Inputs
    }
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/operation-v0.1.json")
    let fixture = try JSONDecoder().decode(
        OperationFixture.self,
        from: Data(contentsOf: url)
    )
    let source = Data(fixture.inputs.canonicalParametersUTF8.utf8)
    #expect(try CanonicalJSON.canonicalize(source) == source)
}
