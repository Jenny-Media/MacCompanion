import CompanionWire
import Foundation

public enum LocalMenuPairingCommandWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
}

/// Canonical bounded JSON for the three menu-to-Agent pairing commands and
/// their exactly typed receipts. XPC method kind, peer authentication,
/// readiness, single-flight admission, and timeout remain separate closed
/// transport concerns.
public enum LocalMenuPairingCommandWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodeCreateCommand(
        _ command: LocalPairingSessionCreateCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeCreateCommand(
        _ data: Data
    ) throws -> LocalPairingSessionCreateCommandV0 {
        try decode(LocalPairingSessionCreateCommandV0.self, from: data)
    }

    public static func encodeCreatedReceipt(
        _ receipt: LocalPairingSessionCreatedReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeCreatedReceipt(
        _ data: Data
    ) throws -> LocalPairingSessionCreatedReceiptV0 {
        try decode(LocalPairingSessionCreatedReceiptV0.self, from: data)
    }

    public static func encodeDismissCommand(
        _ command: LocalPairingSessionDismissCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeDismissCommand(
        _ data: Data
    ) throws -> LocalPairingSessionDismissCommandV0 {
        try decode(LocalPairingSessionDismissCommandV0.self, from: data)
    }

    public static func encodeDismissedReceipt(
        _ receipt: LocalPairingSessionDismissedReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeDismissedReceipt(
        _ data: Data
    ) throws -> LocalPairingSessionDismissedReceiptV0 {
        try decode(LocalPairingSessionDismissedReceiptV0.self, from: data)
    }

    public static func encodeDecisionCommand(
        _ command: LocalPairingDecisionCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeDecisionCommand(
        _ data: Data
    ) throws -> LocalPairingDecisionCommandV0 {
        try decode(LocalPairingDecisionCommandV0.self, from: data)
    }

    public static func encodeDecisionReceipt(
        _ receipt: LocalPairingDecisionReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeDecisionReceipt(
        _ data: Data
    ) throws -> LocalPairingDecisionReceiptV0 {
        try decode(LocalPairingDecisionReceiptV0.self, from: data)
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalMenuPairingCommandWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalMenuPairingCommandWireCodecErrorV1.payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalMenuPairingCommandWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalMenuPairingCommandWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalMenuPairingCommandWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalMenuPairingCommandWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalMenuPairingCommandWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalMenuPairingCommandWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalMenuPairingCommandWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalMenuPairingCommandWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalMenuPairingCommandWireCodecErrorV1.invalidPayload
        }
    }
}
