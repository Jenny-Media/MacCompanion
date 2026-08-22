#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatformC
import Foundation

package enum MacLocalXPCMenuPresentationRequestV1: Equatable, Sendable {
    case pairingReview(Data)
    case pairingWithdrawal(UUID)
    case hostRecoveryReview(Data)
    case hostRecoveryResume(Data)
    case hostRecoveryWithdrawal(UUID)

    package var authorizationMethod: LocalIPCMethod {
        switch self {
        case .pairingReview:
            .publishPairingReview
        case .pairingWithdrawal:
            .withdrawPairingReview
        case .hostRecoveryReview:
            .publishHostIdentityRecoveryReview
        case .hostRecoveryResume:
            .publishHostIdentityRecoveryResume
        case .hostRecoveryWithdrawal:
            .withdrawHostIdentityRecovery
        }
    }

    package var isPublish: Bool {
        switch self {
        case .pairingReview, .hostRecoveryReview, .hostRecoveryResume:
            true
        case .pairingWithdrawal, .hostRecoveryWithdrawal:
            false
        }
    }
}

package enum MacLocalXPCMenuPresentationPayloadKindV1: Sendable {
    case pairingReview
    case hostRecoveryReview
    case hostRecoveryResume
}

package enum MacLocalXPCMenuPresentationWithdrawalKindV1: Sendable {
    case pairing
    case hostRecovery
}

/// Copies the borrowed data or UUID bytes while the incoming XPC message is
/// alive. Canonical typed JSON validation remains a separate CompanionIPC
/// concern performed before a request reaches a presentation owner.
@available(macOS 26.0, *)
package enum MacLocalXPCMenuPresentationWireV1 {
    package static let maximumPayloadBytes = Int(
        MCLocalXPCMaximumMenuPresentationPayloadBytes
    )

    package static func copyExactRequest(
        _ message: MCLocalXPCMessageRef
    ) -> MacLocalXPCMenuPresentationRequestV1? {
        var payload: UnsafePointer<UInt8>?
        var payloadLength = 0
        if MCLocalXPCMessageGetExactPairingReviewPublish(
            message,
            &payload,
            &payloadLength
        ), let payload {
            return copyBorrowedPayload(
                payload,
                count: payloadLength,
                kind: .pairingReview
            )
        }
        if let bytes = MCLocalXPCMessageGetExactPairingReviewWithdrawal(
            message
        ) {
            return copyBorrowedWithdrawal(
                bytes,
                count: 16,
                kind: .pairing
            )
        }
        if MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
            message,
            &payload,
            &payloadLength
        ), let payload {
            return copyBorrowedPayload(
                payload,
                count: payloadLength,
                kind: .hostRecoveryReview
            )
        }
        if MCLocalXPCMessageGetExactHostRecoveryResumePublish(
            message,
            &payload,
            &payloadLength
        ), let payload {
            return copyBorrowedPayload(
                payload,
                count: payloadLength,
                kind: .hostRecoveryResume
            )
        }
        if let bytes = MCLocalXPCMessageGetExactHostRecoveryWithdrawal(
            message
        ) {
            return copyBorrowedWithdrawal(
                bytes,
                count: 16,
                kind: .hostRecovery
            )
        }
        return nil
    }

    /// Exercises the same exact builders used by the outbound C wrappers,
    /// then releases the source message before returning the copied value.
    package static func copyExactConstructedRequest(
        _ request: MacLocalXPCMenuPresentationRequestV1
    ) -> MacLocalXPCMenuPresentationRequestV1? {
        let message: MCLocalXPCMessageRef?
        switch request {
        case .pairingReview(let payload):
            message = payload.withUnsafeBytes { buffer in
                guard let bytes = buffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return MCLocalXPCMessageCreatePairingReviewPublish(
                    bytes,
                    payload.count
                )
            }
        case .pairingWithdrawal(let reviewID):
            var bytes = reviewID.uuid
            message = withUnsafeBytes(of: &bytes) { buffer in
                guard let address = buffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return MCLocalXPCMessageCreatePairingReviewWithdrawal(
                    address,
                    buffer.count
                )
            }
        case .hostRecoveryReview(let payload):
            message = payload.withUnsafeBytes { buffer in
                guard let bytes = buffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return MCLocalXPCMessageCreateHostRecoveryReviewPublish(
                    bytes,
                    payload.count
                )
            }
        case .hostRecoveryResume(let payload):
            message = payload.withUnsafeBytes { buffer in
                guard let bytes = buffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return MCLocalXPCMessageCreateHostRecoveryResumePublish(
                    bytes,
                    payload.count
                )
            }
        case .hostRecoveryWithdrawal(let reviewID):
            var bytes = reviewID.uuid
            message = withUnsafeBytes(of: &bytes) { buffer in
                guard let address = buffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return MCLocalXPCMessageCreateHostRecoveryWithdrawal(
                    address,
                    buffer.count
                )
            }
        }
        guard let message else { return nil }
        defer { MCLocalXPCMessageRelease(message) }
        return copyExactRequest(message)
    }

    package static func copyBorrowedPayload(
        _ bytes: UnsafePointer<UInt8>,
        count: Int,
        kind: MacLocalXPCMenuPresentationPayloadKindV1
    ) -> MacLocalXPCMenuPresentationRequestV1? {
        guard count > 0, count <= maximumPayloadBytes else { return nil }
        let payload = Data(bytes: bytes, count: count)
        switch kind {
        case .pairingReview:
            return .pairingReview(payload)
        case .hostRecoveryReview:
            return .hostRecoveryReview(payload)
        case .hostRecoveryResume:
            return .hostRecoveryResume(payload)
        }
    }

    package static func copyBorrowedWithdrawal(
        _ bytes: UnsafePointer<UInt8>,
        count: Int,
        kind: MacLocalXPCMenuPresentationWithdrawalKindV1
    ) -> MacLocalXPCMenuPresentationRequestV1? {
        guard count == 16 else { return nil }
        let reviewID = copyUUID(bytes)
        guard reviewID != zeroUUID else { return nil }
        switch kind {
        case .pairing:
            return .pairingWithdrawal(reviewID)
        case .hostRecovery:
            return .hostRecoveryWithdrawal(reviewID)
        }
    }

    private static func copyUUID(
        _ bytes: UnsafePointer<UInt8>
    ) -> UUID {
        UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}
#endif
