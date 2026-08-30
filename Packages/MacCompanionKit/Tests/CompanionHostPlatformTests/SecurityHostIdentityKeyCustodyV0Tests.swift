@testable import CompanionHostPlatform
import CompanionSecurity
import CryptoKit
import Foundation
import Security
import Testing

@Test func hostIdentityKeyProfileIsNonexportableAndPromptFree() {
    let profile = SecurityHostIdentityKeyCreationProfileV0.required()
    #expect(profile.protection == .afterFirstUnlockThisDeviceOnly)
    #expect(profile.requiresSecureEnclave)
    #expect(profile.requiresPrivateKeyUsage)
    #expect(!profile.requiresUserPresence)
    #expect(!profile.synchronizable)
    #expect(!profile.exportable)
}

@Test func hostIdentityKeyTagsAreExactBoundedAndRoleScoped() throws {
    let configuration = try SecurityHostIdentityKeyCustodyConfigurationV0(
        applicationTagPrefix: "example.maccompanion.agent"
    )
    let reference = UUID(
        uuidString: "018f9000-0000-7000-8000-000000000001"
    )!
    #expect(
        String(
            data: try configuration.applicationTag(reference: reference),
            encoding: .utf8
        ) == "example.maccompanion.agent.host."
            + "018f9000-0000-7000-8000-000000000001"
    )

    #expect(throws: SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration) {
        _ = try SecurityHostIdentityKeyCustodyConfigurationV0(
            applicationTagPrefix: "contains whitespace"
        )
    }
    #expect(throws: SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration) {
        _ = try SecurityHostIdentityKeyCustodyConfigurationV0(
            applicationTagPrefix: String(repeating: "a", count: 87)
        )
    }
}

@Test func hostIdentityCustodyRejectsForeignAndNoncanonicalTagsBeforeLookup()
    async throws
{
    let configuration = try SecurityHostIdentityKeyCustodyConfigurationV0(
        applicationTagPrefix: "example.maccompanion.agent"
    )
    let custody = SecurityHostIdentityKeyCustodyV0(
        configuration: configuration
    )
    let foreign = Data(
        "foreign.host.018f9000-0000-7000-8000-000000000001".utf8
    )
    let uppercase = Data(
        ("example.maccompanion.agent.host."
            + "018F9000-0000-7000-8000-000000000001").utf8
    )

    #expect(try await custody.availability(applicationTag: foreign) == .invalid)
    #expect(try await custody.availability(applicationTag: uppercase) == .invalid)
}

@Test func hostIdentityIssuerComposesStrictCertificateAndSecIdentityInMemory()
    throws
{
    let softwareKey = P256.Signing.PrivateKey()
    var creationError: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateWithData(
        softwareKey.x963Representation as CFData,
        [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecAttrKeySizeInBits: 256,
        ] as CFDictionary,
        &creationError
    ) else {
        let error = creationError?.takeRetainedValue()
        Issue.record("could not create ephemeral P-256 test key: \(String(describing: error))")
        return
    }
    let issuanceTime: Int64 = 1_724_000_000_000
    let issued = try SecurityHostIdentityKeyCustodyV0
        .assembleIssuedIdentity(
            privateKey: privateKey,
            applicationTag: Data("example.host.ephemeral".utf8),
            serialNumber: Data(repeating: 0x11, count: 16),
            issuanceTimeUnixMilliseconds: issuanceTime
        )
    let inspection = try HostIdentityCertificateInspectorV0.inspect(
        certificateDER: issued.certificateDER,
        wallNowUnixMilliseconds: issuanceTime
    )

    #expect(inspection.publicKeyX963 == issued.key.publicKeyX963)
    #expect(
        inspection.subjectPublicKeyInfoDER
            == issued.key.subjectPublicKeyInfoDER
    )
    #expect(
        issued.key.hostFingerprint
            == (try CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: inspection.subjectPublicKeyInfoDER
            ))
    )
    #expect(
        issued.validity
            == (try HostIdentityCertificateV0.validity(
                issuanceTimeUnixMilliseconds: issuanceTime
            ))
    )

    var copiedPrivateKey: SecKey?
    #expect(
        SecIdentityCopyPrivateKey(
            issued.listenerIdentity.copySecIdentity(),
            &copiedPrivateKey
        ) == errSecSuccess
    )
    #expect(copiedPrivateKey != nil)

    let loaded = try SecurityHostIdentityKeyCustodyV0.assembleLoadedIdentity(
        privateKey: privateKey, applicationTag: issued.key.applicationTag,
        certificateDER: issued.certificateDER, wallNowUnixMilliseconds: issuanceTime)
    #expect(loaded.key == issued.key)
    #expect(loaded.certificateDER == issued.certificateDER)
    #expect(loaded.validity == issued.validity)
    #expect(throws: SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid) {
        _ = try SecurityHostIdentityKeyCustodyV0.assembleLoadedIdentity(
            privateKey: privateKey, applicationTag: issued.key.applicationTag,
            certificateDER: Data([0]), wallNowUnixMilliseconds: issuanceTime)
    }
    #expect(throws: SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid) {
        _ = try SecurityHostIdentityKeyCustodyV0.assembleLoadedIdentity(
            privateKey: privateKey, applicationTag: issued.key.applicationTag,
            certificateDER: issued.certificateDER,
            wallNowUnixMilliseconds: issued.validity.notAfterUnixMilliseconds + 1)
    }
    let wrongSoftwareKey = P256.Signing.PrivateKey()
    let wrongKey = try #require(SecKeyCreateWithData(
        wrongSoftwareKey.x963Representation as CFData,
        [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
         kSecAttrKeySizeInBits: 256] as CFDictionary, nil))
    #expect(throws: SecurityHostIdentityKeyCustodyErrorV0.keyMismatch) {
        _ = try SecurityHostIdentityKeyCustodyV0.assembleLoadedIdentity(
            privateKey: wrongKey, applicationTag: issued.key.applicationTag,
            certificateDER: issued.certificateDER, wallNowUnixMilliseconds: issuanceTime)
    }
}
