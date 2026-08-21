import Foundation

public struct HostIdentityCertificateInspectionV0: Equatable, Sendable {
    public let subjectPublicKeyInfoDER: Data
    public let publicKeyX963: Data
    public let serialNumber: Data
    public let validity: HostIdentityCertificateValidity
}

public enum HostIdentityCertificateInspectorV0 {
    public static let maximumCertificateBytes = 4_096

    /// Strictly accepts only the canonical certificate emitted by
    /// `HostIdentityCertificateV0`, verifies its self-signature, and checks its
    /// exact second-precision validity window against the supplied wall clock.
    public static func inspect(
        certificateDER: Data,
        wallNowUnixMilliseconds: Int64
    ) throws -> HostIdentityCertificateInspectionV0 {
        guard (1...maximumCertificateBytes).contains(certificateDER.count),
              wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds
                <= HostIdentityLifecycleV0.maximumSafeUnixMilliseconds else {
            throw CompanionSecurityError.invalidValue(field: "hostCertificate")
        }

        do {
            var certificateReader = StrictDERReaderV0(certificateDER)
            let certificate = try certificateReader.read(expectedTag: 0x30)
            guard certificateReader.isAtEnd else { throw StrictDERErrorV0.invalid }

            var outer = StrictDERReaderV0(certificate.content)
            let tbs = try outer.read(expectedTag: 0x30)
            _ = try outer.read(expectedTag: 0x30)
            let signatureBits = try outer.read(expectedTag: 0x03)
            guard outer.isAtEnd,
                  signatureBits.content.count > 1,
                  signatureBits.content.first == 0 else {
                throw StrictDERErrorV0.invalid
            }
            let signatureDER = signatureBits.content.dropFirstData()

            var tbsReader = StrictDERReaderV0(tbs.content)
            let version = try tbsReader.read(expectedTag: 0xa0)
            guard version.encoded == Data([0xa0, 0x03, 0x02, 0x01, 0x02]) else {
                throw StrictDERErrorV0.invalid
            }
            let serial = try canonicalSerial(
                try tbsReader.read(expectedTag: 0x02).content
            )
            _ = try tbsReader.read(expectedTag: 0x30)
            _ = try tbsReader.read(expectedTag: 0x30)
            let validityTLV = try tbsReader.read(expectedTag: 0x30)
            _ = try tbsReader.read(expectedTag: 0x30)
            let spkiTLV = try tbsReader.read(expectedTag: 0x30)
            _ = try tbsReader.read(expectedTag: 0xa3)
            guard tbsReader.isAtEnd else { throw StrictDERErrorV0.invalid }

            let validity = try parseValidity(validityTLV.content)
            let publicKeyX963 = try parsePublicKey(spkiTLV)
            let issuance = try exactIssuance(validity)
            let reconstructedTBS = try HostIdentityCertificateV0
                .certificateSigningInput(
                    publicKeyX963: publicKeyX963,
                    serialNumber: serial,
                    issuanceTimeUnixMilliseconds: issuance
                )
            guard reconstructedTBS == tbs.encoded else {
                throw StrictDERErrorV0.invalid
            }

            let reconstructedCertificate = try HostIdentityCertificateV0
                .assembleSelfSignedCertificate(
                    certificateSigningInput: reconstructedTBS,
                    publicKeyX963: publicKeyX963,
                    signatureDER: signatureDER
                )
            guard reconstructedCertificate == certificateDER,
                  wallNowUnixMilliseconds
                    >= validity.notBeforeUnixMilliseconds,
                  wallNowUnixMilliseconds
                    <= validity.notAfterUnixMilliseconds else {
                throw StrictDERErrorV0.invalid
            }
            return HostIdentityCertificateInspectionV0(
                subjectPublicKeyInfoDER: spkiTLV.encoded,
                publicKeyX963: publicKeyX963,
                serialNumber: serial,
                validity: validity
            )
        } catch let error as CompanionSecurityError {
            throw error
        } catch {
            throw CompanionSecurityError.invalidValue(field: "hostCertificate")
        }
    }

    private static func canonicalSerial(_ content: Data) throws -> Data {
        var bytes = Array(content)
        guard !bytes.isEmpty, bytes.count <= 17 else {
            throw StrictDERErrorV0.invalid
        }
        if bytes[0] == 0 {
            guard bytes.count > 1, bytes[1] >= 0x80 else {
                throw StrictDERErrorV0.invalid
            }
            bytes.removeFirst()
        } else if bytes[0] >= 0x80 {
            throw StrictDERErrorV0.invalid
        }
        guard bytes.count <= 16, bytes.contains(where: { $0 != 0 }) else {
            throw StrictDERErrorV0.invalid
        }
        return Data(repeating: 0, count: 16 - bytes.count) + Data(bytes)
    }

