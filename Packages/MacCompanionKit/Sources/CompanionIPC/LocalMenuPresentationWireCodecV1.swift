import CompanionWire
import Foundation

public enum LocalMenuPresentationWireCodecErrorV1:
    Error,
    Equatable,
    Sendable
{
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidPayload
    case invalidWithdrawal
}

/// Closed withdrawal value used by the XPC envelope. It is deliberately not
/// a JSON payload: the transport carries this exact UUID as XPC_TYPE_UUID.
public struct LocalMenuPresentationWithdrawalV1: Equatable, Sendable {
    public let reviewID: UUID

    public init(reviewID: UUID) throws {
        guard reviewID != Self.zeroUUID else {
            throw LocalMenuPresentationWireCodecErrorV1.invalidWithdrawal
        }
        self.reviewID = reviewID
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Canonical bounded JSON for the three payload-bearing Agent-to-menu
/// presentation operations. Method kind and authorization remain separate
/// closed XPC-envelope concerns.
public enum LocalMenuPresentationWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encodePairingReview(
        _ review: LocalPairingReviewV0
    ) throws -> Data {
        try encode(review)
    }

    public static func decodePairingReview(
        _ data: Data
    ) throws -> LocalPairingReviewV0 {
        try decode(LocalPairingReviewV0.self, from: data)
    }

    public static func encodeHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) throws -> Data {
        try encode(review)
    }

    public static func decodeHostIdentityRecoveryReview(
        _ data: Data
    ) throws -> LocalHostIdentityRecoveryReviewV0 {
        try decode(LocalHostIdentityRecoveryReviewV0.self, from: data)
    }

    public static func encodeHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeHostIdentityRecoveryResume(
        _ data: Data
    ) throws -> LocalHostIdentityRecoveryCommandV0 {
        try decode(LocalHostIdentityRecoveryCommandV0.self, from: data)
    }

    public static func validateWithdrawal(
        reviewID: UUID
    ) throws -> LocalMenuPresentationWithdrawalV1 {
        try LocalMenuPresentationWithdrawalV1(reviewID: reviewID)
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalMenuPresentationWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalMenuPresentationWireCodecErrorV1.payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalMenuPresentationWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return data
        } catch let error as LocalMenuPresentationWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalMenuPresentationWireCodecErrorV1.invalidPayload
        }
    }

    private static func decode<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalMenuPresentationWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalMenuPresentationWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalMenuPresentationWireCodecErrorV1
                    .nonCanonicalPayload
            }
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw LocalMenuPresentationWireCodecErrorV1
                    .nonCanonicalPayload
            }
            return value
        } catch let error as LocalMenuPresentationWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalMenuPresentationWireCodecErrorV1.invalidPayload
        }
    }
}
