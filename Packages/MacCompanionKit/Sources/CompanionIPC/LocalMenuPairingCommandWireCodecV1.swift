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

    public static func encodeInteractiveControlGrantReviewRequest(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) throws -> Data {
        try encode(request)
    }

    public static func decodeInteractiveControlGrantReviewRequest(
        _ data: Data
    ) throws -> LocalInteractiveControlGrantReviewRequestV0 {
        try decode(LocalInteractiveControlGrantReviewRequestV0.self, from: data)
    }

    public static func encodeInteractiveControlGrantReview(
        _ review: LocalInteractiveControlGrantReviewV0
    ) throws -> Data {
        try encode(review)
    }

    public static func decodeInteractiveControlGrantReview(
        _ data: Data
    ) throws -> LocalInteractiveControlGrantReviewV0 {
        try decode(LocalInteractiveControlGrantReviewV0.self, from: data)
    }

    public static func encodeGrantDecisionCommand(
        _ command: LocalGrantDecisionCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeGrantDecisionCommand(
        _ data: Data
    ) throws -> LocalGrantDecisionCommandV0 {
        try decode(LocalGrantDecisionCommandV0.self, from: data)
    }

    public static func encodeGrantDecisionReceipt(
        _ receipt: LocalGrantDecisionReceiptV0
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeGrantDecisionReceipt(
        _ data: Data
    ) throws -> LocalGrantDecisionReceiptV0 {
        try decode(LocalGrantDecisionReceiptV0.self, from: data)
    }

    public static func encodeDeviceRevocationReviewRequest(_ value: LocalDeviceRevocationReviewRequestV1) throws -> Data { try encode(value) }
    public static func decodeDeviceRevocationReviewRequest(_ data: Data) throws -> LocalDeviceRevocationReviewRequestV1 { try decode(LocalDeviceRevocationReviewRequestV1.self, from: data) }
    public static func encodeDeviceRevocationReviewReply(_ value: LocalDeviceRevocationReviewReplyV1) throws -> Data { try encode(value) }
    public static func decodeDeviceRevocationReviewReply(_ data: Data) throws -> LocalDeviceRevocationReviewReplyV1 { try decode(LocalDeviceRevocationReviewReplyV1.self, from: data) }
    public static func encodeDeviceRevocationCommand(_ value: LocalDeviceRevocationCommandV0) throws -> Data { try encode(value) }
    public static func decodeDeviceRevocationCommand(_ data: Data) throws -> LocalDeviceRevocationCommandV0 { try decode(LocalDeviceRevocationCommandV0.self, from: data) }
    public static func encodeDeviceRevokedReceipt(_ value: LocalDeviceRevokedReceiptV0) throws -> Data { try encode(value) }
    public static func decodeDeviceRevokedReceipt(_ data: Data) throws -> LocalDeviceRevokedReceiptV0 { try decode(LocalDeviceRevokedReceiptV0.self, from: data) }

    public static func encodeCapabilityGrantReviewRequest(_ value: LocalCapabilityGrantReviewRequestV1) throws -> Data { try encode(value) }
    public static func decodeCapabilityGrantReviewRequest(_ data: Data) throws -> LocalCapabilityGrantReviewRequestV1 { try decode(LocalCapabilityGrantReviewRequestV1.self, from: data) }
    public static func encodeCapabilityGrantReview(_ value: LocalCapabilityGrantReviewV1) throws -> Data { try encode(value) }
    public static func decodeCapabilityGrantReview(_ data: Data) throws -> LocalCapabilityGrantReviewV1 { try decode(LocalCapabilityGrantReviewV1.self, from: data) }
    public static func encodeCapabilityGrantDecision(_ value: LocalCapabilityGrantDecisionCommandV1) throws -> Data { try encode(value) }
    public static func decodeCapabilityGrantDecision(_ data: Data) throws -> LocalCapabilityGrantDecisionCommandV1 { try decode(LocalCapabilityGrantDecisionCommandV1.self, from: data) }

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
