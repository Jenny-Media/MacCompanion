import CompanionWire
import Foundation

public enum LocalInteractiveAdmissionWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
}

public enum LocalInteractiveAdmissionWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodePublication(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) throws -> Data {
        try encode(publication)
    }

    public static func decodePublication(
        _ data: Data
    ) throws -> LocalInteractiveAdmissionPublicationV1 {
        try decode(LocalInteractiveAdmissionPublicationV1.self, from: data)
    }

    public static func encodeReceipt(
        _ receipt: LocalInteractiveAdmissionPublishedReceiptV1
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeReceipt(
        _ data: Data
    ) throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        try decode(
            LocalInteractiveAdmissionPublishedReceiptV1.self,
            from: data
        )
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalInteractiveAdmissionWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalInteractiveAdmissionWireCodecErrorV1
                    .payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalInteractiveAdmissionWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalInteractiveAdmissionWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalInteractiveAdmissionWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalInteractiveAdmissionWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalInteractiveAdmissionWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalInteractiveAdmissionWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalInteractiveAdmissionWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalInteractiveAdmissionWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalInteractiveAdmissionWireCodecErrorV1.invalidPayload
        }
    }
}
