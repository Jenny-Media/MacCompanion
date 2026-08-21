import CompanionSecurity
import CompanionTestSupport
import CryptoKit
import Foundation
import Security
import Testing

private let certificateIssuance: Int64 = 1_724_000_000_000
private let certificateSerial = Data((0x00..<0x10).map(UInt8.init))

private struct HostCertificateFixture: Decodable {
    let certificateIssuanceTimeUnixMilliseconds: Int64
    let certificateSerialHex: String
    let certificateSigningInputDERHex: String
    let certificateSigningInputSHA256Hex: String
}

private func certificateFixture() throws -> HostCertificateFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/tls-spki-v0.1.json")
    return try JSONDecoder().decode(
        HostCertificateFixture.self,
        from: Data(contentsOf: url)
    )
}

private func certificateData(hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
    var result = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let end = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<end], radix: 16) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        result.append(byte)
        index = end
    }
    return result
}

private func certificateKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 1
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func assembledCertificate() throws -> (tbs: Data, der: Data) {
    let key = try certificateKey()
    let tbs = try HostIdentityCertificateV0.certificateSigningInput(
        publicKeyX963: key.publicKey.x963Representation,
        serialNumber: certificateSerial,
        issuanceTimeUnixMilliseconds: certificateIssuance
    )
    let signature = try key.signature(for: tbs).derRepresentation
    return (
        tbs,
        try HostIdentityCertificateV0.assembleSelfSignedCertificate(
            certificateSigningInput: tbs,
            publicKeyX963: key.publicKey.x963Representation,
            signatureDER: signature
        )
    )
}

@Test func certificateSigningInputMatchesIndependentGoldenDER() throws {
    let fixture = try certificateFixture()
    let tbs = try HostIdentityCertificateV0.certificateSigningInput(
        publicKeyX963: certificateKey().publicKey.x963Representation,
        serialNumber: certificateData(hex: fixture.certificateSerialHex),
        issuanceTimeUnixMilliseconds: fixture.certificateIssuanceTimeUnixMilliseconds
    )
    #expect(tbs == (try certificateData(hex: fixture.certificateSigningInputDERHex)))
    #expect(Data(SHA256.hash(data: tbs)) == (try certificateData(
        hex: fixture.certificateSigningInputSHA256Hex
    )))
}

@Test func selfSignedHostCertificateParsesAndCarriesExactKey() throws {
    let built = try assembledCertificate()
    guard let certificate = SecCertificateCreateWithData(nil, built.der as CFData) else {
        Issue.record("Security.framework rejected certificate DER")
        return
    }
    guard let extractedKey = SecCertificateCopyKey(certificate) else {
        Issue.record("certificate has no public key")
        return
    }
    var keyError: Unmanaged<CFError>?
    guard let external = SecKeyCopyExternalRepresentation(extractedKey, &keyError) else {
        throw keyError!.takeRetainedValue()
    }
    #expect((external as Data) == (try certificateKey()).publicKey.x963Representation)
}

@Test func certificateAssemblyRejectsTamperedOrMalformedSignatures() throws {
    let key = try certificateKey()
    let tbs = try HostIdentityCertificateV0.certificateSigningInput(
        publicKeyX963: key.publicKey.x963Representation,
        serialNumber: certificateSerial,
        issuanceTimeUnixMilliseconds: certificateIssuance
    )
    var signature = try key.signature(for: tbs).derRepresentation
    signature[signature.index(before: signature.endIndex)] ^= 1
    #expect(throws: CompanionSecurityError.invalidSignature) {
        try HostIdentityCertificateV0.assembleSelfSignedCertificate(
            certificateSigningInput: tbs,
            publicKeyX963: key.publicKey.x963Representation,
            signatureDER: signature
        )
    }
    #expect(throws: CompanionSecurityError.invalidSignature) {
        try HostIdentityCertificateV0.assembleSelfSignedCertificate(
            certificateSigningInput: tbs,
            publicKeyX963: key.publicKey.x963Representation,
            signatureDER: Data([0x30, 0x00])
        )
    }
}

@Test func certificateProfileRejectsZeroSerialInvalidKeyAndUTCTimeOverflow() throws {
    let key = try certificateKey()
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "certificateSerialNumber"
    )) {
        try HostIdentityCertificateV0.certificateSigningInput(
            publicKeyX963: key.publicKey.x963Representation,
            serialNumber: Data(repeating: 0, count: 16),
            issuanceTimeUnixMilliseconds: certificateIssuance
        )
    }
    #expect(throws: CompanionSecurityError.invalidPublicKey) {
        try HostIdentityCertificateV0.certificateSigningInput(
            publicKeyX963: Data(repeating: 0, count: 65),
            serialNumber: certificateSerial,
            issuanceTimeUnixMilliseconds: certificateIssuance
        )
    }
    #expect(throws: CompanionSecurityError.invalidValue(field: "certificateUTCTime")) {
        try HostIdentityCertificateV0.validity(
            issuanceTimeUnixMilliseconds: 2_524_608_000_000
        )
    }
}

@Test func strictCertificateInspectorReturnsOnlyCanonicalCurrentProfile() throws {
    let built = try assembledCertificate()
    let inspected = try HostIdentityCertificateInspectorV0.inspect(
        certificateDER: built.der,
        wallNowUnixMilliseconds: certificateIssuance
    )
    let key = try certificateKey()
    let expectedSPKI = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let expectedValidity = try HostIdentityCertificateV0.validity(
        issuanceTimeUnixMilliseconds: certificateIssuance
    )
    #expect(inspected.subjectPublicKeyInfoDER == expectedSPKI)
    #expect(inspected.publicKeyX963 == key.publicKey.x963Representation)
    #expect(inspected.serialNumber == certificateSerial)
    #expect(inspected.validity == expectedValidity)
}

@Test func strictCertificateInspectorRejectsResignedProfileChanges() throws {
    let key = try certificateKey()
    var changedTBS = try assembledCertificate().tbs
    let name = Data("Mac Companion Host".utf8)
    guard let range = changedTBS.range(of: name) else {
        Issue.record("fixture TBS has no expected subject name")
        return
    }
    changedTBS[range.lowerBound] ^= 1
    let signature = try key.signature(for: changedTBS).derRepresentation
    let changedCertificate = try HostIdentityCertificateV0
        .assembleSelfSignedCertificate(
            certificateSigningInput: changedTBS,
            publicKeyX963: key.publicKey.x963Representation,
            signatureDER: signature
        )
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "hostCertificate"
    )) {
        _ = try HostIdentityCertificateInspectorV0.inspect(
            certificateDER: changedCertificate,
            wallNowUnixMilliseconds: certificateIssuance
        )
    }
}

@Test func strictCertificateInspectorRejectsInvalidTimeAndDERBoundary() throws {
    let built = try assembledCertificate()
    let validity = try HostIdentityCertificateV0.validity(
        issuanceTimeUnixMilliseconds: certificateIssuance
    )
    for now in [
        validity.notBeforeUnixMilliseconds - 1,
        validity.notAfterUnixMilliseconds + 1,
    ] {
        #expect(throws: CompanionSecurityError.invalidValue(
            field: "hostCertificate"
        )) {
            _ = try HostIdentityCertificateInspectorV0.inspect(
                certificateDER: built.der,
                wallNowUnixMilliseconds: now
            )
        }
    }
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "hostCertificate"
    )) {
        _ = try HostIdentityCertificateInspectorV0.inspect(
            certificateDER: built.der + Data([0]),
            wallNowUnixMilliseconds: certificateIssuance
        )
    }
}