    private static func parseValidity(
        _ content: Data
    ) throws -> HostIdentityCertificateValidity {
        var reader = StrictDERReaderV0(content)
        let notBefore = try parseUTCTime(
            reader.read(expectedTag: 0x17).content
        )
        let notAfter = try parseUTCTime(
            reader.read(expectedTag: 0x17).content
        )
        guard reader.isAtEnd, notAfter > notBefore else {
            throw StrictDERErrorV0.invalid
        }
        return HostIdentityCertificateValidity(
            notBeforeUnixMilliseconds: notBefore,
            notAfterUnixMilliseconds: notAfter
        )
    }

    private static func exactIssuance(
        _ validity: HostIdentityCertificateValidity
    ) throws -> Int64 {
        let backdate = HostIdentityLifecycleV0.notBeforeBackdateMilliseconds
        guard validity.notBeforeUnixMilliseconds <= Int64.max - backdate else {
            throw StrictDERErrorV0.invalid
        }
        let issuance = validity.notBeforeUnixMilliseconds + backdate
        let expected = try HostIdentityCertificateV0.validity(
            issuanceTimeUnixMilliseconds: issuance
        )
        guard expected == validity else { throw StrictDERErrorV0.invalid }
        return issuance
    }

    private static func parsePublicKey(
        _ spki: StrictDERTLVV0
    ) throws -> Data {
        var reader = StrictDERReaderV0(spki.content)
        let algorithm = try reader.read(expectedTag: 0x30)
        let expectedAlgorithm = Data([
            0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
        ])
        let bits = try reader.read(expectedTag: 0x03)
        guard reader.isAtEnd,
              algorithm.encoded == expectedAlgorithm,
              bits.content.count == 66,
              bits.content.first == 0 else {
            throw StrictDERErrorV0.invalid
        }
        let publicKey = bits.content.dropFirstData()
        let reconstructed = try CompanionSecurityV0
            .p256SubjectPublicKeyInfoDER(publicKeyX963: publicKey)
        guard reconstructed == spki.encoded else {
            throw StrictDERErrorV0.invalid
        }
        return publicKey
    }

    private static func parseUTCTime(_ value: Data) throws -> Int64 {
        let bytes = Array(value)
        guard bytes.count == 13, bytes[12] == 0x5a,
              bytes[0..<12].allSatisfy({ (0x30...0x39).contains($0) }) else {
            throw StrictDERErrorV0.invalid
        }
        func number(_ start: Int) -> Int {
            Int(bytes[start] - 0x30) * 10 + Int(bytes[start + 1] - 0x30)
        }
        let shortYear = number(0)
        let year = shortYear >= 50 ? 1_900 + shortYear : 2_000 + shortYear
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            throw StrictDERErrorV0.invalid
        }
        calendar.timeZone = utc
        let components = DateComponents(
            calendar: calendar,
            timeZone: utc,
            year: year,
            month: number(2),
            day: number(4),
            hour: number(6),
            minute: number(8),
            second: number(10)
        )
        guard let date = calendar.date(from: components) else {
            throw StrictDERErrorV0.invalid
        }
        let checked = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard checked.year == year,
              checked.month == number(2),
              checked.day == number(4),
              checked.hour == number(6),
              checked.minute == number(8),
              checked.second == number(10) else {
            throw StrictDERErrorV0.invalid
        }
        return Int64(date.timeIntervalSince1970) * 1_000
    }
}

private enum StrictDERErrorV0: Error {
    case invalid
}

private struct StrictDERTLVV0 {
    let tag: UInt8
    let content: Data
    let encoded: Data
}

private struct StrictDERReaderV0 {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func read(expectedTag: UInt8) throws -> StrictDERTLVV0 {
        let value = try read()
        guard value.tag == expectedTag else { throw StrictDERErrorV0.invalid }
        return value
    }

    private mutating func read() throws -> StrictDERTLVV0 {
        let start = offset
        guard offset < bytes.count else { throw StrictDERErrorV0.invalid }
        let tag = bytes[offset]
        offset += 1
        guard tag & 0x1f != 0x1f, offset < bytes.count else {
            throw StrictDERErrorV0.invalid
        }
        let firstLength = bytes[offset]
        offset += 1
        let length: Int
        if firstLength < 0x80 {
            length = Int(firstLength)
        } else {
            let byteCount = Int(firstLength & 0x7f)
            guard (1...4).contains(byteCount),
                  offset <= bytes.count - byteCount,
                  bytes[offset] != 0 else {
                throw StrictDERErrorV0.invalid
            }
            var accumulated = 0
            for byte in bytes[offset..<(offset + byteCount)] {
                guard accumulated <= (Int.max - Int(byte)) / 256 else {
                    throw StrictDERErrorV0.invalid
                }
                accumulated = accumulated * 256 + Int(byte)
            }
            guard accumulated >= 0x80 else { throw StrictDERErrorV0.invalid }
            offset += byteCount
            length = accumulated
        }
        guard length >= 0, offset <= bytes.count - length else {
            throw StrictDERErrorV0.invalid
        }
        let contentStart = offset
        offset += length
        return StrictDERTLVV0(
            tag: tag,
            content: Data(bytes[contentStart..<offset]),
            encoded: Data(bytes[start..<offset])
        )
    }
}

private extension Data {
    func dropFirstData() -> Data {
        Data(dropFirst())
    }
}
