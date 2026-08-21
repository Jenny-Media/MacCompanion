import Foundation

struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public func requireExactKeys(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual == expected else {
        let unknown = actual.subtracting(expected).sorted()
        let missing = expected.subtracting(actual).sorted()
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "closed object mismatch; unknown=\(unknown), missing=\(missing)"
            )
        )
    }
}
