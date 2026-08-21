@testable import CompanionClientPlatform
import CompanionClient
import CryptoKit
import Foundation
import Testing

private func clientPlatformPrompts() throws -> SecurityClientPresencePromptsV0 {
    try SecurityClientPresencePromptsV0(
        pairNewMac: "Confirm pairing this Mac.",
        approveOperation: "Approve this Mac operation.",
        startInteractiveControl: "Start Interactive Control.",
        expandGrant: "Approve additional Mac capabilities."
    )
}

@Test func clientKeyProfilesKeepReconnectAndFreshPresenceSeparate() throws {
    let session = SecurityClientKeyCreationProfileV0.profile(
        for: .session,
        requireSecureEnclave: true
    )
    #expect(session.protection == .afterFirstUnlockThisDeviceOnly)
    #expect(!session.requiresUserPresence)
    #expect(session.requiresSecureEnclave)

    let approval = SecurityClientKeyCreationProfileV0.profile(
        for: .approval,
        requireSecureEnclave: true
    )
    #expect(approval.protection == .whenUnlockedThisDeviceOnlyUserPresence)
    #expect(approval.requiresUserPresence)
    #expect(approval.requiresSecureEnclave)
}

@Test func clientKeyConfigurationRejectsUnboundedOrUnsafePresentationText() throws {
    _ = try SecurityClientKeyCustodyConfigurationV0(
        applicationTagPrefix: "com.jennymedia.maccompanion.client",
        prompts: clientPlatformPrompts()
    )
    #expect(throws: SecurityClientKeyCustodyErrorV0.invalidConfiguration) {
        _ = try SecurityClientKeyCustodyConfigurationV0(
            applicationTagPrefix: "invalid prefix",
            prompts: clientPlatformPrompts()
        )
    }
    #expect(throws: SecurityClientKeyCustodyErrorV0.invalidConfiguration) {
        _ = try SecurityClientPresencePromptsV0(
            pairNewMac: "bad\ntext",
            approveOperation: "Approve.",
            startInteractiveControl: "Start.",
            expandGrant: "Expand."
        )
    }
}

@Test func securityDERConversionProducesExactRawP256Signature() throws {
    let key = P256.Signing.PrivateKey()
    let signature = try key.signature(for: Data("message".utf8))
    #expect(try SecurityClientIdentityKeyCustodyV0.rawP256Signature(
        fromDER: signature.derRepresentation
    ) == signature.rawRepresentation)
    #expect(throws: SecurityClientKeyCustodyErrorV0.signingFailed) {
        _ = try SecurityClientIdentityKeyCustodyV0.rawP256Signature(
            fromDER: Data([0x30, 0x00])
        )
    }
}
