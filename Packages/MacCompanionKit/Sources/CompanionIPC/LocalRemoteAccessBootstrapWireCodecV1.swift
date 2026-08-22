import CompanionWire
import Foundation

public enum LocalRemoteAccessBootstrapWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
}

/// Canonical bounded JSON carried only inside the exact authentication-only
/// bootstrap XPC envelopes. Method kind, peer authentication, phase admission,
/// and durable mutation remain separate closed concerns.
public enum LocalRemoteAccessBootstrapWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodeOffer(
        _ offer: LocalRemoteAccessBootstrapOfferV0
    ) throws -> Data {
        try encode(offer)
    }

    public static func decodeOffer(
        _ data: Data
    ) throws -> LocalRemoteAccessBootstrapOfferV0 {
        try decode(LocalRemoteAccessBootstrapOfferV0.self, from: data)
    }

    public static func encodeEnableCommand(
        _ command: LocalRemoteAccessEnableCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeEnableCommand(
        _ data: Data
    ) throws -> LocalRemoteAccessEnableCommandV0 {
        try decode(LocalRemoteAccessEnableCommandV0.self, from: data)
    }

    public static func encodeEnabledReceipt(
        _ receipt: LocalRemoteAccessEnabledReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeEnabledReceipt(
        _ data: Data
    ) throws -> LocalRemoteAccessEnabledReceiptV0 {
        try decode(LocalRemoteAccessEnabledReceiptV0.self, from: data)
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalRemoteAccessBootstrapWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalRemoteAccessBootstrapWireCodecErrorV1
                    .payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalRemoteAccessBootstrapWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalRemoteAccessBootstrapWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalRemoteAccessBootstrapWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalRemoteAccessBootstrapWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalRemoteAccessBootstrapWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalRemoteAccessBootstrapWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalRemoteAccessBootstrapWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalRemoteAccessBootstrapWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalRemoteAccessBootstrapWireCodecErrorV1.invalidPayload
        }
    }
}
