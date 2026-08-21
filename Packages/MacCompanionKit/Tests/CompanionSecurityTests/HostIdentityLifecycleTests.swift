import CompanionSecurity
import CompanionTestSupport
import Foundation
import Testing

private struct HostIdentityFixture: Decodable {
    let publicKeyX963Base64URL: String
    let subjectPublicKeyInfoDERHex: String
    let hostFingerprintSHA256Hex: String
}

private func hostIdentityFixture() throws -> HostIdentityFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/tls-spki-v0.1.json")
    return try JSONDecoder().decode(
        HostIdentityFixture.self,
        from: Data(contentsOf: url)
    )
}

private func hostIdentityData(hex: String) throws -> Data {
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

private func hostPublicKey() throws -> Data {
    var text = try hostIdentityFixture().publicKeyX963Base64URL
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    text.append(String(repeating: "=", count: (4 - text.count % 4) % 4))
    guard let data = Data(base64Encoded: text) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return data
}

private func hostSPKI() throws -> Data {
    try hostIdentityData(hex: hostIdentityFixture().subjectPublicKeyInfoDERHex)
}

private let hostNow: Int64 = 1_724_000_000_000

@Test func exactP256SPKIAndFingerprintMatchAuthoritativeFixture() throws {
    let fixture = try hostIdentityFixture()
    let expectedSPKI = try hostIdentityData(hex: fixture.subjectPublicKeyInfoDERHex)
    let expectedFingerprint = try hostIdentityData(hex: fixture.hostFingerprintSHA256Hex)
    #expect(try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostPublicKey()
    ) == expectedSPKI)
    #expect(try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: expectedSPKI
    ) == expectedFingerprint)
    #expect(try CompanionSecurityV0.hostFingerprint(
        publicKeyX963: hostPublicKey()
    ) == expectedFingerprint)
}

@Test func freshInstallAndInterruptedBootstrapHaveDistinctActions() throws {
    let fresh = HostIdentityInventory(
        establishedIdentity: false,
        key: .missing,
        certificate: .missing
    )
    #expect(try HostIdentityLifecycleV0.evaluate(
        fresh,
        wallNowUnixMilliseconds: hostNow
    ) == .bootstrapNewIdentity)

    let continuation = HostIdentityInventory(
        establishedIdentity: false,
        key: .available(publicKeyX963: try hostPublicKey()),
        certificate: .missing
    )
    guard case let .issueCertificate(_, reason) = try HostIdentityLifecycleV0.evaluate(
        continuation,
        wallNowUnixMilliseconds: hostNow
    ) else {
        Issue.record("expected certificate issuance")
        return
    }
    #expect(reason == .bootstrapContinuation)
}

@Test func establishedKeyLossRequiresLocalRecoveryAndNeverSilentRotation() throws {
    for key: HostIdentityKeyAvailability in [.missing, .invalid] {
        let inventory = HostIdentityInventory(
            establishedIdentity: true,
            key: key,
            certificate: .missing
        )
        guard case .requireLocalRecovery = try HostIdentityLifecycleV0.evaluate(
            inventory,
            wallNowUnixMilliseconds: hostNow
        ) else {
            Issue.record("established key loss must require local recovery")
            return
        }
    }
    #expect(try HostIdentityLifecycleV0.evaluate(
        HostIdentityInventory(
            establishedIdentity: true,
            key: .unavailableBeforeFirstUnlock,
            certificate: .missing
        ),
        wallNowUnixMilliseconds: hostNow
    ) == .waitForFirstUnlock)
}

@Test func missingOrMismatchedCertificateRenewsUnderTheSamePin() throws {
    let publicKey = try hostPublicKey()
    let expectedPin = try CompanionSecurityV0.hostFingerprint(publicKeyX963: publicKey)
    for certificate: HostIdentityCertificateAvailability in [
        .missing,
        .invalid,
        .available(
            subjectPublicKeyInfoDER: Data(repeating: 7, count: 91),
            notBeforeUnixMilliseconds: hostNow - 1_000,
            notAfterUnixMilliseconds: hostNow + 1_000
        ),
    ] {
        let disposition = try HostIdentityLifecycleV0.evaluate(
            HostIdentityInventory(
                establishedIdentity: true,
                key: .available(publicKeyX963: publicKey),
                certificate: certificate
            ),
            wallNowUnixMilliseconds: hostNow
        )
        guard case let .issueCertificate(pin, _) = disposition else {
            Issue.record("expected same-key certificate issuance")
            return
        }
        #expect(pin == expectedPin)
    }
}

@Test func validCertificateServesAndRenewalWindowDoesNotChangePin() throws {
    let publicKey = try hostPublicKey()
    let fingerprint = try CompanionSecurityV0.hostFingerprint(publicKeyX963: publicKey)
    let farExpiry = hostNow + HostIdentityLifecycleV0.renewalWindowMilliseconds + 1
    let current = HostIdentityInventory(
        establishedIdentity: true,
        key: .available(publicKeyX963: publicKey),
        certificate: .available(
            subjectPublicKeyInfoDER: try hostSPKI(),
            notBeforeUnixMilliseconds: hostNow - 1_000,
            notAfterUnixMilliseconds: farExpiry
        )
    )
    #expect(try HostIdentityLifecycleV0.evaluate(
        current,
        wallNowUnixMilliseconds: hostNow
    ) == .ready(
        hostFingerprint: fingerprint,
        certificateNotAfterUnixMilliseconds: farExpiry,
        renewalRecommended: false
    ))

    let due = HostIdentityInventory(
        establishedIdentity: true,
        key: current.key,
        certificate: .available(
            subjectPublicKeyInfoDER: try hostSPKI(),
            notBeforeUnixMilliseconds: hostNow - 1_000,
            notAfterUnixMilliseconds: hostNow
                + HostIdentityLifecycleV0.renewalWindowMilliseconds
        )
    )
    guard case let .ready(duePin, _, renewal) = try HostIdentityLifecycleV0.evaluate(
        due,
        wallNowUnixMilliseconds: hostNow
    ) else {
        Issue.record("expected renewable ready identity")
        return
    }
    #expect(duePin == fingerprint)
    #expect(renewal)
}

@Test func expiredFutureAndOutOfProfileCertificatesCannotServe() throws {
    let publicKey = try hostPublicKey()
    let spki = try hostSPKI()
    let certificates: [HostIdentityCertificateAvailability] = [
        .available(
            subjectPublicKeyInfoDER: spki,
            notBeforeUnixMilliseconds: hostNow - 2_000,
            notAfterUnixMilliseconds: hostNow
        ),
        .available(
            subjectPublicKeyInfoDER: spki,
            notBeforeUnixMilliseconds: hostNow + 1,
            notAfterUnixMilliseconds: hostNow + 2
        ),
        .available(
            subjectPublicKeyInfoDER: spki,
            notBeforeUnixMilliseconds: hostNow - 1,
            notAfterUnixMilliseconds: hostNow
                + HostIdentityLifecycleV0.maximumCertificateIntervalMilliseconds + 1
        ),
    ]
    for certificate in certificates {
        guard case .issueCertificate = try HostIdentityLifecycleV0.evaluate(
            HostIdentityInventory(
                establishedIdentity: true,
                key: .available(publicKeyX963: publicKey),
                certificate: certificate
            ),
            wallNowUnixMilliseconds: hostNow
        ) else {
            Issue.record("noncurrent certificate must not serve")
            return
        }
    }
}
