import CompanionClientNetworkPlatform
import CompanionSecurity
import CryptoKit
import Foundation
import Security
import Testing

private let evaluatorIssuance: Int64 = 1_724_000_000_000
private let evaluatorSerial = Data((0x20..<0x30).map(UInt8.init))

private func evaluatorKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 2
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func evaluatorCertificate(
    changingProfile: Bool = false
) throws -> (trust: SecTrust, spki: Data) {
    let key = try evaluatorKey()
    var tbs = try HostIdentityCertificateV0.certificateSigningInput(
        publicKeyX963: key.publicKey.x963Representation,
        serialNumber: evaluatorSerial,
        issuanceTimeUnixMilliseconds: evaluatorIssuance
    )
    if changingProfile {
        let expectedName = Data("Mac Companion Host".utf8)
        guard let range = tbs.range(of: expectedName) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        tbs[range.lowerBound] ^= 1
    }
    let signature = try key.signature(for: tbs).derRepresentation
    let certificateDER = try HostIdentityCertificateV0
        .assembleSelfSignedCertificate(
            certificateSigningInput: tbs,
            publicKeyX963: key.publicKey.x963Representation,
            signatureDER: signature
        )
    guard let certificate = SecCertificateCreateWithData(
        nil,
        certificateDER as CFData
    ) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    var trust: SecTrust?
    let status = SecTrustCreateWithCertificates(
        certificate,
        SecPolicyCreateBasicX509(),
        &trust
    )
    guard status == errSecSuccess, let trust else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return (
        trust,
        try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
            publicKeyX963: key.publicKey.x963Representation
        )
    )
}

@Test func securityLeafEvaluatorReturnsStrictCanonicalSPKI() throws {
    let fixture = try evaluatorCertificate()
    let spki = try SecurityClientPinnedLeafEvaluatorV0
        .subjectPublicKeyInfoDER(
            from: fixture.trust,
            wallNowUnixMilliseconds: evaluatorIssuance
        )
    #expect(spki == fixture.spki)

    let closure = SecurityClientPinnedLeafEvaluatorV0.make(
        wallNowUnixMilliseconds: { evaluatorIssuance }
    )
    #expect(try closure(fixture.trust) == fixture.spki)
}

@Test func securityLeafEvaluatorRejectsExpiredAndResignedProfileChange() throws {
    let valid = try evaluatorCertificate()
    let validity = try HostIdentityCertificateV0.validity(
        issuanceTimeUnixMilliseconds: evaluatorIssuance
    )
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "hostCertificate"
    )) {
        _ = try SecurityClientPinnedLeafEvaluatorV0
            .subjectPublicKeyInfoDER(
                from: valid.trust,
                wallNowUnixMilliseconds:
                    validity.notAfterUnixMilliseconds + 1
            )
    }

    let changed = try evaluatorCertificate(changingProfile: true)
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "hostCertificate"
    )) {
        _ = try SecurityClientPinnedLeafEvaluatorV0
            .subjectPublicKeyInfoDER(
                from: changed.trust,
                wallNowUnixMilliseconds: evaluatorIssuance
            )
    }
}
