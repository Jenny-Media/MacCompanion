import CompanionHostPlatform
import Foundation
import Testing

private func uuidBytes(_ value: UUID) -> [UInt8] {
    withUnsafeBytes(of: value.uuid) { Array($0) }
}

private func expectRandomVersion4UUID(_ value: UUID) {
    let bytes = uuidBytes(value)
    #expect(bytes.count == 16)
    #expect(bytes[6] >> 4 == 4)
    #expect(bytes[8] >> 6 == 2)
}

@Test func securityGeneratorCreatesBoundedApprovalMaterial() async throws {
    let value = try await SecurityInteractiveSessionMaterialGeneratorV0()
        .approvalMaterials()
    expectRandomVersion4UUID(value.approvalID)
    #expect(value.serverChallenge.count == 32)
}

@Test func securityGeneratorCreatesDistinctRoleBoundBootstrapMaterial() async throws {
    let value = try await SecurityInteractiveSessionMaterialGeneratorV0()
        .bootstrapMaterials()
    expectRandomVersion4UUID(value.interactiveSessionID)
    expectRandomVersion4UUID(value.inputChannelID)
    expectRandomVersion4UUID(value.mediaChannelID)
    #expect(Set([
        value.interactiveSessionID,
        value.inputChannelID,
        value.mediaChannelID,
    ]).count == 3)
    #expect(value.inputCredential.count == 32)
    #expect(value.mediaCredential.count == 32)
    #expect(value.inputCredential != value.mediaCredential)
}
