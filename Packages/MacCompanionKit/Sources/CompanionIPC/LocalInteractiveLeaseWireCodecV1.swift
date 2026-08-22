import CompanionWire
import Foundation

public enum LocalInteractiveLeaseWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
}

/// Canonical bounded JSON for the Agent-to-menu Interactive lease lifecycle.
/// XPC dictionary shape, peer authentication, readiness, single-flight
/// admission, deadlines, and runtime invalidation remain separate transport
/// concerns.
public enum LocalInteractiveLeaseWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodeInstallCommand(
        _ command: InteractiveRuntimeInstallCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeInstallCommand(
        _ data: Data
    ) throws -> InteractiveRuntimeInstallCommandV0 {
        try decode(InteractiveRuntimeInstallCommandV0.self, from: data)
    }

    public static func encodeInstallReceipt(
        _ receipt: InteractiveRuntimeInstallReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeInstallReceipt(
        _ data: Data
    ) throws -> InteractiveRuntimeInstallReceiptV0 {
        try decode(InteractiveRuntimeInstallReceiptV0.self, from: data)
    }

    public static func encodeRenewal(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) throws -> Data {
        try encode(renewal)
    }

    public static func decodeRenewal(
        _ data: Data
    ) throws -> InteractiveRuntimeLeaseRenewalV0 {
        try decode(InteractiveRuntimeLeaseRenewalV0.self, from: data)
    }

    public static func encodeRevokeCommand(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeRevokeCommand(
        _ data: Data
    ) throws -> InteractiveRuntimeRevokeCommandV0 {
        try decode(InteractiveRuntimeRevokeCommandV0.self, from: data)
    }

    public static func encodeRevokedReceipt(
        _ receipt: InteractiveRuntimeRevokedReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeRevokedReceipt(
        _ data: Data
    ) throws -> InteractiveRuntimeRevokedReceiptV0 {
        try decode(InteractiveRuntimeRevokedReceiptV0.self, from: data)
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalInteractiveLeaseWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalInteractiveLeaseWireCodecErrorV1.payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalInteractiveLeaseWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalInteractiveLeaseWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalInteractiveLeaseWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalInteractiveLeaseWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalInteractiveLeaseWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalInteractiveLeaseWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalInteractiveLeaseWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalInteractiveLeaseWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalInteractiveLeaseWireCodecErrorV1.invalidPayload
        }
    }
}
