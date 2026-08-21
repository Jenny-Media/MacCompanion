import CompanionInteractiveHost
import Foundation
import Security

public enum SecurityInteractiveMaterialErrorV0: Error, Equatable, Sendable {
    case randomFailure(OSStatus)
}

/// Production Interactive Control material generator backed exclusively by
/// Security.framework's system cryptographic random source.
public struct SecurityInteractiveSessionMaterialGeneratorV0:
    InteractiveSessionMaterialGeneratingV0,
    Sendable
{
    public init() {}

    public func approvalMaterials() async throws
        -> InteractiveApprovalMaterialsV0 {
        try InteractiveApprovalMaterialsV0(
            approvalID: randomUUID(),
            serverChallenge: randomData(count: 32)
        )
    }

    public func bootstrapMaterials() async throws
        -> InteractiveSessionBootstrapMaterials {
        let sessionID = try randomUUID()
        let inputChannelID = try distinctUUID(excluding: [sessionID])
        let mediaChannelID = try distinctUUID(
            excluding: [sessionID, inputChannelID]
        )
        let inputCredential = try randomData(count: 32)
        var mediaCredential = try randomData(count: 32)
        while mediaCredential == inputCredential {
            mediaCredential = try randomData(count: 32)
        }
        return InteractiveSessionBootstrapMaterials(
            interactiveSessionID: sessionID,
            inputChannelID: inputChannelID,
            inputCredential: inputCredential,
            mediaChannelID: mediaChannelID,
            mediaCredential: mediaCredential
        )
    }

    private func distinctUUID(excluding values: Set<UUID>) throws -> UUID {
        var candidate = try randomUUID()
        while values.contains(candidate) {
            candidate = try randomUUID()
        }
        return candidate
    }

    private func randomUUID() throws -> UUID {
        var bytes = [UInt8](try randomData(count: 16))
        // RFC 4122 variant, random UUID version 4.
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func randomData(count: Int) throws -> Data {
        var value = Data(count: count)
        let status = value.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SecurityInteractiveMaterialErrorV0.randomFailure(status)
        }
        return value
    }
}
