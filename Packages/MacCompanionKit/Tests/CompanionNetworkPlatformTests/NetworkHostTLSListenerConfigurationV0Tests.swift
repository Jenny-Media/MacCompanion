@testable import CompanionHostPlatform
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CryptoKit
import Foundation
import Network
import Security
import Testing

private let networkHostTLSIssuanceTime: Int64 = 1_724_000_000_000

private func networkHostTestIssuedIdentity() throws
    -> SecurityHostIssuedIdentityV0
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
        throw error ?? CocoaError(.featureUnsupported)
    }
    return try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(
        privateKey: privateKey,
        applicationTag: Data("example.host.ephemeral".utf8),
        serialNumber: Data(repeating: 0x22, count: 16),
        issuanceTimeUnixMilliseconds: networkHostTLSIssuanceTime
    )
}

@Test func hostTLSListenerConfigurationBindsExactIdentityAndTLS13Profile()
    throws
{
    let issued = try networkHostTestIssuedIdentity()
    let configuration = try NetworkHostTLSListenerConfigurationV0(
        issuedIdentity: issued,
        requiredHostFingerprint: issued.key.hostFingerprint,
        wallNowUnixMilliseconds: networkHostTLSIssuanceTime
    )

    #expect(configuration.hostFingerprint == issued.key.hostFingerprint)
    #expect(configuration.certificateDER == issued.certificateDER)
    #expect(
        configuration.facts
            == NetworkHostTLSListenerConfigurationFactsV0.required
    )
    #expect(configuration.facts.minimumTLSMajor == 1)
    #expect(configuration.facts.minimumTLSMinor == 3)
    #expect(configuration.facts.maximumTLSMajor == 1)
    #expect(configuration.facts.maximumTLSMinor == 3)
    #expect(!configuration.facts.resumptionEnabled)
    #expect(!configuration.facts.earlyDataEnabled)
    #expect(!configuration.facts.localEndpointReuse)
    let expectedHostHint = issued.key.hostFingerprint.prefix(8).map {
        String(format: "%02x", $0)
    }.joined()
    #expect(
        configuration.bonjourFacts.instanceName
            == "mac-\(expectedHostHint)"
    )
    #expect(configuration.bonjourFacts.serviceType == "_maccompanion._tcp")
    #expect(configuration.bonjourFacts.domain == "local.")
    #expect(configuration.bonjourFacts.protocolMajor == "0")
    #expect(configuration.bonjourFacts.hostHint.count == 16)

    _ = try configuration.makeUnstartedListenerOwner(port: 47_474)
    #expect(
        throws:
            NetworkHostTLSListenerConfigurationErrorV0.listenerAlreadyCreated
    ) {
        _ = try configuration.makeUnstartedListenerOwner(port: 47_474)
    }
}

@Test func hostTLSListenerConfigurationRejectsWrongPinAndExpiredLeaf()
    throws
{
    let issued = try networkHostTestIssuedIdentity()

    #expect(throws: NetworkHostTLSListenerConfigurationErrorV0.identityMismatch) {
        _ = try NetworkHostTLSListenerConfigurationV0(
            issuedIdentity: issued,
            requiredHostFingerprint: Data(repeating: 0, count: 32),
            wallNowUnixMilliseconds: networkHostTLSIssuanceTime
        )
    }
    #expect(throws: NetworkHostTLSListenerConfigurationErrorV0.certificateInvalid) {
        _ = try NetworkHostTLSListenerConfigurationV0(
            issuedIdentity: issued,
            requiredHostFingerprint: issued.key.hostFingerprint,
            wallNowUnixMilliseconds:
                issued.validity.notAfterUnixMilliseconds + 1
        )
    }
    #expect(throws: NetworkHostTLSListenerConfigurationErrorV0.invalidConfiguration) {
        _ = try NetworkHostTLSListenerConfigurationV0(
            issuedIdentity: issued,
            requiredHostFingerprint: Data(repeating: 0, count: 31),
            wallNowUnixMilliseconds: networkHostTLSIssuanceTime
        )
    }
}

#if DEBUG
@Test func loopbackTLSListenerKeepsProfileAndOneShotOwnership() throws {
    let issued = try networkHostTestIssuedIdentity()
    let configuration = try NetworkHostTLSListenerConfigurationV0(
        issuedIdentity: issued, requiredHostFingerprint: issued.key.hostFingerprint,
        wallNowUnixMilliseconds: networkHostTLSIssuanceTime)
    let (owner, port) = try configuration.makeUnstartedLoopbackListener()
    #expect((port() ?? 0) == 0, "Unstarted ephemeral listener must not have an assigned port")
    #expect(configuration.facts == .required)
    #expect(configuration.hostFingerprint == issued.key.hostFingerprint)
    #expect(throws: NetworkHostTLSListenerConfigurationErrorV0.listenerAlreadyCreated) {
        _ = try configuration.makeUnstartedListenerOwner(port: 47_474)
    }
    #expect(throws: NetworkHostTLSListenerConfigurationErrorV0.listenerAlreadyCreated) {
        _ = try configuration.makeUnstartedLoopbackListener()
    }
    owner.cancel()
}
#endif
