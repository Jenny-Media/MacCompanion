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
    public static let maximumSurfaceTargetsReceiptBytes = 65_536

    public static func encodeInitialDesktopCommand(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) throws -> Data {
        try encode(command)
    }

    public static func decodeInitialDesktopCommand(
        _ data: Data
    ) throws -> LocalInteractiveInitialDesktopPreparationCommandV1 {
        try decode(
            LocalInteractiveInitialDesktopPreparationCommandV1.self,
            from: data
        )
    }

    public static func encodeInitialDesktopReceipt(
        _ receipt: LocalInteractiveInitialDesktopPreparedReceiptV1
    ) throws -> Data {
        try encode(receipt)
    }

    public static func decodeInitialDesktopReceipt(
        _ data: Data
    ) throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try decode(
            LocalInteractiveInitialDesktopPreparedReceiptV1.self,
            from: data
        )
    }

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

    public static func encodeSurfaceTargetsCommand(
        _ command: LocalInteractiveSurfaceTargetsCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeSurfaceTargetsCommand(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceTargetsCommandV1 {
        try decode(LocalInteractiveSurfaceTargetsCommandV1.self, from: data)
    }

    public static func encodeSurfaceTargetsReceipt(
        _ receipt: LocalInteractiveSurfaceTargetsReceiptV1
    ) throws -> Data {
        try encode(receipt, maximumBytes: maximumSurfaceTargetsReceiptBytes)
    }

    public static func decodeSurfaceTargetsReceipt(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try decode(
            LocalInteractiveSurfaceTargetsReceiptV1.self,
            from: data,
            maximumBytes: maximumSurfaceTargetsReceiptBytes
        )
    }

    public static func encodeSurfaceResolveCommand(
        _ command: LocalInteractiveSurfaceResolveCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeSurfaceResolveCommand(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceResolveCommandV1 {
        try decode(LocalInteractiveSurfaceResolveCommandV1.self, from: data)
    }

    public static func encodeSurfaceResolvedReceipt(
        _ receipt: LocalInteractiveSurfaceResolvedReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeSurfaceResolvedReceipt(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try decode(LocalInteractiveSurfaceResolvedReceiptV1.self, from: data)
    }

    public static func encodeSurfaceTransitionCommand(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) throws -> Data { try encode(command) }

    public static func decodeSurfaceTransitionCommand(
        _ data: Data
    ) throws -> InteractiveRuntimeSurfaceTransitionCommandV0 {
        try decode(InteractiveRuntimeSurfaceTransitionCommandV0.self, from: data)
    }

    public static func encodeSurfaceTransitionReceipt(
        _ receipt: InteractiveRuntimeSurfaceTransitionReceiptV0
    ) throws -> Data { try encode(receipt) }

    public static func decodeSurfaceTransitionReceipt(
        _ data: Data
    ) throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try decode(InteractiveRuntimeSurfaceTransitionReceiptV0.self, from: data)
    }

    public static func encodeSurfaceAcknowledgementCommand(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) throws -> Data { try encode(command) }

    public static func decodeSurfaceAcknowledgementCommand(
        _ data: Data
    ) throws -> InteractiveRuntimeSurfaceAcknowledgementCommandV0 {
        try decode(
            InteractiveRuntimeSurfaceAcknowledgementCommandV0.self,
            from: data
        )
    }

    public static func encodeSurfaceAcknowledgementReceipt(
        _ receipt: InteractiveRuntimeSurfaceAcknowledgementReceiptV0
    ) throws -> Data { try encode(receipt) }

    public static func decodeSurfaceAcknowledgementReceipt(
        _ data: Data
    ) throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try decode(
            InteractiveRuntimeSurfaceAcknowledgementReceiptV0.self,
            from: data
        )
    }

    public static func encodeSurfaceFailureCommand(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeSurfaceFailureCommand(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceFailureCommandV1 {
        try decode(LocalInteractiveSurfaceFailureCommandV1.self, from: data)
    }

    public static func encodeSurfaceFailureReceipt(
        _ receipt: LocalInteractiveSurfaceFailureReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeSurfaceFailureReceipt(
        _ data: Data
    ) throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try decode(LocalInteractiveSurfaceFailureReceiptV1.self, from: data)
    }

    public static func encodeFocusSnapshotCommand(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeFocusSnapshotCommand(
        _ data: Data
    ) throws -> LocalInteractiveFocusSnapshotCommandV1 {
        try decode(LocalInteractiveFocusSnapshotCommandV1.self, from: data)
    }

    public static func encodeFocusSnapshotReceipt(
        _ receipt: LocalInteractiveFocusSnapshotReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeFocusSnapshotReceipt(
        _ data: Data
    ) throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        try decode(LocalInteractiveFocusSnapshotReceiptV1.self, from: data)
    }

    public static func encodeDisplayCatalogCommand(
        _ command: LocalInteractiveDisplayCatalogCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeDisplayCatalogCommand(
        _ data: Data
    ) throws -> LocalInteractiveDisplayCatalogCommandV1 {
        try decode(LocalInteractiveDisplayCatalogCommandV1.self, from: data)
    }

    public static func encodeDisplayCatalogReceipt(
        _ receipt: LocalInteractiveDisplayCatalogReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeDisplayCatalogReceipt(
        _ data: Data
    ) throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try decode(LocalInteractiveDisplayCatalogReceiptV1.self, from: data)
    }

    public static func encodeDisplaySelectCommand(
        _ command: LocalInteractiveDisplaySelectCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeDisplaySelectCommand(
        _ data: Data
    ) throws -> LocalInteractiveDisplaySelectCommandV1 {
        try decode(LocalInteractiveDisplaySelectCommandV1.self, from: data)
    }

    public static func encodeDisplaySelectedReceipt(
        _ receipt: LocalInteractiveDisplaySelectedReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeDisplaySelectedReceipt(
        _ data: Data
    ) throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try decode(LocalInteractiveDisplaySelectedReceiptV1.self, from: data)
    }

    public static func encodeNativeBackendCommand(_ command: LocalInteractiveNativeBackendCommandV1) throws -> Data {
        try command.validate(); return try encode(command)
    }
    public static func decodeNativeBackendCommand(_ data: Data) throws -> LocalInteractiveNativeBackendCommandV1 {
        let command = try decode(LocalInteractiveNativeBackendCommandV1.self, from: data)
        try command.validate(); return command
    }
    public static func encodeNativeBackendReceipt(_ receipt: LocalInteractiveNativeBackendReceiptV1) throws -> Data {
        try receipt.validate(); return try encode(receipt)
    }
    public static func decodeNativeBackendReceipt(_ data: Data) throws -> LocalInteractiveNativeBackendReceiptV1 {
        let receipt = try decode(LocalInteractiveNativeBackendReceiptV1.self, from: data)
        try receipt.validate(); return receipt
    }

    public static func encodeNativeSnapshotCommand(_ command: LocalInteractiveNativeSnapshotCommandV1) throws -> Data {
        try command.fence.validate()
        return try encode(command)
    }
    public static func decodeNativeSnapshotCommand(_ data: Data) throws -> LocalInteractiveNativeSnapshotCommandV1 {
        let command = try decode(LocalInteractiveNativeSnapshotCommandV1.self, from: data)
        try command.fence.validate()
        return command
    }
    public static func encodeNativeSnapshotReceipt(_ receipt: LocalInteractiveNativeSnapshotReceiptV1) throws -> Data {
        try receipt.snapshot.validate()
        return try encode(receipt)
    }
    public static func decodeNativeSnapshotReceipt(_ data: Data) throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        let receipt = try decode(LocalInteractiveNativeSnapshotReceiptV1.self, from: data)
        try receipt.snapshot.validate()
        return receipt
    }

    public static func encodeWebRTCOfferCommand(
        _ command: LocalInteractiveWebRTCOfferCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeWebRTCOfferCommand(
        _ data: Data
    ) throws -> LocalInteractiveWebRTCOfferCommandV1 {
        try decode(LocalInteractiveWebRTCOfferCommandV1.self, from: data)
    }

    public static func encodeWebRTCOfferReceipt(
        _ receipt: LocalInteractiveWebRTCOfferReceiptV1
    ) throws -> Data { try encode(receipt) }

    public static func decodeWebRTCOfferReceipt(
        _ data: Data
    ) throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        try decode(LocalInteractiveWebRTCOfferReceiptV1.self, from: data)
    }

    public static func encodeWebRTCAnswerCommand(
        _ command: LocalInteractiveWebRTCAnswerCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeWebRTCAnswerCommand(
        _ data: Data
    ) throws -> LocalInteractiveWebRTCAnswerCommandV1 {
        try decode(LocalInteractiveWebRTCAnswerCommandV1.self, from: data)
    }

    public static func encodeWebRTCCloseCommand(
        _ command: LocalInteractiveWebRTCCloseCommandV1
    ) throws -> Data { try encode(command) }

    public static func decodeWebRTCCloseCommand(
        _ data: Data
    ) throws -> LocalInteractiveWebRTCCloseCommandV1 {
        try decode(LocalInteractiveWebRTCCloseCommandV1.self, from: data)
    }

    private static func encode<Value: Encodable>(
        _ value: Value,
        maximumBytes: Int = maximumEncodedBytes
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard !data.isEmpty else {
                throw LocalInteractiveLeaseWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumBytes else {
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
        from data: Data,
        maximumBytes: Int = maximumEncodedBytes
    ) throws -> Value {
        guard !data.isEmpty else {
            throw LocalInteractiveLeaseWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumBytes else {
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
            guard try encode(value, maximumBytes: maximumBytes) == data else {
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
