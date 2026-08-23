import CompanionWire
import Foundation

public enum LocalHostIdentityRecoveryWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
}

/// Canonical bounded JSON for the destructive recovery command and its exact
/// receipt. Authentication, method authorization, current-review admission,
/// single-flight delivery, and timeout fencing remain transport concerns.
public enum LocalHostIdentityRecoveryWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodeCommand(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeCommand(
        _ data: Data
    ) throws -> LocalHostIdentityRecoveryCommandV0 {
        try decode(LocalHostIdentityRecoveryCommandV0.self, from: data)
    }

    public static func encodeReceipt(
        _ receipt: LocalHostIdentityRecoveredReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeReceipt(
        _ data: Data
    ) throws -> LocalHostIdentityRecoveredReceiptV0 {
        try decode(LocalHostIdentityRecoveredReceiptV0.self, from: data)
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalHostIdentityRecoveryWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalHostIdentityRecoveryWireCodecErrorV1.payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalHostIdentityRecoveryWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalHostIdentityRecoveryWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalHostIdentityRecoveryWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalHostIdentityRecoveryWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalHostIdentityRecoveryWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalHostIdentityRecoveryWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalHostIdentityRecoveryWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalHostIdentityRecoveryWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalHostIdentityRecoveryWireCodecErrorV1.invalidPayload
        }
    }
}
