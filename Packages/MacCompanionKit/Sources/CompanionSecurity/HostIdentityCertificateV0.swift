import CryptoKit
import Foundation

public struct HostIdentityCertificateValidity: Equatable, Sendable {
    public let notBeforeUnixMilliseconds: Int64
    public let notAfterUnixMilliseconds: Int64
}

public enum HostIdentityCertificateV0 {
    public static func validity(
        issuanceTimeUnixMilliseconds: Int64
    ) throws -> HostIdentityCertificateValidity {
        guard issuanceTimeUnixMilliseconds
                >= HostIdentityLifecycleV0.notBeforeBackdateMilliseconds,
              issuanceTimeUnixMilliseconds
                <= HostIdentityLifecycleV0.maximumSafeUnixMilliseconds
                    - HostIdentityLifecycleV0.certificateLifetimeMilliseconds else {
            throw CompanionSecurityError.invalidValue(field: "certificateIssuanceTime")
        }
        let value = HostIdentityCertificateValidity(
            notBeforeUnixMilliseconds: issuanceTimeUnixMilliseconds
                - HostIdentityLifecycleV0.notBeforeBackdateMilliseconds,
            notAfterUnixMilliseconds: issuanceTimeUnixMilliseconds
                + HostIdentityLifecycleV0.certificateLifetimeMilliseconds
        )
        _ = try utcTime(value.notBeforeUnixMilliseconds)
        _ = try utcTime(value.notAfterUnixMilliseconds)
        return value
    }

    public static func certificateSigningInput(
        publicKeyX963: Data,
        serialNumber: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) throws -> Data {
        guard serialNumber.count == 16, serialNumber.contains(where: { $0 != 0 }) else {
            throw CompanionSecurityError.invalidValue(field: "certificateSerialNumber")
        }
        let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
            publicKeyX963: publicKeyX963
        )
        let validity = try validity(
            issuanceTimeUnixMilliseconds: issuanceTimeUnixMilliseconds
        )
        let name = distinguishedName()
        let extensions = derExplicit(
            tag: 3,
            content: derSequence([
                basicConstraintsExtension(),
                keyUsageExtension(),
                extendedKeyUsageExtension(),
            ])
        )
        return derSequence([
            derExplicit(tag: 0, content: derInteger(Data([2]))),
            derInteger(serialNumber),
            ecdsaWithSHA256AlgorithmIdentifier(),
            name,
            derSequence([
                derTLV(tag: 0x17, content: try utcTime(validity.notBeforeUnixMilliseconds)),
                derTLV(tag: 0x17, content: try utcTime(validity.notAfterUnixMilliseconds)),
            ]),
            name,
            spki,
            extensions,
        ])
    }

    public static func assembleSelfSignedCertificate(
        certificateSigningInput: Data,
        publicKeyX963: Data,
        signatureDER: Data
    ) throws -> Data {
        guard !certificateSigningInput.isEmpty,
              certificateSigningInput.count <= 4_096,
              !signatureDER.isEmpty,
              signatureDER.count <= 80 else {
            throw CompanionSecurityError.invalidValue(field: "certificateSignature")
        }
        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963)
            signature = try P256.Signing.ECDSASignature(derRepresentation: signatureDER)
        } catch {
            throw CompanionSecurityError.invalidSignature
        }
        guard publicKey.isValidSignature(signature, for: certificateSigningInput) else {
            throw CompanionSecurityError.invalidSignature
        }
        return derSequence([
            certificateSigningInput,
            ecdsaWithSHA256AlgorithmIdentifier(),
            derBitString(signatureDER),
        ])
    }

    private static func distinguishedName() -> Data {
        derSequence([
            derSet([
                derSequence([
                    derOID([0x55, 0x04, 0x03]),
                    derTLV(tag: 0x0c, content: Data("Mac Companion Host".utf8)),
                ]),
            ]),
        ])
    }

    private static func ecdsaWithSHA256AlgorithmIdentifier() -> Data {
        derSequence([derOID([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])])
    }

    private static func basicConstraintsExtension() -> Data {
        derSequence([
            derOID([0x55, 0x1d, 0x13]),
            derBoolean(true),
            derOctetString(derSequence([])),
        ])
    }

    private static func keyUsageExtension() -> Data {
        derSequence([
            derOID([0x55, 0x1d, 0x0f]),
            derBoolean(true),
            derOctetString(derTLV(tag: 0x03, content: Data([0x07, 0x80]))),
        ])
    }

    private static func extendedKeyUsageExtension() -> Data {
        derSequence([
            derOID([0x55, 0x1d, 0x25]),
            derOctetString(derSequence([
                derOID([0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]),
            ])),
        ])
    }

    private static func utcTime(_ milliseconds: Int64) throws -> Data {
        let seconds = milliseconds / 1_000
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: date)
        guard (1950...2049).contains(year) else {
            throw CompanionSecurityError.invalidValue(field: "certificateUTCTime")
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return Data(formatter.string(from: date).utf8)
    }

    private static func derInteger(_ bytes: Data) -> Data {
        var value = bytes
        while value.count > 1, value.first == 0, value[value.index(after: value.startIndex)] < 0x80 {
            value.removeFirst()
        }
        if value.first.map({ $0 >= 0x80 }) == true {
            value.insert(0, at: value.startIndex)
        }
        return derTLV(tag: 0x02, content: value)
    }

    private static func derBoolean(_ value: Bool) -> Data {
        derTLV(tag: 0x01, content: Data([value ? 0xff : 0x00]))
    }

    private static func derBitString(_ bytes: Data) -> Data {
        derTLV(tag: 0x03, content: Data([0]) + bytes)
    }

    private static func derOctetString(_ bytes: Data) -> Data {
        derTLV(tag: 0x04, content: bytes)
    }

    private static func derOID(_ content: [UInt8]) -> Data {
        derTLV(tag: 0x06, content: Data(content))
    }

    private static func derSequence(_ values: [Data]) -> Data {
        derTLV(tag: 0x30, content: values.reduce(into: Data(), { $0.append($1) }))
    }

    private static func derSet(_ values: [Data]) -> Data {
        derTLV(tag: 0x31, content: values.sorted(by: { $0.lexicographicallyPrecedes($1) })
            .reduce(into: Data(), { $0.append($1) }))
    }

    private static func derExplicit(tag: UInt8, content: Data) -> Data {
        derTLV(tag: 0xa0 | tag, content: content)
    }

    private static func derTLV(tag: UInt8, content: Data) -> Data {
        Data([tag]) + derLength(content.count) + content
    }

    private static func derLength(_ count: Int) -> Data {
        precondition(count >= 0)
        if count < 0x80 { return Data([UInt8(count)]) }
        var value = count
        var bytes = [UInt8]()
        while value > 0 {
            bytes.append(UInt8(value & 0xff))
            value >>= 8
        }
        bytes.reverse()
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
